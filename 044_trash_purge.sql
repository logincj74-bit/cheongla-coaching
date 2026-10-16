begin;
create table if not exists cheongla_private.trash_purge_events(id bigint generated always as identity primary key,kind text not null check(kind in('tuition','meal')),source_id uuid not null,actor_id uuid not null,created_at timestamptz not null default clock_timestamp());
alter table cheongla_private.trash_purge_events enable row level security;
revoke all on cheongla_private.trash_purge_events from public,anon,authenticated;
create or replace function public.cheongla_purge_tuition_draft(target_notice uuid,expected_updated_at timestamptz)
returns void language plpgsql security definer set search_path=''as $$
declare n public.cheongla_tuition_notices%rowtype;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 휴지통을 영구 삭제할 수 있습니다.'using errcode='42501';end if;
 perform cheongla_private.lock_collection('tuition',target_notice);
 select * into n from public.cheongla_tuition_notices where id=target_notice;
 if not found then raise exception '이미 삭제되었거나 찾을 수 없는 초안입니다.';end if;
 if n.updated_at is distinct from expected_updated_at then raise exception '안내가 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 if n.deleted_at is null or n.archived_at is null or n.status<>'draft'then raise exception '휴지통에 있는 초안만 영구 삭제할 수 있습니다.';end if;
 if exists(select 1 from cheongla_private.fee_payments p where p.notice_kind='tuition'and p.notice_id=n.id)
 or exists(select 1 from cheongla_private.fee_deposit_reports r where r.fee_kind='tuition'and r.notice_id=n.id)
 or exists(select 1 from cheongla_private.fee_payment_events e where e.fee_kind='tuition'and e.notice_id=n.id)then raise exception '입금 알림이나 수납 이력이 있는 안내는 영구 삭제할 수 없습니다.';end if;
 update cheongla_private.tuition_draft_actions set snapshot='{}'::jsonb where notice_id=n.id;
 insert into cheongla_private.trash_purge_events(kind,source_id,actor_id)values('tuition',n.id,auth.uid());
 delete from public.cheongla_tuition_notices where id=n.id;
end;$$;
create or replace function public.cheongla_purge_meal_submission(target_trash uuid,expected_deleted_at timestamptz)
returns void language plpgsql security definer set search_path=''as $$
declare t cheongla_private.meal_submission_trash%rowtype;b uuid;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 휴지통을 영구 삭제할 수 있습니다.'using errcode='42501';end if;
 select * into t from cheongla_private.meal_submission_trash where id=target_trash for update;
 if not found then raise exception '이미 삭제되었거나 찾을 수 없는 신청서입니다.';end if;
 if t.deleted_at is distinct from expected_deleted_at then raise exception '삭제 내용이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 if t.restored_at is not null then raise exception '이미 복구한 신청서는 휴지통에서 영구 삭제할 수 없습니다.';end if;
 b:=(t.bill_snapshot->>'id')::uuid;
 if b is not null and(exists(select 1 from cheongla_private.fee_payments p where p.notice_kind='meal'and p.notice_id=b)
 or exists(select 1 from cheongla_private.fee_deposit_reports r where r.fee_kind='meal'and r.notice_id=b)
 or exists(select 1 from cheongla_private.fee_payment_events e where e.fee_kind='meal'and e.notice_id=b))then raise exception '입금 알림이나 수납 이력이 있는 신청서는 영구 삭제할 수 없습니다.';end if;
 insert into cheongla_private.trash_purge_events(kind,source_id,actor_id)values('meal',t.id,auth.uid());
 delete from cheongla_private.meal_submission_trash where id=t.id;
end;$$;
revoke all on function public.cheongla_purge_tuition_draft(uuid,timestamptz),public.cheongla_purge_meal_submission(uuid,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_purge_tuition_draft(uuid,timestamptz),public.cheongla_purge_meal_submission(uuid,timestamptz)to authenticated;
notify pgrst,'reload schema';
commit;
