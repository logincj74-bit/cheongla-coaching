begin;
do $$declare u uuid;k int;begin
 for k in 1..3 loop
 u:=('07700000-0000-4000-8000-'||lpad(k::text,12,'0'))::uuid;
 insert into auth.users(id,email,raw_user_meta_data)values(u,'news-files-test-'||k||'@example.invalid',jsonb_build_object('full_name','첨부 검증','contact_phone','0100000070'||k));
 update public.cheongla_profiles set role=case when k=1 then 'english_director'when k=2 then 'student'else 'manager'end,approval_status='approved'where id=u;
 end loop;
end;$$;
select set_config('request.jwt.claim.sub','07700000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$declare pid uuid:=gen_random_uuid();f jsonb;v timestamptz;j jsonb;rid uuid;begin
 f:=public.cheongla_reserve_notice_file(pid,'검증.pdf',12,'director');
 insert into storage.objects(bucket_id,name,metadata)values('cheongla-notices',f->>'path','{"size":12}');
 perform public.cheongla_save_notice_files(pid,'첨부 검증','안내','student',false,'director',null,array[(f->>'id')::uuid],array[]::uuid[]);
 if not cheongla_private.notice_file_access(f->>'path','read')then raise exception 'director read denied';end if;
 select updated_at into v from public.cheongla_notices where id=pid;
 begin perform public.cheongla_save_notice_files(pid,'충돌','안내','student',false,'director',null,array[]::uuid[],array[]::uuid[]);raise exception 'conflict accepted';exception when raise_exception then if sqlerrm='conflict accepted'then raise;end if;end;
 perform public.cheongla_save_notice_files(pid,'수정','안내 수정','student',false,'director',v,array[]::uuid[],array[]::uuid[]);
 delete from public.cheongla_notices where id=pid;
 if cheongla_private.notice_file_access(f->>'path','read')then raise exception 'trashed file readable';end if;
 select id,deleted_at into rid,v from cheongla_private.content_recycle where source_id=pid and kind='notice';
 perform public.cheongla_content_trash_action('notice',rid,'restore',v);
 if not cheongla_private.notice_file_access(f->>'path','read')then raise exception 'restored file absent';end if;
 delete from public.cheongla_notices where id=pid;select id,deleted_at into rid,v from cheongla_private.content_recycle where source_id=pid and kind='notice';
 j:=public.cheongla_prepare_notice_purge(rid,v);if jsonb_array_length(j->'paths')<>1 then raise exception 'purge paths missing';end if;
 begin perform public.cheongla_content_trash_action('notice',rid,'purge',v);raise exception 'purge accepted before storage';exception when raise_exception then if sqlerrm='purge accepted before storage'then raise;end if;end;
 if not cheongla_private.notice_file_access(f->>'path','purge')then raise exception 'purge permission missing';end if;
 perform set_config('storage.allow_delete_query','true',true);delete from storage.objects where bucket_id='cheongla-notices'and name=f->>'path';perform public.cheongla_content_trash_action('notice',rid,'purge',v);
 if exists(select 1 from public.cheongla_notice_files where post_id=pid)then raise exception 'file metadata survived purge';end if;
 -- Existing news supports photos, staged deletion and post recycling.
 pid:=public.cheongla_save_information(null,'news','뉴스 첨부','본문',null,'','draft',null);
 f:=public.cheongla_reserve_information_file(pid,'검증.png',12);insert into storage.objects(bucket_id,name,metadata)values('cheongla-information',f->>'path','{"size":12}');perform public.cheongla_finish_information_file((f->>'id')::uuid);
 select updated_at into v from public.cheongla_information_posts where id=pid;perform public.cheongla_save_information(pid,'news','뉴스 첨부 수정','본문',null,'','published',v);
 select updated_at into v from public.cheongla_information_posts where id=pid;perform public.cheongla_set_information_deleted(pid,true,v);
 select updated_at into v from public.cheongla_information_posts where id=pid;perform public.cheongla_content_trash_action('information',pid,'restore',v);
 if not exists(select 1 from public.cheongla_information_files where post_id=pid and state='ready')then raise exception 'news restore file missing';end if;
end;$$;
select set_config('request.jwt.claim.sub','07700000-0000-4000-8000-000000000002',true);
do $$begin
 begin perform public.cheongla_reserve_notice_file(gen_random_uuid(),'x.pdf',12,'director');raise exception 'student upload allowed';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.cheongla_save_notice_files(uuid,text,text,text,boolean,text,timestamptz,uuid[],uuid[])','execute')then raise exception 'anonymous mutation granted';end if;
end;$$;
select set_config('request.jwt.claim.sub','07700000-0000-4000-8000-000000000003',true);
do $$begin
 begin perform public.cheongla_reserve_notice_file(gen_random_uuid(),'x.pdf',12,'director');raise exception 'manager director upload allowed';exception when insufficient_privilege then null;end;
end;$$;
select 'PASS notice attachments save conflict trash restore purge and news photos; student and manager permissions' as result;
rollback;
