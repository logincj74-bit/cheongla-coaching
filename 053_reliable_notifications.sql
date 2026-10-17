begin;
-- Publication and its recipient inbox rows commit together; include the publisher.
create or replace function cheongla_private.send_notification(
 people uuid[],kind text,target uuid,student uuid,label text,destination text,event_id text)
returns void language sql security definer set search_path='' as $$
 insert into public.cheongla_notifications(recipient_id,source_kind,source_id,student_id,title,route,event_key)
 select p.id,kind,target,student,label,destination,event_id
 from public.cheongla_profiles p where p.approval_status='approved' and p.membership_state='active'
 and p.id=any(people)
 on conflict(recipient_id,event_key) do nothing;
$$;
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
  if n->>'deleted_at' is not null then return new;end if;
  if n->>'status' not in ('open','closed') or (tg_op='INSERT' and n->>'status'<>'open') then return new;end if;
  if tg_op='UPDATE' and (n->>'title',n->>'body',n->>'exam_on',n->>'deadline',n->>'status') is not distinct from (o->>'title',o->>'body',o->>'exam_on',o->>'deadline',o->>'status') then return new;end if;
  select array_agg(id) into people from public.cheongla_profiles where is_app_admin or role in ('owner','english_director','math_director','manager','student','parent');
  kind='exam';target=(n->>'id')::uuid;label='모의고사 신청 안내가 게시되었습니다.';destination='desk_exams';
 when 'cheongla_exam_applications' then
  if tg_op='UPDATE' and n->>'status' is not distinct from o->>'status' then return new;end if;
  student=(n->>'student_id')::uuid;
  select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role in ('owner','english_director','math_director','manager') or (p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.parent_id=p.id and l.student_id=student));
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
end;$$;
create or replace function cheongla_private.notify_collection(kind text,target uuid,admin_only boolean,label text,event_key text) returns void language plpgsql security definer set search_path='' as $$
declare n record;people uuid[];begin
 select * into n from cheongla_private.collection_notices where fee_kind=kind and id=target;if not found then return;end if;
 select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role in ('owner','english_director','math_director','manager') or (not admin_only and (p.id=n.student_id or (p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.student_id=n.student_id and l.parent_id=p.id))));
 perform cheongla_private.send_notification(people,'fee_collection',target,n.student_id,label,'billing_dashboard',event_key);
