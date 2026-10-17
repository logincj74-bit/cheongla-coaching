begin;
create table cheongla_private.bank_confirmation_checks(
 confirmation_id uuid not null references cheongla_private.bank_confirmations(id),staff_id uuid not null,
 staff_name text not null,checked_at timestamptz not null default clock_timestamp(),primary key(confirmation_id,staff_id)
);
alter table cheongla_private.bank_confirmation_checks enable row level security;
revoke all on cheongla_private.bank_confirmation_checks from public,anon,authenticated;
create or replace function cheongla_private.can_manage_schedule()returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.can_use_member_services()and exists(select 1 from public.cheongla_profiles where id=(select auth.uid())and approval_status='approved'and(is_app_admin or role in('owner','english_director','math_director','manager')));
$$;
create or replace function cheongla_private.can_manage_consultations()returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.can_use_member_services()and exists(select 1 from public.cheongla_profiles where id=(select auth.uid())and approval_status='approved'and role in('owner','english_director','math_director','manager'));
$$;
create or replace function public.cheongla_ack_bank_confirmation(target_confirmation uuid,expected_payment_updated_at timestamptz)returns void
language plpgsql security definer set search_path='' as $$
declare b record;p record;n record;staff_name text;
begin
 if not cheongla_private.can_use_member_services()or not exists(select 1 from public.cheongla_profiles where id=(select auth.uid())and role='manager'and approval_status='approved')then raise exception '실장만 확인 완료를 표시할 수 있습니다.'using errcode='42501';end if;
 select * into b from cheongla_private.bank_confirmations where id=target_confirmation;
 if not found then raise exception '해당 원장 확인 내역이 없습니다.';end if;
 perform cheongla_private.lock_collection(b.fee_kind,b.notice_id);
 select * into p from cheongla_private.fee_payments where notice_kind=b.fee_kind and notice_id=b.notice_id;
 select * into n from cheongla_private.collection_notices where fee_kind=b.fee_kind and id=b.notice_id;
 if n.id is null or n.status<>'published'or not n.eligible or not n.source_current or n.amount<>b.amount or p.paid_at is null or p.updated_at is distinct from b.payment_updated_at or b.payment_updated_at is distinct from expected_payment_updated_at then raise exception '입금 확인 또는 청구 상태가 변경되었습니다. 새로고침해 주세요.';end if;
 select full_name into staff_name from public.cheongla_profiles where id=(select auth.uid());
 insert into cheongla_private.bank_confirmation_checks(confirmation_id,staff_id,staff_name)values(b.id,(select auth.uid()),coalesce(staff_name,'실장'))on conflict do nothing;
end;$$;
create or replace function public.cheongla_bank_confirmation_list(target_month date)returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_use_member_services()or not cheongla_private.can_manage_tuition()then raise exception '원장과 실장만 통장 확인 명단을 조회할 수 있습니다.'using errcode='42501';end if;
 if target_month is null or extract(day from target_month)<>1 then raise exception '청구 월을 선택해 주세요.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'fee_kind',b.fee_kind,'notice_id',b.notice_id,'student_id',b.student_id,'student_name',b.student_name,'depositor_name',b.depositor_name,'deposit_on',b.deposit_on,'amount',b.amount,'note',b.note,'confirmed_by_name',b.confirmed_by_name,'confirmed_at',b.confirmed_at,'payment_updated_at',b.payment_updated_at,'is_current',coalesce(p.paid_at is not null and p.updated_at=b.payment_updated_at and p.paid_amount=b.amount,false),'staff_checks',coalesce((select jsonb_agg(jsonb_build_object('staff_name',c.staff_name,'checked_at',c.checked_at)order by c.checked_at,c.staff_id)from cheongla_private.bank_confirmation_checks c where c.confirmation_id=b.id),'[]'::jsonb))order by b.confirmed_at desc,b.id)from cheongla_private.bank_confirmations b left join cheongla_private.fee_payments p on p.notice_kind=b.fee_kind and p.notice_id=b.notice_id where b.billing_month=target_month),'[]'::jsonb);
end;$$;
revoke all on function public.cheongla_ack_bank_confirmation(uuid,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_ack_bank_confirmation(uuid,timestamptz)to authenticated;
revoke all on function cheongla_private.can_manage_schedule(),cheongla_private.can_manage_consultations()from public,anon;
grant execute on function cheongla_private.can_manage_schedule(),cheongla_private.can_manage_consultations()to authenticated;
commit;
