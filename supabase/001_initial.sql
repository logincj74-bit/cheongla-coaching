-- 청라 학습코칭: 새 프로젝트 초기 설정
-- Supabase SQL Editor에서 전체 실행하세요. 기존 계정이나 데이터를 삭제하지 않습니다.
begin;
create schema if not exists cheongla_private;
revoke all on schema cheongla_private from public;
grant usage on schema cheongla_private to authenticated;

create table if not exists public.cheongla_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'student'
    check (role in ('student','owner','english_director','math_director','korean_teacher','manager')),
  approval_status text not null default 'pending'
    check (approval_status in ('pending','approved','rejected','suspended')),
  created_at timestamptz not null default now()
);
alter table public.cheongla_profiles enable row level security;
revoke all on public.cheongla_profiles from anon, authenticated;
grant select on public.cheongla_profiles to authenticated;
grant update (role, approval_status) on public.cheongla_profiles to authenticated;

-- 본인이 보내는 가입 정보에서 권한과 승인 여부를 가져오지 않습니다.
create or replace function cheongla_private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.cheongla_profiles (id, full_name, role, approval_status)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'full_name', ''),100), 'student','pending')
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function cheongla_private.handle_new_user() from public, anon, authenticated;
drop trigger if exists cheongla_on_auth_user_created on auth.users;
create trigger cheongla_on_auth_user_created after insert on auth.users
for each row execute function cheongla_private.handle_new_user();

-- 같은 테이블의 RLS를 반복 호출하지 않도록 별도 함수에서 원장 권한을 확인합니다.
create or replace function cheongla_private.is_director()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved'
    and role in ('owner','english_director','math_director')
  );
$$;
revoke all on function cheongla_private.is_director() from public, anon;
grant execute on function cheongla_private.is_director() to authenticated;

drop policy if exists cheongla_profile_read on public.cheongla_profiles;
create policy cheongla_profile_read on public.cheongla_profiles
for select to authenticated
using (id = (select auth.uid()) or (select cheongla_private.is_director()));

drop policy if exists cheongla_director_approve on public.cheongla_profiles;
create policy cheongla_director_approve on public.cheongla_profiles
for update to authenticated
using ((select cheongla_private.is_director()))
with check ((select cheongla_private.is_director()));

-- 초기 설정 전에 만들어진 사용자도 학생/승인 대기로 등록합니다.
insert into public.cheongla_profiles (id, full_name)
select id, left(coalesce(raw_user_meta_data ->> 'full_name',''),100) from auth.users
on conflict (id) do nothing;
commit;
