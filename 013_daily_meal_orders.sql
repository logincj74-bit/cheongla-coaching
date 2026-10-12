-- 앞서 진행한 설정 후 추가 실행합니다. 도시락은 식사일 당일에 마감합니다.
begin;
create or replace function cheongla_private.can_manage_meals()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and approval_status='approved' and (is_app_admin or role='manager'));
$$;
create or replace function cheongla_private.can_view_meals()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and approval_status='approved' and (is_app_admin or role in ('manager','student','parent')));
$$;
revoke all on function cheongla_private.can_manage_meals(),cheongla_private.can_view_meals()
 from public,anon,authenticated;
grant execute on function cheongla_private.can_manage_meals(),cheongla_private.can_view_meals()
 to authenticated;

create table if not exists public.cheongla_meals (
 id uuid primary key default gen_random_uuid(),
 meal_type text not null check(meal_type in ('lunch','dinner')),
 title text not null check(length(btrim(title)) between 1 and 150),
 meal_on date not null,
 deadline timestamptz not null,
 body text not null default '' check(length(body)<=5000),
 status text not null default 'draft' check(status in ('draft','open','closed')),
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 unique(meal_on,meal_type),
 check(deadline>=(meal_on::timestamp at time zone 'Asia/Seoul')
 and deadline<((meal_on+1)::timestamp at time zone 'Asia/Seoul'))
);
create table if not exists public.cheongla_meal_orders (
 meal_id uuid not null references public.cheongla_meals(id) on delete cascade,
 student_id uuid not null references public.cheongla_profiles(id) on delete cascade,
 student_name text not null,
 status text not null check(status in ('registered','canceled')),
 registered_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 primary key(meal_id,student_id)
);
alter table public.cheongla_meals enable row level security;
alter table public.cheongla_meal_orders enable row level security;
revoke all on public.cheongla_meals,public.cheongla_meal_orders from anon,authenticated;
grant select on public.cheongla_meals,public.cheongla_meal_orders to authenticated;
drop policy if exists cheongla_meal_read on public.cheongla_meals;
create policy cheongla_meal_read on public.cheongla_meals for select to authenticated
 using ((select cheongla_private.can_manage_meals())
 or (status in ('open','closed') and (select cheongla_private.can_view_meals())));
drop policy if exists cheongla_meal_order_read on public.cheongla_meal_orders;
create policy cheongla_meal_order_read on public.cheongla_meal_orders for select to authenticated
 using ((select cheongla_private.can_manage_meals()) or (
 exists(select 1 from public.cheongla_meals e where e.id=meal_id and e.status in ('open','closed'))
 and (exists(select 1 from public.cheongla_profiles p where p.id=(select auth.uid())
 and p.id=student_id and p.role='student' and p.approval_status='approved')
 or (select cheongla_private.is_parent_of(student_id)))));

create or replace function public.cheongla_save_meal(
 target_meal uuid,meal_kind text,meal_date date,application_deadline timestamptz,
 meal_body text,meal_status text,expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_meal public.cheongla_meals%rowtype;result_id uuid;
begin
 if not cheongla_private.can_manage_meals() then
  raise exception '실장과 앱 관리자만 도시락를 관리할 수 있습니다.' using errcode='42501';end if;
 if meal_kind is null or meal_kind not in ('lunch','dinner')
 or meal_date is null or application_deadline is null or meal_body is null or length(meal_body)>5000
 or meal_status is null or meal_status not in ('draft','open','closed') then
  raise exception '식사 구분, 식사일, 당일 신청 마감과 안내 내용을 확인해 주세요.';end if;
 if application_deadline<(meal_date::timestamp at time zone 'Asia/Seoul')
 or application_deadline>=((meal_date+1)::timestamp at time zone 'Asia/Seoul') then
  raise exception '신청 마감은 식사일 당일 시간으로 설정해 주세요.';end if;
 if target_meal is not null then
  select * into old_meal from public.cheongla_meals where id=target_meal for update;
  if not found then raise exception '해당 도시락가 없습니다.';end if;
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
create or replace function public.cheongla_apply_meal(target_meal uuid,application_action text)
returns uuid language plpgsql security definer set search_path='' as $$
declare meal public.cheongla_meals%rowtype;student_label text;old_status text;
begin
 select full_name into student_label from public.cheongla_profiles
 where id=(select auth.uid()) and role='student' and approval_status='approved';
 if not found then raise exception '승인된 학생 계정으로 신청해 주세요.' using errcode='42501';end if;
 if application_action is null or application_action not in ('register','cancel') then
  raise exception '신청 또는 취소를 선택해 주세요.';end if;
 select * into meal from public.cheongla_meals where id=target_meal for update;
 if not found then raise exception '해당 도시락가 없습니다.';end if;
 if meal.status<>'open' or meal.deadline<=clock_timestamp() then
  raise exception '신청이 마감되었습니다. 실장에게 문의해 주세요.';end if;
 select status into old_status from public.cheongla_meal_orders
 where meal_id=target_meal and student_id=(select auth.uid());
 if application_action='cancel' then
  if old_status is null then raise exception '신청 내역이 없습니다.';end if;
  update public.cheongla_meal_orders set status='canceled',updated_at=clock_timestamp()
  where meal_id=target_meal and student_id=(select auth.uid()) and status='registered';
 else
  insert into public.cheongla_meal_orders(meal_id,student_id,student_name,status)
  values(target_meal,(select auth.uid()),student_label,'registered')
  on conflict(meal_id,student_id) do update set student_name=excluded.student_name,status='registered',
  registered_at=clock_timestamp(),updated_at=clock_timestamp()
  where public.cheongla_meal_orders.status='canceled';
 end if;
 return target_meal;
end;
$$;
create or replace function public.cheongla_meal_roster(target_meal uuid)
returns table(student_id uuid,student_name text,approval_status text,application_status text,
 registered_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_meals() then
  raise exception '실장과 앱 관리자만 신청 명단을 확인할 수 있습니다.' using errcode='42501';end if;
 if not exists(select 1 from public.cheongla_meals where id=target_meal) then
  raise exception '해당 도시락가 없습니다.';end if;
 return query select p.id,coalesce(a.student_name,p.full_name),p.approval_status,
 coalesce(a.status,'unregistered'),a.registered_at,a.updated_at
 from public.cheongla_profiles p left join public.cheongla_meal_orders a
 on a.student_id=p.id and a.meal_id=target_meal
 where (p.role='student' and p.approval_status='approved') or a.meal_id is not null
 order by coalesce(a.student_name,p.full_name),p.id;
end;
$$;
revoke all on function public.cheongla_save_meal(uuid,text,date,timestamptz,text,text,timestamptz)
 from public,anon,authenticated;
revoke all on function public.cheongla_apply_meal(uuid,text) from public,anon,authenticated;
revoke all on function public.cheongla_meal_roster(uuid) from public,anon,authenticated;
grant execute on function public.cheongla_save_meal(uuid,text,date,timestamptz,text,text,timestamptz)
 to authenticated;
grant execute on function public.cheongla_apply_meal(uuid,text) to authenticated;
grant execute on function public.cheongla_meal_roster(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
