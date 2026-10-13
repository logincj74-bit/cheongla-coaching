-- 022 연락처 설정 적용 후 실행합니다. 기존 납부 기록은 변경하지 않습니다.
begin;
create table if not exists cheongla_private.fee_payments (
 notice_kind text not null check(notice_kind in ('tuition','exam')),
 notice_id uuid not null,
 paid_at timestamptz,
 paid_amount integer,
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid references auth.users(id) on delete set null,
 primary key(notice_kind,notice_id),
 check((paid_at is null and paid_amount is null) or (paid_at is not null and paid_amount>=0))
);
alter table cheongla_private.fee_payments enable row level security;
revoke all on cheongla_private.fee_payments from public,anon,authenticated;

create or replace function public.cheongla_fee_payment_states(fee_kind text,notice_ids uuid[])
returns table(notice_id uuid,paid_at timestamptz,paid_amount integer,payment_updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if fee_kind is null or fee_kind not in ('tuition','exam') or coalesce(cardinality(notice_ids),0)>500 then
  raise exception '납부 안내 종류와 조회 범위를 확인해 주세요.';
 end if;
 return query
 with notices as (
  select t.id,t.student_id,null::uuid as exam_id,t.status from public.cheongla_tuition_notices t
  where fee_kind='tuition' and t.id=any(notice_ids)
  union all
  select e.id,e.student_id,e.exam_id,e.status from public.cheongla_exam_fee_notices e
  where fee_kind='exam' and e.id=any(notice_ids)
 )
 select n.id,p.paid_at,p.paid_amount,p.updated_at from notices n
 left join cheongla_private.fee_payments p on p.notice_kind=fee_kind and p.notice_id=n.id
 where cheongla_private.can_manage_tuition() or (n.status='published' and
 case when fee_kind='tuition' then cheongla_private.can_read_tuition(n.student_id)
 else cheongla_private.can_read_exam_fee(n.exam_id,n.student_id) end);
end;
$$;

create or replace function public.cheongla_set_fee_payment(
 fee_kind text,target_notice uuid,is_paid boolean,
 expected_notice_updated_at timestamptz,expected_payment_updated_at timestamptz
)
returns void language plpgsql security definer set search_path='' as $$
declare amount_due integer;notice_state text;notice_version timestamptz;payment_version timestamptz;
begin
 if not cheongla_private.can_manage_tuition() then
  raise exception '앱 관리자와 실장만 납부를 확인할 수 있습니다.' using errcode='42501';
 end if;
 if fee_kind is null or fee_kind not in ('tuition','exam') or is_paid is null then
  raise exception '납부 처리 내용을 확인해 주세요.';
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(fee_kind||target_notice::text,0));
 if fee_kind='tuition' then
  select amount,status,updated_at into amount_due,notice_state,notice_version
  from public.cheongla_tuition_notices where id=target_notice for update;
 else
  select amount,status,updated_at into amount_due,notice_state,notice_version
  from public.cheongla_exam_fee_notices where id=target_notice for update;
 end if;
 if not found or notice_state<>'published' then raise exception '게시된 납부 안내를 선택해 주세요.';end if;
 if fee_kind='exam' and is_paid and not exists(
  select 1 from public.cheongla_exam_fee_notices n
  join public.cheongla_exam_applications a on a.exam_id=n.exam_id and a.student_id=n.student_id
  where n.id=target_notice and a.status='registered'
 ) then raise exception '신청 취소된 시험은 납부 상태를 먼저 확인해 주세요.';end if;
 if notice_version is distinct from expected_notice_updated_at then
  raise exception '청구 내용이 변경되었습니다. 새로고침 후 처리해 주세요.';
 end if;
 select updated_at into payment_version from cheongla_private.fee_payments
 where notice_kind=fee_kind and notice_id=target_notice for update;
 if payment_version is distinct from expected_payment_updated_at then
  raise exception '납부 상태가 변경되었습니다. 새로고침 후 처리해 주세요.';
 end if;
 insert into cheongla_private.fee_payments(notice_kind,notice_id,paid_at,paid_amount,updated_by)
 values(fee_kind,target_notice,case when is_paid then clock_timestamp() else null end,
 case when is_paid then amount_due else null end,auth.uid())
 on conflict(notice_kind,notice_id) do update set paid_at=excluded.paid_at,
 paid_amount=excluded.paid_amount,updated_at=clock_timestamp(),updated_by=excluded.updated_by;
end;
$$;

create or replace function public.cheongla_fee_sms_recipients(
 fee_kind text,target_notice uuid,expected_updated_at timestamptz
)
returns table(parent_id uuid,parent_name text,phone text)
language plpgsql stable security definer set search_path='' as $$
declare student uuid;exam uuid;amount_due integer;notice_state text;notice_version timestamptz;
begin
 if not cheongla_private.can_manage_tuition() then
  raise exception '앱 관리자와 실장만 납부 문자를 작성할 수 있습니다.' using errcode='42501';
 end if;
 if fee_kind='tuition' then
  select student_id,amount,status,updated_at into student,amount_due,notice_state,notice_version
  from public.cheongla_tuition_notices where id=target_notice;
 elsif fee_kind='exam' then
  select student_id,exam_id,amount,status,updated_at into student,exam,amount_due,notice_state,notice_version
  from public.cheongla_exam_fee_notices where id=target_notice;
 else raise exception '학원비 또는 응시료 안내를 선택해 주세요.';
 end if;
 if not found or notice_state<>'published' then raise exception '학부모에게 게시한 안내만 문자로 작성할 수 있습니다.';end if;
 if notice_version is distinct from expected_updated_at then raise exception '안내가 변경되었습니다. 새로고침해 주세요.';end if;
 if not exists(select 1 from public.cheongla_profiles where id=student and role='student' and approval_status='approved') then
  raise exception '승인된 학생의 납부 안내를 선택해 주세요.';
 end if;
 if fee_kind='exam' and not exists(select 1 from public.cheongla_exam_applications
 where exam_id=exam and student_id=student and status='registered') then
  raise exception '신청 완료 학생의 학부모에게만 응시료를 안내할 수 있습니다.';
 end if;
 if exists(select 1 from cheongla_private.fee_payments p where p.notice_kind=fee_kind and p.notice_id=target_notice
 and p.paid_at is not null and p.paid_amount=amount_due) then
  raise exception '이미 납부 완료된 안내입니다. 납부 상태를 확인해 주세요.';
 end if;
 return query select p.id,p.full_name::text,c.phone from public.cheongla_parent_students l
 join public.cheongla_profiles p on p.id=l.parent_id
 left join cheongla_private.member_contacts c on c.user_id=p.id
 where l.student_id=student and p.role='parent' and p.approval_status='approved'
 order by p.full_name,p.id;
end;
$$;
revoke all on function public.cheongla_fee_payment_states(text,uuid[]),
public.cheongla_set_fee_payment(text,uuid,boolean,timestamptz,timestamptz),
public.cheongla_fee_sms_recipients(text,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_fee_payment_states(text,uuid[]),
public.cheongla_set_fee_payment(text,uuid,boolean,timestamptz,timestamptz),
public.cheongla_fee_sms_recipients(text,uuid,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
