-- Staff-only daily journal alerts; no journal body is copied into notifications.
create table if not exists cheongla_private.journal_notification_events(
 id uuid primary key default gen_random_uuid(),work_on date not null,
 actor_id uuid not null references public.cheongla_profiles(id),event_group text not null,
 action text not null,opened_at timestamptz not null default clock_timestamp(),
 last_changed_at timestamptz not null default clock_timestamp(),change_count integer not null default 1
);
alter table cheongla_private.journal_notification_events enable row level security;
revoke all on cheongla_private.journal_notification_events from public,anon,authenticated;
create index if not exists journal_notification_recent on cheongla_private.journal_notification_events(work_on,actor_id,event_group,opened_at desc);

create or replace function cheongla_private.notify_daily_journal_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();event_action text;group_key text;event cheongla_private.journal_notification_events%rowtype;
 people uuid[];actor_name text;label text;before_length integer;after_length integer;k text;fresh boolean:=true;
begin
 if actor is null or not cheongla_private.can_use_staff_journal()then return new;end if;
 if old.purged_at is null and new.purged_at is not null then event_action:='purge';
 elsif old.archived_at is null and new.archived_at is not null then event_action:='archive';
 elsif old.archived_at is not null and new.archived_at is null then event_action:='restore';
 elsif new.closed_by is distinct from old.closed_by and actor=any(new.closed_by)and not(actor=any(old.closed_by))then event_action:='close';
 elsif new.archived_at is null and new.purged_at is null and(new.fields is distinct from old.fields or new.field_inks is distinct from old.field_inks)then
  before_length:=0;after_length:=0;
  foreach k in array array['duty','special','handover']loop
   before_length:=before_length+length(btrim(coalesce(old.fields->>k,'')));
   after_length:=after_length+length(btrim(coalesce(new.fields->>k,'')));
  end loop;
  event_action:=case when after_length<before_length then 'content_delete'when before_length=0 and after_length>0 then 'write'else 'edit'end;
 else return new;end if;
 group_key:=case when event_action in('write','edit')then'content'else event_action end;
 perform pg_advisory_xact_lock(hashtextextended('journal-notification:'||new.work_on::text||':'||actor::text,0));
 if event_action in('write','edit','content_delete')then
  select *into event from cheongla_private.journal_notification_events
   where work_on=new.work_on and actor_id=actor and event_group=group_key and opened_at>clock_timestamp()-interval'1 minute'
   order by opened_at desc limit 1 for update;
  if found then
   update cheongla_private.journal_notification_events set action=event_action,last_changed_at=clock_timestamp(),change_count=change_count+1 where id=event.id returning *into event;fresh:=false;
  end if;
 end if;
 if fresh then
  insert into cheongla_private.journal_notification_events(work_on,actor_id,event_group,action)
   values(new.work_on,actor,group_key,event_action)returning *into event;
 end if;
 select left(full_name,30)into actor_name from public.cheongla_profiles where id=actor;
 label:=to_char(new.work_on,'YYYY.MM.DD')||' 근무일지 · '||coalesce(nullif(actor_name,''),'근무자')||' · '||case event_action
  when 'write'then'새 내용 기록'when'edit'then'내용 기록·수정'when'content_delete'then'내용 수정·삭제'
  when'close'then'업무 마감'when'archive'then'일지 삭제 · 휴지통 이동'when'restore'then'일지 복구'when'purge'then'일지 영구삭제'end;
 if event.change_count>1 then label:=label||' · 연속 변경 '||event.change_count||'회';end if;
 if fresh then
  select array_agg(id)into people from public.cheongla_profiles
   where id<>actor and approval_status='approved'and membership_state='active'
   and role in('owner','english_director','math_director','manager','korean_teacher');
  perform cheongla_private.send_notification(people,'staff_journal',event.id,null,label,'account_staffJournalPanel','journal:'||event.id::text);
 else
  -- Keep the same notification and push during a one-minute autosave batch.
  -- Never restore a trashed/read notification or resend an already delivered push.
  update public.cheongla_notifications set title=label where source_kind='staff_journal'and source_id=event.id
   and archived_at is null and inbox_until>clock_timestamp();
 end if;
 return new;
end;$$;
revoke all on function cheongla_private.notify_daily_journal_change()from public,anon,authenticated;
create or replace trigger daily_journal_change_notifications after update on cheongla_private.daily_journals
 for each row execute function cheongla_private.notify_daily_journal_change();

create or replace function cheongla_private.can_read_notification(kind text,target uuid,student uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select case
 when kind='staff_journal'then cheongla_private.can_use_staff_journal()and exists(select 1 from cheongla_private.journal_notification_events where id=target)
 when kind='director_post'then exists(select 1 from public.cheongla_director_posts where id=target and state='published'and archived_at is null)
 when kind='account_recovery'then cheongla_private.can_manage_account_recovery()and exists(select 1 from cheongla_private.account_help_requests where id=target)
 when kind='winter_booking'then exists(select 1 from cheongla_private.winter_bookings r where r.id=target and r.archived_at is null and(cheongla_private.can_manage_winter()or(cheongla_private.can_use_member_services()and r.owner_id=auth.uid())))
 else cheongla_private.can_read_notification_before_winter(kind,target,student)end;
$$;
revoke all on function cheongla_private.can_read_notification(text,uuid,uuid)from public,anon;
grant execute on function cheongla_private.can_read_notification(text,uuid,uuid)to authenticated;

create or replace function public.cheongla_journal_notification_context(target_event uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare event cheongla_private.journal_notification_events%rowtype;d cheongla_private.daily_journals%rowtype;
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 근무일지 알림을 열 수 있습니다.'using errcode='42501';end if;
 if not exists(select 1 from public.cheongla_notifications where recipient_id=auth.uid()and source_kind='staff_journal'and source_id=target_event and archived_at is null and inbox_until>clock_timestamp())then raise exception '본인의 활성 근무일지 알림만 열 수 있습니다.'using errcode='42501';end if;
 select *into event from cheongla_private.journal_notification_events where id=target_event;
 if not found then raise exception '근무일지 알림을 찾을 수 없습니다.';end if;
 select *into d from cheongla_private.daily_journals where work_on=event.work_on;
 return jsonb_build_object('work_on',event.work_on,'action',event.action,'change_count',event.change_count,'archived',d.archived_at is not null,'purged',d.purged_at is not null);
end;$$;
revoke all on function public.cheongla_journal_notification_context(uuid)from public,anon;
grant execute on function public.cheongla_journal_notification_context(uuid)to authenticated;
notify pgrst,'reload schema';
