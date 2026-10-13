-- 기존 가입자와 권한을 유지합니다. 전화번호는 본인·앱 관리자·실장만 조회합니다.
begin;
create table if not exists cheongla_private.member_contacts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 phone text not null check(phone ~ '^01[016789][0-9]{7,8}$'),
 updated_at timestamptz not null default clock_timestamp()
);
alter table cheongla_private.member_contacts enable row level security;
revoke all on cheongla_private.member_contacts from public,anon,authenticated;

create or replace function cheongla_private.save_signup_contact()
returns trigger language plpgsql security definer set search_path='' as $$
declare number text;
begin
 number:=regexp_replace(coalesce(new.raw_user_meta_data->>'contact_phone',''),'[^0-9]','','g');
 if coalesce(btrim(new.email),'')='' or number !~ '^01[016789][0-9]{7,8}$' then
  raise exception '가입하려면 이메일과 올바른 휴대전화번호를 입력해 주세요.' using errcode='22023';
 end if;
 insert into cheongla_private.member_contacts(user_id,phone) values(new.id,number);
 return new;
end;
$$;
revoke all on function cheongla_private.save_signup_contact() from public,anon,authenticated;
drop trigger if exists cheongla_signup_contact on auth.users;
create trigger cheongla_signup_contact after insert on auth.users
for each row execute function cheongla_private.save_signup_contact();

-- 화면 배포 후 SQL 실행 전에 가입한 회원의 전화번호도 보완합니다.
insert into cheongla_private.member_contacts(user_id,phone)
select id,regexp_replace(raw_user_meta_data->>'contact_phone','[^0-9]','','g')
from auth.users where regexp_replace(coalesce(raw_user_meta_data->>'contact_phone',''),'[^0-9]','','g') ~ '^01[016789][0-9]{7,8}$'
on conflict(user_id) do nothing;

create or replace function public.cheongla_my_contact()
returns table(email text,phone text) language sql stable security definer set search_path='' as $$
 select u.email::text,c.phone from auth.users u
 left join cheongla_private.member_contacts c on c.user_id=u.id where u.id=(select auth.uid());
$$;
create or replace function public.cheongla_save_my_contact(contact_phone text)
returns void language plpgsql security definer set search_path='' as $$
declare number text;member_id uuid;
begin
 member_id:=auth.uid();
 if member_id is null or not exists(select 1 from auth.users where id=member_id and coalesce(btrim(email),'')<>'') then
  raise exception '이메일로 로그인한 본인 계정에서 등록해 주세요.' using errcode='42501';
 end if;
 number:=regexp_replace(coalesce(contact_phone,''),'[^0-9]','','g');
 if number !~ '^01[016789][0-9]{7,8}$' then
  raise exception '올바른 휴대전화번호를 입력해 주세요.' using errcode='22023';
 end if;
 insert into cheongla_private.member_contacts(user_id,phone) values(member_id,number)
 on conflict(user_id) do update set phone=excluded.phone,updated_at=clock_timestamp();
end;
$$;
create or replace function public.cheongla_member_contacts()
returns table(member_id uuid,full_name text,role text,approval_status text,email text,phone text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.cheongla_profiles p where p.id=(select auth.uid())
 and p.approval_status='approved' and (p.is_app_admin or p.role='manager')) then
  raise exception '앱 관리자와 실장만 연락처를 확인할 수 있습니다.' using errcode='42501';
 end if;
 return query select p.id,p.full_name::text,p.role::text,p.approval_status::text,u.email::text,c.phone
 from public.cheongla_profiles p join auth.users u on u.id=p.id
 left join cheongla_private.member_contacts c on c.user_id=p.id
 order by p.full_name,p.id;
end;
$$;
revoke all on function public.cheongla_my_contact(),public.cheongla_save_my_contact(text),public.cheongla_member_contacts() from public,anon,authenticated;
grant execute on function public.cheongla_my_contact(),public.cheongla_save_my_contact(text),public.cheongla_member_contacts() to authenticated;
notify pgrst,'reload schema';
commit;
