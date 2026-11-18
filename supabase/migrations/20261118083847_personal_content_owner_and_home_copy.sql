-- Use the existing immutable owner binding, never an editable display name or role alone.
create function cheongla_private.can_manage_app_content()returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.can_manage_season();
$$;
revoke all on function cheongla_private.can_manage_app_content() from public,anon;
grant execute on function cheongla_private.can_manage_app_content() to authenticated;
create function public.cheongla_can_manage_app_content()returns boolean language sql stable security definer set search_path='' as $$select cheongla_private.can_manage_app_content();$$;
revoke all on function public.cheongla_can_manage_app_content() from public,anon;
grant execute on function public.cheongla_can_manage_app_content() to authenticated;
create function cheongla_private.can_manage_shared_content()returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.can_manage_app_content() or exists(select 1 from public.cheongla_profiles where id=auth.uid()and role='manager'and approval_status='approved'and membership_state='active');
$$;
revoke all on function cheongla_private.can_manage_shared_content() from public,anon;
grant execute on function cheongla_private.can_manage_shared_content() to authenticated;
create or replace function cheongla_private.can_manage_home_features()returns boolean language sql stable security definer set search_path='' as $$select cheongla_private.can_manage_app_content();$$;
create or replace function cheongla_private.can_manage_mbti_operations()returns boolean language sql stable security definer set search_path='' as $$select cheongla_private.can_manage_app_content();$$;
-- Keep desk notices and all staff operational helpers unchanged.
do $$declare source text;begin
 select prosrc into source from pg_proc where oid='cheongla_private.can_manage_notice_channel(text)'::regprocedure;
 execute replace(pg_get_functiondef('cheongla_private.can_manage_notice_channel(text)'::regprocedure),source,
 'select case when target_channel=''director''then cheongla_private.can_manage_app_content()else ('||regexp_replace(source,';[[:space:]]*$','')||')end;');
end;$$;
-- Change only content-specific functions; never the shared is_principal()/can_manage_life().
do $$declare f record;begin
 for f in select p.oid,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and
 (p.proname like 'cheongla_intro_%'or p.proname like '%director%'or p.proname in('cheongla_save_daily_word','cheongla_english_answer_key','cheongla_add_english_synonym'))
 and p.prosrc like '%cheongla_private.is_principal()%'loop
 execute replace(pg_get_functiondef(f.oid),'cheongla_private.is_principal()','cheongla_private.can_manage_app_content()');
 end loop;
 -- Preserve existing staff news/resource work while restricting other principal accounts.
 for f in select p.oid,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and
 p.proname in('cheongla_prepare_information','cheongla_save_information','cheongla_stage_information_file','cheongla_finish_information_file','cheongla_remove_information_file','cheongla_reserve_information_file','cheongla_set_information_deleted','cheongla_prepare_content_purge')loop
 execute replace(pg_get_functiondef(f.oid),f.prosrc,regexp_replace(f.prosrc,'\mbegin\M',E'begin\n if not cheongla_private.can_manage_shared_content()then raise insufficient_privilege;end if;','i'));
 end loop;
end;$$;
-- Preserve existing policy roles/types while replacing broad principal gates on content.
do $$declare p record;u text;c text;statement text;begin
 for p in select *from pg_policies where (schemaname='public'and tablename in('cheongla_daily_words','cheongla_dictionary_overrides','cheongla_director_posts','cheongla_director_files'))
 or(schemaname='storage'and(coalesce(qual,'')||coalesce(with_check,''))~'cheongla-(intro|director)')loop
 u:=replace(p.qual,'cheongla_private.is_principal()','cheongla_private.can_manage_app_content()');c:=replace(p.with_check,'cheongla_private.is_principal()','cheongla_private.can_manage_app_content()');
 if u is distinct from p.qual or c is distinct from p.with_check then
 statement:=format('alter policy %I on %I.%I',p.policyname,p.schemaname,p.tablename);
 if u is not null then statement:=statement||' using('||u||')';end if;
 if c is not null then statement:=statement||' with check('||c||')';end if;execute statement;
 end if;end loop;
end;$$;
-- Additional restrictions protect direct REST writes even when a permissive policy is broad.
do $$declare t text;begin
 foreach t in array array['cheongla_winter_promotions']loop
 execute format('create policy personal_content_insert on public.%I as restrictive for insert to authenticated with check(cheongla_private.can_manage_app_content())',t);
 execute format('create policy personal_content_update on public.%I as restrictive for update to authenticated using(cheongla_private.can_manage_app_content())with check(cheongla_private.can_manage_app_content())',t);
 execute format('create policy personal_content_delete on public.%I as restrictive for delete to authenticated using(cheongla_private.can_manage_app_content())',t);
 end loop;
end;$$;
create policy personal_notice_delete on public.cheongla_notices as restrictive for delete to authenticated using(cheongla_private.can_manage_notice_channel(channel));

