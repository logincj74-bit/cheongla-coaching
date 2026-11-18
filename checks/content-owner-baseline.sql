-- Pre-change function definitions for an isolated synthetic database, no private records.
CREATE OR REPLACE FUNCTION cheongla_private.can_use_member_services()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved' and membership_state='active');
$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_manage_notice_channel(target_channel text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved' and membership_state='active' and ((target_channel='director' and role in ('owner','english_director','math_director')) or (target_channel='desk' and role in ('owner','english_director','math_director','manager'))));
$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.is_principal()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.cheongla_profiles where id=auth.uid() and approval_status='approved' and membership_state='active' and role in('owner','english_director','math_director'));
$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_save_daily_word(target_day date, post_title text, post_body text, post_status text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_save_information(target_post uuid, post_kind text, post_title text, post_body text, resource_category text, source_url text, post_status text, expected_updated_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare old public.cheongla_information_posts%rowtype;result uuid;
begin
 if not cheongla_private.can_manage_notice_channel('desk')then raise exception '원장·실장만 게시물을 관리할 수 있습니다.' using errcode='42501';end if;
 if post_kind is null or post_kind not in('news','resource')or post_title is null or length(btrim(post_title))not between 1 and 150 or post_body is null or length(btrim(post_body))not between 1 and 10000 or source_url is null or length(source_url)>2000 or(source_url<>'' and source_url !~ '^https://[^/@[:space:]]+([/:?].*)?$')or post_status is null or post_status not in('draft','published')or(post_kind='resource' and coalesce(resource_category,'')not in('admissions','past_papers','learning_materials','learning_materials_korean','learning_materials_math','learning_materials_english','learning_materials_exploration','forms'))then raise exception '제목·내용·분류·주소를 확인해 주세요.';end if;
 if target_post is not null then select * into old from public.cheongla_information_posts where id=target_post for update;if not found or old.deleted_at is not null then raise exception '삭제되었거나 없는 게시물입니다.';end if;end if;
 if old.updated_at is distinct from expected_updated_at then raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 저장해 주세요.';end if;
 if old.id is not null and old.kind<>post_kind then raise exception '게시판 종류는 바꿀 수 없습니다.';end if;
 if post_kind='resource' and post_status='published' and source_url='' and not exists(select 1 from public.cheongla_information_files where post_id=target_post and state='ready')then raise exception '자료 파일을 첨부하거나 다운로드 주소를 입력해 주세요.';end if;
 if target_post is null then insert into public.cheongla_information_posts(kind,category,title,body,source_url,status,created_by)values(post_kind,case when post_kind='resource' then resource_category else null end,btrim(post_title),btrim(post_body),source_url,post_status,auth.uid())returning id into result;
 else update public.cheongla_information_posts set category=case when post_kind='resource' then resource_category else null end,title=btrim(post_title),body=btrim(post_body),source_url=cheongla_save_information.source_url,status=post_status,updated_at=clock_timestamp()where id=target_post returning id into result;end if;return result;
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_manage_mbti_operations()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.cheongla_profiles
 where id=(select auth.uid()) and approval_status='approved'
 and membership_state='active'
 and role in('owner','english_director','math_director'));
$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_stage_director_file(target_post uuid, object_name text, original_name text, file_size integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result uuid;
begin
 if not(cheongla_private.is_principal()and cheongla_private.can_use_member_services())then raise exception '원장만 첨부할 수 있습니다.'using errcode='42501';end if;
 if original_name is null or length(original_name)not between 1 and 255 or original_name!~*'\.(jpg|jpeg|png|webp|gif|pdf|doc|docx|ppt|pptx|xls|xlsx|hwp|hwpx|txt)$'or file_size is null or file_size not between 1 and 20971520 or split_part(object_name,'/',1)is distinct from target_post::text then raise exception '파일 종류·이름·크기를 확인해 주세요. 파일당 최대 20MB입니다.';end if;
 if not exists(select 1 from public.cheongla_director_posts where id=target_post and archived_at is null)or not exists(select 1 from storage.objects where bucket_id='cheongla-director'and name=object_name and (metadata->>'size')::bigint=file_size)then raise exception '업로드된 파일을 확인하지 못했습니다.';end if;
 insert into public.cheongla_director_files(post_id,object_path,filename,size_bytes,created_by)values(target_post,object_name,original_name,file_size,auth.uid())returning id into result;return result;
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_prepare_director_post(target_post uuid, post_category text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.cheongla_director_posts%rowtype;
begin
 if not(cheongla_private.is_principal()and cheongla_private.can_use_member_services())then raise exception '원장만 글을 작성할 수 있습니다.'using errcode='42501';end if;
 if post_category is null or post_category not in('greeting','thoughts','photos','objects','column')then raise exception '게시판을 확인해 주세요.';end if;
 perform pg_advisory_xact_lock(hashtext('director-space'),hashtext(post_category));
 if target_post is not null then select *into r from public.cheongla_director_posts where id=target_post and category=post_category and archived_at is null;
 elsif post_category='greeting'then select *into r from public.cheongla_director_posts where category='greeting'and archived_at is null;end if;
 if r.id is null then
  if target_post is not null then raise exception '글을 찾을 수 없습니다.';end if;
  insert into public.cheongla_director_posts(category,created_by,updated_by)values(post_category,auth.uid(),auth.uid())returning *into r;
 end if;return to_jsonb(r);
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_manage_season()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.cheongla_profiles p join cheongla_private.season_effect_owner o on o.profile_id=p.id where o.singleton and p.id=auth.uid() and p.role='english_director' and p.approval_status='approved' and p.membership_state='active');
$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_save_director_post(target_post uuid, post_title text, post_body text, post_state text, expected_updated_at timestamp with time zone, file_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_manage_life()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select cheongla_private.can_use_member_services()and exists(select 1 from public.cheongla_profiles where id=auth.uid()and approval_status='approved'and membership_state='active'and(role in('owner','english_director','math_director','manager')or is_app_admin));
$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_trash_director_post(target_post uuid, expected_updated_at timestamp with time zone, restore_post boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.cheongla_director_posts%rowtype;before_row jsonb;
begin
 if not(cheongla_private.is_principal()and cheongla_private.can_use_member_services())then raise exception '원장만 글을 삭제·복구할 수 있습니다.'using errcode='42501';end if;
 if restore_post is null or expected_updated_at is null then raise exception '삭제·복구할 글을 새로고침해 주세요.';end if;
 select *into r from public.cheongla_director_posts where id=target_post and category in('thoughts','photos','objects','column')for update;
 if not found or r.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 if restore_post is distinct from(r.archived_at is not null)then raise exception '휴지통 상태가 변경되었습니다. 새로고침해 주세요.';end if;
 before_row:=to_jsonb(r);
 update public.cheongla_director_posts set archived_at=case when restore_post then null else clock_timestamp()end,state=case when restore_post then 'draft'else state end,updated_at=clock_timestamp(),updated_by=auth.uid()where id=r.id returning *into r;
 insert into cheongla_private.director_post_history(post_id,actor_id,before_record,after_record)values(r.id,auth.uid(),before_row,to_jsonb(r));
 return to_jsonb(r);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_finish_director_removal(target_post uuid, target_file uuid, expected_updated_at timestamp with time zone, confirmation text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.cheongla_director_posts%rowtype;f public.cheongla_director_files%rowtype;
begin
 if not(cheongla_private.is_principal()and cheongla_private.can_use_member_services())then raise exception '원장만 삭제를 마칠 수 있습니다.'using errcode='42501';end if;
 select *into p from public.cheongla_director_posts where id=target_post and category in('thoughts','photos','objects','column')for update;
 if not found or expected_updated_at is null or p.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 새로고침 후 삭제를 다시 눌러 주세요.';end if;
 if target_file is null then
  if confirmation is distinct from '글 영구삭제'or p.archived_at is null or p.purge_requested_at is null then raise exception '영구삭제 중인 글을 확인해 주세요.';end if;
  if exists(select 1 from storage.objects where bucket_id='cheongla-director'and(split_part(name,'/',1)=p.id::text or name in(select object_path from public.cheongla_director_files where post_id=p.id)))then raise exception '실제 첨부파일 삭제가 완료되지 않았습니다. 다시 시도해 주세요.';end if;
  delete from public.cheongla_notifications where source_kind='director_post'and source_id=p.id;
  delete from cheongla_private.director_post_history where post_id=p.id;
  delete from public.cheongla_director_files where post_id=p.id;
  delete from public.cheongla_director_posts where id=p.id;
 else
  if confirmation is distinct from '첨부파일 삭제'or p.archived_at is not null or p.purge_requested_at is not null then raise exception '삭제할 첨부파일을 확인해 주세요.';end if;
  select *into f from public.cheongla_director_files where id=target_file and post_id=p.id for update;
  if not found or f.removal_requested_at is null then raise exception '삭제 요청한 첨부파일을 확인해 주세요.';end if;
  if exists(select 1 from storage.objects where bucket_id='cheongla-director'and name=f.object_path)then raise exception '실제 첨부파일 삭제가 완료되지 않았습니다. 다시 시도해 주세요.';end if;
  delete from public.cheongla_director_files where id=f.id;
  update public.cheongla_director_posts set updated_at=clock_timestamp(),updated_by=auth.uid()where id=p.id;
 end if;
 return true;
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_begin_director_removal(target_post uuid, target_file uuid, expected_updated_at timestamp with time zone, confirmation text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.cheongla_director_posts%rowtype;f public.cheongla_director_files%rowtype;paths jsonb;
begin
 if not(cheongla_private.is_principal()and cheongla_private.can_use_member_services())then raise exception '원장만 첨부파일·글을 영구삭제할 수 있습니다.'using errcode='42501';end if;
 select *into p from public.cheongla_director_posts where id=target_post and category in('thoughts','photos','objects','column')for update;
 if not found or expected_updated_at is null or p.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 if target_file is null then
  if confirmation is distinct from '글 영구삭제'or p.archived_at is null then raise exception '휴지통에 있는 글만 영구삭제할 수 있습니다.';end if;
  if p.purge_requested_at is null then
   update public.cheongla_director_posts set purge_requested_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by=auth.uid()where id=p.id returning *into p;
  end if;
  select coalesce(jsonb_agg(path order by path),'[]'::jsonb)into paths from(
   select object_path as path from public.cheongla_director_files where post_id=p.id
   union select name from storage.objects where bucket_id='cheongla-director'and split_part(name,'/',1)=p.id::text
  )x;
 else
  if confirmation is distinct from '첨부파일 삭제'or p.archived_at is not null or p.purge_requested_at is not null then raise exception '글 목록에서 삭제할 첨부파일을 확인해 주세요.';end if;
  select *into f from public.cheongla_director_files where id=target_file and post_id=p.id for update;
  if not found then raise exception '첨부파일이 변경되었습니다. 새로고침해 주세요.';end if;
  if f.removal_requested_at is null then
   update public.cheongla_director_files set removal_requested_at=clock_timestamp()where id=f.id;
   update public.cheongla_director_posts set updated_at=clock_timestamp(),updated_by=auth.uid()where id=p.id returning *into p;
  end if;
  paths:=jsonb_build_array(f.object_path);
 end if;
 return jsonb_build_object('post_id',p.id,'file_id',target_file,'updated_at',p.updated_at,'paths',paths);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_content_trash_v71()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if not cheongla_private.can_manage_life()then raise exception '원장·실장 전용 휴지통입니다.'using errcode='42501';end if;
 select coalesce(jsonb_agg(x order by x->>'deleted_at' desc),'[]')into result from(
 select jsonb_build_object('kind',r.kind,'id',r.id,'title',r.row_data->>'title','version',r.deleted_at,'deleted_at',r.deleted_at,'files','[]'::jsonb)x from cheongla_private.content_recycle r
 union all select jsonb_build_object('kind','information','purging',exists(select 1 from cheongla_private.content_purge_claims j where j.post_id=p.id),'id',p.id,'title',p.title,'version',p.updated_at,'deleted_at',p.deleted_at,'files',(select coalesce(jsonb_agg(f.object_path),'[]')from public.cheongla_information_files f where f.post_id=p.id))from public.cheongla_information_posts p where p.deleted_at is not null
 union all select jsonb_build_object('kind','board','id',p.id,'title',p.title,'version',p.updated_at,'deleted_at',p.deleted_at,'files','[]'::jsonb)from public.cheongla_board_posts p where p.deleted_at is not null
 union all select jsonb_build_object('kind','reply','id',p.id,'title',left(p.body,80),'version',p.deleted_at,'deleted_at',p.deleted_at,'files','[]'::jsonb)from public.cheongla_board_replies p where p.deleted_at is not null and exists(select 1 from public.cheongla_board_posts b where b.id=p.post_id and b.deleted_at is null)
 union all select jsonb_build_object('kind','inquiry','id',p.id,'title',p.title,'version',p.updated_at,'deleted_at',p.deleted_at,'files','[]'::jsonb)from public.cheongla_new_inquiries p where p.deleted_at is not null
 )data;
 return result;
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_intro_read(target_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.intro_pages%rowtype;
begin
 select *into r from cheongla_private.intro_pages where page_key=target_key;
 if not found then raise exception '안내 메뉴를 찾을 수 없습니다.';end if;
 return jsonb_build_object('page_key',r.page_key,'state',r.state,'updated_at',r.updated_at,'payload',case when r.state='active'or cheongla_private.is_principal()then r.payload else null end);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_prepare_content_purge(target_id uuid, expected_version timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.cheongla_information_posts%rowtype;paths jsonb;
begin
 if not cheongla_private.can_manage_life()then raise exception '원장·실장 전용입니다.'using errcode='42501';end if;
 select *into p from public.cheongla_information_posts where id=target_id for update;
 if not found or p.deleted_at is null or p.updated_at is distinct from expected_version then raise exception '휴지통이 변경되었습니다. 새로고침해 주세요.';end if;
 insert into cheongla_private.content_purge_claims(post_id,record_version)values(p.id,p.updated_at)on conflict(post_id)do nothing;
 select coalesce(jsonb_agg(f.object_path),'[]')into paths from public.cheongla_information_files f where f.post_id=p.id;
 return jsonb_build_object('id',p.id,'version',p.updated_at,'paths',paths);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_content_trash_action_v71(target_kind text, target_id uuid, trash_action text, expected_version timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.content_recycle%rowtype; tbl text; row_data jsonb; version timestamptz;
begin
 if not cheongla_private.can_manage_life()then raise exception '원장·실장 전용 휴지통입니다.'using errcode='42501';end if;
 if trash_action is null or trash_action not in('restore','purge')then raise exception '처리 방법을 확인해 주세요.';end if;
 if target_kind in('notice','schedule')then
 select *into r from cheongla_private.content_recycle where id=target_id and kind=target_kind for update;
 if not found or r.deleted_at is distinct from expected_version then raise exception '휴지통이 변경되었습니다. 새로고침해 주세요.';end if;
 if trash_action='restore'then
 if target_kind='notice'then insert into public.cheongla_notices select *from jsonb_populate_record(null::public.cheongla_notices,r.row_data||jsonb_build_object('updated_at',clock_timestamp()));
 else insert into public.cheongla_schedule_events select *from jsonb_populate_record(null::public.cheongla_schedule_events,r.row_data||jsonb_build_object('status','draft','updated_at',clock_timestamp(),'updated_by',auth.uid()));end if;
 end if;
 delete from cheongla_private.content_recycle where id=r.id;return;
 end if;
 tbl:=case target_kind when 'information'then 'cheongla_information_posts'when 'board'then 'cheongla_board_posts'when 'reply'then 'cheongla_board_replies'when 'inquiry'then 'cheongla_new_inquiries'end;
 if tbl is null then raise exception '자료 종류를 확인해 주세요.';end if;
 execute format('select to_jsonb(p)from public.%I p where id=$1 and deleted_at is not null for update',tbl)into row_data using target_id;
 version:=case when target_kind='reply'then(row_data->>'deleted_at')::timestamptz else(row_data->>'updated_at')::timestamptz end;
 if row_data is null or version is distinct from expected_version then raise exception '휴지통이 변경되었습니다. 새로고침해 주세요.';end if;
 if trash_action='restore'then
 if target_kind='reply'and not exists(select 1 from public.cheongla_board_posts where id=(row_data->>'post_id')::uuid and deleted_at is null)then raise exception '먼저 원래 질문을 복구해 주세요.';end if;
 execute format('update public.%I set deleted_at=null%s where id=$1',tbl,case when target_kind='reply'then ''when target_kind='information'then ',status=''draft'',updated_at=clock_timestamp()'else ',updated_at=clock_timestamp()'end)using target_id;
 return;
 end if;
 if target_kind='information'then
 if exists(select 1 from storage.objects o join public.cheongla_information_files f on f.object_path=o.name where o.bucket_id='cheongla-information'and f.post_id=target_id)then raise exception '첨부파일 삭제를 먼저 완료해 주세요.';end if;
 delete from public.cheongla_information_files where post_id=target_id;
 elsif target_kind='inquiry'then delete from cheongla_private.inquiry_blocks where inquiry_id=target_id;
 end if;
 if target_kind in('board','inquiry')then delete from cheongla_private.inquiry_pins where kind=case target_kind when 'inquiry'then 'new'else target_kind end and post_id=target_id;end if;
 execute format('delete from public.%I where id=$1',tbl)using target_id;
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_intro_save(target_key text, content jsonb, expected_updated_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.intro_pages%rowtype;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 소개 내용을 수정할 수 있습니다.'using errcode='42501';end if;
 if jsonb_typeof(content)is distinct from'object'or length(trim(coalesce(content->>'title','')))not between 1 and 200 or octet_length(content::text)>250000 then raise exception '제목과 안내 내용을 확인해 주세요.';end if;
 select *into r from cheongla_private.intro_pages where page_key=target_key for update;
 if not found or r.updated_at is distinct from expected_updated_at or r.state not in('active','purged')then raise exception '다른 화면에서 변경되었거나 삭제된 안내입니다. 다시 불러와 주세요.';end if;
 update cheongla_private.intro_pages set payload=content,state='active',updated_at=clock_timestamp(),updated_by=auth.uid()where page_key=target_key returning *into r;
 return jsonb_build_object('page_key',r.page_key,'state',r.state,'updated_at',r.updated_at,'payload',r.payload);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_intro_action(target_key text, page_action text, expected_updated_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.intro_pages%rowtype;paths jsonb;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 소개 휴지통을 관리할 수 있습니다.'using errcode='42501';end if;
 select *into r from cheongla_private.intro_pages where page_key=target_key for update;
 if not found or r.updated_at is distinct from expected_updated_at then raise exception '다른 화면에서 변경되었습니다. 새로고침해 주세요.';end if;
 if page_action='archive'and r.state='active'then r.state:='deleted';
 elsif page_action='restore'and r.state='deleted'then r.state:='active';
 elsif page_action='prepare_purge'and r.state in('deleted','purging')then r.state:='purging';
 elsif page_action='finish_purge'and r.state='purging'then
 if exists(select 1 from storage.objects o where o.bucket_id='cheongla-intro'and o.name like target_key||'/%')then raise exception '사진 파일 삭제를 먼저 완료해 주세요.';end if;
 r.state:='purged';r.payload:='{}'::jsonb;
 else raise exception '현재 안내의 상태와 처리 방법을 확인해 주세요.';end if;
 update cheongla_private.intro_pages set state=r.state,payload=r.payload,updated_at=clock_timestamp(),updated_by=auth.uid()where page_key=target_key returning *into r;
 select coalesce(jsonb_agg(name),'[]')into paths from storage.objects where bucket_id='cheongla-intro'and name like target_key||'/%';
 return jsonb_build_object('page_key',r.page_key,'state',r.state,'payload',r.payload,'updated_at',r.updated_at,'paths',case when r.state='purging'then paths else '[]'::jsonb end);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_intro_trash()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 if not cheongla_private.is_principal()then raise exception '원장 전용 휴지통입니다.'using errcode='42501';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('page_key',page_key,'state',state,'updated_at',updated_at,'payload',payload)order by updated_at desc),'[]')from cheongla_private.intro_pages where state in('deleted','purging'));
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_prepare_notice_purge(target_id uuid, expected_version timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.content_recycle%rowtype;paths jsonb;
begin
 if auth.uid()is null or not cheongla_private.can_manage_life()then raise exception '휴지통 관리 권한이 없습니다.'using errcode='42501';end if;
 select *into r from cheongla_private.content_recycle where id=target_id and kind='notice'for update;
 if not found or r.deleted_at is distinct from expected_version then raise exception '휴지통이 변경되었습니다.';end if;
 insert into cheongla_private.notice_file_purge_claims values(r.source_id,r.deleted_at)on conflict(post_id)do nothing;
 select coalesce(jsonb_agg(object_path),'[]')into paths from public.cheongla_notice_files where post_id=r.source_id;return jsonb_build_object('id',r.id,'post_id',r.source_id,'version',r.deleted_at,'paths',paths);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_content_trash_action(target_kind text, target_id uuid, trash_action text, expected_version timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_manage_home_features()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved'
      and membership_state = 'active' and role in ('owner', 'english_director', 'math_director')
  );
$function$
;