end;$$;
revoke all on function cheongla_private.notify_collection(text,uuid,boolean,text,text) from public,anon,authenticated;
create or replace function cheongla_private.can_read_notification(kind text,target uuid,student uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;q record;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved' and membership_state='active';
 if not found then return false;end if;
 if kind='fee_collection' then return exists(select 1 from cheongla_private.collection_notices n where n.id=target and cheongla_private.can_read_collection(n.fee_kind,n.id));end if;
 if kind='contact_update' then return cheongla_private.can_manage_tuition();end if;
 if kind='meal_submission' then return cheongla_private.can_manage_meal_forms();end if;
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
 when 'application' then return exists(select 1 from public.cheongla_exam_applications a where a.exam_id=target and a.student_id=student and (cheongla_private.can_manage_exams() or cheongla_private.is_parent_of(student) or me.id=student));
 when 'exam_fee' then return exists(select 1 from public.cheongla_exam_fee_notices n where n.id=target and (cheongla_private.can_manage_exams() or (n.status='published' and cheongla_private.can_read_exam_fee(n.exam_id,n.student_id))));
 when 'schedule' then return exists(select 1 from public.cheongla_schedule_events e where e.id=target and (cheongla_private.can_manage_schedule() or (e.status='published' and (e.audience='all' or e.audience=me.role))));
 else return false;
 end case;
end;$$;
create or replace function public.cheongla_claim_push_deliveries()
returns jsonb language plpgsql security definer set search_path='' as $$
declare item record;batch jsonb='[]'::jsonb;
begin
 for item in
  select d.id as delivery_id,d.attempts,n.id as notification_id,n.recipient_id,n.source_kind,n.source_id,n.student_id,n.title,s.id as subscription_id,s.endpoint,s.p256dh,s.auth_key,s.enabled
  from cheongla_private.push_deliveries d join public.cheongla_notifications n on n.id=d.notification_id join public.cheongla_push_subscriptions s on s.id=d.subscription_id
  where d.attempts<6 and ((d.state in ('pending','failed') and d.next_attempt_at<=clock_timestamp()) or (d.state='processing' and d.last_attempt_at<clock_timestamp()-interval '3 minutes'))
  order by d.created_at,d.id limit 40 for update of d skip locked
 loop
  if not item.enabled or not exists(select 1 from public.cheongla_push_subscriptions where id=item.subscription_id and user_id=item.recipient_id)
  or not cheongla_private.push_source_allowed(item.recipient_id,item.source_kind,item.source_id,item.student_id) then
   update cheongla_private.push_deliveries set state='cancelled',finished_at=clock_timestamp() where id=item.delivery_id;continue;
  end if;
  update cheongla_private.push_deliveries set state='processing',attempts=attempts+1,last_attempt_at=clock_timestamp() where id=item.delivery_id;
  batch=batch||jsonb_build_array(to_jsonb(item));
 end loop;
 return batch;
end;$$;
create or replace function public.cheongla_finish_push_delivery(delivery bigint,response_status integer)
returns void language plpgsql security definer set search_path='' as $$
declare sub uuid;
begin
 update cheongla_private.push_deliveries set state=case when response_status between 200 and 299 then 'sent' when response_status in (404,410) then 'cancelled' else 'failed' end,
 http_status=response_status,finished_at=case when response_status between 200 and 299 or response_status in (404,410) then clock_timestamp() else null end,next_attempt_at=clock_timestamp()+case when attempts<=1 then interval '1 minute' when attempts=2 then interval '2 minutes' when attempts=3 then interval '5 minutes' when attempts=4 then interval '15 minutes' else interval '30 minutes' end
 where id=delivery and state='processing' returning subscription_id into sub;
 if response_status in (404,410) and sub is not null then update public.cheongla_push_subscriptions set enabled=false where id=sub;end if;
end;$$;
-- Durable outbox is independent of dispatcher availability.
create or replace function cheongla_private.enqueue_push_notification()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into cheongla_private.push_deliveries(notification_id,subscription_id)
 select new.id,s.id from public.cheongla_push_subscriptions s
 where s.user_id=new.recipient_id and s.enabled on conflict do nothing;
 return new;
end;$$;
create or replace function cheongla_private.wake_push_dispatcher()
returns void language plpgsql security definer set search_path='' as $$
declare s cheongla_private.push_settings%rowtype;
begin
 -- A worker that disappeared on its last attempt must not remain processing forever.
 update cheongla_private.push_deliveries set state='failed'
 where state='processing' and attempts>=6 and last_attempt_at<clock_timestamp()-interval '3 minutes';
 select * into s from cheongla_private.push_settings where singleton;
 if not coalesce(s.enabled,false) or not exists(select 1 from cheongla_private.push_deliveries where attempts<6 and ((state in ('pending','failed') and next_attempt_at<=clock_timestamp()) or (state='processing' and last_attempt_at<clock_timestamp()-interval '3 minutes'))) then return;end if;
 perform net.http_post(url:=s.dispatcher_url,body:='{"action":"dispatch"}'::jsonb,headers:=jsonb_build_object('Content-Type','application/json','x-cheongla-webhook',s.webhook_secret),timeout_milliseconds:=10000);
exception when others then
 -- Persisted inbox/outbox survive a temporary dispatcher/network failure; cron retries.
 raise warning '청라 푸시 호출 실패: 발송 대기열을 유지하며 정기 재시도합니다.';
end;$$;
create or replace function cheongla_private.wake_push_after_insert()
returns trigger language plpgsql security definer set search_path='' as $$
begin perform cheongla_private.wake_push_dispatcher();return null;end;$$;
revoke all on function cheongla_private.wake_push_after_insert() from public,anon,authenticated;
drop trigger if exists cheongla_push_batch_wake on public.cheongla_notifications;
create trigger cheongla_push_batch_wake after insert on public.cheongla_notifications for each statement execute function cheongla_private.wake_push_after_insert();
-- Explicitly reject inactive recipients even for direct/test notification inserts.
create or replace function cheongla_private.push_source_allowed(reader uuid,kind text,target uuid,student uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare old_sub text=current_setting('request.jwt.claim.sub',true);old_claims text=current_setting('request.jwt.claims',true);allowed boolean;
begin
 if not exists(select 1 from public.cheongla_profiles where id=reader and approval_status='approved' and membership_state='active') then return false;end if;
 if kind='push_test' then return true;end if;
 perform set_config('request.jwt.claim.sub',reader::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reader)::text,true);
 begin allowed=cheongla_private.can_read_notification(kind,target,student);
 exception when others then
  perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);
  perform set_config('request.jwt.claims',coalesce(old_claims,''),true);raise;
 end;
 perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);
 perform set_config('request.jwt.claims',coalesce(old_claims,''),true);
 return allowed;
