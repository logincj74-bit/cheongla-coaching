-- 001_initial.sql 실행 후 추가 실행하세요. 기존 계정과 원장 권한은 유지됩니다.
begin;
alter table public.cheongla_profiles drop constraint if exists cheongla_profiles_role_check;
alter table public.cheongla_profiles add constraint cheongla_profiles_role_check
check (role in ('student','parent','owner','english_director','math_director','korean_teacher','manager'));
alter table public.cheongla_profiles add column if not exists requested_student_name text not null default '';

create or replace function cheongla_private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.cheongla_profiles (id,full_name,role,approval_status,requested_student_name)
  values (new.id,left(coalesce(new.raw_user_meta_data ->> 'full_name',''),100),
    case when new.raw_user_meta_data ->> 'requested_role' = 'parent' then 'parent' else 'student' end,
    'pending',case when new.raw_user_meta_data ->> 'requested_role' = 'parent'
      then left(coalesce(new.raw_user_meta_data ->> 'requested_student_name',''),100) else '' end)
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function cheongla_private.handle_new_user() from public,anon,authenticated;

create table if not exists public.cheongla_parent_students (
  parent_id uuid not null references public.cheongla_profiles(id) on delete cascade,
  student_id uuid not null references public.cheongla_profiles(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (parent_id,student_id),
  check (parent_id <> student_id)
);
create index if not exists cheongla_parent_students_student_idx on public.cheongla_parent_students(student_id);
alter table public.cheongla_parent_students enable row level security;
revoke all on public.cheongla_parent_students from anon,authenticated;
grant select,insert,delete on public.cheongla_parent_students to authenticated;

-- 요청한 자녀 이름은 확인용 정보일 뿐이며 자동으로 열람 권한을 부여하지 않습니다.
-- 승인된 보호자와 승인된 학생의 연결만 실제 접근 권한으로 사용합니다.
create or replace function cheongla_private.is_parent_of(target_student uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.cheongla_parent_students l
    join public.cheongla_profiles p on p.id=l.parent_id
    join public.cheongla_profiles s on s.id=l.student_id
    where l.parent_id=(select auth.uid()) and l.student_id=target_student
      and p.role='parent' and p.approval_status='approved'
      and s.role='student' and s.approval_status='approved'
  );
$$;
revoke all on function cheongla_private.is_parent_of(uuid) from public,anon;
grant execute on function cheongla_private.is_parent_of(uuid) to authenticated;

drop policy if exists cheongla_parent_read_child on public.cheongla_profiles;
create policy cheongla_parent_read_child on public.cheongla_profiles
for select to authenticated using ((select cheongla_private.is_parent_of(id)));

drop policy if exists cheongla_link_read on public.cheongla_parent_students;
create policy cheongla_link_read on public.cheongla_parent_students
for select to authenticated using (
  (select cheongla_private.is_director()) or
  (parent_id=(select auth.uid()) and (select cheongla_private.is_parent_of(student_id)))
);
drop policy if exists cheongla_link_create on public.cheongla_parent_students;
create policy cheongla_link_create on public.cheongla_parent_students
for insert to authenticated with check (
  (select cheongla_private.is_director()) and created_by=(select auth.uid())
  and exists (select 1 from public.cheongla_profiles p
    where p.id=parent_id and p.role='parent' and p.approval_status='approved')
  and exists (select 1 from public.cheongla_profiles s
    where s.id=student_id and s.role='student' and s.approval_status='approved')
);
drop policy if exists cheongla_link_delete on public.cheongla_parent_students;
create policy cheongla_link_delete on public.cheongla_parent_students
for delete to authenticated using ((select cheongla_private.is_director()));
commit;
