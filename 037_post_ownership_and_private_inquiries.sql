begin;
create or replace function cheongla_private.is_principal() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=auth.uid() and approval_status='approved' and membership_state='active' and role in('owner','english_director','math_director'));
$$;
revoke all on function cheongla_private.is_principal() from public,anon,authenticated;
grant execute on function cheongla_private.is_principal() to authenticated;
grant select(created_by)on public.cheongla_information_posts to authenticated;
drop policy if exists cheongla_notice_delete on public.cheongla_notices;
create policy cheongla_notice_delete on public.cheongla_notices for delete to authenticated using(cheongla_private.can_use_member_services()and(cheongla_private.is_principal()or created_by=auth.uid()));
create or replace function public.cheongla_set_information_deleted(target_post uuid,remove_post boolean,expected_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare p public.cheongla_information_posts%rowtype;
begin
 if not cheongla_private.can_use_member_services()then raise exception '권한이 없습니다.'using errcode='42501';end if;
 select * into p from public.cheongla_information_posts where id=target_post for update;
 if not found or p.updated_at is distinct from expected_updated_at then raise exception '게시물이 변경되었습니다. 새로고침 후 확인해 주세요.';end if;
 if not(cheongla_private.is_principal()or (p.created_by is not distinct from auth.uid()))then raise exception '본인 글만 삭제할 수 있습니다.'using errcode='42501';end if;
 if remove_post is null then raise exception '처리 방법을 선택해 주세요.';end if;
 update public.cheongla_information_posts set deleted_at=case when remove_post then clock_timestamp()else null end,status='draft',updated_at=clock_timestamp()where id=target_post;
end;$$;
alter table public.cheongla_board_posts add column if not exists deleted_at timestamptz;
alter table public.cheongla_new_inquiries add column if not exists deleted_at timestamptz;
create or replace function cheongla_private.can_read_board_post(target_post uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles me
 where me.id=(select auth.uid()) and me.approval_status='approved' and me.membership_state='active')
 and exists(select 1 from public.cheongla_board_posts p where p.id=target_post and p.deleted_at is null
 and (p.visibility='public' or p.author_id=(select auth.uid())
 or cheongla_private.can_manage_consultations()));
$$;
create or replace function public.cheongla_delete_board_post(target_post uuid,expected_updated_at timestamptz)returns uuid language plpgsql security definer set search_path='' as $$
declare p public.cheongla_board_posts%rowtype;
begin
 if not cheongla_private.can_use_member_services()then raise exception '권한이 없습니다.'using errcode='42501';end if;
 select * into p from public.cheongla_board_posts where id=target_post for update;
 if not found or not(cheongla_private.is_principal()or (p.author_id is not distinct from auth.uid()))then raise exception '본인 글만 삭제할 수 있습니다.'using errcode='42501';end if;
 if p.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 새로고침해 주세요.';end if;
 update public.cheongla_board_posts set deleted_at=clock_timestamp(),updated_at=clock_timestamp()where id=target_post;return target_post;
end;$$;
create or replace function public.cheongla_delete_new_inquiry(target_post uuid,expected_updated_at timestamptz)returns void language plpgsql security definer set search_path='' as $$
declare p public.cheongla_new_inquiries%rowtype;
begin
 if not cheongla_private.can_use_member_services()then raise exception '권한이 없습니다.'using errcode='42501';end if;
 select * into p from public.cheongla_new_inquiries where id=target_post for update;
 if not found or not(cheongla_private.is_principal()or (p.author_id is not distinct from auth.uid()))then raise exception '본인 글만 삭제할 수 있습니다.'using errcode='42501';end if;
 if p.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 새로고침해 주세요.';end if;
 update public.cheongla_new_inquiries set deleted_at=clock_timestamp(),updated_at=clock_timestamp()where id=target_post;
end;$$;
create table if not exists cheongla_private.inquiry_pins(kind text not null check(kind in('new','board')),post_id uuid not null,pin_hash text not null,primary key(kind,post_id));
alter table cheongla_private.inquiry_pins enable row level security;
revoke all on cheongla_private.inquiry_pins from public,anon,authenticated;
create or replace function public.cheongla_list_new_inquiries(page_limit integer default 20) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean:=false;result jsonb;max_rows integer;
begin
 if auth.uid() is not null then manager:=cheongla_private.can_manage_consultations();end if;
 max_rows:=greatest(1,least(coalesce(page_limit,20),200));
 select coalesce(jsonb_agg(item order by created_at desc,id desc),'[]'::jsonb) into result
 from (select id,created_at,jsonb_build_object('id',id,'title',title,'body',body,'visibility',visibility,'applicant_role',applicant_role,'created_at',created_at,'updated_at',updated_at,'reply_body',reply_body,'replied_at',replied_at)
 ||case when manager then jsonb_build_object('contact_name',contact_name,'contact_phone',contact_phone,'consultation_status',consultation_status,'status_updated_at',status_updated_at,'review_state',review_state,'risk_flags',risk_flags,'review_reason',review_reason,'author_id',author_id,'blocked',exists(select 1 from cheongla_private.inquiry_blocks b join public.cheongla_new_inquiries q on q.id=b.inquiry_id where b.enabled and (q.visitor_key=cheongla_new_inquiries.visitor_key or q.contact_phone=cheongla_new_inquiries.contact_phone or (q.author_id is not null and q.author_id=cheongla_new_inquiries.author_id)))) else '{}'::jsonb end as item
 from public.cheongla_new_inquiries where deleted_at is null and(manager or (visibility='public' and review_state='published')) order by created_at desc,id desc limit max_rows) p;
 return jsonb_build_object('items',result,'can_manage',manager);
end;$$;
create or replace function public.cheongla_submit_new_inquiry_secure(visitor_token uuid,submission_token uuid,visitor_name text,visitor_phone text,visitor_role text,inquiry_title text,inquiry_body text,inquiry_visibility text,contact_consent boolean,website_field text,private_pin text)
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;
begin
 if inquiry_visibility='private'and coalesce(private_pin,'')!~'^[0-9]{4}$'then raise exception '비밀번호 4자리를 입력해 주세요.';end if;
 id:=public.cheongla_submit_new_inquiry(visitor_token,submission_token,visitor_name,visitor_phone,visitor_role,inquiry_title,inquiry_body,inquiry_visibility,contact_consent,website_field);
 if inquiry_visibility='private'then insert into cheongla_private.inquiry_pins(kind,post_id,pin_hash)values('new',id,extensions.crypt(private_pin,extensions.gen_salt('bf',10)))on conflict do nothing;end if;return id;
end;$$;
create or replace function public.cheongla_save_board_post_secure(target_post uuid,post_title text,post_body text,post_visibility text,expected_updated_at timestamptz,private_pin text)
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;
begin
 if not cheongla_private.can_use_member_services()then raise exception '권한이 없습니다.'using errcode='42501';end if;
 if target_post is not null and not exists(select 1 from public.cheongla_board_posts p where p.id=target_post and p.deleted_at is null and((p.author_id is not distinct from auth.uid())or cheongla_private.is_principal()))then raise exception '글을 수정할 권한이 없습니다.'using errcode='42501';end if;
 if post_visibility='private'and coalesce(private_pin,'')!~'^[0-9]{4}$'then raise exception '비밀번호 4자리를 입력해 주세요.';end if;
 id:=public.cheongla_save_board_post(target_post,post_title,post_body,post_visibility,expected_updated_at);
 if post_visibility='private'then insert into cheongla_private.inquiry_pins(kind,post_id,pin_hash)values('board',id,extensions.crypt(private_pin,extensions.gen_salt('bf',10)))on conflict(kind,post_id)do update set pin_hash=excluded.pin_hash;end if;return id;
end;$$;
revoke all on function public.cheongla_submit_new_inquiry(uuid,uuid,text,text,text,text,text,text,boolean,text),public.cheongla_save_board_post(uuid,text,text,text,timestamptz)from public,anon,authenticated;
revoke all on function public.cheongla_submit_new_inquiry_secure(uuid,uuid,text,text,text,text,text,text,boolean,text,text)from public,anon,authenticated;
grant execute on function public.cheongla_submit_new_inquiry_secure(uuid,uuid,text,text,text,text,text,text,boolean,text,text)to authenticated;
revoke all on function public.cheongla_save_board_post_secure(uuid,text,text,text,timestamptz,text)from public,anon,authenticated;
grant execute on function public.cheongla_save_board_post_secure(uuid,text,text,text,timestamptz,text)to authenticated;
revoke all on function public.cheongla_delete_new_inquiry(uuid,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_delete_new_inquiry(uuid,timestamptz)to authenticated;
grant execute on function public.cheongla_submit_new_inquiry_secure(uuid,uuid,text,text,text,text,text,text,boolean,text,text)to anon;
create or replace function public.cheongla_reply_new_inquiry(target_inquiry uuid,reply_text text,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_stamp timestamptz;
begin
 if not cheongla_private.can_manage_consultations() then raise exception '영어원장·수학원장·실장만 답변할 수 있습니다.' using errcode='42501';end if;
 if reply_text is null or length(btrim(reply_text)) not between 1 and 5000 then raise exception '답변 내용을 확인해 주세요.';end if;
 select updated_at into old_stamp from public.cheongla_new_inquiries where id=target_inquiry and deleted_at is null for update;
 if not found then raise exception '해당 문의가 없습니다.';end if;
 if old_stamp is distinct from expected_updated_at then raise exception '문의가 변경되었습니다. 새로고침 후 다시 답변해 주세요.';end if;
 update public.cheongla_new_inquiries set reply_body=btrim(reply_text),replied_by=(select auth.uid()),replied_at=clock_timestamp(),updated_at=clock_timestamp()
 where id=target_inquiry;return target_inquiry;
end;$$;
create or replace function public.cheongla_review_new_inquiry(target_inquiry uuid,review_action text,action_reason text,expected_updated_at timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare q public.cheongla_new_inquiries%rowtype;
begin
 if not cheongla_private.can_manage_consultations() then raise exception '원장·실장만 신규 문의를 검토할 수 있습니다.' using errcode='42501';end if;
 if review_action is null or review_action not in ('publish','hide','pending','block','unblock') or action_reason is null or length(action_reason)>1000 then raise exception '검토 처리 내용을 확인해 주세요.';end if;
 if review_action in ('hide','block') and length(btrim(action_reason))<2 then raise exception '숨김·차단 사유를 입력해 주세요.';end if;
 perform pg_catalog.pg_advisory_xact_lock(7492053);
 select * into q from public.cheongla_new_inquiries where id=target_inquiry and deleted_at is null for update;
 if not found then raise exception '해당 문의가 없습니다.';end if;
 if q.updated_at is distinct from expected_updated_at then raise exception '문의가 변경되었습니다. 새로고침해 주세요.';end if;
 if review_action='publish' and q.visibility<>'public' then raise exception '비공개 문의는 공개 게시할 수 없습니다.';end if;
 if review_action='publish' and exists(select 1 from cheongla_private.inquiry_blocks b join public.cheongla_new_inquiries x on x.id=b.inquiry_id where b.enabled and (x.visitor_key=q.visitor_key or x.contact_phone=q.contact_phone or (x.author_id is not null and x.author_id=q.author_id))) then raise exception '차단된 작성자의 문의는 공개할 수 없습니다.';end if;
 if review_action='block' then
  insert into cheongla_private.inquiry_blocks(inquiry_id,blocked_by,reason) values(q.id,(select auth.uid()),btrim(action_reason)) on conflict(inquiry_id) do update set enabled=true,blocked_by=excluded.blocked_by,reason=excluded.reason,created_at=clock_timestamp();
  update public.cheongla_new_inquiries set review_state='hidden',review_reason=btrim(action_reason),reviewed_by=(select auth.uid()),reviewed_at=clock_timestamp(),updated_at=clock_timestamp() where visitor_key=q.visitor_key or contact_phone=q.contact_phone or (author_id is not null and author_id=q.author_id);
 elsif review_action='unblock' then
  update cheongla_private.inquiry_blocks b set enabled=false from public.cheongla_new_inquiries x where x.id=b.inquiry_id and (x.visitor_key=q.visitor_key or x.contact_phone=q.contact_phone or (x.author_id is not null and x.author_id=q.author_id));
  update public.cheongla_new_inquiries set updated_at=clock_timestamp() where id=q.id;
 else
  update public.cheongla_new_inquiries set review_state=case review_action when 'publish' then 'published' when 'hide' then 'hidden' else 'pending' end,review_reason=btrim(action_reason),reviewed_by=(select auth.uid()),reviewed_at=clock_timestamp(),updated_at=clock_timestamp() where id=q.id;
 end if;
 return q.id;
end;$$;
alter table public.cheongla_board_replies add column if not exists deleted_at timestamptz;
drop policy if exists cheongla_board_reply_read on public.cheongla_board_replies;
create policy cheongla_board_reply_read on public.cheongla_board_replies for select to authenticated using(deleted_at is null and cheongla_private.can_read_board_post(post_id));
create or replace function public.cheongla_delete_board_reply(target_reply uuid)returns void language plpgsql security definer set search_path='' as $$
declare r public.cheongla_board_replies%rowtype;
begin
 if not cheongla_private.can_use_member_services()then raise exception '권한이 없습니다.'using errcode='42501';end if;
 select * into r from public.cheongla_board_replies where id=target_reply for update;
 if not found or not(cheongla_private.is_principal()or (r.author_id is not distinct from auth.uid()))then raise exception '본인 글만 삭제할 수 있습니다.'using errcode='42501';end if;
 update public.cheongla_board_replies set deleted_at=clock_timestamp()where id=target_reply;
end;$$;
revoke all on function public.cheongla_delete_board_reply(uuid)from public,anon,authenticated;
grant execute on function public.cheongla_delete_board_reply(uuid)to authenticated;
notify pgrst,'reload schema';
commit;
