begin;
create table if not exists cheongla_private.exam_purge_events(
 id bigint generated always as identity primary key,exam_id uuid not null,actor_id uuid not null,
 application_count integer not null,fee_count integer not null,created_at timestamptz not null default clock_timestamp()
);
alter table cheongla_private.exam_purge_events enable row level security;
revoke all on cheongla_private.exam_purge_events from public,anon,authenticated;
create or replace function public.cheongla_purge_deleted_exam(target_exam uuid,expected_updated_at timestamptz,expected_deleted_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare e public.cheongla_exams%rowtype;notice uuid;fees uuid[];applications integer;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 삭제한 시험을 영구 삭제할 수 있습니다.'using errcode='42501';end if;
 select * into e from public.cheongla_exams where id=target_exam for update;
 if not found then raise exception '이미 영구 삭제되었거나 없는 시험입니다.';end if;
 if e.updated_at is distinct from expected_updated_at or e.deleted_at is distinct from expected_deleted_at then raise exception '시험 정보가 변경되었습니다. 시험 새로고침 후 확인해 주세요.';end if;
 if e.deleted_at is null then raise exception '삭제한 시험 목록의 시험만 영구 삭제할 수 있습니다.';end if;
 -- Root and application locks prevent concurrent re-application/new fee notices.
 perform 1 from public.cheongla_exam_applications where exam_id=e.id order by student_id for update;
 select count(*) into applications from public.cheongla_exam_applications where exam_id=e.id;
 select coalesce(array_agg(id order by id),'{}'::uuid[])into fees from public.cheongla_exam_fee_notices where exam_id=e.id;
 foreach notice in array fees loop perform cheongla_private.lock_collection('exam',notice);end loop;
 if exists(select 1 from cheongla_private.fee_payments where notice_kind='exam'and notice_id=any(fees))
 or exists(select 1 from cheongla_private.fee_deposit_reports where fee_kind='exam'and notice_id=any(fees))
 or exists(select 1 from cheongla_private.fee_payment_events where fee_kind='exam'and notice_id=any(fees))
 or exists(select 1 from cheongla_private.bank_confirmations where fee_kind='exam'and notice_id=any(fees))then
  raise exception '수납·입금 알림 이력이 있는 시험은 기록 보존을 위해 영구 삭제할 수 없습니다. 삭제 상태로 보관해 주세요.';
 end if;
 insert into cheongla_private.exam_purge_events(exam_id,actor_id,application_count,fee_count)values(e.id,auth.uid(),applications,cardinality(fees));
 -- Remove stale links; push queue rows cascade from notification deletion.
 delete from public.cheongla_notifications where(source_kind in('exam','application')and source_id=e.id)
 or(source_kind in('exam_fee','fee_collection')and source_id=any(fees));
 -- Existing FK cascades remove the applications, uncollected fee notices and fee settings.
 delete from public.cheongla_exams where id=e.id;
 return e.id;
end;$$;
revoke all on function public.cheongla_purge_deleted_exam(uuid,timestamptz,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_purge_deleted_exam(uuid,timestamptz,timestamptz)to authenticated;
notify pgrst,'reload schema';
commit;