-- Recycled director notices remain personal-owner content; desk operations stay shared.
create function cheongla_private.can_manage_recycled_content(kind text,target uuid)returns boolean language plpgsql stable security definer set search_path='' as $$
declare channel text;
begin
 if kind='notice'then
  select coalesce(row_data->>'channel','director')into channel from cheongla_private.content_recycle where id=target and content_recycle.kind='notice';
  return coalesce(cheongla_private.can_manage_notice_channel(channel),false);
 elsif kind='information'then return cheongla_private.can_manage_shared_content();
 else return cheongla_private.can_manage_life();end if;
end;$$;
revoke all on function cheongla_private.can_manage_recycled_content(text,uuid) from public,anon;
grant execute on function cheongla_private.can_manage_recycled_content(text,uuid)to authenticated;
do $$declare f record;body text;begin
 for f in select p.oid,p.proname,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.proname in('cheongla_content_trash_action','cheongla_content_trash_action_v71','cheongla_prepare_notice_purge','cheongla_content_trash_v71')loop
 if f.proname='cheongla_content_trash_v71'then
 body:=replace(f.prosrc,'return result;',E'return(select coalesce(jsonb_agg(x),\'[]\'::jsonb)from jsonb_array_elements(result)x where cheongla_private.can_manage_recycled_content(x->>\'kind\',(x->>\'id\')::uuid));');
 elsif f.proname='cheongla_prepare_notice_purge'then
 body:=regexp_replace(f.prosrc,'\mbegin\M',E'begin\n if not cheongla_private.can_manage_recycled_content(\'notice\',target_id)then raise insufficient_privilege;end if;','i');
 else
 body:=regexp_replace(f.prosrc,'\mbegin\M',E'begin\n if not cheongla_private.can_manage_recycled_content(target_kind,target_id)then raise insufficient_privilege;end if;','i');end if;
 execute replace(pg_get_functiondef(f.oid),f.prosrc,body);
 end loop;
end;$$;
create policy personal_content_storage_insert on storage.objects as restrictive for insert to authenticated with check(bucket_id not in('cheongla-intro','cheongla-director','cheongla-home-videos')or cheongla_private.can_manage_app_content());
create policy personal_content_storage_update on storage.objects as restrictive for update to authenticated using(bucket_id not in('cheongla-intro','cheongla-director','cheongla-home-videos')or cheongla_private.can_manage_app_content())with check(bucket_id not in('cheongla-intro','cheongla-director','cheongla-home-videos')or cheongla_private.can_manage_app_content());
create policy personal_content_storage_delete on storage.objects as restrictive for delete to authenticated using(bucket_id not in('cheongla-intro','cheongla-director','cheongla-home-videos')or cheongla_private.can_manage_app_content());
alter table cheongla_private.intro_pages drop constraint intro_pages_page_key_check;
alter table cheongla_private.intro_pages add constraint intro_pages_page_key_check check(page_key in('greeting','identity','results','photos','rules','daily_timetable','home_message','home_services','official_contacts'));
notify pgrst,'reload schema';

-- Existing public home wording; no private records or generated profile IDs.
insert into cheongla_private.intro_pages(page_key,payload)values('home_message','{"title": "담장 너머,\n더 넓은 세상으로.", "kicker": "독학재수학원 청라", "paragraphs": ["학생의 하루를 함께 살피고,\n스스로 공부하는 힘을 기릅니다."]}'::jsonb)on conflict(page_key)do nothing;
insert into cheongla_private.intro_pages(page_key,payload)values('home_services','{"title": "청라에서 함께하는 일", "items": [{"title": "자기주도학습", "body": "자신에게 맞는 공부 방식과 꾸준한 학습 습관"}, {"title": "상담문의", "body": "학원 이용과 학습에 관한 문의를 남겨 주세요"}, {"title": "생활 · 학습 · 입시 상담", "body": "목표를 세우고 계획을 점검하는 과정"}]}'::jsonb)on conflict(page_key)do nothing;
insert into cheongla_private.intro_pages(page_key,payload)values('official_contacts','{"title": "청라 문의 · 공식 채널", "items": [{"title": "학원 상담 전화하기", "detail": "010-8664-2052", "href": "tel:01086642052", "symbol": "☎", "hours": "상담 가능 시간: 오전 8시~오후 11시", "logo": "", "helper": ""}, {"title": "학원 상담 문자 보내기", "detail": "010-8664-2052", "href": "sms:01086642052", "symbol": "문자", "hours": "상담 가능 시간: 오전 8시~오후 11시", "logo": "", "helper": "학생 이름·학년과 문의 내용을 적어주세요."}, {"title": "청라 공식 인스타그램", "detail": "@cheongla_edu", "href": "https://www.instagram.com/cheongla_edu/", "symbol": "", "logo": "assets/instagram-logo.png", "hours": "", "helper": ""}, {"title": "청라 공식 블로그", "detail": "cheongla2020", "href": "https://blog.naver.com/cheongla2020", "symbol": "", "logo": "assets/naver-blog-logo.png", "hours": "", "helper": ""}]}'::jsonb)on conflict(page_key)do nothing;
