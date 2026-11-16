-- Revised introduction, six-group and parent documents. Existing records remain intact.
create table cheongla_private.mbti_articles (
 code text primary key check(code in('intro_learning','intro_letter','groups','parent_overview','parent_sj','parent_sp','parent_nf','parent_nt')),
 content jsonb,
 revision integer not null default 1,
 archived_at timestamptz,
 purged_at timestamptz,
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid,
 check(content is null or jsonb_typeof(content)='object'),
 check((content is null)=(purged_at is not null))
);
alter table cheongla_private.mbti_articles enable row level security;
revoke all on cheongla_private.mbti_articles from public,anon,authenticated;

create function public.cheongla_mbti_articles_list()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_mbti_operations() then raise insufficient_privilege;end if;
 return coalesce((select jsonb_agg(jsonb_build_object('code',code,'content',content,'revision',revision,'archived_at',archived_at,'purged_at',purged_at) order by code) from cheongla_private.mbti_articles),'[]');
end;$$;

create function public.cheongla_mbti_articles_save(target_code text,section_id integer,document_title text,document_frontmatter text,section_title text,section_body text,expected_revision integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r cheongla_private.mbti_articles%rowtype;part jsonb;
begin
 if not cheongla_private.can_manage_mbti_operations() then raise insufficient_privilege;end if;
 if section_id is null or section_id not between 1 and 30 or document_title is null or length(btrim(document_title))not between 1 and 200
 or document_frontmatter is null or length(document_frontmatter)>10000 or section_title is null or length(btrim(section_title))not between 1 and 200
 or section_body is null or length(btrim(section_body))not between 1 and 60000 then raise exception '제목과 항목 본문을 확인해 주세요.';end if;
 perform pg_advisory_xact_lock(hashtext('cheongla_mbti_articles'));
 select *into r from cheongla_private.mbti_articles where code=target_code for update;
 if not found or r.revision is distinct from expected_revision then raise exception '다른 원장·실장이 내용을 변경했습니다. 작성 내용을 복사해 둔 뒤 새로고침해 주세요.';end if;
 if r.archived_at is not null or r.purged_at is not null then raise exception '휴지통 또는 삭제된 문서는 수정할 수 없습니다.';end if;
 part:=r.content->'sections'->(section_id-1);
  if part is null or (part->>'id')::integer is distinct from section_id then raise exception '항목을 찾을 수 없습니다.';end if;
 if part->>'archived_at' is not null or part->>'purged_at' is not null then raise exception '휴지통 또는 삭제된 항목은 수정할 수 없습니다.';end if;
 part:=part||jsonb_build_object('title',btrim(section_title),'body',btrim(section_body));
 update cheongla_private.mbti_articles set content=jsonb_set(content||jsonb_build_object('title',btrim(document_title),'frontmatter',document_frontmatter),array['sections',(section_id-1)::text],part),revision=revision+1,updated_at=clock_timestamp(),updated_by=auth.uid() where code=target_code returning *into r;
 return jsonb_build_object('code',r.code,'content',r.content,'revision',r.revision,'archived_at',r.archived_at,'purged_at',r.purged_at);
end;$$;

create function public.cheongla_mbti_articles_action(target_code text,operation text,expected_revision integer,section_id integer default null)
returns void language plpgsql security definer set search_path='' as $$
declare r cheongla_private.mbti_articles%rowtype;part jsonb;
begin
 if not cheongla_private.can_manage_mbti_operations() then raise insufficient_privilege;end if;
 if operation is null or operation not in('archive','restore','purge') or(section_id is not null and section_id not between 1 and 30)then raise exception '작업을 확인해 주세요.';end if;
 perform pg_advisory_xact_lock(hashtext('cheongla_mbti_articles'));
 select *into r from cheongla_private.mbti_articles where code=target_code for update;
 if not found or r.revision is distinct from expected_revision then raise exception '문서가 변경되었습니다. 새로고침 후 다시 시도해 주세요.';end if;
 if r.purged_at is not null then raise exception '영구삭제된 문서입니다.';end if;
 if section_id is null then
  if operation='archive'and r.archived_at is null then update cheongla_private.mbti_articles set archived_at=clock_timestamp()where code=target_code;
  elsif operation='restore'and r.archived_at is not null then update cheongla_private.mbti_articles set archived_at=null where code=target_code;
  elsif operation='purge'and r.archived_at is not null then update cheongla_private.mbti_articles set content=null,archived_at=null,purged_at=clock_timestamp()where code=target_code;
  else raise exception '먼저 문서 상태를 확인해 주세요.';end if;
 else
  if r.archived_at is not null then raise exception '문서를 복원한 뒤 항목을 처리해 주세요.';end if;
  part:=r.content->'sections'->(section_id-1);
  if part is null or (part->>'id')::integer is distinct from section_id then raise exception '항목을 찾을 수 없습니다.';end if;
  if part->>'purged_at' is not null then raise exception '영구삭제된 항목입니다.';end if;
  if operation='archive'and part->>'archived_at' is null then part:=part||jsonb_build_object('archived_at',clock_timestamp());
  elsif operation='restore'and part->>'archived_at' is not null then part:=part-'archived_at';
  elsif operation='purge'and part->>'archived_at' is not null then part:=(part-'archived_at')||jsonb_build_object('title','삭제된 항목','body',null,'purged_at',clock_timestamp());
  else raise exception '먼저 항목 상태를 확인해 주세요.';end if;
  update cheongla_private.mbti_articles set content=jsonb_set(content,array['sections',(section_id-1)::text],part)where code=target_code;
 end if;
 update cheongla_private.mbti_articles set revision=revision+1,updated_at=clock_timestamp(),updated_by=auth.uid()where code=target_code;
end;$$;

create function public.cheongla_mbti_articles_empty_trash(expected_items jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare actual jsonb;normalized jsonb;r cheongla_private.mbti_articles%rowtype;parts jsonb;
begin
 if not cheongla_private.can_manage_mbti_operations() then raise insufficient_privilege;end if;
 if jsonb_typeof(expected_items)is distinct from 'array' then raise exception '휴지통 목록을 다시 확인해 주세요.';end if;
 perform pg_advisory_xact_lock(hashtext('cheongla_mbti_articles'));
 select coalesce(jsonb_agg(jsonb_build_object('code',code,'revision',revision)order by code),'[]')into actual from cheongla_private.mbti_articles
 where purged_at is null and(archived_at is not null or exists(select 1 from jsonb_array_elements(content->'sections')s where s->>'archived_at'is not null));
 select coalesce(jsonb_agg(jsonb_build_object('code',v->>'code','revision',(v->>'revision')::integer)order by v->>'code'),'[]')into normalized from jsonb_array_elements(expected_items)v;
 if actual is distinct from normalized then raise exception '휴지통 내용이 변경되었습니다. 다시 확인한 뒤 비워 주세요.';end if;
 for r in select *from cheongla_private.mbti_articles where code in(select v->>'code'from jsonb_array_elements(actual)v)order by code for update loop
  if r.archived_at is not null then update cheongla_private.mbti_articles set content=null,archived_at=null,purged_at=clock_timestamp()where code=r.code;
  else
   select jsonb_agg(case when s->>'archived_at'is not null then(s-'archived_at')||jsonb_build_object('title','삭제된 항목','body',null,'purged_at',clock_timestamp())else s end order by ord)into parts from jsonb_array_elements(r.content->'sections')with ordinality e(s,ord);
   update cheongla_private.mbti_articles set content=jsonb_set(content,'{sections}',parts)where code=r.code;
  end if;
  update cheongla_private.mbti_articles set revision=revision+1,updated_at=clock_timestamp(),updated_by=auth.uid()where code=r.code;
 end loop;
end;$$;
revoke all on function public.cheongla_mbti_articles_list()from public,anon;
revoke all on function public.cheongla_mbti_articles_save(text,integer,text,text,text,text,integer)from public,anon;
revoke all on function public.cheongla_mbti_articles_action(text,text,integer,integer)from public,anon;
revoke all on function public.cheongla_mbti_articles_empty_trash(jsonb)from public,anon;
grant execute on function public.cheongla_mbti_articles_list()to authenticated;
grant execute on function public.cheongla_mbti_articles_save(text,integer,text,text,text,text,integer)to authenticated;
grant execute on function public.cheongla_mbti_articles_action(text,text,integer,integer)to authenticated;
grant execute on function public.cheongla_mbti_articles_empty_trash(jsonb)to authenticated;
