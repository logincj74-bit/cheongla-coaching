begin;
create or replace function cheongla_private.can_manage_consultations()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and approval_status='approved' and role in ('owner','english_director','math_director','manager'));
$$;
revoke all on function cheongla_private.can_manage_consultations() from public,anon,authenticated;
grant execute on function cheongla_private.can_manage_consultations() to authenticated;
create table if not exists public.cheongla_new_inquiries(
 id uuid primary key default gen_random_uuid(),
 visitor_key uuid not null,
 submission_key uuid not null unique,
 contact_name text not null check(length(btrim(contact_name)) between 1 and 60),
 contact_phone text not null check(contact_phone ~ '^0[0-9]{8,10}$'),
 applicant_role text not null check(applicant_role in ('student','parent')),
 title text not null check(length(btrim(title)) between 1 and 150),
 body text not null check(length(btrim(body)) between 1 and 5000),
 visibility text not null default 'private' check(visibility in ('public','private')),
 reply_body text not null default '' check(length(reply_body)<=5000),
 replied_by uuid references public.cheongla_profiles(id),
 replied_at timestamptz,
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp()
);
create index if not exists cheongla_new_inquiry_order on public.cheongla_new_inquiries(created_at desc,id desc);
create index if not exists cheongla_new_inquiry_rate on public.cheongla_new_inquiries(visitor_key,created_at desc);
alter table public.cheongla_new_inquiries enable row level security;
revoke all on public.cheongla_new_inquiries from public,anon,authenticated;
grant select on public.cheongla_new_inquiries to authenticated;
drop policy if exists cheongla_new_inquiry_admin_read on public.cheongla_new_inquiries;
create policy cheongla_new_inquiry_admin_read on public.cheongla_new_inquiries for select to authenticated
 using ((select cheongla_private.can_manage_consultations()));
create or replace function public.cheongla_submit_new_inquiry(
 visitor_token uuid,submission_token uuid,visitor_name text,visitor_phone text,visitor_role text,
 inquiry_title text,inquiry_body text,inquiry_visibility text,contact_consent boolean,website_field text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;phone text;
begin
 if visitor_token is null or submission_token is null or contact_consent is distinct from true
 or coalesce(website_field,'')<>'' then raise exception '상담 정보와 연락처 이용 동의를 확인해 주세요.';end if;
 phone:=regexp_replace(coalesce(visitor_phone,''),'[^0-9]','','g');
 if visitor_name is null or length(btrim(visitor_name)) not between 1 and 60
 or phone !~ '^0[0-9]{8,10}$' or visitor_role is null or visitor_role not in ('student','parent')
 or inquiry_title is null or length(btrim(inquiry_title)) not between 1 and 150
 or inquiry_body is null or length(btrim(inquiry_body)) not between 1 and 5000
 or inquiry_visibility is null or inquiry_visibility not in ('public','private') then
 raise exception '이름, 전화번호, 제목, 내용과 공개 여부를 확인해 주세요.';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(visitor_token::text,0));
 select id into result_id from public.cheongla_new_inquiries where submission_key=submission_token and visitor_key=visitor_token;
 if found then return result_id;end if;
 if exists(select 1 from public.cheongla_new_inquiries where visitor_key=visitor_token and created_at>clock_timestamp()-interval '30 seconds') then
 raise exception '잠시 기다린 뒤 문의를 등록해 주세요.';end if;
 insert into public.cheongla_new_inquiries(visitor_key,submission_key,contact_name,contact_phone,applicant_role,title,body,visibility)
 values(visitor_token,submission_token,btrim(visitor_name),phone,visitor_role,btrim(inquiry_title),btrim(inquiry_body),inquiry_visibility)
 returning id into result_id;return result_id;
