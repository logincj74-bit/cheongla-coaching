-- A daily shared document: plain text + validated colour runs, no stored HTML.
create table if not exists cheongla_private.daily_journals(
 work_on date primary key, fields jsonb not null default '{"duty":"","special":"","handover":""}',
 field_inks jsonb not null default '{"duty":[],"special":[],"handover":[]}',
 revision bigint not null default 1, updated_at timestamptz not null default clock_timestamp(),updated_by uuid references public.cheongla_profiles(id),
 closed_by uuid[] not null default '{}',archived_at timestamptz,purged_at timestamptz
);
alter table cheongla_private.daily_journals enable row level security;
revoke all on cheongla_private.daily_journals from public,anon,authenticated;
create table if not exists cheongla_private.daily_journal_history(
 id uuid primary key default gen_random_uuid(),work_on date not null,actor_id uuid references public.cheongla_profiles(id),
 action text not null,created_at timestamptz not null default clock_timestamp(),before_record jsonb,after_record jsonb
);
alter table cheongla_private.daily_journal_history enable row level security;
revoke all on cheongla_private.daily_journal_history from public,anon,authenticated;

-- Called only from authorized RPCs; once created, a document is never rebuilt from old records.
create or replace function cheongla_private.seed_daily_journal(day date)returns void language plpgsql security definer set search_path='' as $$
declare j record;c record;k text;t text;fields jsonb:='{"duty":"","special":"","handover":""}';inks jsonb:='{"duty":[],"special":[],"handover":[]}';part jsonb;closed uuid[]:='{}';
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 이용할 수 있습니다.'using errcode='42501';end if;
 if day is null or day<'2020-01-01'or day>(clock_timestamp()at time zone'Asia/Seoul')::date then raise exception '근무 날짜를 확인해 주세요.';end if;
 perform pg_advisory_xact_lock(hashtext('daily-journal:'||day::text));
 if exists(select 1 from cheongla_private.daily_journals where work_on=day)then return;end if;
 for j in select *from cheongla_private.staff_journals where work_on=day and archived_at is null order by created_at,id loop
  if j.closed_at is not null then closed:=array_append(closed,j.author_id);end if;
  foreach k in array array['duty','special','handover']loop
   t:=to_jsonb(j)->>k;
   if coalesce(t,'')<>''then
    if fields->>k<>''then fields:=jsonb_set(fields,array[k],to_jsonb((fields->>k)||E'\n\n'));inks:=jsonb_set(inks,array[k],(inks->k)||jsonb_build_array(jsonb_build_object('text',E'\n\n','ink',j.ink_color)));end if;
    part:=case when cheongla_private.valid_journal_inks(j.field_inks->k,t)then j.field_inks->k else jsonb_build_array(jsonb_build_object('text',t,'ink',j.ink_color))end;
    fields:=jsonb_set(fields,array[k],to_jsonb((fields->>k)||t));inks:=jsonb_set(inks,array[k],(inks->k)||part);
   end if;
   for c in select *from cheongla_private.staff_journal_comments where journal_id=j.id and field_key=k and deleted_at is null order by created_at,id loop
    t:=case when fields->>k=''then ''else E'\n'end;
    fields:=jsonb_set(fields,array[k],to_jsonb((fields->>k)||t||c.body));
    part:=case when cheongla_private.valid_journal_inks(c.ink_runs,c.body)then c.ink_runs else jsonb_build_array(jsonb_build_object('text',c.body,'ink',c.ink_color))end;
    inks:=jsonb_set(inks,array[k],(inks->k)||case when t=''then '[]'::jsonb else jsonb_build_array(jsonb_build_object('text',t,'ink',c.ink_color))end||part);
   end loop;
  end loop;
 end loop;
 insert into cheongla_private.daily_journals(work_on,fields,field_inks,closed_by,updated_by)values(day,fields,inks,closed,auth.uid())on conflict do nothing;
