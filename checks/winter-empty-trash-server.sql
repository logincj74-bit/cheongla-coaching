-- The transaction temporarily hides existing trash from this test's snapshot.
-- Only synthetic records are purged; all changes, including the audit, roll back.
begin;
update cheongla_private.winter_legacy_records set deleted_at=null where deleted_at is not null;
do $$
declare principal uuid;staff uuid;a text:='purge-a-'||gen_random_uuid();b text:='purge-b-'||gen_random_uuid();live text:='purge-active-'||gen_random_uuid();snapshot jsonb;oldstamp timestamptz:=clock_timestamp();removed integer;
begin
 select id into principal from public.cheongla_profiles where role in('owner','english_director','math_director')and approval_status='approved'and membership_state='active'limit 1;
 select id into staff from public.cheongla_profiles where role='manager'and approval_status='approved'and membership_state='active'limit 1;
 assert principal is not null and staff is not null,'fixture staff missing';
 assert not has_function_privilege('anon','public.cheongla_empty_winter_legacy_trash(jsonb)','execute'),'anonymous privilege';
 assert has_function_privilege('authenticated','public.cheongla_empty_winter_legacy_trash(jsonb)','execute'),'member RPC privilege missing';
 insert into cheongla_private.winter_legacy_records(source_id,record,deleted_at)values(a,'{"student_name":"검증 A"}',oldstamp),(b,'{"student_name":"검증 B"}',oldstamp),(live,'{"deleted_at":"2026-10-21T00:00:00Z"}',null);
 snapshot:=jsonb_build_array(jsonb_build_object('source_id',a,'deleted_at',oldstamp),jsonb_build_object('source_id',b,'deleted_at',oldstamp));
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.cheongla_empty_winter_legacy_trash(snapshot);raise exception 'anonymous accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',staff::text,true);
 begin perform public.cheongla_empty_winter_legacy_trash(snapshot);raise exception 'manager accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.cheongla_empty_winter_legacy_trash(snapshot);raise exception 'nonmember accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',principal::text,true);
 begin perform public.cheongla_empty_winter_legacy_trash(snapshot||snapshot);raise exception 'duplicate snapshot accepted';exception when raise_exception then if sqlerrm='duplicate snapshot accepted'then raise;end if;end;
 update cheongla_private.winter_legacy_records set deleted_at=oldstamp+interval'1 second'where source_id=a;
 begin perform public.cheongla_empty_winter_legacy_trash(snapshot);raise exception 'stale snapshot accepted';exception when raise_exception then if sqlerrm='stale snapshot accepted'then raise;end if;end;
 assert exists(select 1 from cheongla_private.winter_legacy_records where source_id=b),'stale attempt partially purged';
 update cheongla_private.winter_legacy_records set deleted_at=oldstamp where source_id=a;
 update cheongla_private.winter_legacy_records set deleted_at=oldstamp where source_id=live;
 begin perform public.cheongla_empty_winter_legacy_trash(snapshot);raise exception 'unconfirmed new trash accepted';exception when raise_exception then if sqlerrm='unconfirmed new trash accepted'then raise;end if;end;
 update cheongla_private.winter_legacy_records set deleted_at=null where source_id=live;
 removed:=public.cheongla_empty_winter_legacy_trash(snapshot);
 assert removed=2,'wrong count';
 assert not exists(select 1 from cheongla_private.winter_legacy_records where source_id in(a,b)),'fixture trash survived';
 assert exists(select 1 from cheongla_private.winter_legacy_records where source_id=live),'active historical record purged';
 assert exists(select 1 from cheongla_private.winter_legacy_purges where actor_id=principal and deleted_count=2),'audit missing';
 assert public.cheongla_empty_winter_legacy_trash('[]')=0,'empty list not handled';
 begin perform public.cheongla_empty_winter_legacy_trash(snapshot);raise exception 'replayed purge accepted';exception when raise_exception then if sqlerrm='replayed purge accepted'then raise;end if;end;
end $$;
rollback;
select 'PASS: principal-only permanent purge, matching counts/audit, active record preservation, stale/new/duplicate/replayed snapshot rejection; all tests rolled back' as result,count(*) as existing_records,count(*)filter(where deleted_at is not null)as trash_records from cheongla_private.winter_legacy_records;
