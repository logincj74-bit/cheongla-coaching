begin;
create or replace function public.cheongla_manage_member(target_member uuid,member_action text,action_reason text,expected_member_version timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare m public.cheongla_profiles%rowtype;
begin
 perform pg_catalog.pg_advisory_xact_lock(7492052);
 if not cheongla_private.is_principal() then raise exception '원장만 강제 탈퇴와 이용 중지를 처리할 수 있습니다.' using errcode='42501';end if;
 if member_action is null or member_action not in ('suspend','restore','withdraw') or action_reason is null or length(btrim(action_reason)) not between 2 and 1000 then raise exception '처리 종류와 사유를 확인해 주세요.';end if;
 select * into m from public.cheongla_profiles where id=target_member for update;
 if not found or m.id=(select auth.uid()) or m.is_app_admin or m.role in ('owner','english_director','math_director') then raise exception '본인·원장·앱 관리자 계정을 제외한 회원만 처리할 수 있습니다.' using errcode='42501';end if;
 if m.membership_updated_at is distinct from expected_member_version then raise exception '회원 상태가 변경되었습니다. 목록을 새로고침해 주세요.';end if;
 if m.membership_state='withdrawn' then raise exception '이미 탈퇴 처리된 회원입니다.';end if;
 if member_action='restore' and m.approval_status<>'suspended' then raise exception '이용 중지된 회원만 복원할 수 있습니다.';end if;
 update public.cheongla_profiles set approval_status=case when member_action='restore' then 'approved' else 'suspended' end,
 membership_state=case when member_action='withdraw' then 'withdrawn' else 'active' end,
 withdrawn_at=case when member_action='withdraw' then clock_timestamp() else null end where id=m.id;
 if member_action<>'restore' then update public.cheongla_push_subscriptions set enabled=false,updated_at=clock_timestamp() where user_id=m.id;end if;
 insert into cheongla_private.member_actions(member_id,actor_id,action,reason) values(m.id,(select auth.uid()),member_action,btrim(action_reason));
 return m.id;
end;$$;
create or replace function public.cheongla_member_action_history(target_member uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not(cheongla_private.is_app_admin()or cheongla_private.is_principal())then raise exception '앱 관리자만 처리 기록을 확인할 수 있습니다.' using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (select action,reason,created_at from cheongla_private.member_actions where member_id=target_member order by created_at desc,id desc limit 20) x),'[]'::jsonb);
end;$$;
create or replace function public.cheongla_list_members_for_lifecycle()returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.is_principal()then raise exception '원장만 회원 탈퇴 관리 목록을 확인할 수 있습니다.'using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(p)order by p.created_at desc,p.id)from(select id,full_name,role,approval_status,is_app_admin,membership_state,membership_updated_at,created_at from public.cheongla_profiles)p),'[]'::jsonb);
end;$$;
revoke all on function public.cheongla_list_members_for_lifecycle()from public,anon,authenticated;
grant execute on function public.cheongla_list_members_for_lifecycle()to authenticated;
notify pgrst,'reload schema';
commit;
