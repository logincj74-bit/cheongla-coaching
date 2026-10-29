create table public.cheongla_director_posts(
 id uuid primary key default gen_random_uuid(),category text not null check(category in('greeting','thoughts','photos','objects')),
 title text not null default '새 글' check(length(title)between 1 and 200),body text not null default '' check(length(body)<=50000),
 state text not null default 'draft' check(state in('draft','published')),archived_at timestamptz,
 created_by uuid not null,updated_by uuid not null,created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp()
);
create unique index director_single_greeting on public.cheongla_director_posts(category)where category='greeting'and archived_at is null;
alter table public.cheongla_director_posts enable row level security;
revoke all on public.cheongla_director_posts from public,anon,authenticated;
grant select on public.cheongla_director_posts to anon,authenticated;
create policy director_public_read on public.cheongla_director_posts for select to anon using(state='published'and archived_at is null);
create policy director_member_read on public.cheongla_director_posts for select to authenticated using((state='published'and archived_at is null)or(cheongla_private.is_principal()and cheongla_private.can_use_member_services()));

create table public.cheongla_director_files(
 id uuid primary key default gen_random_uuid(),post_id uuid not null references public.cheongla_director_posts(id),
 object_path text not null unique,filename text not null,size_bytes integer not null check(size_bytes between 1 and 20971520),
 state text not null default 'pending' check(state in('pending','ready')),created_by uuid not null,created_at timestamptz not null default clock_timestamp()
);
alter table public.cheongla_director_files enable row level security;
revoke all on public.cheongla_director_files from public,anon,authenticated;
grant select on public.cheongla_director_files to anon,authenticated;
create policy director_files_public on public.cheongla_director_files for select to anon using(state='ready'and exists(select 1 from public.cheongla_director_posts p where p.id=post_id and p.state='published'and p.archived_at is null));
create policy director_files_member on public.cheongla_director_files for select to authenticated using((cheongla_private.is_principal()and cheongla_private.can_use_member_services())or(state='ready'and exists(select 1 from public.cheongla_director_posts p where p.id=post_id and p.state='published'and p.archived_at is null)));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('cheongla-director','cheongla-director',false,20971520,array['image/jpeg','image/png','image/webp','image/gif','application/pdf','text/plain','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/haansofthwp','application/x-hwp','application/hwp+zip','application/octet-stream']);
create policy director_storage_anon on storage.objects for select to anon using(bucket_id='cheongla-director'and exists(select 1 from public.cheongla_director_files f where f.object_path=name and f.state='ready'));
create policy director_storage_member on storage.objects for select to authenticated using(bucket_id='cheongla-director'and((cheongla_private.is_principal()and cheongla_private.can_use_member_services())or exists(select 1 from public.cheongla_director_files f where f.object_path=name and f.state='ready')));
create policy director_storage_upload on storage.objects for insert to authenticated with check(bucket_id='cheongla-director'and cheongla_private.is_principal()and cheongla_private.can_use_member_services()and name~*'^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|gif|pdf|doc|docx|ppt|pptx|xls|xlsx|hwp|hwpx|txt)$'and exists(select 1 from public.cheongla_director_posts p where p.id::text=split_part(name,'/',1)and p.archived_at is null));
create policy director_storage_cleanup on storage.objects for delete to authenticated using(bucket_id='cheongla-director'and cheongla_private.is_principal()and cheongla_private.can_use_member_services());

create or replace function public.cheongla_prepare_director_post(target_post uuid,post_category text)returns jsonb language plpgsql security definer set search_path=''as $$
declare r public.cheongla_director_posts%rowtype;
begin
 if not(cheongla_private.is_principal()and cheongla_private.can_use_member_services())then raise exception '원장만 글을 작성할 수 있습니다.'using errcode='42501';end if;
 if post_category is null or post_category not in('greeting','thoughts','photos','objects')then raise exception '게시판을 확인해 주세요.';end if;
 perform pg_advisory_xact_lock(hashtext('director-space'),hashtext(post_category));
 if target_post is not null then select *into r from public.cheongla_director_posts where id=target_post and category=post_category and archived_at is null;
 elsif post_category='greeting'then select *into r from public.cheongla_director_posts where category='greeting'and archived_at is null;end if;
 if r.id is null then
  if target_post is not null then raise exception '글을 찾을 수 없습니다.';end if;
  insert into public.cheongla_director_posts(category,created_by,updated_by)values(post_category,auth.uid(),auth.uid())returning *into r;
 end if;return to_jsonb(r);
