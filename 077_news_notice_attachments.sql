-- Notice attachments are staged before the post transaction and retained through recycling.
create table public.cheongla_notice_files(id uuid primary key default gen_random_uuid(),post_id uuid not null,channel text not null default 'director' check(channel in('director','desk')),object_path text not null unique,filename text not null,size_bytes integer not null check(size_bytes between 1 and 20971520),state text not null default 'uploading' check(state in('uploading','ready','removed')),created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp());
create index on public.cheongla_notice_files(post_id,state);
alter table public.cheongla_notice_files enable row level security;
revoke all on public.cheongla_notice_files from public,anon,authenticated;
grant select on public.cheongla_notice_files to authenticated;
create policy notice_files_read on public.cheongla_notice_files for select to authenticated using(cheongla_private.can_use_member_services() and exists(select 1 from public.cheongla_notices n where n.id=post_id) and(state='ready' or cheongla_private.can_manage_notice_channel((select n.channel from public.cheongla_notices n where n.id=post_id))));
create table cheongla_private.notice_file_purge_claims(post_id uuid primary key,version timestamptz not null);
alter table cheongla_private.notice_file_purge_claims enable row level security;
revoke all on cheongla_private.notice_file_purge_claims from public,anon,authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('cheongla-notices','cheongla-notices',false,20971520,array['application/pdf','application/octet-stream','image/jpeg','image/png','image/webp']);
create or replace function cheongla_private.notice_file_access(path text,operation text)returns boolean language plpgsql stable security definer set search_path=''as $$
declare f public.cheongla_notice_files%rowtype;n public.cheongla_notices%rowtype;
begin
 if not cheongla_private.can_use_member_services()then return false;end if;
 select *into f from public.cheongla_notice_files where object_path=path;if not found then return false;end if;
 select *into n from public.cheongla_notices where id=f.post_id;
 if operation='upload'then return f.created_by=auth.uid()and f.state='uploading'and cheongla_private.can_manage_notice_channel(coalesce(n.channel,f.channel))and not exists(select 1 from cheongla_private.content_recycle where source_id=f.post_id and kind='notice');end if;
 if operation='read'then return n.id is not null and cheongla_private.can_read_notice(n.audience)and(f.state='ready' or cheongla_private.can_manage_notice_channel(n.channel));end if;
 if operation='purge'then return cheongla_private.can_manage_life()and exists(select 1 from cheongla_private.content_recycle r join cheongla_private.notice_file_purge_claims j on j.post_id=r.source_id and j.version=r.deleted_at where r.source_id=f.post_id and r.kind='notice');end if;
 return false;
end;$$;
revoke all on function cheongla_private.notice_file_access(text,text)from public,anon,authenticated;
grant execute on function cheongla_private.notice_file_access(text,text)to authenticated;
create policy notice_file_upload on storage.objects for insert to authenticated with check(bucket_id='cheongla-notices'and cheongla_private.notice_file_access(name,'upload'));
create policy notice_file_download on storage.objects for select to authenticated using(bucket_id='cheongla-notices'and cheongla_private.notice_file_access(name,'read'));
create policy notice_file_purge on storage.objects for delete to authenticated using(bucket_id='cheongla-notices'and cheongla_private.notice_file_access(name,'purge'));
create or replace function public.cheongla_reserve_notice_file(target_post uuid,file_name text,file_size integer,target_channel text)returns jsonb language plpgsql security definer set search_path=''as $$
declare fid uuid:=gen_random_uuid();ext text;n public.cheongla_notices%rowtype;path text;
begin
 if auth.uid()is null or not cheongla_private.can_manage_notice_channel(target_channel)then raise exception '공지 작성 권한이 없습니다.'using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(target_post::text,0));select *into n from public.cheongla_notices where id=target_post;
 if target_post is null or(n.id is not null and n.channel<>target_channel)or exists(select 1 from cheongla_private.content_recycle where source_id=target_post)then raise exception '공지 상태를 다시 확인해 주세요.';end if;
 ext:=lower(substring(file_name from '\.([^.]+)$'));
 if file_name is null or length(file_name)not between 1 and 180 or file_name ~ '[/\\[:cntrl:]]'or file_size is null or file_size not between 1 and 20971520 or ext is null or ext not in('pdf','hwp','hwpx','doc','docx','xls','xlsx','ppt','pptx','jpg','jpeg','png','webp')then raise exception '문서·사진 파일을 20MB 이하로 선택해 주세요.';end if;
 if(select count(*)from public.cheongla_notice_files where post_id=target_post and state='uploading')>=10 then raise exception '미완료 첨부파일이 많습니다. 기존 수정을 먼저 저장해 주세요.';end if;
 path:=target_post::text||'/'||fid::text||'.'||ext;
 insert into public.cheongla_notice_files(id,post_id,channel,object_path,filename,size_bytes,created_by)values(fid,target_post,target_channel,path,file_name,file_size,auth.uid());return jsonb_build_object('id',fid,'path',path);
