create table public.cheongla_daily_rotation (
  slot integer primary key check (slot between 0 and 85),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null check (char_length(btrim(body)) between 1 and 6000),
  photo text not null check (photo ~ '^[A-Za-z0-9_]{1,50}[.]webp$'),
  revision integer not null default 1
);
alter table public.cheongla_daily_rotation enable row level security;
revoke all on public.cheongla_daily_rotation from public, anon, authenticated;
grant select on public.cheongla_daily_rotation to anon, authenticated;
create policy daily_rotation_public_read on public.cheongla_daily_rotation for select to anon, authenticated using (true);

create function public.cheongla_save_daily_rotation(target_slot integer, post_title text, post_body text, post_photo text, expected_revision integer)
returns public.cheongla_daily_rotation
language plpgsql security definer set search_path to ''
as $$
declare saved public.cheongla_daily_rotation;
begin
  if not cheongla_private.can_manage_app_content() then
    raise exception '원장 계정만 자동 문구와 사진을 수정할 수 있습니다.' using errcode='42501';
  end if;
  if expected_revision is null then
    insert into public.cheongla_daily_rotation(slot,title,body,photo)
    values(target_slot,btrim(post_title),btrim(post_body),post_photo)
    on conflict (slot) do nothing returning * into saved;
  else
    update public.cheongla_daily_rotation
    set title=btrim(post_title),body=btrim(post_body),photo=post_photo,revision=revision+1
    where slot=target_slot and revision=expected_revision returning * into saved;
  end if;
  if not found then
    raise exception '다른 곳에서 수정한 내용이 있습니다. 새로고침 후 다시 열어 주세요.' using errcode='40001';
  end if;
  return saved;
end;
$$;
revoke all on function public.cheongla_save_daily_rotation(integer,text,text,text,integer) from public, anon, authenticated;
grant execute on function public.cheongla_save_daily_rotation(integer,text,text,text,integer) to authenticated;
