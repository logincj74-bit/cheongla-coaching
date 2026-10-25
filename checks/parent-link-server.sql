begin;
update cheongla_private.push_settings set enabled=false;
update cheongla_private.membership_sms_settings set enabled=false;
do $$
declare pa uuid:=gen_random_uuid();st uuid:=gen_random_uuid();outsider uuid:=gen_random_uuid();ad uuid;stamp timestamptz;
begin
 select id into ad from public.cheongla_profiles where role in('owner','english_director','math_director') and approval_status='approved' and membership_state='active' limit 1;
 insert into auth.users(id,email,raw_user_meta_data)values
 (pa,pa::text||'@example.invalid',jsonb_build_object('full_name','연결알림 검증 학부모','requested_role','parent','contact_phone','010'||repeat('0',8))),
 (st,st::text||'@example.invalid',jsonb_build_object('full_name','연결알림 검증 학생','requested_role','student','contact_phone','010'||repeat('0',8)));
 perform set_config('request.jwt.claim.sub',ad::text,true);
 update public.cheongla_profiles set approval_status='approved' where id in(pa,st);
 insert into public.cheongla_parent_students(parent_id,student_id,created_by)values(pa,st,ad)returning created_at into stamp;
 if (select count(*) from public.cheongla_notifications where source_kind='parent_link' and source_id=pa and student_id=st and recipient_id=pa and route='account_childrenPanel')<>1 then raise exception 'FAIL exact parent inbox';end if;
 if exists(select 1 from public.cheongla_notifications where source_kind='parent_link' and student_id=st and recipient_id<>pa)then raise exception 'FAIL private recipient';end if;
 insert into public.cheongla_parent_students(parent_id,student_id,created_by)values(pa,st,ad)on conflict do nothing;
 if (select count(*) from public.cheongla_notifications where source_kind='parent_link' and source_id=pa and student_id=st)<>1 then raise exception 'FAIL duplicate';end if;
 if not cheongla_private.push_source_allowed(pa,'parent_link',pa,st)then raise exception 'FAIL parent push permission';end if;
 if cheongla_private.push_source_allowed(st,'parent_link',pa,st)then raise exception 'FAIL student privacy';end if;
 perform set_config('request.jwt.claim.sub',pa::text,true);
 if cheongla_private.can_read_notification('parent_link',outsider,st)or cheongla_private.can_read_notification('parent_link',pa,outsider)then raise exception 'FAIL wrong pair privacy';end if;
 if has_function_privilege('authenticated','cheongla_private.notify_parent_link()','execute')or has_function_privilege('anon','cheongla_private.notify_parent_link()','execute')then raise exception 'FAIL trigger RPC exposure';end if;
 -- Roll this relation back inside a subtransaction to verify stale notification access without unlinking real accounts.
 begin
  delete from public.cheongla_parent_students where parent_id=pa and student_id=st;
  if cheongla_private.push_source_allowed(pa,'parent_link',pa,st)then raise exception 'FAIL revoked relation';end if;
  raise sqlstate 'ZX063';
 exception when sqlstate 'ZX063'then null;end;
end;$$;
rollback;
select 'PASS: parent-only completion inbox, exact child route, push authorization, duplicate prevention, revoked relation, private trigger; fixtures/settings rolled back, no messages sent.' as result;
