-- LOCAL MEMORY DATABASE ONLY. Never execute these fixtures on the operating service.
begin;
do $$declare k integer;u uuid;d jsonb;t text:='도시락 수량 확정';begin
 for k in 1..4 loop
  u:=('07930000-0000-4000-8000-'||lpad(k::text,12,'0'))::uuid;
  insert into auth.users(id,email,raw_user_meta_data)values(u,'local-receipt-'||k||'@example.invalid',jsonb_build_object('full_name','읽음 검증 '||k));
  update public.cheongla_profiles set role=case k when 3 then'english_director'when 4 then'student'else'manager'end,approval_status='approved'where id=u;
 end loop;
 perform set_config('request.jwt.claim.sub','07930000-0000-4000-8000-000000000001',true);
 d:=public.cheongla_daily_journal_get('2097-11-08');
 d:=public.cheongla_daily_journal_save('2097-11-08',jsonb_build_object('duty',t,'special','','handover',''),jsonb_build_object('duty',jsonb_build_array(jsonb_build_object('text',t,'ink','green')),'special','[]'::jsonb,'handover','[]'::jsonb),(d->>'revision')::bigint);
 perform set_config('test.receipt_event',(select id::text from cheongla_private.journal_notification_events where work_on='2097-11-08'),true);
 perform set_config('test.receipt_notification',(select id::text from public.cheongla_notifications where source_id=current_setting('test.receipt_event')::uuid and recipient_id='07930000-0000-4000-8000-000000000002'),true);
 -- A whole page of other notifications must not hide the older journal alert.
 for k in 1..30 loop
  insert into public.cheongla_notifications(recipient_id,source_kind,source_id,title,event_key)values('07930000-0000-4000-8000-000000000002','push_test','07930000-0000-4000-8000-000000000002','별도 알림','local-other:'||k);
 end loop;
end;$$;
select set_config('request.jwt.claim.sub','07930000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$declare n jsonb;begin
 n:=public.cheongla_my_journal_notifications(20);
 if jsonb_array_length(n->'items')<>1 or(n->>'unread_count')::int<>1 then raise exception 'server journal pagination filtered incorrectly';end if;
 if n#>>'{items,0,source_kind}'<>'staff_journal'then raise exception 'other notifications leaked';end if;
 begin perform public.cheongla_journal_alert_activity(20);raise exception 'manager read monitor allowed';exception when insufficient_privilege then null;end;
 perform public.cheongla_read_notification(current_setting('test.receipt_notification')::uuid);
 if(public.cheongla_my_journal_notifications(20)->>'unread_count')::int<>0 then raise exception 'read acknowledgement not reflected';end if;
end;$$;
reset role;
select set_config('request.jwt.claim.sub','07930000-0000-4000-8000-000000000003',true);
set local role authenticated;
do $$declare a jsonb;begin
 a:=public.cheongla_journal_alert_activity(20);
 if a#>>'{items,0,work_on}'<>'2097-11-08'or(a#>>'{items,0,recipient_count}')::int<>2 or(a#>>'{items,0,read_count}')::int<>1 then raise exception 'principal per-recipient counts wrong';end if;
 if not exists(select 1 from jsonb_array_elements(a#>'{items,0,recipients}')x where x->>'name'='읽음 검증 2'and x->>'read_at'is not null)then raise exception 'read timestamp/name missing';end if;
 if has_table_privilege('authenticated','cheongla_private.journal_notification_receipts','select')then raise exception 'private receipt table exposed';end if;
end;$$;
reset role;
-- Deleting the personal inbox item must not invent a new unread acknowledgement.
delete from public.cheongla_notifications where id=current_setting('test.receipt_notification')::uuid;
do $$declare a jsonb;begin
 a:=public.cheongla_journal_alert_activity(20);
 if(a#>>'{items,0,recipient_count}')::int<>2 or(a#>>'{items,0,read_count}')::int<>1 then raise exception 'inbox deletion destroyed receipt';end if;
end;$$;
select set_config('request.jwt.claim.sub','07930000-0000-4000-8000-000000000004',true);
set local role authenticated;
do $$begin
 begin perform public.cheongla_my_journal_notifications(20);raise exception 'student inbox allowed';exception when insufficient_privilege then null;end;
 begin perform public.cheongla_journal_alert_activity(20);raise exception 'student monitor allowed';exception when insufficient_privilege then null;end;
end;$$;
reset role;
update public.cheongla_profiles set role='student'where id='07930000-0000-4000-8000-000000000003';
select set_config('request.jwt.claim.sub','07930000-0000-4000-8000-000000000003',true);
set local role authenticated;
do $$begin
 begin perform public.cheongla_journal_alert_activity(20);raise exception 'revoked principal allowed';exception when insufficient_privilege then null;end;
end;$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.cheongla_my_journal_notifications(integer)','execute')or has_function_privilege('anon','public.cheongla_journal_alert_activity(integer)','execute')then raise exception 'anonymous RPC exposure';end if;
end;$$;
select 'PASS journal-only server pagination beyond other notifications, own scope, principal recipient names/first-read timestamps, read acknowledgement, receipt survives inbox deletion, private table/anonymous/student/manager/revoked-role restrictions' as result;
rollback;
