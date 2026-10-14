begin;
alter table public.cheongla_exams add column if not exists deleted_at timestamptz,
 add column if not exists deleted_by uuid references public.cheongla_profiles(id);
drop policy if exists cheongla_exam_read on public.cheongla_exams;
create policy cheongla_exam_read on public.cheongla_exams for select to authenticated
using ((select cheongla_private.can_manage_exams()) or (deleted_at is null and status in ('open','closed') and (select cheongla_private.can_view_exams())));
create or replace function public.cheongla_set_exam_deleted(target_exam uuid,delete_exam boolean,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_exam public.cheongla_exams%rowtype;
begin
 if not cheongla_private.can_manage_exams() then raise exception '실장과 앱 관리자만 시험을 삭제·복원할 수 있습니다.' using errcode='42501';end if;
 if delete_exam is null then raise exception '삭제 여부를 확인해 주세요.';end if;
 select * into old_exam from public.cheongla_exams where id=target_exam for update;
 if not found then raise exception '해당 모의고사가 없습니다.';end if;
 if old_exam.updated_at is distinct from expected_updated_at then raise exception '다른 담당자가 변경했습니다. 시험 새로고침 후 다시 확인해 주세요.';end if;
 if delete_exam=(old_exam.deleted_at is not null) then return target_exam;end if;
 update public.cheongla_exams set deleted_at=case when delete_exam then clock_timestamp() else null end,
 deleted_by=case when delete_exam then (select auth.uid()) else null end,updated_at=clock_timestamp() where id=target_exam;
 return target_exam;
end;$$;
revoke all on function public.cheongla_set_exam_deleted(uuid,boolean,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_set_exam_deleted(uuid,boolean,timestamptz) to authenticated;
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
  if not found or old_exam.deleted_at is not null then raise exception '삭제된 시험은 복원 후 수정해 주세요.';end if;
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
 if not found or exam.deleted_at is not null then raise exception '삭제된 시험은 신청할 수 없습니다.';end if;
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
create or replace function public.cheongla_schedule_month(target_month date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;exam_items jsonb;
begin
 if not cheongla_private.can_use_schedule() then raise exception '승인된 학원 계정으로 확인해 주세요.' using errcode='42501';end if;
 if target_month is null or extract(day from target_month)<>1 then raise exception '조회할 월을 확인해 주세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.starts_on,e.event_time,e.title,e.id),'[]'::jsonb)
 into result from public.cheongla_schedule_events e
 where e.starts_on<(target_month+interval '1 month')::date and e.ends_on>=target_month;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.exam_on,e.title,e.id),'[]'::jsonb) into exam_items
 from public.cheongla_exams e where e.deleted_at is null and (
 (e.exam_on>=target_month and e.exam_on<(target_month+interval '1 month')::date)
 or (e.deadline>=(target_month::timestamp at time zone 'Asia/Seoul') and e.deadline<((target_month+interval '1 month')::timestamp at time zone 'Asia/Seoul')));
 return jsonb_build_object('events',result,'exams',exam_items);
end;$$;
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
 if not found or old_exam.deleted_at is not null then raise exception '삭제된 시험은 시험 관리에서 복원해 주세요.';end if;
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
