-- Record only the actor, time and count; purged member data is not copied here.
create table cheongla_private.winter_legacy_purges(
 id bigint generated always as identity primary key,
 actor_id uuid not null,
 deleted_count integer not null check(deleted_count>0),
 created_at timestamptz not null default clock_timestamp()
);
alter table cheongla_private.winter_legacy_purges enable row level security;
revoke all on cheongla_private.winter_legacy_purges from public,anon,authenticated;

create or replace function public.cheongla_empty_winter_legacy_trash(expected_records jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare expected jsonb;actual jsonb;removed integer;
begin
 if not cheongla_private.is_principal() then
  raise exception '휴지통 비우기는 원장만 가능합니다.' using errcode='42501';
 end if;
 if expected_records is null or jsonb_typeof(expected_records)<>'array' then
  raise exception '휴지통 목록을 새로고침해 주세요.';
 end if;
 if jsonb_array_length(expected_records)=0 then return 0; end if;
 if exists(select 1 from jsonb_to_recordset(expected_records)as r(source_id text,deleted_at timestamptz)where source_id is null or deleted_at is null)
 or (select count(*)<>count(distinct source_id)from jsonb_to_recordset(expected_records)as r(source_id text,deleted_at timestamptz)) then
  raise exception '휴지통 목록을 새로고침해 주세요.';
 end if;
 select jsonb_agg(jsonb_build_object('source_id',source_id,'deleted_at',deleted_at)order by source_id)
 into expected from jsonb_to_recordset(expected_records)as r(source_id text,deleted_at timestamptz);
 -- Lock in a deterministic order; a concurrent restore must finish before validation.
 perform r.source_id from cheongla_private.winter_legacy_records r
 join jsonb_to_recordset(expected_records)as x(source_id text,deleted_at timestamptz)on x.source_id=r.source_id
 order by r.source_id for update of r;
 select coalesce(jsonb_agg(jsonb_build_object('source_id',source_id,'deleted_at',deleted_at)order by source_id),'[]')
 into actual from cheongla_private.winter_legacy_records where deleted_at is not null;
 if actual is distinct from expected then
  raise exception '휴지통 내용이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';
 end if;
 -- Match only the confirmed versions; newly deleted records are never swept in.
 delete from cheongla_private.winter_legacy_records r
 using jsonb_to_recordset(expected_records)as x(source_id text,deleted_at timestamptz)
 where r.source_id=x.source_id and r.deleted_at=x.deleted_at;
 get diagnostics removed=row_count;
 if removed<>jsonb_array_length(expected_records) then
  raise exception '휴지통 내용이 변경되었습니다. 새로고침해 주세요.';
 end if;
 insert into cheongla_private.winter_legacy_purges(actor_id,deleted_count)values(auth.uid(),removed);
 return removed;
end;
$$;
revoke all on function public.cheongla_empty_winter_legacy_trash(jsonb) from public,anon;
grant execute on function public.cheongla_empty_winter_legacy_trash(jsonb) to authenticated;
notify pgrst,'reload schema';
