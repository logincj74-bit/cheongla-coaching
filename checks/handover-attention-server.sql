begin;
insert into auth.users(id,email,raw_user_meta_data)values('07900000-0000-4000-8000-000000000004','attention-fixture@example.invalid','{"full_name":"인계 확인 검증","contact_phone":"01000000794"}');
update public.cheongla_profiles set role='manager',approval_status='approved'where id='07900000-0000-4000-8000-000000000004';
select set_config('request.jwt.claim.sub','07900000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$declare today date:=(now()at time zone'Asia/Seoul')::date;fixture uuid[]:='{}';hid uuid;r jsonb;item jsonb;kind text;age integer;k integer;count_before integer;revision bigint;
begin
 for k in 1..8 loop
 kind:=case when k in(1,2)then'daily'when k in(3,4,8)then'general'else'long'end;
 age:=case k when 1 then 1 when 2 then 2 when 3 then 2 when 4 then 4 when 5 then 7 when 6 then 14 when 7 then 2 else -1 end;
 insert into cheongla_private.daily_journals(work_on,fields,field_inks,updated_by)values(today-age,'{"duty":"","special":"","handover":""}','{"duty":[],"special":[],"handover":[]}',auth.uid())on conflict do nothing;
 insert into cheongla_private.journal_handovers(source_date,source_field,selection_start,excerpt,excerpt_inks,created_by,handover_kind)values(today-age,'duty',0,'검증용 인계','[{"text":"검증용 인계","ink":"red"}]',auth.uid(),kind)returning id into hid;
 fixture:=array_append(fixture,hid);
 end loop;
 r:=public.cheongla_journal_handovers(today+1,false,0,100);
 for k in 1..8 loop
 select x into item from jsonb_array_elements(r->'items')x where x->>'id'=fixture[k]::text;
 if item is null then raise exception 'fixture not in first 100 results';end if;
 if(item->>'attention_level')::int<>(case when k in(2,4,6)then 2 when k in(1,3,5)then 1 else 0 end)then raise exception 'wrong category threshold fixture %',k;end if;
 end loop;
 -- Viewing a past or future journal must not advance or rewind the real elapsed days.
 r:=public.cheongla_journal_handovers(today-1,false,0,100);
 select x into item from jsonb_array_elements(r->'items')x where x->>'id'=fixture[4]::text;
 if(item->>'days_elapsed')::int<>4 then raise exception 'elapsed time depends on viewed date';end if;
 perform public.cheongla_journal_handover_action(fixture[6],'check',1);
 r:=public.cheongla_journal_handovers(today,false,0,1);
 if r#>>'{items,0,is_unread}'<>'true'then raise exception 'unread priority not applied before pagination';end if;
 r:=public.cheongla_journal_handovers(today,false,0,100);
 select x into item from jsonb_array_elements(r->'items')x where x->>'id'=fixture[6]::text;
 if(item->>'attention_level')::int<>2 or item->>'is_unread'<>'false'then raise exception 'check erased overdue badge';end if;
 count_before:=(r->>'unread_total')::int;
 perform public.cheongla_journal_handover_action(fixture[1],'check',1);
 if(public.cheongla_journal_handovers(today)->>'unread_total')::int<>count_before-1 then raise exception 'per-user unread count incorrect';end if;
 item:=public.cheongla_journal_handover_action(fixture[7],'kind:daily',1);
 revision:=(item->>'revision')::bigint;
 if item->>'handover_kind'<>'daily'then raise exception 'kind not saved';end if;
 begin perform public.cheongla_journal_handover_action(fixture[7],'kind:long',1);raise exception 'stale kind accepted';exception when serialization_failure then null;end;
 item:=public.cheongla_journal_handover_action(fixture[7],'complete',revision);
 r:=public.cheongla_journal_handovers(today,true,0,100);
 select x into item from jsonb_array_elements(r->'items')x where x->>'id'=fixture[7]::text;
 if item->>'attention_level'<>'0'or item->>'is_unread'<>'false'then raise exception 'completed item retains warning';end if;
 begin perform public.cheongla_journal_handover_action(fixture[7],'kind:long',(item->>'revision')::bigint);raise exception 'completed kind editable';exception when raise_exception then if sqlerrm='completed kind editable'then raise;end if;end;
 update public.cheongla_profiles set role='student'where id=auth.uid();
 begin perform public.cheongla_journal_handover_action(fixture[1],'kind:long',1);raise exception 'student category write accepted';exception when insufficient_privilege then null;end;
end;$$;
select 'PASS category boundaries, KST actual-day aging, future not overdue, global unread pagination, independent check/overdue, unread count, kind CAS, completion badges, student denied' as result;
rollback;