end;$$;
create or replace function public.cheongla_save_notice_files(target_post uuid,post_title text,post_body text,post_audience text,post_pinned boolean,target_channel text,expected_updated_at timestamptz,added_files uuid[],removed_files uuid[])returns uuid language plpgsql security definer set search_path=''as $$
declare n public.cheongla_notices%rowtype;f public.cheongla_notice_files%rowtype;cnt integer:=0;
begin
 if auth.uid()is null or not cheongla_private.can_manage_notice_channel(target_channel)then raise exception '공지 작성 권한이 없습니다.'using errcode='42501';end if;
 if target_post is null or length(btrim(coalesce(post_title,'')))not between 1 and 150 or length(btrim(coalesce(post_body,'')))not between 1 and 10000 or post_audience is null or post_audience not in('all','student','parent')or post_pinned is null or added_files is null or removed_files is null then raise exception '공지 내용을 확인해 주세요.';end if;
 perform pg_advisory_xact_lock(hashtextextended(target_post::text,0));select *into n from public.cheongla_notices where id=target_post for update;
 if n.updated_at is distinct from expected_updated_at or(n.id is not null and n.channel<>target_channel)or exists(select 1 from cheongla_private.content_recycle where source_id=target_post)then raise exception '다른 담당자가 수정하거나 삭제했습니다. 새로고침 후 확인해 주세요.';end if;
 for f in select *from public.cheongla_notice_files where id=any(added_files)for update loop
  if f.post_id<>target_post or f.created_by<>auth.uid()or f.state<>'uploading'or not exists(select 1 from storage.objects where bucket_id='cheongla-notices'and name=f.object_path and(metadata->>'size')::bigint=f.size_bytes)then raise exception '첨부파일 업로드를 확인해 주세요.';end if;cnt:=cnt+1;
 end loop;
 if cnt<>cardinality(added_files)or(select count(*)from public.cheongla_notice_files where post_id=target_post and state='ready'and not(id=any(removed_files)))+cnt>5 then raise exception '기존 첨부를 포함해 최대 5개까지 올릴 수 있습니다.';end if;
 if exists(select 1 from unnest(removed_files)x where not exists(select 1 from public.cheongla_notice_files where id=x and post_id=target_post and state='ready'))then raise exception '삭제할 첨부가 변경되었습니다.';end if;
 update public.cheongla_notice_files set state='removed'where id=any(removed_files)and post_id=target_post;
 update public.cheongla_notice_files set state='ready'where id=any(added_files)and post_id=target_post;
 if n.id is null then insert into public.cheongla_notices(id,title,body,audience,pinned,created_by,channel)values(target_post,btrim(post_title),btrim(post_body),post_audience,post_pinned,auth.uid(),target_channel);
 else update public.cheongla_notices set title=btrim(post_title),body=btrim(post_body),audience=post_audience,pinned=post_pinned where id=target_post;end if;
 return target_post;
