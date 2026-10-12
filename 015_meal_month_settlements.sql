-- 기존 도시락 SQL까지 실행한 후, 전체를 한 번에 실행하세요.
begin;
create table if not exists public.cheongla_meal_bills (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.cheongla_profiles(id),
 student_name text not null,billing_month date not null check(extract(day from billing_month)=1),
 lunch_count integer not null,dinner_count integer not null,
 meal_ids uuid[] not null default '{}',unit_price integer not null default 7500,
 adjustment integer not null default 0 check(adjustment between 0 and 1000000),
 adjustment_method text not null check(adjustment_method in ('credit','refund')),
 amount integer not null check(amount>=0),refund_amount integer not null check(refund_amount>=0),
 due_on date not null,note text not null default '' check(length(note)<=2000),
 status text not null default 'draft' check(status in ('draft','published')),
 paid_at timestamptz,refunded_at timestamptz,updated_by uuid references public.cheongla_profiles(id),
 updated_at timestamptz not null default clock_timestamp(),unique(student_id,billing_month)
);
-- 하나의 전월 취소분을 차감과 환불로 중복 처리하지 않습니다.
create table if not exists public.cheongla_meal_adjustment_ledger (
 student_id uuid not null references public.cheongla_profiles(id),source_month date not null,
 bill_id uuid not null unique references public.cheongla_meal_bills(id),
 primary key(student_id,source_month)
);
alter table public.cheongla_meal_bills enable row level security;
alter table public.cheongla_meal_adjustment_ledger enable row level security;
revoke all on public.cheongla_meal_bills,public.cheongla_meal_adjustment_ledger from anon,authenticated;
grant select on public.cheongla_meal_bills to authenticated;
drop policy if exists cheongla_meal_bill_read on public.cheongla_meal_bills;
create policy cheongla_meal_bill_read on public.cheongla_meal_bills for select to authenticated
 using ((select cheongla_private.can_manage_meals()) or
 (status='published' and (select cheongla_private.is_parent_of(student_id))));

create or replace function public.cheongla_meal_month_accounts(target_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not cheongla_private.can_manage_meals() then raise exception '실장과 앱 관리자만 정산 명단을 볼 수 있습니다.' using errcode='42501';end if;
 if target_month is null or extract(day from target_month)<>1 then raise exception '신청 월을 확인해 주세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.student_name,r.student_id),'[]'::jsonb) into result from (
 select p.id student_id,p.full_name student_name,
 (select count(*) from public.cheongla_meal_orders o join public.cheongla_meals m on m.id=o.meal_id
 where o.student_id=p.id and o.status='registered' and m.meal_type='lunch' and m.meal_on>=target_month and m.meal_on<(target_month+interval '1 month')::date) lunch_count,
 (select count(*) from public.cheongla_meal_orders o join public.cheongla_meals m on m.id=o.meal_id
 where o.student_id=p.id and o.status='registered' and m.meal_type='dinner' and m.meal_on>=target_month and m.meal_on<(target_month+interval '1 month')::date) dinner_count,
 (select count(*) from public.cheongla_meal_orders o join public.cheongla_meals m on m.id=o.meal_id
 where o.student_id=p.id and o.status='canceled' and m.meal_on>=(target_month-interval '1 month')::date and m.meal_on<target_month) previous_canceled,
 (select to_jsonb(b) from public.cheongla_meal_bills b where b.student_id=p.id and b.billing_month=target_month) bill
 from public.cheongla_profiles p where (p.role='student' and p.approval_status='approved')
 or exists(select 1 from public.cheongla_meal_bills b where b.student_id=p.id and b.billing_month=target_month)
 ) r;return result;
end;$$;

