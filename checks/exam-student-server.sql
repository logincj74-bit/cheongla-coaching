rollback;
begin;
do $$declare st uuid:=gen_random_uuid();other_student uuid:=gen_random_uuid();ex uuid;k text;begin
 perform set_config('test.exam_student',st::text,true);perform set_config('test.other_student',other_student::text,true);
 insert into auth.users(id,email,raw_user_meta_data)values(st,'exam-test-'||st||'@example.invalid','{"full_name":"모의고사 신청 검증","contact_phone":"01000000995","requested_role":"student"}'),(other_student,'exam-test-'||other_student||'@example.invalid','{"full_name":"다른 학생 검증","contact_phone":"01000000996","requested_role":"student"}');
 update public.cheongla_profiles set role='student',approval_status='approved'where id in(st,other_student);
 foreach k in array array['daesung','survival','kice_june','kice_september']loop
  ex:=gen_random_uuid();insert into public.cheongla_exams(id,title,exam_kind,exam_on,deadline,body,status)values(ex,'신청 회귀검증 '||k,k,current_date+30,clock_timestamp()+interval '29 days','가상 시험','open');
 end loop;
end;$$;
set local role authenticated;
do $$declare st uuid:=current_setting('test.exam_student')::uuid;e record;n integer:=0;begin
 perform set_config('request.jwt.claim.sub',st::text,true);perform set_config('request.jwt.claim.role','authenticated',true);
 if not exists(select 1 from jsonb_array_elements(public.cheongla_application_students())s where s->>'id'=st::text)then raise exception 'FAIL student absent from applicant list';end if;
 for e in select id,exam_kind from public.cheongla_exams where title like '신청 회귀검증 %'loop
  n:=n+1;perform public.cheongla_apply_student_exam(st,e.id,'register');
  if not exists(select 1 from public.cheongla_exam_applications where exam_id=e.id and student_id=st and status='registered')then raise exception 'FAIL register %',e.exam_kind;end if;
  perform public.cheongla_apply_student_exam(st,e.id,'register');
  perform public.cheongla_apply_student_exam(st,e.id,'cancel');
  if not exists(select 1 from public.cheongla_exam_applications where exam_id=e.id and student_id=st and status='canceled')then raise exception 'FAIL cancel';end if;
  perform public.cheongla_apply_student_exam(st,e.id,'register');
  if(select count(*)from public.cheongla_exam_applications where exam_id=e.id and student_id=st)<>1 then raise exception 'FAIL duplicate';end if;
  begin perform public.cheongla_apply_student_exam(current_setting('test.other_student')::uuid,e.id,'register');raise exception 'FAIL other student access';exception when insufficient_privilege then null;end;
 end loop;
 if n<>4 then raise exception 'FAIL exam categories %',n;end if;
end;$$;
reset role;
do $$declare st uuid:=current_setting('test.exam_student')::uuid;e uuid;begin
 select id into e from public.cheongla_exams where title='신청 회귀검증 daesung';
 update public.cheongla_exams set deleted_at=clock_timestamp()where id=e;
 perform set_config('request.jwt.claim.sub',st::text,true);
 begin perform public.cheongla_apply_student_exam(st,e,'register');raise exception 'FAIL deleted accepted';exception when raise_exception then if SQLERRM like 'FAIL%'then raise;end if;end;
 update public.cheongla_exams set deleted_at=null,deadline=clock_timestamp()-interval '1 minute'where id=e;
 begin perform public.cheongla_apply_student_exam(st,e,'register');raise exception 'FAIL expired accepted';exception when raise_exception then if SQLERRM like 'FAIL%'then raise;end if;end;
end;$$;
rollback;
select 'PASS: authenticated student registers, cancels and re-registers all 4 exam types; duplicate/other-student/deleted/deadline checks; synthetic data rolled back.'as result;
