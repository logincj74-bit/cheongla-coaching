rollback;
begin;
do $$declare owner_id uuid;manager_id uuid;student_id uuid;begin
 select id into owner_id from public.cheongla_profiles where role in('owner','english_director','math_director')and approval_status='approved'and membership_state='active'limit 1;
 select id into manager_id from public.cheongla_profiles where role='manager'and approval_status='approved'and membership_state='active'limit 1;
 select id into student_id from public.cheongla_profiles where role='student'and approval_status='approved'and membership_state='active'limit 1;
 if owner_id is null or manager_id is null or student_id is null then raise exception 'required test roles missing';end if;
 perform set_config('test.exam_owner',owner_id::text,true);perform set_config('test.exam_manager',manager_id::text,true);perform set_config('test.exam_student',student_id::text,true);
end;$$;
set local role authenticated;
do $$declare actor uuid;k text;ex uuid;v timestamptz;n integer:=0;begin
 perform set_config('request.jwt.claim.role','authenticated',true);
 foreach actor in array array[current_setting('test.exam_owner')::uuid,current_setting('test.exam_manager')::uuid]loop
  perform set_config('request.jwt.claim.sub',actor::text,true);
  foreach k in array array['daesung','survival','kice_june','kice_september','other']loop
   ex:=public.cheongla_save_exam_v2(null,'저장 검증 '||k,current_date+30,(current_date+29)::timestamp at time zone 'Asia/Seoul','안내 내용','open',k,null);
   if not exists(select 1 from public.cheongla_exams where id=ex and title='저장 검증 '||k and exam_kind=k and status='open')then raise exception 'FAIL save/readback %',k;end if;
   select updated_at into v from public.cheongla_exams where id=ex;
   perform public.cheongla_save_exam_v2(ex,'저장 검증 '||k,current_date+30,(current_date+29)::timestamp at time zone 'Asia/Seoul','수정된 안내','open',k,v);
   if not exists(select 1 from public.cheongla_exams where id=ex and body='수정된 안내')then raise exception 'FAIL update';end if;
   n:=n+1;
  end loop;
 end loop;
 if n<>10 then raise exception 'FAIL roles/category coverage';end if;
 perform set_config('request.jwt.claim.sub',current_setting('test.exam_student'),true);
 begin perform public.cheongla_save_exam_v2(null,'등록 금지 검증',current_date+30,(current_date+29)::timestamp at time zone 'Asia/Seoul','','open','daesung',null);raise exception 'FAIL student save';exception when insufficient_privilege then null;end;
end;$$;
reset role;
rollback;
select 'PASS: owner and manager create/read/update all 5 exam categories, student creation denied; synthetic exam records rolled back.'as result;
