begin;
create or replace function cheongla_private.can_manage_tuition() returns boolean language sql stable security definer set search_path='' as $$ select cheongla_private.can_use_member_services() and exists(select 1 from public.cheongla_profiles where id=auth.uid() and (is_app_admin or role in ('owner','english_director','math_director','manager'))); $$;
create or replace function cheongla_private.can_manage_exams() returns boolean language sql stable security definer set search_path='' as $$ select cheongla_private.can_use_member_services() and exists(select 1 from public.cheongla_profiles where id=auth.uid() and (is_app_admin or role in ('owner','english_director','math_director','manager'))); $$;
create or replace function cheongla_private.can_view_exams() returns boolean language sql stable security definer set search_path='' as $$ select cheongla_private.can_use_member_services() and exists(select 1 from public.cheongla_profiles where id=auth.uid() and (is_app_admin or role in ('owner','english_director','math_director','manager','student','parent'))); $$;
create or replace function cheongla_private.can_apply_for(student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.can_use_member_services() and exists(select 1 from public.cheongla_profiles s where s.id=student and s.role='student' and s.approval_status='approved' and s.membership_state='active' and (s.id=auth.uid() or cheongla_private.is_parent_of(s.id)));
$$;
revoke all on function cheongla_private.can_apply_for(uuid) from public,anon,authenticated;
create or replace function public.cheongla_application_students() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name) order by p.full_name,p.id),'[]'::jsonb) from public.cheongla_profiles p where cheongla_private.can_apply_for(p.id);
$$;
create or replace function public.cheongla_member_contacts()
returns table(member_id uuid,full_name text,role text,approval_status text,email text,phone text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.cheongla_profiles p where p.id=(select auth.uid())
 and p.approval_status='approved' and (p.is_app_admin or p.role in ('owner','english_director','math_director','manager')) and p.membership_state='active') then
  raise exception '앱 관리자와 실장만 연락처를 확인할 수 있습니다.' using errcode='42501';
 end if;
 return query select p.id,p.full_name::text,p.role::text,p.approval_status::text,u.email::text,c.phone
 from public.cheongla_profiles p join auth.users u on u.id=p.id
 left join cheongla_private.member_contacts c on c.user_id=p.id
 where p.role in ('student','parent') and p.membership_state='active'
 order by p.full_name,p.id;
