begin;
do $$declare k integer;u uuid;begin
for k in 1..4 loop
u:=('04100000-0000-0000-0000-'||lpad(k::text,12,'0'))::uuid;
insert into auth.users(id,email,raw_user_meta_data)values(u,'tuition-reset-test-'||k||'@example.invalid',jsonb_build_object('full_name','학원비 검증','contact_phone','0100000000'||k));
insert into public.cheongla_profiles(id,full_name,role,approval_status,is_app_admin)values(u,'학원비 검증 '||k,case k when 1 then 'manager'when 2 then 'student'else 'parent'end,'approved',false)on conflict(id)do update set full_name=excluded.full_name,role=excluded.role,approval_status='approved',is_app_admin=false;
end loop;
insert into public.cheongla_parent_students(parent_id,student_id,created_by)values('04100000-0000-0000-0000-000000000003','04100000-0000-0000-0000-000000000002','04100000-0000-0000-0000-000000000001');
end;$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','04100000-0000-0000-0000-000000000001',true);
do $$
#variable_conflict use_variable
declare st uuid:='04100000-0000-0000-0000-000000000002';n public.cheongla_tuition_notices%rowtype;id uuid;v timestamptz;begin
perform public.cheongla_save_tuition_settings_v2(st,'2099-01-01',450000,'repeat',null);
id:=public.cheongla_save_tuition_notice(st,'2099-01-01','2099-01-01','초기화 검증','draft',null);
select * into n from public.cheongla_tuition_notices where cheongla_tuition_notices.id=id;
perform set_config('request.jwt.claim.sub','04100000-0000-0000-0000-000000000003',true);
begin perform public.cheongla_reset_tuition_draft(id,n.updated_at,false);raise exception 'FAIL parent reset';exception when insufficient_privilege then null;end;
perform set_config('request.jwt.claim.sub','04100000-0000-0000-0000-000000000001',true);
perform public.cheongla_reset_tuition_draft(id,n.updated_at,false);
select * into n from public.cheongla_tuition_notices where cheongla_tuition_notices.id=id;
if n.archived_at is null or n.amount<>450000 then raise exception 'FAIL archive preserves data';end if;
if exists(select 1 from jsonb_array_elements(public.cheongla_billing_list('2099-01-01')->'items')x where x->>'id'=id::text)then raise exception 'FAIL archive still in collection';end if;
begin perform public.cheongla_save_tuition_notice(st,'2099-01-01',n.due_on,n.note,'publish',n.updated_at);raise exception 'FAIL archived publish';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
perform public.cheongla_reset_tuition_draft(id,n.updated_at,true);
select * into n from public.cheongla_tuition_notices where cheongla_tuition_notices.id=id;
if n.archived_at is not null then raise exception 'FAIL restore';end if;
v:=n.updated_at;
perform public.cheongla_reset_tuition_draft(id,n.updated_at,false);
begin perform public.cheongla_reset_tuition_draft(id,v,true);raise exception 'FAIL stale reset';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
-- Creating a new draft reuses the hidden row without exposing the old version to the editor.
perform public.cheongla_save_tuition_notice(st,'2099-01-01','2099-01-02','새 초안','draft',null);
select * into n from public.cheongla_tuition_notices where cheongla_tuition_notices.id=id;
if n.archived_at is not null or n.note<>'새 초안'then raise exception 'FAIL recreate';end if;
perform public.cheongla_save_tuition_notice(st,'2099-01-01',n.due_on,n.note,'publish',n.updated_at);
select * into n from public.cheongla_tuition_notices where cheongla_tuition_notices.id=id;
begin perform public.cheongla_reset_tuition_draft(id,n.updated_at,false);raise exception 'FAIL published reset';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
perform public.cheongla_set_fee_payment('tuition',id,true,n.updated_at,null);
perform public.cheongla_save_tuition_notice(st,'2099-01-01',n.due_on,n.note,'withdraw',n.updated_at);
select * into n from public.cheongla_tuition_notices where cheongla_tuition_notices.id=id;
begin perform public.cheongla_reset_tuition_draft(id,n.updated_at,false);raise exception 'FAIL paid reset';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
end;$$;
reset role;
do $$begin if(select count(*)from cheongla_private.tuition_draft_actions where notice_id in(select id from public.cheongla_tuition_notices where student_id='04100000-0000-0000-0000-000000000002'))<>3 then raise exception 'FAIL audit';end if;end;$$;
rollback;
select 'PASS: 초안 초기화·복구·새 작성, 목록 제외, 관리자 권한, 게시·수납·동시 수정 차단. 검증 데이터 롤백.'as result;
