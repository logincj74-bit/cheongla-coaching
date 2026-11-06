begin;
-- LOCAL TEST ONLY: run via journal-notifications-local.mjs. Never run fixtures on production.
-- Only fake local users and subscriptions are used; no network dispatcher exists.
do $$declare k integer;u uuid;begin
 if exists(select 1 from cheongla_private.daily_journals where work_on='2097-11-07')then raise exception 'fixture date occupied';end if;
 for k in 1..10 loop
  u:=('07920000-0000-4000-8000-'||lpad(k::text,12,'0'))::uuid;
  insert into auth.users(id,email,raw_user_meta_data)values(u,'journal-notification-fixture-'||k||'@example.invalid',jsonb_build_object('full_name','근무알림 검증 '||k,'contact_phone','010000092'||lpad(k::text,2,'0')));
  update public.cheongla_profiles set role=case k when 3 then'english_director'when 4 then'math_director'when 5 then'korean_teacher'when 6 then'student'when 7 then'parent'when 10 then'owner'else'manager'end,
   approval_status=case k when 8 then'pending'when 9 then'suspended'else'approved'end,
   membership_state=case when k=9 then'withdrawn'else'active'end where id=u;
 end loop;
end;$$;
select set_config('request.jwt.claim.sub','07920000-0000-4000-8000-000000000001',true);
do $$declare d jsonb;t text;fields jsonb;inks jsonb;first_event uuid;second_event uuid;n integer;before_queue bigint;day date:='2097-11-07';today date:=(clock_timestamp()at time zone'Asia/Seoul')::date;td jsonb;begin
 d:=public.cheongla_daily_journal_get(day);
 if exists(select 1 from cheongla_private.journal_notification_events where work_on=day)then raise exception 'viewing seeded a notification';end if;
 t:='도시락 점심 32개';fields:=jsonb_build_object('duty',t,'special','','handover','');inks:=jsonb_build_object('duty',jsonb_build_array(jsonb_build_object('text',t,'ink','green')),'special','[]'::jsonb,'handover','[]'::jsonb);
 d:=public.cheongla_daily_journal_save(day,fields,inks,(d->>'revision')::bigint);
 select id into first_event from cheongla_private.journal_notification_events where work_on=day;
 if first_event is null then raise exception 'save produced no event';end if;
 if(select action from cheongla_private.journal_notification_events where id=first_event)<>'write'then raise exception 'new content not classified';end if;
 select count(*)into n from public.cheongla_notifications where source_kind='staff_journal'and source_id=first_event and recipient_id::text like'07920000-%';
 if n<>5 then raise exception 'wrong eligible fixture recipients: %',n;end if;
 if exists(select 1 from public.cheongla_notifications where source_id=first_event and recipient_id in('07920000-0000-4000-8000-000000000001','07920000-0000-4000-8000-000000000006','07920000-0000-4000-8000-000000000007','07920000-0000-4000-8000-000000000008','07920000-0000-4000-8000-000000000009'))then raise exception 'self or unauthorized recipient';end if;
 if exists(select 1 from public.cheongla_notifications where source_id=first_event and title like'%도시락 점심%')then raise exception 'journal body leaked into title';end if;
 select count(*)into before_queue from cheongla_private.push_deliveries p join public.cheongla_notifications n on n.id=p.notification_id where n.source_id=first_event;
 if before_queue<>(select count(*)from public.cheongla_push_subscriptions s join public.cheongla_notifications n on n.recipient_id=s.user_id where n.source_id=first_event and s.enabled)then raise exception 'outbox count mismatch';end if;
 d:=public.cheongla_daily_journal_save(day,fields,inks,(d->>'revision')::bigint);
 if(select change_count from cheongla_private.journal_notification_events where id=first_event)<>1 then raise exception 'no-op save notified';end if;
 update public.cheongla_notifications set archived_at=clock_timestamp()where source_id=first_event and recipient_id='07920000-0000-4000-8000-000000000002';
 update public.cheongla_notifications set read_at=clock_timestamp()where source_id=first_event and recipient_id='07920000-0000-4000-8000-000000000003';
 t:=t||' · 업체 문자 발송 완료';fields:=jsonb_set(fields,'{duty}',to_jsonb(t));inks:=jsonb_set(inks,'{duty}',jsonb_build_array(jsonb_build_object('text',t,'ink','green')));
 d:=public.cheongla_daily_journal_save(day,fields,inks,(d->>'revision')::bigint);
 if(select count(*)from cheongla_private.journal_notification_events where work_on=day)<>1 or(select change_count from cheongla_private.journal_notification_events where id=first_event)<>2 then raise exception 'autosaves not coalesced';end if;
 if(select archived_at from public.cheongla_notifications where source_id=first_event and recipient_id='07920000-0000-4000-8000-000000000002')is null then raise exception 'trashed notification revived';end if;
 if(select read_at from public.cheongla_notifications where source_id=first_event and recipient_id='07920000-0000-4000-8000-000000000003')is null then raise exception 'read state reset';end if;
 if before_queue<>(select count(*)from cheongla_private.push_deliveries p join public.cheongla_notifications n on n.id=p.notification_id where n.source_id=first_event)then raise exception 'coalescing requeued push';end if;
 update cheongla_private.journal_notification_events set opened_at=clock_timestamp()-interval'61 seconds'where id=first_event;
 t:=t||' · 수량 확인';fields:=jsonb_set(fields,'{duty}',to_jsonb(t));inks:=jsonb_set(inks,'{duty}',jsonb_build_array(jsonb_build_object('text',t,'ink','green')));
 d:=public.cheongla_daily_journal_save(day,fields,inks,(d->>'revision')::bigint);
 if(select count(*)from cheongla_private.journal_notification_events where work_on=day)<>2 then raise exception 'later change lost';end if;
 perform set_config('request.jwt.claim.sub','07920000-0000-4000-8000-000000000002',true);
 -- A colour-only correction is a real edit and a different actor gets a new alert.
 inks:=jsonb_set(inks,'{duty}',jsonb_build_array(jsonb_build_object('text',t,'ink','blue')));
 d:=public.cheongla_daily_journal_save(day,fields,inks,(d->>'revision')::bigint);
 if(select count(*)from cheongla_private.journal_notification_events where work_on=day)<>3 then raise exception 'colour/different actor change lost';end if;
 t:='수량 확인';fields:=jsonb_set(fields,'{duty}',to_jsonb(t));inks:=jsonb_set(inks,'{duty}',jsonb_build_array(jsonb_build_object('text',t,'ink','blue')));
 d:=public.cheongla_daily_journal_save(day,fields,inks,(d->>'revision')::bigint);
 if not exists(select 1 from cheongla_private.journal_notification_events where work_on=day and action='content_delete')then raise exception 'content deletion missing';end if;
 -- The isolated database contains no real journal, so exercise the actual close RPC.
 td:=public.cheongla_daily_journal_get(today);td:=public.cheongla_daily_journal_save(today,fields,inks,(td->>'revision')::bigint);
 td:=public.cheongla_daily_journal_action(today,'close',(td->>'revision')::bigint);
 td:=public.cheongla_daily_journal_action(today,'close',(td->>'revision')::bigint);
 if(select count(*)from cheongla_private.journal_notification_events where work_on=today and action='close')<>1 then raise exception 'close missing or duplicated';end if;
 perform set_config('request.jwt.claim.sub','07920000-0000-4000-8000-000000000010',true);
 d:=public.cheongla_daily_journal_get(day);d:=public.cheongla_daily_journal_action(day,'archive',(d->>'revision')::bigint);
 d:=public.cheongla_daily_journal_action(day,'restore',(d->>'revision')::bigint);
 d:=public.cheongla_daily_journal_action(day,'archive',(d->>'revision')::bigint);
 d:=public.cheongla_daily_journal_action(day,'purge',(d->>'revision')::bigint);
 if(select count(*)from cheongla_private.journal_notification_events where work_on=day and action='archive')<>2 then raise exception 'archive missing/duplicated';end if;
 if not exists(select 1 from cheongla_private.journal_notification_events where work_on=day and action='restore')then raise exception 'restore missing';end if;
 select id into second_event from cheongla_private.journal_notification_events where work_on=day and action='purge';
 if second_event is null then raise exception 'purge event missing';end if;
 perform set_config('test.journal_notification_event',second_event::text,true);
 if not cheongla_private.push_source_allowed('07920000-0000-4000-8000-000000000002','staff_journal',second_event,null)then raise exception 'staff push authorization failed';end if;
 if cheongla_private.push_source_allowed('07920000-0000-4000-8000-000000000006','staff_journal',second_event,null)then raise exception 'student push allowed';end if;
