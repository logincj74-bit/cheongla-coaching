-- 001~003 실행 후 실행하세요. 기존 계정, 공지, 자녀 연결을 유지합니다.
-- 승인된 기존 원장 계정을 영어원장 + 앱 관리자로 전환합니다.
begin;
alter table public.cheongla_profiles add column if not exists is_app_admin boolean not null default false;
update public.cheongla_profiles set role='english_director',is_app_admin=true
where role='owner' and approval_status='approved';
alter table public.cheongla_profiles drop constraint if exists cheongla_admin_staff_check;
alter table public.cheongla_profiles add constraint cheongla_admin_staff_check
check (not is_app_admin or role in ('english_director','math_director','korean_teacher','manager','owner'));

create or replace function cheongla_private.is_app_admin()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles p where p.id=(select auth.uid())
 and p.approval_status='approved' and p.is_app_admin);
$$;
revoke all on function cheongla_private.is_app_admin() from public,anon,authenticated;
grant execute on function cheongla_private.is_app_admin() to authenticated;

-- 기존 보호자 연결 정책에서 쓰는 함수는 이제 앱 관리자만 허용합니다.
create or replace function cheongla_private.is_director()
returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.is_app_admin();
$$;

-- 두 원장의 공동 학습코칭 권한. 실장과 국어선생에게 전체 학습 권한을 주지 않습니다.
create or replace function cheongla_private.can_coach_all()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles p where p.id=(select auth.uid())
 and p.approval_status='approved' and (p.is_app_admin or p.role in ('english_director','math_director')));
$$;
revoke all on function cheongla_private.can_coach_all() from public,anon,authenticated;
grant execute on function cheongla_private.can_coach_all() to authenticated;

drop policy if exists cheongla_profile_read on public.cheongla_profiles;
create policy cheongla_profile_read on public.cheongla_profiles for select to authenticated
using (id=(select auth.uid()) or (select cheongla_private.is_app_admin())
 or (role='student' and approval_status='approved' and (select cheongla_private.can_coach_all())));

-- 권한 변경은 검증하는 관리자 전용 함수로만 처리합니다.
drop policy if exists cheongla_director_approve on public.cheongla_profiles;
revoke update on public.cheongla_profiles from authenticated;
revoke update(role,approval_status) on public.cheongla_profiles from authenticated;
create or replace function public.cheongla_set_member_access(
 target_id uuid,new_role text,new_status text,new_is_app_admin boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
begin
 -- 관리자 동시 변경을 직렬화하고 현재 권한을 다시 확인합니다.
 perform pg_catalog.pg_advisory_xact_lock(7492052);
 if not cheongla_private.is_app_admin() then
  raise exception '앱 관리자만 회원 권한을 변경할 수 있습니다.' using errcode='42501';
 end if;
 if target_id=(select auth.uid()) then
  raise exception '본인 관리자 계정은 이 화면에서 변경할 수 없습니다.' using errcode='42501';
 end if;
 if new_role not in ('student','parent','english_director','math_director','korean_teacher','manager')
 or new_status not in ('pending','approved','rejected','suspended')
 or new_role is null or new_status is null or new_is_app_admin is null then
  raise exception '직책과 승인 상태를 확인해 주세요.' using errcode='22023';
 end if;
 if new_is_app_admin and new_role in ('student','parent') then
  raise exception '학생과 학부모에게 관리자 권한을 부여할 수 없습니다.' using errcode='22023';
 end if;
 update public.cheongla_profiles set role=new_role,approval_status=new_status,
 is_app_admin=new_is_app_admin where id=target_id;
 if not found then raise exception '해당 회원이 없습니다.' using errcode='P0002';end if;
 return target_id;
end;
$$;
revoke all on function public.cheongla_set_member_access(uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.cheongla_set_member_access(uuid,text,text,boolean) to authenticated;

create or replace function cheongla_private.can_manage_notices()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles p where p.id=(select auth.uid())
 and p.approval_status='approved' and (p.is_app_admin or p.role in ('english_director','math_director','manager')));
$$;
notify pgrst,'reload schema';
commit;
