create or replace function public.cheongla_daily_journal_get(work_date date)returns jsonb language plpgsql security definer set search_path='' as $$
declare r cheongla_private.daily_journals%rowtype;
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 이용할 수 있습니다.'using errcode='42501';end if;
 if work_date is null or work_date<'2020-01-01'or work_date>'2099-12-31' then raise exception '근무 날짜를 확인해 주세요.';end if;
 perform cheongla_private.seed_daily_journal(work_date);select *into r from cheongla_private.daily_journals where work_on=work_date;
 if(r.archived_at is not null or r.purged_at is not null)and not cheongla_private.is_principal()then return jsonb_build_object('work_on',work_date,'unavailable',true);end if;
 return to_jsonb(r)||jsonb_build_object('editor_name',(select full_name from public.cheongla_profiles where id=r.updated_by));
end;$$;
create or replace function public.cheongla_daily_journal_save(work_date date,document_fields jsonb,document_inks jsonb,expected_revision bigint)returns jsonb language plpgsql security definer set search_path='' as $$
declare r cheongla_private.daily_journals%rowtype;oldr jsonb;k text;
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 저장할 수 있습니다.'using errcode='42501';end if;
 if work_date is null or work_date<'2020-01-01'or work_date>'2099-12-31'then raise exception '근무 날짜를 확인해 주세요.';end if;
 perform cheongla_private.seed_daily_journal(work_date);select *into r from cheongla_private.daily_journals where work_on=work_date for update;
 if r.purged_at is not null or r.archived_at is not null then raise exception '휴지통에 있거나 삭제된 일지입니다.';end if;
 if not cheongla_private.is_principal()and(work_date<(clock_timestamp()at time zone'Asia/Seoul')::date or(work_date=(clock_timestamp()at time zone'Asia/Seoul')::date and auth.uid()=any(r.closed_by)))then raise exception '업무마감 후 또는 지난 날짜의 수정은 원장에게 요청해 주세요.'using errcode='42501';end if;
 if r.revision is distinct from expected_revision then raise exception '다른 근무자가 먼저 저장했습니다. 내 작성 내용은 화면에 유지됩니다. 최신 내용과 비교해 반영해 주세요.'using errcode='40001';end if;
 if document_fields is null or document_inks is null or jsonb_typeof(document_fields)<>'object'or jsonb_typeof(document_inks)<>'object'then raise exception '문서 형식을 확인해 주세요.';end if;
 foreach k in array array['duty','special','handover']loop
  if jsonb_typeof(document_fields->k)is distinct from 'string'or length(document_fields->>k)>60000 or not cheongla_private.valid_journal_inks(document_inks->k,document_fields->>k)then raise exception '각 칸은 60,000자 이내이며 글씨색과 본문이 일치해야 합니다.';end if;
 end loop;
 oldr:=to_jsonb(r);update cheongla_private.daily_journals set fields=document_fields,field_inks=document_inks,revision=revision+1,updated_at=clock_timestamp(),updated_by=auth.uid()where work_on=work_date returning *into r;
 insert into cheongla_private.daily_journal_history(work_on,actor_id,action,before_record,after_record)values(work_date,auth.uid(),'save',oldr,to_jsonb(r));
 return to_jsonb(r)||jsonb_build_object('editor_name',(select full_name from public.cheongla_profiles where id=auth.uid()));