end;$$;
create or replace function public.cheongla_notification_delivery_status()
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if not cheongla_private.can_manage_tuition() then raise exception '직원만 확인할 수 있습니다.' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into result from (
  select n.event_key,min(n.title) as title,min(n.created_at) as created_at,
   count(*) as inbox_count,count(*) filter(where n.read_at is not null) as read_count,
   count(*) filter(where not exists(select 1 from public.cheongla_push_subscriptions s where s.user_id=n.recipient_id and s.enabled)) as no_device_count,
   (select count(*) from cheongla_private.push_deliveries d join public.cheongla_notifications a on a.id=d.notification_id where a.event_key=n.event_key and d.state='sent') as accepted_count,
   (select count(*) from cheongla_private.push_deliveries d join public.cheongla_notifications a on a.id=d.notification_id where a.event_key=n.event_key and d.state in ('pending','processing','failed') and d.attempts<6) as waiting_count,
   (select count(*) from cheongla_private.push_deliveries d join public.cheongla_notifications a on a.id=d.notification_id where a.event_key=n.event_key and d.state='failed' and d.attempts>=6) as failed_count,
   (select count(*) from cheongla_private.push_deliveries d join public.cheongla_notifications a on a.id=d.notification_id where a.event_key=n.event_key and d.state='cancelled') as cancelled_count
  from public.cheongla_notifications n
  where n.created_at>clock_timestamp()-interval '7 days'
   and cheongla_private.push_source_allowed(auth.uid(),n.source_kind,n.source_id,n.student_id)
  group by n.event_key order by min(n.created_at) desc limit 30
 ) x;
 return jsonb_build_object('enabled',coalesce((select enabled from cheongla_private.push_settings where singleton),false),
  'retry_active',exists(select 1 from cron.job where jobname='cheongla-web-push-retry' and active),'events',result);
end;$$;
create or replace function public.cheongla_retry_notification_delivery(target_event text)
returns integer language plpgsql security definer set search_path='' as $$
declare result integer;
begin
 if not cheongla_private.can_manage_tuition() then raise exception '직원만 재시도할 수 있습니다.' using errcode='42501';end if;
 if not exists(select 1 from public.cheongla_notifications n where n.event_key=target_event and n.created_at>clock_timestamp()-interval '7 days' and cheongla_private.push_source_allowed(auth.uid(),n.source_kind,n.source_id,n.student_id)) then raise exception '재시도할 알림을 확인해 주세요.';end if;
 update cheongla_private.push_deliveries d set state='pending',attempts=0,next_attempt_at=clock_timestamp(),finished_at=null
 from public.cheongla_notifications n where d.notification_id=n.id and n.event_key=target_event
 and d.state='failed' and d.attempts>=6 and exists(select 1 from public.cheongla_push_subscriptions s where s.id=d.subscription_id and s.enabled)
 and cheongla_private.push_source_allowed(n.recipient_id,n.source_kind,n.source_id,n.student_id);
 get diagnostics result=row_count;
 perform cheongla_private.wake_push_dispatcher();return result;
end;$$;
revoke all on function public.cheongla_notification_delivery_status(),public.cheongla_retry_notification_delivery(text) from public,anon,authenticated;
grant execute on function public.cheongla_notification_delivery_status(),public.cheongla_retry_notification_delivery(text) to authenticated;
create index if not exists cheongla_push_retry_six on cheongla_private.push_deliveries(state,next_attempt_at,created_at) where attempts<6 and state in ('pending','failed','processing');
create or replace function cheongla_private.notify_new_inquiry()
returns trigger language plpgsql security definer set search_path='' as $$
declare people uuid[];
begin
 select array_agg(id) into people from public.cheongla_profiles where role in ('owner','english_director','math_director','manager');
 perform cheongla_private.send_notification(people,'new_inquiry',new.id,null,'새 신규 상담 문의가 접수되었습니다.','new_inquiry','new_inquiry:'||new.id::text);
 return new;
end;$$;
-- Keep the existing one-minute cron job and its installed credentials unchanged.
notify pgrst,'reload schema';
commit;
