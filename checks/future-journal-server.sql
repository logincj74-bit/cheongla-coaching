begin isolation level repeatable read;
do $$declare k integer;u uuid;begin
 for k in 1..3 loop
 u:=('07900000-0000-4000-8000-'||lpad(k::text,12,'0'))::uuid;insert into auth.users(id,email,raw_user_meta_data)values(u,'handover-fixture-'||k||'@example.invalid',jsonb_build_object('full_name','인계 검증 '||k,'contact_phone','0100000079'||k));
 update public.cheongla_profiles set role=case when k=1 then 'english_director'when k=2 then 'manager'else 'student'end,approval_status='approved'where id=u;
 end loop;
 if exists(select 1 from cheongla_private.daily_journals where work_on='2096-11-05')then raise exception 'fixture date occupied';end if;
end;$$;
select set_config('request.jwt.claim.sub','07900000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$declare d jsonb;hid uuid;note_id uuid:=gen_random_uuid();h jsonb;r jsonb;t text:='도시락 점심 32개 · 저녁 25개. 문자 발송 완료';day date:='2096-11-05';fields jsonb;inks jsonb;base_before integer;base_total integer;base_history integer;page integer:=0;entry jsonb;
begin
 d:=public.cheongla_daily_journal_get(day);fields:=jsonb_build_object('duty',t,'special','','handover','');inks:=jsonb_build_object('duty',jsonb_build_array(jsonb_build_object('text',t,'ink','green')),'special','[]'::jsonb,'handover','[]'::jsonb);
 d:=public.cheongla_daily_journal_save(day,fields,inks,(d->>'revision')::bigint);
 begin perform public.cheongla_daily_journal_action(day,'close',(d->>'revision')::bigint);raise exception 'future close accepted';exception when raise_exception then if sqlerrm='future close accepted'then raise;end if;end;
 base_before:=(public.cheongla_journal_handovers(day-1)->>'total')::int;base_total:=(public.cheongla_journal_handovers(day+3)->>'total')::int;base_history:=(public.cheongla_journal_handovers(day+3,true)->>'total')::int;
 hid:=public.cheongla_journal_handover_create(day,'duty',0,length(t),(d->>'revision')::bigint);
 if hid<>public.cheongla_journal_handover_create(day,'duty',0,length(t),(d->>'revision')::bigint)then raise exception 'duplicate handover created';end if;
 if(public.cheongla_journal_handovers(day-1)->>'total')::int<>base_before then raise exception 'handover leaked to earlier work date';end if;
 if(public.cheongla_journal_handovers(day+1)->>'total')::int<>base_total+1 or(public.cheongla_journal_handovers(day+2)->>'total')::int<>base_total+1 or(public.cheongla_journal_handovers(day+3)->>'total')::int<>base_total+1 then raise exception 'handover did not persist across work dates';end if;
 h:=public.cheongla_journal_handover_action(hid,'check',1);
 if h->>'completed_at'is not null then raise exception 'ack completed task';end if;
 if(public.cheongla_journal_handovers(day+2)->>'total')::int<>base_total+1 then raise exception 'ack hid pending task';end if;
 h:=public.cheongla_journal_handover_note(hid,note_id,'수량과 문자 발송 내용을 확인했습니다.','[{"text":"수량과 문자 발송 내용을 확인했습니다.","ink":"purple"}]');
 perform public.cheongla_journal_handover_note(hid,note_id,'수량과 문자 발송 내용을 확인했습니다.','[{"text":"수량과 문자 발송 내용을 확인했습니다.","ink":"purple"}]');
 if(public.cheongla_journal_handover_thread(hid)->>'total')::int<>1 then raise exception 'retry duplicated note';end if;
 begin perform public.cheongla_journal_handover_action(hid,'complete',1);raise exception 'stale completion accepted';exception when serialization_failure then null;end;
 h:=public.cheongla_journal_handover_action(hid,'complete',(h->>'revision')::bigint);
 if(public.cheongla_journal_handovers(day+3)->>'total')::int<>base_total or(public.cheongla_journal_handovers(day+3,true)->>'total')::int<>base_history+1 then raise exception 'completion/history incorrect';end if;
 h:=public.cheongla_journal_handover_action(hid,'reopen',(h->>'revision')::bigint);
 if(public.cheongla_journal_handovers(day+3)->>'total')::int<>base_total+1 then raise exception 'reopen absent';end if;
 if jsonb_array_length(public.cheongla_journal_upcoming(day-1))<>1 then raise exception 'future overview absent';end if;
 if jsonb_array_length(public.cheongla_journal_upcoming(day))<>0 then raise exception 'today shown as future';end if;
 -- A later source edit must not silently rewrite the registered instruction.
 fields:=jsonb_set(fields,'{duty}','"원문을 정정했습니다."');inks:=jsonb_set(inks,'{duty}','[{"text":"원문을 정정했습니다.","ink":"green"}]');perform public.cheongla_daily_journal_save(day,fields,inks,(d->>'revision')::bigint);
 loop r:=public.cheongla_journal_handovers(day+3,false,page,100);select x into entry from jsonb_array_elements(r->'items')x where x->>'id'=hid::text;exit when entry is not null or jsonb_array_length(r->'items')=0;page:=page+100;end loop;
 if entry is null or entry->>'source_changed'<>'true'or entry->>'excerpt'<>t then raise exception 'source change not flagged/preserved';end if;
 -- Completion and comments do not change the original journal text.
 if(select j.fields->>'duty'from cheongla_private.daily_journals j where j.work_on=day)<>'원문을 정정했습니다.'then raise exception 'handover changed original body';end if;
end;$$;
select set_config('request.jwt.claim.sub','07900000-0000-4000-8000-000000000003',true);
do $$begin
 begin perform public.cheongla_journal_handovers('2096-11-08');raise exception 'student read allowed';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.cheongla_journal_handovers(date,boolean,integer,integer)','execute')or has_table_privilege('authenticated','cheongla_private.journal_handovers','select')then raise exception 'handover directly exposed';end if;
end;$$;
select set_config('request.jwt.claim.sub','07900000-0000-4000-8000-000000000001',true);
do $$declare d jsonb;hid uuid;baseline integer;begin
 select id into hid from cheongla_private.journal_handovers where source_date='2096-11-05';d:=public.cheongla_daily_journal_get('2096-11-05');baseline:=(public.cheongla_journal_handovers('2096-11-08')->>'total')::int;d:=public.cheongla_daily_journal_action('2096-11-05','archive',(d->>'revision')::bigint);
 if(public.cheongla_journal_handovers('2096-11-08')->>'total')::int<>baseline-1 then raise exception 'archived handover visible';end if;
 d:=public.cheongla_daily_journal_action('2096-11-05','restore',(d->>'revision')::bigint);if(public.cheongla_journal_handovers('2096-11-08')->>'total')::int<>baseline then raise exception 'restored handover missing';end if;
 d:=public.cheongla_daily_journal_action('2096-11-05','archive',(d->>'revision')::bigint);d:=public.cheongla_daily_journal_action('2096-11-05','purge',(d->>'revision')::bigint);
 if exists(select 1 from cheongla_private.journal_handovers where id=hid)or exists(select 1 from cheongla_private.journal_handover_notes where handover_id=hid)then raise exception 'purge retained handover data';end if;
end;$$;
select 'PASS future staff write, today-only close, date carry incl weekend, independent checks, idempotent coloured notes, completion conflict/history/reopen, source change, permissions and source trash cascade' as result;
rollback;
