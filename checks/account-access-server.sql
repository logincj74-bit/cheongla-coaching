begin;
do $$declare k int;u uuid;begin
 for k in 1..4 loop
 u:=('04700000-0000-0000-0000-'||lpad(k::text,12,'0'))::uuid;
 insert into auth.users(id,email,raw_user_meta_data)values(u,'account-test-'||k||'@example.invalid',jsonb_build_object('full_name','계정 검증','contact_phone','0100000000'||k));
 insert into public.cheongla_profiles(id,full_name,role,approval_status,is_app_admin)values(u,'계정 검증',case when k=1 then 'owner'else 'student'end,'approved',false)on conflict(id)do update set role=excluded.role,approval_status='approved',is_app_admin=false;
 end loop;
 update public.cheongla_profiles set membership_state='withdrawn',approval_status='suspended'where id='04700000-0000-0000-0000-000000000003';
 update auth.users set raw_user_meta_data=jsonb_set(raw_user_meta_data,'{contact_phone}','"01099999999"')where id='04700000-0000-0000-0000-000000000002';
 if(select phone from cheongla_private.recovery_phones where user_id='04700000-0000-0000-0000-000000000002')<>'01000000002'then raise exception 'signup number mutated';end if;
end;$$;
select set_config('request.jwt.claim.sub','04700000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$declare k text;e uuid;cfg public.cheongla_exam_fee_settings%rowtype;v jsonb;
begin
 foreach k in array array['daesung','survival','kice_june','kice_september','other']loop
 e:=public.cheongla_save_exam_v2(null,'시험 분류 검증','2099-12-21','2099-12-20 12:00+09','','draft',k,null);
 if(select exam_kind from public.cheongla_exams where id=e)<>k then raise exception 'exam kind not saved';end if;
 perform public.cheongla_save_exam_fee_settings(e,57900,'2099-12-21','직접 입력',null);
 select * into cfg from public.cheongla_exam_fee_settings where exam_id=e;
 perform public.cheongla_save_exam_fee_settings(e,60123,'2099-12-21','금액 변경',cfg.updated_at);
 if(select amount from public.cheongla_exam_fee_settings where exam_id=e)<>60123 then raise exception 'manual fee failed';end if;
 end loop;
 v:=public.cheongla_account_access_hook(jsonb_build_object('user_id','04700000-0000-0000-0000-000000000003','claims','{"sub":"withdrawn"}'::jsonb));
 if v#>>'{error,http_code}'<>'403' then raise exception 'withdrawn token not rejected';end if;
 v:=public.cheongla_account_access_hook(jsonb_build_object('user_id','04700000-0000-0000-0000-000000000002','claims','{"sub":"active"}'::jsonb));
 if v->'claims'<>'{"sub":"active"}'::jsonb then raise exception 'active claims changed';end if;
 if has_function_privilege('anon','public.cheongla_account_access_hook(jsonb)','execute')or has_function_privilege('authenticated','public.cheongla_account_access_hook(jsonb)','execute')then raise exception 'hook public';end if;
 if has_function_privilege('authenticated','public.cheongla_recovery_verify(uuid,text,text)','execute')then raise exception 'recovery RPC public';end if;
 begin perform public.cheongla_recovery_consume(gen_random_uuid(),repeat('a',64));raise exception 'RPC role allowed';exception when insufficient_privilege then null;end;
end;$$;
select set_config('request.jwt.claim.role','service_role',true);
do $$declare ch uuid:=gen_random_uuid();r jsonb;v uuid;k int;begin
 r:=public.cheongla_recovery_issue(ch,'reset_password','01000000002','account-test-2@example.invalid',repeat('a',64),repeat('b',64),repeat('c',64));
 if r->>'eligible'<>'true'then raise exception 'eligible account missing';end if;
 if(public.cheongla_recovery_issue(gen_random_uuid(),'find_id','01000000002','',repeat('a',64),repeat('b',64),repeat('c',64))->>'limited')<>'true'then raise exception 'cooldown bypass';end if;
 perform public.cheongla_recovery_sent(ch,true);
 r:=public.cheongla_recovery_verify(ch,repeat('d',64),repeat('e',64));if r->>'ok'<>'false'then raise exception 'wrong OTP';end if;
 if(select attempts from cheongla_private.recovery_challenges where id=ch)<>1 then raise exception 'failure attempts rolled back';end if;
 r:=public.cheongla_recovery_verify(ch,repeat('c',64),repeat('e',64));if r->>'ok'<>'true'then raise exception 'correct OTP failed';end if;
 if public.cheongla_recovery_consume(ch,repeat('f',64))is not null then raise exception 'forged ticket';end if;
 v:=public.cheongla_recovery_consume(ch,repeat('e',64));if v<>'04700000-0000-0000-0000-000000000002'::uuid or v is null then raise exception 'ticket wrong user';end if;
 if public.cheongla_recovery_consume(ch,repeat('e',64))is not null then raise exception 'ticket reused';end if;
 -- Expiry and attempt lockout.
 ch:=gen_random_uuid();r:=public.cheongla_recovery_issue(ch,'find_id','01000000004','',repeat('1',64),repeat('b',64),repeat('c',64));perform public.cheongla_recovery_sent(ch,true);
 for k in 1..5 loop perform public.cheongla_recovery_verify(ch,repeat('d',64),repeat('e',64));end loop;
 if(public.cheongla_recovery_verify(ch,repeat('c',64),repeat('e',64))->>'ok')<>'false'then raise exception 'attempt lockout bypass';end if;
 update cheongla_private.recovery_challenges set attempts=0,expires_at=clock_timestamp()-interval '1 second'where id=ch;
 if(public.cheongla_recovery_verify(ch,repeat('c',64),repeat('e',64))->>'ok')<>'false'then raise exception 'expiry bypass';end if;
 ch:=gen_random_uuid();r:=public.cheongla_recovery_issue(ch,'find_id','01000000003','',repeat('2',64),repeat('b',64),repeat('c',64));if r->>'eligible'<>'false'then raise exception 'withdrawn recovery allowed';end if;
 -- Verified ID lookup exposes account only after correct OTP and only once.
 update cheongla_private.recovery_challenges set created_at=clock_timestamp()-interval '2 minutes'where phone_hash=repeat('a',64);
 ch:=gen_random_uuid();r:=public.cheongla_recovery_issue(ch,'find_id','01000000002','',repeat('a',64),repeat('b',64),repeat('c',64));perform public.cheongla_recovery_sent(ch,true);
 r:=public.cheongla_recovery_verify(ch,repeat('c',64),repeat('e',64));if r->'emails'<>'["account-test-2@example.invalid"]'::jsonb then raise exception 'ID reveal failed';end if;
 if(public.cheongla_recovery_verify(ch,repeat('c',64),repeat('e',64))->>'ok')<>'false'then raise exception 'ID OTP reused';end if;
end;$$;
rollback;
select 'PASS: 모의고사 5구분·가변 응시료 저장, 탈퇴 토큰 거부·정상 토큰 보존, 서버 전용 복구, 가입 번호 보존, 재전송 제한·오류 누적·만료·일회용 인증·탈퇴 복구 차단. 테스트 데이터 롤백.'as result;
