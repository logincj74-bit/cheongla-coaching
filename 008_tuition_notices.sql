-- 001~007 실행 후 추가 실행. 기존 계정과 질의응답은 유지됩니다.
begin;
create or replace function cheongla_private.can_manage_tuition()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and approval_status='approved' and (is_app_admin or role='manager'));
$$;
revoke all on function cheongla_private.can_manage_tuition() from public,anon,authenticated;
grant execute on function cheongla_private.can_manage_tuition() to authenticated;

create table if not exists public.cheongla_tuition_settings (
 student_id uuid primary key references public.cheongla_profiles(id) on delete cascade,
 enrolled_on date not null,
 monthly_fee integer not null check(monthly_fee between 0 and 10000000),
 updated_at timestamptz not null default clock_timestamp()
);
create table if not exists public.cheongla_tuition_notices (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.cheongla_profiles(id) on delete cascade,
 student_name text not null,
 billing_month date not null check(extract(day from billing_month)=1),
 period_start date not null,
 period_end date not null,
 monthly_fee integer not null check(monthly_fee between 0 and 10000000),
 billable_days integer not null check(billable_days between 1 and 31),
 month_days integer not null check(month_days between 28 and 31),
 amount integer not null check(amount between 0 and 10000000),
 due_on date not null,
 note text not null default '' check(length(note)<=2000),
 status text not null default 'draft' check(status in ('draft','published')),
 published_at timestamptz,
 updated_at timestamptz not null default clock_timestamp(),
 unique(student_id,billing_month),
 check(period_start<=period_end and billable_days<=month_days)
);
alter table public.cheongla_tuition_settings enable row level security;
alter table public.cheongla_tuition_notices enable row level security;
revoke all on public.cheongla_tuition_settings,public.cheongla_tuition_notices from anon,authenticated;
grant select on public.cheongla_tuition_notices to authenticated;

create or replace function cheongla_private.can_read_tuition(target_student uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=target_student
 and role='student' and approval_status='approved')
 and (exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and id=target_student and role='student' and approval_status='approved')
 or cheongla_private.is_parent_of(target_student));
$$;
revoke all on function cheongla_private.can_read_tuition(uuid) from public,anon,authenticated;
grant execute on function cheongla_private.can_read_tuition(uuid) to authenticated;
drop policy if exists cheongla_tuition_read on public.cheongla_tuition_notices;
create policy cheongla_tuition_read on public.cheongla_tuition_notices for select to authenticated
using ((select cheongla_private.can_manage_tuition())
 or (status='published' and (select cheongla_private.can_read_tuition(student_id))));

-- 실장에게 회원 권한 관리나 학습 질문 열람 권한을 추가하지 않습니다.
create or replace function public.cheongla_tuition_students()
returns table(student_id uuid,student_name text,enrolled_on date,monthly_fee integer,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_tuition() then
  raise exception '실장과 앱 관리자만 등록 정보를 관리할 수 있습니다.' using errcode='42501';
 end if;
 return query select p.id,p.full_name,s.enrolled_on,s.monthly_fee,s.updated_at
 from public.cheongla_profiles p left join public.cheongla_tuition_settings s on s.student_id=p.id
 where p.role='student' and p.approval_status='approved' order by p.full_name,p.id;
end;
$$;
create or replace function public.cheongla_save_tuition_settings(
 target_student uuid,enrollment_date date,fee integer,expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_stamp timestamptz;
begin
 if not cheongla_private.can_manage_tuition() then
  raise exception '실장과 앱 관리자만 등록 정보를 관리할 수 있습니다.' using errcode='42501';
 end if;
 perform 1 from public.cheongla_profiles where id=target_student and role='student'
 and approval_status='approved' for update;
 if not found then raise exception '승인된 재원생을 선택해 주세요.';end if;
 if enrollment_date is null or fee is null or fee<0 or fee>10000000 then
  raise exception '등록일과 월 학원비를 확인해 주세요.';end if;
 select updated_at into old_stamp from public.cheongla_tuition_settings where student_id=target_student for update;
 if old_stamp is distinct from expected_updated_at then
  raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 저장해 주세요.';end if;
 insert into public.cheongla_tuition_settings(student_id,enrolled_on,monthly_fee)
 values(target_student,enrollment_date,fee)
 on conflict(student_id) do update set enrolled_on=excluded.enrolled_on,
 monthly_fee=excluded.monthly_fee,updated_at=clock_timestamp();
 return target_student;
end;
$$;
create or replace function public.cheongla_save_tuition_notice(
 target_student uuid,target_month date,payment_due date,notice_note text,notice_action text,
 expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare cfg public.cheongla_tuition_settings%rowtype;
 old_notice public.cheongla_tuition_notices%rowtype;
 student_label text;last_day date;first_day date;days_in_month integer;days_to_bill integer;result_id uuid;
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
 insert into public.cheongla_tuition_notices(student_id,student_name,billing_month,period_start,period_end,
 monthly_fee,billable_days,month_days,amount,due_on,note)
 values(target_student,student_label,target_month,first_day,last_day,cfg.monthly_fee,days_to_bill,
 days_in_month,round(cfg.monthly_fee::numeric*days_to_bill/days_in_month)::integer,payment_due,notice_note)
 on conflict(student_id,billing_month) do update set student_name=excluded.student_name,
 period_start=excluded.period_start,period_end=excluded.period_end,monthly_fee=excluded.monthly_fee,
 billable_days=excluded.billable_days,month_days=excluded.month_days,amount=excluded.amount,
 due_on=excluded.due_on,note=excluded.note,updated_at=clock_timestamp()
 returning id into result_id;return result_id;
end;
$$;
revoke all on function public.cheongla_tuition_students() from public,anon,authenticated;
revoke all on function public.cheongla_save_tuition_settings(uuid,date,integer,timestamptz) from public,anon,authenticated;
revoke all on function public.cheongla_save_tuition_notice(uuid,date,date,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_tuition_students() to authenticated;
grant execute on function public.cheongla_save_tuition_settings(uuid,date,integer,timestamptz) to authenticated;
grant execute on function public.cheongla_save_tuition_notice(uuid,date,date,text,text,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
