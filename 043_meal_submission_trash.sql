begin;
create table if not exists cheongla_private.meal_submission_trash(
 id uuid primary key default gen_random_uuid(),month date not null,student_id uuid not null,student_name text not null,
 submission_snapshot jsonb not null,bill_snapshot jsonb,deleted_by uuid not null,deleted_at timestamptz not null default clock_timestamp(),
 restored_by uuid,restored_at timestamptz
);
alter table cheongla_private.meal_submission_trash enable row level security;
revoke all on cheongla_private.meal_submission_trash from public,anon,authenticated;
create or replace function public.cheongla_trash_meal_submission(target_month date,target_student uuid,expected_submission_updated_at timestamptz,expected_bill_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path=''as $$
declare s public.cheongla_meal_submissions%rowtype;b public.cheongla_meal_bills%rowtype;result uuid;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 도시락 신청서를 삭제할 수 있습니다.'using errcode='42501';end if;
 perform 1 from public.cheongla_meal_forms where month=target_month for update;
 select * into s from public.cheongla_meal_submissions where month=target_month and student_id=target_student for update;
 if not found then raise exception '신청서를 찾을 수 없습니다. 명단을 새로고침해 주세요.';end if;
 if s.updated_at is distinct from expected_submission_updated_at then raise exception '신청 내용이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 select * into b from public.cheongla_meal_bills where month=target_month and student_id=target_student;
 if b.id is not null then
  perform cheongla_private.lock_collection('meal',b.id);
  select * into b from public.cheongla_meal_bills where month=target_month and student_id=target_student for update;
 end if;
 if b.updated_at is distinct from expected_bill_updated_at then raise exception '청구 내용이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 if b.id is not null then
  if b.status<>'draft'then raise exception '게시된 도시락비 청구는 먼저 게시 취소해 주세요.';end if;
  if exists(select 1 from cheongla_private.fee_payments p where p.notice_kind='meal'and p.notice_id=b.id)
  or exists(select 1 from cheongla_private.fee_deposit_reports r where r.fee_kind='meal'and r.notice_id=b.id)
  or exists(select 1 from cheongla_private.fee_payment_events e where e.fee_kind='meal'and e.notice_id=b.id)then raise exception '입금 알림이나 수납 이력이 있는 신청서는 삭제할 수 없습니다.';end if;
 end if;
 insert into cheongla_private.meal_submission_trash(month,student_id,student_name,submission_snapshot,bill_snapshot,deleted_by)
 values(s.month,s.student_id,s.student_name,to_jsonb(s),case when b.id is not null then to_jsonb(b)end,auth.uid())returning id into result;
 delete from public.cheongla_meal_bills where month=target_month and student_id=target_student;
 delete from public.cheongla_meal_submissions where month=target_month and student_id=target_student;
 return result;
end;$$;
create or replace function public.cheongla_deleted_meal_submissions(target_month date)
returns jsonb language plpgsql stable security definer set search_path=''as $$
begin
 if not cheongla_private.is_principal()then raise exception '원장만 삭제한 신청서를 확인할 수 있습니다.'using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'month',t.month,'student_id',t.student_id,'student_name',t.student_name,
 'lunch_count',jsonb_array_length(t.submission_snapshot->'lunch'),'dinner_count',jsonb_array_length(t.submission_snapshot->'dinner'),'deleted_at',t.deleted_at)order by t.deleted_at desc)
 from cheongla_private.meal_submission_trash t where t.month=target_month and t.restored_at is null),'[]'::jsonb);
end;$$;
create or replace function public.cheongla_restore_meal_submission(target_trash uuid)
returns void language plpgsql security definer set search_path=''as $$
declare t cheongla_private.meal_submission_trash%rowtype;s public.cheongla_meal_submissions%rowtype;b public.cheongla_meal_bills%rowtype;f public.cheongla_meal_forms%rowtype;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 삭제한 신청서를 복구할 수 있습니다.'using errcode='42501';end if;
 select * into t from cheongla_private.meal_submission_trash where id=target_trash;
 if not found then raise exception '삭제한 신청서를 찾을 수 없습니다.';end if;
 select * into f from public.cheongla_meal_forms where month=t.month for update;
 if not found then raise exception '해당 월 신청서 설정을 확인해 주세요.';end if;
 select * into t from cheongla_private.meal_submission_trash where id=target_trash for update;
 if t.restored_at is not null then raise exception '이미 복구한 신청서입니다.';end if;
 if exists(select 1 from public.cheongla_meal_submissions where month=t.month and student_id=t.student_id)then raise exception '학생이 새 신청서를 제출했습니다. 현재 신청서를 확인해 주세요.';end if;
 if not exists(select 1 from public.cheongla_profiles where id=t.student_id and role='student'and approval_status='approved'and membership_state='active')then raise exception '승인된 재원생의 신청서만 복구할 수 있습니다.';end if;
 s:=jsonb_populate_record(null::public.cheongla_meal_submissions,t.submission_snapshot);
 s.updated_at:=clock_timestamp();
 insert into public.cheongla_meal_submissions select (s).*;
 if t.bill_snapshot is not null then
  b:=jsonb_populate_record(null::public.cheongla_meal_bills,t.bill_snapshot);
  if b.unit_price<>f.unit_price then raise exception '식사 단가가 변경되어 복구할 수 없습니다. 신청 내역과 청구 금액을 먼저 확인해 주세요.';end if;
  b.updated_at:=clock_timestamp();b.source_updated_at:=s.updated_at;b.status:='draft';b.published_at:=null;
  insert into public.cheongla_meal_bills select (b).*;
 end if;
 update cheongla_private.meal_submission_trash set restored_at=clock_timestamp(),restored_by=auth.uid()where id=t.id;
end;$$;
revoke all on function public.cheongla_trash_meal_submission(date,uuid,timestamptz,timestamptz),public.cheongla_deleted_meal_submissions(date),public.cheongla_restore_meal_submission(uuid)from public,anon,authenticated;
grant execute on function public.cheongla_trash_meal_submission(date,uuid,timestamptz,timestamptz),public.cheongla_deleted_meal_submissions(date),public.cheongla_restore_meal_submission(uuid)to authenticated;
notify pgrst,'reload schema';
commit;
