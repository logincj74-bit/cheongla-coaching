begin;
create table if not exists public.cheongla_notifications(
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references public.cheongla_profiles(id) on delete cascade,
 source_kind text not null,source_id uuid not null,student_id uuid,
 title text not null,route text not null,event_key text not null,
 created_at timestamptz not null default clock_timestamp(),read_at timestamptz,
 unique(recipient_id,event_key)
);
create index if not exists cheongla_notification_order on public.cheongla_notifications(recipient_id,created_at desc,id desc);
create or replace function cheongla_private.can_read_notification(kind text,target uuid,student uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;q record;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved';
 if not found then return false;end if;
 case kind
 when 'notice' then return exists(select 1 from public.cheongla_notices n where n.id=target and (n.audience='all' or n.audience=me.role or me.role in ('owner','english_director','math_director','korean_teacher','manager')));
 when 'question' then
  select student_id,subject into q from public.cheongla_questions where id=target;
  return found and cheongla_private.can_read_question(q.student_id,q.subject);
 when 'board' then return cheongla_private.can_read_board_post(target);
 when 'tuition' then return exists(select 1 from public.cheongla_tuition_notices n where n.id=target and (cheongla_private.can_manage_tuition() or (n.status='published' and cheongla_private.is_parent_of(n.student_id))));
 when 'exam' then return exists(select 1 from public.cheongla_exams e where e.id=target and (cheongla_private.can_manage_exams() or (e.status in ('open','closed') and cheongla_private.can_view_exams())));
 when 'application' then return exists(select 1 from public.cheongla_exam_applications a where a.exam_id=target and a.student_id=student and (cheongla_private.can_manage_exams() or cheongla_private.is_parent_of(student) or me.id=student));
 when 'exam_fee' then return exists(select 1 from public.cheongla_exam_fee_notices n where n.id=target and (cheongla_private.can_manage_exams() or (n.status='published' and cheongla_private.can_read_exam_fee(n.exam_id,n.student_id))));
 when 'schedule' then return exists(select 1 from public.cheongla_schedule_events e where e.id=target and (cheongla_private.can_manage_schedule() or (e.status='published' and (e.audience='all' or e.audience=me.role))));
 else return false;
 end case;
end;$$;
revoke all on function cheongla_private.can_read_notification(text,uuid,uuid) from public,anon,authenticated;
grant execute on function cheongla_private.can_read_notification(text,uuid,uuid) to authenticated;
alter table public.cheongla_notifications enable row level security;
revoke all on public.cheongla_notifications from public,anon,authenticated;
grant select on public.cheongla_notifications to authenticated;
drop policy if exists cheongla_notification_read on public.cheongla_notifications;
create policy cheongla_notification_read on public.cheongla_notifications for select to authenticated
using (recipient_id=(select auth.uid()) and cheongla_private.can_read_notification(source_kind,source_id,student_id));
create or replace function cheongla_private.send_notification(
 people uuid[],kind text,target uuid,student uuid,label text,destination text,event_id text)
returns void language sql security definer set search_path='' as $$
 insert into public.cheongla_notifications(recipient_id,source_kind,source_id,student_id,title,route,event_key)
 select p.id,kind,target,student,label,destination,event_id
 from public.cheongla_profiles p where p.approval_status='approved'
 and p.id=any(people) and p.id is distinct from (select auth.uid())
 on conflict(recipient_id,event_key) do nothing;
$$;
revoke all on function cheongla_private.send_notification(uuid[],text,uuid,uuid,text,text,text) from public,anon,authenticated;
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
  select array_agg(id) into people from public.cheongla_profiles where n->>'visibility'='public' or is_app_admin;
  kind='board';target=(n->>'id')::uuid;label='새 상담문의가 등록되었습니다.';destination='question_board';
 when 'cheongla_board_replies' then
  if tg_op<>'INSERT' then return new;end if;
  select author_id into q from public.cheongla_board_posts where id=(n->>'post_id')::uuid;
  if (n->>'author_id')::uuid=q.author_id then
   select array_agg(id) into people from public.cheongla_profiles where is_app_admin;
   label='상담문의에 추가 질문이 등록되었습니다.';
  else people=array[q.author_id];label='상담문의에 답변이 등록되었습니다. 답변 완료';end if;
  kind='board';target=(n->>'post_id')::uuid;destination='question_board';
 when 'cheongla_tuition_notices','cheongla_exam_fee_notices' then
  if n->>'status'<>'published' or (tg_op='UPDATE' and o->>'status'='published') then return new;end if;
  student=(n->>'student_id')::uuid;
  select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role='manager' or (p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.parent_id=p.id and l.student_id=student));
  target=(n->>'id')::uuid;
  if tg_table_name='cheongla_tuition_notices' then kind='tuition';label='학원비 안내가 게시되었습니다.';destination='desk_tuition';else kind='exam_fee';label='모의고사 응시료 안내가 게시되었습니다.';destination='desk_fees';end if;
 when 'cheongla_exams' then
  if n->>'status'<>'open' or (tg_op='UPDATE' and o->>'status'='open') then return new;end if;
  select array_agg(id) into people from public.cheongla_profiles where is_app_admin or role in ('manager','student','parent');
  kind='exam';target=(n->>'id')::uuid;label='모의고사 신청 안내가 게시되었습니다.';destination='desk_exams';
 when 'cheongla_exam_applications' then
  if tg_op='UPDATE' and n->>'status' is not distinct from o->>'status' then return new;end if;
  student=(n->>'student_id')::uuid;
  select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role='manager' or (p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.parent_id=p.id and l.student_id=student));
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
revoke all on function cheongla_private.create_event_notifications() from public,anon,authenticated;
do $$
declare table_name text;
begin
 foreach table_name in array array['cheongla_notices','cheongla_questions','cheongla_answers','cheongla_qa_messages','cheongla_board_posts','cheongla_board_replies','cheongla_tuition_notices','cheongla_exam_fee_notices','cheongla_exams','cheongla_exam_applications','cheongla_schedule_events'] loop
  if to_regclass(format('public.%I',table_name)) is not null then
   execute format('drop trigger if exists cheongla_notify_event on public.%I',table_name);
   execute format('create trigger cheongla_notify_event after insert or update on public.%I for each row execute function cheongla_private.create_event_notifications()',table_name);
  end if;
 end loop;
end;$$;
create or replace function public.cheongla_my_notifications(page_limit integer default 20)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare items jsonb;unread bigint;
begin
 if page_limit is null or page_limit not between 1 and 200 then raise exception '알림 조회 범위를 확인해 주세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc,n.id desc),'[]'::jsonb) into items from (select * from public.cheongla_notifications order by created_at desc,id desc limit page_limit) n;
 select count(*) into unread from public.cheongla_notifications where read_at is null;
 return jsonb_build_object('items',items,'unread_count',unread);
end;$$;
create or replace function public.cheongla_read_notification(target_notification uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 update public.cheongla_notifications set read_at=clock_timestamp()
 where recipient_id=(select auth.uid()) and read_at is null
 and (target_notification is null or id=target_notification)
 and cheongla_private.can_read_notification(source_kind,source_id,student_id);
end;$$;
revoke all on function public.cheongla_my_notifications(integer),public.cheongla_read_notification(uuid) from public,anon,authenticated;
grant execute on function public.cheongla_my_notifications(integer),public.cheongla_read_notification(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
