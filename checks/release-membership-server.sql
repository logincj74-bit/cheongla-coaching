begin;
do $$declare st uuid;pa uuid;ad uuid;mg uuid;v timestamptz;token uuid:=gen_random_uuid();q uuid;q2 uuid;payload jsonb;phone text:='010'||lpad((floor(random()*100000000))::bigint::text,8,'0');n uuid;begin
select id into st from public.cheongla_profiles where role='student' and approval_status='approved' limit 1;
select id into pa from public.cheongla_profiles where role='parent' and approval_status='approved' limit 1;
select id into ad from public.cheongla_profiles where is_app_admin and role in ('owner','english_director','math_director') and approval_status='approved' limit 1;
select id into mg from public.cheongla_profiles where role='manager' and approval_status='approved' limit 1;
if st is null or pa is null or ad is null or mg is null then raise exception '검증할 학생·학부모·원장·실장 계정이 필요합니다.';end if;
perform set_config('test.student',st::text,true);perform set_config('test.director',ad::text,true);perform set_config('test.manager',mg::text,true);
perform set_config('request.jwt.claim.sub',st::text,true);
begin perform public.cheongla_manage_member(pa,'withdraw','퇴원',null);raise exception 'FAIL student administration';exception when insufficient_privilege then null;end;
perform set_config('request.jwt.claim.sub',pa::text,true);
begin perform public.cheongla_withdraw_membership('틀림');raise exception 'FAIL confirmation';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
perform public.cheongla_withdraw_membership('회원탈퇴');
if cheongla_private.can_use_member_services() or (select membership_state from public.cheongla_profiles where id=pa)<>'withdrawn' then raise exception 'FAIL self withdrawal';end if;
perform set_config('request.jwt.claim.sub',ad::text,true);
begin perform public.cheongla_set_member_access(pa,'parent','approved',false);raise exception 'FAIL reapproval';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
begin perform public.cheongla_withdraw_membership('회원탈퇴');raise exception 'FAIL admin withdrawal';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
select membership_updated_at into v from public.cheongla_profiles where id=st;
perform public.cheongla_manage_member(st,'suspend','규칙 위반 검증',v);
begin perform public.cheongla_manage_member(st,'restore','검증 복원',v);raise exception 'FAIL stale version';exception when raise_exception then if SQLERRM like 'FAIL%' then raise;end if;end;
select membership_updated_at into v from public.cheongla_profiles where id=st;
perform public.cheongla_manage_member(st,'restore','검증 복원',v);
if jsonb_array_length(public.cheongla_member_action_history(st))<2 then raise exception 'FAIL history';end if;
-- Guest submissions are retained for staff review, never immediately made public.
perform set_config('request.jwt.claim.sub','',true);
q:=public.cheongla_submit_new_inquiry(token,gen_random_uuid(),'검증용 문의',phone,'student','검증용 제목','등록 상담 문의 야동 링크 의심','public',true,'');
if not exists(select 1 from public.cheongla_new_inquiries where id=q and review_state='pending' and cardinality(risk_flags)>0) then raise exception 'FAIL pending risk flag';end if;
payload:=public.cheongla_list_new_inquiries(200);
if exists(select 1 from jsonb_array_elements(payload->'items') x where x->>'id'=q::text or x ? 'contact_phone' or x ? 'risk_flags') then raise exception 'FAIL pending exposure';end if;
perform set_config('request.jwt.claim.sub',ad::text,true);select updated_at into v from public.cheongla_new_inquiries where id=q;
perform public.cheongla_review_new_inquiry(q,'publish','검증',v);
perform set_config('request.jwt.claim.sub','',true);payload:=public.cheongla_list_new_inquiries(200);
if not exists(select 1 from jsonb_array_elements(payload->'items') x where x->>'id'=q::text) then raise exception 'FAIL published missing';end if;
perform set_config('request.jwt.claim.sub',ad::text,true);select updated_at into v from public.cheongla_new_inquiries where id=q;
perform public.cheongla_review_new_inquiry(q,'block','검증용 접수 차단',v);
perform set_config('request.jwt.claim.sub','',true);
begin perform public.cheongla_submit_new_inquiry(gen_random_uuid(),gen_random_uuid(),'검증용 문의',phone,'student','다른 브라우저','등록 상담','private',true,'');raise exception 'FAIL phone block bypass';exception when insufficient_privilege then null;end;
payload:=public.cheongla_list_new_inquiries(200);if exists(select 1 from jsonb_array_elements(payload->'items') x where x->>'id'=q::text) then raise exception 'FAIL hidden visible';end if;
perform set_config('request.jwt.claim.sub',mg::text,true);select updated_at into v from public.cheongla_new_inquiries where id=q;perform public.cheongla_review_new_inquiry(q,'unblock','검증 해제',v);
if (select review_state from public.cheongla_new_inquiries where id=q)<>'hidden' then raise exception 'FAIL automatic republish';end if;
perform set_config('request.jwt.claim.sub',st::text,true);
begin perform public.cheongla_review_new_inquiry(q,'publish','',v);raise exception 'FAIL student review';exception when insufficient_privilege then null;end;
perform set_config('request.jwt.claim.sub',pa::text,true);
begin perform public.cheongla_submit_new_inquiry(gen_random_uuid(),gen_random_uuid(),'검증',phone,'student','검증','검증','private',true,'');raise exception 'FAIL withdrawn inquiry';exception when insufficient_privilege then null;end;
end;$$;
set local role authenticated;
do $$declare n uuid;v timestamptz;begin
perform set_config('request.jwt.claim.sub',current_setting('test.director'),true);
insert into public.cheongla_notices(title,body,audience,channel,created_by) values('검증용 원장 공지','검증','all','director',auth.uid()) returning id into n;

