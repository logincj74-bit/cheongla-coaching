begin;
do $$declare k integer;u uuid;begin
for k in 1..4 loop
u:=('03900000-0000-0000-0000-'||lpad(k::text,12,'0'))::uuid;
insert into auth.users(id,email,raw_user_meta_data)values(u,'tuition-program-test-'||k||'@example.invalid',jsonb_build_object('full_name','학원비 검증','contact_phone','0100000000'||k));
insert into public.cheongla_profiles(id,full_name,role,approval_status,is_app_admin)values(u,'학원비 검증 '||k,case k when 1 then 'manager'when 2 then 'student'else 'parent'end,'approved',false)on conflict(id)do update set full_name=excluded.full_name,role=excluded.role,approval_status='approved',is_app_admin=false;
end loop;
insert into public.cheongla_parent_students(parent_id,student_id,created_by)values('03900000-0000-0000-0000-000000000003','03900000-0000-0000-0000-000000000002','03900000-0000-0000-0000-000000000001');
end;$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','03900000-0000-0000-0000-000000000001',true);
do $$declare st uuid:='03900000-0000-0000-0000-000000000002';code text;fee integer;v timestamptz;n uuid;old_v timestamptz;expected_amount integer;bill public.cheongla_tuition_notices%rowtype;begin
foreach code in array array['repeat','school','civil','winter','summer']loop
fee:=case code when 'repeat'then 450000 when 'school'then 200000 when 'civil'then 350000 else 610000 end;
select(x->>'updated_at')::timestamptz into v from jsonb_array_elements(public.cheongla_tuition_students_v2())x where x->>'student_id'=st::text;
perform public.cheongla_save_tuition_settings_v2(st,'2099-01-01',fee,code,v);
select updated_at into old_v from public.cheongla_tuition_notices where student_id=st and billing_month='2099-01-01';
n:=public.cheongla_save_tuition_notice_v2(st,'2099-01-01','2099-01-01','검증용 안내','draft',old_v,case when code in('winter','summer')then 45 else null end,case when code in('winter','summer')then '2099-01-10'::date else null end);
select * into bill from public.cheongla_tuition_notices where id=n;
expected_amount:=case when code in('winter','summer')then 900000 else fee end;
if bill.amount<>expected_amount or bill.monthly_fee<>fee or bill.program<>code then raise exception 'FAIL program amount or type';end if;
if code in('winter','summer')and(bill.billable_days<>45 or bill.daily_fee<>20000 or bill.period_end<>'2099-02-23'::date)then raise exception 'FAIL camp days';end if;
end loop;
-- A 30-day camp charge is 600,000 while the unchanged base remains 610,000.
select updated_at into v from public.cheongla_tuition_notices where id=n;
perform public.cheongla_save_tuition_notice_v2(st,'2099-01-01','2099-01-01','30일 검증','draft',v,30,'2099-01-01');
select * into bill from public.cheongla_tuition_notices where id=n;
if bill.amount<>600000 or bill.monthly_fee<>610000 then raise exception 'FAIL base versus daily price';end if;
begin perform public.cheongla_save_tuition_notice_v2(st,'2099-01-01','2099-01-01','','draft',bill.updated_at,0,'2099-01-01');raise exception 'FAIL zero days';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
begin perform public.cheongla_save_tuition_notice_v2(st,'2099-01-01','2099-01-01','','draft',bill.updated_at,121,'2099-01-01');raise exception 'FAIL oversized days';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
begin perform public.cheongla_save_tuition_notice(st,'2099-01-01','2099-01-01','','draft',bill.updated_at);raise exception 'FAIL old camp calculation';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
select(x->>'updated_at')::timestamptz into v from jsonb_array_elements(public.cheongla_tuition_students_v2())x where x->>'student_id'=st::text;
begin perform public.cheongla_save_tuition_settings_v2(st,'2099-01-01',600000,'winter',v);raise exception 'FAIL wrong base';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
-- Cached clients may update a monthly fee; classification must follow the new amount.
select(x->>'updated_at')::timestamptz into v from jsonb_array_elements(public.cheongla_tuition_students_v2())x where x->>'student_id'=st::text;
perform public.cheongla_save_tuition_settings(st,'2099-01-01',350000,v);
if not exists(select 1 from jsonb_array_elements(public.cheongla_tuition_students_v2())x where x->>'student_id'=st::text and x->>'program'='civil')then raise exception 'FAIL legacy fee classification';end if;
-- Already calculated tuition retains its own program and base regardless of later settings.
perform public.cheongla_save_tuition_notice(st,'2099-01-01',bill.due_on,bill.note,'publish',bill.updated_at);
perform set_config('test.tuition_id',n::text,true);
end;$$;
select set_config('request.jwt.claim.sub','03900000-0000-0000-0000-000000000003',true);
do $$declare p jsonb;begin
if not exists(select 1 from public.cheongla_tuition_notices where id=current_setting('test.tuition_id')::uuid and amount=600000 and program='summer')then raise exception 'FAIL linked parent read';end if;
p:=public.cheongla_billing_list('2099-01-01');
if not exists(select 1 from jsonb_array_elements(p->'items')x where x->>'id'=current_setting('test.tuition_id')and x->'details'->>'program'='summer')then raise exception 'FAIL collection metadata';end if;
begin perform public.cheongla_save_tuition_settings_v2('03900000-0000-0000-0000-000000000002','2099-01-01',450000,'repeat',null);raise exception 'FAIL parent write';exception when insufficient_privilege then null;end;
end;$$;
select set_config('request.jwt.claim.sub','03900000-0000-0000-0000-000000000004',true);
do $$begin if exists(select 1 from public.cheongla_tuition_notices where id=current_setting('test.tuition_id')::uuid)then raise exception 'FAIL unrelated parent read';end if;end;$$;
reset role;
rollback;
select 'PASS: 재수생 45만·재학생 20만·공시생 35만, 윈터/썸머 기본 61만·일 2만, 30일 60만·45일 90만 및 월간 경계, 부모 열람·작성 차단, 저장 기준 유지. 검증 내용 전부 롤백.'as result;
