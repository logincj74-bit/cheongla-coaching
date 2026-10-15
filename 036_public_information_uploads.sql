begin;
create table if not exists public.cheongla_information_posts(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in('news','resource')),
 category text check(category in('admissions','past_papers','forms')),title text not null check(length(btrim(title)) between 1 and 150),
 body text not null check(length(btrim(body)) between 1 and 10000),source_url text not null default '' check(length(source_url)<=2000 and (source_url='' or source_url ~ '^https://[^/@[:space:]]+([/:?].*)?$')),
 status text not null default 'draft' check(status in('draft','published')),deleted_at timestamptz,
 created_by uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),check(kind='news' or category is not null)
);
create table if not exists public.cheongla_information_files(
 id uuid primary key default gen_random_uuid(),post_id uuid not null references public.cheongla_information_posts(id),object_path text not null unique,
 filename text not null check(length(filename) between 1 and 180),size_bytes integer not null check(size_bytes between 1 and 20971520),
 state text not null default 'uploading' check(state in('uploading','ready','removed')),created_by uuid references auth.users(id),created_at timestamptz not null default clock_timestamp()
);
alter table public.cheongla_information_posts enable row level security;
alter table public.cheongla_information_files enable row level security;
revoke all on public.cheongla_information_posts,public.cheongla_information_files from public,anon,authenticated;
grant select(id,kind,category,title,body,source_url,status,deleted_at,created_at,updated_at) on public.cheongla_information_posts to anon,authenticated;
grant select(id,post_id,object_path,filename,size_bytes,state,created_at) on public.cheongla_information_files to anon,authenticated;
create policy information_read on public.cheongla_information_posts for select to anon,authenticated using((status='published' and deleted_at is null) or cheongla_private.can_manage_notice_channel('desk'));
create policy information_file_read on public.cheongla_information_files for select to anon,authenticated using((state='ready' and exists(select 1 from public.cheongla_information_posts p where p.id=post_id and p.status='published' and p.deleted_at is null)) or cheongla_private.can_manage_notice_channel('desk'));
-- Anonymous policies call this boolean helper, which exposes no member data.
grant usage on schema cheongla_private to anon;
grant execute on function cheongla_private.can_manage_notice_channel(text) to anon;
create index if not exists information_kind_order on public.cheongla_information_posts(kind,created_at desc,id desc);
create index if not exists information_files_post on public.cheongla_information_files(post_id,state);
-- Only explicitly tagged news/resources are copied; academy/private notices remain protected.
do $$declare r record;d jsonb;
begin
 for r in select * from public.cheongla_notices where channel='desk' and title like '[청라정보:%' loop
  begin d:=r.body::jsonb;exception when others then continue;end;
  if coalesce(d->>'cheongla_information','')<>'1' or d->>'kind' not in('news','resource') or d->>'text' is null or r.title not like '[청라정보:'||(d->>'kind')||'] %' then continue;end if;
  if d->>'kind'='resource' and coalesce(d->>'category','') not in('admissions','past_papers','forms')then continue;end if;
  insert into public.cheongla_information_posts(id,kind,category,title,body,source_url,status,created_by,created_at,updated_at)
  values(r.id,d->>'kind',case when d->>'kind'='resource' then d->>'category' else null end,substr(r.title,length('[청라정보:'||(d->>'kind')||'] ')+1),d->>'text',coalesce(d->>'url',''),'published',r.created_by,r.created_at,r.updated_at)on conflict(id)do nothing;
 end loop;
