create table public.cheongla_home_features (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('tour', 'countdown')),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  description text not null default '' check (char_length(description) <= 600),
  target_date date,
  video_path text unique check (video_path ~ '^[0-9a-f-]{36}[.]mp4$'),
  original_video boolean not null default false,
  archived_at timestamptz,
  revision integer not null default 1,
  check ((kind = 'countdown') = (target_date is not null)),
  check (not original_video or (kind = 'tour' and video_path is null))
);

create unique index cheongla_home_features_one_live
  on public.cheongla_home_features (kind) where archived_at is null;

create table public.cheongla_home_video_cleanup (path text primary key);

create function cheongla_private.can_manage_home_features()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved'
      and membership_state = 'active' and role in ('owner', 'english_director', 'math_director')
  );
$$;
revoke all on function cheongla_private.can_manage_home_features() from public, anon, authenticated;
grant execute on function cheongla_private.can_manage_home_features() to authenticated;

alter table public.cheongla_home_features enable row level security;
alter table public.cheongla_home_video_cleanup enable row level security;
revoke all on public.cheongla_home_features, public.cheongla_home_video_cleanup from public, anon, authenticated;
grant select on public.cheongla_home_features to anon, authenticated;
grant insert (kind, title, description, target_date, video_path),
  update (title, description, target_date, video_path, original_video, archived_at), delete
  on public.cheongla_home_features to authenticated;
grant select, delete on public.cheongla_home_video_cleanup to authenticated;

create policy home_features_published_read on public.cheongla_home_features
  for select to anon, authenticated using (archived_at is null);
create policy home_features_principal_manage on public.cheongla_home_features
  for all to authenticated
  using ((select cheongla_private.can_manage_home_features()))
  with check ((select cheongla_private.can_manage_home_features()));
create policy home_features_only_delete_archived on public.cheongla_home_features
  as restrictive for delete to authenticated using (archived_at is not null);
create policy home_video_cleanup_principal on public.cheongla_home_video_cleanup
  for all to authenticated using ((select cheongla_private.can_manage_home_features()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cheongla-home-videos', 'cheongla-home-videos', false, 20971520, array['video/mp4']);

create policy home_video_published_read on storage.objects
  for select to anon, authenticated using (
    bucket_id = 'cheongla-home-videos' and exists (
      select 1 from public.cheongla_home_features as feature
      where feature.video_path = name and feature.archived_at is null
    )
  );
create policy home_video_principal_read on storage.objects
  for select to authenticated using (
    bucket_id = 'cheongla-home-videos' and (select cheongla_private.can_manage_home_features())
  );
create policy home_video_principal_upload on storage.objects
  for insert to authenticated with check (
    bucket_id = 'cheongla-home-videos' and name ~ '^[0-9a-f-]{36}[.]mp4$'
      and (select cheongla_private.can_manage_home_features())
  );
create policy home_video_principal_remove on storage.objects
  for delete to authenticated using (
    bucket_id = 'cheongla-home-videos' and (select cheongla_private.can_manage_home_features())
      and not exists (select 1 from public.cheongla_home_features as feature where feature.video_path = name)
  );

create function cheongla_private.track_home_feature_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op <> 'DELETE' then
    if new.video_path is not null and (tg_op = 'INSERT' or new.video_path is distinct from old.video_path) then
      if exists (select 1 from public.cheongla_home_video_cleanup where path = new.video_path)
        or not exists (select 1 from storage.objects where bucket_id = 'cheongla-home-videos' and name = new.video_path) then
        raise exception '업로드된 동영상 파일을 확인해 주세요.' using errcode = '23514';
      end if;
    end if;
    if tg_op = 'INSERT' then
      return new;
    end if;
    new.revision := old.revision + 1;
  end if;
  if old.video_path is not null and (tg_op = 'DELETE' or new.video_path is distinct from old.video_path) then
    insert into public.cheongla_home_video_cleanup (path) values (old.video_path) on conflict do nothing;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function cheongla_private.track_home_feature_change() from public, anon, authenticated;
create trigger home_feature_revision_and_video_cleanup
  before insert or update or delete on public.cheongla_home_features
  for each row execute function cheongla_private.track_home_feature_change();

insert into public.cheongla_home_features (kind, title, description, target_date, original_video) values
  ('tour', '공부에 집중할 수 있는 공간', '청라의 실제 학습 공간을 영상으로 만나보세요.', null, true),
  ('countdown', '2027학년도 수능까지', '', date '2026-11-19', false);
