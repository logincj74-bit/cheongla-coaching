-- 022 연락처 설정 적용 후 실행합니다.
begin;
create or replace function public.cheongla_exam_fee_sms_recipients(
 target_notice uuid,expected_updated_at timestamptz
)
returns table(parent_id uuid,parent_name text,phone text)
language plpgsql stable security definer set search_path='' as $$
declare n public.cheongla_exam_fee_notices%rowtype;
begin
 if not cheongla_private.can_manage_exams() then
  raise exception '앱 관리자와 실장만 응시료 문자를 작성할 수 있습니다.' using errcode='42501';
 end if;
 select * into n from public.cheongla_exam_fee_notices where id=target_notice;
 if not found or n.status<>'published' then
  raise exception '학부모에게 게시한 응시료 안내만 문자로 작성할 수 있습니다.';
 end if;
 if n.updated_at is distinct from expected_updated_at then
  raise exception '안내가 변경되었습니다. 새로고침 후 다시 작성해 주세요.';
 end if;
 if not exists(select 1 from public.cheongla_exam_applications a
 join public.cheongla_profiles s on s.id=a.student_id
 where a.exam_id=n.exam_id and a.student_id=n.student_id
 and a.status='registered' and s.role='student' and s.approval_status='approved') then
  raise exception '신청 완료 학생의 학부모에게만 안내할 수 있습니다.';
 end if;
 return query select p.id,p.full_name::text,c.phone
 from public.cheongla_parent_students l
 join public.cheongla_profiles p on p.id=l.parent_id
 left join cheongla_private.member_contacts c on c.user_id=p.id
 where l.student_id=n.student_id and p.role='parent' and p.approval_status='approved'
 order by p.full_name,p.id;
end;
$$;
revoke all on function public.cheongla_exam_fee_sms_recipients(uuid,timestamptz)
from public,anon,authenticated;
grant execute on function public.cheongla_exam_fee_sms_recipients(uuid,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
