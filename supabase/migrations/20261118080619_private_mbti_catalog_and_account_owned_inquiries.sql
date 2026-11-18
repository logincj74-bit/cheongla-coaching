-- Document content is provisioned privately and must never be embedded in this file.
create table cheongla_private.mbti_legacy_catalog (
 singleton boolean primary key default true check(singleton),
 content jsonb not null check(jsonb_typeof(content)='object')
);
alter table cheongla_private.mbti_legacy_catalog enable row level security;
revoke all on cheongla_private.mbti_legacy_catalog from public,anon,authenticated;

create function public.cheongla_mbti_legacy_catalog()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_mbti_operations() then
  raise exception '원장만 자료를 열람할 수 있습니다.' using errcode='42501';
 end if;
 return (select content from cheongla_private.mbti_legacy_catalog where singleton);
end;$$;
revoke all on function public.cheongla_mbti_legacy_catalog() from public,anon,authenticated;
grant execute on function public.cheongla_mbti_legacy_catalog() to authenticated;

-- Keep the existing RPC signatures for cached clients. private_pin is deprecated
-- and ignored; visibility and account authorization remain enforced below.
create or replace function public.cheongla_submit_new_inquiry_secure(
 visitor_token uuid,submission_token uuid,visitor_name text,visitor_phone text,
 visitor_role text,inquiry_title text,inquiry_body text,inquiry_visibility text,
 contact_consent boolean,website_field text,private_pin text default null)
returns uuid language plpgsql security definer set search_path='' as $$
begin
 return public.cheongla_submit_new_inquiry(visitor_token,submission_token,
  visitor_name,visitor_phone,visitor_role,inquiry_title,inquiry_body,
  inquiry_visibility,contact_consent,website_field);
end;$$;
revoke all on function public.cheongla_submit_new_inquiry_secure(uuid,uuid,text,text,text,text,text,text,boolean,text,text) from public,anon,authenticated;
grant execute on function public.cheongla_submit_new_inquiry_secure(uuid,uuid,text,text,text,text,text,text,boolean,text,text) to anon,authenticated;

create or replace function public.cheongla_save_board_post_secure(
 target_post uuid,post_title text,post_body text,post_visibility text,
 expected_updated_at timestamptz,private_pin text default null)
returns uuid language plpgsql security definer set search_path='' as $$
begin
 if not cheongla_private.can_use_member_services() then
  raise exception '권한이 없습니다.' using errcode='42501';
 end if;
 if target_post is not null and not exists(
  select 1 from public.cheongla_board_posts p
  where p.id=target_post and p.deleted_at is null
  and (p.author_id is not distinct from auth.uid() or cheongla_private.can_manage_life())
 ) then raise exception '글을 수정할 권한이 없습니다.' using errcode='42501';end if;
 return public.cheongla_save_board_post(target_post,post_title,post_body,
  post_visibility,expected_updated_at);
end;$$;
revoke all on function public.cheongla_save_board_post_secure(uuid,text,text,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.cheongla_save_board_post_secure(uuid,text,text,text,timestamptz,text) to authenticated;
notify pgrst,'reload schema';
