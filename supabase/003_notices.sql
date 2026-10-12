-- 001_initial.sql, 002_parent_access.sql 실행 후 실행하세요.
-- 기존 가입자, 승인 상태, 자녀 연결은 유지됩니다.
begin;

create table if not exists public.cheongla_notices (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 150),
  body text not null check (char_length(btrim(body)) between 1 and 10000),
  audience text not null default 'all' check (audience in ('all','student','parent')),
  pinned boolean not null default false,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists cheongla_notices_order_idx
  on public.cheongla_notices(pinned desc, created_at desc, id desc);
alter table public.cheongla_notices enable row level security;
revoke all on public.cheongla_notices from public,anon,authenticated;
grant select,delete on public.cheongla_notices to authenticated;
grant insert (title,body,audience,pinned,created_by) on public.cheongla_notices to authenticated;
grant update (title,body,audience,pinned) on public.cheongla_notices to authenticated;

create or replace function cheongla_private.can_manage_notices()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cheongla_profiles p
    where p.id=(select auth.uid()) and p.approval_status='approved'
    and p.role in ('owner','english_director','math_director','manager'));
$$;
revoke all on function cheongla_private.can_manage_notices() from public,anon,authenticated;
grant execute on function cheongla_private.can_manage_notices() to authenticated;

create or replace function cheongla_private.can_read_notice(target_audience text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cheongla_profiles p
    where p.id=(select auth.uid()) and p.approval_status='approved'
    and (target_audience='all' or p.role=target_audience
      or p.role in ('owner','english_director','math_director','korean_teacher','manager')));
$$;
revoke all on function cheongla_private.can_read_notice(text) from public,anon,authenticated;
grant execute on function cheongla_private.can_read_notice(text) to authenticated;

create or replace function cheongla_private.touch_notice()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at=now();
  return new;
end;
$$;
revoke all on function cheongla_private.touch_notice() from public,anon,authenticated;
drop trigger if exists cheongla_notice_updated on public.cheongla_notices;
create trigger cheongla_notice_updated before update on public.cheongla_notices
for each row execute function cheongla_private.touch_notice();

drop policy if exists cheongla_notice_read on public.cheongla_notices;
create policy cheongla_notice_read on public.cheongla_notices
for select to authenticated using (cheongla_private.can_read_notice(audience));
drop policy if exists cheongla_notice_create on public.cheongla_notices;
create policy cheongla_notice_create on public.cheongla_notices
for insert to authenticated with check (
  (select cheongla_private.can_manage_notices()) and created_by=(select auth.uid())
);
drop policy if exists cheongla_notice_edit on public.cheongla_notices;
create policy cheongla_notice_edit on public.cheongla_notices
for update to authenticated using ((select cheongla_private.can_manage_notices()))
with check ((select cheongla_private.can_manage_notices()));
drop policy if exists cheongla_notice_delete on public.cheongla_notices;
create policy cheongla_notice_delete on public.cheongla_notices
for delete to authenticated using ((select cheongla_private.can_manage_notices()));

notify pgrst, 'reload schema';
commit;
