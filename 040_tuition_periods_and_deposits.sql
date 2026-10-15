begin;
alter table public.cheongla_tuition_notices
 add column if not exists excluded_dates date[] not null default '{}',
 add column if not exists deposit_credit integer not null default 0,
 add column if not exists deposit_season integer,
 add column if not exists deposit_confirmed_by uuid,
 add column if not exists deposit_confirmed_at timestamptz;
alter table public.cheongla_tuition_notices drop constraint if exists tuition_deposit_valid;
alter table public.cheongla_tuition_notices add constraint tuition_deposit_valid check(deposit_credit=0 or(deposit_credit=100000 and program in('winter','summer')and deposit_season is not null and deposit_confirmed_by is not null and deposit_confirmed_at is not null));
create unique index if not exists tuition_deposit_once_per_season on public.cheongla_tuition_notices(student_id,program,deposit_season)where deposit_credit>0;
create or replace function public.cheongla_save_tuition_notice_v3(
 target_student uuid,target_month date,payment_due date,notice_note text,notice_action text,
 expected_updated_at timestamptz,billing_basis text,usage_start date,usage_end date,excluded_days date[],apply_deposit boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare cfg public.cheongla_tuition_settings%rowtype;
 old_notice public.cheongla_tuition_notices%rowtype;
 clean_excluded date[];credit integer:=0;season integer;total_amount integer;basis text;student_label text;last_day date;first_day date;days_in_month integer;days_to_bill integer;day_rate integer;result_id uuid;
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
 if billing_basis='monthly'and cfg.program not in('winter','summer')and first_day>last_day then raise exception '등록일 이전 달은 청구할 수 없습니다.';end if;
 days_in_month=extract(day from last_day)::integer;
 days_to_bill=last_day-first_day+1;
 day_rate=round(cfg.monthly_fee::numeric/30)::integer;
 basis:=case when cfg.program in('winter','summer')then 'daily'else billing_basis end;
 if basis is null or basis not in('monthly','daily')then raise exception '계산 방식을 선택해 주세요.';end if;
 clean_excluded:=coalesce((select array_agg(distinct d order by d)from unnest(excluded_days)d),'{}'::date[]);
 if basis='daily'then
  if usage_start is null or usage_end is null or usage_start<cfg.enrolled_on or usage_end<usage_start or usage_end-usage_start+1>120 then raise exception '등록일 이후 시작일과 종료일을 입력해 주세요. 전체 기간은 1~120일입니다.';end if;
  if exists(select 1 from unnest(clean_excluded)d where d is null or d<usage_start or d>usage_end)then raise exception '제외 날짜는 선택한 이용 기간 안에 있어야 합니다.';end if;
  first_day:=usage_start;last_day:=usage_end;days_to_bill:=last_day-first_day+1-cardinality(clean_excluded);
  if days_to_bill<1 then raise exception '실제 이용일이 하루 이상이어야 합니다.';end if;
  if cfg.program in('winter','summer')then day_rate:=20000;end if;
 elsif cardinality(clean_excluded)>0 then raise exception '제외 날짜는 기간별 계산에서 선택해 주세요.';
 end if;
 total_amount:=case when basis='monthly'and first_day=target_month then cfg.monthly_fee else day_rate*days_to_bill end;
 if coalesce(apply_deposit,false)then
  if cfg.program not in('winter','summer')then raise exception '예약금 차감은 윈터·썸머스쿨에서만 가능합니다.';end if;
  credit:=100000;
  season:=extract(year from first_day)::integer-case when cfg.program='winter'and extract(month from first_day)<=3 then 1 else 0 end;
  if total_amount<credit then raise exception '예약금이 계산한 교육비보다 큽니다. 차감 여부를 확인해 주세요.';end if;
  if exists(select 1 from public.cheongla_tuition_notices t where t.student_id=target_student and t.program=cfg.program and t.deposit_season=season and t.deposit_credit>0 and t.id is distinct from old_notice.id)then raise exception '이 학생의 같은 스쿨 시즌 예약금은 다른 청구에서 이미 차감했습니다.';end if;
 end if;
 insert into public.cheongla_tuition_notices(student_id,student_name,billing_month,period_start,period_end,
 monthly_fee,billable_days,month_days,amount,due_on,note,daily_fee,program,calculation_basis,excluded_dates,deposit_credit,deposit_season,deposit_confirmed_by,deposit_confirmed_at)
 values(target_student,student_label,target_month,first_day,last_day,cfg.monthly_fee,days_to_bill,
 days_in_month,total_amount-credit,payment_due,notice_note,day_rate,cfg.program,basis,clean_excluded,credit,season,
 case when credit>0 then auth.uid()end,case when credit>0 then clock_timestamp()end)
 on conflict(student_id,billing_month) do update set student_name=excluded.student_name,
 period_start=excluded.period_start,period_end=excluded.period_end,monthly_fee=excluded.monthly_fee,
 billable_days=excluded.billable_days,month_days=excluded.month_days,amount=excluded.amount,
 due_on=excluded.due_on,note=excluded.note,daily_fee=excluded.daily_fee,program=excluded.program,calculation_basis=excluded.calculation_basis,excluded_dates=excluded.excluded_dates,deposit_credit=excluded.deposit_credit,deposit_season=excluded.deposit_season,deposit_confirmed_by=excluded.deposit_confirmed_by,deposit_confirmed_at=excluded.deposit_confirmed_at,updated_at=clock_timestamp()
 returning id into result_id;return result_id;
end;
$$;
create or replace function public.cheongla_save_tuition_notice_v2(target_student uuid,target_month date,payment_due date,notice_note text,notice_action text,expected_updated_at timestamptz,usage_days integer,usage_start date)
returns uuid language plpgsql security definer set search_path=''as $$
begin
 if not cheongla_private.can_manage_tuition()then raise exception '원장·실장만 납부 안내를 관리할 수 있습니다.'using errcode='42501';end if;
 if notice_action='draft'and exists(select 1 from public.cheongla_tuition_settings where student_id=target_student and program in('winter','summer'))then raise exception '앱을 새로고침한 뒤 실제 시작일·종료일·제외 날짜를 입력해 주세요.';end if;
 return public.cheongla_save_tuition_notice_v3(target_student,target_month,payment_due,notice_note,notice_action,expected_updated_at,'monthly',null,null,'{}',false);
end;$$;
revoke all on function public.cheongla_save_tuition_notice_v3(uuid,date,date,text,text,timestamptz,text,date,date,date[],boolean)from public,anon,authenticated;
grant execute on function public.cheongla_save_tuition_notice_v3(uuid,date,date,text,text,timestamptz,text,date,date,date[],boolean)to authenticated;
notify pgrst,'reload schema';
commit;
