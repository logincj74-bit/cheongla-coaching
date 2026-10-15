begin;
do $$declare mg uuid;st uuid;post uuid;draft uuid;r jsonb;v timestamptz;f uuid;
begin
select id into mg from public.cheongla_profiles where role='manager'and approval_status='approved'and membership_state='active'limit 1;
select id into st from public.cheongla_profiles where role='student'and approval_status='approved'and membership_state='active'limit 1;
if mg is null or st is null then raise exception '검증용 계정 없음';end if;
perform set_config('request.jwt.claim.sub',mg::text,true);
post:=public.cheongla_save_information(null,'resource','검증용 첨부 자료','공개·초안·파일 권한 검증','forms','','draft',null);
draft:=public.cheongla_save_information(null,'news','검증용 비공개 초안','비공개 초안',null,'','draft',null);
select updated_at into v from public.cheongla_information_posts where id=post;
begin perform public.cheongla_save_information(post,'resource','검증용 첨부 자료','파일 없는 공개 차단','forms','','published',v);raise exception 'FAIL empty resource publication';exception when raise_exception then if sqlerrm='FAIL empty resource publication'then raise;end if;end;
begin perform public.cheongla_reserve_information_file(post,'test.exe',100);raise exception 'FAIL executable';exception when raise_exception then if sqlerrm='FAIL executable'then raise;end if;end;
begin perform public.cheongla_reserve_information_file(post,'large.pdf',20971521);raise exception 'FAIL oversized';exception when raise_exception then if sqlerrm='FAIL oversized'then raise;end if;end;
r:=public.cheongla_reserve_information_file(post,'검증.pdf',100);f:=(r->>'id')::uuid;
begin perform public.cheongla_finish_information_file(f);raise exception 'FAIL missing object';exception when raise_exception then if sqlerrm='FAIL missing object'then raise;end if;end;
perform set_config('test.publication_post',post::text,true);perform set_config('test.publication_draft',draft::text,true);perform set_config('test.publication_file',f::text,true);perform set_config('test.publication_path',r->>'path',true);perform set_config('test.publication_manager',mg::text,true);perform set_config('test.publication_student',st::text,true);
end;$$;
set local role authenticated;
-- The storage insert uses the exact uploader policy used by the Storage API.
insert into storage.objects(bucket_id,name,metadata)values('cheongla-information',current_setting('test.publication_path'),'{"size":100,"mimetype":"application/pdf"}');
select public.cheongla_finish_information_file(current_setting('test.publication_file')::uuid);
do $$declare v timestamptz;post uuid:=current_setting('test.publication_post')::uuid;
begin
select updated_at into v from public.cheongla_information_posts where id=post;
perform public.cheongla_save_information(post,'resource','검증용 첨부 자료','파일 완료 후 공개','forms','','published',v);
begin perform public.cheongla_save_information(post,'resource','오래된 수정','충돌 차단','forms','','draft',v);raise exception 'FAIL concurrent edit';exception when raise_exception then if sqlerrm='FAIL concurrent edit'then raise;end if;end;
end;$$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$begin
if not exists(select 1 from public.cheongla_information_posts where id=current_setting('test.publication_post')::uuid)then raise exception 'FAIL anonymous public read';end if;
if exists(select 1 from public.cheongla_information_posts where id=current_setting('test.publication_draft')::uuid)then raise exception 'FAIL anonymous draft leak';end if;
if not exists(select 1 from public.cheongla_information_files where id=current_setting('test.publication_file')::uuid and state='ready')then raise exception 'FAIL anonymous ready file metadata';end if;
if not exists(select 1 from storage.objects where bucket_id='cheongla-information'and name=current_setting('test.publication_path'))then raise exception 'FAIL anonymous file download';end if;
begin perform public.cheongla_save_information(null,'news','권한 차단','비회원 작성 차단',null,'','draft',null);raise exception 'FAIL anonymous write';exception when insufficient_privilege then null;end;
end;$$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('test.publication_student'),true);
set local role authenticated;
do $$begin
begin perform public.cheongla_save_information(null,'news','학생 작성 차단','권한 검증',null,'','draft',null);raise exception 'FAIL student write';exception when insufficient_privilege then null;end;
begin perform public.cheongla_reserve_information_file(current_setting('test.publication_post')::uuid,'학생.pdf',100);raise exception 'FAIL student upload';exception when insufficient_privilege then null;end;
begin insert into storage.objects(bucket_id,name,metadata)values('cheongla-information','unauthorized.pdf','{"size":100}');raise exception 'FAIL storage bypass';exception when insufficient_privilege then null;end;
end;$$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('test.publication_manager'),true);
set local role authenticated;
do $$declare v timestamptz;post uuid:=current_setting('test.publication_post')::uuid;
begin select updated_at into v from public.cheongla_information_posts where id=post;perform public.cheongla_set_information_deleted(post,true,v);end;$$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$begin
if exists(select 1 from public.cheongla_information_posts where id=current_setting('test.publication_post')::uuid)then raise exception 'FAIL deleted post leak';end if;
if exists(select 1 from storage.objects where bucket_id='cheongla-information'and name=current_setting('test.publication_path'))then raise exception 'FAIL removed post file access';end if;
end;$$;
reset role;
rollback;
select 'PASS: 비회원 공개 글·첨부 조회, 초안·삭제글 차단, 실장 글 작성·업로드·게시, 업로드 완료 검증, 용량·확장자 제한, 학생·비회원 작성 및 업로드 차단, 동시 수정 보호. 실제 게시물·파일 변경은 전부 롤백.' as result;
