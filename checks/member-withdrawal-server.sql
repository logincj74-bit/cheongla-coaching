begin;
-- Synthetic identities exist only inside this transaction. Never modify a real member.
do $$declare k integer;uid uuid;begin
for k in 1..8 loop
 uid:=('03800000-0000-0000-0000-'||lpad(k::text,12,'0'))::uuid;
 insert into auth.users(id,email,raw_user_meta_data)values(uid,'withdrawal-test-'||k||'@example.invalid',jsonb_build_object('full_name','탈퇴 기능 검증','contact_phone','0100000000'||k));
 insert into public.cheongla_profiles(id,full_name,role,approval_status,is_app_admin)values(uid,'탈퇴 검증 '||k,'student','approved',false)on conflict(id)do update set full_name=excluded.full_name,role='student',approval_status='approved',is_app_admin=false;
end loop;
update public.cheongla_profiles set role=case right(id::text,1)when '1'then 'english_director'when '2'then 'manager'when '3'then 'manager'when '4'then 'math_director'when '5'then 'parent'when '7'then 'korean_teacher'when '8'then 'manager'else 'student'end where id::text like '03800000-%';
update public.cheongla_profiles set approval_status='suspended'where id='03800000-0000-0000-0000-000000000002';
update public.cheongla_profiles set is_app_admin=true where id='03800000-0000-0000-0000-000000000008';
end;$$;
set local role authenticated;
do $$declare v timestamptz;p jsonb;uid uuid;begin
-- A suspended employee can still leave their own membership.
perform set_config('request.jwt.claim.sub','03800000-0000-0000-0000-000000000002',true);
perform public.cheongla_withdraw_membership('회원탈퇴');
if not exists(select 1 from public.cheongla_profiles where id=auth.uid()and membership_state='withdrawn'and approval_status='suspended'and withdrawn_at is not null)then raise exception 'FAIL suspended staff self withdrawal';end if;
if cheongla_private.can_use_member_services()or exists(select 1 from public.cheongla_notices)then raise exception 'FAIL old self session still active';end if;
-- An English principal without app-admin permission must have the requested control.
perform set_config('request.jwt.claim.sub','03800000-0000-0000-0000-000000000001',true);
p:=public.cheongla_list_members_for_lifecycle();
if not exists(select 1 from jsonb_array_elements(p)x where x->>'id'='03800000-0000-0000-0000-000000000003')then raise exception 'FAIL principal list';end if;
select (x->>'membership_updated_at')::timestamptz into v from jsonb_array_elements(p)x where x->>'id'='03800000-0000-0000-0000-000000000003';
begin perform public.cheongla_manage_member('03800000-0000-0000-0000-000000000003','withdraw','퇴사 검증',v-interval '1 second');raise exception 'FAIL stale version';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
perform public.cheongla_manage_member('03800000-0000-0000-0000-000000000003','withdraw','퇴사 검증',v);
p:=public.cheongla_list_members_for_lifecycle();
if not exists(select 1 from jsonb_array_elements(p)x where x->>'id'='03800000-0000-0000-0000-000000000003'and x->>'membership_state'='withdrawn'and x->>'approval_status'='suspended')then raise exception 'FAIL staff force withdrawal state';end if;
if not exists(select 1 from jsonb_array_elements(public.cheongla_member_action_history('03800000-0000-0000-0000-000000000003'))x where x->>'action'='withdraw'and x->>'reason'='퇴사 검증')then raise exception 'FAIL audit history';end if;
-- Remaining ordinary roles are also eligible; no student/parent-only restriction.
for uid in select x::uuid from unnest(array['03800000-0000-0000-0000-000000000005','03800000-0000-0000-0000-000000000006','03800000-0000-0000-0000-000000000007'])x loop
 p:=public.cheongla_list_members_for_lifecycle();select(x->>'membership_updated_at')::timestamptz into v from jsonb_array_elements(p)x where x->>'id'=uid::text;
 perform public.cheongla_manage_member(uid,'withdraw','테스트 종료',v);
end loop;
-- Other principals and administrator accounts remain protected.
for uid in select x::uuid from unnest(array['03800000-0000-0000-0000-000000000004','03800000-0000-0000-0000-000000000008','03800000-0000-0000-0000-000000000001'])x loop
 begin perform public.cheongla_manage_member(uid,'withdraw','보호 계정 검증',null);raise exception 'FAIL protected account';exception when insufficient_privilege then null;end;
end loop;
-- A former employee's existing login cannot use member services or force others out.
perform set_config('request.jwt.claim.sub','03800000-0000-0000-0000-000000000003',true);
if cheongla_private.can_use_member_services()or exists(select 1 from public.cheongla_notices)then raise exception 'FAIL force old session access';end if;
begin perform public.cheongla_manage_member('03800000-0000-0000-0000-000000000004','withdraw','권한 차단',null);raise exception 'FAIL employee administration';exception when insufficient_privilege then null;end;
begin perform public.cheongla_list_members_for_lifecycle();raise exception 'FAIL employee list';exception when insufficient_privilege then null;end;
-- App-admin employee is still not a principal and cannot force withdrawal.
perform set_config('request.jwt.claim.sub','03800000-0000-0000-0000-000000000008',true);
begin perform public.cheongla_manage_member('03800000-0000-0000-0000-000000000004','withdraw','직원 관리자 차단',null);raise exception 'FAIL admin employee force';exception when insufficient_privilege then null;end;
-- Both principal roles work without acquiring global admin privileges.
perform set_config('request.jwt.claim.sub','03800000-0000-0000-0000-000000000004',true);perform public.cheongla_list_members_for_lifecycle();
end;$$;
reset role;
do $$begin
if(select count(*)from public.cheongla_profiles where id::text like '03800000-%'and membership_state='withdrawn')<>5 then raise exception 'FAIL final persisted states';end if;
if(select count(*)from cheongla_private.member_actions where member_id::text like '03800000-%')<>5 then raise exception 'FAIL audit count';end if;
end;$$;
rollback;
select 'PASS: 이용 중지 직원 본인 탈퇴, 비관리자 원장의 직원·학생·학부모 강제 탈퇴, 상태 재조회·처리 기록, 기존 로그인 차단, 직원 권한 차단·보호 계정·동시 수정 보호. 검증 계정과 변경 사항 모두 롤백.'as result;
