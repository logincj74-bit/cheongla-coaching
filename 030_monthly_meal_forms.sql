begin;
create or replace function cheongla_private.can_manage_meal_forms() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved'
 and (is_app_admin or role in ('owner','english_director','math_director','manager')));
$$;
create table public.cheongla_meal_forms (
 month date primary key check(extract(day from month)=1),
 deadline date not null,
 note text not null default '' check(length(note)<=3000),
 unit_price integer not null default 7500 check(unit_price between 0 and 100000),
 updated_at timestamptz not null default clock_timestamp()
);
create table public.cheongla_meal_submissions (
 month date not null references public.cheongla_meal_forms(month),
 student_id uuid not null references public.cheongla_profiles(id),
 student_name text not null,
 lunch date[] not null default '{}', dinner date[] not null default '{}',
 note text not null default '' check(length(note)<=1000),
 submitted_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 primary key(month,student_id)
);
alter table public.cheongla_meal_forms enable row level security;
alter table public.cheongla_meal_submissions enable row level security;
revoke all on public.cheongla_meal_forms,public.cheongla_meal_submissions from anon,authenticated;
grant select on public.cheongla_meal_forms,public.cheongla_meal_submissions to authenticated;
create policy meal_form_read on public.cheongla_meal_forms for select to authenticated using(
 cheongla_private.can_manage_meal_forms() or exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role='student' and approval_status='approved'));
create policy meal_submission_read on public.cheongla_meal_submissions for select to authenticated using(
 cheongla_private.can_manage_meal_forms() or (student_id=(select auth.uid()) and exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role='student' and approval_status='approved')));
create or replace function public.cheongla_save_meal_form(target_month date,submit_by date,form_note text,meal_price integer,expected_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare old_row public.cheongla_meal_forms%rowtype;
begin
 if not cheongla_private.can_manage_meal_forms() then raise exception '관리자만 신청서를 설정할 수 있습니다.' using errcode='42501';end if;
 if target_month is null or extract(day from target_month)<>1 or submit_by is null or form_note is null or length(form_note)>3000 or meal_price is null or meal_price not between 0 and 100000 then raise exception '신청 월, 제출 기한, 금액과 비고를 확인해 주세요.';end if;
 perform pg_advisory_xact_lock(hashtextextended('meal-form:'||target_month::text,0));
 select * into old_row from public.cheongla_meal_forms where month=target_month for update;
 if old_row.updated_at is distinct from expected_updated_at then raise exception '다른 담당자가 변경했습니다. 새로고침 후 다시 저장해 주세요.';end if;
 if (old_row.month is null or old_row.deadline is distinct from submit_by) and submit_by<(clock_timestamp() at time zone 'Asia/Seoul')::date then raise exception '새 제출 기한은 오늘 이후로 설정해 주세요.';end if;
 if old_row.month is not null and old_row.unit_price<>meal_price and exists(select 1 from public.cheongla_meal_submissions where month=target_month) then raise exception '이미 신청한 학생이 있어 식사 가격을 변경할 수 없습니다.';end if;
 insert into public.cheongla_meal_forms(month,deadline,note,unit_price) values(target_month,submit_by,form_note,meal_price)
 on conflict(month) do update set deadline=excluded.deadline,note=excluded.note,unit_price=excluded.unit_price,updated_at=clock_timestamp();
end;$$;
create or replace function public.cheongla_submit_meal_form(target_month date,lunch_dates date[],dinner_dates date[],student_note text,expected_updated_at timestamptz,expected_form_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare f public.cheongla_meal_forms%rowtype;s public.cheongla_meal_submissions%rowtype;n text;today date:=(clock_timestamp() at time zone 'Asia/Seoul')::date;l date[];d date[];
begin
 select full_name into n from public.cheongla_profiles where id=(select auth.uid()) and role='student' and approval_status='approved';
 if not found then raise exception '승인된 학생 계정으로 신청해 주세요.' using errcode='42501';end if;
 select * into f from public.cheongla_meal_forms where month=target_month for update;
 if not found then raise exception '아직 등록되지 않은 월의 신청서입니다.';end if;
 if f.updated_at is distinct from expected_form_updated_at then raise exception '신청 안내가 변경되었습니다. 새로고침 후 확인해 주세요.';end if;
 if lunch_dates is null or dinner_dates is null or cardinality(lunch_dates)>31 or cardinality(dinner_dates)>31 or student_note is null or length(student_note)>1000 then raise exception '신청 내용과 비고를 확인해 주세요.';end if;
 if exists(select 1 from unnest(lunch_dates||dinner_dates) x where x is null or x<target_month or x>=(target_month+interval '1 month')::date or extract(isodow from x)=7) then raise exception '해당 월의 월요일부터 토요일까지 선택해 주세요.';end if;
 select coalesce(array_agg(distinct x order by x),'{}') into l from unnest(lunch_dates) x;
 select coalesce(array_agg(distinct x order by x),'{}') into d from unnest(dinner_dates) x;
 select * into s from public.cheongla_meal_submissions where month=target_month and student_id=(select auth.uid()) for update;
 if s.updated_at is distinct from expected_updated_at then raise exception '다른 화면에서 신청 내용이 변경되었습니다. 새로고침 후 확인해 주세요.';end if;
 if today>f.deadline and (s.student_id is null or not l<@s.lunch or not d<@s.dinner) then raise exception '제출 기한이 지났습니다. 추가 신청은 관리자에게 문의해 주세요.';end if;
 if exists(select 1 from ((select unnest(l) except select unnest(coalesce(s.lunch,'{}'))) union all (select unnest(coalesce(s.lunch,'{}')) except select unnest(l)) union all (select unnest(d) except select unnest(coalesce(s.dinner,'{}'))) union all (select unnest(coalesce(s.dinner,'{}')) except select unnest(d))) changes(x) where x<=today) then raise exception '식사 당일과 지난 날짜는 신청·취소할 수 없습니다.';end if;
 insert into public.cheongla_meal_submissions(month,student_id,student_name,lunch,dinner,note) values(target_month,(select auth.uid()),n,l,d,student_note)
 on conflict(month,student_id) do update set student_name=excluded.student_name,lunch=excluded.lunch,dinner=excluded.dinner,note=excluded.note,updated_at=clock_timestamp();
end;$$;
create or replace function public.cheongla_read_meal_form(target_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean:=cheongla_private.can_manage_meal_forms();result jsonb;
begin
 if not manager and not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role='student' and approval_status='approved') then raise exception '승인된 학생과 관리자만 이용할 수 있습니다.' using errcode='42501';end if;
 select jsonb_build_object('form',(select to_jsonb(f) from public.cheongla_meal_forms f where month=target_month),'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.student_name,s.student_id) from public.cheongla_meal_submissions s where month=target_month and (manager or s.student_id=(select auth.uid()))),'[]'::jsonb),'today',(now() at time zone 'Asia/Seoul')::date) into result;
 return result;
end;$$;
revoke all on function public.cheongla_save_meal_form(date,date,text,integer,timestamptz),public.cheongla_submit_meal_form(date,date[],date[],text,timestamptz,timestamptz),public.cheongla_read_meal_form(date) from public,anon,authenticated;
grant execute on function public.cheongla_save_meal_form(date,date,text,integer,timestamptz),public.cheongla_submit_meal_form(date,date[],date[],text,timestamptz,timestamptz),public.cheongla_read_meal_form(date) to authenticated;
notify pgrst,'reload schema';
commit;
