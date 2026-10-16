begin;
-- Immutable signup number, independent of later editable contact/metadata.
create table if not exists cheongla_private.recovery_phones(user_id uuid primary key references auth.users(id) on delete cascade,phone text not null check(phone~'^01[016789][0-9]{7,8}$'));
alter table cheongla_private.recovery_phones enable row level security;
revoke all on cheongla_private.recovery_phones from public,anon,authenticated;
insert into cheongla_private.recovery_phones(user_id,phone)
 select u.id,coalesce(nullif(regexp_replace(u.raw_user_meta_data->>'contact_phone','[^0-9]','','g'),''),c.phone)
 from auth.users u left join cheongla_private.member_contacts c on c.user_id=u.id
 where coalesce(nullif(regexp_replace(u.raw_user_meta_data->>'contact_phone','[^0-9]','','g'),''),c.phone)~'^01[016789][0-9]{7,8}$' on conflict do nothing;
create or replace function cheongla_private.capture_recovery_phone()returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into cheongla_private.recovery_phones(user_id,phone) values(new.id,regexp_replace(new.raw_user_meta_data->>'contact_phone','[^0-9]','','g')) on conflict do nothing;return new;
end;$$;
revoke all on function cheongla_private.capture_recovery_phone()from public,anon,authenticated;
drop trigger if exists cheongla_recovery_signup_phone on auth.users;
create trigger cheongla_recovery_signup_phone after insert on auth.users for each row execute function cheongla_private.capture_recovery_phone();
create table if not exists cheongla_private.recovery_challenges(
 id uuid primary key,purpose text not null check(purpose in('find_id','reset_password')),phone_hash text not null,ip_hash text not null,code_hash text not null,
 users uuid[] not null default '{}',created_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null default clock_timestamp()+interval '5 minutes',
 sent boolean not null default false,attempts int not null default 0,verified_at timestamptz,ticket_hash text,consumed_at timestamptz);
alter table cheongla_private.recovery_challenges enable row level security;
revoke all on cheongla_private.recovery_challenges from public,anon,authenticated;
create index if not exists cheongla_recovery_phone_rate on cheongla_private.recovery_challenges(phone_hash,created_at);
create index if not exists cheongla_recovery_ip_rate on cheongla_private.recovery_challenges(ip_hash,created_at);
create or replace function public.cheongla_recovery_issue(challenge uuid,recovery_purpose text,phone text,email text,phone_hash text,ip_hash text,code_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare targets uuid[];
begin
 if (select auth.role()) is distinct from 'service_role' then raise exception 'server only' using errcode='42501';end if;
 if challenge is null or recovery_purpose not in('find_id','reset_password')or recovery_purpose is null or phone!~'^01[016789][0-9]{7,8}$' or phone is null or phone_hash!~'^[0-9a-f]{64}$' or ip_hash!~'^[0-9a-f]{64}$' or code_hash!~'^[0-9a-f]{64}$' then raise exception 'invalid request';end if;
 perform pg_catalog.pg_advisory_xact_lock(7492055);
 delete from cheongla_private.recovery_challenges where created_at<clock_timestamp()-interval '2 days';
 if exists(select 1 from cheongla_private.recovery_challenges c where c.phone_hash=cheongla_recovery_issue.phone_hash and c.created_at>clock_timestamp()-interval '60 seconds')
 or (select count(*)from cheongla_private.recovery_challenges c where c.phone_hash=cheongla_recovery_issue.phone_hash and c.created_at>clock_timestamp()-interval '1 day')>=5
 or (select count(*)from cheongla_private.recovery_challenges c where c.ip_hash=cheongla_recovery_issue.ip_hash and c.created_at>clock_timestamp()-interval '1 day')>=20
 or (select count(*)from cheongla_private.recovery_challenges c where c.created_at>clock_timestamp()-interval '1 day')>=200 then return jsonb_build_object('limited',true);end if;
 select coalesce(array_agg(u.id),'{}') into targets from auth.users u join public.cheongla_profiles p on p.id=u.id join cheongla_private.recovery_phones r on r.user_id=u.id
 where r.phone=cheongla_recovery_issue.phone and p.membership_state='active' and p.approval_status not in('suspended','rejected') and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp()) and coalesce(u.email,'')<>''
 and (recovery_purpose='find_id' or lower(u.email)=lower(btrim(cheongla_recovery_issue.email)));
 update cheongla_private.recovery_challenges c set consumed_at=clock_timestamp()where c.phone_hash=cheongla_recovery_issue.phone_hash and c.consumed_at is null;
 insert into cheongla_private.recovery_challenges(id,purpose,phone_hash,ip_hash,code_hash,users)values(challenge,recovery_purpose,phone_hash,ip_hash,code_hash,targets);
 return jsonb_build_object('eligible',cardinality(targets)>0);
