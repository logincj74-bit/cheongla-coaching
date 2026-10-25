-- Applied through Supabase SQL Editor; verified with rollback tests.
create or replace function public.cheongla_purge_meal_submission(target_trash uuid,expected_deleted_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare t cheongla_private.meal_submission_trash%rowtype;b uuid;
begin
 if not cheongla_private.is_principal() then raise exception '원장만 영구 삭제할 수 있습니다.' using errcode='42501';end if;
 select * into t from cheongla_private.meal_submission_trash where id=target_trash;
 if not found then raise exception '삭제한 신청서가 없습니다.';end if;
 perform 1 from public.cheongla_meal_forms where month=t.month for update;
 select * into t from cheongla_private.meal_submission_trash where id=target_trash for update;
 if not found or t.deleted_at is distinct from expected_deleted_at or t.restored_at is not null then raise exception '휴지통 상태가 변경되었습니다. 새로고침해 주세요.';end if;
 b:=(t.bill_snapshot->>'id')::uuid;
 if t.submission_snapshot->>'_soft_archive'='true' then
  if not exists(select 1 from public.cheongla_meal_submissions s where s.month=t.month and s.student_id=t.student_id and s.archived_at is not null) then raise exception '현재 신청서를 확인해 주세요.';end if;
  if b is not null then
   perform cheongla_private.lock_collection('meal',b);
   if not exists(select 1 from public.cheongla_meal_bills x where x.id=b and x.archived_at is not null) then raise exception '현재 청구를 확인해 주세요.';end if;
   delete from public.cheongla_meal_bills where id=b and archived_at is not null;
  end if;
  delete from public.cheongla_meal_submissions where month=t.month and student_id=t.student_id and archived_at is not null;
 end if;
 -- Financial payment/report/event records are retained separately.
 insert into cheongla_private.trash_purge_events(kind,source_id,actor_id) values('meal',t.id,auth.uid());
 delete from cheongla_private.meal_submission_trash where id=t.id;
end;$$;