end;$$;
create or replace function public.cheongla_list_new_inquiries(page_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean:=false;result jsonb;max_rows integer;
begin
 if auth.uid() is not null then manager:=cheongla_private.can_manage_consultations();end if;
 max_rows:=greatest(1,least(coalesce(page_limit,20),200));
 select coalesce(jsonb_agg(item order by created_at desc,id desc),'[]'::jsonb) into result
 from (select id,created_at,jsonb_build_object('id',id,'title',title,'body',body,'visibility',visibility,
 'applicant_role',applicant_role,'created_at',created_at,'updated_at',updated_at,'reply_body',reply_body,'replied_at',replied_at)
 ||case when manager then jsonb_build_object('contact_name',contact_name,'contact_phone',contact_phone) else '{}'::jsonb end as item
 from public.cheongla_new_inquiries where manager or visibility='public' order by created_at desc,id desc limit max_rows) p;
 return jsonb_build_object('items',result,'can_manage',manager);
end;$$;
create or replace function public.cheongla_reply_new_inquiry(target_inquiry uuid,reply_text text,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_stamp timestamptz;
begin
 if not cheongla_private.can_manage_consultations() then raise exception '영어원장·수학원장·실장만 답변할 수 있습니다.' using errcode='42501';end if;
 if reply_text is null or length(btrim(reply_text)) not between 1 and 5000 then raise exception '답변 내용을 확인해 주세요.';end if;
 select updated_at into old_stamp from public.cheongla_new_inquiries where id=target_inquiry for update;
 if not found then raise exception '해당 문의가 없습니다.';end if;
 if old_stamp is distinct from expected_updated_at then raise exception '문의가 변경되었습니다. 새로고침 후 다시 답변해 주세요.';end if;
 update public.cheongla_new_inquiries set reply_body=btrim(reply_text),replied_by=(select auth.uid()),replied_at=clock_timestamp(),updated_at=clock_timestamp()
 where id=target_inquiry;return target_inquiry;
end;$$;
revoke all on function public.cheongla_submit_new_inquiry(uuid,uuid,text,text,text,text,text,text,boolean,text),public.cheongla_list_new_inquiries(integer),public.cheongla_reply_new_inquiry(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_submit_new_inquiry(uuid,uuid,text,text,text,text,text,text,boolean,text),public.cheongla_list_new_inquiries(integer) to anon,authenticated;
grant execute on function public.cheongla_reply_new_inquiry(uuid,text,timestamptz) to authenticated;
create or replace function cheongla_private.can_read_board_post(target_post uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles me
 where me.id=(select auth.uid()) and me.approval_status='approved')
 and exists(select 1 from public.cheongla_board_posts p where p.id=target_post
 and (p.visibility='public' or p.author_id=(select auth.uid())
 or cheongla_private.can_manage_consultations()));
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
  if not found or not (old.author_id=me.id or cheongla_private.can_manage_consultations()) then
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
 if not (cheongla_private.can_manage_consultations() or me.id=post_author) then
  raise exception '관리자 답변과 작성자 추가 질문만 등록할 수 있습니다.' using errcode='42501';end if;
 if reply_body is null or length(btrim(reply_body)) not between 1 and 10000 then raise exception '답변 내용을 확인해 주세요.';end if;
 insert into public.cheongla_board_replies(post_id,author_id,author_name,is_admin_reply,body)
 values(target_post,me.id,me.full_name,cheongla_private.can_manage_consultations(),btrim(reply_body)) returning id into result_id;
 return result_id;
end;$$;
create or replace function public.cheongla_delete_board_post(target_post uuid,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;old public.cheongla_board_posts%rowtype;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved';
 if not found then raise exception '승인된 계정으로 이용해 주세요.' using errcode='42501';end if;
 select * into old from public.cheongla_board_posts where id=target_post for update;
 if not found or not (old.author_id=me.id or cheongla_private.can_manage_consultations()) then
 raise exception '글을 삭제할 권한이 없습니다.' using errcode='42501';end if;
 if old.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 다시 확인해 주세요.';end if;
 delete from public.cheongla_board_posts where id=target_post;return target_post;
end;$$;
revoke all on function public.cheongla_save_board_post(uuid,text,text,text,timestamptz),public.cheongla_add_board_reply(uuid,text),public.cheongla_delete_board_post(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_save_board_post(uuid,text,text,text,timestamptz),public.cheongla_add_board_reply(uuid,text),public.cheongla_delete_board_post(uuid,timestamptz) to authenticated;

notify pgrst,'reload schema';
commit;
