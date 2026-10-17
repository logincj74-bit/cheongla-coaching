begin;
-- Append-only evidence for principal bank checks. Existing payments remain authoritative.
create table cheongla_private.bank_confirmations(
 id uuid primary key default gen_random_uuid(),fee_kind text not null check(fee_kind in('tuition','exam','meal')),
 notice_id uuid not null,student_id uuid not null,student_name text not null,billing_month date not null,
 depositor_name text not null check(length(depositor_name)between 1 and 100),deposit_on date not null,
 amount integer not null check(amount>0),note text not null default '' check(length(note)<=1000),
 confirmed_by uuid not null,confirmed_by_name text not null,confirmed_at timestamptz not null default clock_timestamp(),
 payment_updated_at timestamptz not null,unique(fee_kind,notice_id,payment_updated_at)
);
alter table cheongla_private.bank_confirmations enable row level security;
revoke all on cheongla_private.bank_confirmations from public,anon,authenticated;
create index bank_confirmations_month on cheongla_private.bank_confirmations(billing_month,confirmed_at desc);
create or replace function public.cheongla_register_bank_payments(target_month date,deposit_date date,entries jsonb,batch_note text default '')returns jsonb
language plpgsql security definer set search_path='' as $$
declare e jsonb;n record;p record;actor_name text;count_saved integer:=0;total_saved bigint:=0;payer text;stamp timestamptz;kind text;notice uuid;
begin
 if not cheongla_private.can_use_member_services() or not cheongla_private.is_principal() then raise exception '원장만 통장 확인 명단을 등록할 수 있습니다.'using errcode='42501';end if;
 if target_month is null or extract(day from target_month)<>1 or deposit_date is null or deposit_date<'1900-01-01'::date or deposit_date>(now()at time zone'Asia/Seoul')::date then raise exception '청구 월과 실제 입금일을 확인해 주세요.';end if;
 if entries is null or jsonb_typeof(entries)<>'array' then raise exception '입금 확인할 청구를 선택해 주세요.';end if;
 if jsonb_array_length(entries)not between 1 and 100 or batch_note is null or length(batch_note)>1000 then raise exception '한 번에 1~100건을 선택하고 메모는 1,000자 이내로 입력해 주세요.';end if;
 if exists(select 1 from jsonb_array_elements(entries)x group by x->>'fee_kind',x->>'notice_id'having count(*)>1)then raise exception '같은 청구가 중복 선택되었습니다.';end if;
 select full_name into actor_name from public.cheongla_profiles where id=(select auth.uid());
 for e in select value from jsonb_array_elements(entries)order by value->>'fee_kind',value->>'notice_id'loop
  kind:=e->>'fee_kind';notice:=(e->>'notice_id')::uuid;payer:=btrim(e->>'depositor_name');
  if kind is null or kind not in('tuition','exam','meal')or notice is null or payer is null or length(payer)not between 1 and 100 then raise exception '청구와 입금자명을 확인해 주세요.';end if;
  perform cheongla_private.lock_collection(kind,notice);
  select * into n from cheongla_private.collection_notices where fee_kind=kind and id=notice;
  if not found or n.billing_month<>target_month or n.amount is distinct from (e->>'amount')::integer then raise exception '선택한 월이나 청구 금액이 변경되었습니다. 새로고침 후 다시 선택해 주세요.';end if;
  select * into p from cheongla_private.fee_payments where notice_kind=kind and notice_id=notice for update;
  if p.paid_at is not null then raise exception '이미 입금 완료된 청구가 포함되어 있습니다. 새로고침해 주세요.';end if;
  perform public.cheongla_set_fee_payment(kind,notice,true,(e->>'notice_updated_at')::timestamptz,(e->>'payment_updated_at')::timestamptz);
  select updated_at into stamp from cheongla_private.fee_payments where notice_kind=kind and notice_id=notice;
  insert into cheongla_private.bank_confirmations(fee_kind,notice_id,student_id,student_name,billing_month,depositor_name,deposit_on,amount,note,confirmed_by,confirmed_by_name,payment_updated_at)
   values(kind,notice,n.student_id,n.student_name,n.billing_month,payer,deposit_date,n.amount,btrim(batch_note),(select auth.uid()),coalesce(actor_name,'원장'),stamp);
  count_saved:=count_saved+1;total_saved:=total_saved+n.amount;
 end loop;
 return jsonb_build_object('count',count_saved,'total',total_saved);
end;$$;
create or replace function public.cheongla_bank_confirmation_list(target_month date)returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_use_member_services() or not cheongla_private.can_manage_tuition()then raise exception '원장과 실장만 통장 확인 명단을 조회할 수 있습니다.'using errcode='42501';end if;
 if target_month is null or extract(day from target_month)<>1 then raise exception '청구 월을 선택해 주세요.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'fee_kind',b.fee_kind,'notice_id',b.notice_id,'student_id',b.student_id,'student_name',b.student_name,'depositor_name',b.depositor_name,'deposit_on',b.deposit_on,'amount',b.amount,'note',b.note,'confirmed_by_name',b.confirmed_by_name,'confirmed_at',b.confirmed_at,'payment_updated_at',b.payment_updated_at,'is_current',coalesce(p.paid_at is not null and p.updated_at=b.payment_updated_at and p.paid_amount=b.amount,false))order by b.confirmed_at desc,b.id)from cheongla_private.bank_confirmations b left join cheongla_private.fee_payments p on p.notice_kind=b.fee_kind and p.notice_id=b.notice_id where b.billing_month=target_month),'[]'::jsonb);
end;$$;
revoke all on function public.cheongla_register_bank_payments(date,date,jsonb,text)from public,anon,authenticated;
revoke all on function public.cheongla_bank_confirmation_list(date)from public,anon,authenticated;
grant execute on function public.cheongla_register_bank_payments(date,date,jsonb,text)to authenticated;
grant execute on function public.cheongla_bank_confirmation_list(date)to authenticated;
commit;
