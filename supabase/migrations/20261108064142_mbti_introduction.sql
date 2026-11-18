create table public.cheongla_mbti_introductions (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null check (char_length(btrim(body)) between 1 and 20000),
  archived_at timestamptz,
  revision integer not null default 1
);

create unique index cheongla_one_published_mbti_introduction
  on public.cheongla_mbti_introductions ((true)) where archived_at is null;

alter table public.cheongla_mbti_introductions enable row level security;
revoke all on public.cheongla_mbti_introductions from public, anon, authenticated;
grant select, delete on public.cheongla_mbti_introductions to authenticated;
grant insert (title, body), update (title, body, archived_at)
  on public.cheongla_mbti_introductions to authenticated;

create policy mbti_introduction_member_read on public.cheongla_mbti_introductions
  for select to authenticated
  using (archived_at is null and (select exists (
    select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved' and membership_state = 'active'
  )));

create policy mbti_introduction_principal_manage on public.cheongla_mbti_introductions
  for all to authenticated
  using ((select exists (
    select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved'
      and membership_state = 'active' and role in ('owner', 'english_director', 'math_director')
  )))
  with check ((select exists (
    select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved'
      and membership_state = 'active' and role in ('owner', 'english_director', 'math_director')
  )));

create policy mbti_introduction_delete_only_from_trash on public.cheongla_mbti_introductions
  as restrictive for delete to authenticated using (archived_at is not null);

create function cheongla_private.bump_mbti_introduction_revision()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.revision := old.revision + 1;
  return new;
end;
$$;

revoke all on function cheongla_private.bump_mbti_introduction_revision() from public, anon, authenticated;
create trigger mbti_introduction_revision before update on public.cheongla_mbti_introductions
  for each row execute function cheongla_private.bump_mbti_introduction_revision();

-- Document seeds are retained in the private source backup, not in this public schema.
