-- 001~006 실행 후 실행하세요. 기존 질문과 답변은 유지합니다.
begin;
create table if not exists public.cheongla_qa_messages(
 id uuid primary key default gen_random_uuid(),question_id uuid not null references public.cheongla_questions(id),
 author_id uuid not null references public.cheongla_profiles(id),author_name text not null,
 author_role text not null,body text not null check(char_length(btrim(body)) between 1 and 10000),
 created_at timestamptz not null default now()
);
create index if not exists cheongla_qa_messages_order_idx on public.cheongla_qa_messages(question_id,created_at desc,id desc);
alter table public.cheongla_qa_messages enable row level security;
revoke all on public.cheongla_qa_messages from public,anon,authenticated;
grant select on public.cheongla_qa_messages to authenticated;
grant insert(question_id,body) on public.cheongla_qa_messages to authenticated;
create or replace function cheongla_private.prepare_qa_message()
returns trigger language plpgsql security definer set search_path='' as $$
declare q public.cheongla_questions%rowtype;p public.cheongla_profiles%rowtype;
begin
 select * into q from public.cheongla_questions where id=new.question_id;
 if not found then raise exception '질문이 없습니다.' using errcode='P0002';end if;
 select * into p from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved';
 if not found or not ((p.role='student' and p.id=q.student_id) or cheongla_private.can_answer_question(q.subject)) then
 raise exception '본인 질문의 학생 또는 담당 선생님만 대화할 수 있습니다.' using errcode='42501';end if;
 new.author_id=p.id;new.author_name=p.full_name;new.author_role=p.role;new.created_at=clock_timestamp();return new;
end;
$$;
revoke all on function cheongla_private.prepare_qa_message() from public,anon,authenticated;
drop trigger if exists cheongla_prepare_qa_message on public.cheongla_qa_messages;
create trigger cheongla_prepare_qa_message before insert on public.cheongla_qa_messages
for each row execute function cheongla_private.prepare_qa_message();
drop policy if exists cheongla_qa_message_read on public.cheongla_qa_messages;
create policy cheongla_qa_message_read on public.cheongla_qa_messages for select to authenticated
using(exists(select 1 from public.cheongla_questions q where q.id=question_id and cheongla_private.can_read_question(q.student_id,q.subject)));
drop policy if exists cheongla_qa_message_create on public.cheongla_qa_messages;
create policy cheongla_qa_message_create on public.cheongla_qa_messages for insert to authenticated
with check(author_id=(select auth.uid()) and exists(select 1 from public.cheongla_questions q where q.id=question_id
 and ((q.student_id=(select auth.uid())) or cheongla_private.can_answer_question(q.subject))));
create or replace view public.cheongla_qa_latest with(security_invoker=true) as
select distinct on(question_id) question_id,author_role,created_at from public.cheongla_qa_messages order by question_id,created_at desc,id desc;
revoke all on public.cheongla_qa_latest from public,anon,authenticated;
grant select on public.cheongla_qa_latest to authenticated;

