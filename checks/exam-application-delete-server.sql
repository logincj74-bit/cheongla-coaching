begin;
do $$declare owner_id uuid;manager_id uuid;student uuid;other_student uuid;ex uuid;v timestamptz;
begin
 select id into owner_id from public.cheongla_profiles where role in('owner','english_director','math_director')and approval_status='approved'and membership_state='active'limit 1;
 select id into manager_id from public.cheongla_profiles where role='manager'and approval_status='approved'and membership_state='active'limit 1;
 select id into student from public.cheongla_profiles where role='student' limit 1;
 select id into other_student from public.cheongla_profiles where role='student'and id<>student limit 1;
 if owner_id is null or manager_id is null or student is null or other_student is null then raise exception 'test roles missing';end if;
 insert into public.cheongla_exams(title,exam_on,deadline,status) values('신청 삭제 롤백 검증',current_date+31,clock_timestamp()+interval '30 days','draft') returning id into ex;
 insert into public.cheongla_exam_applications(exam_id,student_id,student_name,status)values(ex,student,'삭제 검증','registered'),(ex,other_student,'다른 학생 보존 검증','registered');
 select updated_at into v from public.cheongla_exam_applications where exam_id=ex and student_id=student;
 perform set_config('test.delete_owner',owner_id::text,true);perform set_config('test.delete_manager',manager_id::text,true);perform set_config('test.delete_student',student::text,true);perform set_config('test.delete_other',other_student::text,true);perform set_config('test.delete_exam',ex::text,true);perform set_config('test.delete_version',v::text,true);
end;$$;
set local role authenticated;
do $$declare actor uuid;ex uuid:=current_setting('test.delete_exam')::uuid;student uuid:=current_setting('test.delete_student')::uuid;v timestamptz:=current_setting('test.delete_version')::timestamptz;
begin
 foreach actor in array array[current_setting('test.delete_manager')::uuid,student]loop
  perform set_config('request.jwt.claim.sub',actor::text,true);
  begin perform public.cheongla_delete_exam_application(ex,student,v);raise exception 'FAIL nonprincipal delete';exception when insufficient_privilege then null;end;
 end loop;
 perform set_config('request.jwt.claim.sub',current_setting('test.delete_owner'),true);
 begin perform public.cheongla_delete_exam_application(ex,student,v-interval '1 second');raise exception 'FAIL stale version';exception when raise_exception then if sqlerrm='FAIL stale version'then raise;end if;end;
end;$$;
reset role;
do $$declare e public.cheongla_exams%rowtype;
begin
 select * into e from public.cheongla_exams where id=current_setting('test.delete_exam')::uuid;
 insert into public.cheongla_exam_fee_notices(exam_id,student_id,student_name,exam_title,exam_on,amount,due_on,note)
 values(e.id,current_setting('test.delete_student')::uuid,'삭제 검증',e.title,e.exam_on,30000,e.exam_on,'연결 보호 검증');
end;$$;
set local role authenticated;
do $$begin
 begin perform public.cheongla_delete_exam_application(current_setting('test.delete_exam')::uuid,current_setting('test.delete_student')::uuid,current_setting('test.delete_version')::timestamptz);raise exception 'FAIL billing protection';exception when raise_exception then if sqlerrm='FAIL billing protection'then raise;end if;end;
end;$$;
reset role;
delete from public.cheongla_exam_fee_notices where exam_id=current_setting('test.delete_exam')::uuid;
set local role authenticated;
select public.cheongla_delete_exam_application(current_setting('test.delete_exam')::uuid,current_setting('test.delete_student')::uuid,current_setting('test.delete_version')::timestamptz) is not null as deleted;
reset role;
do $$begin
 if exists(select 1 from public.cheongla_exam_applications where exam_id=current_setting('test.delete_exam')::uuid and student_id=current_setting('test.delete_student')::uuid)then raise exception 'FAIL not deleted';end if;
 if not exists(select 1 from public.cheongla_exam_applications where exam_id=current_setting('test.delete_exam')::uuid and student_id=current_setting('test.delete_other')::uuid)then raise exception 'FAIL other student changed';end if;
 if not exists(select 1 from public.cheongla_profiles where id=current_setting('test.delete_student')::uuid)then raise exception 'FAIL account deleted';end if;
 if not exists(select 1 from cheongla_private.exam_application_deletions where exam_id=current_setting('test.delete_exam')::uuid and student_id=current_setting('test.delete_student')::uuid)then raise exception 'FAIL missing deletion log';end if;
end;$$;
set local role anon;
do $$begin
 begin perform public.cheongla_delete_exam_application(current_setting('test.delete_exam')::uuid,current_setting('test.delete_other')::uuid,now());raise exception 'FAIL anon access';exception when insufficient_privilege then null;end;
end;$$;
reset role;
rollback;
select 'PASS: principal delete, manager/student/anon denied, stale version denied, fee protection, other student/account retained, private audit recorded. Test data rolled back.' as result;