end;$$;
revoke all on function cheongla_private.seed_daily_journal(date)from public,anon,authenticated;

create or replace function public.cheongla_daily_journal_get(work_date date)returns jsonb language plpgsql security definer set search_path='' as $$
declare r cheongla_private.daily_journals%rowtype;
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 이용할 수 있습니다.'using errcode='42501';end if;
 if work_date is null or work_date<'2020-01-01'or work_date>(clock_timestamp()at time zone'Asia/Seoul')::date then raise exception '근무 날짜를 확인해 주세요.';end if;
 perform cheongla_private.seed_daily_journal(work_date);select *into r from cheongla_private.daily_journals where work_on=work_date;
 if(r.archived_at is not null or r.purged_at is not null)and not cheongla_private.is_principal()then return jsonb_build_object('work_on',work_date,'unavailable',true);end if;
 return to_jsonb(r)||jsonb_build_object('editor_name',(select full_name from public.cheongla_profiles where id=r.updated_by));
end;$$;

create or replace function public.cheongla_daily_journal_list(target_month date)returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 이용할 수 있습니다.'using errcode='42501';end if;
 if target_month is null then raise exception '조회 월을 선택해 주세요.';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)order by x.work_on desc)from(
 select d.work_on,d.revision,d.updated_at,d.archived_at,d.purged_at from cheongla_private.daily_journals d where d.work_on>=date_trunc('month',target_month)::date and d.work_on<(date_trunc('month',target_month)+interval'1 month')::date and d.purged_at is null and(d.archived_at is null or cheongla_private.is_principal())
 union all select distinct j.work_on,0::bigint,null::timestamptz,null::timestamptz,null::timestamptz from cheongla_private.staff_journals j where j.archived_at is null and j.work_on>=date_trunc('month',target_month)::date and j.work_on<(date_trunc('month',target_month)+interval'1 month')::date and not exists(select 1 from cheongla_private.daily_journals d where d.work_on=j.work_on)
 )x),'[]');
end;$$;

create or replace function public.cheongla_daily_journal_save(work_date date,document_fields jsonb,document_inks jsonb,expected_revision bigint)returns jsonb language plpgsql security definer set search_path='' as $$
declare r cheongla_private.daily_journals%rowtype;oldr jsonb;k text;
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 저장할 수 있습니다.'using errcode='42501';end if;
 perform cheongla_private.seed_daily_journal(work_date);select *into r from cheongla_private.daily_journals where work_on=work_date for update;
 if r.purged_at is not null or r.archived_at is not null then raise exception '휴지통에 있거나 삭제된 일지입니다.';end if;
 if not cheongla_private.is_principal()and(work_date<>(clock_timestamp()at time zone'Asia/Seoul')::date or auth.uid()=any(r.closed_by))then raise exception '업무마감 후 또는 지난 날짜의 수정은 원장에게 요청해 주세요.'using errcode='42501';end if;
 if r.revision is distinct from expected_revision then raise exception '다른 근무자가 먼저 저장했습니다. 내 작성 내용은 화면에 유지됩니다. 최신 내용과 비교해 반영해 주세요.'using errcode='40001';end if;
 if document_fields is null or document_inks is null or jsonb_typeof(document_fields)<>'object'or jsonb_typeof(document_inks)<>'object'then raise exception '문서 형식을 확인해 주세요.';end if;
 foreach k in array array['duty','special','handover']loop
  if jsonb_typeof(document_fields->k)is distinct from 'string'or length(document_fields->>k)>60000 or not cheongla_private.valid_journal_inks(document_inks->k,document_fields->>k)then raise exception '각 칸은 60,000자 이내이며 글씨색과 본문이 일치해야 합니다.';end if;
 end loop;
 oldr:=to_jsonb(r);update cheongla_private.daily_journals set fields=document_fields,field_inks=document_inks,revision=revision+1,updated_at=clock_timestamp(),updated_by=auth.uid()where work_on=work_date returning *into r;
 insert into cheongla_private.daily_journal_history(work_on,actor_id,action,before_record,after_record)values(work_date,auth.uid(),'save',oldr,to_jsonb(r));
 return to_jsonb(r)||jsonb_build_object('editor_name',(select full_name from public.cheongla_profiles where id=auth.uid()));
