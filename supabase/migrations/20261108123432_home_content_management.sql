alter table public.cheongla_home_features
  add column hidden boolean not null default false,
  add column video_hidden boolean not null default false,
  add column sort_order integer not null default 100 check (sort_order between 0 and 9999),
  add column featured boolean not null default false,
  add constraint home_feature_featured_visible check
    (not featured or (kind = 'countdown' and not hidden and archived_at is null));

drop index public.cheongla_home_features_one_live;
create unique index cheongla_home_features_one_featured
  on public.cheongla_home_features (featured) where featured;
update public.cheongla_home_features set featured = true where kind = 'countdown' and archived_at is null;
grant insert (sort_order, hidden), update (hidden, video_hidden, sort_order)
  on public.cheongla_home_features to authenticated;
alter policy home_features_published_read on public.cheongla_home_features
  using (archived_at is null and not hidden);

create table public.cheongla_home_video_trash (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('tour','countdown')),
  title text not null,
  path text unique,
  original_video boolean not null,
  archived_at timestamptz not null default now(),
  check (original_video = (path is null))
);
alter table public.cheongla_home_video_trash enable row level security;
revoke all on public.cheongla_home_video_trash from public, anon, authenticated;
grant select on public.cheongla_home_video_trash to authenticated;
create policy home_video_trash_principal_read on public.cheongla_home_video_trash
  for select to authenticated using ((select cheongla_private.can_manage_home_features()));

alter policy home_video_published_read on storage.objects using (
  bucket_id = 'cheongla-home-videos' and exists (
    select 1 from public.cheongla_home_features as feature
    where feature.video_path = name and feature.archived_at is null
      and not feature.hidden and not feature.video_hidden
  )
);
alter policy home_video_principal_remove on storage.objects using (
  bucket_id = 'cheongla-home-videos' and (select cheongla_private.can_manage_home_features())
    and not exists (select 1 from public.cheongla_home_features as feature where feature.video_path = name)
    and not exists (select 1 from public.cheongla_home_video_trash as trash where trash.path = name)
);

create or replace function cheongla_private.track_home_feature_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.video_path is not null then
      insert into public.cheongla_home_video_cleanup (path) values (old.video_path) on conflict do nothing;
    end if;
    return old;
  end if;
  if new.hidden or new.archived_at is not null then new.featured := false; end if;
  if new.video_path is not null and (tg_op = 'INSERT' or new.video_path is distinct from old.video_path) then
    if exists (select 1 from public.cheongla_home_video_cleanup where path = new.video_path)
      or exists (select 1 from public.cheongla_home_video_trash where path = new.video_path)
      or not exists (select 1 from storage.objects where bucket_id = 'cheongla-home-videos' and name = new.video_path) then
      raise exception '업로드된 동영상 파일을 확인해 주세요.' using errcode = '23514';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    new.revision := old.revision + 1;
    if (old.video_path is not null or old.original_video)
      and (new.video_path is distinct from old.video_path or new.original_video is distinct from old.original_video) then
      insert into public.cheongla_home_video_trash (kind, title, path, original_video)
      values (old.kind, old.title, old.video_path, old.original_video);
    end if;
  end if;
  return new;
end;
$$;

create function public.cheongla_set_featured_home_countdown(target uuid, expected_revision integer)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not cheongla_private.can_manage_home_features() then raise insufficient_privilege; end if;
  perform pg_advisory_xact_lock(801326411);
  perform 1 from public.cheongla_home_features
    where id = target and revision = expected_revision and kind = 'countdown' and not hidden and archived_at is null for update;
  if not found then raise exception '공개 중인 최신 D-day만 대표로 지정할 수 있습니다.'; end if;
  update public.cheongla_home_features set featured = false where featured and id <> target;
  update public.cheongla_home_features set featured = true where id = target and not featured;
end;
$$;

create function public.cheongla_manage_home_video_trash(target uuid, restore_to uuid default null, expected_revision integer default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare item public.cheongla_home_video_trash%rowtype;
begin
  if not cheongla_private.can_manage_home_features() then raise insufficient_privilege; end if;
  select * into item from public.cheongla_home_video_trash where id = target for update;
  if not found then raise exception '영상 휴지통을 다시 불러와 주세요.'; end if;
  delete from public.cheongla_home_video_trash where id = target;
  if restore_to is null then
    if item.path is not null then
      insert into public.cheongla_home_video_cleanup (path) values (item.path) on conflict do nothing;
    end if;
  else
    update public.cheongla_home_features set video_path = item.path, original_video = item.original_video, video_hidden = false
      where id = restore_to and revision = expected_revision and kind = item.kind and archived_at is null;
    if not found then raise exception '복원할 항목을 다시 선택해 주세요.'; end if;
  end if;
end;
$$;

revoke all on function public.cheongla_set_featured_home_countdown(uuid,integer),
  public.cheongla_manage_home_video_trash(uuid,uuid,integer) from public, anon, authenticated;
grant execute on function public.cheongla_set_featured_home_countdown(uuid,integer),
  public.cheongla_manage_home_video_trash(uuid,uuid,integer) to authenticated;
