begin;
alter table public.cheongla_exams add column if not exists calendar_hidden boolean not null default false;
create or replace function public.cheongla_set_exam_calendar_visibility(
 target_exam uuid,hide_from_calendar boolean,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_exam public.cheongla_exams%rowtype;
begin
 if not cheongla_private.can_manage_exams() then
  raise exception '실장과 앱 관리자만 달력 일정을 관리할 수 있습니다.' using errcode='42501';
 end if;
 if hide_from_calendar is null then raise exception '달력 표시 여부를 확인해 주세요.';end if;
 select * into old_exam from public.cheongla_exams where id=target_exam for update;
 if not found then raise exception '해당 모의고사가 없습니다.';end if;
 if old_exam.updated_at is distinct from expected_updated_at then
  raise exception '다른 담당자가 수정했습니다. 일정 새로고침 후 다시 확인해 주세요.';
 end if;
 update public.cheongla_exams set calendar_hidden=hide_from_calendar,updated_at=clock_timestamp() where id=target_exam;
 return target_exam;
end;$$;
revoke all on function public.cheongla_set_exam_calendar_visibility(uuid,boolean,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_set_exam_calendar_visibility(uuid,boolean,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
