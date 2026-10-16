rollback;
begin;
do $$declare u uuid:=gen_random_uuid();begin
 if public.cheongla_signup_access_hook('{}')<>'{}'::jsonb then raise exception 'manual signup blocked';end if;
 if has_function_privilege('anon','public.cheongla_signup_access_hook(jsonb)','execute')or has_function_privilege('authenticated','public.cheongla_signup_access_hook(jsonb)','execute')then raise exception 'auth hook exposed';end if;
 insert into auth.users(id,email,raw_user_meta_data)values(u,'manual-signup-'||u||'@example.invalid','{"full_name":"수동 승인 검증","contact_phone":"01000000993","requested_role":"student"}');
 if not exists(select 1 from public.cheongla_profiles where id=u and approval_status='pending'and not is_app_admin and role='student')then raise exception 'signup auto-approved';end if;
 if not exists(select 1 from cheongla_private.recovery_phones where user_id=u and phone='01000000993')then raise exception 'original signup phone missing';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);if cheongla_private.can_use_member_services()then raise exception 'pending service access';end if;
end;$$;
rollback;
select 'PASS: manual signup allowed, pending approval required, original phone captured privately, pending services blocked, auth hook not callable by clients; synthetic rollback.'as result;