end;$$;
-- References to one source excerpt, rather than daily copies of handover text.
create table cheongla_private.journal_handovers(
 id uuid primary key default gen_random_uuid(),source_date date not null references cheongla_private.daily_journals(work_on),source_field text not null check(source_field in('duty','special','handover')),
 selection_start integer not null check(selection_start>=0),excerpt text not null check(length(btrim(excerpt))between 1 and 6000),excerpt_inks jsonb not null,
 created_by uuid not null references public.cheongla_profiles(id),created_at timestamptz not null default clock_timestamp(),revision bigint not null default 1,
 completed_at timestamptz,completed_by uuid references public.cheongla_profiles(id),check((completed_at is null)=(completed_by is null))
);
create index journal_handovers_dates on cheongla_private.journal_handovers(source_date,created_at,id);
create index journal_handovers_pending on cheongla_private.journal_handovers(source_date,created_at,id)where completed_at is null;
create table cheongla_private.journal_handover_checks(handover_id uuid not null references cheongla_private.journal_handovers(id)on delete cascade,staff_id uuid not null references public.cheongla_profiles(id),checked_at timestamptz not null default clock_timestamp(),primary key(handover_id,staff_id));
create table cheongla_private.journal_handover_notes(id uuid primary key,handover_id uuid not null references cheongla_private.journal_handovers(id)on delete cascade,staff_id uuid not null references public.cheongla_profiles(id),body text not null check(length(btrim(body))between 1 and 6000),inks jsonb not null,created_at timestamptz not null default clock_timestamp());
create index journal_handover_notes_order on cheongla_private.journal_handover_notes(handover_id,created_at,id);
create table cheongla_private.journal_handover_events(id bigint generated always as identity primary key,handover_id uuid not null references cheongla_private.journal_handovers(id)on delete cascade,actor_id uuid not null references public.cheongla_profiles(id),action text not null,created_at timestamptz not null default clock_timestamp());
alter table cheongla_private.journal_handovers enable row level security;
alter table cheongla_private.journal_handover_checks enable row level security;
alter table cheongla_private.journal_handover_notes enable row level security;
alter table cheongla_private.journal_handover_events enable row level security;
revoke all on cheongla_private.journal_handovers,cheongla_private.journal_handover_checks,cheongla_private.journal_handover_notes,cheongla_private.journal_handover_events from public,anon,authenticated;

create or replace function public.cheongla_journal_handover_create(work_date date,source_field text,selection_start integer,selection_end integer,expected_revision bigint)returns uuid language plpgsql security definer set search_path=''as $$
declare d cheongla_private.daily_journals%rowtype;snippet text;part jsonb;r jsonb;pos integer:=0;a integer;b integer;result uuid;
begin
 if auth.uid()is null or not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 인계를 등록할 수 있습니다.'using errcode='42501';end if;
 select *into d from cheongla_private.daily_journals where work_on=work_date for update;
 if not found or d.archived_at is not null or d.purged_at is not null or d.revision is distinct from expected_revision then raise exception '일지가 변경되었습니다. 저장 후 최신 내용에서 다시 선택해 주세요.'using errcode='40001';end if;
 if source_field is null or source_field not in('duty','special','handover')or selection_start is null or selection_end is null or selection_start<0 or selection_end<=selection_start or selection_end>length(d.fields->>source_field)then raise exception '인계할 글자를 먼저 드래그하거나 길게 눌러 선택해 주세요.';end if;
 snippet:=substring(d.fields->>source_field from selection_start+1 for selection_end-selection_start);
 if length(btrim(snippet))not between 1 and 6000 then raise exception '인계 내용은 1자 이상 6,000자 이하로 선택해 주세요.';end if;
 select id into result from cheongla_private.journal_handovers h where h.source_date=work_date and h.source_field=cheongla_journal_handover_create.source_field and h.selection_start=cheongla_journal_handover_create.selection_start and h.excerpt=snippet and h.completed_at is null;
 if found then return result;end if;
 part:='[]';for r in select value from jsonb_array_elements(d.field_inks->source_field)loop
  a:=greatest(pos,selection_start);b:=least(pos+length(r->>'text'),selection_end);
  if b>a then part:=part||jsonb_build_array(jsonb_build_object('text',substring(r->>'text'from a-pos+1 for b-a),'ink',r->>'ink'));end if;pos:=pos+length(r->>'text');
 end loop;
 if not cheongla_private.valid_journal_inks(part,snippet)then raise exception '원문 글씨색을 확인하지 못했습니다. 다시 선택해 주세요.';end if;
 insert into cheongla_private.journal_handovers(source_date,source_field,selection_start,excerpt,excerpt_inks,created_by)values(work_date,source_field,selection_start,snippet,part,auth.uid())returning id into result;
 insert into cheongla_private.journal_handover_events(handover_id,actor_id,action)values(result,auth.uid(),'create');return result;
end;$$;

