begin;
do $$
declare principal uuid;member uuid:=gen_random_uuid();past jsonb;current_row jsonb;
begin
 select id into principal from public.cheongla_profiles where role in('owner','english_director','math_director')and approval_status='approved'and membership_state='active'limit 1;
 insert into auth.users(id,email,raw_user_meta_data)values(member,'journal-check-'||member||'@example.invalid','{"full_name":"근무기록 검증","contact_phone":"01000000997"}');
 update public.cheongla_profiles set role='manager',approval_status='approved'where id=member;
 perform set_config('request.jwt.claim.sub',member::text,true);
 current_row:=public.cheongla_save_staff_journal_v2(null,(clock_timestamp()at time zone'Asia/Seoul')::date,'오늘 작성 검증','','',null,'green');
 assert current_row->>'duty'='오늘 작성 검증','staff cannot write own today journal';
 begin perform public.cheongla_staff_journal_action((current_row->>'id')::uuid,'archive',(current_row->>'updated_at')::timestamptz);raise exception 'staff can archive';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',principal::text,true);
 past:=public.cheongla_save_staff_journal_v2(null,'2001-02-03','이전 일지 검증','','',null,'red');
 update cheongla_private.staff_journals set author_id=member where id=(past->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',member::text,true);
 begin perform public.cheongla_save_staff_journal_v2((past->>'id')::uuid,'2001-02-03','비원장 수정','','',(past->>'updated_at')::timestamptz,'green');raise exception 'staff can modify past journal';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',principal::text,true);
 perform public.cheongla_staff_journal_action((current_row->>'id')::uuid,'archive',(current_row->>'updated_at')::timestamptz);
 assert exists(select 1 from cheongla_private.staff_journals where id=(current_row->>'id')::uuid and archived_at is not null),'principal archive failed';
end $$;
rollback;
select 'PASS: staff own today writing preserved; past modification and trash management reserved to principals; fixtures rolled back' as result;
