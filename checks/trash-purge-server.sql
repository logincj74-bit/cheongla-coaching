begin;
do $$declare k integer;u uuid;begin
for k in 1..4 loop
u:=('04400000-0000-0000-0000-'||lpad(k::text,12,'0'))::uuid;
insert into auth.users(id,email,raw_user_meta_data)values(u,'tuition-reset-test-'||k||'@example.invalid',jsonb_build_object('full_name','학원비 검증','contact_phone','0100000000'||k));
insert into public.cheongla_profiles(id,full_name,role,approval_status,is_app_admin)values(u,'학원비 검증 '||k,case k when 1 then 'owner'when 2 then 'student'when 4 then 'manager'else 'parent'end,'approved',false)on conflict(id)do update set full_name=excluded.full_name,role=excluded.role,approval_status='approved',is_app_admin=false;
end loop;
insert into public.cheongla_parent_students(parent_id,student_id,created_by)values('04400000-0000-0000-0000-000000000003','04400000-0000-0000-0000-000000000002','04400000-0000-0000-0000-000000000001');
end;$$;
insert into public.cheongla_meal_forms(month,deadline,unit_price)values('2099-11-01','2099-10-28',7500);
insert into public.cheongla_meal_submissions(month,student_id,student_name,lunch,dinner)values('2099-11-01','04400000-0000-0000-0000-000000000002','영구삭제 검증','{}','{}');
set local role authenticated;
select set_config('request.jwt.claim.sub','04400000-0000-0000-0000-000000000001',true);
do $$declare st uuid:='04400000-0000-0000-0000-000000000002';n public.cheongla_tuition_notices%rowtype;s public.cheongla_meal_submissions%rowtype;tid uuid;trash uuid;deleted timestamptz;fv timestamptz;k integer;newid uuid;
begin
perform public.cheongla_save_tuition_settings_v2(st,'2099-01-01',450000,'repeat',null);
tid:=public.cheongla_save_tuition_notice(st,'2099-01-01','2099-01-01','','draft',null);
select * into n from public.cheongla_tuition_notices where id=tid;
begin perform public.cheongla_purge_tuition_draft(tid,n.updated_at);raise exception 'FAIL active purge';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
perform public.cheongla_reset_tuition_draft(tid,n.updated_at,false);
select * into n from public.cheongla_tuition_notices where id=tid;
perform public.cheongla_trash_tuition_draft(tid,n.updated_at,false);
select * into n from public.cheongla_tuition_notices where id=tid;
select * into s from public.cheongla_meal_submissions where month='2099-11-01'and student_id=st;
trash:=public.cheongla_trash_meal_submission(s.month,st,s.updated_at,null);
select (x->>'deleted_at')::timestamptz into deleted from jsonb_array_elements(public.cheongla_deleted_meal_submissions(s.month))x where x->>'id'=trash::text;
for k in 2..4 loop
 perform set_config('request.jwt.claim.sub','04400000-0000-0000-0000-'||lpad(k::text,12,'0'),true);
 begin perform public.cheongla_purge_tuition_draft(tid,n.updated_at);raise exception 'FAIL nonprincipal tuition';exception when insufficient_privilege then null;end;
 begin perform public.cheongla_purge_meal_submission(trash,deleted);raise exception 'FAIL nonprincipal meal';exception when insufficient_privilege then null;end;
end loop;
perform set_config('request.jwt.claim.sub','04400000-0000-0000-0000-000000000001',true);
begin perform public.cheongla_purge_tuition_draft(tid,null);raise exception 'FAIL stale tuition';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
begin perform public.cheongla_purge_meal_submission(trash,null);raise exception 'FAIL stale meal';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
perform public.cheongla_purge_tuition_draft(tid,n.updated_at);
if exists(select 1 from public.cheongla_tuition_notices where id=tid)then raise exception 'FAIL tuition not purged';end if;
begin perform public.cheongla_trash_tuition_draft(tid,n.updated_at,true);raise exception 'FAIL purged tuition restore';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
newid:=public.cheongla_save_tuition_notice(st,'2099-01-01','2099-01-01','','draft',null);
if newid=tid then raise exception 'FAIL reused purged ID';end if;
select updated_at into fv from public.cheongla_meal_forms where month=s.month;
perform set_config('request.jwt.claim.sub',st::text,true);
perform public.cheongla_submit_student_meal(st,s.month,'{}','{}','새 신청',null,fv);
perform set_config('request.jwt.claim.sub','04400000-0000-0000-0000-000000000001',true);
perform public.cheongla_purge_meal_submission(trash,deleted);
if jsonb_array_length(public.cheongla_deleted_meal_submissions(s.month))<>0 then raise exception 'FAIL meal trash not empty';end if;
if not exists(select 1 from public.cheongla_meal_submissions where month=s.month and student_id=st and note='새 신청')then raise exception 'FAIL new meal removed';end if;
begin perform public.cheongla_restore_meal_submission(trash);raise exception 'FAIL purged meal restore';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
perform set_config('test.purged_tuition',tid::text,true);
end;$$;
reset role;
do $$begin
 if exists(select 1 from cheongla_private.tuition_draft_actions where notice_id=current_setting('test.purged_tuition')::uuid and snapshot<>'{}'::jsonb)then raise exception 'FAIL recoverable snapshot retained';end if;
 if(select count(*)from cheongla_private.trash_purge_events where actor_id='04400000-0000-0000-0000-000000000001')<>2 then raise exception 'FAIL purge audit';end if;
end;$$;
rollback;
select 'PASS: 학원비·도시락 휴지통 영구 삭제, 원장 권한·변경 충돌 보호, 복구 불가·새 작성·현재 신청 보존, 복구용 원본 제거·최소 처리 기록 보관. 합성 검증 데이터 롤백.'as result;
