begin;
insert into auth.users(id,email,raw_user_meta_data)values('07800000-0000-4000-8000-000000000001','rejoin-fixture@example.invalid','{"full_name":"재가입 검증","contact_phone":"01000000781","requested_role":"student"}');
update public.cheongla_profiles set membership_state='withdrawn',approval_status='suspended'where id='07800000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.role','service_role',true);
do $$declare check_result jsonb;j jsonb;begin
 check_result:=public.cheongla_rejoin_job('REJOIN-FIXTURE@example.invalid');if check_result->>'history'<>'true'then raise exception 'withdrawn history missing';end if;
 j:=public.cheongla_rejoin_job('rejoin-fixture@example.invalid',(check_result->>'operation')::uuid,'begin');
 update auth.users set email=j->>'archive_email'where id=(j->>'member')::uuid;
 perform public.cheongla_rejoin_job('rejoin-fixture@example.invalid',(check_result->>'operation')::uuid,'finish');
 if not exists(select 1 from public.cheongla_profiles where id=(j->>'member')::uuid and membership_state='withdrawn'and approval_status='suspended')then raise exception 'old account reactivated';end if;
 insert into auth.users(id,email,raw_user_meta_data)values('07800000-0000-4000-8000-000000000002','rejoin-fixture@example.invalid','{"full_name":"새 가입 검증","contact_phone":"01000000781","requested_role":"student"}');
 if not exists(select 1 from public.cheongla_profiles where id='07800000-0000-4000-8000-000000000002'and approval_status='pending'and membership_state='active'and not is_app_admin)then raise exception 'new approval gate missing';end if;
 if public.cheongla_rejoin_job('rejoin-fixture@example.invalid')->>'history'<>'false'then raise exception 'active identity offered rotation';end if;
 if has_function_privilege('anon','public.cheongla_rejoin_job(text,uuid,text)','execute')or has_function_privilege('authenticated','public.cheongla_rejoin_job(text,uuid,text)','execute')then raise exception 'service operation exposed';end if;
end;$$;
select set_config('request.jwt.claim.role','authenticated',true);
do $$begin begin perform public.cheongla_rejoin_job('rejoin-fixture@example.invalid');raise exception 'anonymous rejoin RPC allowed';exception when insufficient_privilege then null;end;end;$$;
select 'PASS withdrawn email archived, old profile retained, same email creates new pending account, active identity blocked, service-only RPC' as result;
rollback;
