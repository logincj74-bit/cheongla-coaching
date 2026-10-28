-- Only a synthetic record is changed; the transaction always rolls back.
begin;
do $$
declare principal_id uuid; manager_id uuid; fixture text:='test-winter-trash-'||gen_random_uuid(); stamp timestamptz; items jsonb; payload jsonb:='{"student_name":"삭제 복구 검증","amount":100000,"deleted_at":"2026-10-21T01:00:00Z"}'::jsonb;
begin
 select id into principal_id from public.cheongla_profiles where role in ('owner','english_director','math_director') and approval_status='approved' and membership_state='active' limit 1;
 select id into manager_id from public.cheongla_profiles where role='manager' and approval_status='approved' and membership_state='active' limit 1;
 assert principal_id is not null,'principal fixture identity missing';
 assert not has_function_privilege('anon','public.cheongla_trash_winter_legacy(text,boolean,timestamptz)','EXECUTE'),'anonymous execute';
 assert has_function_privilege('authenticated','public.cheongla_trash_winter_legacy(text,boolean,timestamptz)','EXECUTE'),'authenticated execute missing';
 insert into cheongla_private.winter_legacy_records(source_id,record)values(fixture,payload);
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.cheongla_trash_winter_legacy(fixture,false,null);raise exception 'anonymous accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.cheongla_trash_winter_legacy(fixture,false,null);raise exception 'nonmember accepted';exception when insufficient_privilege then null;end;
 if manager_id is not null then
  perform set_config('request.jwt.claim.sub',manager_id::text,true);
  begin perform public.cheongla_trash_winter_legacy(fixture,false,null);raise exception 'manager accepted';exception when insufficient_privilege then null;end;
 end if;
 perform set_config('request.jwt.claim.sub',principal_id::text,true);
 items:=public.cheongla_winter_booking_list();
 assert exists(select 1 from jsonb_array_elements(items->'legacy')r where r->>'source_id'=fixture),'active fixture missing';
 assert (select r->'deleted_at'='null'::jsonb from jsonb_array_elements(items->'legacy')r where r->>'source_id'=fixture),'historical deletion date leaked into current trash version';
 perform public.cheongla_trash_winter_legacy(fixture,false,(select (r->>'deleted_at')::timestamptz from jsonb_array_elements(items->'legacy')r where r->>'source_id'=fixture));
 select deleted_at into stamp from cheongla_private.winter_legacy_records where source_id=fixture;
 assert stamp is not null,'archive did not persist';
 assert (select deleted_by=principal_id and record=payload from cheongla_private.winter_legacy_records where source_id=fixture),'original payload changed';
 items:=public.cheongla_winter_booking_list();
 assert not exists(select 1 from jsonb_array_elements(items->'legacy')r where r->>'source_id'=fixture),'archive still active';
 assert exists(select 1 from jsonb_array_elements(items->'legacy_trash')r where r->>'source_id'=fixture),'archive not in trash';
 begin perform public.cheongla_trash_winter_legacy(fixture,true,null);raise exception 'stale restore accepted';exception when raise_exception then if sqlerrm='stale restore accepted' then raise;end if;end;
 if manager_id is not null then
  perform set_config('request.jwt.claim.sub',manager_id::text,true);
  items:=public.cheongla_winter_booking_list();assert items->'legacy_trash'='[]'::jsonb,'manager can see trash';
  begin perform public.cheongla_trash_winter_legacy(fixture,true,stamp);raise exception 'manager restore accepted';exception when insufficient_privilege then null;end;
 end if;
 perform set_config('request.jwt.claim.sub',principal_id::text,true);
 perform public.cheongla_trash_winter_legacy(fixture,true,stamp);
 assert (select deleted_at is null and deleted_by is null and record=payload from cheongla_private.winter_legacy_records where source_id=fixture),'restore or preservation failed';
 items:=public.cheongla_winter_booking_list();
 assert exists(select 1 from jsonb_array_elements(items->'legacy')r where r->>'source_id'=fixture),'restore missing from active list';
end $$;
rollback;
select 'PASS: anonymous/nonmember/manager denial, principal archive/restore, stale version rejection, original preservation; synthetic transaction rolled back' as result,
 count(*) as existing_records,count(*) filter(where deleted_at is not null) as deleted_records from cheongla_private.winter_legacy_records;
