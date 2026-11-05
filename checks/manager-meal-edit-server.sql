begin;
do $$
declare manager uuid:=gen_random_uuid();student uuid:=gen_random_uuid();m date:='2097-11-01';f timestamptz;v timestamptz;
begin
 insert into auth.users(id,email,raw_user_meta_data)select x,'meal-edit-'||x||'@example.invalid','{"full_name":"도시락수정검증","contact_phone":"01000000994"}'::jsonb from unnest(array[manager,student])x;
 update public.cheongla_profiles set role='manager',is_app_admin=false,approval_status='approved'where id=manager;
 update public.cheongla_profiles set role='student',approval_status='approved'where id=student;
 insert into public.cheongla_meal_forms(month,deadline,unit_price,note)values(m,current_date-1,7500,'실장 권한 검증용')returning updated_at into f;
 insert into public.cheongla_meal_submissions(month,student_id,student_name,lunch,dinner,note)values(m,student,'도시락수정검증',array['2097-11-04'::date],array['2097-11-05'::date],'기존 신청')returning updated_at into v;
 perform set_config('request.jwt.claim.sub',manager::text,true);
 perform public.cheongla_manage_student_meal(student,m,array['2097-11-04'::date,'2097-11-06'::date],'{}','실장이 신청 수량 정정',v,f);
 assert exists(select 1 from public.cheongla_meal_submissions where student_id=student and month=m and cardinality(lunch)=2 and cardinality(dinner)=0 and note='실장이 신청 수량 정정'),'manager counts not persisted';
 assert exists(select 1 from cheongla_private.meal_submission_edits where actor_id=manager and student_id=student and month=m),'manager edit history missing';
 select updated_at into v from public.cheongla_meal_submissions where month=m and student_id=student;
 perform set_config('request.jwt.claim.sub',student::text,true);
 begin perform public.cheongla_manage_student_meal(student,m,'{}','{}','우회 수정',v,f);raise exception 'student used manager edit';exception when insufficient_privilege then null;end;
end $$;
rollback;
select 'PASS: non-admin manager edits expired-month student lunch/dinner counts with persisted results and edit history; student cannot use staff edit; all fixtures rolled back' as result;
