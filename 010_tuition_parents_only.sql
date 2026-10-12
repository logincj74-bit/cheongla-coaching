-- 학원비 안내는 연결된 학부모와 실장·앱 관리자만 열람합니다.
begin;
create or replace function cheongla_private.can_read_tuition(target_student uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.is_parent_of(target_student);
$$;
revoke all on function cheongla_private.can_read_tuition(uuid)
 from public,anon,authenticated;
grant execute on function cheongla_private.can_read_tuition(uuid)
 to authenticated;
notify pgrst,'reload schema';
commit;
