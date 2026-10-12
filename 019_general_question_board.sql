begin;
-- 성인재 수학원장에게 기존 영어원장과 동일한 앱 관리자 권한을 부여합니다.
do $$
begin
 if (select count(*) from public.cheongla_profiles
 where btrim(full_name)='성인재' and role='math_director'
 and approval_status='approved')<>1 then
  raise exception '승인된 성인재 수학원장 계정이 정확히 한 명인지 확인해 주세요.';
 end if;
 update public.cheongla_profiles set is_app_admin=true
 where btrim(full_name)='성인재' and role='math_director'
 and approval_status='approved';
end;$$;
create table if not exists public.cheongla_board_posts(
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.cheongla_profiles(id) on delete cascade,
 author_name text not null,
 title text not null check(length(btrim(title)) between 1 and 150),
 body text not null check(length(btrim(body)) between 1 and 10000),
 visibility text not null check(visibility in ('public','private')),
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp()
);
create table if not exists public.cheongla_board_replies(
 id uuid primary key default gen_random_uuid(),
 post_id uuid not null references public.cheongla_board_posts(id) on delete cascade,
 author_id uuid not null references public.cheongla_profiles(id) on delete cascade,
 author_name text not null,
 is_admin_reply boolean not null,
 body text not null check(length(btrim(body)) between 1 and 10000),
 created_at timestamptz not null default clock_timestamp()
);
create index if not exists cheongla_board_order on public.cheongla_board_posts(created_at desc,id desc);
create index if not exists cheongla_board_reply_order on public.cheongla_board_replies(post_id,created_at,id);
create or replace function cheongla_private.can_read_board_post(target_post uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles me
 where me.id=(select auth.uid()) and me.approval_status='approved')
 and exists(select 1 from public.cheongla_board_posts p where p.id=target_post
 and (p.visibility='public' or p.author_id=(select auth.uid())
 or cheongla_private.is_app_admin()));
$$;
revoke all on function cheongla_private.can_read_board_post(uuid) from public,anon,authenticated;
grant execute on function cheongla_private.can_read_board_post(uuid) to authenticated;
alter table public.cheongla_board_posts enable row level security;
alter table public.cheongla_board_replies enable row level security;
revoke all on public.cheongla_board_posts,public.cheongla_board_replies from public,anon,authenticated;
grant select on public.cheongla_board_posts,public.cheongla_board_replies to authenticated;
drop policy if exists cheongla_board_post_read on public.cheongla_board_posts;
create policy cheongla_board_post_read on public.cheongla_board_posts for select to authenticated
using ((select cheongla_private.can_read_board_post(id)));
drop policy if exists cheongla_board_reply_read on public.cheongla_board_replies;
create policy cheongla_board_reply_read on public.cheongla_board_replies for select to authenticated
using ((select cheongla_private.can_read_board_post(post_id)));
create or replace function public.cheongla_save_board_post(
 target_post uuid,post_title text,post_body text,post_visibility text,
 expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;old public.cheongla_board_posts%rowtype;result_id uuid;
begin
 select * into me from public.cheongla_profiles
 where id=(select auth.uid()) and approval_status='approved';
 if not found then raise exception '승인된 계정으로 이용해 주세요.' using errcode='42501';end if;
 if post_title is null or length(btrim(post_title)) not between 1 and 150
 or post_body is null or length(btrim(post_body)) not between 1 and 10000
 or post_visibility is null or post_visibility not in ('public','private') then
 raise exception '제목, 내용과 공개 여부를 확인해 주세요.';end if;
 if target_post is null then
  if expected_updated_at is not null then raise exception '새 글의 저장 정보를 확인해 주세요.';end if;
  insert into public.cheongla_board_posts(author_id,author_name,title,body,visibility)
  values(me.id,me.full_name,btrim(post_title),btrim(post_body),post_visibility) returning id into result_id;
 else
  select * into old from public.cheongla_board_posts where id=target_post for update;
  if not found or not (old.author_id=me.id or me.is_app_admin) then
   raise exception '글을 수정할 권한이 없습니다.' using errcode='42501';end if;
  if old.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 다시 확인해 주세요.';end if;
  update public.cheongla_board_posts set title=btrim(post_title),body=btrim(post_body),
  visibility=post_visibility,updated_at=clock_timestamp() where id=target_post returning id into result_id;
 end if;
 return result_id;
end;$$;
create or replace function public.cheongla_add_board_reply(target_post uuid,reply_body text)
returns uuid language plpgsql security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;post_author uuid;result_id uuid;
begin
 if not cheongla_private.can_read_board_post(target_post) then
  raise exception '질문을 확인할 권한이 없습니다.' using errcode='42501';end if;
 select * into me from public.cheongla_profiles where id=(select auth.uid());
 select author_id into post_author from public.cheongla_board_posts where id=target_post;
 if not (me.is_app_admin or me.id=post_author) then
  raise exception '관리자 답변과 작성자 추가 질문만 등록할 수 있습니다.' using errcode='42501';end if;
 if reply_body is null or length(btrim(reply_body)) not between 1 and 10000 then raise exception '답변 내용을 확인해 주세요.';end if;
 insert into public.cheongla_board_replies(post_id,author_id,author_name,is_admin_reply,body)
 values(target_post,me.id,me.full_name,me.is_app_admin,btrim(reply_body)) returning id into result_id;
 return result_id;
end;$$;
create or replace function public.cheongla_delete_board_post(target_post uuid,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;old public.cheongla_board_posts%rowtype;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved';
 if not found then raise exception '승인된 계정으로 이용해 주세요.' using errcode='42501';end if;
 select * into old from public.cheongla_board_posts where id=target_post for update;
 if not found or not (old.author_id=me.id or me.is_app_admin) then
 raise exception '글을 삭제할 권한이 없습니다.' using errcode='42501';end if;
 if old.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 다시 확인해 주세요.';end if;
 delete from public.cheongla_board_posts where id=target_post;return target_post;
end;$$;
revoke all on function public.cheongla_save_board_post(uuid,text,text,text,timestamptz),public.cheongla_add_board_reply(uuid,text),public.cheongla_delete_board_post(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_save_board_post(uuid,text,text,text,timestamptz),public.cheongla_add_board_reply(uuid,text),public.cheongla_delete_board_post(uuid,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
