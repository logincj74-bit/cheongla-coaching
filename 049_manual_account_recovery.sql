begin;
-- Manual recovery keeps the original auth UUID. Temporary credentials never enter audit tables.
create table cheongla_private.manual_recoveries(user_id uuid primary key references auth.users(id),actor_id uuid not null,prior_status text not null,member_version timestamptz not null,operation uuid not null,ready boolean not null default false,busy_until timestamptz not null,reason text not null,created_at timestamptz not null default clock_timestamp(),completed_at timestamptz);
alter table cheongla_private.manual_recoveries enable row level security;
revoke all on cheongla_private.manual_recoveries from public,anon,authenticated;
create or replace function public.cheongla_account_recovery_state()returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from cheongla_private.manual_recoveries where user_id=auth.uid()and completed_at is null)$$;
create or replace function cheongla_private.guard_recovery_approval()returns trigger language plpgsql security definer set search_path='' as $$begin if new.approval_status='approved'and exists(select 1 from cheongla_private.manual_recoveries where user_id=new.id and completed_at is null)then raise exception '임시 비밀번호 변경을 먼저 완료해야 합니다.';end if;return new;end;$$;
create trigger cheongla_recovery_approval before update on public.cheongla_profiles for each row execute function cheongla_private.guard_recovery_approval();
create or replace function public.cheongla_manual_account(target_member uuid)returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not(cheongla_private.is_app_admin()or cheongla_private.is_principal())then raise exception '관리자만 확인할 수 있습니다.'using errcode='42501';end if;
 return(select jsonb_build_object('email',u.email,'phone',r.phone,'name',p.full_name,'role',p.role,'version',p.membership_updated_at,'recovering',exists(select 1 from cheongla_private.manual_recoveries m where m.user_id=p.id and m.completed_at is null))from public.cheongla_profiles p join auth.users u on u.id=p.id left join cheongla_private.recovery_phones r on r.user_id=p.id where p.id=target_member and p.role in('student','parent')and not p.is_app_admin and p.membership_state='active');
end;$$;
-- Only the authenticated server may change credentials; actor ID is verified at the Edge.
create or replace function public.cheongla_manual_recovery_job(actor uuid,target_member uuid,operation uuid,step text,reason text default '',expected_version timestamptz default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.cheongla_profiles%rowtype;r cheongla_private.manual_recoveries%rowtype;old_status text;
begin
 if auth.role()is distinct from 'service_role'then raise exception 'server only'using errcode='42501';end if;
 perform pg_advisory_xact_lock(7492052);
 select * into p from public.cheongla_profiles where id=target_member for update;
 if not found or p.membership_state<>'active'or p.is_app_admin or p.role not in('student','parent')or p.approval_status in('suspended','rejected')then raise exception '이 계정은 복구할 수 없습니다.';end if;
 select * into r from cheongla_private.manual_recoveries where user_id=p.id for update;
 if step='issue'then
  if not exists(select 1 from public.cheongla_profiles where id=actor and approval_status='approved'and membership_state='active'and(is_app_admin or role in('owner','english_director','math_director')))or actor=target_member then raise exception '관리자만 처리할 수 있습니다.'using errcode='42501';end if;
  if length(btrim(reason))not between 2 and 1000 or p.membership_updated_at is distinct from expected_version then raise exception '처리 사유와 최신 회원 상태를 확인해 주세요.';end if;
  if r.completed_at is null and r.busy_until>clock_timestamp()then raise exception '계정 복구 처리 중입니다. 잠시 후 다시 확인해 주세요.';end if;
  old_status:=case when r.completed_at is null then coalesce(r.prior_status,p.approval_status)else p.approval_status end;
  update public.cheongla_profiles set approval_status='pending'where id=p.id returning * into p;
  insert into cheongla_private.manual_recoveries(user_id,actor_id,prior_status,member_version,operation,busy_until,reason)values(p.id,actor,old_status,p.membership_updated_at,operation,clock_timestamp()+interval '1 minute',btrim(reason))on conflict(user_id)do update set actor_id=excluded.actor_id,prior_status=excluded.prior_status,member_version=excluded.member_version,operation=excluded.operation,ready=false,busy_until=excluded.busy_until,reason=excluded.reason,created_at=clock_timestamp(),completed_at=null;
  update public.cheongla_push_subscriptions set enabled=false,updated_at=clock_timestamp()where user_id=p.id;
  insert into cheongla_private.member_actions(member_id,actor_id,action,reason)values(p.id,actor,'manual_recovery',btrim(reason));
 elsif step='issued'then
  if r.operation is distinct from operation or r.actor_id<>actor or r.completed_at is not null then raise exception '복구 요청이 변경되었습니다.';end if;
  update cheongla_private.manual_recoveries set ready=true,busy_until=clock_timestamp()where user_id=p.id;
 elsif step='finish_begin'then
  if actor<>target_member or r.completed_at is not null or not coalesce(r.ready,false)or r.busy_until>clock_timestamp()or p.membership_updated_at is distinct from r.member_version then raise exception '임시 비밀번호 발급 상태를 확인해 주세요.';end if;
  update cheongla_private.manual_recoveries set operation=cheongla_manual_recovery_job.operation,busy_until=clock_timestamp()+interval '1 minute'where user_id=p.id;
 elsif step='finish'then
  if actor<>target_member or r.completed_at is not null or not coalesce(r.ready,false)or r.operation is distinct from operation or p.membership_updated_at is distinct from r.member_version then raise exception '계정 상태가 변경되었습니다. 관리자에게 문의해 주세요.';end if;
  update cheongla_private.manual_recoveries set completed_at=clock_timestamp(),ready=false where user_id=p.id;
  update public.cheongla_profiles set approval_status=r.prior_status where id=p.id;
  insert into cheongla_private.member_actions(member_id,actor_id,action,reason)values(p.id,actor,'recovery_password_changed','본인 새 비밀번호 설정 완료');
 else raise exception 'invalid action';end if;
 return jsonb_build_object('ok',true);
end;$$;
-- Retire paid SMS entry points. Signup still requires manual approval.
create or replace function public.cheongla_signup_access_hook(event jsonb)returns jsonb language sql stable security definer set search_path='' as $$select '{}'::jsonb$$;
revoke all on function public.cheongla_account_recovery_state(),public.cheongla_manual_account(uuid),public.cheongla_manual_recovery_job(uuid,uuid,uuid,text,text,timestamptz),cheongla_private.guard_recovery_approval()from public,anon,authenticated;
grant execute on function public.cheongla_account_recovery_state(),public.cheongla_manual_account(uuid)to authenticated;
grant execute on function public.cheongla_manual_recovery_job(uuid,uuid,uuid,text,text,timestamptz)to service_role;
notify pgrst,'reload schema';
commit;
