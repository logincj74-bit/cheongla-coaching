-- Principal-written daily encouragement, through the 2027 CSAT on 2026-11-19.
create table public.cheongla_daily_words (
 id uuid primary key default gen_random_uuid(),
 message_on date not null unique check (message_on <= date '2026-11-19'),
 title text not null default '' check (char_length(title) <= 120),
 body text not null check (char_length(btrim(body)) between 1 and 6000),
 status text not null default 'draft' check (status in ('draft','published')),
 created_by uuid references public.cheongla_profiles(id) on delete set null,
 updated_by uuid references public.cheongla_profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.cheongla_daily_words enable row level security;
revoke all on public.cheongla_daily_words from public,anon,authenticated;
grant select on public.cheongla_daily_words to anon,authenticated;
grant insert,update on public.cheongla_daily_words to authenticated;
create policy daily_word_public_read on public.cheongla_daily_words for select to anon,authenticated
 using (status='published' and message_on <= (now() at time zone 'Asia/Seoul')::date);
create policy daily_word_principal_read on public.cheongla_daily_words for select to authenticated
 using ((select cheongla_private.is_principal()));
create policy daily_word_principal_insert on public.cheongla_daily_words for insert to authenticated
 with check ((select cheongla_private.is_principal()));
create policy daily_word_principal_update on public.cheongla_daily_words for update to authenticated
 using ((select cheongla_private.is_principal())) with check ((select cheongla_private.is_principal()));

create function cheongla_private.stamp_daily_word() returns trigger language plpgsql set search_path='' as $$
begin
 new.title=btrim(new.title);new.body=btrim(new.body);
 if new.message_on > (now() at time zone 'Asia/Seoul')::date then
  raise exception '미래 날짜의 글은 아직 저장할 수 없습니다.' using errcode='22023';
 end if;
 if tg_op='INSERT' then new.created_by=auth.uid();new.created_at=clock_timestamp();
 else new.id=old.id;new.created_by=old.created_by;new.created_at=old.created_at;end if;
 new.updated_by=auth.uid();new.updated_at=clock_timestamp();return new;
end;$$;
revoke all on function cheongla_private.stamp_daily_word() from public,anon,authenticated;
create trigger stamp_daily_word before insert or update on public.cheongla_daily_words for each row execute function cheongla_private.stamp_daily_word();

create function public.cheongla_save_daily_word(target_day date,post_title text,post_body text,post_status text,expected_updated_at timestamptz default null)
 returns jsonb language plpgsql set search_path='' as $$
declare old_row public.cheongla_daily_words%rowtype; saved public.cheongla_daily_words%rowtype;
begin
 if not cheongla_private.is_principal() then raise exception '원장 계정만 글을 작성하고 수정할 수 있습니다.' using errcode='42501';end if;
 if target_day is null or target_day > date '2026-11-19' or target_day > (now() at time zone 'Asia/Seoul')::date then
  raise exception '게시일은 오늘까지, 수능일(2026-11-19) 이내로 선택해 주세요.' using errcode='22023';end if;
 if post_status is null or post_status not in ('draft','published') or post_body is null or char_length(btrim(post_body)) not between 1 and 6000 or char_length(coalesce(post_title,''))>120 then
  raise exception '본문은 1~6,000자, 제목은 120자 이내로 입력해 주세요.' using errcode='22023';end if;
 select * into old_row from public.cheongla_daily_words where message_on=target_day for update;
 if found then
  if expected_updated_at is null or old_row.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 새로고침한 뒤 다시 수정해 주세요.' using errcode='40001';end if;
  update public.cheongla_daily_words set title=coalesce(post_title,''),body=post_body,status=post_status where id=old_row.id returning * into saved;
 else
  if expected_updated_at is not null then raise exception '수정할 글을 다시 확인해 주세요.' using errcode='40001';end if;
  insert into public.cheongla_daily_words(message_on,title,body,status) values(target_day,coalesce(post_title,''),post_body,post_status) returning * into saved;
 end if;
 return to_jsonb(saved);
exception when unique_violation then raise exception '이 날짜의 글이 이미 저장되었습니다. 새로고침 후 수정해 주세요.' using errcode='40001';
end;$$;
revoke all on function public.cheongla_save_daily_word(date,text,text,text,timestamptz) from public,anon;
grant execute on function public.cheongla_save_daily_word(date,text,text,text,timestamptz) to authenticated;

-- Preserve existing notification authorization and add this public board source.
do $patch$
declare definition text;
begin
 select pg_get_functiondef('cheongla_private.can_read_notification(text,uuid,uuid)'::regprocedure) into definition;
 if position('if kind=''daily_word''' in definition)=0 then
  if position(' if kind=''information''' in definition)=0 then raise exception 'Notification authorization anchor changed';end if;
  definition=replace(definition,' if kind=''information''',E' if kind=''daily_word'' then return exists(select 1 from public.cheongla_daily_words where id=target and status=''published'' and message_on <= (now() at time zone ''Asia/Seoul'')::date);end if;\n if kind=''information''');
  execute definition;
 end if;
end;$patch$;
create function cheongla_private.notify_daily_word() returns trigger language plpgsql security definer set search_path='' as $$
declare people uuid[];
begin
 if new.status<>'published' then return new;end if;
 if tg_op='UPDATE' and old.status='published' and old.title=new.title and old.body=new.body and old.message_on=new.message_on then return new;end if;
 select array_agg(id) into people from public.cheongla_profiles where approval_status='approved' and membership_state='active';
 perform cheongla_private.send_notification(people,'daily_word',new.id,null,'청라, 오늘의 한마디 · '||to_char(new.message_on,'MM.DD')||case when new.title<>'' then ' · '||left(new.title,65) else '' end,'daily_word','daily-word-'||new.id::text||'-'||new.updated_at::text);
 return new;
end;$$;
revoke all on function cheongla_private.notify_daily_word() from public,anon,authenticated;
create trigger notify_daily_word after insert or update on public.cheongla_daily_words for each row execute function cheongla_private.notify_daily_word();
notify pgrst,'reload schema';
