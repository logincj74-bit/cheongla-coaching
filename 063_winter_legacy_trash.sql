-- Preserve imported records while allowing principals to delete and restore them.
alter table cheongla_private.winter_legacy_records
 add column if not exists deleted_at timestamptz,
 add column if not exists deleted_by uuid;

create or replace function public.cheongla_trash_winter_legacy(
 target_source_id text, restore_record boolean, expected_deleted_at timestamptz
) returns void language plpgsql security definer set search_path='' as $$
declare r cheongla_private.winter_legacy_records%rowtype;
begin
 if not cheongla_private.is_principal() then
  raise exception '이전 기록의 삭제·복구는 원장만 가능합니다.' using errcode='42501';
 end if;
 if restore_record is null then raise exception '처리 방법을 확인해 주세요.'; end if;
 select * into r from cheongla_private.winter_legacy_records where source_id=target_source_id for update;
 if not found then raise exception '이전 접수 내역이 없습니다.'; end if;
 if r.deleted_at is distinct from expected_deleted_at then
  raise exception '다른 관리자가 변경했습니다. 새로고침해 주세요.';
 end if;
 if restore_record and r.deleted_at is not null then
  update cheongla_private.winter_legacy_records set deleted_at=null,deleted_by=null where source_id=r.source_id;
 elsif not restore_record and r.deleted_at is null then
  update cheongla_private.winter_legacy_records set deleted_at=clock_timestamp(),deleted_by=auth.uid() where source_id=r.source_id;
 else raise exception '휴지통 상태를 확인해 주세요.';
 end if;
end;
$$;
revoke all on function public.cheongla_trash_winter_legacy(text,boolean,timestamptz) from public,anon;
grant execute on function public.cheongla_trash_winter_legacy(text,boolean,timestamptz) to authenticated;

create or replace function public.cheongla_winter_booking_list()
 returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_winter() then
  raise exception '원장·실장만 상담·예약을 관리할 수 있습니다.' using errcode='42501';
 end if;
 return jsonb_build_object(
  'items',(select coalesce(jsonb_agg(to_jsonb(r)-'receipt_hash'-'request_id' order by r.created_at desc),'[]') from cheongla_private.winter_bookings r where r.archived_at is null or cheongla_private.is_principal()),
  'legacy',(select coalesce(jsonb_agg(record||jsonb_build_object('source_id',source_id)),'[]') from cheongla_private.winter_legacy_records where deleted_at is null),
  'legacy_trash',case when cheongla_private.is_principal() then
   (select coalesce(jsonb_agg(record||jsonb_build_object('source_id',source_id,'deleted_at',deleted_at) order by deleted_at desc),'[]') from cheongla_private.winter_legacy_records where deleted_at is not null)
   else '[]'::jsonb end);
end;
$$;
revoke all on function public.cheongla_winter_booking_list() from public,anon;
grant execute on function public.cheongla_winter_booking_list() to authenticated;