end;$$;
create or replace function public.cheongla_stage_director_file(target_post uuid,object_name text,original_name text,file_size integer)returns uuid language plpgsql security definer set search_path=''as $$
declare result uuid;
begin
 if not(cheongla_private.is_principal()and cheongla_private.can_use_member_services())then raise exception '원장만 첨부할 수 있습니다.'using errcode='42501';end if;
 if original_name is null or length(original_name)not between 1 and 255 or original_name!~*'\.(jpg|jpeg|png|webp|gif|pdf|doc|docx|ppt|pptx|xls|xlsx|hwp|hwpx|txt)$'or file_size is null or file_size not between 1 and 20971520 or split_part(object_name,'/',1)is distinct from target_post::text then raise exception '파일 종류·이름·크기를 확인해 주세요. 파일당 최대 20MB입니다.';end if;
 if not exists(select 1 from public.cheongla_director_posts where id=target_post and archived_at is null)or not exists(select 1 from storage.objects where bucket_id='cheongla-director'and name=object_name and (metadata->>'size')::bigint=file_size)then raise exception '업로드된 파일을 확인하지 못했습니다.';end if;
 insert into public.cheongla_director_files(post_id,object_path,filename,size_bytes,created_by)values(target_post,object_name,original_name,file_size,auth.uid())returning id into result;return result;
end;$$;
create table cheongla_private.director_post_history(id bigint generated always as identity primary key,post_id uuid not null,actor_id uuid not null,before_record jsonb not null,after_record jsonb not null,created_at timestamptz not null default clock_timestamp());
alter table cheongla_private.director_post_history enable row level security;
revoke all on cheongla_private.director_post_history from public,anon,authenticated;
create or replace function public.cheongla_save_director_post(target_post uuid,post_title text,post_body text,post_state text,expected_updated_at timestamptz,file_ids uuid[])returns jsonb language plpgsql security definer set search_path=''as $$
declare r public.cheongla_director_posts%rowtype;n integer;before_row jsonb;
begin
 if not(cheongla_private.is_principal()and cheongla_private.can_use_member_services())then raise exception '원장만 수정할 수 있습니다.'using errcode='42501';end if;
 if post_title is null or length(trim(post_title))not between 1 and 200 or post_body is null or length(post_body)>50000 or post_state is null or post_state not in('draft','published')or coalesce(cardinality(file_ids),0)>10 then raise exception '제목·본문·첨부파일을 확인해 주세요.';end if;
 select *into r from public.cheongla_director_posts where id=target_post and archived_at is null for update;
 if not found or r.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 작성 내용을 보관한 뒤 새로고침해 주세요.';end if;
 before_row:=to_jsonb(r);
 if coalesce(cardinality(file_ids),0)>0 then
  update public.cheongla_director_files set state='ready'where id=any(file_ids)and post_id=r.id and state='pending'and created_by=auth.uid();get diagnostics n=row_count;
  if n<>cardinality(file_ids)then raise exception '첨부파일 상태가 변경되었습니다.';end if;
 end if;
 update public.cheongla_director_posts set title=trim(post_title),body=post_body,state=post_state,updated_at=clock_timestamp(),updated_by=auth.uid()where id=r.id returning *into r;
 insert into cheongla_private.director_post_history(post_id,actor_id,before_record,after_record)values(r.id,auth.uid(),before_row,to_jsonb(r));
 return to_jsonb(r);
end;$$;
revoke all on function public.cheongla_prepare_director_post(uuid,text),public.cheongla_stage_director_file(uuid,text,text,integer),public.cheongla_save_director_post(uuid,text,text,text,timestamptz,uuid[])from public,anon;
grant execute on function public.cheongla_prepare_director_post(uuid,text),public.cheongla_stage_director_file(uuid,text,text,integer),public.cheongla_save_director_post(uuid,text,text,text,timestamptz,uuid[])to authenticated;
create or replace function cheongla_private.notify_director_post()returns trigger language plpgsql security definer set search_path=''as $$
declare people uuid[];
begin
 if new.state<>'published'or new.archived_at is not null then return new;end if;
 select array_agg(id)into people from public.cheongla_profiles where approval_status='approved'and membership_state='active';
 perform cheongla_private.send_notification(people,'director_post',new.id,null,'원장님의 새 글: '||left(new.title,80),'director_'||new.category,'director-post:'||new.id||':'||new.updated_at);return new;