end;$$;

create or replace function public.cheongla_daily_journal_action(work_date date,document_action text,expected_revision bigint)returns jsonb language plpgsql security definer set search_path='' as $$
declare r cheongla_private.daily_journals%rowtype;oldr jsonb;
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 이용할 수 있습니다.'using errcode='42501';end if;
 if document_action<>'close'and not cheongla_private.is_principal()then raise exception '삭제·복구·영구삭제는 원장만 가능합니다.'using errcode='42501';end if;
 select *into r from cheongla_private.daily_journals where work_on=work_date for update;
 if not found or r.purged_at is not null then raise exception '일지를 찾을 수 없습니다.';end if;
 if r.revision is distinct from expected_revision then raise exception '일지가 변경되었습니다. 새로고침해 주세요.'using errcode='40001';end if;oldr:=to_jsonb(r);
 if document_action='close'and r.archived_at is null then
  if work_date<>(clock_timestamp()at time zone'Asia/Seoul')::date then raise exception '오늘의 근무만 마감할 수 있습니다.';end if;
  update cheongla_private.daily_journals set closed_by=case when auth.uid()=any(closed_by)then closed_by else array_append(closed_by,auth.uid())end where work_on=work_date;
 elsif document_action='archive'and r.archived_at is null then update cheongla_private.daily_journals set archived_at=clock_timestamp()where work_on=work_date;
 elsif document_action='restore'and r.archived_at is not null then update cheongla_private.daily_journals set archived_at=null where work_on=work_date;
 elsif document_action='purge'and r.archived_at is not null then
  -- Retain only a tombstone to prevent legacy contents reappearing.
  delete from cheongla_private.daily_journal_history where work_on=work_date;
  delete from cheongla_private.staff_journal_comments where journal_id in(select id from cheongla_private.staff_journals where work_on=work_date);
  delete from cheongla_private.staff_journal_history where journal_id in(select id from cheongla_private.staff_journals where work_on=work_date);
  delete from cheongla_private.staff_journals where work_on=work_date;
  update cheongla_private.daily_journals set fields='{}',field_inks='{}',closed_by='{}',purged_at=clock_timestamp()where work_on=work_date;
 else raise exception '처리 항목과 휴지통 상태를 확인해 주세요.';end if;
 update cheongla_private.daily_journals set revision=revision+1,updated_at=clock_timestamp(),updated_by=auth.uid()where work_on=work_date returning *into r;
 if document_action<>'purge'then insert into cheongla_private.daily_journal_history(work_on,actor_id,action,before_record,after_record)values(work_date,auth.uid(),document_action,oldr,to_jsonb(r));end if;
 return to_jsonb(r);
end;$$;
revoke all on function public.cheongla_daily_journal_get(date),public.cheongla_daily_journal_list(date),public.cheongla_daily_journal_save(date,jsonb,jsonb,bigint),public.cheongla_daily_journal_action(date,text,bigint)from public,anon;
grant execute on function public.cheongla_daily_journal_get(date),public.cheongla_daily_journal_list(date),public.cheongla_daily_journal_save(date,jsonb,jsonb,bigint),public.cheongla_daily_journal_action(date,text,bigint)to authenticated;
notify pgrst,'reload schema';