create or replace function public.cheongla_save_meal_bill(
 target_student uuid,target_month date,bill_action text,payment_due date,
 cancellation_amount integer,cancellation_method text,prepayment_confirmed boolean,
 bill_note text,expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare old public.cheongla_meal_bills%rowtype;label text;ids uuid[];lc integer;dc integer;
 gross integer;deduction integer;refund integer;result_id uuid;source date;
begin
 if not cheongla_private.can_manage_meals() then raise exception '실장과 앱 관리자만 도시락 식비를 정산할 수 있습니다.' using errcode='42501';end if;
 if target_student is null or target_month is null or extract(day from target_month)<>1
 or bill_action is null or bill_action not in ('save','publish','withdraw','paid','refunded') then raise exception '학생, 월과 처리 방법을 확인해 주세요.';end if;
 perform pg_catalog.pg_advisory_xact_lock(7492055);
 select * into old from public.cheongla_meal_bills where student_id=target_student and billing_month=target_month for update;
 if old.updated_at is distinct from expected_updated_at then raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 확인해 주세요.';end if;
 if bill_action<>'save' and old.id is null then raise exception '먼저 정산 초안을 저장해 주세요.';end if;
 if bill_action='save' then
  if old.status='published' or old.paid_at is not null or old.refunded_at is not null then raise exception '게시·납부·환불 기록이 있는 안내는 바로 재계산할 수 없습니다. 미납 안내는 게시 취소 후 수정하세요.';end if;
  if payment_due is null or cancellation_amount is null or cancellation_amount not between 0 and 1000000
  or cancellation_method is null or cancellation_method not in ('credit','refund') or bill_note is null or length(bill_note)>2000 then raise exception '납부기한과 취소 정산액을 확인해 주세요.';end if;
  if cancellation_amount>0 and prepayment_confirmed is distinct from true then raise exception '전월 취소분의 실제 선납 여부와 미정산 여부를 먼저 확인해 주세요.';end if;
  select full_name into label from public.cheongla_profiles where id=target_student and role='student' and approval_status='approved';
  if not found then raise exception '승인된 학생을 선택해 주세요.';end if;
  -- 신청/취소와 같은 행 잠금을 사용해 정산 중 수량 변동을 막습니다.
  perform 1 from public.cheongla_meals where meal_on>=target_month and meal_on<(target_month+interval '1 month')::date order by id for update;
  select coalesce(array_agg(m.id order by m.id),'{}'::uuid[]),count(*) filter(where m.meal_type='lunch'),count(*) filter(where m.meal_type='dinner')
  into ids,lc,dc from public.cheongla_meal_orders o join public.cheongla_meals m on m.id=o.meal_id
  where o.student_id=target_student and o.status='registered' and m.meal_on>=target_month and m.meal_on<(target_month+interval '1 month')::date;
  gross=(lc+dc)*7500;deduction=case when cancellation_method='credit' then least(gross,cancellation_amount) else 0 end;
  refund=cancellation_amount-deduction;source=(target_month-interval '1 month')::date;
  if old.id is not null then delete from public.cheongla_meal_adjustment_ledger where bill_id=old.id;end if;
  insert into public.cheongla_meal_bills(student_id,student_name,billing_month,lunch_count,dinner_count,meal_ids,adjustment,adjustment_method,amount,refund_amount,due_on,note,updated_by)
  values(target_student,label,target_month,lc,dc,ids,cancellation_amount,cancellation_method,gross-deduction,refund,payment_due,bill_note,(select auth.uid()))
  on conflict(student_id,billing_month) do update set student_name=excluded.student_name,lunch_count=excluded.lunch_count,dinner_count=excluded.dinner_count,
  meal_ids=excluded.meal_ids,adjustment=excluded.adjustment,adjustment_method=excluded.adjustment_method,amount=excluded.amount,refund_amount=excluded.refund_amount,
  due_on=excluded.due_on,note=excluded.note,updated_by=excluded.updated_by,updated_at=clock_timestamp() returning id into result_id;
  if cancellation_amount>0 then insert into public.cheongla_meal_adjustment_ledger(student_id,source_month,bill_id) values(target_student,source,result_id);end if;
  return result_id;
 end if;
 if bill_action='publish' then
  if not exists(select 1 from public.cheongla_profiles where id=target_student and role='student' and approval_status='approved') then raise exception '학생 승인 상태를 확인해 주세요.';end if;
  perform 1 from public.cheongla_meals where meal_on>=target_month and meal_on<(target_month+interval '1 month')::date order by id for update;
  select coalesce(array_agg(m.id order by m.id),'{}'::uuid[]) into ids from public.cheongla_meal_orders o join public.cheongla_meals m on m.id=o.meal_id
  where o.student_id=target_student and o.status='registered' and m.meal_on>=target_month and m.meal_on<(target_month+interval '1 month')::date;
  if old.paid_at is null and old.meal_ids is distinct from ids then raise exception '신청 수량이 바뀌었습니다. 초안을 다시 계산한 뒤 게시하세요.';end if;
 elsif bill_action='paid' then
  if old.status<>'published' or old.paid_at is not null then raise exception '게시된 미납 안내에서 실제 입금 확인 후 처리하세요.';end if;
 elsif bill_action='refunded' then
  if old.status<>'published' or old.refund_amount=0 or old.refunded_at is not null then raise exception '게시된 환불 예정 안내에서 실제 환불 후 처리하세요.';end if;
 end if;
 update public.cheongla_meal_bills set status=case when bill_action='publish' then 'published' when bill_action='withdraw' then 'draft' else status end,
 paid_at=case when bill_action='paid' then clock_timestamp() else paid_at end,
 refunded_at=case when bill_action='refunded' then clock_timestamp() else refunded_at end,
 updated_by=(select auth.uid()),updated_at=clock_timestamp() where id=old.id;return old.id;
end;$$;
revoke all on function public.cheongla_meal_month_accounts(date),public.cheongla_save_meal_bill(uuid,date,text,date,integer,text,boolean,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_meal_month_accounts(date),public.cheongla_save_meal_bill(uuid,date,text,date,integer,text,boolean,text,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
