create function cheongla_private.can_manage_mbti_operations()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved' and membership_state = 'active'
      and role in ('owner','english_director','math_director','manager'));
$$;
revoke all on function cheongla_private.can_manage_mbti_operations() from public, anon, authenticated;
grant execute on function cheongla_private.can_manage_mbti_operations() to authenticated;

create table public.cheongla_mbti_operation_references (
  mbti text primary key check (mbti ~ '^[IE][NS][TF][JP]$'),
  sections jsonb not null check (jsonb_typeof(sections) = 'array')
);
alter table public.cheongla_mbti_operation_references enable row level security;
revoke all on public.cheongla_mbti_operation_references from public, anon, authenticated;
grant select on public.cheongla_mbti_operation_references to authenticated;
create policy mbti_operation_reference_staff on public.cheongla_mbti_operation_references
  for select to authenticated using ((select cheongla_private.can_manage_mbti_operations()));

insert into public.cheongla_mbti_operation_references(mbti, sections)
  select mbti, guide->'coaching' from public.cheongla_mbti_guides
  where jsonb_typeof(guide->'coaching') = 'array';
update public.cheongla_mbti_guides set guide = guide - 'coaching' where guide ? 'coaching';
alter table public.cheongla_mbti_guides
  add constraint mbti_public_guide_excludes_operations check (not (guide ? 'coaching'));

create table public.cheongla_mbti_prescriptions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.cheongla_profiles(id) on delete cascade,
  mbti text not null check (mbti ~ '^[IE][NS][TF][JP]$'),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null check (char_length(btrim(body)) between 1 and 20000),
  archived_at timestamptz,
  revision integer not null default 1
);
create unique index mbti_one_current_prescription_per_student_type
  on public.cheongla_mbti_prescriptions (student_id, mbti) where archived_at is null;
alter table public.cheongla_mbti_prescriptions enable row level security;
revoke all on public.cheongla_mbti_prescriptions from public, anon, authenticated;
grant select, delete on public.cheongla_mbti_prescriptions to authenticated;
grant insert(student_id, mbti, title, body), update(title, body, archived_at)
  on public.cheongla_mbti_prescriptions to authenticated;
create policy mbti_prescription_staff on public.cheongla_mbti_prescriptions for all to authenticated
  using ((select cheongla_private.can_manage_mbti_operations()))
  with check ((select cheongla_private.can_manage_mbti_operations()));
create policy mbti_prescription_trash_only on public.cheongla_mbti_prescriptions as restrictive
  for delete to authenticated using (archived_at is not null);

create function cheongla_private.set_mbti_prescription_revision()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    new.revision := old.revision + 1;
  elsif not exists (select 1 from public.cheongla_profiles where id = new.student_id
    and role = 'student' and approval_status = 'approved' and membership_state = 'active') then
    raise exception '승인된 재원생을 선택해 주세요.';
  end if;
  return new;
end;
$$;
revoke all on function cheongla_private.set_mbti_prescription_revision() from public, anon, authenticated;
create trigger mbti_prescription_revision before insert or update on public.cheongla_mbti_prescriptions
  for each row execute function cheongla_private.set_mbti_prescription_revision();

create function public.cheongla_mbti_operation_students()
returns table (id uuid, full_name text) language plpgsql stable security definer set search_path = ''
as $$
begin
  if not cheongla_private.can_manage_mbti_operations() then raise insufficient_privilege; end if;
  return query select p.id, p.full_name from public.cheongla_profiles p
    where p.role = 'student' and p.approval_status = 'approved' and p.membership_state = 'active'
    order by p.full_name, p.id;
end;
$$;
revoke all on function public.cheongla_mbti_operation_students() from public, anon, authenticated;
grant execute on function public.cheongla_mbti_operation_students() to authenticated;