end;
$$;
create or replace function public.cheongla_submit_student_meal(target_student uuid,target_month date,lunch_dates date[],dinner_dates date[],student_note text,expected_updated_at timestamptz,expected_form_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
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
 if today>f.deadline and (s.student_id is null or not l<@s.lunch or not d<@s.dinner) then raise exception '제출 기한이 지났습니다. 추가 신청은 관리자에게 문의해 주세요.';end if;
 if exists(select 1 from ((select unnest(l) except select unnest(coalesce(s.lunch,'{}'))) union all (select unnest(coalesce(s.lunch,'{}')) except select unnest(l)) union all (select unnest(d) except select unnest(coalesce(s.dinner,'{}'))) union all (select unnest(coalesce(s.dinner,'{}')) except select unnest(d))) changes(x) where x<=today) then raise exception '식사 당일과 지난 날짜는 신청·취소할 수 없습니다.';end if;
 insert into public.cheongla_meal_submissions(month,student_id,student_name,lunch,dinner,note) values(target_month,target_student,n,l,d,student_note)
 on conflict(month,student_id) do update set student_name=excluded.student_name,lunch=excluded.lunch,dinner=excluded.dinner,note=excluded.note,updated_at=clock_timestamp();
end;$$;
create or replace function public.cheongla_apply_student_exam(target_student uuid,target_exam uuid,application_action text)
returns uuid language plpgsql security definer set search_path='' as $$
declare exam public.cheongla_exams%rowtype;student_label text;old_status text;
begin
 select full_name into student_label from public.cheongla_profiles
 where id=target_student and cheongla_private.can_apply_for(target_student);
 if not found then raise exception '승인된 학생 계정으로 신청해 주세요.' using errcode='42501';end if;
 if application_action is null or application_action not in ('register','cancel') then
  raise exception '신청 또는 취소를 선택해 주세요.';end if;
 select * into exam from public.cheongla_exams where id=target_exam for update;
 if not found or exam.deleted_at is not null then raise exception '삭제된 시험은 신청할 수 없습니다.';end if;
 if exam.status<>'open' or exam.deadline<=clock_timestamp() then
  raise exception '신청이 마감되었습니다. 실장에게 문의해 주세요.';end if;
 select status into old_status from public.cheongla_exam_applications
 where exam_id=target_exam and student_id=target_student;
 if application_action='cancel' then
  if old_status is null then raise exception '신청 내역이 없습니다.';end if;
  update public.cheongla_exam_applications set status='canceled',updated_at=clock_timestamp()
  where exam_id=target_exam and student_id=target_student and status='registered';
 else
  insert into public.cheongla_exam_applications(exam_id,student_id,student_name,status)
  values(target_exam,target_student,student_label,'registered')
  on conflict(exam_id,student_id) do update set student_name=excluded.student_name,status='registered',
  registered_at=clock_timestamp(),updated_at=clock_timestamp()
  where public.cheongla_exam_applications.status='canceled';
 end if;
 return target_exam;
end;
$$;
create or replace function public.cheongla_read_meal_form(target_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean:=cheongla_private.can_manage_meal_forms();result jsonb;
begin
 if not manager and not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role in ('student','parent') and approval_status='approved' and membership_state='active') then raise exception '승인된 학생과 관리자만 이용할 수 있습니다.' using errcode='42501';end if;
 select jsonb_build_object('form',(select to_jsonb(f) from public.cheongla_meal_forms f where month=target_month),'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.student_name,s.student_id) from public.cheongla_meal_submissions s where month=target_month and (manager or cheongla_private.can_apply_for(s.student_id))),'[]'::jsonb),'bills',case when manager then coalesce((select jsonb_agg(to_jsonb(b)) from public.cheongla_meal_bills b where b.month=target_month),'[]'::jsonb) else '[]'::jsonb end,'today',(now() at time zone 'Asia/Seoul')::date) into result;
 return result;
end;$$;
drop policy if exists meal_form_read on public.cheongla_meal_forms;
create policy meal_form_read on public.cheongla_meal_forms for select to authenticated using(cheongla_private.can_manage_meal_forms() or exists(select 1 from public.cheongla_profiles where id=auth.uid() and approval_status='approved' and role in ('student','parent')));
drop policy if exists meal_submission_read on public.cheongla_meal_submissions;
create policy meal_submission_read on public.cheongla_meal_submissions for select to authenticated using(cheongla_private.can_manage_meal_forms() or cheongla_private.can_apply_for(student_id));
grant execute on function cheongla_private.can_apply_for(uuid) to authenticated;
create or replace function cheongla_private.create_event_notifications()
returns trigger language plpgsql security definer set search_path='' as $$
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
  select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role in ('owner','english_director','math_director','manager') or (p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.parent_id=p.id and l.student_id=student));
  target=(n->>'id')::uuid;
  if tg_table_name='cheongla_tuition_notices' then kind='tuition';label='학원비 안내가 게시되었습니다.';destination='desk_tuition';else kind='exam_fee';label='모의고사 응시료 안내가 게시되었습니다.';destination='desk_fees';end if;
 when 'cheongla_exams' then
  if n->>'status'<>'open' or (tg_op='UPDATE' and o->>'status'='open') then return new;end if;
  select array_agg(id) into people from public.cheongla_profiles where is_app_admin or role in ('manager','student','parent');
  kind='exam';target=(n->>'id')::uuid;label='모의고사 신청 안내가 게시되었습니다.';destination='desk_exams';
 when 'cheongla_exam_applications' then
  if tg_op='UPDATE' and n->>'status' is not distinct from o->>'status' then return new;end if;
  student=(n->>'student_id')::uuid;
  select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role in ('owner','english_director','math_director','manager') or (p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.parent_id=p.id and l.student_id=student));
  kind='application';target=(n->>'exam_id')::uuid;label='모의고사 신청 내역이 변경되었습니다.';destination='desk_exams';
 when 'cheongla_schedule_events' then
  if n->>'status'<>'published' or (tg_op='UPDATE' and o->>'status'='published') then return new;end if;
  select array_agg(id) into people from public.cheongla_profiles where is_app_admin or role='manager' or n->>'audience'='all' or role=n->>'audience';
  kind='schedule';target=(n->>'id')::uuid;label='월간일정이 게시되었습니다.';destination='schedule';
 else return new;
 end case;
 perform cheongla_private.send_notification(people,kind,target,student,label,destination,event_id);
 return new;
