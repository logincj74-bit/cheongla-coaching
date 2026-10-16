begin;
alter table cheongla_private.recovery_challenges drop constraint if exists recovery_challenges_purpose_check;
alter table cheongla_private.recovery_challenges add constraint recovery_challenges_purpose_check check(purpose in('find_id','reset_password','signup'));
alter table cheongla_private.recovery_challenges add column if not exists signup_email text,add column if not exists signup_phone text,add column if not exists signup_user_id uuid;
alter table cheongla_private.recovery_phones add column if not exists verified_at timestamptz;
create or replace function public.cheongla_signup_issue(challenge uuid,phone text,email text,phone_hash text,ip_hash text,code_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if (select auth.role())is distinct from 'service_role'then raise exception 'server only'using errcode='42501';end if;
 if challenge is null or phone is null or phone!~'^01[016789][0-9]{7,8}$'or email is null or length(email)>254 or email!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'or phone_hash is null or phone_hash!~'^[0-9a-f]{64}$'or ip_hash is null or ip_hash!~'^[0-9a-f]{64}$'or code_hash is null or code_hash!~'^[0-9a-f]{64}$'then raise exception 'invalid request';end if;
 perform pg_catalog.pg_advisory_xact_lock(7492055);
 delete from cheongla_private.recovery_challenges where created_at<clock_timestamp()-interval '2 days';
 if exists(select 1 from cheongla_private.recovery_challenges c where c.phone_hash=cheongla_signup_issue.phone_hash and c.created_at>clock_timestamp()-interval '60 seconds')
 or(select count(*)from cheongla_private.recovery_challenges c where c.phone_hash=cheongla_signup_issue.phone_hash and c.created_at>clock_timestamp()-interval '1 day')>=5
 or(select count(*)from cheongla_private.recovery_challenges c where c.ip_hash=cheongla_signup_issue.ip_hash and c.created_at>clock_timestamp()-interval '1 day')>=20
 or(select count(*)from cheongla_private.recovery_challenges c where c.created_at>clock_timestamp()-interval '1 day')>=200 then return jsonb_build_object('limited',true);end if;
 update cheongla_private.recovery_challenges c set consumed_at=clock_timestamp()where c.phone_hash=cheongla_signup_issue.phone_hash and c.consumed_at is null;
 insert into cheongla_private.recovery_challenges(id,purpose,phone_hash,ip_hash,code_hash,signup_email,signup_phone)values(challenge,'signup',phone_hash,ip_hash,code_hash,lower(btrim(email)),phone);
 return jsonb_build_object('eligible',true);
end;$$;
create or replace function public.cheongla_signup_verify(challenge uuid,code_hash text,ticket_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c cheongla_private.recovery_challenges%rowtype;
begin
 if(select auth.role())is distinct from 'service_role'then raise exception 'server only'using errcode='42501';end if;
 select * into c from cheongla_private.recovery_challenges where id=challenge for update;
 if not found or c.purpose<>'signup'or not c.sent or c.consumed_at is not null or c.verified_at is not null or c.expires_at<=clock_timestamp()or c.attempts>=5 then return jsonb_build_object('ok',false);end if;
 update cheongla_private.recovery_challenges set attempts=attempts+1 where id=c.id;
 if c.code_hash is distinct from cheongla_signup_verify.code_hash or ticket_hash is null or ticket_hash!~'^[0-9a-f]{64}$'then return jsonb_build_object('ok',false);end if;
 update cheongla_private.recovery_challenges set verified_at=clock_timestamp(),ticket_hash=cheongla_signup_verify.ticket_hash,expires_at=clock_timestamp()+interval '5 minutes'where id=c.id;
 return jsonb_build_object('ok',true,'purpose','signup');
end;$$;
-- Official Before User Created hook: no browser or anon caller may bypass OTP.
create or replace function public.cheongla_signup_access_hook(event jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare meta jsonb:=event->'user'->'user_metadata';ch text;ticket text;phone text;email text;c cheongla_private.recovery_challenges%rowtype;
 denied jsonb:=jsonb_build_object('error',jsonb_build_object('http_code',403,'message','CHEONGLA_SIGNUP_PHONE: 휴대전화 문자 인증을 완료한 뒤 가입해 주세요.'));
begin
 ch:=meta->>'signup_challenge';ticket:=meta->>'signup_ticket';phone:=regexp_replace(coalesce(meta->>'contact_phone',''),'[^0-9]','','g');email:=lower(btrim(event->'user'->>'email'));
 if ch is null or ch!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'or ticket is null or ticket!~'^[0-9a-f]{64}$'then return denied;end if;
 select * into c from cheongla_private.recovery_challenges where id=ch::uuid for update;
 if not found or c.purpose<>'signup'or not c.sent or c.verified_at is null or c.consumed_at is not null or c.expires_at<=clock_timestamp()or c.signup_phone is distinct from phone or c.signup_email is distinct from email or c.ticket_hash is distinct from pg_catalog.encode(extensions.digest(ticket,'sha256'),'hex')then return denied;end if;
 update cheongla_private.recovery_challenges set consumed_at=clock_timestamp(),signup_user_id=(event->'user'->>'id')::uuid where id=c.id;
 return '{}'::jsonb;
end;$$;
revoke all on function public.cheongla_signup_issue(uuid,text,text,text,text,text),public.cheongla_signup_verify(uuid,text,text),public.cheongla_signup_access_hook(jsonb)from public,anon,authenticated;
grant execute on function public.cheongla_signup_issue(uuid,text,text,text,text,text),public.cheongla_signup_verify(uuid,text,text)to service_role;
grant execute on function public.cheongla_signup_access_hook(jsonb)to supabase_auth_admin;
-- Do not retain the one-use credential in auth metadata/JWTs after signup.
create or replace function cheongla_private.scrub_signup_proof()returns trigger language plpgsql set search_path='' as $$
begin new.raw_user_meta_data:=new.raw_user_meta_data-'signup_ticket'-'signup_challenge';return new;end;$$;
revoke all on function cheongla_private.scrub_signup_proof()from public,anon,authenticated;
drop trigger if exists cheongla_scrub_signup_proof on auth.users;
create trigger cheongla_scrub_signup_proof before insert on auth.users for each row execute function cheongla_private.scrub_signup_proof();
create or replace function cheongla_private.mark_signup_phone_verified()returns trigger language plpgsql security definer set search_path='' as $$
begin
 update cheongla_private.recovery_phones set verified_at=c.verified_at from cheongla_private.recovery_challenges c where user_id=new.id and c.signup_user_id=new.id and c.purpose='signup'and c.consumed_at is not null;return new;
end;$$;
revoke all on function cheongla_private.mark_signup_phone_verified()from public,anon,authenticated;
drop trigger if exists cheongla_z_signup_verified on auth.users;
create trigger cheongla_z_signup_verified after insert on auth.users for each row execute function cheongla_private.mark_signup_phone_verified();
notify pgrst,'reload schema';
commit;