create table if not exists public.cheongla_qa_photos(
 id uuid primary key default gen_random_uuid(),question_id uuid not null references public.cheongla_questions(id),
 uploader_id uuid not null references public.cheongla_profiles(id),object_path text not null unique,
 size_bytes bigint not null check(size_bytes between 1 and 1048576),
 status text not null default 'pending' check(status in ('pending','ready')),created_at timestamptz not null default now()
);
create index if not exists cheongla_qa_photos_question_idx on public.cheongla_qa_photos(question_id);
alter table public.cheongla_qa_photos enable row level security;
revoke all on public.cheongla_qa_photos from public,anon,authenticated;
grant select on public.cheongla_qa_photos to authenticated;
drop policy if exists cheongla_qa_photo_read on public.cheongla_qa_photos;
create policy cheongla_qa_photo_read on public.cheongla_qa_photos for select to authenticated
using(exists(select 1 from public.cheongla_questions q where q.id=question_id and cheongla_private.can_read_question(q.student_id,q.subject)
 and (status='ready' or uploader_id=(select auth.uid()) or cheongla_private.is_app_admin())));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('cheongla-qa-photos','cheongla-qa-photos',false,1048576,array['image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=1048576,allowed_mime_types=array['image/jpeg'];

create or replace function public.cheongla_reserve_photo(target_question uuid,photo_bytes bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.cheongla_questions%rowtype;photo_id uuid=gen_random_uuid();path text;
begin
 perform pg_catalog.pg_advisory_xact_lock(7492053);
 select * into q from public.cheongla_questions where id=target_question;
 if not found or q.student_id is distinct from (select auth.uid()) or not exists(select 1 from public.cheongla_profiles p
 where p.id=(select auth.uid()) and p.role='student' and p.approval_status='approved') then
 raise exception '승인된 학생이 본인 질문에만 사진을 첨부할 수 있습니다.' using errcode='42501';end if;
 if photo_bytes is null or photo_bytes not between 1 and 1048576 then raise exception '사진은 1MB 이하로 첨부해 주세요.' using errcode='22023';end if;
 if (select count(*) from public.cheongla_qa_photos where question_id=q.id)>=3 then
 raise exception '한 질문에 사진은 최대 3장입니다.' using errcode='22023';end if;
 if coalesce((select sum(case when status='pending' then 1048576 else size_bytes end) from public.cheongla_qa_photos),0)+1048576>838860800 then
 raise exception '사진 보관 한도에 도달했습니다. 사진 없이 질문하거나 관리자에게 사진 정리를 요청해 주세요.' using errcode='53100';end if;
 path=q.student_id::text||'/'||q.id::text||'/'||photo_id::text||'.jpg';
 insert into public.cheongla_qa_photos(id,question_id,uploader_id,object_path,size_bytes) values(photo_id,q.id,q.student_id,path,photo_bytes);
 return jsonb_build_object('id',photo_id,'object_path',path);
end;
$$;
create or replace function cheongla_private.can_use_photo(path text,operation text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_qa_photos a join public.cheongla_questions q on q.id=a.question_id
 join public.cheongla_profiles p on p.id=(select auth.uid()) where a.object_path=path and p.approval_status='approved'
 and case operation
 when 'read' then cheongla_private.can_read_question(q.student_id,q.subject) and (a.status='ready' or a.uploader_id=p.id or p.is_app_admin)
 when 'upload' then a.status='pending' and a.uploader_id=p.id and p.role='student' and q.student_id=p.id
 when 'delete' then p.is_app_admin or (a.uploader_id=p.id and p.role='student' and q.student_id=p.id)
 else false end);
$$;
revoke all on function cheongla_private.can_use_photo(text,text) from public,anon,authenticated;
grant execute on function cheongla_private.can_use_photo(text,text) to authenticated;
drop policy if exists cheongla_qa_storage_read on storage.objects;
create policy cheongla_qa_storage_read on storage.objects for select to authenticated
using(bucket_id='cheongla-qa-photos' and cheongla_private.can_use_photo(name,'read'));
drop policy if exists cheongla_qa_storage_upload on storage.objects;
create policy cheongla_qa_storage_upload on storage.objects for insert to authenticated
with check(bucket_id='cheongla-qa-photos' and cheongla_private.can_use_photo(name,'upload'));
drop policy if exists cheongla_qa_storage_delete on storage.objects;
create policy cheongla_qa_storage_delete on storage.objects for delete to authenticated
using(bucket_id='cheongla-qa-photos' and cheongla_private.can_use_photo(name,'delete'));

create or replace function public.cheongla_finish_photo(target_photo uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.cheongla_qa_photos%rowtype;actual_size bigint;
begin
 perform pg_catalog.pg_advisory_xact_lock(7492053);
 select * into a from public.cheongla_qa_photos where id=target_photo for update;
 if not found or not cheongla_private.can_use_photo(a.object_path,'upload') then raise exception '첨부 권한을 확인해 주세요.' using errcode='42501';end if;
 select (o.metadata->>'size')::bigint into actual_size from storage.objects o
 where o.bucket_id='cheongla-qa-photos' and o.name=a.object_path and o.metadata->>'mimetype'='image/jpeg';
 if actual_size is null or actual_size<>a.size_bytes then raise exception '사진 업로드 크기를 확인하지 못했습니다.' using errcode='22023';end if;
 update public.cheongla_qa_photos set status='ready' where id=a.id;return a.id;
end;
$$;
create or replace function public.cheongla_remove_photo_record(target_photo uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.cheongla_qa_photos%rowtype;
begin
 perform pg_catalog.pg_advisory_xact_lock(7492053);
 select * into a from public.cheongla_qa_photos where id=target_photo for update;
 if not found or not cheongla_private.can_use_photo(a.object_path,'delete') then raise exception '삭제 권한을 확인해 주세요.' using errcode='42501';end if;
 if exists(select 1 from storage.objects o where o.bucket_id='cheongla-qa-photos' and o.name=a.object_path) then
 raise exception '사진 파일을 먼저 삭제해 주세요.' using errcode='22023';end if;
 delete from public.cheongla_qa_photos where id=a.id;return a.id;
end;
$$;
create or replace function public.cheongla_photo_usage()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not cheongla_private.is_app_admin() then raise exception '앱 관리자만 용량을 확인할 수 있습니다.' using errcode='42501';end if;
 return jsonb_build_object('used_bytes',coalesce((select sum((metadata->>'size')::bigint) from storage.objects where bucket_id='cheongla-qa-photos'),0),
 'reserved_bytes',coalesce((select sum(case when status='pending' then 1048576 else size_bytes end) from public.cheongla_qa_photos),0),'cap_bytes',838860800,
 'photo_count',(select count(*) from public.cheongla_qa_photos where status='ready'));
end;
$$;
revoke all on function public.cheongla_reserve_photo(uuid,bigint),public.cheongla_finish_photo(uuid),public.cheongla_remove_photo_record(uuid),public.cheongla_photo_usage() from public,anon,authenticated;
grant execute on function public.cheongla_reserve_photo(uuid,bigint),public.cheongla_finish_photo(uuid),public.cheongla_remove_photo_record(uuid),public.cheongla_photo_usage() to authenticated;
notify pgrst,'reload schema';
commit;