end;$$;
create or replace function public.cheongla_recovery_sent(challenge uuid,accepted boolean)returns void language plpgsql security definer set search_path='' as $$
begin
 if (select auth.role()) is distinct from 'service_role' then raise exception 'server only' using errcode='42501';end if;
 update cheongla_private.recovery_challenges set sent=accepted,consumed_at=case when accepted then consumed_at else clock_timestamp()end where id=challenge;
end;$$;
create or replace function public.cheongla_recovery_verify(challenge uuid,code_hash text,ticket_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c cheongla_private.recovery_challenges%rowtype;emails jsonb;eligible uuid[];
begin
 if (select auth.role()) is distinct from 'service_role' then raise exception 'server only' using errcode='42501';end if;
 select * into c from cheongla_private.recovery_challenges where id=challenge for update;
 if not found or not c.sent or c.consumed_at is not null or c.verified_at is not null or c.expires_at<=clock_timestamp()or c.attempts>=5 then return jsonb_build_object('ok',false);end if;
 update cheongla_private.recovery_challenges set attempts=attempts+1 where id=c.id;
 if c.code_hash is distinct from cheongla_recovery_verify.code_hash or cardinality(c.users)=0 then return jsonb_build_object('ok',false);end if;
 select coalesce(array_agg(u.id),'{}'),coalesce(jsonb_agg(u.email order by u.email),'[]') into eligible,emails from auth.users u join public.cheongla_profiles p on p.id=u.id
 where u.id=any(c.users)and p.membership_state='active' and p.approval_status not in('suspended','rejected')and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp());
 if cardinality(eligible)=0 or (c.purpose='reset_password' and cardinality(eligible)<>1)then return jsonb_build_object('ok',false);end if;
 if ticket_hash is null or ticket_hash!~'^[0-9a-f]{64}$' then return jsonb_build_object('ok',false);end if;
 update cheongla_private.recovery_challenges set verified_at=clock_timestamp(),ticket_hash=cheongla_recovery_verify.ticket_hash,users=eligible,expires_at=clock_timestamp()+interval '5 minutes',consumed_at=case when c.purpose='find_id' then clock_timestamp()else null end where id=c.id;
 return jsonb_build_object('ok',true,'purpose',c.purpose,'emails',case when c.purpose='find_id' then emails else '[]'::jsonb end);
end;$$;
create or replace function public.cheongla_recovery_consume(challenge uuid,ticket_hash text)returns uuid language plpgsql security definer set search_path='' as $$
declare c cheongla_private.recovery_challenges%rowtype;target uuid;
begin
 if (select auth.role()) is distinct from 'service_role' then raise exception 'server only' using errcode='42501';end if;
 select * into c from cheongla_private.recovery_challenges where id=challenge for update;
 if not found or c.purpose<>'reset_password'or c.verified_at is null or c.consumed_at is not null or c.expires_at<=clock_timestamp()or c.ticket_hash is distinct from cheongla_recovery_consume.ticket_hash then return null;end if;
 select u.id into target from auth.users u join public.cheongla_profiles p on p.id=u.id where u.id=any(c.users)and p.membership_state='active' and p.approval_status not in('suspended','rejected')and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp());
 update cheongla_private.recovery_challenges set consumed_at=clock_timestamp()where id=c.id;return target;
end;$$;
revoke all on function public.cheongla_recovery_issue(uuid,text,text,text,text,text,text),public.cheongla_recovery_sent(uuid,boolean),public.cheongla_recovery_verify(uuid,text,text),public.cheongla_recovery_consume(uuid,text) from public,anon,authenticated;
grant execute on function public.cheongla_recovery_issue(uuid,text,text,text,text,text,text),public.cheongla_recovery_sent(uuid,boolean),public.cheongla_recovery_verify(uuid,text,text),public.cheongla_recovery_consume(uuid,text) to service_role;
notify pgrst,'reload schema';
commit;
