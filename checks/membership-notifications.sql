-- Run within a transaction. The inner block rolls every fixture and queued HTTP request back.
do $test$
declare member uuid:=gen_random_uuid();other_member uuid:=gen_random_uuid();principal uuid;expected integer;batch jsonb;job jsonb;phone text:='01086642052';
begin
 begin
  update cheongla_private.push_settings set enabled=false;
  update cheongla_private.membership_sms_settings set enabled=false;
  select count(*),min(id::text)::uuid into expected,principal from public.cheongla_profiles where approval_status='approved'and membership_state='active'and role in('owner','english_director','math_director');
  if expected=0 then raise exception 'Test requires an existing principal';end if;
  insert into auth.users(id,email,raw_user_meta_data)values(member,member::text||'@example.invalid',jsonb_build_object('full_name','알림 검증용 임시 계정','requested_role','student','contact_phone',phone));
  if (select count(*)from public.cheongla_notifications where source_kind='member_request'and source_id=member)<>expected then raise exception 'Signup recipients mismatch';end if;
  if exists(select 1 from cheongla_private.membership_sms_jobs where member_id=member)then raise exception 'Disabled SMS queued';end if;
  perform set_config('request.jwt.claim.sub',principal::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',principal)::text,true);
  if not cheongla_private.can_read_notification('member_request',member,null)then raise exception 'Principal cannot read signup';end if;
  perform public.cheongla_configure_membership_sms(phone,true);
  update public.cheongla_profiles set approval_status='approved'where id=member;
  if (select count(*)from public.cheongla_notifications where source_kind='member_approved'and source_id=member and recipient_id=member)<>1 then raise exception 'Approval inbox mismatch';end if;
  update public.cheongla_profiles set approval_status='approved'where id=member;
  if (select count(*)from cheongla_private.membership_sms_jobs where member_id=member and kind='approved')<>1 then raise exception 'Approval duplicate';end if;
  if not cheongla_private.push_source_allowed(member,'member_approved',member,null)then raise exception 'Approval push blocked';end if;
  perform set_config('request.jwt.claim.sub',member::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',member)::text,true);
  if cheongla_private.can_read_notification('member_request',member,null)or cheongla_private.can_read_notification('member_approved',other_member,null)then raise exception 'Member notification privacy failed';end if;
  begin
   perform public.cheongla_configure_membership_sms(phone,true);
   raise exception 'Student changed SMS settings';
  exception when insufficient_privilege then null;end;
  batch:=public.cheongla_claim_membership_sms();
  select value into job from jsonb_array_elements(batch)where value->>'id'=(select id::text from cheongla_private.membership_sms_jobs where member_id=member and kind='approved');
  if job is null or job->>'to'<>phone then raise exception 'Approval claim mismatch';end if;
  perform public.cheongla_finish_membership_sms((job->>'id')::uuid,gen_random_uuid(),'accepted','mock');
  if not exists(select 1 from cheongla_private.membership_sms_jobs where id=(job->>'id')::uuid and state='processing')then raise exception 'Invalid claim token accepted';end if;
  perform public.cheongla_finish_membership_sms((job->>'id')::uuid,(job->>'token')::uuid,'accepted','mock');
  if not exists(select 1 from cheongla_private.membership_sms_jobs where id=(job->>'id')::uuid and state='accepted')then raise exception 'Finish failed';end if;
  insert into auth.users(id,email,raw_user_meta_data)values(other_member,other_member::text||'@example.invalid',jsonb_build_object('full_name','알림 검증용 임시 계정','requested_role','parent','contact_phone',phone));
  if (select count(*)from cheongla_private.membership_sms_jobs where member_id=other_member and kind='request')<>1 then raise exception 'Signup SMS missing';end if;
  update public.cheongla_profiles set approval_status='approved'where id=other_member;
  batch:=public.cheongla_claim_membership_sms();
  if not exists(select 1 from cheongla_private.membership_sms_jobs where member_id=other_member and kind='request'and state='cancelled')then raise exception 'Stale signup SMS not cancelled';end if;
  if has_function_privilege('authenticated','public.cheongla_claim_membership_sms()','EXECUTE')or has_function_privilege('anon','public.cheongla_membership_sms_server_config()','EXECUTE')then raise exception 'Service RPC exposed';end if;
  if has_table_privilege('authenticated','cheongla_private.membership_sms_jobs','SELECT')or has_table_privilege('anon','cheongla_private.membership_sms_settings','SELECT')then raise exception 'SMS private tables exposed';end if;
  raise sqlstate 'ZX055' using message='PASS';
 exception when sqlstate 'ZX055'then null;end;
 if exists(select 1 from auth.users where id in(member,other_member))or exists(select 1 from public.cheongla_notifications where source_id in(member,other_member))then raise exception 'Fixture rollback failed';end if;
 raise notice 'PASS membership: signup recipients, own approval inbox/push, dedupe, SMS disabled/enabled queue, stale cancellation, token guard, service-only RPCs, private tables, fixture rollback';
end;$test$;