-- Old tabs must not silently write to a superseded per-author document.
create or replace function cheongla_private.guard_legacy_journal_write()returns trigger language plpgsql security definer set search_path='' as $$
declare day date;d cheongla_private.daily_journals%rowtype;
begin
 if tg_table_name='staff_journals'then day:=new.work_on;else select work_on into day from cheongla_private.staff_journals where id=new.journal_id;end if;
 select *into d from cheongla_private.daily_journals where work_on=day;
 if found then
  if tg_table_name='staff_journals'then if tg_op='UPDATE'then if old.archived_at is not null and new.archived_at is null and d.purged_at is null and d.archived_at is null and cheongla_private.is_principal()then return new;end if;end if;end if;
  raise exception '공동 근무일지로 바뀌었습니다. 현재 작성 내용을 복사해 둔 뒤 최신 청라앱을 다시 열어 주세요.'using errcode='40001';
 end if;return new;
end;$$;
revoke all on function cheongla_private.guard_legacy_journal_write()from public,anon,authenticated;
create trigger daily_journal_guard_old_records before insert or update on cheongla_private.staff_journals for each row execute function cheongla_private.guard_legacy_journal_write();
create trigger daily_journal_guard_old_comments before insert or update on cheongla_private.staff_journal_comments for each row execute function cheongla_private.guard_legacy_journal_write();

create or replace function cheongla_private.merge_restored_legacy_journal()returns trigger language plpgsql security definer set search_path='' as $$
declare d cheongla_private.daily_journals%rowtype;k text;t text;part jsonb;c record;before_value jsonb;prefix text;
begin
 if old.archived_at is null or new.archived_at is not null then return new;end if;
 select *into d from cheongla_private.daily_journals where work_on=new.work_on and purged_at is null and archived_at is null for update;
 if not found then return new;end if;
 before_value:=to_jsonb(d);
 foreach k in array array['duty','special','handover']loop
  t:=to_jsonb(new)->>k;
  if coalesce(t,'')<>''then
   prefix:=case when d.fields->>k=''then ''else E'\n\n'end;
   part:=case when cheongla_private.valid_journal_inks(new.field_inks->k,t)then new.field_inks->k else jsonb_build_array(jsonb_build_object('text',t,'ink',new.ink_color))end;
   d.fields:=jsonb_set(d.fields,array[k],to_jsonb((d.fields->>k)||prefix||t));
   d.field_inks:=jsonb_set(d.field_inks,array[k],(d.field_inks->k)||case when prefix=''then '[]'::jsonb else jsonb_build_array(jsonb_build_object('text',prefix,'ink',new.ink_color))end||part);
  end if;
  for c in select *from cheongla_private.staff_journal_comments where journal_id=new.id and field_key=k and deleted_at is null order by created_at,id loop
   prefix:=case when d.fields->>k=''then ''else E'\n'end;
   part:=case when cheongla_private.valid_journal_inks(c.ink_runs,c.body)then c.ink_runs else jsonb_build_array(jsonb_build_object('text',c.body,'ink',c.ink_color))end;
   d.fields:=jsonb_set(d.fields,array[k],to_jsonb((d.fields->>k)||prefix||c.body));
   d.field_inks:=jsonb_set(d.field_inks,array[k],(d.field_inks->k)||case when prefix=''then '[]'::jsonb else jsonb_build_array(jsonb_build_object('text',prefix,'ink',c.ink_color))end||part);
  end loop;
 end loop;
 update cheongla_private.daily_journals set fields=d.fields,field_inks=d.field_inks,revision=revision+1,updated_at=clock_timestamp(),updated_by=auth.uid()where work_on=new.work_on returning *into d;
 insert into cheongla_private.daily_journal_history(work_on,actor_id,action,before_record,after_record)values(new.work_on,auth.uid(),'restore_legacy',before_value,to_jsonb(d));
 return new;
end;$$;
revoke all on function cheongla_private.merge_restored_legacy_journal()from public,anon,authenticated;
create trigger daily_journal_merge_legacy_restore after update on cheongla_private.staff_journals for each row execute function cheongla_private.merge_restored_legacy_journal();
