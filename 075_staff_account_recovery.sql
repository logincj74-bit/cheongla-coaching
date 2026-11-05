create or replace function cheongla_private.can_recover_target(actor uuid,target_member uuid)returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.cheongla_profiles a cross join public.cheongla_profiles p where a.id=actor and p.id=target_member and a.id<>p.id and a.approval_status='approved'and a.membership_state='active'and a.role in('owner','english_director','math_director','manager')and p.membership_state='active'and p.approval_status not in('suspended','rejected')and(
 (p.role in('student','parent')and not p.is_app_admin)or
 (a.role in('owner','english_director','math_director')and p.role in('owner','english_director','math_director','manager','korean_teacher')and(not p.is_app_admin or a.is_app_admin))
));$$;
revoke all on function cheongla_private.can_recover_target(uuid,uuid)from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.cheongla_manual_account(target_member uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not cheongla_private.can_manage_account_recovery()then raise exception '원장·실장만 확인할 수 있습니다.'using errcode='42501';end if;
 return(select jsonb_build_object('email',u.email,'phone',r.phone,'login_phone',case when u.email like '%@phone.cheongla.invalid'then regexp_replace(u.raw_user_meta_data->>'contact_phone','[^0-9]','','g')else null end,'name',p.full_name,'role',p.role,'version',p.membership_updated_at,'recovering',exists(select 1 from cheongla_private.manual_recoveries m where m.user_id=p.id and m.completed_at is null))from public.cheongla_profiles p join auth.users u on u.id=p.id left join cheongla_private.recovery_phones r on r.user_id=p.id where p.id=target_member and cheongla_private.can_recover_target(auth.uid(),p.id));
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_manual_recovery_job(actor uuid, target_member uuid, operation uuid, step text, reason text DEFAULT ''::text, expected_version timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.cheongla_profiles%rowtype;r cheongla_private.manual_recoveries%rowtype;old_status text;
begin
 if auth.role()is distinct from 'service_role'then raise exception 'server only'using errcode='42501';end if;
 perform pg_advisory_xact_lock(7492052);
 select * into p from public.cheongla_profiles where id=target_member for update;
 if not found or p.membership_state<>'active'or p.role not in('student','parent','owner','english_director','math_director','manager','korean_teacher')or p.approval_status in('suspended','rejected')then raise exception '이 계정은 복구할 수 없습니다.';end if;
 select * into r from cheongla_private.manual_recoveries where user_id=p.id for update;
 if step='issue'then
  if not cheongla_private.can_recover_target(actor,target_member) then raise exception '관리자만 처리할 수 있습니다.'using errcode='42501';end if;
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
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_recovery_member_search(search_name text, search_phone text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q text:=trim(coalesce(search_name,''));number text:=regexp_replace(coalesce(search_phone,''),'[^0-9]','','g');
begin
 if not cheongla_private.can_manage_account_recovery()then raise exception '원장·실장만 회원 복구 정보를 검색할 수 있습니다.'using errcode='42501';end if;
 if length(q)<2 or length(q)>60 or(number<>''and number!~'^01[016789][0-9]{7,8}$')then raise exception '이름은 두 글자 이상 입력하고 번호는 전체를 입력해 주세요.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role',p.role,'membership_state',p.membership_state,'is_app_admin',p.is_app_admin,'approval_status',p.approval_status))from public.cheongla_profiles p left join cheongla_private.recovery_phones r on r.user_id=p.id where p.full_name ilike '%'||q||'%'and(number=''or r.phone=number)and cheongla_private.can_recover_target(auth.uid(),p.id)),'[]'::jsonb);
end;$function$
;
notify pgrst,'reload schema';
create or replace function public.cheongla_register_staff_recovery_phone(target_member uuid,phone_number text,verification_note text,expected_version timestamptz)returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.cheongla_profiles%rowtype;number text:=regexp_replace(coalesce(phone_number,''),'[^0-9]','','g');
begin
 if not cheongla_private.is_principal()or not cheongla_private.can_recover_target(auth.uid(),target_member)then raise exception '원장만 다른 교직원의 누락된 복구 번호를 등록할 수 있습니다.'using errcode='42501';end if;
 perform pg_advisory_xact_lock(7492052);select *into p from public.cheongla_profiles where id=target_member for update;
 if p.role not in('owner','english_director','math_director','manager','korean_teacher')or p.membership_updated_at is distinct from expected_version then raise exception '교직원 정보가 변경되었습니다. 다시 확인해 주세요.';end if;
 if number!~'^01[016789][0-9]{7,8}$'or length(btrim(coalesce(verification_note,'')))not between 2 and 1000 then raise exception '본인 휴대전화번호와 대면·통화 확인 방법을 입력해 주세요.';end if;
 if exists(select 1 from cheongla_private.recovery_phones where user_id=p.id and phone<>'')then raise exception '이미 등록된 복구 번호는 이 화면에서 바꿀 수 없습니다.';end if;
 insert into cheongla_private.recovery_phones(user_id,phone,verified_at)values(p.id,number,null)on conflict(user_id)do update set phone=excluded.phone,verified_at=null;
 insert into cheongla_private.member_contacts(user_id,phone)values(p.id,number)on conflict(user_id)do nothing;
 update public.cheongla_profiles set membership_updated_at=clock_timestamp()where id=p.id;
 insert into cheongla_private.member_actions(member_id,actor_id,action,reason)values(p.id,auth.uid(),'staff_recovery_phone_registered',btrim(verification_note));
 return jsonb_build_object('ok',true);
end;$$;
revoke all on function public.cheongla_register_staff_recovery_phone(uuid,text,text,timestamptz)from public,anon;
grant execute on function public.cheongla_register_staff_recovery_phone(uuid,text,text,timestamptz)to authenticated;
notify pgrst,'reload schema';
