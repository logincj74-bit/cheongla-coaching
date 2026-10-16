begin;
do $$declare k integer;u uuid;begin
for k in 1..5 loop
u:=('04500000-0000-0000-0000-'||lpad(k::text,12,'0'))::uuid;
insert into auth.users(id,email,raw_user_meta_data)values(u,'tuition-reset-test-'||k||'@example.invalid',jsonb_build_object('full_name','학원비 검증','contact_phone','0100000000'||k));
insert into public.cheongla_profiles(id,full_name,role,approval_status,is_app_admin)values(u,'학원비 검증 '||k,case k when 1 then 'owner'when 2 then 'student'when 5 then 'student'when 4 then 'manager'else 'parent'end,'approved',false)on conflict(id)do update set full_name=excluded.full_name,role=excluded.role,approval_status='approved',is_app_admin=false;
end loop;
insert into public.cheongla_parent_students(parent_id,student_id,created_by)values('04500000-0000-0000-0000-000000000003','04500000-0000-0000-0000-000000000002','04500000-0000-0000-0000-000000000001');
end;$$;
insert into public.cheongla_meal_forms(month,deadline,unit_price)values('2099-01-01','2098-12-28',7500);
insert into public.cheongla_meal_submissions(month,student_id,student_name)values('2099-01-01','04500000-0000-0000-0000-000000000002','검증1'),('2099-01-01','04500000-0000-0000-0000-000000000005','검증2');
set local role authenticated;
select set_config('request.jwt.claim.sub','04500000-0000-0000-0000-000000000001',true);
do $$declare st uuid;n public.cheongla_tuition_notices%rowtype;s public.cheongla_meal_submissions%rowtype;tid uuid;items jsonb;bad jsonb;tids uuid[]:='{}';mids uuid[]:='{}';k integer;result integer;history jsonb;
begin
for k in 2..5 loop
 if k not in(2,5)then continue;end if;
 st:=('04500000-0000-0000-0000-'||lpad(k::text,12,'0'))::uuid;
 perform public.cheongla_save_tuition_settings_v2(st,'2099-01-01',450000,'repeat',null);
 tid:=public.cheongla_save_tuition_notice(st,'2099-01-01','2099-01-01','','draft',null);tids:=array_append(tids,tid);
 select * into n from public.cheongla_tuition_notices where id=tid;
 perform public.cheongla_reset_tuition_draft(tid,n.updated_at,false);
 select * into n from public.cheongla_tuition_notices where id=tid;
 perform public.cheongla_trash_tuition_draft(tid,n.updated_at,false);
 select * into s from public.cheongla_meal_submissions where month='2099-01-01'and student_id=st;
 mids:=array_append(mids,public.cheongla_trash_meal_submission(s.month,st,s.updated_at,null));
end loop;
select jsonb_agg(jsonb_build_object('id',id,'version',updated_at)order by id)into items from public.cheongla_tuition_notices where id=any(tids);
for k in 2..4 loop
 perform set_config('request.jwt.claim.sub','04500000-0000-0000-0000-'||lpad(k::text,12,'0'),true);
 begin perform public.cheongla_empty_trash('tuition','2099-01-01',items);raise exception 'FAIL nonprincipal bulk';exception when insufficient_privilege then null;end;
 begin perform public.cheongla_trash_history('tuition');raise exception 'FAIL nonprincipal history';exception when insufficient_privilege then null;end;
end loop;
perform set_config('request.jwt.claim.sub','04500000-0000-0000-0000-000000000001',true);
begin perform public.cheongla_empty_trash('tuition','2099-01-01',jsonb_build_array(items->0));raise exception 'FAIL partial list';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
bad:=jsonb_set(items,'{1,version}','null');
begin perform public.cheongla_empty_trash('tuition','2099-01-01',bad);raise exception 'FAIL stale batch';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
if(select count(*)from public.cheongla_tuition_notices where id=any(tids))<>2 then raise exception 'FAIL partial commit';end if;
result:=public.cheongla_empty_trash('tuition','2099-01-01',items);
if result<>2 or exists(select 1 from public.cheongla_tuition_notices where id=any(tids))then raise exception 'FAIL tuition bulk result';end if;
history:=public.cheongla_trash_history('tuition');
if(select count(*)from jsonb_array_elements(history)x where(x->>'source_id')::uuid=any(tids)and x->>'action'='purge'and x->>'actor_name'='학원비 검증 1')<>2 then raise exception 'FAIL purge actor history';end if;
select jsonb_agg(jsonb_build_object('id',x->>'id','version',x->>'deleted_at'))into items from jsonb_array_elements(public.cheongla_deleted_meal_submissions('2099-01-01'))x;
result:=public.cheongla_empty_trash('meal','2099-01-01',items);
if result<>2 or jsonb_array_length(public.cheongla_deleted_meal_submissions('2099-01-01'))<>0 then raise exception 'FAIL meal bulk result';end if;
history:=public.cheongla_trash_history('meal');
if(select count(*)from jsonb_array_elements(history)x where(x->>'source_id')::uuid=any(mids)and x->>'action'='delete')<>2 then raise exception 'FAIL deletion history lost';end if;
if(select count(*)from jsonb_array_elements(history)x where(x->>'source_id')::uuid=any(mids)and x->>'action'='purge')<>2 then raise exception 'FAIL meal purge history';end if;
end;$$;
reset role;
rollback;
select 'PASS: 선택 월 휴지통 전체 비우기, 목록·버전 충돌 시 전체 롤백, 원장 전용 처리자·시각·삭제·복구 이력, 영구 삭제 후 이력 보존. 검증 자료 롤백.'as result;
