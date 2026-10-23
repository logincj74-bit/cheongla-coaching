-- Add learning subjects; retain unclassified learning materials as common.
begin;
alter table public.cheongla_information_posts
 drop constraint cheongla_information_posts_category_check;
alter table public.cheongla_information_posts
 add constraint cheongla_information_posts_category_check
 check(category in ('admissions','past_papers','learning_materials','learning_materials_korean','learning_materials_math','learning_materials_english','learning_materials_exploration','forms'));

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
end;$function$;

commit;

