-- 013 실행 후 추가 실행. 기존 신청 내역을 유지합니다.
begin;
alter table public.cheongla_meals drop constraint if exists cheongla_meals_check;
update public.cheongla_meals set deadline=(meal_on::timestamp at time zone 'Asia/Seoul'),updated_at=clock_timestamp()
 where deadline>(meal_on::timestamp at time zone 'Asia/Seoul');
alter table public.cheongla_meals drop constraint if exists cheongla_meals_before_day_check;
alter table public.cheongla_meals add constraint cheongla_meals_before_day_check
 check(deadline<=(meal_on::timestamp at time zone 'Asia/Seoul'));
alter table public.cheongla_meal_orders add column if not exists canceled_by uuid
 references public.cheongla_profiles(id) on delete set null;
alter table public.cheongla_meal_orders add column if not exists canceled_at timestamptz;
alter table public.cheongla_meal_orders add column if not exists cancel_channel text
 check(cancel_channel in ('oral','sms'));
create or replace function public.cheongla_save_meal(
 target_meal uuid,meal_kind text,meal_date date,application_deadline timestamptz,
 meal_body text,meal_status text,expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_meal public.cheongla_meals%rowtype;result_id uuid;
begin
 if not cheongla_private.can_manage_meals() then
  raise exception '실장과 앱 관리자만 도시락을 관리할 수 있습니다.' using errcode='42501';end if;
 if meal_kind is null or meal_kind not in ('lunch','dinner')
 or meal_date is null or application_deadline is null or meal_body is null or length(meal_body)>5000
 or meal_status is null or meal_status not in ('draft','open','closed') then
  raise exception '식사 구분, 식사일, 당일 신청 마감과 안내 내용을 확인해 주세요.';end if;
 if application_deadline>(meal_date::timestamp at time zone 'Asia/Seoul') then
  raise exception '신청 마감은 식사일이 시작되기 전으로 설정해 주세요.';end if;
 if target_meal is not null then
  select * into old_meal from public.cheongla_meals where id=target_meal for update;
  if not found then raise exception '해당 도시락이 없습니다.';end if;
 end if;
 if old_meal.updated_at is distinct from expected_updated_at then
  raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 저장해 주세요.';end if;
 if meal_status='open' and (old_meal.status is distinct from 'open'
 or old_meal.deadline is distinct from application_deadline) and application_deadline<=clock_timestamp() then
  raise exception '신청을 열려면 마감 시간을 현재보다 뒤로 설정해 주세요.';end if;
 if old_meal.id is not null and exists(select 1 from public.cheongla_meal_orders where meal_id=old_meal.id) then
  if meal_status='draft' then raise exception '신청 이력이 있는 도시락은 초안으로 되돌릴 수 없습니다. 마감으로 변경해 주세요.';end if;
  if old_meal.meal_type is distinct from meal_kind or old_meal.meal_on is distinct from meal_date then
   raise exception '신청 이력이 있는 도시락의 식사 구분과 날짜는 변경할 수 없습니다. 새 날짜로 등록해 주세요.';end if;
 end if;
 if target_meal is null then
  insert into public.cheongla_meals(meal_type,title,meal_on,deadline,body,status)
  values(meal_kind,case meal_kind when 'lunch' then '점심 도시락' else '저녁 도시락' end,meal_date,application_deadline,meal_body,meal_status) returning id into result_id;
 else
  update public.cheongla_meals set meal_type=meal_kind,title=case meal_kind when 'lunch' then '점심 도시락' else '저녁 도시락' end,meal_on=meal_date,deadline=application_deadline,
  body=meal_body,status=meal_status,updated_at=clock_timestamp() where id=target_meal returning id into result_id;
 end if;
 return result_id;
end;
$$;

create or replace function public.cheongla_open_meal_month(
 target_month date,lunch_weekdays integer[],dinner_weekdays integer[],meal_note text default '')
returns integer language plpgsql security definer set search_path='' as $$
declare result_count integer;
begin
 if not cheongla_private.can_manage_meals() then
  raise exception '실장과 앱 관리자만 월간 신청표를 열 수 있습니다.' using errcode='42501';end if;
 if target_month is null or extract(day from target_month)<>1 or meal_note is null or length(meal_note)>5000
 or lunch_weekdays is null or dinner_weekdays is null
 or exists(select 1 from unnest(lunch_weekdays||dinner_weekdays) v where v is null or v<0 or v>6) then
  raise exception '신청 월, 운영 요일과 안내 내용을 확인해 주세요.';end if;
 if target_month<date_trunc('month',clock_timestamp() at time zone 'Asia/Seoul')::date then
  raise exception '지난달 신청표는 새로 열 수 없습니다.';end if;
 perform pg_catalog.pg_advisory_xact_lock(7492054);
 insert into public.cheongla_meals(meal_type,title,meal_on,deadline,body,status)
 select t.kind,case t.kind when 'lunch' then '점심 도시락' else '저녁 도시락' end,
 d::date,(d::date::timestamp at time zone 'Asia/Seoul'),meal_note,'open'
 from generate_series(target_month::timestamp,(target_month+interval '1 month'-interval '1 day')::timestamp,interval '1 day') d
 cross join (values('lunch'::text),('dinner'::text)) t(kind)
 where d::date>(clock_timestamp() at time zone 'Asia/Seoul')::date
 and extract(dow from d)::integer=any(case t.kind when 'lunch' then lunch_weekdays else dinner_weekdays end)
 on conflict(meal_on,meal_type) do nothing;
 get diagnostics result_count=row_count;return result_count;
end;
$$;
create or replace function public.cheongla_apply_meal_month(target_month date,selected_meals uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare student_label text;selected_count integer;eligible_count integer;result_count integer;
begin
 select full_name into student_label from public.cheongla_profiles where id=(select auth.uid())
 and role='student' and approval_status='approved';
 if not found then raise exception '승인된 학생 계정으로 신청해 주세요.' using errcode='42501';end if;
 if target_month is null or extract(day from target_month)<>1 or selected_meals is null
 or cardinality(selected_meals) not between 1 and 62 then raise exception '신청할 날짜와 식사를 선택해 주세요.';end if;
 select count(distinct v) into selected_count from unnest(selected_meals) v;
 if selected_count<>cardinality(selected_meals) then raise exception '중복되거나 잘못된 신청 항목이 있습니다.';end if;
 perform 1 from public.cheongla_meals where id=any(selected_meals) order by id for update;
 select count(*) into eligible_count from public.cheongla_meals
 where id=any(selected_meals) and meal_on>=target_month and meal_on<(target_month+interval '1 month')::date
 and status='open' and deadline>clock_timestamp();
 if eligible_count<>selected_count then raise exception '마감되었거나 신청할 수 없는 항목이 있습니다. 새로고침 후 다시 신청해 주세요.';end if;
 insert into public.cheongla_meal_orders(meal_id,student_id,student_name,status)
 select id,(select auth.uid()),student_label,'registered' from public.cheongla_meals where id=any(selected_meals)
 on conflict(meal_id,student_id) do update set student_name=excluded.student_name,status='registered',
 registered_at=clock_timestamp(),updated_at=clock_timestamp(),canceled_by=null,canceled_at=null,cancel_channel=null
 where public.cheongla_meal_orders.status='canceled';
 get diagnostics result_count=row_count;return result_count;
end;
$$;
-- 이전 화면이나 직접 호출로 학생이 취소하는 것도 차단합니다.
create or replace function public.cheongla_apply_meal(target_meal uuid,application_action text)
returns uuid language plpgsql security definer set search_path='' as $$
declare target_month date;
begin
 if application_action is distinct from 'register' then
  raise exception '취소는 식사일 전날까지 실장님께 구두로 말하거나 학원 휴대전화로 직접 연락해 주세요.' using errcode='42501';end if;
 select date_trunc('month',meal_on::timestamp)::date into target_month from public.cheongla_meals where id=target_meal;
 if not found then raise exception '해당 도시락이 없습니다.';end if;
 perform public.cheongla_apply_meal_month(target_month,array[target_meal]);return target_meal;
end;
$$;
create or replace function public.cheongla_cancel_meal_order(
 target_meal uuid,target_student uuid,cancellation_channel text,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare deadline_stamp timestamptz;old_order public.cheongla_meal_orders%rowtype;
begin
 if not cheongla_private.can_manage_meals() then
  raise exception '실장과 앱 관리자만 연락받은 취소를 처리할 수 있습니다.' using errcode='42501';end if;
 if cancellation_channel is null or cancellation_channel not in ('oral','sms') then
  raise exception '구두 또는 문자 요청을 선택해 주세요.';end if;
 select deadline into deadline_stamp from public.cheongla_meals where id=target_meal for update;
 if not found then raise exception '해당 도시락이 없습니다.';end if;
 if deadline_stamp<=clock_timestamp() then raise exception '취소 기한이 지났습니다. 식사일 전날까지만 처리할 수 있습니다.';end if;
 select * into old_order from public.cheongla_meal_orders
 where meal_id=target_meal and student_id=target_student for update;
 if not found or old_order.status<>'registered' then raise exception '신청 완료 내역이 없습니다.';end if;
 if old_order.updated_at is distinct from expected_updated_at then
  raise exception '신청 내역이 변경됐습니다. 명단 새로고침 후 다시 처리해 주세요.';end if;
 update public.cheongla_meal_orders set status='canceled',canceled_by=(select auth.uid()),
 canceled_at=clock_timestamp(),cancel_channel=cancellation_channel,updated_at=clock_timestamp()
 where meal_id=target_meal and student_id=target_student;return target_meal;
end;
$$;
drop function if exists public.cheongla_meal_roster(uuid);
create function public.cheongla_meal_roster(target_meal uuid)
returns table(student_id uuid,student_name text,approval_status text,application_status text,
 registered_at timestamptz,updated_at timestamptz,cancel_channel text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_meals() then
  raise exception '실장과 앱 관리자만 신청 명단을 확인할 수 있습니다.' using errcode='42501';end if;
 if not exists(select 1 from public.cheongla_meals where id=target_meal) then raise exception '해당 도시락이 없습니다.';end if;
 return query select p.id,coalesce(a.student_name,p.full_name),p.approval_status,
 coalesce(a.status,'unregistered'),a.registered_at,a.updated_at,a.cancel_channel
 from public.cheongla_profiles p left join public.cheongla_meal_orders a on a.student_id=p.id and a.meal_id=target_meal
 where (p.role='student' and p.approval_status='approved') or a.meal_id is not null
 order by coalesce(a.student_name,p.full_name),p.id;
end;
$$;
create or replace function public.cheongla_meal_month_ready()
returns boolean language sql stable set search_path='' as $$ select cheongla_private.can_view_meals(); $$;
revoke all on function public.cheongla_meal_month_ready() from public,anon,authenticated;
grant execute on function public.cheongla_meal_month_ready() to authenticated;
revoke all on function public.cheongla_save_meal(uuid,text,date,timestamptz,text,text,timestamptz),
 public.cheongla_open_meal_month(date,integer[],integer[],text),public.cheongla_apply_meal_month(date,uuid[]),
 public.cheongla_apply_meal(uuid,text),public.cheongla_cancel_meal_order(uuid,uuid,text,timestamptz),public.cheongla_meal_roster(uuid)
 from public,anon,authenticated;
grant execute on function public.cheongla_save_meal(uuid,text,date,timestamptz,text,text,timestamptz),
 public.cheongla_open_meal_month(date,integer[],integer[],text),public.cheongla_apply_meal_month(date,uuid[]),
 public.cheongla_apply_meal(uuid,text),public.cheongla_cancel_meal_order(uuid,uuid,text,timestamptz),public.cheongla_meal_roster(uuid)
 to authenticated;
notify pgrst,'reload schema';
commit;
