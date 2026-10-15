-- 040, 041 적용 후 실행. 초안 삭제는 복구 가능한 휴지통 이동입니다.
begin;
alter table public.cheongla_tuition_notices add column if not exists deleted_at timestamptz,add column if not exists deleted_by uuid;
alter table public.cheongla_tuition_notices drop constraint if exists tuition_deleted_draft_only;
alter table public.cheongla_tuition_notices add constraint tuition_deleted_draft_only check(deleted_at is null or (archived_at is not null and status='draft'));
alter table cheongla_private.tuition_draft_actions drop constraint if exists tuition_draft_actions_action_check;
alter table cheongla_private.tuition_draft_actions add constraint tuition_draft_actions_action_check check(action in('reset','restore','delete','undelete'));
create or replace function public.cheongla_trash_tuition_draft(target_notice uuid,expected_updated_at timestamptz,restore_draft boolean default false)
returns uuid language plpgsql security definer set search_path=''as $$
declare n public.cheongla_tuition_notices%rowtype;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 초기화한 초안을 삭제하거나 삭제 복구할 수 있습니다.'using errcode='42501';end if;
 if restore_draft is null then raise exception '처리 내용을 확인해 주세요.';end if;
 perform cheongla_private.lock_collection('tuition',target_notice);
 select * into n from public.cheongla_tuition_notices where id=target_notice;
 if not found then raise exception '초안을 찾을 수 없습니다. 목록을 새로고침해 주세요.';end if;
 if n.updated_at is distinct from expected_updated_at then raise exception '안내가 변경되었습니다. 새로고침 후 다시 처리해 주세요.';end if;
 if n.status<>'draft'or n.archived_at is null then raise exception '초기화한 초안만 삭제할 수 있습니다.';end if;
 if exists(select 1 from cheongla_private.fee_payments p where p.notice_kind='tuition'and p.notice_id=n.id)
 or exists(select 1 from cheongla_private.fee_deposit_reports r where r.fee_kind='tuition'and r.notice_id=n.id)
 or exists(select 1 from cheongla_private.fee_payment_events e where e.fee_kind='tuition'and e.notice_id=n.id)then raise exception '입금 알림이나 수납 이력이 있는 안내는 삭제할 수 없습니다.';end if;
 if restore_draft and n.deleted_at is null then raise exception '이미 복구된 초안입니다.';end if;
 if not restore_draft and n.deleted_at is not null then raise exception '이미 삭제한 초안입니다.';end if;
 insert into cheongla_private.tuition_draft_actions(notice_id,actor_id,action,snapshot)values(n.id,auth.uid(),case when restore_draft then 'undelete'else 'delete'end,to_jsonb(n));
 update public.cheongla_tuition_notices set deleted_at=case when restore_draft then null else clock_timestamp()end,deleted_by=case when restore_draft then null else auth.uid()end,updated_at=clock_timestamp()where id=n.id;
 return n.id;
end;$$;
revoke all on function public.cheongla_trash_tuition_draft(uuid,timestamptz,boolean)from public,anon,authenticated;
grant execute on function public.cheongla_trash_tuition_draft(uuid,timestamptz,boolean)to authenticated;
-- Prevent the old restore route from clearing the archive flag on a trashed draft.
-- A new student/month draft may reuse the row, preserving the deletion snapshot in the audit log.
do $patch$
declare source text;patched text;
begin
 source:=pg_get_functiondef('public.cheongla_reset_tuition_draft(uuid,timestamptz,boolean)'::regprocedure);
 if source not like '%n.deleted_at%'then
  patched:=replace(source,'if n.status<>',E'if n.deleted_at is not null then raise exception ''삭제한 초안은 휴지통에서 먼저 복구해 주세요.'';end if;\n if n.status<>');
  if patched=source then raise exception '초안 초기화 함수 버전을 확인해 주세요.';end if;execute patched;
 end if;
 source:=pg_get_functiondef('public.cheongla_save_tuition_notice_v3(uuid,date,date,text,text,timestamptz,text,date,date,date[],boolean)'::regprocedure);
 if source not like '%deleted_at=null%'then
  patched:=replace(source,'do update set archived_at=null,archived_by=null,','do update set archived_at=null,archived_by=null,deleted_at=null,deleted_by=null,');
  if patched=source then raise exception '학원비 계산 함수 버전을 확인해 주세요.';end if;execute patched;
 end if;
end;$patch$;
notify pgrst,'reload schema';
commit;
