create table if not exists cheongla_private.meal_cancellations(
 id uuid primary key default gen_random_uuid(),month date not null,student_id uuid not null,meal_on date not null,meal_kind text not null check(meal_kind in('lunch','dinner','both')),reason text not null,actor_id uuid not null,created_at timestamptz not null default clock_timestamp()
);
alter table cheongla_private.meal_cancellations enable row level security;
revoke all on cheongla_private.meal_cancellations from public,anon,authenticated;
create or replace function public.cheongla_cancel_meal_by_staff(target_month date,target_student uuid,meal_on date,meal_kind text,contact_note text,expected_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare s public.cheongla_meal_submissions%rowtype;today date:=(clock_timestamp() at time zone 'Asia/Seoul')::date;
begin
 if not cheongla_private.can_manage_meal_forms()then raise exception '학원 직원만 접수한 취소를 처리할 수 있습니다.'using errcode='42501';end if;
 if meal_on is null or meal_on<=today then raise exception '식사 취소는 전날까지만 가능합니다. 당일과 지난 날짜는 취소할 수 없습니다.';end if;
 if meal_kind is null or meal_kind not in('lunch','dinner','both')or contact_note is null or length(btrim(contact_note)) not between 1 and 500 then raise exception '취소할 식사와 전화·문자 접수 내용을 확인해 주세요.';end if;
 perform 1 from public.cheongla_meal_forms where month=target_month for update;
 select * into s from public.cheongla_meal_submissions where month=target_month and student_id=target_student and archived_at is null for update;
 if not found or s.updated_at is distinct from expected_updated_at then raise exception '신청서가 변경되었거나 삭제되었습니다. 새로고침 후 확인해 주세요.';end if;
 if (meal_kind='lunch'and not meal_on=any(s.lunch))or(meal_kind='dinner'and not meal_on=any(s.dinner))or(meal_kind='both'and not(meal_on=any(s.lunch)or meal_on=any(s.dinner)))then raise exception '해당 날짜에 신청한 식사가 없습니다.';end if;
 insert into cheongla_private.meal_cancellations(month,student_id,meal_on,meal_kind,reason,actor_id)values(target_month,target_student,meal_on,meal_kind,btrim(contact_note),auth.uid());
 update public.cheongla_meal_submissions set lunch=case when meal_kind in('lunch','both')then array_remove(lunch,meal_on)else lunch end,dinner=case when meal_kind in('dinner','both')then array_remove(dinner,meal_on)else dinner end,updated_at=clock_timestamp()where month=target_month and student_id=target_student;
end;$$;
revoke all on function public.cheongla_cancel_meal_by_staff(date,uuid,date,text,text,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_cancel_meal_by_staff(date,uuid,date,text,text,timestamptz)to authenticated;

CREATE OR REPLACE FUNCTION cheongla_private.can_apply_for(student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select cheongla_private.can_use_member_services() and exists(select 1 from public.cheongla_profiles s where s.id=student and s.role='student' and s.approval_status='approved' and s.membership_state='active' and s.id=auth.uid());
$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_view_exams()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select cheongla_private.can_use_member_services() and exists(select 1 from public.cheongla_profiles where id=auth.uid() and (is_app_admin or role in ('owner','english_director','math_director','manager','student'))); $function$
;
CREATE OR REPLACE FUNCTION public.cheongla_read_meal_form(target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare manager boolean:=cheongla_private.can_manage_meal_forms();result jsonb;
begin
 if not manager and not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role='student' and approval_status='approved' and membership_state='active') then raise exception '승인된 학생과 관리자만 이용할 수 있습니다.' using errcode='42501';end if;
 select jsonb_build_object('form',(select to_jsonb(f) from public.cheongla_meal_forms f where month=target_month),'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.student_name,s.student_id) from public.cheongla_meal_submissions s where month=target_month and s.archived_at is null and (manager or cheongla_private.can_apply_for(s.student_id))),'[]'::jsonb),'bills',case when manager then coalesce((select jsonb_agg(to_jsonb(b)) from public.cheongla_meal_bills b where b.month=target_month and b.archived_at is null),'[]'::jsonb) else '[]'::jsonb end,'today',(now() at time zone 'Asia/Seoul')::date) into result;
 return result;
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_read_collection(fee_kind text, target_notice uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select cheongla_private.can_use_member_services() and exists(select 1 from cheongla_private.collection_notices n where n.fee_kind=can_read_collection.fee_kind and n.id=target_notice and (cheongla_private.can_manage_tuition() or (n.fee_kind='meal' and cheongla_private.can_manage_meal_forms()) or ((n.status='published' or exists(select 1 from cheongla_private.fee_payments fp where fp.notice_kind=n.fee_kind and fp.notice_id=n.id and fp.paid_at is not null)) and exists(select 1 from public.cheongla_profiles s where s.id=n.student_id and s.role='student' and s.approval_status='approved') and cheongla_private.is_parent_of(n.student_id))));
$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.notify_collection(kind text, target uuid, admin_only boolean, label text, event_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n record;people uuid[];begin
 select * into n from cheongla_private.collection_notices where fee_kind=kind and id=target;if not found then return;end if;
 select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role in ('owner','english_director','math_director','manager') or (not admin_only and ((p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.student_id=n.student_id and l.parent_id=p.id))));
 perform cheongla_private.send_notification(people,'fee_collection',target,n.student_id,n.student_name||' · '||to_char(n.billing_month,'YYYY-MM')||' · '||case kind when 'meal' then '도시락비' when 'exam' then '모의고사비' else '학원비' end||' · '||to_char(n.amount,'FM999,999,999')||'원 · '||label,'billing_dashboard',event_key);
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.create_event_notifications()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n jsonb=to_jsonb(new);o jsonb=case when tg_op='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
 people uuid[];kind text;target uuid;student uuid;label text;destination text;event_id text;q record;
begin
 event_id=tg_table_name||':'||coalesce(n->>'id',n->>'question_id',(n->>'exam_id')||':'||(n->>'student_id'))||':'||coalesce(n->>'updated_at',n->>'created_at',clock_timestamp()::text);
 case tg_table_name
 when 'cheongla_notices' then
  if tg_op='UPDATE' and (n->>'title',n->>'body',n->>'audience') is not distinct from (o->>'title',o->>'body',o->>'audience') then return new;end if;
  select array_agg(id) into people from public.cheongla_profiles where (n->>'audience'='all' or role=n->>'audience' or role in ('owner','english_director','math_director','korean_teacher','manager'));
  kind='notice';target=(n->>'id')::uuid;label=case n->>'audience' when 'parent' then '학부모 공지가 게시되었습니다.' when 'student' then '재원생 공지가 게시되었습니다.' else '전체 공지가 게시되었습니다.' end;destination=case n->>'audience' when 'parent' then 'parent' when 'student' then 'student' else 'all' end;
 when 'cheongla_questions' then
  if tg_op<>'INSERT' then return new;end if;
  select array_agg(id) into people from public.cheongla_profiles where is_app_admin or role=case n->>'subject' when 'korean' then 'korean_teacher' when 'math' then 'math_director' else 'english_director' end;
  kind='question';target=(n->>'id')::uuid;label='과목 질문이 등록되었습니다.';destination=n->>'subject';
 when 'cheongla_answers' then
  if tg_op='UPDATE' and n->>'body' is not distinct from o->>'body' then return new;end if;
  select student_id,subject into q from public.cheongla_questions where id=(n->>'question_id')::uuid;
  people=array[q.student_id];kind='question';target=(n->>'question_id')::uuid;label='질문에 답변이 등록되었습니다. 답변 완료';destination=q.subject;
 when 'cheongla_qa_messages' then
  if tg_op<>'INSERT' then return new;end if;
  select student_id,subject into q from public.cheongla_questions where id=(n->>'question_id')::uuid;
  if (n->>'author_id')::uuid=q.student_id then
   select array_agg(id) into people from public.cheongla_profiles where is_app_admin or role=case q.subject when 'korean' then 'korean_teacher' when 'math' then 'math_director' else 'english_director' end;
   label='과목 질문에 추가 질문이 등록되었습니다.';
  else people=array[q.student_id];label='질문에 답변이 등록되었습니다. 답변 완료';end if;
  kind='question';target=(n->>'question_id')::uuid;destination=q.subject;
 when 'cheongla_board_posts' then
  if tg_op<>'INSERT' then return new;end if;
  select array_agg(id) into people from public.cheongla_profiles where n->>'visibility'='public' or is_app_admin or role in ('owner','english_director','math_director','manager');
  kind='board';target=(n->>'id')::uuid;label='새 상담문의가 등록되었습니다.';destination='question_board';
 when 'cheongla_board_replies' then
  if tg_op<>'INSERT' then return new;end if;
  select author_id into q from public.cheongla_board_posts where id=(n->>'post_id')::uuid;
  if (n->>'author_id')::uuid=q.author_id then
   select array_agg(id) into people from public.cheongla_profiles where is_app_admin or role in ('owner','english_director','math_director','manager');
   label='상담문의에 추가 질문이 등록되었습니다.';
  else people=array[q.author_id];label='상담문의에 답변이 등록되었습니다. 답변 완료';end if;
  kind='board';target=(n->>'post_id')::uuid;destination='question_board';
 when 'cheongla_tuition_notices','cheongla_exam_fee_notices' then
  if n->>'status'<>'published' or (tg_op='UPDATE' and o->>'status'='published') then return new;end if;
  student=(n->>'student_id')::uuid;
  select array_agg(p.id) into people from public.cheongla_profiles p where p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.parent_id=p.id and l.student_id=student);
  target=(n->>'id')::uuid;
  if tg_table_name='cheongla_tuition_notices' then kind='tuition';label='학원비 안내가 게시되었습니다.';destination='desk_tuition';else kind='exam_fee';label='모의고사 응시료 안내가 게시되었습니다.';destination='desk_fees';end if;
 when 'cheongla_exams' then
  if n->>'deleted_at' is not null then return new;end if;
  if n->>'status' not in ('open','closed') or (tg_op='INSERT' and n->>'status'<>'open') then return new;end if;
  if tg_op='UPDATE' and (n->>'title',n->>'body',n->>'exam_on',n->>'deadline',n->>'status') is not distinct from (o->>'title',o->>'body',o->>'exam_on',o->>'deadline',o->>'status') then return new;end if;
  select array_agg(id) into people from public.cheongla_profiles where is_app_admin or role in ('owner','english_director','math_director','manager','student');
  kind='exam';target=(n->>'id')::uuid;label='모의고사 신청 안내가 게시되었습니다.';destination='desk_exams';
 when 'cheongla_exam_applications' then
  if tg_op='UPDATE' and n->>'status' is not distinct from o->>'status' then return new;end if;
  student=(n->>'student_id')::uuid;
  select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role in ('owner','english_director','math_director','manager') or p.id=student;
  kind='application';target=(n->>'exam_id')::uuid;label='모의고사 신청 내역이 변경되었습니다.';destination='desk_exams';
 when 'cheongla_schedule_events' then
  if n->>'status'<>'published' then return new;end if;
  if tg_op='UPDATE' and (n->>'title',n->>'body',n->>'starts_on',n->>'ends_on',n->>'event_time',n->>'audience',n->>'status') is not distinct from (o->>'title',o->>'body',o->>'starts_on',o->>'ends_on',o->>'event_time',o->>'audience',o->>'status') then return new;end if;
  select array_agg(id) into people from public.cheongla_profiles where is_app_admin or role in ('owner','english_director','math_director','manager') or n->>'audience'='all' or role=n->>'audience';
  kind='schedule';target=(n->>'id')::uuid;label='월간일정이 게시되었습니다.';destination='schedule';
 else return new;
 end case;
 perform cheongla_private.send_notification(people,kind,target,student,label,destination,event_id);
 return new;
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_read_notification(kind text, target uuid, student uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me public.cheongla_profiles%rowtype;q record;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved' and membership_state='active';
 if not found then return false;end if;
 if kind='member_request' then return cheongla_private.is_principal()and exists(select 1 from public.cheongla_profiles where id=target);end if;
 if kind='parent_link' then return target=me.id and me.role='parent' and exists(select 1 from public.cheongla_parent_students l join public.cheongla_profiles s on s.id=l.student_id where l.parent_id=me.id and l.student_id=student and s.role='student' and s.approval_status='approved' and s.membership_state='active');end if;
 if kind='member_approved' then return target=me.id;end if;
 if kind='fee_collection' then return exists(select 1 from cheongla_private.collection_notices n where n.id=target and cheongla_private.can_read_collection(n.fee_kind,n.id));end if;
 if kind='contact_update' then return cheongla_private.can_manage_tuition();end if;
 if kind='meal_submission' then return cheongla_private.can_manage_meal_forms();end if;
 if kind='daily_word' then return exists(select 1 from public.cheongla_daily_words where id=target and status='published' and message_on <= (now() at time zone 'Asia/Seoul')::date);end if;
 if kind='information' then return exists(select 1 from public.cheongla_information_posts where id=target and status='published' and deleted_at is null);end if;
 case kind
 when 'notice' then return exists(select 1 from public.cheongla_notices n where n.id=target and (n.audience='all' or n.audience=me.role or me.role in ('owner','english_director','math_director','korean_teacher','manager')));
 when 'question' then
  select student_id,subject into q from public.cheongla_questions where id=target;
  return found and cheongla_private.can_read_question(q.student_id,q.subject);
 when 'new_inquiry' then return cheongla_private.can_manage_consultations() and exists(select 1 from public.cheongla_new_inquiries where id=target);
 when 'board' then return cheongla_private.can_read_board_post(target);
 when 'tuition' then return exists(select 1 from public.cheongla_tuition_notices n where n.id=target and (cheongla_private.can_manage_tuition() or (n.status='published' and cheongla_private.is_parent_of(n.student_id))));
 when 'exam' then return exists(select 1 from public.cheongla_exams e where e.id=target and e.deleted_at is null and (cheongla_private.can_manage_exams() or (e.status in ('open','closed') and cheongla_private.can_view_exams())));
 when 'application' then return exists(select 1 from public.cheongla_exam_applications a where a.exam_id=target and a.student_id=student and (cheongla_private.can_manage_exams() or me.id=student));
 when 'exam_fee' then return exists(select 1 from public.cheongla_exam_fee_notices n where n.id=target and (cheongla_private.can_manage_exams() or (n.status='published' and cheongla_private.can_read_exam_fee(n.exam_id,n.student_id))));
 when 'schedule' then return exists(select 1 from public.cheongla_schedule_events e where e.id=target and (cheongla_private.can_manage_schedule() or (e.status='published' and (e.audience='all' or e.audience=me.role))));
 else return false;
 end case;
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_submit_student_meal(target_student uuid, target_month date, lunch_dates date[], dinner_dates date[], student_note text, expected_updated_at timestamp with time zone, expected_form_updated_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.cheongla_meal_forms%rowtype;s public.cheongla_meal_submissions%rowtype;n text;today date:=(clock_timestamp() at time zone 'Asia/Seoul')::date;l date[];d date[];
begin
 select full_name into n from public.cheongla_profiles where id=target_student and cheongla_private.can_apply_for(target_student);
 if not found then raise exception '승인된 학생 계정으로 신청해 주세요.' using errcode='42501';end if;
 select * into f from public.cheongla_meal_forms where month=target_month for update;
 if not found then raise exception '아직 등록되지 않은 월의 신청서입니다.';end if;
 if f.updated_at is distinct from expected_form_updated_at then raise exception '신청 안내가 변경되었습니다. 새로고침 후 확인해 주세요.';end if;
 if lunch_dates is null or dinner_dates is null or cardinality(lunch_dates)>31 or cardinality(dinner_dates)>31 or student_note is null or length(student_note)>1000 then raise exception '신청 내용과 비고를 확인해 주세요.';end if;
 if exists(select 1 from unnest(lunch_dates||dinner_dates) x where x is null or x<target_month or x>=(target_month+interval '1 month')::date or extract(isodow from x)=7) then raise exception '해당 월의 월요일부터 토요일까지 선택해 주세요.';end if;
 select coalesce(array_agg(distinct x order by x),'{}') into l from unnest(lunch_dates) x;
 select coalesce(array_agg(distinct x order by x),'{}') into d from unnest(dinner_dates) x;
 select * into s from public.cheongla_meal_submissions where month=target_month and student_id=target_student for update;
 if s.updated_at is distinct from expected_updated_at then raise exception '다른 화면에서 신청 내용이 변경되었습니다. 새로고침 후 확인해 주세요.';end if;

 if s.student_id is not null and (not s.lunch<@l or not s.dinner<@d) then raise exception '도시락 취소는 전날까지 학원 휴대폰으로 전화 또는 문자 문의해 주세요. 앱에서는 직접 취소할 수 없습니다.';end if;
 if today>f.deadline and (s.student_id is null or not l<@s.lunch or not d<@s.dinner) then raise exception '제출 기한이 지났습니다. 추가 신청은 관리자에게 문의해 주세요.';end if;
 if exists(select 1 from ((select unnest(l) except select unnest(coalesce(s.lunch,'{}'))) union all (select unnest(coalesce(s.lunch,'{}')) except select unnest(l)) union all (select unnest(d) except select unnest(coalesce(s.dinner,'{}'))) union all (select unnest(coalesce(s.dinner,'{}')) except select unnest(d))) changes(x) where x<=today) then raise exception '식사 당일과 지난 날짜는 신청·취소할 수 없습니다.';end if;
 insert into public.cheongla_meal_submissions(month,student_id,student_name,lunch,dinner,note) values(target_month,target_student,n,l,d,student_note)
 on conflict(month,student_id) do update set student_name=excluded.student_name,lunch=excluded.lunch,dinner=excluded.dinner,note=excluded.note,updated_at=clock_timestamp();
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_submit_meal_form(target_month date, lunch_dates date[], dinner_dates date[], student_note text, expected_updated_at timestamp with time zone, expected_form_updated_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.cheongla_meal_forms%rowtype;s public.cheongla_meal_submissions%rowtype;n text;today date:=(clock_timestamp() at time zone 'Asia/Seoul')::date;l date[];d date[];
begin
 select full_name into n from public.cheongla_profiles where id=(select auth.uid()) and role='student' and approval_status='approved' and membership_state='active';
 if not found then raise exception '승인된 학생 계정으로 신청해 주세요.' using errcode='42501';end if;
 select * into f from public.cheongla_meal_forms where month=target_month for update;
 if not found then raise exception '아직 등록되지 않은 월의 신청서입니다.';end if;
 if f.updated_at is distinct from expected_form_updated_at then raise exception '신청 안내가 변경되었습니다. 새로고침 후 확인해 주세요.';end if;
 if lunch_dates is null or dinner_dates is null or cardinality(lunch_dates)>31 or cardinality(dinner_dates)>31 or student_note is null or length(student_note)>1000 then raise exception '신청 내용과 비고를 확인해 주세요.';end if;
 if exists(select 1 from unnest(lunch_dates||dinner_dates) x where x is null or x<target_month or x>=(target_month+interval '1 month')::date or extract(isodow from x)=7) then raise exception '해당 월의 월요일부터 토요일까지 선택해 주세요.';end if;
 select coalesce(array_agg(distinct x order by x),'{}') into l from unnest(lunch_dates) x;
 select coalesce(array_agg(distinct x order by x),'{}') into d from unnest(dinner_dates) x;
 select * into s from public.cheongla_meal_submissions where month=target_month and student_id=(select auth.uid()) for update;
 if s.updated_at is distinct from expected_updated_at then raise exception '다른 화면에서 신청 내용이 변경되었습니다. 새로고침 후 확인해 주세요.';end if;

 if s.student_id is not null and (not s.lunch<@l or not s.dinner<@d) then raise exception '도시락 취소는 전날까지 학원 휴대폰으로 전화 또는 문자 문의해 주세요. 앱에서는 직접 취소할 수 없습니다.';end if;
 if today>f.deadline and (s.student_id is null or not l<@s.lunch or not d<@s.dinner) then raise exception '제출 기한이 지났습니다. 추가 신청은 관리자에게 문의해 주세요.';end if;
 if exists(select 1 from ((select unnest(l) except select unnest(coalesce(s.lunch,'{}'))) union all (select unnest(coalesce(s.lunch,'{}')) except select unnest(l)) union all (select unnest(d) except select unnest(coalesce(s.dinner,'{}'))) union all (select unnest(coalesce(s.dinner,'{}')) except select unnest(d))) changes(x) where x<=today) then raise exception '식사 당일과 지난 날짜는 신청·취소할 수 없습니다.';end if;
 insert into public.cheongla_meal_submissions(month,student_id,student_name,lunch,dinner,note) values(target_month,(select auth.uid()),n,l,d,student_note)
 on conflict(month,student_id) do update set student_name=excluded.student_name,lunch=excluded.lunch,dinner=excluded.dinner,note=excluded.note,updated_at=clock_timestamp();
end;$function$
;
alter policy cheongla_exam_application_read on public.cheongla_exam_applications using (
 cheongla_private.can_manage_exams() or (student_id=auth.uid() and cheongla_private.can_apply_for(student_id) and exists(select 1 from public.cheongla_exams e where e.id=exam_id and e.deleted_at is null and e.status in('open','closed'))));
alter policy meal_form_read on public.cheongla_meal_forms using (
 cheongla_private.can_manage_meal_forms() or exists(select 1 from public.cheongla_profiles where id=auth.uid() and role='student' and approval_status='approved' and membership_state='active'));;

CREATE OR REPLACE FUNCTION cheongla_private.notify_collection(kind text, target uuid, admin_only boolean, label text, event_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n record;people uuid[];begin
 select * into n from cheongla_private.collection_notices where fee_kind=kind and id=target;if not found then return;end if;
 select array_agg(p.id) into people from public.cheongla_profiles p where (admin_only and (p.is_app_admin or p.role in ('owner','english_director','math_director','manager'))) or (not admin_only and p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.student_id=n.student_id and l.parent_id=p.id));
 perform cheongla_private.send_notification(people,'fee_collection',target,n.student_id,n.student_name||' · '||to_char(n.billing_month,'YYYY-MM')||' · '||case kind when 'meal' then '도시락비' when 'exam' then '모의고사비' else '학원비' end||' · '||to_char(n.amount,'FM999,999,999')||'원 · '||label,'billing_dashboard',event_key);
end;$function$
;

CREATE OR REPLACE FUNCTION public.cheongla_read_meal_form(target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare manager boolean:=cheongla_private.can_manage_meal_forms();result jsonb;
begin
 if not manager and not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role='student' and approval_status='approved' and membership_state='active') then raise exception '승인된 학생과 관리자만 이용할 수 있습니다.' using errcode='42501';end if;
 select jsonb_build_object('cancellations',case when manager then coalesce((select jsonb_agg(to_jsonb(c)) from cheongla_private.meal_cancellations c where c.month=target_month),'[]'::jsonb)else '[]'::jsonb end,'form',(select to_jsonb(f) from public.cheongla_meal_forms f where month=target_month),'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.student_name,s.student_id) from public.cheongla_meal_submissions s where month=target_month and s.archived_at is null and (manager or cheongla_private.can_apply_for(s.student_id))),'[]'::jsonb),'bills',case when manager then coalesce((select jsonb_agg(to_jsonb(b)) from public.cheongla_meal_bills b where b.month=target_month and b.archived_at is null),'[]'::jsonb) else '[]'::jsonb end,'today',(now() at time zone 'Asia/Seoul')::date) into result;
 return result;
end;$function$
;

create table if not exists cheongla_private.exam_fee_archives(id uuid primary key,snapshot jsonb not null,archived_at timestamptz not null default clock_timestamp());
alter table cheongla_private.exam_fee_archives enable row level security;
revoke all on cheongla_private.exam_fee_archives from public,anon,authenticated;
create or replace view cheongla_private.collection_notices as
SELECT 'tuition'::text AS fee_kind,
    t.id,
    t.student_id,
    t.student_name,
    t.billing_month,
    (t.billing_month::text || ' '::text) ||
        CASE t.program
            WHEN 'repeat'::text THEN '재수생 학원비'::text
            WHEN 'school'::text THEN '재학생 학원비'::text
            WHEN 'winter'::text THEN '윈터스쿨 학원비'::text
            WHEN 'summer'::text THEN '썸머스쿨 학원비'::text
            WHEN 'civil'::text THEN '공시생 학원비'::text
            ELSE '학원비'::text
        END AS label,
    t.amount,
    t.due_on,
    t.note,
    t.status,
    t.updated_at,
    true AS eligible,
    true AS source_current,
    to_jsonb(t.*) AS details
   FROM cheongla_tuition_notices t
  WHERE t.archived_at IS NULL
UNION ALL
 SELECT 'exam'::text AS fee_kind,
    e.id,
    e.student_id,
    e.student_name,
    date_trunc('month'::text, e.exam_on::timestamp with time zone)::date AS billing_month,
    e.exam_title || ' 모의고사비'::text AS label,
    e.amount,
    e.due_on,
    e.note,
    e.status,
    e.updated_at,
    (EXISTS ( SELECT 1
           FROM cheongla_exam_applications a
             JOIN cheongla_exams x ON x.id = a.exam_id
          WHERE a.exam_id = e.exam_id AND a.student_id = e.student_id AND a.status = 'registered'::text AND (to_jsonb(x.*) ->> 'deleted_at'::text) IS NULL)) AS eligible,
    true AS source_current,
    to_jsonb(e.*) AS details
   FROM cheongla_exam_fee_notices e
UNION ALL
 SELECT 'meal'::text AS fee_kind,
    b.id,
    b.student_id,
    b.student_name,
    b.month AS billing_month,
    b.month::text || ' 도시락비'::text AS label,
    b.amount,
    b.due_on,
    b.note,
    b.status,
    b.updated_at,
    true AS eligible,
    (EXISTS ( SELECT 1
           FROM cheongla_meal_submissions s
          WHERE s.month = b.month AND s.student_id = b.student_id AND s.updated_at = b.source_updated_at)) AS source_current,
    to_jsonb(b.*) AS details
   FROM cheongla_meal_bills b
  WHERE b.archived_at IS NULL
union all select 'exam'::text,e.id,e.student_id,e.student_name,date_trunc('month',e.exam_on)::date,e.exam_title||' 모의고사비',e.amount,e.due_on,e.note,e.status,e.updated_at,false,true,to_jsonb(e)||jsonb_build_object('exam_archived',true)
from cheongla_private.exam_fee_archives a cross join lateral jsonb_populate_record(null::public.cheongla_exam_fee_notices,a.snapshot)e;

CREATE OR REPLACE FUNCTION public.cheongla_purge_deleted_exam(target_exam uuid, expected_updated_at timestamp with time zone, expected_deleted_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not cheongla_private.is_principal()then raise exception '원장만 영구 삭제할 수 있습니다.'using errcode='42501';end if;
 perform 1 from public.cheongla_exams where id=target_exam for update;
 if exists(select 1 from cheongla_private.fee_deposit_reports r join public.cheongla_exam_fee_notices f on f.id=r.notice_id where r.fee_kind='exam'and f.exam_id=target_exam and r.state='pending')then raise exception '입금 확인 대기 중인 청구가 있습니다. 입금 확인 또는 반려 처리 후 영구 삭제해 주세요.';end if;
 return cheongla_private.purge_deleted_exam_impl(target_exam,expected_updated_at,expected_deleted_at);
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.purge_deleted_exam_impl(target_exam uuid, expected_updated_at timestamp with time zone, expected_deleted_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e public.cheongla_exams%rowtype;notice uuid;fees uuid[];applications integer;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 삭제한 시험을 영구 삭제할 수 있습니다.'using errcode='42501';end if;
 select * into e from public.cheongla_exams where id=target_exam for update;
 if not found then raise exception '이미 영구 삭제되었거나 없는 시험입니다.';end if;
 if e.updated_at is distinct from expected_updated_at or e.deleted_at is distinct from expected_deleted_at then raise exception '시험 정보가 변경되었습니다. 시험 새로고침 후 확인해 주세요.';end if;
 if e.deleted_at is null then raise exception '삭제한 시험 목록의 시험만 영구 삭제할 수 있습니다.';end if;
 -- Root and application locks prevent concurrent re-application/new fee notices.
 perform 1 from public.cheongla_exam_applications where exam_id=e.id order by student_id for update;
 select count(*) into applications from public.cheongla_exam_applications where exam_id=e.id;
 select coalesce(array_agg(id order by id),'{}'::uuid[])into fees from public.cheongla_exam_fee_notices where exam_id=e.id;
 foreach notice in array fees loop perform cheongla_private.lock_collection('exam',notice);end loop;
 insert into cheongla_private.exam_fee_archives(id,snapshot)
 select f.id,to_jsonb(f) from public.cheongla_exam_fee_notices f where f.id=any(fees) and (
 exists(select 1 from cheongla_private.fee_payments where notice_kind='exam' and notice_id=f.id)
 or exists(select 1 from cheongla_private.fee_deposit_reports where fee_kind='exam' and notice_id=f.id)
 or exists(select 1 from cheongla_private.fee_payment_events where fee_kind='exam' and notice_id=f.id)
 or exists(select 1 from cheongla_private.bank_confirmations where fee_kind='exam' and notice_id=f.id))
 on conflict(id) do nothing;
 insert into cheongla_private.exam_purge_events(exam_id,actor_id,application_count,fee_count)values(e.id,auth.uid(),applications,cardinality(fees));
 -- Remove stale links; push queue rows cascade from notification deletion.
 delete from public.cheongla_notifications where(source_kind in('exam','application')and source_id=e.id)
 or(source_kind in('exam_fee','fee_collection')and source_id=any(fees) and not exists(select 1 from cheongla_private.exam_fee_archives a where a.id=source_id));
 -- Existing FK cascades remove the applications, uncollected fee notices and fee settings.
 delete from public.cheongla_exams where id=e.id;
 return e.id;
end;$function$
;

revoke all on function cheongla_private.purge_deleted_exam_impl(uuid,timestamptz,timestamptz)from public,anon,authenticated;
revoke all on function public.cheongla_purge_deleted_exam(uuid,timestamptz,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_purge_deleted_exam(uuid,timestamptz,timestamptz)to authenticated;
notify pgrst,'reload schema';

