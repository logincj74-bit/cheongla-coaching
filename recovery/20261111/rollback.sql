begin;
CREATE OR REPLACE FUNCTION public.cheongla_learning_list(record_kind text, from_on date, to_on date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare people jsonb;items jsonb;
begin
 if not cheongla_private.can_use_member_services() or record_kind not in('study','external','registration')or record_kind is null or from_on is null or to_on is null or to_on<from_on or to_on-from_on>366 then raise exception '조회 기간과 승인 상태를 확인해 주세요.'using errcode='42501';end if;
 if record_kind='registration' and not cheongla_private.can_manage_life() then raise exception '원장·실장만 등록카드를 조회할 수 있습니다.'using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name)order by p.full_name,p.id),'[]')into people from public.cheongla_profiles p where p.role='student'and p.approval_status='approved'and p.membership_state='active'and cheongla_private.can_read_learning(record_kind,p.id);
 select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('student_name',coalesce(p.full_name,r.payload->>'name'),'reviewer_name',(select full_name from public.cheongla_profiles where id=r.reviewed_by),'parent_checks',(select coalesce(jsonb_agg(jsonb_build_object('parent_id',c.parent_id,'parent_name',q.full_name,'checked_at',c.checked_at)),'[]')from cheongla_private.learning_parent_checks c join public.cheongla_profiles q on q.id=c.parent_id where c.record_id=r.id and c.record_version=r.updated_at and exists(select 1 from public.cheongla_parent_students l where l.parent_id=c.parent_id and l.student_id=r.student_id)))order by r.record_on desc,p.full_name,r.id),'[]')into items from cheongla_private.learning_records r left join public.cheongla_profiles p on p.id=r.student_id where r.kind=record_kind and ((r.kind<>'external'and r.record_on between from_on and to_on)or(r.kind='external'and r.record_on<=to_on and(r.payload->>'until')::date>=from_on)) and cheongla_private.can_read_learning(r.kind,r.student_id) and(r.archived_at is null or cheongla_private.is_principal()or(record_kind in('study','external','registration')and cheongla_private.can_manage_life()));
 return jsonb_build_object('students',people,'items',items);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_save_learning(record_kind text, target_record uuid, target_student uuid, day_on date, content jsonb, submit_record boolean, expected_updated_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.learning_records%rowtype;me public.cheongla_profiles%rowtype;people uuid[];destination text;
begin
 select * into me from public.cheongla_profiles where id=auth.uid()and approval_status='approved'and membership_state='active';
 if not found or record_kind is null or record_kind not in('study','external','registration')or day_on is null or submit_record is null then raise exception '승인 상태와 양식을 확인해 주세요.'using errcode='42501';end if;
 if record_kind='registration' then
  if not cheongla_private.can_manage_life()then raise exception '원장·실장만 등록카드를 작성할 수 있습니다.'using errcode='42501';end if;
 elsif not(record_kind in('study','external')and cheongla_private.can_manage_life())and(me.role<>'student'or target_student is distinct from me.id)then raise exception '학생 본인만 작성할 수 있습니다.'using errcode='42501';end if;
 if target_student is not null and not exists(select 1 from public.cheongla_profiles where id=target_student and role='student'and approval_status='approved'and membership_state='active')then raise exception '재원생 선택을 확인해 주세요.';end if;
 perform cheongla_private.validate_learning(record_kind,content);
 if record_kind='external'and ((content->>'until')::date<day_on or (content->>'until')::date-day_on>366)then raise exception '적용 기간은 시작일부터 1년 이내로 입력해 주세요.';end if;
 if record_kind='study'and submit_record and not exists(select 1 from jsonb_array_elements(content->'subjects')s,jsonb_array_elements(s->'tasks')t where length(trim(t->>'text'))>0)then raise exception '학습계획을 하나 이상 입력해 주세요.';end if;
 if target_record is null then
  if expected_updated_at is not null then raise exception '새 양식의 버전을 확인해 주세요.';end if;
  insert into cheongla_private.learning_records(kind,student_id,record_on,payload,state,created_by)values(record_kind,target_student,day_on,content,case when submit_record then 'submitted'else 'draft'end,me.id)returning *into r;
 else
  select *into r from cheongla_private.learning_records where id=target_record for update;
  if not found or r.kind<>record_kind or r.student_id is distinct from target_student or r.archived_at is not null or not cheongla_private.can_read_learning(r.kind,r.student_id)then raise exception '현재 양식을 수정할 수 없습니다.'using errcode='42501';end if;
  if r.updated_at is distinct from expected_updated_at then raise exception '다른 화면에서 변경되었습니다. 새로고침 후 다시 작성해 주세요.';end if;
  update cheongla_private.learning_records set record_on=day_on,payload=content,state=case when submit_record then 'submitted'when record_kind='study'then r.state else 'draft'end,updated_at=clock_timestamp(),reviewed_at=null,reviewed_by=null,review_note=''where id=r.id returning *into r;
 end if;
 if submit_record and record_kind<>'registration'then
  select array_agg(p.id)into people from public.cheongla_profiles p where p.id<>me.id and(p.role in('owner','english_director','math_director','manager')or(p.role='parent'and exists(select 1 from public.cheongla_parent_students l where l.parent_id=p.id and l.student_id=target_student)));
  destination:=case record_kind when 'study'then 'account_learningPanel'else 'account_externalPanel'end;
  perform cheongla_private.send_notification(people,case record_kind when 'study'then 'study_plan'else 'external_schedule'end,r.id,target_student,me.full_name||' · '||day_on||' · '||case record_kind when 'study'then '학습계획표 제출'else '외부 수업·출결 예외 일정 제출'end,destination,'learning:'||r.id||':'||r.updated_at);
 end if;
 return to_jsonb(r);
exception when unique_violation then raise exception '이 날짜의 학습계획표가 이미 있습니다. 새로고침 후 기존 계획표를 수정해 주세요.';
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_archive_learning(target_record uuid, record_action text, expected_updated_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.learning_records%rowtype;
begin
 select *into r from cheongla_private.learning_records where id=target_record for update;
 if not found or not cheongla_private.can_read_learning(r.kind,r.student_id)or(not (cheongla_private.is_principal()or(r.kind in('study','external','registration')and cheongla_private.can_manage_life()))and(r.created_by<>auth.uid()or record_action<>'archive'or r.state<>'draft'))then raise exception '삭제·복구 권한을 확인해 주세요.'using errcode='42501';end if;
 if r.updated_at is distinct from expected_updated_at then raise exception '양식이 변경되었습니다. 새로고침해 주세요.';end if;
 if record_action='archive'and r.archived_at is null then update cheongla_private.learning_records set archived_at=clock_timestamp(),updated_at=clock_timestamp()where id=r.id;
 elsif record_action='restore'and r.archived_at is not null then update cheongla_private.learning_records set archived_at=null,updated_at=clock_timestamp()where id=r.id;
 elsif record_action='purge'and r.archived_at is not null and (cheongla_private.is_principal()or(r.kind in('study','external','registration')and cheongla_private.can_manage_life()))then delete from cheongla_private.learning_records where id=r.id;
 else raise exception '휴지통 상태를 확인해 주세요.';end if;
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_learning_context(target_record uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.learning_records%rowtype;
begin
 select *into r from cheongla_private.learning_records where id=target_record;
 if not found or r.archived_at is not null or not cheongla_private.can_read_learning(r.kind,r.student_id)then raise exception '양식이 삭제되었거나 볼 수 없습니다.'using errcode='42501';end if;
 return jsonb_build_object('kind',r.kind,'date',r.record_on,'student_id',r.student_id,'id',r.id);
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.enqueue_push_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 insert into cheongla_private.push_deliveries(notification_id,subscription_id)
 select new.id,s.id from public.cheongla_push_subscriptions s
 where s.user_id=new.recipient_id and s.enabled on conflict do nothing;
 return new;
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_claim_push_deliveries()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item record;batch jsonb='[]'::jsonb;
begin
 for item in
  select d.id as delivery_id,d.attempts,n.id as notification_id,n.recipient_id,n.source_kind,n.source_id,n.student_id,n.title,n.archived_at,n.inbox_until,s.id as subscription_id,s.endpoint,s.p256dh,s.auth_key,s.enabled
  from cheongla_private.push_deliveries d join public.cheongla_notifications n on n.id=d.notification_id join public.cheongla_push_subscriptions s on s.id=d.subscription_id
  where d.attempts<6 and ((d.state in ('pending','failed') and d.next_attempt_at<=clock_timestamp()) or (d.state='processing' and d.last_attempt_at<clock_timestamp()-interval '3 minutes'))
  order by d.created_at,d.id limit 40 for update of d skip locked
 loop
  if item.archived_at is not null or item.inbox_until<=clock_timestamp()or not item.enabled or not exists(select 1 from public.cheongla_push_subscriptions where id=item.subscription_id and user_id=item.recipient_id)
  or not cheongla_private.push_source_allowed(item.recipient_id,item.source_kind,item.source_id,item.student_id) then
   update cheongla_private.push_deliveries set state='cancelled',finished_at=clock_timestamp() where id=item.delivery_id;continue;
  end if;
  update cheongla_private.push_deliveries set state='processing',attempts=attempts+1,last_attempt_at=clock_timestamp() where id=item.delivery_id;
  batch=batch||jsonb_build_array(to_jsonb(item));
 end loop;
 return batch;
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_use_mbti_study()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(
    select 1
    from public.cheongla_profiles
    where id=(select auth.uid())
    and approval_status='approved'
  );
$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_read_notification(kind text, target uuid, student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select case
 when kind='staff_journal'then cheongla_private.can_use_staff_journal()and exists(select 1 from cheongla_private.journal_notification_events where id=target)
 when kind='director_post'then exists(select 1 from public.cheongla_director_posts where id=target and state='published'and archived_at is null)
 when kind='account_recovery'then cheongla_private.can_manage_account_recovery()and exists(select 1 from cheongla_private.account_help_requests where id=target)
 when kind='winter_booking'then exists(select 1 from cheongla_private.winter_bookings r where r.id=target and r.archived_at is null and(cheongla_private.can_manage_winter()or(cheongla_private.can_use_member_services()and r.owner_id=auth.uid())))
 else cheongla_private.can_read_notification_before_winter(kind,target,student)end;
$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_manage_mbti_operations()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved' and membership_state = 'active'
      and role in ('owner','english_director','math_director','manager'));
$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.guard_study_day()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare current_day date:=(clock_timestamp()at time zone'Asia/Seoul')::date;is_director boolean:=cheongla_private.can_manage_life();
begin
 if TG_OP='DELETE'then
  if OLD.kind='study'then
   if not is_director then raise exception '학습계획표 삭제는 원장·실장만 가능합니다.'using errcode='42501';end if;
   insert into cheongla_private.study_corrections(record_id,student_id,changed_by,action,before_record)values(OLD.id,OLD.student_id,auth.uid(),'purge',to_jsonb(OLD));
  end if;return OLD;
 end if;
 if NEW.kind<>'study'and(TG_OP='INSERT'or OLD.kind<>'study')then return NEW;end if;
 if not cheongla_private.can_use_member_services()then raise exception '승인 상태를 확인해 주세요.'using errcode='42501';end if;
 if TG_OP='INSERT'then
  if not is_director and(NEW.student_id is distinct from auth.uid()or NEW.record_on<>current_day)then raise exception '학생은 오늘의 학습계획표만 작성할 수 있습니다.'using errcode='42501';end if;
 else
  if not is_director and(NEW.kind is distinct from OLD.kind or NEW.student_id is distinct from OLD.student_id or NEW.record_on is distinct from OLD.record_on or NEW.archived_at is distinct from OLD.archived_at)then raise exception '학습계획표 날짜 변경·삭제·복구는 원장·실장만 가능합니다.'using errcode='42501';end if;
  if not is_director and(NEW.payload is distinct from OLD.payload or NEW.state is distinct from OLD.state)and(NEW.student_id is distinct from auth.uid()or OLD.record_on<>current_day or NEW.record_on<>current_day)then raise exception '지난 학습계획표의 수정은 원장·실장만 가능합니다.'using errcode='42501';end if;
  -- Reject no-op save RPCs after midnight too; staff review only changes review metadata.
  if not is_director and NEW.updated_at is distinct from OLD.updated_at and OLD.record_on<>current_day then raise exception '지난 학습계획표의 수정은 원장·실장만 가능합니다.'using errcode='42501';end if;
  if is_director and(NEW.payload is distinct from OLD.payload or NEW.record_on is distinct from OLD.record_on or NEW.archived_at is distinct from OLD.archived_at)then
   insert into cheongla_private.study_corrections(record_id,student_id,changed_by,action,before_record,after_record)values(OLD.id,OLD.student_id,auth.uid(),'correct',to_jsonb(OLD),to_jsonb(NEW));
  end if;
 end if;return NEW;
end;$function$
;
drop policy if exists principal_only_role_release on public.cheongla_mbti_preferences;
drop policy if exists principal_only_role_release on public.cheongla_mbti_guides;
drop policy if exists principal_only_role_release on public.cheongla_mbti_introductions;
drop policy if exists principal_only_role_release on public.cheongla_mbti_learning_articles;
drop policy if exists principal_only_role_release on public.cheongla_mbti_operation_references;
drop policy if exists principal_only_role_release on public.cheongla_mbti_prescriptions;
select cron.unschedule(jobid)from cron.job where jobname='cheongla-confirmed-study-retention';
notify pgrst,'reload schema';
commit;
