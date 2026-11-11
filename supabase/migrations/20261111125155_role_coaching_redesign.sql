-- Additive role/coaching release. Apply only after approval, in one transaction.
begin;
alter table cheongla_private.learning_records add column retention_exempt boolean not null default true;
create table cheongla_private.journal_push_preferences (
 user_id uuid primary key references public.cheongla_profiles(id) on delete cascade,
 paused boolean not null default false, paused_until timestamptz
);
alter table cheongla_private.journal_push_preferences enable row level security;
revoke all on cheongla_private.journal_push_preferences from public,anon,authenticated;
create or replace function public.cheongla_journal_push_preference()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_life() then raise insufficient_privilege; end if;
 return coalesce((select to_jsonb(p)-'user_id' from cheongla_private.journal_push_preferences p where user_id=auth.uid()),'{"paused":false,"paused_until":null}'::jsonb);
end;$$;
create or replace function public.cheongla_set_journal_push_preference(setting text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare until_at timestamptz;
begin
 if not cheongla_private.can_manage_life() or setting is null or setting not in('on','2h','tomorrow','paused') then raise insufficient_privilege;end if;
 until_at:=case setting when '2h' then clock_timestamp()+interval '2 hours' when 'tomorrow' then (((clock_timestamp()at time zone'Asia/Seoul')::date+1)+time'08:00')at time zone'Asia/Seoul' else null end;
 insert into cheongla_private.journal_push_preferences(user_id,paused,paused_until)values(auth.uid(),setting='paused',until_at) on conflict(user_id)do update set paused=excluded.paused,paused_until=excluded.paused_until;
 -- Pending journal pushes are cancelled so resuming does not replay off-duty alerts.
 if setting<>'on' then update cheongla_private.push_deliveries d set state='cancelled',finished_at=clock_timestamp()from public.cheongla_notifications n where n.id=d.notification_id and n.source_kind='staff_journal'and n.recipient_id=auth.uid()and d.state in('pending','failed');end if;
 return public.cheongla_journal_push_preference();
end;$$;
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
  if (item.source_kind='staff_journal'and exists(select 1 from cheongla_private.journal_push_preferences p where p.user_id=item.recipient_id and(p.paused or p.paused_until>clock_timestamp()))) or item.archived_at is not null or item.inbox_until<=clock_timestamp()or not item.enabled or not exists(select 1 from public.cheongla_push_subscriptions where id=item.subscription_id and user_id=item.recipient_id)
  or not cheongla_private.push_source_allowed(item.recipient_id,item.source_kind,item.source_id,item.student_id) then
   update cheongla_private.push_deliveries set state='cancelled',finished_at=clock_timestamp() where id=item.delivery_id;continue;
  end if;
  update cheongla_private.push_deliveries set state='processing',attempts=attempts+1,last_attempt_at=clock_timestamp() where id=item.delivery_id;
  batch=batch||jsonb_build_array(to_jsonb(item));
 end loop;
 return batch;
end;$function$;
CREATE OR REPLACE FUNCTION cheongla_private.enqueue_push_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 insert into cheongla_private.push_deliveries(notification_id,subscription_id)
 select new.id,s.id from public.cheongla_push_subscriptions s
 where s.user_id=new.recipient_id and s.enabled and not(new.source_kind='staff_journal'and exists(select 1 from cheongla_private.journal_push_preferences p where p.user_id=new.recipient_id and(p.paused or p.paused_until>clock_timestamp()))) on conflict do nothing;
 return new;
end;$function$;
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
  insert into cheongla_private.learning_records(kind,student_id,record_on,payload,state,created_by,retention_exempt)values(record_kind,target_student,day_on,content,case when submit_record then 'submitted'else 'draft'end,me.id,false)returning *into r;
 else
  select *into r from cheongla_private.learning_records where id=target_record for update;
  if not found or r.kind<>record_kind or r.student_id is distinct from target_student or r.archived_at is not null or not cheongla_private.can_read_learning(r.kind,r.student_id)then raise exception '현재 양식을 수정할 수 없습니다.'using errcode='42501';end if;
  if r.updated_at is distinct from expected_updated_at then raise exception '다른 화면에서 변경되었습니다. 새로고침 후 다시 작성해 주세요.';end if;
  update cheongla_private.learning_records set retention_exempt=case when submit_record and record_kind='study'then false else r.retention_exempt end,record_on=day_on,payload=content,state=case when submit_record then 'submitted'when record_kind='study'then r.state else 'draft'end,updated_at=clock_timestamp(),reviewed_at=null,reviewed_by=null,review_note=''where id=r.id returning *into r;
 end if;
 if submit_record and record_kind<>'registration'then
  select array_agg(p.id)into people from public.cheongla_profiles p where p.id<>me.id and(p.role in('owner','english_director','math_director','manager')or(p.role='parent'and exists(select 1 from public.cheongla_parent_students l where l.parent_id=p.id and l.student_id=target_student)));
  destination:=case record_kind when 'study'then 'account_learningPanel'else 'account_externalPanel'end;
  perform cheongla_private.send_notification(people,case record_kind when 'study'then 'study_plan'else 'external_schedule'end,r.id,target_student,me.full_name||' · '||day_on||' · '||case record_kind when 'study'then '학습계획표 제출'else '외부 수업·출결 예외 일정 제출'end,destination,'learning:'||r.id||':'||r.updated_at);
 end if;
 return to_jsonb(r);
exception when unique_violation then raise exception '이 날짜의 학습계획표가 이미 있습니다. 새로고침 후 기존 계획표를 수정해 주세요.';
end;$function$;
CREATE OR REPLACE FUNCTION public.cheongla_archive_learning(target_record uuid, record_action text, expected_updated_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.learning_records%rowtype;
begin
 if record_action='purge'and not cheongla_private.is_principal()then raise insufficient_privilege;end if;
 select *into r from cheongla_private.learning_records where id=target_record for update;
 if not found or not cheongla_private.can_read_learning(r.kind,r.student_id)or(not (cheongla_private.is_principal()or(r.kind in('study','external','registration')and cheongla_private.can_manage_life()))and(r.created_by<>auth.uid()or record_action<>'archive'or r.state<>'draft'))then raise exception '삭제·복구 권한을 확인해 주세요.'using errcode='42501';end if;
 if r.kind='study'and not cheongla_private.is_principal()then raise insufficient_privilege;end if;
 if r.updated_at is distinct from expected_updated_at then raise exception '양식이 변경되었습니다. 새로고침해 주세요.';end if;
 if record_action='archive'and r.archived_at is null then update cheongla_private.learning_records set archived_at=clock_timestamp(),updated_at=clock_timestamp()where id=r.id;
 elsif record_action='restore'and r.archived_at is not null then update cheongla_private.learning_records set retention_exempt=true,archived_at=null,updated_at=clock_timestamp()where id=r.id;
 elsif record_action='purge'and r.archived_at is not null and (cheongla_private.is_principal()or(r.kind in('study','external','registration')and cheongla_private.can_manage_life()))then delete from cheongla_private.learning_records where id=r.id;
 else raise exception '휴지통 상태를 확인해 주세요.';end if;
end;$function$;
CREATE OR REPLACE FUNCTION cheongla_private.guard_study_day()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare current_day date:=(clock_timestamp()at time zone'Asia/Seoul')::date;is_director boolean:=cheongla_private.can_manage_life();
begin
 -- Only archival metadata may change in this narrowly validated retention path.
 if TG_OP='UPDATE'and NEW.kind='study'and OLD.archived_at is null and NEW.archived_at is not null
 and not OLD.retention_exempt and OLD.state='submitted'and OLD.record_on+7<=current_day
 and(to_jsonb(NEW)-'archived_at')=(to_jsonb(OLD)-'archived_at')
 and exists(select 1 from cheongla_private.learning_parent_checks c join public.cheongla_parent_students l on l.parent_id=c.parent_id and l.student_id=OLD.student_id where c.record_id=OLD.id and c.record_version=OLD.updated_at)then return NEW;end if;
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
end;$function$;

create or replace function public.cheongla_acknowledge_study(target_record uuid,expected_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare r cheongla_private.learning_records%rowtype;
begin
 select *into r from cheongla_private.learning_records where id=target_record for update;
 if not found or r.kind<>'study'or r.state<>'submitted'or r.archived_at is not null
 or not cheongla_private.can_use_member_services()or not exists(select 1 from public.cheongla_profiles p join public.cheongla_parent_students l on l.parent_id=p.id where p.id=auth.uid()and p.role='parent'and l.student_id=r.student_id)then raise insufficient_privilege;end if;
 if r.updated_at is distinct from expected_updated_at then raise exception '내용이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 insert into cheongla_private.learning_parent_checks(record_id,parent_id,record_version,checked_at)values(r.id,auth.uid(),r.updated_at,clock_timestamp())on conflict(record_id,parent_id)do update set record_version=excluded.record_version,checked_at=excluded.checked_at;
end;$$;
create or replace function cheongla_private.archive_confirmed_study()
returns void language sql security definer set search_path='' as $$
 update cheongla_private.learning_records r set archived_at=clock_timestamp()
 where r.kind='study'and r.archived_at is null and not r.retention_exempt and r.state='submitted'
 and r.record_on+7<=(clock_timestamp()at time zone'Asia/Seoul')::date
 and exists(select 1 from cheongla_private.learning_parent_checks c join public.cheongla_parent_students l on l.parent_id=c.parent_id and l.student_id=r.student_id join public.cheongla_profiles p on p.id=c.parent_id where c.record_id=r.id and c.record_version=r.updated_at and p.role='parent'and p.approval_status='approved'and p.membership_state='active');
$$;

create or replace function cheongla_private.can_use_mbti_study() returns boolean language sql stable security definer set search_path='' as $$select cheongla_private.is_principal();$$;
create or replace function cheongla_private.can_manage_mbti_operations() returns boolean language sql stable security definer set search_path='' as $$select cheongla_private.is_principal();$$;
create policy principal_only_role_release on public.cheongla_mbti_preferences as restrictive for select to authenticated using((select cheongla_private.is_principal()));
create policy principal_only_role_release on public.cheongla_mbti_guides as restrictive for select to authenticated using((select cheongla_private.is_principal()));
create policy principal_only_role_release on public.cheongla_mbti_introductions as restrictive for select to authenticated using((select cheongla_private.is_principal()));
create policy principal_only_role_release on public.cheongla_mbti_learning_articles as restrictive for select to authenticated using((select cheongla_private.is_principal()));
create policy principal_only_role_release on public.cheongla_mbti_operation_references as restrictive for select to authenticated using((select cheongla_private.is_principal()));
create policy principal_only_role_release on public.cheongla_mbti_prescriptions as restrictive for select to authenticated using((select cheongla_private.is_principal()));

create table cheongla_private.score_coaching (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.cheongla_profiles(id) on delete cascade,
 exam_on date not null, title text not null check(length(btrim(title))between 1 and 150),
 scores jsonb not null, report text not null default '' check(length(report)<=20000),
 revision integer not null default 1, published_revision integer,
 published_snapshot jsonb, archived_at timestamptz, updated_at timestamptz not null default clock_timestamp(),
 created_by uuid not null references public.cheongla_profiles(id)
);
create index score_coaching_student_date on cheongla_private.score_coaching(student_id,exam_on desc,id);
alter table cheongla_private.score_coaching enable row level security;
revoke all on cheongla_private.score_coaching from public,anon,authenticated;

create function cheongla_private.can_read_score_coaching(target uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.can_use_member_services()and exists(select 1 from cheongla_private.score_coaching r
 where r.id=target and r.archived_at is null and(cheongla_private.is_principal()or(r.published_snapshot is not null and
 (r.student_id=auth.uid()or exists(select 1 from public.cheongla_parent_students l join public.cheongla_profiles p on p.id=l.parent_id where p.id=auth.uid()and p.role='parent'and l.student_id=r.student_id)))));
$$;
create function public.cheongla_score_coaching_list()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare people jsonb;items jsonb;
begin
 if not cheongla_private.can_use_member_services()then raise insufficient_privilege;end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name)order by p.full_name,p.id),'[]')into people
 from public.cheongla_profiles p where p.role='student'and p.approval_status='approved'and p.membership_state='active'
 and(cheongla_private.is_principal()or p.id=auth.uid()or exists(select 1 from public.cheongla_parent_students l join public.cheongla_profiles guardian on guardian.id=l.parent_id where l.student_id=p.id and guardian.id=auth.uid()and guardian.role='parent'));
 select coalesce(jsonb_agg(case when cheongla_private.is_principal()then to_jsonb(r)else r.published_snapshot end order by r.exam_on desc,r.id),'[]')into items
 from cheongla_private.score_coaching r where cheongla_private.is_principal()or cheongla_private.can_read_score_coaching(r.id);
 return jsonb_build_object('students',people,'items',items);
end;$$;
create function public.cheongla_save_score_coaching(target_report uuid,target_student uuid,exam_date date,exam_title text,subject_scores jsonb,coaching_text text,expected_revision integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r cheongla_private.score_coaching%rowtype;s jsonb;k text;value numeric;
begin
 if not cheongla_private.is_principal()then raise insufficient_privilege;end if;
 if not exists(select 1 from public.cheongla_profiles where id=target_student and role='student'and approval_status='approved'and membership_state='active')then raise exception '승인된 학생을 선택해 주세요.';end if;
 if exam_date is null or exam_date<date'2000-01-01'or exam_date>(clock_timestamp()at time zone'Asia/Seoul')::date or exam_title is null or length(btrim(exam_title))not between 1 and 150 or coaching_text is null or length(coaching_text)>20000 then raise exception '시험일·시험명·코칭 내용을 확인해 주세요.';end if;
 if subject_scores is null or jsonb_typeof(subject_scores)<>'array'or jsonb_array_length(subject_scores)not between 1 and 10 then raise exception '과목별 점수를 확인해 주세요.';end if;
 for s in select *from jsonb_array_elements(subject_scores)loop
  if jsonb_typeof(s)<>'object'or length(btrim(coalesce(s->>'subject','')))not between 1 and 60 or not(s ?| array['raw','standard','percentile','grade'])then raise exception '과목명을 확인해 주세요.';end if;
  if not exists(select 1 from jsonb_each(s)e where e.key in('raw','standard','percentile','grade')and jsonb_typeof(e.value)='number')then raise exception '과목별 점수를 하나 이상 입력해 주세요.';end if;
  foreach k in array array['raw','standard','percentile','grade']loop
   if s->k is not null and s->k<>'null'::jsonb then
    if jsonb_typeof(s->k)<>'number'then raise exception '숫자 점수를 입력해 주세요.';end if;value:=(s->>k)::numeric;
    if value<(case when k='grade'then 1 else 0 end) or value>(case when k='grade'then 9 when k='standard'then 200 else 100 end) or(k<>'percentile'and value<>trunc(value))then raise exception '점수 범위를 확인해 주세요.';end if;
   end if;
  end loop;
 end loop;
 if(select count(distinct btrim(x->>'subject'))from jsonb_array_elements(subject_scores)x)<>jsonb_array_length(subject_scores)then raise exception '과목명이 중복되었습니다.';end if;
 if target_report is null then
  if expected_revision is not null then raise exception '새 성적표를 다시 열어 주세요.';end if;
  insert into cheongla_private.score_coaching(student_id,exam_on,title,scores,report,created_by)values(target_student,exam_date,btrim(exam_title),subject_scores,coaching_text,auth.uid())returning *into r;
 else
  select *into r from cheongla_private.score_coaching where id=target_report for update;
  if not found or r.student_id<>target_student or r.archived_at is not null or r.revision is distinct from expected_revision then raise exception '성적표가 변경되었습니다. 새로고침해 주세요.';end if;
  update cheongla_private.score_coaching set exam_on=exam_date,title=btrim(exam_title),scores=subject_scores,report=coaching_text,revision=revision+1,updated_at=clock_timestamp()where id=r.id returning *into r;
 end if;
 return to_jsonb(r);
end;$$;
create function public.cheongla_score_coaching_action(target_report uuid,action text,expected_revision integer)
returns void language plpgsql security definer set search_path='' as $$
declare r cheongla_private.score_coaching%rowtype;people uuid[];snapshot jsonb;
begin
 if not cheongla_private.is_principal()then raise insufficient_privilege;end if;
 select *into r from cheongla_private.score_coaching where id=target_report for update;
 if not found or r.revision is distinct from expected_revision then raise exception '문서가 변경되었습니다. 새로고침해 주세요.';end if;
 if action='purge'and r.archived_at is not null then delete from cheongla_private.score_coaching where id=r.id;return;
 elsif action='archive'and r.archived_at is null then update cheongla_private.score_coaching set archived_at=clock_timestamp(),revision=revision+1 where id=r.id;
 elsif action='restore'and r.archived_at is not null then update cheongla_private.score_coaching set archived_at=null,published_snapshot=null,published_revision=null,revision=revision+1 where id=r.id;
 elsif action='unpublish'and r.archived_at is null then update cheongla_private.score_coaching set published_snapshot=null,published_revision=null,revision=revision+1 where id=r.id;
 elsif action='publish'and r.archived_at is null and length(btrim(r.report))>0 then
  if r.published_revision=r.revision then return;end if;
  snapshot:=jsonb_build_object('id',r.id,'student_id',r.student_id,'exam_on',r.exam_on,'title',r.title,'scores',r.scores,'report',r.report);
  update cheongla_private.score_coaching set published_snapshot=snapshot,published_revision=revision where id=r.id;
  select array_agg(p.id)into people from public.cheongla_profiles p where p.id=r.student_id or(p.role='parent'and exists(select 1 from public.cheongla_parent_students l where l.parent_id=p.id and l.student_id=r.student_id));
  perform cheongla_private.send_notification(people,'score_coaching',r.id,r.student_id,'새 학습코칭이 도착했습니다.','account_scoreCoachingPanel','score:'||r.id||':'||r.revision);
 else raise exception '문서 상태와 코칭 내용을 확인해 주세요.';end if;
end;$$;

CREATE OR REPLACE FUNCTION cheongla_private.can_read_notification(kind text, target uuid, student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select case
 when kind='score_coaching'then cheongla_private.can_read_score_coaching(target)
 when kind='staff_journal'then cheongla_private.can_use_staff_journal()and exists(select 1 from cheongla_private.journal_notification_events where id=target)
 when kind='director_post'then exists(select 1 from public.cheongla_director_posts where id=target and state='published'and archived_at is null)
 when kind='account_recovery'then cheongla_private.can_manage_account_recovery()and exists(select 1 from cheongla_private.account_help_requests where id=target)
 when kind='winter_booking'then exists(select 1 from cheongla_private.winter_bookings r where r.id=target and r.archived_at is null and(cheongla_private.can_manage_winter()or(cheongla_private.can_use_member_services()and r.owner_id=auth.uid())))
 else cheongla_private.can_read_notification_before_winter(kind,target,student)end;
$function$
;
create table cheongla_private.score_extraction_requests(user_id uuid primary key references public.cheongla_profiles(id)on delete cascade,window_at timestamptz not null,attempts integer not null);
alter table cheongla_private.score_extraction_requests enable row level security;
revoke all on cheongla_private.score_extraction_requests from public,anon,authenticated;
create function public.cheongla_claim_score_extraction()returns void language plpgsql security definer set search_path='' as $$
declare r cheongla_private.score_extraction_requests%rowtype;
begin
 if not cheongla_private.is_principal()then raise insufficient_privilege;end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1111));
 select *into r from cheongla_private.score_extraction_requests where user_id=auth.uid();
 if found and r.window_at>clock_timestamp()-interval '1 minute'and r.attempts>=5 then raise exception '1분 후 다시 시도해 주세요.';end if;
 insert into cheongla_private.score_extraction_requests values(auth.uid(),clock_timestamp(),1)on conflict(user_id)do update set window_at=case when r.window_at>clock_timestamp()-interval '1 minute'then r.window_at else excluded.window_at end,attempts=case when r.window_at>clock_timestamp()-interval '1 minute'then r.attempts+1 else 1 end;
end;$$;
revoke all on function public.cheongla_claim_score_extraction()from public,anon;
grant execute on function public.cheongla_claim_score_extraction()to authenticated;
-- Restrict every new RPC, including read RPCs, to authenticated callers.
revoke all on function public.cheongla_journal_push_preference(),public.cheongla_set_journal_push_preference(text),public.cheongla_acknowledge_study(uuid,timestamptz),public.cheongla_score_coaching_list(),public.cheongla_save_score_coaching(uuid,uuid,date,text,jsonb,text,integer),public.cheongla_score_coaching_action(uuid,text,integer)from public,anon;
grant execute on function public.cheongla_journal_push_preference(),public.cheongla_set_journal_push_preference(text),public.cheongla_acknowledge_study(uuid,timestamptz),public.cheongla_score_coaching_list(),public.cheongla_save_score_coaching(uuid,uuid,date,text,jsonb,text,integer),public.cheongla_score_coaching_action(uuid,text,integer)to authenticated;
revoke all on function cheongla_private.archive_confirmed_study(),cheongla_private.can_read_score_coaching(uuid)from public,anon,authenticated;
select cron.schedule('cheongla-confirmed-study-retention','5 * * * *','select cheongla_private.archive_confirmed_study()');
notify pgrst,'reload schema';
commit;
