create table public.cheongla_mbti_guides(
 mbti text primary key check(mbti~'^[IE][NS][TF][JP]$'),
 guide jsonb not null,
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid not null
);
alter table public.cheongla_mbti_guides enable row level security;
revoke all on public.cheongla_mbti_guides from public,anon,authenticated;
grant select on public.cheongla_mbti_guides to authenticated;
create policy mbti_guide_read on public.cheongla_mbti_guides for select to authenticated
 using(cheongla_private.can_use_member_services());

create table cheongla_private.mbti_guide_history(
 id bigint generated always as identity primary key,
 mbti text not null,actor_id uuid not null,before_guide jsonb,after_guide jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table cheongla_private.mbti_guide_history enable row level security;
revoke all on cheongla_private.mbti_guide_history from public,anon,authenticated;

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
 foreach field in array array['overview','coaching'] loop
  if jsonb_typeof(guide_content->field)is distinct from 'array'then raise exception '유형 이해와 학습 운영 내용을 확인해 주세요.';end if;
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
