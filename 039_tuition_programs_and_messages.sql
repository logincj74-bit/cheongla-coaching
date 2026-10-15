begin;
alter table public.cheongla_tuition_settings add column if not exists program text not null default 'custom'check(program in('repeat','school','winter','summer','civil','custom'));
update public.cheongla_tuition_settings set program=case monthly_fee when 450000 then 'repeat'when 200000 then 'school'when 350000 then 'civil'else 'custom'end where program='custom';
alter table public.cheongla_tuition_notices add column if not exists program text not null default 'custom'check(program in('repeat','school','winter','summer','civil','custom'));
alter table public.cheongla_tuition_notices add column if not exists calculation_basis text not null default 'monthly'check(calculation_basis in('monthly','daily'));
update public.cheongla_tuition_notices set program=case monthly_fee when 450000 then 'repeat'when 200000 then 'school'when 350000 then 'civil'else 'custom'end where program='custom';
do $$declare c record;begin for c in select conname from pg_constraint where conrelid='public.cheongla_tuition_notices'::regclass and contype='c'and pg_get_constraintdef(oid)like '%billable_days%'loop execute format('alter table public.cheongla_tuition_notices drop constraint %I',c.conname);end loop;end;$$;
alter table public.cheongla_tuition_notices drop constraint if exists tuition_period_order;
alter table public.cheongla_tuition_notices add constraint tuition_days_range check(billable_days between 1 and 120),add constraint tuition_period_order check(period_start<=period_end);
create or replace function public.cheongla_tuition_students_v2()returns jsonb language plpgsql stable security definer set search_path=''as $$
begin
 if not cheongla_private.can_manage_tuition()then raise exception '원장·실장만 등록 정보를 관리할 수 있습니다.'using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(q)order by q.student_name,q.student_id)from(select p.id student_id,p.full_name student_name,s.enrolled_on,s.monthly_fee,s.updated_at,s.program from public.cheongla_profiles p left join public.cheongla_tuition_settings s on s.student_id=p.id where p.role='student'and p.approval_status='approved'and p.membership_state='active')q),'[]'::jsonb);
end;$$;
create or replace function public.cheongla_save_tuition_settings_v2(target_student uuid,enrollment_date date,fee integer,student_program text,expected_updated_at timestamptz)returns uuid language plpgsql security definer set search_path=''as $$
declare expected_fee integer;
begin
 if student_program is null or student_program not in('repeat','school','winter','summer','civil','custom')then raise exception '학원비 유형을 선택해 주세요.';end if;
 expected_fee:=case student_program when 'repeat'then 450000 when 'school'then 200000 when 'winter'then 610000 when 'summer'then 610000 when 'civil'then 350000 else fee end;
 if fee is distinct from expected_fee then raise exception '유형별 기본 원비를 확인해 주세요. 다른 금액은 별도 금액을 선택해 주세요.';end if;
 perform public.cheongla_save_tuition_settings(target_student,enrollment_date,fee,expected_updated_at);
 update public.cheongla_tuition_settings set program=student_program,updated_at=clock_timestamp()where student_id=target_student;
 return target_student;
end;$$;
create or replace function public.cheongla_save_tuition_notice_v2(
 target_student uuid,target_month date,payment_due date,notice_note text,notice_action text,
 expected_updated_at timestamptz,usage_days integer,usage_start date)
returns uuid language plpgsql security definer set search_path='' as $$
declare cfg public.cheongla_tuition_settings%rowtype;
 old_notice public.cheongla_tuition_notices%rowtype;
 student_label text;last_day date;first_day date;days_in_month integer;days_to_bill integer;day_rate integer;result_id uuid;
