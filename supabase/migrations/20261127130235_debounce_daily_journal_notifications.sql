-- Keep autosave independent from delivery. A pending event has no inbox or push rows.
alter table cheongla_private.journal_notification_events
  add column notify_after timestamptz;

create unique index journal_notification_one_pending_per_writer
  on cheongla_private.journal_notification_events (work_on, actor_id)
  where notify_after is not null;

create index journal_notification_due
  on cheongla_private.journal_notification_events (notify_after, id)
  where notify_after is not null;

create function cheongla_private.deliver_daily_journal_notification(
  event cheongla_private.journal_notification_events
)
returns void language plpgsql set search_path = '' as $$
declare
  people uuid[];
  actor_name text;
  label text;
begin
  select left(full_name, 30) into actor_name
  from public.cheongla_profiles
  where id = event.actor_id and approval_status = 'approved' and membership_state = 'active'
    and role in ('owner', 'english_director', 'math_director', 'manager', 'korean_teacher');
  if not found then return; end if;

  select array_agg(id) into people
  from public.cheongla_profiles
  where id <> event.actor_id and approval_status = 'approved' and membership_state = 'active'
    and role in ('owner', 'english_director', 'math_director', 'manager', 'korean_teacher');

  label := to_char(event.work_on, 'YYYY.MM.DD') || ' 근무일지 · ' ||
    coalesce(nullif(actor_name, ''), '근무자') || ' · ' ||
    case event.action
      when 'write' then '새 내용 기록'
      when 'edit' then '내용 기록·수정'
      when 'content_delete' then '내용 수정·삭제'
      when 'close' then '업무 마감'
      when 'archive' then '일지 삭제 · 휴지통 이동'
      when 'restore' then '일지 복구'
      when 'purge' then '일지 영구삭제'
    end;
  if event.change_count > 1 then
    label := label || ' · 연속 변경 ' || event.change_count || '회';
  end if;
  perform cheongla_private.send_notification(
    people, 'staff_journal', event.id, null, label, 'account_staffJournalPanel',
    'journal:' || event.id::text
  );
end;
$$;

create or replace function cheongla_private.notify_daily_journal_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  event_action text;
  event cheongla_private.journal_notification_events;
  changed_at timestamptz;
  before_length integer;
  after_length integer;
begin
  if actor is null or not cheongla_private.can_use_staff_journal() then return new; end if;

  if old.purged_at is null and new.purged_at is not null then
    event_action := 'purge';
  elsif old.archived_at is null and new.archived_at is not null then
    event_action := 'archive';
  elsif old.archived_at is not null and new.archived_at is null then
    event_action := 'restore';
  elsif new.closed_by is distinct from old.closed_by and actor = any(new.closed_by)
    and not (actor = any(old.closed_by)) then
    event_action := 'close';
  elsif new.archived_at is null and new.purged_at is null and
    (new.fields is distinct from old.fields or new.field_inks is distinct from old.field_inks) then
    select sum(length(btrim(coalesce(old.fields->>k, '')))),
           sum(length(btrim(coalesce(new.fields->>k, ''))))
    into before_length, after_length
    from unnest(array['duty', 'special', 'handover', 'patrol']) as field(k);

    event_action := case
      when after_length < before_length then 'content_delete'
      when before_length = 0 and after_length > 0 then 'write'
      else 'edit'
    end;
    changed_at := clock_timestamp();
    insert into cheongla_private.journal_notification_events as pending
      (work_on, actor_id, event_group, action, opened_at, last_changed_at, notify_after)
    values (new.work_on, actor, 'content', event_action, changed_at, changed_at,
      changed_at + interval '3 minutes')
    on conflict (work_on, actor_id) where notify_after is not null
    do update set action = excluded.action,
      last_changed_at = excluded.last_changed_at,
      notify_after = excluded.notify_after,
      change_count = pending.change_count + 1;
    return new;
  else
    return new;
  end if;

  if event_action in ('close', 'archive', 'purge') then
    delete from cheongla_private.journal_notification_events
    where work_on = new.work_on and notify_after is not null
      and (event_action <> 'close' or actor_id = actor);
  end if;

  insert into cheongla_private.journal_notification_events (work_on, actor_id, event_group, action)
  values (new.work_on, actor, event_action, event_action) returning * into event;
  perform cheongla_private.deliver_daily_journal_notification(event);
  return new;
end;
$$;

create function cheongla_private.deliver_due_daily_journal_notifications()
returns integer language plpgsql set search_path = '' as $$
declare
  event cheongla_private.journal_notification_events;
  cutoff timestamptz := clock_timestamp();
  processed integer := 0;
begin
  for event in
    select * from cheongla_private.journal_notification_events
    where notify_after <= cutoff
    order by notify_after, id
    limit 50
    for update skip locked
  loop
    perform cheongla_private.deliver_daily_journal_notification(event);
    update cheongla_private.journal_notification_events
    set notify_after = null where id = event.id;
    processed := processed + 1;
  end loop;
  return processed;
end;
$$;

revoke all on function cheongla_private.deliver_daily_journal_notification(
  cheongla_private.journal_notification_events
) from public, anon, authenticated;
revoke all on function cheongla_private.deliver_due_daily_journal_notifications()
  from public, anon, authenticated;

select cron.schedule(
  'cheongla-daily-journal-notifications', '15 seconds',
  'select cheongla_private.deliver_due_daily_journal_notifications()'
);
