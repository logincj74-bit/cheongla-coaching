-- Isolated database only. Simulate the passage of time by moving the due timestamp.
do $$
declare
  day date := (clock_timestamp() at time zone 'Asia/Seoul')::date;
  writer uuid := '07920000-0000-4000-8000-000000000001';
  colleague uuid := '07920000-0000-4000-8000-000000000002';
  owner_id uuid := '07920000-0000-4000-8000-000000000010';
  journal jsonb;
  fields jsonb;
  inks jsonb;
  first_event cheongla_private.journal_notification_events;
  pending cheongla_private.journal_notification_events;
  close_event_id uuid;
  note text := '시험용 순시 기록';
begin
  perform set_config('request.jwt.claim.sub', writer::text, true);
  journal := public.cheongla_daily_journal_get(day);
  fields := jsonb_set(journal->'fields', '{patrol}', to_jsonb(note));
  inks := jsonb_set(journal->'field_inks', '{patrol}', jsonb_build_array(jsonb_build_object('text', note, 'ink', 'green')));
  journal := public.cheongla_daily_journal_save(day, fields, inks, (journal->>'revision')::bigint);
  assert journal->'fields'->>'patrol' = note, 'notification delay blocked save';
  select * into strict first_event from cheongla_private.journal_notification_events;
  assert first_event.action = 'write', 'patrol was not included in classification';
  assert first_event.notify_after = first_event.last_changed_at + interval '3 minutes', 'wrong delay';
  assert not exists (select 1 from public.cheongla_notifications), 'inbox notified on autosave';
  assert not exists (select 1 from cheongla_private.push_deliveries), 'push queued on autosave';

  journal := public.cheongla_daily_journal_save(day, fields, inks, (journal->>'revision')::bigint);
  assert (select change_count from cheongla_private.journal_notification_events where id = first_event.id) = 1, 'no-op extended the window';
  update cheongla_private.journal_notification_events set notify_after = clock_timestamp() - interval '1 second'
  where id = first_event.id;
  -- An actual correction made before dispatch replaces the due time on the same event.
  inks := jsonb_set(inks, '{patrol}', jsonb_build_array(jsonb_build_object('text', note, 'ink', 'blue')));
  journal := public.cheongla_daily_journal_save(day, fields, inks, (journal->>'revision')::bigint);
  select * into strict pending from cheongla_private.journal_notification_events;
  assert pending.id = first_event.id and pending.change_count = 2, 'save batch split';
  assert pending.notify_after = pending.last_changed_at + interval '3 minutes', 'last edit did not reset delay';
  assert cheongla_private.deliver_due_daily_journal_notifications() = 0, 'worker delivered before deadline';

  -- Run as the database scheduler, without an app session.
  perform set_config('request.jwt.claim.sub', '', true);
  update cheongla_private.journal_notification_events set notify_after = clock_timestamp() - interval '1 second'
  where id = first_event.id;
  assert cheongla_private.deliver_due_daily_journal_notifications() = 1, 'scheduled delivery missing';
  assert cheongla_private.deliver_due_daily_journal_notifications() = 0, 'repeat scheduled delivery';
  assert (select count(*) from public.cheongla_notifications where source_id = first_event.id) = 5, 'wrong recipients';
  assert exists (select 1 from public.cheongla_notifications where source_id = first_event.id and recipient_id = colleague and title like '%연속 변경 2회'), 'summary missed interval';
  assert not exists (select 1 from public.cheongla_notifications where recipient_id = writer or title like '%' || note || '%'), 'self-notification or leaked journal text';
  assert (select count(*) from cheongla_private.push_deliveries) = 5, 'push was not queued exactly once per subscription';

  -- Closing one writer's shift cancels only their pending edit and alerts immediately.
  perform set_config('request.jwt.claim.sub', colleague::text, true);
  note := '다른 근무자 기록';
  fields := jsonb_set(fields, '{patrol}', to_jsonb(note));
  inks := jsonb_set(inks, '{patrol}', jsonb_build_array(jsonb_build_object('text', note, 'ink', 'green')));
  journal := public.cheongla_daily_journal_save(day, fields, inks, (journal->>'revision')::bigint);
  perform set_config('request.jwt.claim.sub', writer::text, true);
  fields := jsonb_set(fields, '{patrol}', '""');
  inks := jsonb_set(inks, '{patrol}', '[]');
  journal := public.cheongla_daily_journal_save(day, fields, inks, (journal->>'revision')::bigint);
  assert exists (select 1 from cheongla_private.journal_notification_events where actor_id = writer and action = 'content_delete' and notify_after is not null), 'deletion not batched';
  journal := public.cheongla_daily_journal_action(day, 'close', (journal->>'revision')::bigint);
  select id into strict close_event_id from cheongla_private.journal_notification_events where action = 'close';
  assert (select count(*) from public.cheongla_notifications where source_id = close_event_id) = 5, 'close was delayed';
  assert not exists (select 1 from cheongla_private.journal_notification_events where actor_id = writer and notify_after is not null), 'close left duplicate alert';
  assert exists (select 1 from cheongla_private.journal_notification_events where actor_id = colleague and notify_after is not null), 'close canceled another writer';

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  journal := public.cheongla_daily_journal_action(day, 'archive', (journal->>'revision')::bigint);
  assert not exists (select 1 from cheongla_private.journal_notification_events where notify_after is not null), 'archive left stale pending alert';
  assert exists (select 1 from public.cheongla_notifications where title like '%휴지통 이동%'), 'archive was delayed';
  assert not has_function_privilege('authenticated', 'cheongla_private.deliver_due_daily_journal_notifications()', 'execute'), 'scheduler exposed to clients';
end;
$$;
select 'PASS 3-minute debounce, no-op stability, sessionless dispatch, exactly-once inbox and push, immediate close, and cancellation.' as result;
