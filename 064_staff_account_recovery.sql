-- Staff may recover ordinary members; staff/admin targets remain excluded.
create or replace function cheongla_private.can_manage_account_recovery()
returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.cheongla_profiles where id=auth.uid() and approval_status='approved' and membership_state='active' and role in('owner','english_director','math_director','manager'));
$$;
revoke all on function cheongla_private.can_manage_account_recovery() from public,anon,authenticated;
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
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role',p.role,'membership_state',p.membership_state,'is_app_admin',p.is_app_admin,'approval_status',p.approval_status))from public.cheongla_profiles p left join cheongla_private.recovery_phones r on r.user_id=p.id where p.full_name ilike '%'||q||'%'and(number=''or r.phone=number)and p.membership_state='active'and p.approval_status not in('suspended','rejected')and p.role in('student','parent')and not p.is_app_admin),'[]'::jsonb);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_manual_account(target_member uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not cheongla_private.can_manage_account_recovery()then raise exception '원장·실장만 확인할 수 있습니다.'using errcode='42501';end if;
 return(select jsonb_build_object('email',u.email,'phone',r.phone,'login_phone',case when u.email like '%@phone.cheongla.invalid'then regexp_replace(u.raw_user_meta_data->>'contact_phone','[^0-9]','','g')else null end,'name',p.full_name,'role',p.role,'version',p.membership_updated_at,'recovering',exists(select 1 from cheongla_private.manual_recoveries m where m.user_id=p.id and m.completed_at is null))from public.cheongla_profiles p join auth.users u on u.id=p.id left join cheongla_private.recovery_phones r on r.user_id=p.id where p.id=target_member and p.role in('student','parent')and not p.is_app_admin and p.membership_state='active'and p.approval_status not in('suspended','rejected'));
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
 if not found or p.membership_state<>'active'or p.is_app_admin or p.role not in('student','parent')or p.approval_status in('suspended','rejected')then raise exception '이 계정은 복구할 수 없습니다.';end if;
 select * into r from cheongla_private.manual_recoveries where user_id=p.id for update;
 if step='issue'then
  if not exists(select 1 from public.cheongla_profiles where id=actor and approval_status='approved'and membership_state='active'and role in('owner','english_director','math_director','manager'))or actor=target_member then raise exception '관리자만 처리할 수 있습니다.'using errcode='42501';end if;
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
CREATE OR REPLACE FUNCTION public.cheongla_request_account_help(visitor_token uuid, submission_token uuid, help_kind text, member_name text, registered_phone text, member_type text, student_name text, known_login text, website_field text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rid uuid;number text:=regexp_replace(coalesce(registered_phone,''),'[^0-9]','','g');people uuid[];
begin
 if coalesce(website_field,'')<>''then return jsonb_build_object('accepted',true);end if;
 if visitor_token is null or submission_token is null or help_kind is null or help_kind not in('id','password')or length(trim(coalesce(member_name,'')))not between 2 and 60 or number!~'^01[016789][0-9]{7,8}$'or member_type is null or member_type not in('student','parent')or length(coalesce(student_name,''))>60 or(member_type='parent'and length(trim(coalesce(student_name,'')))<2)or length(coalesce(known_login,''))>254 then raise exception '이름·가입 당시 번호·회원 구분을 확인해 주세요. 학부모는 자녀 이름도 입력해 주세요.';end if;
 perform pg_advisory_xact_lock(310526);
 if exists(select 1 from cheongla_private.account_help_requests where request_token=submission_token)then return jsonb_build_object('accepted',true);end if;
 -- Quietly absorb excessive requests; never reveal whether a member matches.
 if(select count(*)from cheongla_private.account_help_requests where(phone=number or visitor_id=visitor_token)and created_at>clock_timestamp()-interval'1 hour')>=3 or(select count(*)from cheongla_private.account_help_requests where created_at>clock_timestamp()-interval'1 day')>=100 then return jsonb_build_object('accepted',true);end if;
 insert into cheongla_private.account_help_requests(visitor_id,request_token,purpose,claimant_name,phone,member_role,child_name,login_hint)values(visitor_token,submission_token,help_kind,trim(member_name),number,member_type,trim(coalesce(student_name,'')),trim(coalesce(known_login,'')))returning id into rid;
 select array_agg(id)into people from public.cheongla_profiles where approval_status='approved' and membership_state='active' and role in('owner','english_director','math_director','manager');
 perform cheongla_private.send_notification(people,'account_recovery',rid,null,'아이디·비밀번호 복구 요청이 접수되었습니다.','account_recoveryManagerPanel','account-help:'||rid);
 return jsonb_build_object('accepted',true);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_account_help_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not cheongla_private.can_manage_account_recovery()then raise exception '원장·실장만 계정 복구 요청을 확인할 수 있습니다.'using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(q)-'visitor_id'-'request_token'order by(q.state='pending')desc,q.created_at desc)from(select *from cheongla_private.account_help_requests order by(state='pending')desc,created_at desc limit 100)q),'[]'::jsonb);
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_resolve_account_help(target_request uuid, decision text, decision_note text, expected_updated_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r cheongla_private.account_help_requests%rowtype;
begin
 if not cheongla_private.can_manage_account_recovery()then raise exception '원장·실장만 계정 복구 요청을 처리할 수 있습니다.'using errcode='42501';end if;
 select *into r from cheongla_private.account_help_requests where id=target_request for update;
 if not found or r.updated_at is distinct from expected_updated_at or r.state<>'pending'then raise exception '요청 상태가 변경되었습니다. 새로고침해 주세요.';end if;
 if decision is null or decision not in('done','rejected')or length(trim(coalesce(decision_note,'')))not between 2 and 1000 then raise exception '처리 결과와 확인 내용을 입력해 주세요. 임시비밀번호는 메모에 기록하지 마세요.';end if;
 update cheongla_private.account_help_requests set state=decision,resolution_note=trim(decision_note),resolved_by=auth.uid(),updated_at=clock_timestamp()where id=r.id;
end;$function$
;
CREATE OR REPLACE FUNCTION cheongla_private.can_read_notification(kind text, target uuid, student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select case when kind='account_recovery' then cheongla_private.can_manage_account_recovery() and exists(select 1 from cheongla_private.account_help_requests where id=target) when kind='winter_booking'then exists(select 1 from cheongla_private.winter_bookings r where r.id=target and r.archived_at is null and(cheongla_private.can_manage_winter()or(cheongla_private.can_use_member_services()and r.owner_id=auth.uid())))else cheongla_private.can_read_notification_before_winter(kind,target,student)end;$function$
;
notify pgrst,'reload schema';
