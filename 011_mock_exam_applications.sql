-- 001~010 실행 후 추가 실행합니다.
begin;
create or replace function cheongla_private.can_manage_exams()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and approval_status='approved' and (is_app_admin or role='manager'));
$$;
create or replace function cheongla_private.can_view_exams()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and approval_status='approved' and (is_app_admin or role in ('manager','student','parent')));
$$;
revoke all on function cheongla_private.can_manage_exams(),cheongla_private.can_view_exams()
 from public,anon,authenticated;
grant execute on function cheongla_private.can_manage_exams(),cheongla_private.can_view_exams()
 to authenticated;

create table if not exists public.cheongla_exams (
 id uuid primary key default gen_random_uuid(),
 title text not null check(length(btrim(title)) between 1 and 150),
 exam_on date not null,
 deadline timestamptz not null,
 body text not null default '' check(length(body)<=5000),
 status text not null default 'draft' check(status in ('draft','open','closed')),
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 check(deadline<((exam_on+1)::timestamp at time zone 'Asia/Seoul'))
);
create table if not exists public.cheongla_exam_applications (
 exam_id uuid not null references public.cheongla_exams(id) on delete cascade,
 student_id uuid not null references public.cheongla_profiles(id) on delete cascade,
 student_name text not null,
 status text not null check(status in ('registered','canceled')),
 registered_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 primary key(exam_id,student_id)
);
alter table public.cheongla_exams enable row level security;
alter table public.cheongla_exam_applications enable row level security;
revoke all on public.cheongla_exams,public.cheongla_exam_applications from anon,authenticated;
grant select on public.cheongla_exams,public.cheongla_exam_applications to authenticated;
drop policy if exists cheongla_exam_read on public.cheongla_exams;
create policy cheongla_exam_read on public.cheongla_exams for select to authenticated
 using ((select cheongla_private.can_manage_exams())
 or (status in ('open','closed') and (select cheongla_private.can_view_exams())));
drop policy if exists cheongla_exam_application_read on public.cheongla_exam_applications;
create policy cheongla_exam_application_read on public.cheongla_exam_applications for select to authenticated
 using ((select cheongla_private.can_manage_exams()) or (
 exists(select 1 from public.cheongla_exams e where e.id=exam_id and e.status in ('open','closed'))
 and (exists(select 1 from public.cheongla_profiles p where p.id=(select auth.uid())
 and p.id=student_id and p.role='student' and p.approval_status='approved')
 or (select cheongla_private.is_parent_of(student_id)))));