begin
 if not cheongla_private.can_manage_tuition() then
  raise exception '실장과 앱 관리자만 납부 안내를 관리할 수 있습니다.' using errcode='42501';
 end if;
 select full_name into student_label from public.cheongla_profiles where id=target_student
 and role='student' and approval_status='approved' for update;
 if not found then raise exception '승인된 재원생을 선택해 주세요.';end if;
 if target_month is null or extract(day from target_month)<>1
 or notice_action is null or notice_action not in ('draft','publish','withdraw') then
  raise exception '청구 월과 처리 내용을 확인해 주세요.';end if;
 select * into old_notice from public.cheongla_tuition_notices
 where student_id=target_student and billing_month=target_month for update;
 if old_notice.updated_at is distinct from expected_updated_at then
  raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 처리해 주세요.';end if;
 if notice_action='withdraw' then
  if old_notice.id is null or old_notice.status<>'published' then raise exception '게시된 안내가 없습니다.';end if;
  update public.cheongla_tuition_notices set status='draft',published_at=null,updated_at=clock_timestamp()
  where id=old_notice.id returning id into result_id;return result_id;
 end if;
 if old_notice.status='published' then raise exception '먼저 게시를 취소한 뒤 수정해 주세요.';end if;
 if notice_action='publish' then
  if old_notice.id is null then raise exception '계산한 초안을 먼저 저장해 주세요.';end if;
  if old_notice.daily_fee is null then raise exception '변경된 30일 기준으로 초안 계산·저장을 다시 눌러 주세요.';end if;
  update public.cheongla_tuition_notices set status='published',published_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=old_notice.id returning id into result_id;return result_id;
 end if;
 if payment_due is null or notice_note is null or length(notice_note)>2000 then
  raise exception '납부기한과 안내 내용을 확인해 주세요.';end if;
 select * into cfg from public.cheongla_tuition_settings where student_id=target_student for update;
 if not found then raise exception '등록일과 월 학원비를 먼저 저장해 주세요.';end if;
 last_day=(target_month+interval '1 month'-interval '1 day')::date;
 first_day=greatest(target_month,cfg.enrolled_on);
 if cfg.program not in('winter','summer')and first_day>last_day then raise exception '등록일 이전 달은 청구할 수 없습니다.';end if;
 days_in_month=extract(day from last_day)::integer;
 days_to_bill=last_day-first_day+1;
 day_rate=round(cfg.monthly_fee::numeric/30)::integer;
 if cfg.program in('winter','summer')then
  if usage_days is null or usage_days not between 1 and 120 or usage_start is null or usage_start<cfg.enrolled_on then raise exception '이용 시작일과 이용일수(1~120일)를 입력해 주세요.';end if;
  first_day:=usage_start;last_day:=usage_start+usage_days-1;days_to_bill:=usage_days;day_rate:=20000;
 end if;
 insert into public.cheongla_tuition_notices(student_id,student_name,billing_month,period_start,period_end,
 monthly_fee,billable_days,month_days,amount,due_on,note,daily_fee,program,calculation_basis)
 values(target_student,student_label,target_month,first_day,last_day,cfg.monthly_fee,days_to_bill,
 days_in_month,case when cfg.program in('winter','summer')then day_rate*days_to_bill when first_day=target_month then cfg.monthly_fee
 else day_rate*days_to_bill end,payment_due,notice_note,day_rate,cfg.program,case when cfg.program in('winter','summer')then 'daily'else 'monthly'end)
 on conflict(student_id,billing_month) do update set student_name=excluded.student_name,
 period_start=excluded.period_start,period_end=excluded.period_end,monthly_fee=excluded.monthly_fee,
 billable_days=excluded.billable_days,month_days=excluded.month_days,amount=excluded.amount,
 due_on=excluded.due_on,note=excluded.note,daily_fee=excluded.daily_fee,program=excluded.program,calculation_basis=excluded.calculation_basis,updated_at=clock_timestamp()
 returning id into result_id;return result_id;
end;
$$;
create or replace function public.cheongla_save_tuition_notice(target_student uuid,target_month date,payment_due date,notice_note text,notice_action text,expected_updated_at timestamptz default null)returns uuid language plpgsql security definer set search_path=''as $$
begin return public.cheongla_save_tuition_notice_v2(target_student,target_month,payment_due,notice_note,notice_action,expected_updated_at,null,null);end;$$;
revoke all on function public.cheongla_tuition_students_v2()from public,anon,authenticated;
grant execute on function public.cheongla_tuition_students_v2()to authenticated;
revoke all on function public.cheongla_save_tuition_settings_v2(uuid,date,integer,text,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_save_tuition_settings_v2(uuid,date,integer,text,timestamptz)to authenticated;
revoke all on function public.cheongla_save_tuition_notice_v2(uuid,date,date,text,text,timestamptz,integer,date)from public,anon,authenticated;
grant execute on function public.cheongla_save_tuition_notice_v2(uuid,date,date,text,text,timestamptz,integer,date)to authenticated;
create or replace view cheongla_private.collection_notices as
 select 'tuition'::text fee_kind,t.id,t.student_id,t.student_name,t.billing_month,t.billing_month::text||' '||case t.program when 'repeat'then '재수생 학원비'when 'school'then '재학생 학원비'when 'winter'then '윈터스쿨 학원비'when 'summer'then '썸머스쿨 학원비'when 'civil'then '공시생 학원비'else '학원비'end as label,t.amount,t.due_on,t.note,t.status,t.updated_at,true as eligible,true as source_current,to_jsonb(t)as details from public.cheongla_tuition_notices t
 union all
 select 'exam',e.id,e.student_id,e.student_name,date_trunc('month',e.exam_on)::date,e.exam_title||' 모의고사비',e.amount,e.due_on,e.note,e.status,e.updated_at,exists(select 1 from public.cheongla_exam_applications a join public.cheongla_exams x on x.id=a.exam_id where a.exam_id=e.exam_id and a.student_id=e.student_id and a.status='registered' and to_jsonb(x)->>'deleted_at' is null),true,to_jsonb(e)from public.cheongla_exam_fee_notices e
 union all
 select 'meal',b.id,b.student_id,b.student_name,b.month,b.month::text||' 도시락비',b.amount,b.due_on,b.note,b.status,b.updated_at,true,exists(select 1 from public.cheongla_meal_submissions s where s.month=b.month and s.student_id=b.student_id and s.updated_at=b.source_updated_at),to_jsonb(b)from public.cheongla_meal_bills b;
create or replace function cheongla_private.sync_legacy_tuition_program()returns trigger language plpgsql set search_path=''as $$
begin
 if tg_op='INSERT'then
  if new.program<>'custom'then return new;end if;
 elsif new.monthly_fee is not distinct from old.monthly_fee or new.program is distinct from old.program then return new;
 end if;
 new.program:=case new.monthly_fee when 450000 then 'repeat'when 200000 then 'school'when 350000 then 'civil'else 'custom'end;
 return new;
end;$$;
revoke all on function cheongla_private.sync_legacy_tuition_program()from public,anon,authenticated;
drop trigger if exists tuition_legacy_program_sync on public.cheongla_tuition_settings;
create trigger tuition_legacy_program_sync before insert or update on public.cheongla_tuition_settings for each row execute function cheongla_private.sync_legacy_tuition_program();
notify pgrst,'reload schema';
commit;