end;$$;
select set_config('request.jwt.claim.sub','07920000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$declare ctx jsonb;begin
 ctx:=public.cheongla_journal_notification_context(current_setting('test.journal_notification_event')::uuid);
 if ctx->>'work_on'<>'2097-11-07'or ctx->>'purged'<>'true'then raise exception 'exact date/purge context missing';end if;
 if not exists(select 1 from public.cheongla_notifications where source_id=current_setting('test.journal_notification_event')::uuid)then raise exception 'RLS hides eligible alert';end if;
 if has_table_privilege('authenticated','cheongla_private.journal_notification_events','select')then raise exception 'private event table exposed';end if;
 begin perform public.cheongla_journal_notification_context('07920000-0000-4000-9000-000000000001');raise exception 'arbitrary context allowed';exception when insufficient_privilege then null;end;
end;$$;
select set_config('request.jwt.claim.sub','07920000-0000-4000-8000-000000000006',true);
do $$begin
 if exists(select 1 from public.cheongla_notifications where source_kind='staff_journal')then raise exception 'student sees staff notifications';end if;
 begin perform public.cheongla_journal_notification_context(current_setting('test.journal_notification_event')::uuid);raise exception 'student context allowed';exception when insufficient_privilege then null;end;
end;$$;
reset role;
update public.cheongla_profiles set role='student'where id='07920000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub','07920000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.cheongla_notifications where source_kind='staff_journal')then raise exception 'revoked staff still sees alerts';end if;
end;$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.cheongla_journal_notification_context(uuid)','execute')then raise exception 'anonymous context callable';end if;
end;$$;
select 'PASS journal write/edit/colour/delete/close/archive/restore/purge; no-op and seed silent; exact staff recipients; 60s coalescing/new window; no content leakage; persistent outbox; read/trash retained; RLS and context authorization; revoked role denied. Everything rolled back.'as result;
rollback;
