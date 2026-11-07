create table cheongla_private.winter_signin_codes (
  subject uuid primary key references public.cheongla_profiles(id) on delete cascade,
  code_hash bytea not null unique,
  expires_at timestamptz not null
);
alter table cheongla_private.winter_signin_codes enable row level security;
revoke all on cheongla_private.winter_signin_codes from public, anon, authenticated;

create function public.cheongla_issue_winter_signin()
returns text language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  code text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if not exists (
    select 1 from public.cheongla_profiles
    where id = actor and approval_status = 'approved' and membership_state = 'active'
      and role in ('student','parent')
  ) then
    raise exception '승인된 학생·학부모 계정만 이용할 수 있습니다.' using errcode = '42501';
  end if;
  insert into cheongla_private.winter_signin_codes(subject,code_hash,expires_at)
    values (actor, sha256(convert_to(code,'UTF8')), now() + interval '45 seconds')
    on conflict (subject) do update set code_hash=excluded.code_hash, expires_at=excluded.expires_at;
  return code;
end;
$$;

create function public.cheongla_redeem_winter_signin(handoff_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid;
begin
  if handoff_code is null or handoff_code !~ '^[0-9a-f]{64}$' then return null; end if;
  delete from cheongla_private.winter_signin_codes
    where code_hash=sha256(convert_to(handoff_code,'UTF8')) and expires_at > now()
    returning subject into actor;
  if not exists (
    select 1 from public.cheongla_profiles
    where id=actor and approval_status='approved' and membership_state='active'
      and role in ('student','parent')
  ) then return null; end if;
  return actor;
end;
$$;

revoke all on function public.cheongla_issue_winter_signin() from public, anon, authenticated;
revoke all on function public.cheongla_redeem_winter_signin(text) from public, anon, authenticated;
grant execute on function public.cheongla_issue_winter_signin() to authenticated;
grant execute on function public.cheongla_redeem_winter_signin(text) to anon;
