create table public.cheongla_winter_promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 80),
  message text not null default '' check (char_length(message) <= 180),
  button_text text not null check (char_length(btrim(button_text)) between 1 and 40),
  first_date date not null,
  second_date date not null check (second_date >= first_date),
  first_open boolean not null default true,
  second_open boolean not null default true,
  enabled boolean not null default false,
  ends_at timestamptz not null,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  revision integer not null default 1,
  check (deleted_at is null or not enabled)
);

create unique index cheongla_one_enabled_winter_promotion
  on public.cheongla_winter_promotions (enabled) where enabled;

alter table public.cheongla_winter_promotions enable row level security;
revoke all on public.cheongla_winter_promotions from public, anon, authenticated;
grant select on public.cheongla_winter_promotions to anon, authenticated;
grant insert (title, message, button_text, first_date, second_date, first_open, second_open, enabled, ends_at),
  update (title, message, button_text, first_date, second_date, first_open, second_open, enabled, ends_at, deleted_at),
  delete on public.cheongla_winter_promotions to authenticated;

create policy winter_promotion_public_read on public.cheongla_winter_promotions
  for select to anon, authenticated
  using (enabled and deleted_at is null and (first_open or second_open) and ends_at > now());

create policy winter_promotion_principal_manage on public.cheongla_winter_promotions
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

create policy winter_promotion_delete_only_from_trash on public.cheongla_winter_promotions
  as restrictive for delete to authenticated using (deleted_at is not null);

create function cheongla_private.bump_winter_promotion_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.revision := old.revision + 1;
  return new;
end;
$$;

revoke all on function cheongla_private.bump_winter_promotion_revision() from public, anon, authenticated;

create trigger winter_promotion_revision
  before update on public.cheongla_winter_promotions
  for each row execute function cheongla_private.bump_winter_promotion_revision();

insert into public.cheongla_winter_promotions
  (title, button_text, first_date, second_date, enabled, ends_at)
values
  ('2027 청라 윈터스쿨', '모집 안내 · 상담 신청',
   '2026-12-21', '2026-12-28', true, '2026-12-28 00:00:00+09');