end;$$;
revoke all on function cheongla_private.notify_director_post()from public,anon,authenticated;
create trigger director_post_notification after insert or update on public.cheongla_director_posts for each row execute function cheongla_private.notify_director_post();

alter table cheongla_private.account_help_requests add column school_name text not null default '';
create or replace function public.cheongla_request_account_help_v2(visitor_token uuid,submission_token uuid,help_kind text,member_name text,registered_phone text,member_type text,student_name text,known_login text,website_field text,school_name text)returns jsonb language plpgsql security definer set search_path=''as $$
declare result jsonb;
begin
 if school_name is null or length(trim(school_name))not between 1 and 120 then raise exception '학교명을 입력해 주세요.';end if;
 result:=public.cheongla_request_account_help(visitor_token,submission_token,help_kind,member_name,registered_phone,member_type,student_name,known_login,website_field);
 update cheongla_private.account_help_requests set school_name=trim(cheongla_request_account_help_v2.school_name)where request_token=submission_token and visitor_id=visitor_token and state='pending';return result;
end;$$;
revoke all on function public.cheongla_request_account_help_v2(uuid,uuid,text,text,text,text,text,text,text,text)from public;
grant execute on function public.cheongla_request_account_help_v2(uuid,uuid,text,text,text,text,text,text,text,text)to anon,authenticated;

-- Reopen only the upcoming month's expired initial application window.
update public.cheongla_meal_forms set deadline=(clock_timestamp()at time zone'Asia/Seoul')::date+2,updated_at=clock_timestamp()
where month=(date_trunc('month',clock_timestamp()at time zone'Asia/Seoul')+interval'1 month')::date and deadline<(clock_timestamp()at time zone'Asia/Seoul')::date;
notify pgrst,'reload schema';
CREATE OR REPLACE FUNCTION cheongla_private.can_read_notification(kind text, target uuid, student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select case when kind='director_post' then exists(select 1 from public.cheongla_director_posts where id=target and state='published'and archived_at is null) when kind='account_recovery' then cheongla_private.can_manage_account_recovery() and exists(select 1 from cheongla_private.account_help_requests where id=target) when kind='winter_booking'then exists(select 1 from cheongla_private.winter_bookings r where r.id=target and r.archived_at is null and(cheongla_private.can_manage_winter()or(cheongla_private.can_use_member_services()and r.owner_id=auth.uid())))else cheongla_private.can_read_notification_before_winter(kind,target,student)end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.guard_staff_journal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare director boolean:=cheongla_private.is_principal();d date:=(clock_timestamp()at time zone'Asia/Seoul')::date;
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 근무일지를 이용할 수 있습니다.'using errcode='42501';end if;
 if TG_OP='DELETE'then if not director then raise exception '원장만 삭제할 수 있습니다.'using errcode='42501';end if;return old;end if;
 if not director then
  if new.author_id<>auth.uid()or new.archived_at is not null then raise exception '본인의 미마감 일지만 수정할 수 있습니다.'using errcode='42501';end if;
  if TG_OP='INSERT'then
   if new.work_on<>d or new.closed_at is not null or cheongla_private.staff_shift_closed(auth.uid(),new.work_on)then raise exception '이미 마감했거나 작성할 수 없는 날짜입니다.'using errcode='42501';end if;
  else
   if old.work_on<>d or old.closed_at is not null or old.author_id<>auth.uid()or old.author_id<>new.author_id or old.work_on<>new.work_on or old.archived_at is distinct from new.archived_at then raise exception '업무마감 후 수정·삭제는 원장만 가능합니다.'using errcode='42501';end if;
   if new.closed_at is not null and new.closed_by is distinct from auth.uid()then raise exception '마감자를 확인해 주세요.'using errcode='42501';end if;
  end if;
 end if;return new;
end;$function$
;
