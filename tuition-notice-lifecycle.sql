create or replace function public.cheongla_tuition_notice_action(target_notice uuid, expected_updated_at timestamptz, action text)
returns void language plpgsql security definer set search_path='' as $$
declare n public.cheongla_tuition_notices%rowtype;
begin
 if not cheongla_private.can_manage_tuition() then raise insufficient_privilege;end if;
 perform cheongla_private.lock_collection('tuition',target_notice);
 select * into n from public.cheongla_tuition_notices where id=target_notice for update;
 if not found or n.updated_at is distinct from expected_updated_at then raise exception '안내가 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 if action='purge' then perform public.cheongla_purge_tuition_draft(target_notice,expected_updated_at);return;end if;
 if action not in ('trash','restore') or action is null then raise exception '처리 항목을 확인해 주세요.';end if;
 if action='trash' and n.deleted_at is not null then raise exception '이미 휴지통에 있습니다.';end if;
 if action='restore' and n.deleted_at is null then raise exception '휴지통 항목만 복구할 수 있습니다.';end if;
 insert into cheongla_private.tuition_draft_actions(notice_id,actor_id,action,snapshot) values(n.id,auth.uid(),case when action='trash' then 'delete' else 'undelete' end,to_jsonb(n));
 update public.cheongla_tuition_notices set status='draft',published_at=null,
 archived_at=case when action='trash' then clock_timestamp() else null end,
 archived_by=case when action='trash' then auth.uid() else null end,
 deleted_at=case when action='trash' then clock_timestamp() else null end,
 deleted_by=case when action='trash' then auth.uid() else null end,updated_at=clock_timestamp() where id=n.id;
 update cheongla_private.push_deliveries d set state='cancelled',finished_at=clock_timestamp() from public.cheongla_notifications x where x.id=d.notification_id and x.source_id=n.id and d.state in ('pending','failed');
end;$$;
revoke all on function public.cheongla_tuition_notice_action(uuid,timestamptz,text) from public,anon;
grant execute on function public.cheongla_tuition_notice_action(uuid,timestamptz,text) to authenticated;
do $p$ declare s text;begin
s:=pg_get_functiondef('public.cheongla_purge_tuition_draft(uuid,timestamptz)'::regprocedure);
s:=replace(s,'cheongla_private.is_principal()','cheongla_private.can_manage_tuition()');
s:=replace(s,'원장만 휴지통을 영구 삭제할 수 있습니다.','원장·실장만 휴지통을 영구 삭제할 수 있습니다.');execute s;end;$p$;