-- A rejoin receives a NEW auth user and pending profile; old records remain withdrawn.
create table cheongla_private.rejoin_attempts(id uuid primary key default gen_random_uuid(),member_id uuid not null references auth.users(id),login_email text not null,archive_email text not null,created_at timestamptz not null default clock_timestamp(),completed_at timestamptz);
alter table cheongla_private.rejoin_attempts enable row level security;
revoke all on cheongla_private.rejoin_attempts from public,anon,authenticated;
create index on cheongla_private.rejoin_attempts(login_email,created_at desc);
create or replace function public.cheongla_rejoin_job(login_email text,operation_id uuid default null,job_step text default 'check')returns jsonb language plpgsql security definer set search_path=''as $$
declare u auth.users%rowtype;j cheongla_private.rejoin_attempts%rowtype;canonical text:=lower(btrim(login_email));
begin
 if coalesce(auth.role(),'')<>'service_role'then raise exception '서버 전용 처리입니다.'using errcode='42501';end if;
 if canonical is null or length(canonical)>254 or canonical!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'or canonical like '%@withdrawn.cheongla.invalid'then raise exception '가입 이메일이나 전화번호를 확인해 주세요.';end if;
 perform pg_advisory_xact_lock(hashtextextended(canonical,712));
 if job_step='check'then
  select *into u from auth.users where lower(email)=canonical;
  if u.id is not null and not exists(select 1 from public.cheongla_profiles where id=u.id and membership_state='withdrawn')then return jsonb_build_object('history',false);end if;
  if u.id is null then select *into j from cheongla_private.rejoin_attempts a where a.login_email=canonical and completed_at is not null order by created_at desc limit 1;if j.id is null then return jsonb_build_object('history',false);end if;u.id:=j.member_id;end if;
  if(select count(*)from cheongla_private.rejoin_attempts a where a.login_email=canonical and created_at>clock_timestamp()-interval '15 minutes')>=8 then raise exception '잠시 후 다시 가입을 시도해 주세요.';end if;
  insert into cheongla_private.rejoin_attempts(member_id,login_email,archive_email)values(u.id,canonical,'withdrawn-'||u.id::text||'-'||gen_random_uuid()::text||'@withdrawn.cheongla.invalid')returning *into j;
  return jsonb_build_object('history',true,'operation',j.id);
 end if;
 select *into j from cheongla_private.rejoin_attempts a where a.id=operation_id and a.login_email=canonical for update;
 if j.id is null or j.created_at<clock_timestamp()-interval '10 minutes'or not exists(select 1 from public.cheongla_profiles where id=j.member_id and membership_state='withdrawn')then raise exception '재가입 확인이 만료되었습니다. 가입 신청을 다시 눌러 주세요.';end if;
 if job_step='begin'then
  select *into u from auth.users where id=j.member_id;
  if lower(u.email)<>canonical and u.email not like '%@withdrawn.cheongla.invalid'then raise exception '가입 정보가 변경되었습니다.';end if;
  return jsonb_build_object('member',j.member_id,'archive_email',j.archive_email,'already_archived',lower(u.email)<>canonical);
 elsif job_step='finish'then
  if exists(select 1 from auth.users where id=j.member_id and lower(email)=canonical)then raise exception '기존 가입 정보 보관을 확인하지 못했습니다.';end if;
  update cheongla_private.rejoin_attempts set completed_at=clock_timestamp()where id=j.id;
  return jsonb_build_object('ok',true);
 end if;
 raise exception '처리 방법을 확인해 주세요.';
end;$$;
revoke all on function public.cheongla_rejoin_job(text,uuid,text)from public,anon,authenticated;
grant execute on function public.cheongla_rejoin_job(text,uuid,text)to service_role;
notify pgrst,'reload schema';