create or replace function public.cheongla_journal_handovers(work_date date,include_completed boolean default false,page_offset integer default 0,page_limit integer default 50)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare items jsonb;total integer;
begin
 if auth.uid()is null or not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 인계를 확인할 수 있습니다.'using errcode='42501';end if;
 if work_date is null or include_completed is null or page_offset is null or page_offset<0 or page_limit is null or page_limit not between 1 and 100 then raise exception '조회 범위를 확인해 주세요.';end if;
 select count(*)into total from cheongla_private.journal_handovers h join cheongla_private.daily_journals d on d.work_on=h.source_date where h.source_date<=work_date and d.archived_at is null and d.purged_at is null and(h.completed_at is not null)=include_completed;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.sort_at,x.id),'[]')into items from(
  select h.*,case when include_completed then -extract(epoch from h.completed_at)else extract(epoch from h.created_at)end as sort_at,
  coalesce(p.full_name,'이전 근무자')as author_name,cp.full_name as completed_name,
  strpos(d.fields->>h.source_field,h.excerpt)=0 as source_changed,
  (select count(*)from cheongla_private.journal_handover_notes n where n.handover_id=h.id)as note_count,
  coalesce((select jsonb_agg(jsonb_build_object('staff_id',c.staff_id,'name',s.full_name,'checked_at',c.checked_at)order by c.checked_at)from cheongla_private.journal_handover_checks c join public.cheongla_profiles s on s.id=c.staff_id where c.handover_id=h.id),'[]')as checks
  from cheongla_private.journal_handovers h join cheongla_private.daily_journals d on d.work_on=h.source_date left join public.cheongla_profiles p on p.id=h.created_by left join public.cheongla_profiles cp on cp.id=h.completed_by
  where h.source_date<=work_date and d.archived_at is null and d.purged_at is null and(h.completed_at is not null)=include_completed order by sort_at,h.id offset page_offset limit page_limit
 )x;return jsonb_build_object('items',items,'total',total);
end;$$;

create or replace function public.cheongla_journal_handover_thread(target_handover uuid,page_offset integer default 0,page_limit integer default 50)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare items jsonb;total integer;
begin
 if auth.uid()is null or not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 처리 기록을 확인할 수 있습니다.'using errcode='42501';end if;
 if not exists(select 1 from cheongla_private.journal_handovers h join cheongla_private.daily_journals d on d.work_on=h.source_date where h.id=target_handover and d.archived_at is null and d.purged_at is null)then raise exception '원래 일지가 삭제되었거나 인계를 찾을 수 없습니다.';end if;
 if page_offset is null or page_offset<0 or page_limit is null or page_limit not between 1 and 100 then raise exception '조회 범위를 확인해 주세요.';end if;
 select count(*)into total from cheongla_private.journal_handover_notes where handover_id=target_handover;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at,x.id),'[]')into items from(select n.*,coalesce(p.full_name,'이전 근무자')as author_name from cheongla_private.journal_handover_notes n left join public.cheongla_profiles p on p.id=n.staff_id where n.handover_id=target_handover order by n.created_at,n.id offset page_offset limit page_limit)x;
 return jsonb_build_object('items',items,'total',total);
end;$$;

create or replace function public.cheongla_journal_handover_action(target_handover uuid,handover_action text,expected_revision bigint)returns jsonb language plpgsql security definer set search_path=''as $$
declare h cheongla_private.journal_handovers%rowtype;
begin
 if auth.uid()is null or not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 인계를 처리할 수 있습니다.'using errcode='42501';end if;
 -- All handover mutations lock the source first, matching archive/purge lock order.
 perform 1 from cheongla_private.daily_journals d where d.work_on=(select source_date from cheongla_private.journal_handovers where id=target_handover)and d.archived_at is null and d.purged_at is null for update;
 if not found then raise exception '원래 일지가 삭제되었거나 인계를 찾을 수 없습니다.';end if;
 select *into h from cheongla_private.journal_handovers where id=target_handover for update;
 if handover_action='check'then
  insert into cheongla_private.journal_handover_checks(handover_id,staff_id)values(h.id,auth.uid())on conflict(handover_id,staff_id)do update set checked_at=clock_timestamp();
 elsif handover_action in('complete','reopen')then
  if h.revision is distinct from expected_revision then raise exception '다른 근무자가 처리했습니다. 새로고침 후 확인해 주세요.'using errcode='40001';end if;
  if(handover_action='complete'and h.completed_at is not null)or(handover_action='reopen'and h.completed_at is null)then return to_jsonb(h);end if;
  update cheongla_private.journal_handovers set completed_at=case when handover_action='complete'then clock_timestamp()end,completed_by=case when handover_action='complete'then auth.uid()end,revision=revision+1 where id=h.id returning *into h;
 else raise exception '인계 처리 방법을 확인해 주세요.';end if;
 insert into cheongla_private.journal_handover_events(handover_id,actor_id,action)values(h.id,auth.uid(),handover_action);return to_jsonb(h);
