begin;
do $$
declare director uuid:=gen_random_uuid();target uuid:=gen_random_uuid();manager uuid:=gen_random_uuid();stamp timestamptz;
begin
 insert into auth.users(id,email,raw_user_meta_data)select x,'missing-phone-'||x||'@example.invalid','{"full_name":"번호등록검증","contact_phone":"01000000994"}'::jsonb from unnest(array[director,target,manager])x;
 update public.cheongla_profiles set role='english_director',is_app_admin=true,approval_status='approved'where id=director;
 update public.cheongla_profiles set role='math_director',approval_status='approved'where id=target;
 update public.cheongla_profiles set role='manager',approval_status='approved'where id=manager;
 delete from cheongla_private.recovery_phones where user_id=target;
 select membership_updated_at into stamp from public.cheongla_profiles where id=target;
 perform set_config('request.jwt.claim.sub',manager::text,true);
 begin perform public.cheongla_register_staff_recovery_phone(target,'01000000994','대면 본인 확인',stamp);raise exception 'manager changed director recovery phone';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',director::text,true);
 perform public.cheongla_register_staff_recovery_phone(target,'01000000994','대면 본인 확인',stamp);
 assert(select phone='01000000994'from cheongla_private.recovery_phones where user_id=target),'phone not stored';
 assert public.cheongla_manual_account(target)->>'phone'='01000000994','registered phone not returned';
 select membership_updated_at into stamp from public.cheongla_profiles where id=target;
 begin perform public.cheongla_register_staff_recovery_phone(target,'01000000995','다른 번호로 변경 시도',stamp);raise exception 'existing phone overwritten';exception when raise_exception then if sqlerrm='existing phone overwritten'then raise;end if;end;
end $$;
rollback;
select 'PASS: principal registers missing staff recovery phone after identity check, manager denied, existing phone cannot be overwritten; rolled back' as result;
