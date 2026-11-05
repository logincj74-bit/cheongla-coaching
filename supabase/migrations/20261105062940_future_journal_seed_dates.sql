create or replace function cheongla_private.seed_daily_journal(day date)returns void language plpgsql security definer set search_path='' as $$
declare j record;c record;k text;t text;fields jsonb:='{"duty":"","special":"","handover":""}';inks jsonb:='{"duty":[],"special":[],"handover":[]}';part jsonb;closed uuid[]:='{}';
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 이용할 수 있습니다.'using errcode='42501';end if;
 if day is null or day<'2020-01-01'or day>'2099-12-31' then raise exception '근무 날짜를 확인해 주세요.';end if;
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
