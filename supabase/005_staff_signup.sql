-- 001~004 실행 후 실행하세요. 기존 계정과 권한은 유지됩니다.
begin;
alter table public.cheongla_profiles add column if not exists requested_staff_role text not null default '';
alter table public.cheongla_profiles drop constraint if exists cheongla_staff_request_check;
alter table public.cheongla_profiles add constraint cheongla_staff_request_check
check (requested_staff_role in ('','english_director','math_director','korean_teacher','manager'));

-- 신청 직책은 확인용입니다. 직책 선택만으로 실제 권한을 부여하지 않습니다.
create or replace function cheongla_private.handle_new_user()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.cheongla_profiles(id,full_name,role,approval_status,requested_student_name,requested_staff_role,is_app_admin)
 values(new.id,left(coalesce(new.raw_user_meta_data->>'full_name',''),100),
 case when new.raw_user_meta_data->>'requested_role'='parent' then 'parent' else 'student' end,
 'pending',case when new.raw_user_meta_data->>'requested_role'='parent'
 then left(coalesce(new.raw_user_meta_data->>'requested_student_name',''),100) else '' end,
 case when new.raw_user_meta_data->>'requested_role'='staff'
 and new.raw_user_meta_data->>'requested_staff_role' in ('english_director','math_director','korean_teacher','manager')
 then new.raw_user_meta_data->>'requested_staff_role' else '' end,false)
 on conflict(id) do nothing;
 return new;
end;
$$;
revoke all on function cheongla_private.handle_new_user() from public,anon,authenticated;

-- 앱 화면 배포 이후, 이 SQL 실행 전에 접수된 교직원 신청도 보완합니다.
-- 본인이 메타데이터를 변경해도 여기서는 신청 직책만 기록합니다.
update public.cheongla_profiles p set requested_staff_role=u.raw_user_meta_data->>'requested_staff_role'
from auth.users u where p.id=u.id and p.approval_status='pending' and p.requested_staff_role=''
and u.raw_user_meta_data->>'requested_role'='staff'
and u.raw_user_meta_data->>'requested_staff_role' in ('english_director','math_director','korean_teacher','manager');
notify pgrst,'reload schema';
commit;
