-- 008 실행 후 추가 실행. 기존 게시 안내의 금액은 유지됩니다.
begin;
alter table public.cheongla_tuition_notices
 add column if not exists daily_fee integer check(daily_fee between 0 and 333333);
create or replace function public.cheongla_save_tuition_notice(
 target_student uuid,target_month date,payment_due date,notice_note text,notice_action text,
 expected_updated_at timestamptz default null)
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
 if first_day>last_day then raise exception '등록일 이전 달은 청구할 수 없습니다.';end if;
 days_in_month=extract(day from last_day)::integer;
 days_to_bill=last_day-first_day+1;
 day_rate=round(cfg.monthly_fee::numeric/30)::integer;
 insert into public.cheongla_tuition_notices(student_id,student_name,billing_month,period_start,period_end,
 monthly_fee,billable_days,month_days,amount,due_on,note,daily_fee)
 values(target_student,student_label,target_month,first_day,last_day,cfg.monthly_fee,days_to_bill,
 days_in_month,case when first_day=target_month then cfg.monthly_fee
 else day_rate*days_to_bill end,payment_due,notice_note,day_rate)
 on conflict(student_id,billing_month) do update set student_name=excluded.student_name,
 period_start=excluded.period_start,period_end=excluded.period_end,monthly_fee=excluded.monthly_fee,
 billable_days=excluded.billable_days,month_days=excluded.month_days,amount=excluded.amount,
 due_on=excluded.due_on,note=excluded.note,daily_fee=excluded.daily_fee,updated_at=clock_timestamp()
 returning id into result_id;return result_id;
end;
$$;
revoke all on function public.cheongla_save_tuition_notice(uuid,date,date,text,text,timestamptz)
 from public,anon,authenticated;
grant execute on function public.cheongla_save_tuition_notice(uuid,date,date,text,text,timestamptz)
 to authenticated;
notify pgrst,'reload schema';
commit;