end;$$;
create or replace function cheongla_private.can_read_notification(kind text,target uuid,student uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;q record;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved';
 if not found then return false;end if;
 if kind='fee_collection' then return exists(select 1 from cheongla_private.collection_notices n where n.id=target and cheongla_private.can_read_collection(n.fee_kind,n.id));end if;
 if kind='contact_update' then return cheongla_private.can_manage_tuition();end if;
 if kind='meal_submission' then return cheongla_private.can_manage_meal_forms();end if;
 case kind
 when 'notice' then return exists(select 1 from public.cheongla_notices n where n.id=target and (n.audience='all' or n.audience=me.role or me.role in ('owner','english_director','math_director','korean_teacher','manager')));
 when 'question' then
  select student_id,subject into q from public.cheongla_questions where id=target;
  return found and cheongla_private.can_read_question(q.student_id,q.subject);
 when 'new_inquiry' then return cheongla_private.can_manage_consultations() and exists(select 1 from public.cheongla_new_inquiries where id=target);
 when 'board' then return cheongla_private.can_read_board_post(target);
 when 'tuition' then return exists(select 1 from public.cheongla_tuition_notices n where n.id=target and (cheongla_private.can_manage_tuition() or (n.status='published' and cheongla_private.is_parent_of(n.student_id))));
 when 'exam' then return exists(select 1 from public.cheongla_exams e where e.id=target and (cheongla_private.can_manage_exams() or (e.status in ('open','closed') and cheongla_private.can_view_exams())));
 when 'application' then return exists(select 1 from public.cheongla_exam_applications a where a.exam_id=target and a.student_id=student and (cheongla_private.can_manage_exams() or cheongla_private.is_parent_of(student) or me.id=student));
 when 'exam_fee' then return exists(select 1 from public.cheongla_exam_fee_notices n where n.id=target and (cheongla_private.can_manage_exams() or (n.status='published' and cheongla_private.can_read_exam_fee(n.exam_id,n.student_id))));
 when 'schedule' then return exists(select 1 from public.cheongla_schedule_events e where e.id=target and (cheongla_private.can_manage_schedule() or (e.status='published' and (e.audience='all' or e.audience=me.role))));
 else return false;
 end case;
end;$$;
create or replace function cheongla_private.notify_meal_submission() returns trigger language plpgsql security definer set search_path='' as $$
declare people uuid[];
begin
 select array_agg(id) into people from public.cheongla_profiles where approval_status='approved' and membership_state='active' and (is_app_admin or role in ('owner','english_director','math_director','manager'));
 perform cheongla_private.send_notification(people,'meal_submission',new.student_id,new.student_id,new.student_name||' · 도시락 '||case when tg_op='INSERT' then '신청완료' else '신청 변경' end,'meal_forms','meal:'||new.month::text||':'||new.student_id::text||':'||new.updated_at::text);
 return new;
end;$$;
revoke all on function cheongla_private.notify_meal_submission() from public,anon,authenticated;
drop trigger if exists cheongla_meal_submission_notification on public.cheongla_meal_submissions;
create trigger cheongla_meal_submission_notification after insert or update on public.cheongla_meal_submissions for each row execute function cheongla_private.notify_meal_submission();
revoke all on function public.cheongla_application_students() from public,anon,authenticated;
grant execute on function public.cheongla_application_students() to authenticated;
revoke all on function public.cheongla_submit_student_meal(uuid,date,date[],date[],text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_submit_student_meal(uuid,date,date[],date[],text,timestamptz,timestamptz) to authenticated;
revoke all on function public.cheongla_apply_student_exam(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.cheongla_apply_student_exam(uuid,uuid,text) to authenticated;
create or replace function cheongla_private.notify_contact_update() returns trigger language plpgsql security definer set search_path='' as $$
declare people uuid[];label text;
begin
 select full_name into label from public.cheongla_profiles where id=new.user_id and role in ('student','parent') and approval_status='approved' and membership_state='active';
 if not found then return new;end if;
 if tg_op='UPDATE' and new.phone is not distinct from old.phone then return new;end if;
 select array_agg(id) into people from public.cheongla_profiles where approval_status='approved' and membership_state='active' and (is_app_admin or role in ('owner','english_director','math_director','manager'));
 perform cheongla_private.send_notification(people,'contact_update',new.user_id,new.user_id,label||' · 연락처 변경','account_contactManager','contact:'||new.user_id::text||':'||new.updated_at::text);
 return new;
end;$$;
revoke all on function cheongla_private.notify_contact_update() from public,anon,authenticated;
drop trigger if exists cheongla_contact_update_notification on cheongla_private.member_contacts;
create trigger cheongla_contact_update_notification after insert or update on cheongla_private.member_contacts for each row execute function cheongla_private.notify_contact_update();
notify pgrst,'reload schema';
commit;
