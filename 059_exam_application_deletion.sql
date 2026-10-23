begin;
create table cheongla_private.exam_application_deletions(
 id bigint generated always as identity primary key,
 exam_id uuid not null,student_id uuid not null,actor_id uuid not null,
 application_snapshot jsonb not null,
 deleted_at timestamptz not null default clock_timestamp()
);
alter table cheongla_private.exam_application_deletions enable row level security;
revoke all on cheongla_private.exam_application_deletions from public,anon,authenticated;
create or replace function public.cheongla_delete_exam_application(
 target_exam uuid,target_student uuid,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare e public.cheongla_exams%rowtype;a public.cheongla_exam_applications%rowtype;
begin
 if not cheongla_private.is_principal()then
  raise exception '원장만 모의고사 신청 기록을 삭제할 수 있습니다.'using errcode='42501';
 end if;
 -- Lock the exam before its application, matching application and billing writers.
 select * into e from public.cheongla_exams where id=target_exam for update;
 if not found or e.deleted_at is not null then raise exception '시험 목록을 새로고침해 주세요.';end if;
 select * into a from public.cheongla_exam_applications
 where exam_id=target_exam and student_id=target_student for update;
 if not found then raise exception '이미 삭제되었거나 없는 신청 기록입니다.';end if;
 if a.updated_at is distinct from expected_updated_at then
  raise exception '신청 기록이 변경되었습니다. 명단을 새로고침한 후 다시 확인해 주세요.';
 end if;
 if exists(select 1 from public.cheongla_exam_fee_notices where exam_id=target_exam and student_id=target_student)then
  raise exception '응시료 안내가 연결된 신청은 삭제할 수 없습니다. 응시료·입금 기록을 먼저 확인해 주세요.';
 end if;
 insert into cheongla_private.exam_application_deletions(exam_id,student_id,actor_id,application_snapshot)
 values(target_exam,target_student,auth.uid(),to_jsonb(a));
 delete from public.cheongla_exam_applications where exam_id=target_exam and student_id=target_student;
 return target_student;
end;$$;
revoke all on function public.cheongla_delete_exam_application(uuid,uuid,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_delete_exam_application(uuid,uuid,timestamptz)to authenticated;
notify pgrst,'reload schema';
commit;