create or replace function public.cheongla_save_exam(
 target_exam uuid,exam_title text,exam_date date,application_deadline timestamptz,
 exam_body text,exam_status text,expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_exam public.cheongla_exams%rowtype;result_id uuid;
begin
 if not cheongla_private.can_manage_exams() then
  raise exception '실장과 앱 관리자만 모의고사를 관리할 수 있습니다.' using errcode='42501';end if;
 if exam_title is null or length(btrim(exam_title)) not between 1 and 150
 or exam_date is null or application_deadline is null or exam_body is null or length(exam_body)>5000
 or exam_status is null or exam_status not in ('draft','open','closed') then
  raise exception '시험명, 시험일, 신청 마감과 안내 내용을 확인해 주세요.';end if;
 if application_deadline>=((exam_date+1)::timestamp at time zone 'Asia/Seoul') then
  raise exception '신청 마감은 시험일이 끝나기 전으로 설정해 주세요.';end if;
 if target_exam is not null then
  select * into old_exam from public.cheongla_exams where id=target_exam for update;
  if not found then raise exception '해당 모의고사가 없습니다.';end if;
 end if;
 if old_exam.updated_at is distinct from expected_updated_at then
  raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 저장해 주세요.';end if;
 if exam_status='open' and (old_exam.status is distinct from 'open'
 or old_exam.deadline is distinct from application_deadline) and application_deadline<=clock_timestamp() then
  raise exception '신청을 열려면 마감 시간을 현재보다 뒤로 설정해 주세요.';end if;
 if old_exam.id is not null and exists(select 1 from public.cheongla_exam_applications where exam_id=old_exam.id) then
  if exam_status='draft' then raise exception '신청 이력이 있는 시험은 초안으로 되돌릴 수 없습니다. 마감으로 변경해 주세요.';end if;
  if old_exam.title is distinct from btrim(exam_title) or old_exam.exam_on is distinct from exam_date then
   raise exception '신청 이력이 있는 시험의 이름과 시험일은 변경할 수 없습니다. 새 시험으로 등록해 주세요.';end if;
 end if;
 if target_exam is null then
  insert into public.cheongla_exams(title,exam_on,deadline,body,status)
  values(btrim(exam_title),exam_date,application_deadline,exam_body,exam_status) returning id into result_id;
 else
  update public.cheongla_exams set title=btrim(exam_title),exam_on=exam_date,deadline=application_deadline,
  body=exam_body,status=exam_status,updated_at=clock_timestamp() where id=target_exam returning id into result_id;
 end if;
 return result_id;
end;
$$;
create or replace function public.cheongla_apply_exam(target_exam uuid,application_action text)
returns uuid language plpgsql security definer set search_path='' as $$
declare exam public.cheongla_exams%rowtype;student_label text;old_status text;
begin
 select full_name into student_label from public.cheongla_profiles
 where id=(select auth.uid()) and role='student' and approval_status='approved';
 if not found then raise exception '승인된 학생 계정으로 신청해 주세요.' using errcode='42501';end if;
 if application_action is null or application_action not in ('register','cancel') then
  raise exception '신청 또는 취소를 선택해 주세요.';end if;
 select * into exam from public.cheongla_exams where id=target_exam for update;
 if not found then raise exception '해당 모의고사가 없습니다.';end if;
 if exam.status<>'open' or exam.deadline<=clock_timestamp() then
  raise exception '신청이 마감되었습니다. 실장에게 문의해 주세요.';end if;
 select status into old_status from public.cheongla_exam_applications
 where exam_id=target_exam and student_id=(select auth.uid());
 if application_action='cancel' then
  if old_status is null then raise exception '신청 내역이 없습니다.';end if;
  update public.cheongla_exam_applications set status='canceled',updated_at=clock_timestamp()
  where exam_id=target_exam and student_id=(select auth.uid()) and status='registered';
 else
  insert into public.cheongla_exam_applications(exam_id,student_id,student_name,status)
  values(target_exam,(select auth.uid()),student_label,'registered')
  on conflict(exam_id,student_id) do update set student_name=excluded.student_name,status='registered',
  registered_at=clock_timestamp(),updated_at=clock_timestamp()
  where public.cheongla_exam_applications.status='canceled';
 end if;
 return target_exam;
end;
$$;
create or replace function public.cheongla_exam_roster(target_exam uuid)
returns table(student_id uuid,student_name text,approval_status text,application_status text,
 registered_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_exams() then
  raise exception '실장과 앱 관리자만 신청 명단을 확인할 수 있습니다.' using errcode='42501';end if;
 if not exists(select 1 from public.cheongla_exams where id=target_exam) then
  raise exception '해당 모의고사가 없습니다.';end if;
 return query select p.id,coalesce(a.student_name,p.full_name),p.approval_status,
 coalesce(a.status,'unregistered'),a.registered_at,a.updated_at
 from public.cheongla_profiles p left join public.cheongla_exam_applications a
 on a.student_id=p.id and a.exam_id=target_exam
 where (p.role='student' and p.approval_status='approved') or a.exam_id is not null
 order by coalesce(a.student_name,p.full_name),p.id;
end;
$$;
revoke all on function public.cheongla_save_exam(uuid,text,date,timestamptz,text,text,timestamptz)
 from public,anon,authenticated;
revoke all on function public.cheongla_apply_exam(uuid,text) from public,anon,authenticated;
revoke all on function public.cheongla_exam_roster(uuid) from public,anon,authenticated;
grant execute on function public.cheongla_save_exam(uuid,text,date,timestamptz,text,text,timestamptz)
 to authenticated;
grant execute on function public.cheongla_apply_exam(uuid,text) to authenticated;
grant execute on function public.cheongla_exam_roster(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