create or replace function public.cheongla_save_mbti_guide(selected_mbti text,guide_content jsonb,expected_updated_at timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare previous public.cheongla_mbti_guides%rowtype;saved public.cheongla_mbti_guides%rowtype;field text;item jsonb;
begin
 if not(cheongla_private.is_principal()and cheongla_private.can_use_member_services())then
  raise exception '학습법 수정은 승인된 원장만 가능합니다.'using errcode='42501';
 end if;
 if selected_mbti is null or selected_mbti!~'^[IE][NS][TF][JP]$'or guide_content is null or jsonb_typeof(guide_content)<>'object'or octet_length(guide_content::text)>250000 then
  raise exception '유형과 학습법 내용을 확인해 주세요.';
 end if;
 if jsonb_typeof(guide_content->'title')is distinct from 'string'or length(trim(guide_content->>'title'))not between 1 and 200
 or jsonb_typeof(guide_content->'subtitle')is distinct from 'string'or length(guide_content->>'subtitle')>500
 or jsonb_typeof(guide_content->'subjects')is distinct from 'object'
 or jsonb_typeof(guide_content->'groupIntroductions')is distinct from 'object' then raise exception '제목·소개·과목별 자료를 확인해 주세요.';end if;
 foreach field in array array['overview'] loop
  if jsonb_typeof(guide_content->field)is distinct from 'array'then raise exception '유형 이해 내용을 확인해 주세요.';end if;
  if jsonb_array_length(guide_content->field)not between 1 and 30 then raise exception '학습법 항목 수를 확인해 주세요.';end if;
  for item in select value from jsonb_array_elements(guide_content->field)loop
   if jsonb_typeof(item->'title')is distinct from 'string'or length(trim(item->>'title'))not between 1 and 200
   or jsonb_typeof(item->'body')is distinct from 'string'or length(trim(item->>'body'))not between 1 and 30000 then raise exception '항목 제목과 본문을 확인해 주세요.';end if;
  end loop;
 end loop;
 for item in select value from jsonb_each(guide_content->'groupIntroductions')loop
  if jsonb_typeof(item->'title')is distinct from 'string'or length(trim(item->>'title'))not between 1 and 200
  or jsonb_typeof(item->'body')is distinct from 'string'or length(trim(item->>'body'))not between 1 and 30000 then raise exception '과목 소개 제목과 본문을 확인해 주세요.';end if;
 end loop;
 for item in select value from jsonb_each(guide_content->'subjects')loop
  if jsonb_typeof(item)is distinct from 'string'or length(trim(item#>>'{}'))not between 1 and 30000 then raise exception '과목별 본문을 확인해 주세요.';end if;
 end loop;
 guide_content := guide_content - 'coaching';
 perform pg_advisory_xact_lock(hashtext('cheongla_mbti_guides'),hashtext(selected_mbti));
 select *into previous from public.cheongla_mbti_guides where mbti=selected_mbti for update;
 if previous.updated_at is distinct from expected_updated_at then
  raise exception '다른 원장이 내용을 변경했습니다. 작성한 내용을 복사해 보관한 뒤 닫고 다시 확인해 주세요.';
 end if;
 insert into public.cheongla_mbti_guides(mbti,guide,updated_by)values(selected_mbti,guide_content,auth.uid())
 on conflict(mbti)do update set guide=excluded.guide,updated_at=clock_timestamp(),updated_by=excluded.updated_by returning *into saved;
 insert into cheongla_private.mbti_guide_history(mbti,actor_id,before_guide,after_guide)values(selected_mbti,auth.uid(),previous.guide,saved.guide);
 return jsonb_build_object('mbti',saved.mbti,'guide',saved.guide,'updated_at',saved.updated_at);
end;
$$;
revoke all on function public.cheongla_save_mbti_guide(text,jsonb,timestamptz)from public,anon;
grant execute on function public.cheongla_save_mbti_guide(text,jsonb,timestamptz)to authenticated;
notify pgrst,'reload schema';
