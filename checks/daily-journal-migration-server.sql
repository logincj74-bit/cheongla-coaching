begin;
do $$
declare actor uuid:=gen_random_uuid();other_author uuid:=gen_random_uuid();j uuid:=gen_random_uuid();j2 uuid:=gen_random_uuid();day date:='2020-02-01';r jsonb;v timestamptz;
begin
 insert into auth.users(id,email,raw_user_meta_data)values(actor,'journal-import-'||actor||'@example.invalid','{"full_name":"이전일지검증","contact_phone":"01000000994"}');
 update public.cheongla_profiles set role='english_director',is_app_admin=true,approval_status='approved'where id=actor;
 insert into auth.users(id,email,raw_user_meta_data)values(other_author,'journal-import-'||other_author||'@example.invalid','{"full_name":"복구검증실장","contact_phone":"01000000994"}');
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into cheongla_private.staff_journals(id,work_on,author_id,updated_by,duty,ink_color,field_inks)values(j,day,actor,actor,'빨간 원문','red','{"duty":[{"text":"빨간 원문","ink":"red"}],"special":[],"handover":[]}');
 insert into cheongla_private.staff_journal_comments(id,journal_id,author_id,body,ink_color,field_key,ink_runs)values(gen_random_uuid(),j,actor,'녹색 답변','green','duty','[{"text":"녹색 답변","ink":"green"}]');
 insert into cheongla_private.staff_journals(id,work_on,author_id,updated_by,duty,ink_color,archived_at)values(j2,day,other_author,actor,'휴지통의 파란 글','blue',clock_timestamp());
 r:=public.cheongla_daily_journal_get(day);assert r->'fields'->>'duty'='빨간 원문'||E'\n'||'녹색 답변','old comments not in shared document';assert cheongla_private.valid_journal_inks(r->'field_inks'->'duty',r->'fields'->>'duty'),'migration colour mismatch';
 begin update cheongla_private.staff_journals set duty='구버전 변경'where id=j;raise exception 'old tab wrote stale document';exception when serialization_failure then null;end;
 begin insert into cheongla_private.staff_journal_comments(id,journal_id,author_id,body,ink_color,field_key)values(gen_random_uuid(),j,actor,'구버전 답변','green','duty');raise exception 'old comment wrote stale document';exception when serialization_failure then null;end;
 select updated_at into v from cheongla_private.staff_journals where id=j2;
 perform public.cheongla_staff_journal_action(j2,'restore',v);
 r:=public.cheongla_daily_journal_get(day);assert r->'fields'->>'duty'like '%휴지통의 파란 글','restored legacy text missing';assert cheongla_private.valid_journal_inks(r->'field_inks'->'duty',r->'fields'->>'duty'),'restored colour mismatch';
 assert(select count(*)=2 from cheongla_private.staff_journals where work_on=day),'old originals removed during migration';
end $$;
rollback;
select 'PASS: legacy text/replies/colours migrated, originals preserved, old-tab writes rejected, legacy trash restoration appended with colours; rolled back' as result;
