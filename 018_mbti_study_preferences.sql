begin;
create or replace function cheongla_private.can_use_mbti_study()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles
 where id=(select auth.uid()) and approval_status='approved');
$$;
revoke all on function cheongla_private.can_use_mbti_study() from public,anon,authenticated;
grant execute on function cheongla_private.can_use_mbti_study() to authenticated;
create table if not exists public.cheongla_mbti_preferences (
 user_id uuid primary key references public.cheongla_profiles(id) on delete cascade,
 mbti text not null check(mbti ~ '^[EI][SN][TF][JP]$'),
 updated_at timestamptz not null default clock_timestamp()
);
alter table public.cheongla_mbti_preferences enable row level security;
revoke all on public.cheongla_mbti_preferences from public,anon,authenticated;
grant select on public.cheongla_mbti_preferences to authenticated;
drop policy if exists cheongla_mbti_read on public.cheongla_mbti_preferences;
create policy cheongla_mbti_read on public.cheongla_mbti_preferences for select to authenticated
using (
 (user_id=(select auth.uid()) and (select cheongla_private.can_use_mbti_study()))
 or (select cheongla_private.is_app_admin())
 or ((select cheongla_private.can_coach_all()) and exists(
  select 1 from public.cheongla_profiles p where p.id=user_id
  and p.role='student' and p.approval_status='approved'
 ))
);
create or replace function public.cheongla_save_my_mbti(selected_mbti text)
returns text language plpgsql security definer set search_path='' as $$
declare code text=upper(btrim(selected_mbti));
begin
 if not cheongla_private.can_use_mbti_study() then
  raise exception '승인된 학원 계정으로 이용해 주세요.' using errcode='42501';
 end if;
 if code is null or code !~ '^[EI][SN][TF][JP]$' then
  raise exception '16가지 MBTI 유형 중 본인의 유형을 선택해 주세요.';
 end if;
 insert into public.cheongla_mbti_preferences(user_id,mbti)
 values((select auth.uid()),code)
 on conflict(user_id) do update set mbti=excluded.mbti,updated_at=clock_timestamp();
 return code;
end;
$$;
revoke all on function public.cheongla_save_my_mbti(text) from public,anon,authenticated;
grant execute on function public.cheongla_save_my_mbti(text) to authenticated;
notify pgrst,'reload schema';
commit;