end;$$;
create or replace function public.cheongla_prepare_notice_purge(target_id uuid,expected_version timestamptz)returns jsonb language plpgsql security definer set search_path=''as $$
declare r cheongla_private.content_recycle%rowtype;paths jsonb;
begin
 if auth.uid()is null or not cheongla_private.can_manage_life()then raise exception '휴지통 관리 권한이 없습니다.'using errcode='42501';end if;
 select *into r from cheongla_private.content_recycle where id=target_id and kind='notice'for update;
 if not found or r.deleted_at is distinct from expected_version then raise exception '휴지통이 변경되었습니다.';end if;
 insert into cheongla_private.notice_file_purge_claims values(r.source_id,r.deleted_at)on conflict(post_id)do nothing;
 select coalesce(jsonb_agg(object_path),'[]')into paths from public.cheongla_notice_files where post_id=r.source_id;return jsonb_build_object('id',r.id,'post_id',r.source_id,'version',r.deleted_at,'paths',paths);
end;$$;
-- Preserve the existing audited recycle actions and extend the storage cleanup.
alter function public.cheongla_content_trash_action(text,uuid,text,timestamptz)rename to cheongla_content_trash_action_v71;
revoke all on function public.cheongla_content_trash_action_v71(text,uuid,text,timestamptz)from public,anon,authenticated;
create function public.cheongla_content_trash_action(target_kind text,target_id uuid,trash_action text,expected_version timestamptz)returns void language plpgsql security definer set search_path=''as $$
declare original_id uuid;
begin
 if auth.uid()is null or not cheongla_private.can_manage_life()then raise exception '휴지통 관리 권한이 없습니다.'using errcode='42501';end if;
 if target_kind='notice'then
  select source_id into original_id from cheongla_private.content_recycle where id=target_id and kind='notice'and deleted_at=expected_version for update;if not found then raise exception '휴지통이 변경되었습니다.';end if;
  if trash_action='restore'and exists(select 1 from cheongla_private.notice_file_purge_claims where post_id=original_id)then raise exception '영구삭제가 시작된 공지는 복구할 수 없습니다.';end if;
  if trash_action='purge'then
   if exists(select 1 from storage.objects o join public.cheongla_notice_files f on f.object_path=o.name where o.bucket_id='cheongla-notices'and f.post_id=original_id)then raise exception '첨부파일 삭제를 먼저 완료해 주세요.';end if;
   delete from public.cheongla_notice_files where post_id=original_id;delete from cheongla_private.notice_file_purge_claims where post_id=original_id;
  end if;
 end if;
 perform public.cheongla_content_trash_action_v71(target_kind,target_id,trash_action,expected_version);
end;$$;
alter function public.cheongla_content_trash()rename to cheongla_content_trash_v71;
revoke all on function public.cheongla_content_trash_v71()from public,anon,authenticated;
create function public.cheongla_content_trash()returns jsonb language plpgsql security definer set search_path=''as $$
declare data jsonb;
begin
 data:=public.cheongla_content_trash_v71();return(select coalesce(jsonb_agg(x||case when x->>'kind'='notice'then jsonb_build_object('purging',exists(select 1 from cheongla_private.notice_file_purge_claims where post_id=(select source_id from cheongla_private.content_recycle where id=(x->>'id')::uuid)))else '{}'::jsonb end),'[]')from jsonb_array_elements(data)x);
end;$$;
revoke all on function public.cheongla_reserve_notice_file(uuid,text,integer,text),public.cheongla_save_notice_files(uuid,text,text,text,boolean,text,timestamptz,uuid[],uuid[]),public.cheongla_prepare_notice_purge(uuid,timestamptz),public.cheongla_content_trash(),public.cheongla_content_trash_action(text,uuid,text,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_reserve_notice_file(uuid,text,integer,text),public.cheongla_save_notice_files(uuid,text,text,text,boolean,text,timestamptz,uuid[],uuid[]),public.cheongla_prepare_notice_purge(uuid,timestamptz),public.cheongla_content_trash(),public.cheongla_content_trash_action(text,uuid,text,timestamptz)to authenticated;
-- Extend the established news/resource attachment pipeline to photos.
do $$declare definition text;begin
 definition:=pg_get_functiondef('public.cheongla_reserve_information_file(uuid,text,integer)'::regprocedure);
 definition:=replace(definition,'''ppt'',''pptx'')','''ppt'',''pptx'',''jpg'',''jpeg'',''png'',''webp'')');execute definition;
end;$$;
update storage.buckets set allowed_mime_types=allowed_mime_types||array['image/jpeg','image/png','image/webp']where id='cheongla-information';
notify pgrst,'reload schema';