perform set_config('request.jwt.claim.sub',current_setting('test.manager'),true);
begin insert into public.cheongla_notices(title,body,audience,channel,created_by) values('금지 검증','검증','all','director',auth.uid());raise exception 'FAIL manager director notice';exception when insufficient_privilege then null;end;
insert into public.cheongla_notices(title,body,audience,channel,created_by) values('검증용 실장 업무 공지','검증','all','desk',auth.uid());
perform set_config('request.jwt.claim.sub',current_setting('test.student'),true);
if (select count(*) from public.cheongla_notices where title in ('검증용 원장 공지','검증용 실장 업무 공지'))<>2 then raise exception 'FAIL student notice channels';end if;
perform set_config('request.jwt.claim.sub',current_setting('test.director'),true);select membership_updated_at into v from public.cheongla_profiles where id=current_setting('test.student')::uuid;perform public.cheongla_manage_member(current_setting('test.student')::uuid,'withdraw','퇴원 검증',v);
perform set_config('request.jwt.claim.sub',current_setting('test.student'),true);
if exists(select 1 from public.cheongla_notices) or exists(select 1 from public.cheongla_meal_submissions) then raise exception 'FAIL withdrawn old session read';end if;
begin insert into public.cheongla_notices(title,body,audience,channel,created_by) values('금지 검증','검증','all','desk',auth.uid());raise exception 'FAIL withdrawn write';exception when insufficient_privilege then null;end;
end;$$;
reset role;
-- Validate notification destinations as the database owner without disclosing recipients.
do $$begin
if not exists(select 1 from public.cheongla_notifications a join public.cheongla_notices n on n.id=a.source_id where n.title='검증용 실장 업무 공지' and a.route='desk_notice_all') then raise exception 'FAIL desk notification route';end if;
end;$$;
rollback;
select 'PASS: 본인 탈퇴·원장 이용중지/복원/탈퇴·재승인 차단·기존 로그인 권한 차단·공개 사전 검토·접수 차단/해제·원장/실장 공지 권한과 알림 경로. 검증 자료 모두 롤백.' as result;