end;$$;

create or replace function public.cheongla_journal_handover_note(target_handover uuid,submission_id uuid,note_body text,note_inks jsonb)returns jsonb language plpgsql security definer set search_path=''as $$
declare h cheongla_private.journal_handovers%rowtype;n cheongla_private.journal_handover_notes%rowtype;
begin
 if auth.uid()is null or not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 처리 기록을 남길 수 있습니다.'using errcode='42501';end if;
 if submission_id is null or note_body is null or length(btrim(note_body))not between 1 and 6000 or cheongla_private.valid_journal_inks(note_inks,note_body)is not true then raise exception '처리 기록과 글씨색을 확인해 주세요. 6,000자까지 입력할 수 있습니다.';end if;
 perform 1 from cheongla_private.daily_journals d where d.work_on=(select source_date from cheongla_private.journal_handovers where id=target_handover)and d.archived_at is null and d.purged_at is null for update;
 if not found then raise exception '원래 일지가 삭제되었거나 인계를 찾을 수 없습니다.';end if;
 select *into h from cheongla_private.journal_handovers where id=target_handover for update;
 select *into n from cheongla_private.journal_handover_notes where id=submission_id;
 if found then
  if n.handover_id<>h.id or n.staff_id<>auth.uid()or n.body<>note_body or n.inks<>note_inks then raise exception '이 기록은 이미 저장되었습니다. 새로고침 후 새 답변을 작성해 주세요.';end if;return to_jsonb(h);
 end if;
 insert into cheongla_private.journal_handover_notes(id,handover_id,staff_id,body,inks)values(submission_id,h.id,auth.uid(),note_body,note_inks);
 update cheongla_private.journal_handovers set revision=revision+1 where id=h.id returning *into h;
 insert into cheongla_private.journal_handover_events(handover_id,actor_id,action)values(h.id,auth.uid(),'note');return to_jsonb(h);
end;$$;

create or replace function public.cheongla_journal_upcoming(work_date date)returns jsonb language plpgsql stable security definer set search_path=''as $$
begin
 if auth.uid()is null or not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 예정 일지를 볼 수 있습니다.'using errcode='42501';end if;
 if work_date is null then raise exception '날짜를 확인해 주세요.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('work_on',d.work_on,'preview',left(coalesce(nullif(btrim(d.fields->>'handover'),''),nullif(btrim(d.fields->>'duty'),''),d.fields->>'special'),100))order by d.work_on)from cheongla_private.daily_journals d where d.work_on>work_date and d.work_on<=work_date+7 and d.archived_at is null and d.purged_at is null and length(btrim(concat(d.fields->>'duty',d.fields->>'special',d.fields->>'handover')))>0),'[]');
end;$$;

create or replace function cheongla_private.purge_journal_handovers()returns trigger language plpgsql security definer set search_path=''as $$
begin
 if new.purged_at is not null and old.purged_at is null then delete from cheongla_private.journal_handovers where source_date=new.work_on;end if;return new;
end;$$;
revoke all on function cheongla_private.purge_journal_handovers()from public,anon,authenticated;
create trigger purge_journal_handovers before update of purged_at on cheongla_private.daily_journals for each row execute function cheongla_private.purge_journal_handovers();
revoke all on function public.cheongla_journal_handover_create(date,text,integer,integer,bigint),public.cheongla_journal_handovers(date,boolean,integer,integer),public.cheongla_journal_handover_thread(uuid,integer,integer),public.cheongla_journal_handover_action(uuid,text,bigint),public.cheongla_journal_handover_note(uuid,uuid,text,jsonb),public.cheongla_journal_upcoming(date)from public,anon,authenticated;
grant execute on function public.cheongla_journal_handover_create(date,text,integer,integer,bigint),public.cheongla_journal_handovers(date,boolean,integer,integer),public.cheongla_journal_handover_thread(uuid,integer,integer),public.cheongla_journal_handover_action(uuid,text,bigint),public.cheongla_journal_handover_note(uuid,uuid,text,jsonb),public.cheongla_journal_upcoming(date)to authenticated;

notify pgrst,'reload schema';
