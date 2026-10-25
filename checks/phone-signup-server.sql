begin;
update cheongla_private.push_settings set enabled=false;
update cheongla_private.membership_sms_settings set enabled=false;
do $$declare id1 uuid:=gen_random_uuid();id2 uuid:=gen_random_uuid();n text:='010'||repeat('0',8);a text;
begin
 a:=encode(extensions.digest(n,'sha256'),'hex')||'@phone.cheongla.invalid';
 insert into auth.users(id,email,raw_user_meta_data)values(id1,a,jsonb_build_object('full_name','전화 가입 검증','contact_phone',n,'requested_role','parent','is_app_admin',true,'role','owner')),(id2,id2::text||'@example.invalid',jsonb_build_object('full_name','이메일 가입 검증','contact_phone',n,'requested_role','student'));
 if not exists(select 1 from public.cheongla_profiles where id=id1 and role='parent'and approval_status='pending'and not is_app_admin)then raise exception 'FAIL pending access';end if;
 if not exists(select 1 from auth.users where id=id1 and raw_app_meta_data->>'login_method'='phone')or not exists(select 1 from auth.users where id=id2 and raw_app_meta_data->>'login_method'='email')then raise exception 'FAIL method';end if;
 if not exists(select 1 from cheongla_private.member_contacts where user_id=id1 and phone=n)then raise exception 'FAIL contact';end if;
 begin insert into auth.users(id,email,raw_user_meta_data)values(gen_random_uuid(),repeat('a',64)||'@phone.cheongla.invalid',jsonb_build_object('full_name','검증','contact_phone',n));raise exception 'FAIL mismatched phone';exception when invalid_parameter_value then null;end;
end;$$;
rollback;
select 'PASS email/phone identity, contact persistence, pending approval, no metadata privilege escalation, mismatched phone alias denied. All rolled back, no notifications sent.'as result;