end;$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('cheongla-information','cheongla-information',false,20971520,array['application/pdf','application/octet-stream','application/haansofthwp','application/x-hwp','application/hwp','application/vnd.hancom.hwp','application/vnd.hancom.hwpx','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation'])on conflict(id)do update set public=false,file_size_limit=20971520,allowed_mime_types=excluded.allowed_mime_types;
create or replace function cheongla_private.can_upload_information(object_name text)returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.can_manage_notice_channel('desk') and exists(select 1 from public.cheongla_information_files f join public.cheongla_information_posts p on p.id=f.post_id where f.object_path=object_name and f.state='uploading' and f.created_by=auth.uid() and p.deleted_at is null and p.status='draft');
$$;
revoke all on function cheongla_private.can_upload_information(text) from public,anon,authenticated;
grant execute on function cheongla_private.can_upload_information(text) to authenticated;
create policy information_storage_insert on storage.objects for insert to authenticated with check(bucket_id='cheongla-information' and cheongla_private.can_upload_information(name));
create policy information_storage_read on storage.objects for select to anon,authenticated using(bucket_id='cheongla-information' and exists(select 1 from public.cheongla_information_files f join public.cheongla_information_posts p on p.id=f.post_id where f.object_path=name and ((f.state='ready' and p.status='published' and p.deleted_at is null) or cheongla_private.can_manage_notice_channel('desk'))));
create or replace function public.cheongla_save_information(target_post uuid,post_kind text,post_title text,post_body text,resource_category text,source_url text,post_status text,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare old public.cheongla_information_posts%rowtype;result uuid;
begin
 if not cheongla_private.can_manage_notice_channel('desk')then raise exception '원장·실장만 게시물을 관리할 수 있습니다.' using errcode='42501';end if;
 if post_kind is null or post_kind not in('news','resource')or post_title is null or length(btrim(post_title))not between 1 and 150 or post_body is null or length(btrim(post_body))not between 1 and 10000 or source_url is null or length(source_url)>2000 or(source_url<>'' and source_url !~ '^https://[^/@[:space:]]+([/:?].*)?$')or post_status is null or post_status not in('draft','published')or(post_kind='resource' and coalesce(resource_category,'')not in('admissions','past_papers','forms'))then raise exception '제목·내용·분류·주소를 확인해 주세요.';end if;
 if target_post is not null then select * into old from public.cheongla_information_posts where id=target_post for update;if not found or old.deleted_at is not null then raise exception '삭제되었거나 없는 게시물입니다.';end if;end if;
 if old.updated_at is distinct from expected_updated_at then raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 저장해 주세요.';end if;
 if old.id is not null and old.kind<>post_kind then raise exception '게시판 종류는 바꿀 수 없습니다.';end if;
 if post_kind='resource' and post_status='published' and source_url='' and not exists(select 1 from public.cheongla_information_files where post_id=target_post and state='ready')then raise exception '자료 파일을 첨부하거나 다운로드 주소를 입력해 주세요.';end if;
 if target_post is null then insert into public.cheongla_information_posts(kind,category,title,body,source_url,status,created_by)values(post_kind,case when post_kind='resource' then resource_category else null end,btrim(post_title),btrim(post_body),source_url,post_status,auth.uid())returning id into result;
 else update public.cheongla_information_posts set category=case when post_kind='resource' then resource_category else null end,title=btrim(post_title),body=btrim(post_body),source_url=cheongla_save_information.source_url,status=post_status,updated_at=clock_timestamp()where id=target_post returning id into result;end if;return result;
end;$$;
create or replace function public.cheongla_set_information_deleted(target_post uuid,remove_post boolean,expected_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare p public.cheongla_information_posts%rowtype;
begin
 if not cheongla_private.can_manage_notice_channel('desk')then raise exception '원장·실장만 관리할 수 있습니다.'using errcode='42501';end if;
 select * into p from public.cheongla_information_posts where id=target_post for update;
 if not found or p.updated_at is distinct from expected_updated_at then raise exception '게시물이 변경되었습니다. 새로고침 후 확인해 주세요.';end if;
 if remove_post is null then raise exception '처리 방법을 선택해 주세요.';end if;
 update public.cheongla_information_posts set deleted_at=case when remove_post then clock_timestamp()else null end,status='draft',updated_at=clock_timestamp()where id=target_post;
end;$$;
create or replace function public.cheongla_reserve_information_file(target_post uuid,file_name text,file_size integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.cheongla_information_posts%rowtype;fid uuid:=gen_random_uuid();ext text;path text;
begin
 if not cheongla_private.can_manage_notice_channel('desk')then raise exception '원장·실장만 파일을 올릴 수 있습니다.'using errcode='42501';end if;
 select * into p from public.cheongla_information_posts where id=target_post for update;
 if not found or p.deleted_at is not null or p.status<>'draft'then raise exception '먼저 게시물을 초안으로 저장해 주세요.';end if;
 ext:=lower(substring(file_name from '\.([^.]+)$'));
 if file_name is null or length(file_name)not between 1 and 180 or file_name ~ '[/\\[:cntrl:]]'or file_size is null or file_size not between 1 and 20971520 or ext is null or ext not in('pdf','hwp','hwpx','doc','docx','xls','xlsx','ppt','pptx')then raise exception 'PDF·한글·오피스 파일을 20MB 이하로 선택해 주세요.';end if;
 if(select count(*)from public.cheongla_information_files where post_id=target_post and state in('uploading','ready'))>=5 then raise exception '한 게시물에는 최대 5개 파일을 첨부할 수 있습니다.';end if;
 path:=target_post::text||'/'||fid::text||'.'||ext;
 insert into public.cheongla_information_files(id,post_id,object_path,filename,size_bytes,created_by)values(fid,target_post,path,file_name,file_size,auth.uid());
 return jsonb_build_object('id',fid,'path',path);
end;$$;
create or replace function public.cheongla_finish_information_file(target_file uuid)
returns void language plpgsql security definer set search_path='' as $$
declare f public.cheongla_information_files%rowtype;p public.cheongla_information_posts%rowtype;actual_size text;
begin
 if not cheongla_private.can_manage_notice_channel('desk')then raise exception '원장·실장만 파일을 확인할 수 있습니다.'using errcode='42501';end if;
 select * into f from public.cheongla_information_files where id=target_file;
 select * into p from public.cheongla_information_posts where id=f.post_id for update;
 if f.id is null or f.state<>'uploading' or f.created_by is distinct from auth.uid()or p.deleted_at is not null or p.status<>'draft'then raise exception '첨부 상태가 변경되었습니다. 다시 확인해 주세요.';end if;
 select metadata->>'size'into actual_size from storage.objects where bucket_id='cheongla-information'and name=f.object_path;
 if actual_size is null or actual_size !~ '^[0-9]+$'or actual_size::bigint<>f.size_bytes then raise exception '파일 업로드가 완료되지 않았거나 파일 크기가 다릅니다.';end if;
 update public.cheongla_information_files set state='ready'where id=f.id;
end;$$;
create or replace function public.cheongla_remove_information_file(target_file uuid,expected_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare f public.cheongla_information_files%rowtype;p public.cheongla_information_posts%rowtype;
begin
 if not cheongla_private.can_manage_notice_channel('desk')then raise exception '원장·실장만 첨부를 해제할 수 있습니다.'using errcode='42501';end if;
 select * into f from public.cheongla_information_files where id=target_file;
 select * into p from public.cheongla_information_posts where id=f.post_id for update;
 if f.id is null or p.deleted_at is not null or p.status<>'draft'or p.updated_at is distinct from expected_updated_at then raise exception '초안에서 최신 내용을 확인한 후 첨부를 해제해 주세요.';end if;
 update public.cheongla_information_files set state='removed'where id=f.id;
 update public.cheongla_information_posts set updated_at=clock_timestamp()where id=p.id;
end;$$;

create or replace function cheongla_private.can_read_notification(kind text,target uuid,student uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;q record;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved';
 if not found then return false;end if;
 if kind='fee_collection' then return exists(select 1 from cheongla_private.collection_notices n where n.id=target and cheongla_private.can_read_collection(n.fee_kind,n.id));end if;
 if kind='contact_update' then return cheongla_private.can_manage_tuition();end if;
 if kind='meal_submission' then return cheongla_private.can_manage_meal_forms();end if;
 if kind='information' then return exists(select 1 from public.cheongla_information_posts where id=target and status='published' and deleted_at is null);end if;
 case kind
 when 'notice' then return exists(select 1 from public.cheongla_notices n where n.id=target and (n.audience='all' or n.audience=me.role or me.role in ('owner','english_director','math_director','korean_teacher','manager')));
 when 'question' then
  select student_id,subject into q from public.cheongla_questions where id=target;
  return found and cheongla_private.can_read_question(q.student_id,q.subject);
 when 'new_inquiry' then return cheongla_private.can_manage_consultations() and exists(select 1 from public.cheongla_new_inquiries where id=target);
 when 'board' then return cheongla_private.can_read_board_post(target);
 when 'tuition' then return exists(select 1 from public.cheongla_tuition_notices n where n.id=target and (cheongla_private.can_manage_tuition() or (n.status='published' and cheongla_private.is_parent_of(n.student_id))));
 when 'exam' then return exists(select 1 from public.cheongla_exams e where e.id=target and (cheongla_private.can_manage_exams() or (e.status in ('open','closed') and cheongla_private.can_view_exams())));
 when 'application' then return exists(select 1 from public.cheongla_exam_applications a where a.exam_id=target and a.student_id=student and (cheongla_private.can_manage_exams() or cheongla_private.is_parent_of(student) or me.id=student));
 when 'exam_fee' then return exists(select 1 from public.cheongla_exam_fee_notices n where n.id=target and (cheongla_private.can_manage_exams() or (n.status='published' and cheongla_private.can_read_exam_fee(n.exam_id,n.student_id))));
 when 'schedule' then return exists(select 1 from public.cheongla_schedule_events e where e.id=target and (cheongla_private.can_manage_schedule() or (e.status='published' and (e.audience='all' or e.audience=me.role))));
 else return false;
 end case;
end;$$;
create or replace function cheongla_private.notify_information_post() returns trigger language plpgsql security definer set search_path='' as $$
declare people uuid[];
begin
 if new.status<>'published' or new.deleted_at is not null then return new;end if;
 if tg_op='UPDATE' and (new.title,new.body,new.source_url,new.status) is not distinct from(old.title,old.body,old.source_url,old.status) then return new;end if;
 select array_agg(id) into people from public.cheongla_profiles where approval_status='approved' and membership_state='active';
 perform cheongla_private.send_notification(people,'information',new.id,null,case when new.kind='news'then '입시 뉴스'else '자료실'end||' · '||new.title,case when new.kind='news'then 'admissions_news'else 'resources'end,'information:'||new.id::text||':'||new.updated_at::text);
 return new;
end;$$;
revoke all on function cheongla_private.notify_information_post()from public,anon,authenticated;
create trigger cheongla_information_notification after insert or update on public.cheongla_information_posts for each row execute function cheongla_private.notify_information_post();
revoke all on function public.cheongla_save_information(uuid,text,text,text,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_save_information(uuid,text,text,text,text,text,text,timestamptz) to authenticated;
revoke all on function public.cheongla_set_information_deleted(uuid,boolean,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_set_information_deleted(uuid,boolean,timestamptz) to authenticated;
revoke all on function public.cheongla_reserve_information_file(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.cheongla_reserve_information_file(uuid,text,integer) to authenticated;
revoke all on function public.cheongla_finish_information_file(uuid) from public,anon,authenticated;
grant execute on function public.cheongla_finish_information_file(uuid) to authenticated;
revoke all on function public.cheongla_remove_information_file(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_remove_information_file(uuid,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
