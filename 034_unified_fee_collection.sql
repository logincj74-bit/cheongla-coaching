begin;
alter table public.cheongla_meal_bills add column status text not null default 'draft' check(status in ('draft','published')),add column published_at timestamptz;
alter table cheongla_private.fee_payments drop constraint fee_payments_notice_kind_check;
alter table cheongla_private.fee_payments add constraint fee_payments_notice_kind_check check(notice_kind in ('tuition','exam','meal'));
create table cheongla_private.billing_settings(singleton boolean primary key default true check(singleton),bank_name text not null default '',account_number text not null default '',account_holder text not null default '',note text not null default '',updated_at timestamptz not null default clock_timestamp());
alter table cheongla_private.billing_settings enable row level security;
revoke all on cheongla_private.billing_settings from public,anon,authenticated;
create table cheongla_private.fee_deposit_reports(id uuid primary key default gen_random_uuid(),fee_kind text not null check(fee_kind in ('tuition','exam','meal')),notice_id uuid not null,reported_by uuid not null references public.cheongla_profiles(id),depositor_name text not null,deposit_on date not null,amount integer not null check(amount>0),note text not null default '',notice_updated_at timestamptz not null,state text not null default 'pending' check(state in ('pending','confirmed','rejected','closed')),review_reason text not null default '',reviewed_by uuid,created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp());
create unique index fee_one_pending_report on cheongla_private.fee_deposit_reports(fee_kind,notice_id) where state='pending';
create index fee_report_lookup on cheongla_private.fee_deposit_reports(fee_kind,notice_id,created_at desc);
alter table cheongla_private.fee_deposit_reports enable row level security;
revoke all on cheongla_private.fee_deposit_reports from public,anon,authenticated;
create table cheongla_private.fee_payment_events(id bigint generated always as identity primary key,fee_kind text not null,notice_id uuid not null,is_paid boolean not null,amount integer,actor_id uuid,created_at timestamptz not null default clock_timestamp());
alter table cheongla_private.fee_payment_events enable row level security;
revoke all on cheongla_private.fee_payment_events from public,anon,authenticated;
create view cheongla_private.collection_notices as
 select 'tuition'::text fee_kind,t.id,t.student_id,t.student_name,t.billing_month,t.billing_month::text||' 학원비' as label,t.amount,t.due_on,t.note,t.status,t.updated_at,true as eligible,true as source_current from public.cheongla_tuition_notices t
 union all
 select 'exam',e.id,e.student_id,e.student_name,date_trunc('month',e.exam_on)::date,e.exam_title||' 모의고사비',e.amount,e.due_on,e.note,e.status,e.updated_at,exists(select 1 from public.cheongla_exam_applications a join public.cheongla_exams x on x.id=a.exam_id where a.exam_id=e.exam_id and a.student_id=e.student_id and a.status='registered' and to_jsonb(x)->>'deleted_at' is null),true from public.cheongla_exam_fee_notices e
 union all
 select 'meal',b.id,b.student_id,b.student_name,b.month,b.month::text||' 도시락비',b.amount,b.due_on,b.note,b.status,b.updated_at,true,exists(select 1 from public.cheongla_meal_submissions s where s.month=b.month and s.student_id=b.student_id and s.updated_at=b.source_updated_at) from public.cheongla_meal_bills b;
revoke all on cheongla_private.collection_notices from public,anon,authenticated;
create or replace function cheongla_private.can_read_collection(fee_kind text,target_notice uuid) returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.can_use_member_services() and exists(select 1 from cheongla_private.collection_notices n where n.fee_kind=can_read_collection.fee_kind and n.id=target_notice and (cheongla_private.can_manage_tuition() or (n.fee_kind='meal' and cheongla_private.can_manage_meal_forms()) or (n.status='published' and exists(select 1 from public.cheongla_profiles s where s.id=n.student_id and s.role='student' and s.approval_status='approved') and ((n.student_id=(select auth.uid()) and exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role='student')) or cheongla_private.is_parent_of(n.student_id)))));
$$;
revoke all on function cheongla_private.can_read_collection(text,uuid) from public,anon,authenticated;
create or replace function public.cheongla_billing_config() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin if not cheongla_private.can_use_member_services() then raise exception '승인된 계정으로 이용해 주세요.' using errcode='42501';end if;return coalesce((select to_jsonb(s) from cheongla_private.billing_settings s where singleton),'{}'::jsonb);end;$$;
create or replace function public.cheongla_save_billing_config(bank text,account text,holder text,payment_note text,expected_updated_at timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare old_stamp timestamptz;begin
 if not cheongla_private.can_manage_tuition() then raise exception '앱 관리자·실장만 입금 계좌를 관리할 수 있습니다.' using errcode='42501';end if;
 if bank is null or account is null or holder is null or payment_note is null or length(bank) not between 1 and 60 or length(account) not between 3 and 50 or account !~ '^[0-9 -]+$' or length(holder) not between 1 and 100 or length(payment_note)>1000 then raise exception '은행·계좌번호·예금주를 확인해 주세요.';end if;
 perform pg_catalog.pg_advisory_xact_lock(7492054);select updated_at into old_stamp from cheongla_private.billing_settings where singleton for update;
 if old_stamp is distinct from expected_updated_at then raise exception '입금 계좌가 변경되었습니다. 새로고침해 주세요.';end if;
 insert into cheongla_private.billing_settings(bank_name,account_number,account_holder,note) values(btrim(bank),btrim(account),btrim(holder),btrim(payment_note)) on conflict(singleton) do update set bank_name=excluded.bank_name,account_number=excluded.account_number,account_holder=excluded.account_holder,note=excluded.note,updated_at=clock_timestamp();
end;$$;
create or replace function public.cheongla_fee_collection_states(fee_kind text,notice_ids uuid[]) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if fee_kind is null or fee_kind not in ('tuition','exam','meal') or coalesce(cardinality(notice_ids),0)>1000 then raise exception '비용 종류와 조회 범위를 확인해 주세요.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('notice_id',n.id,'paid_at',p.paid_at,'paid_amount',p.paid_amount,'payment_updated_at',p.updated_at,'report', (select to_jsonb(r) from cheongla_private.fee_deposit_reports r where r.fee_kind=n.fee_kind and r.notice_id=n.id order by (state='pending') desc,created_at desc,id desc limit 1))) from cheongla_private.collection_notices n left join cheongla_private.fee_payments p on p.notice_kind=n.fee_kind and p.notice_id=n.id where n.fee_kind=cheongla_fee_collection_states.fee_kind and n.id=any(notice_ids) and cheongla_private.can_read_collection(n.fee_kind,n.id)),'[]'::jsonb);
end;$$;
create or replace function public.cheongla_billing_list(target_month date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;begin
 if not cheongla_private.can_use_member_services() or target_month is null or extract(day from target_month)<>1 then raise exception '승인 상태와 조회 월을 확인해 주세요.' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('_paymentReady',true,'_payment',(select jsonb_build_object('paid_at',p.paid_at,'paid_amount',p.paid_amount,'payment_updated_at',p.updated_at) from cheongla_private.fee_payments p where p.notice_kind=n.fee_kind and p.notice_id=n.id),'_report',(select to_jsonb(r) from cheongla_private.fee_deposit_reports r where r.fee_kind=n.fee_kind and r.notice_id=n.id order by (state='pending') desc,created_at desc,id desc limit 1)) order by n.student_name,n.fee_kind,n.id),'[]'::jsonb) into rows from cheongla_private.collection_notices n where n.billing_month=target_month and cheongla_private.can_read_collection(n.fee_kind,n.id);
 return jsonb_build_object('items',rows,'today',(now() at time zone 'Asia/Seoul')::date,'can_manage',cheongla_private.can_manage_tuition(),'settings',coalesce((select to_jsonb(s) from cheongla_private.billing_settings s where singleton),'{}'::jsonb));
end;$$;
create or replace function cheongla_private.lock_collection(kind text,target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(kind||target::text,0));
 case kind when 'tuition' then perform 1 from public.cheongla_tuition_notices where id=target for update;when 'exam' then perform 1 from public.cheongla_exam_fee_notices where id=target for update;when 'meal' then perform 1 from public.cheongla_meal_bills where id=target for update;else raise exception '비용 종류를 확인해 주세요.';end case;
end;$$;
revoke all on function cheongla_private.lock_collection(text,uuid) from public,anon,authenticated;
create or replace function cheongla_private.notify_collection(kind text,target uuid,admin_only boolean,label text,event_key text) returns void language plpgsql security definer set search_path='' as $$
declare n record;people uuid[];begin
 select * into n from cheongla_private.collection_notices where fee_kind=kind and id=target;if not found then return;end if;
 select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role='manager' or (not admin_only and (p.id=n.student_id or (p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.student_id=n.student_id and l.parent_id=p.id))));
 perform cheongla_private.send_notification(people,'fee_collection',target,n.student_id,label,'billing_dashboard',event_key);
end;$$;
revoke all on function cheongla_private.notify_collection(text,uuid,boolean,text,text) from public,anon,authenticated;
create or replace function public.cheongla_set_fee_payment(fee_kind text,target_notice uuid,is_paid boolean,expected_notice_updated_at timestamptz,expected_payment_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare n record;payment_version timestamptz;begin
 if not cheongla_private.can_manage_tuition() then raise exception '앱 관리자·실장만 실제 입금을 확인할 수 있습니다.' using errcode='42501';end if;
 if fee_kind is null or fee_kind not in ('tuition','exam','meal') or is_paid is null then raise exception '납부 처리 내용을 확인해 주세요.';end if;
 perform cheongla_private.lock_collection(fee_kind,target_notice);
 select * into n from cheongla_private.collection_notices where collection_notices.fee_kind=cheongla_set_fee_payment.fee_kind and id=target_notice;
 if not found or n.status<>'published' then raise exception '게시된 청구를 선택해 주세요.';end if;
 if n.updated_at is distinct from expected_notice_updated_at then raise exception '청구 내용이 변경되었습니다. 새로고침해 주세요.';end if;
 if is_paid and (not n.eligible or not n.source_current or n.amount<=0) then raise exception '신청 취소·신청 변경 또는 청구 금액을 먼저 확인해 주세요.';end if;
 select updated_at into payment_version from cheongla_private.fee_payments where notice_kind=fee_kind and notice_id=target_notice for update;
 if payment_version is distinct from expected_payment_updated_at then raise exception '납부 상태가 변경되었습니다. 새로고침해 주세요.';end if;
 insert into cheongla_private.fee_payments(notice_kind,notice_id,paid_at,paid_amount,updated_by) values(fee_kind,target_notice,case when is_paid then clock_timestamp() else null end,case when is_paid then n.amount else null end,(select auth.uid())) on conflict(notice_kind,notice_id) do update set paid_at=excluded.paid_at,paid_amount=excluded.paid_amount,updated_at=clock_timestamp(),updated_by=excluded.updated_by;
 insert into cheongla_private.fee_payment_events(fee_kind,notice_id,is_paid,amount,actor_id) values(fee_kind,target_notice,is_paid,case when is_paid then n.amount else null end,(select auth.uid()));
 if is_paid then
  update cheongla_private.fee_deposit_reports r set state=case when r.notice_updated_at=n.updated_at and r.amount=n.amount then 'confirmed' else 'closed' end,reviewed_by=(select auth.uid()),review_reason=case when r.notice_updated_at=n.updated_at and r.amount=n.amount then '학원 실제 입금 확인' else '청구 변경 후 학원 별도 입금 확인' end,updated_at=clock_timestamp() where r.fee_kind=cheongla_set_fee_payment.fee_kind and r.notice_id=target_notice and r.state='pending';
 end if;
 perform cheongla_private.notify_collection(fee_kind,target_notice,false,case when is_paid then '학원에서 입금 완료를 확인했습니다.' else '학원에서 납부 상태를 확인 전으로 변경했습니다.' end,'fee_payment:'||fee_kind||':'||target_notice::text||':'||clock_timestamp()::text);
end;$$;
create or replace function public.cheongla_report_fee_deposit(fee_kind text,target_notice uuid,depositor text,deposit_date date,deposit_amount integer,deposit_note text,expected_notice_updated_at timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare n record;result uuid;begin
 if not cheongla_private.can_use_member_services() or not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role in ('student','parent')) then raise exception '승인된 학생·학부모 계정으로 입금 알림을 등록해 주세요.' using errcode='42501';end if;
 perform cheongla_private.lock_collection(fee_kind,target_notice);
 if not cheongla_private.can_read_collection(fee_kind,target_notice) then raise exception '본인 또는 연결된 자녀의 청구만 알릴 수 있습니다.' using errcode='42501';end if;
 select * into n from cheongla_private.collection_notices where collection_notices.fee_kind=cheongla_report_fee_deposit.fee_kind and id=target_notice;
 if not found or n.status<>'published' or not n.eligible or not n.source_current or n.amount<=0 then raise exception '게시된 청구와 신청 상태를 확인해 주세요.';end if;
 if n.updated_at is distinct from expected_notice_updated_at then raise exception '청구 내용이 변경되었습니다. 새로고침해 주세요.';end if;
 if depositor is null or length(btrim(depositor)) not between 1 and 100 or deposit_date is null or deposit_date>(now() at time zone 'Asia/Seoul')::date or deposit_date<'2000-01-01'::date or deposit_amount is distinct from n.amount or deposit_note is null or length(deposit_note)>1000 then raise exception '실제 입금자명·입금일·청구 전액과 메모를 확인해 주세요. 일부 입금은 학원으로 문의해 주세요.';end if;
 if exists(select 1 from cheongla_private.fee_payments p where p.notice_kind=fee_kind and p.notice_id=target_notice and p.paid_at is not null and p.paid_amount=n.amount) then raise exception '이미 입금 완료로 확인된 청구입니다.';end if;
 if exists(select 1 from cheongla_private.fee_deposit_reports r where r.fee_kind=cheongla_report_fee_deposit.fee_kind and r.notice_id=target_notice and r.state='pending') then raise exception '이미 입금 확인 대기 중입니다. 중복 알림을 등록하지 않아도 됩니다.';end if;
 if (select count(*) from cheongla_private.fee_deposit_reports where reported_by=(select auth.uid()) and created_at>clock_timestamp()-interval '1 day')>=20 then raise exception '입금 알림 등록 횟수를 초과했습니다. 학원에 문의해 주세요.';end if;
 insert into cheongla_private.fee_deposit_reports(fee_kind,notice_id,reported_by,depositor_name,deposit_on,amount,note,notice_updated_at) values(fee_kind,target_notice,(select auth.uid()),btrim(depositor),deposit_date,deposit_amount,btrim(deposit_note),n.updated_at) returning id into result;
 perform cheongla_private.notify_collection(fee_kind,target_notice,true,'새 입금 완료 알림이 등록되었습니다. 통장 내역을 확인해 주세요.','fee_report:'||result::text);
 return result;
end;$$;
create or replace function public.cheongla_review_fee_deposit(target_report uuid,decision text,review_note text,expected_report_updated_at timestamptz,expected_notice_updated_at timestamptz,expected_payment_updated_at timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare r cheongla_private.fee_deposit_reports%rowtype;n record;begin
 if not cheongla_private.can_manage_tuition() then raise exception '앱 관리자·실장만 입금 알림을 확인할 수 있습니다.' using errcode='42501';end if;
 select * into r from cheongla_private.fee_deposit_reports where id=target_report;if not found then raise exception '알림이 없습니다.';end if;
 perform cheongla_private.lock_collection(r.fee_kind,r.notice_id);
 select * into r from cheongla_private.fee_deposit_reports where id=target_report for update;
 if r.state<>'pending' or r.updated_at is distinct from expected_report_updated_at then raise exception '알림 상태가 변경되었습니다. 새로고침해 주세요.';end if;
 if decision is null or decision not in ('confirm','reject') or review_note is null or length(review_note)>1000 then raise exception '확인 결과를 선택해 주세요.';end if;
 select * into n from cheongla_private.collection_notices where fee_kind=r.fee_kind and id=r.notice_id;
 if n.updated_at is distinct from expected_notice_updated_at then raise exception '청구 내용이 변경되었습니다. 새로고침해 주세요.';end if;
 if decision='confirm' then
  if r.notice_updated_at is distinct from n.updated_at or r.amount<>n.amount then raise exception '청구 내용이 바뀐 알림입니다. 반려 후 재등록하거나 통장 확인 후 별도 입금 처리해 주세요.';end if;
  perform public.cheongla_set_fee_payment(r.fee_kind,r.notice_id,true,n.updated_at,expected_payment_updated_at);
 else
  if length(btrim(review_note))<2 then raise exception '입금 미확인·반려 사유를 입력해 주세요.';end if;
  update cheongla_private.fee_deposit_reports set state='rejected',review_reason=btrim(review_note),reviewed_by=(select auth.uid()),updated_at=clock_timestamp() where id=r.id;
  perform cheongla_private.notify_collection(r.fee_kind,r.notice_id,false,'입금 알림 재확인이 필요합니다. 앱에서 학원 안내를 확인해 주세요.','fee_report_review:'||r.id::text||':'||clock_timestamp()::text);
 end if;
end;$$;
create or replace function public.cheongla_fee_collection_history(fee_kind text,target_notice uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin if not cheongla_private.can_read_collection(fee_kind,target_notice) then raise exception '청구 기록을 확인할 권한이 없습니다.' using errcode='42501';end if;
 return jsonb_build_object('reports',coalesce((select jsonb_agg(to_jsonb(r) order by created_at desc) from cheongla_private.fee_deposit_reports r where r.fee_kind=cheongla_fee_collection_history.fee_kind and notice_id=target_notice),'[]'::jsonb),'payments',coalesce((select jsonb_agg(to_jsonb(p) order by created_at desc) from cheongla_private.fee_payment_events p where p.fee_kind=cheongla_fee_collection_history.fee_kind and notice_id=target_notice),'[]'::jsonb));end;$$;
create or replace function public.cheongla_cancel_fee_deposit(target_report uuid,expected_updated_at timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare r cheongla_private.fee_deposit_reports%rowtype;begin
 select * into r from cheongla_private.fee_deposit_reports where id=target_report;if not found then raise exception '알림이 없습니다.';end if;
 perform cheongla_private.lock_collection(r.fee_kind,r.notice_id);
 select * into r from cheongla_private.fee_deposit_reports where id=target_report for update;
 if r.reported_by is distinct from (select auth.uid()) or not cheongla_private.can_read_collection(r.fee_kind,r.notice_id) then raise exception '본인이 등록한 알림만 취소할 수 있습니다.' using errcode='42501';end if;
 if r.state<>'pending' or r.updated_at is distinct from expected_updated_at then raise exception '알림 상태가 변경되었습니다. 새로고침해 주세요.';end if;
 update cheongla_private.fee_deposit_reports set state='closed',review_reason='작성자가 입금 알림 취소',updated_at=clock_timestamp() where id=r.id;
end;$$;
create or replace function public.cheongla_collection_sms_recipients(fee_kind text,target_notice uuid,expected_updated_at timestamptz,reminder boolean default false) returns table(parent_id uuid,parent_name text,phone text) language plpgsql stable security definer set search_path='' as $$
declare n record;begin
 if not (cheongla_private.can_manage_tuition() or (fee_kind='meal' and cheongla_private.can_manage_meal_forms())) then raise exception '담당 관리자만 납부 문자를 준비할 수 있습니다.' using errcode='42501';end if;
 select * into n from cheongla_private.collection_notices where collection_notices.fee_kind=cheongla_collection_sms_recipients.fee_kind and id=target_notice;
 if not found or n.status<>'published' or not n.eligible or not n.source_current or n.amount<=0 then raise exception '게시된 청구와 현재 신청 상태를 확인해 주세요.';end if;
 if n.updated_at is distinct from expected_updated_at then raise exception '청구 내용이 변경되었습니다. 새로고침해 주세요.';end if;
 if not exists(select 1 from public.cheongla_profiles where id=n.student_id and role='student' and approval_status='approved') then raise exception '승인된 학생의 청구만 안내할 수 있습니다.';end if;
 if exists(select 1 from cheongla_private.fee_payments p where p.notice_kind=fee_kind and p.notice_id=target_notice and p.paid_at is not null) then raise exception '입금 기록이 있습니다. 완료·금액 재확인 상태를 먼저 확인해 주세요.';end if;
 if exists(select 1 from cheongla_private.fee_deposit_reports r where r.fee_kind=cheongla_collection_sms_recipients.fee_kind and r.notice_id=target_notice and r.state='pending') then raise exception '입금 확인 대기 중입니다. 통장 내역을 먼저 확인해 주세요.';end if;
 if reminder and n.due_on>=(now() at time zone 'Asia/Seoul')::date then raise exception '납부기한이 지난 청구만 미납 안내를 준비할 수 있습니다.';end if;
 return query select p.id,p.full_name::text,c.phone from public.cheongla_parent_students l join public.cheongla_profiles p on p.id=l.parent_id left join cheongla_private.member_contacts c on c.user_id=p.id where l.student_id=n.student_id and p.role='parent' and p.approval_status='approved' order by p.full_name,p.id;
end;$$;
create or replace function public.cheongla_fee_sms_recipients(fee_kind text,target_notice uuid,expected_updated_at timestamptz) returns table(parent_id uuid,parent_name text,phone text) language sql stable security definer set search_path='' as $$ select * from public.cheongla_collection_sms_recipients(fee_kind,target_notice,expected_updated_at,false);$$;
create or replace function public.cheongla_meal_bill_sms_recipients(target_bill uuid,expected_updated_at timestamptz) returns table(parent_id uuid,parent_name text,phone text) language sql stable security definer set search_path='' as $$ select * from public.cheongla_collection_sms_recipients('meal',target_bill,expected_updated_at,false);$$;
create or replace function public.cheongla_publish_meal_bill(target_bill uuid,notice_action text,expected_updated_at timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare b public.cheongla_meal_bills%rowtype;s public.cheongla_meal_submissions%rowtype;begin
 if not cheongla_private.can_manage_meal_forms() then raise exception '원장·실장만 도시락비 청구를 게시할 수 있습니다.' using errcode='42501';end if;
 select * into b from public.cheongla_meal_bills where id=target_bill;if not found then raise exception '청구가 없습니다.';end if;
 perform 1 from public.cheongla_meal_forms where month=b.month for update;
 select * into s from public.cheongla_meal_submissions where month=b.month and student_id=b.student_id for update;
 select * into b from public.cheongla_meal_bills where id=target_bill for update;
 if b.updated_at is distinct from expected_updated_at then raise exception '청구 내용이 변경되었습니다. 새로고침해 주세요.';end if;
 if notice_action is null or notice_action not in ('publish','withdraw') then raise exception '게시 처리 내용을 확인해 주세요.';end if;
 if notice_action='publish' and (b.source_updated_at is distinct from s.updated_at or not exists(select 1 from public.cheongla_profiles where id=b.student_id and role='student' and approval_status='approved')) then raise exception '현재 학생의 신청을 기준으로 청구를 다시 저장해 주세요.';end if;
 update public.cheongla_meal_bills set status=case when notice_action='publish' then 'published' else 'draft' end,published_at=case when notice_action='publish' then clock_timestamp() else null end,updated_at=clock_timestamp() where id=b.id;
 if notice_action='publish' then perform cheongla_private.notify_collection('meal',b.id,false,'도시락비 청구가 게시되었습니다.','meal_bill:'||b.id::text||':'||clock_timestamp()::text);end if;
end;$$;

create or replace function public.cheongla_save_meal_bill_v2(target_month date,target_student uuid,payment_due date,adjustment_amount integer,bill_note text,expected_submission_updated_at timestamptz,expected_bill_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.cheongla_meal_submissions%rowtype;f public.cheongla_meal_forms%rowtype;b public.cheongla_meal_bills%rowtype;total integer;result uuid;
begin
 if not cheongla_private.can_manage_meal_forms() then raise exception '원장과 실장만 도시락비를 안내할 수 있습니다.' using errcode='42501';end if;
 if payment_due is null or adjustment_amount is null or adjustment_amount not between -10000000 and 10000000 or bill_note is null or length(bill_note)>2000 then raise exception '납부기한, 조정 금액, 안내를 확인해 주세요.';end if;
 if adjustment_amount<>0 and length(btrim(bill_note))=0 then raise exception '차감·추가 금액의 사유를 안내에 적어 주세요.';end if;
 select * into f from public.cheongla_meal_forms where month=target_month for update;
 select * into s from public.cheongla_meal_submissions where month=target_month and student_id=target_student for update;
 if not found then raise exception '신청 내역이 없습니다.';end if;
 if s.updated_at is distinct from expected_submission_updated_at then raise exception '신청이 변경되었습니다. 새로고침 후 청구해 주세요.';end if;
 if not exists(select 1 from public.cheongla_profiles where id=target_student and role='student' and approval_status='approved') then raise exception '승인된 학생의 신청만 청구할 수 있습니다.';end if;
 select * into b from public.cheongla_meal_bills where month=target_month and student_id=target_student for update;
 if b.updated_at is distinct from expected_bill_updated_at then raise exception '다른 담당자가 청구 내용을 변경했습니다. 새로고침해 주세요.';end if;
 total:=(cardinality(s.lunch)+cardinality(s.dinner))*f.unit_price+adjustment_amount;
 if total<0 then raise exception '차감액은 식사 금액을 초과할 수 없습니다. 초과 환불은 별도 정산해 주세요.';end if;
 insert into public.cheongla_meal_bills(month,student_id,student_name,lunch_count,dinner_count,unit_price,adjustment,amount,due_on,note,source_updated_at)
 values(target_month,target_student,s.student_name,cardinality(s.lunch),cardinality(s.dinner),f.unit_price,adjustment_amount,total,payment_due,bill_note,s.updated_at)
 on conflict(month,student_id) do update set status='draft',published_at=null,student_name=excluded.student_name,lunch_count=excluded.lunch_count,dinner_count=excluded.dinner_count,unit_price=excluded.unit_price,adjustment=excluded.adjustment,amount=excluded.amount,due_on=excluded.due_on,note=excluded.note,source_updated_at=excluded.source_updated_at,updated_at=clock_timestamp() returning id into result;
 return result;
end;$$;

create or replace function cheongla_private.can_read_notification(kind text,target uuid,student uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;q record;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved';
 if not found then return false;end if;
 if kind='fee_collection' then return exists(select 1 from cheongla_private.collection_notices n where n.id=target and cheongla_private.can_read_collection(n.fee_kind,n.id));end if;
 case kind
 when 'notice' then return exists(select 1 from public.cheongla_notices n where n.id=target and (n.audience='all' or n.audience=me.role or me.role in ('owner','english_director','math_director','korean_teacher','manager')));
 when 'question' then
  select student_id,subject into q from public.cheongla_questions where id=target;
  return found and cheongla_private.can_read_question(q.student_id,q.subject);
 when 'new_inquiry' then return cheongla_private.can_manage_consultations() and exists(select 1 from public.cheongla_new_inquiries where id=target);
 when 'board' then return cheongla_private.can_read_board_post(target);
 when 'tuition' then return exists(select 1 from public.cheongla_tuition_notices n where n.id=target and (cheongla_private.can_manage_tuition() or (n.status='published' and cheongla_private.is_parent_of(n.student_id))));
 when 'exam' then return exists(select 1 from public.cheongla_exams e where e.id=target and (cheongla_private.can_manage_exams() or (e.status in ('open','closed') and cheongla_private.can_view_exams())));
 when 'application' then return exists(select 1 from public.cheongla_exam_applications a where a.exam_id=target and a.student_id=student and (cheongla_private.can_manage_exams() or cheongla_private.is_parent_of(student) or me.id=student));
 when 'exam_fee' then return exists(select 1 from public.cheongla_exam_fee_notices n where n.id=target and (cheongla_private.can_manage_exams() or (n.status='published' and cheongla_private.can_read_exam_fee(n.exam_id,n.student_id))));
 when 'schedule' then return exists(select 1 from public.cheongla_schedule_events e where e.id=target and (cheongla_private.can_manage_schedule() or (e.status='published' and (e.audience='all' or e.audience=me.role))));
 else return false;
 end case;
end;$$;

create or replace function public.cheongla_fee_payment_states(fee_kind text,notice_ids uuid[]) returns table(notice_id uuid,paid_at timestamptz,paid_amount integer,payment_updated_at timestamptz) language sql stable security definer set search_path='' as $$
 select (x->>'notice_id')::uuid,(x->>'paid_at')::timestamptz,(x->>'paid_amount')::integer,(x->>'payment_updated_at')::timestamptz from jsonb_array_elements(public.cheongla_fee_collection_states(fee_kind,notice_ids)) x;
$$;

revoke all on function public.cheongla_billing_config() from public,anon,authenticated;
grant execute on function public.cheongla_billing_config() to authenticated;
revoke all on function public.cheongla_save_billing_config(text,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_save_billing_config(text,text,text,text,timestamptz) to authenticated;
revoke all on function public.cheongla_fee_collection_states(text,uuid[]) from public,anon,authenticated;
grant execute on function public.cheongla_fee_collection_states(text,uuid[]) to authenticated;
revoke all on function public.cheongla_billing_list(date) from public,anon,authenticated;
grant execute on function public.cheongla_billing_list(date) to authenticated;
revoke all on function public.cheongla_report_fee_deposit(text,uuid,text,date,integer,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_report_fee_deposit(text,uuid,text,date,integer,text,timestamptz) to authenticated;
revoke all on function public.cheongla_review_fee_deposit(uuid,text,text,timestamptz,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_review_fee_deposit(uuid,text,text,timestamptz,timestamptz,timestamptz) to authenticated;
revoke all on function public.cheongla_cancel_fee_deposit(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_cancel_fee_deposit(uuid,timestamptz) to authenticated;
revoke all on function public.cheongla_fee_collection_history(text,uuid) from public,anon,authenticated;
grant execute on function public.cheongla_fee_collection_history(text,uuid) to authenticated;
revoke all on function public.cheongla_collection_sms_recipients(text,uuid,timestamptz,boolean) from public,anon,authenticated;
grant execute on function public.cheongla_collection_sms_recipients(text,uuid,timestamptz,boolean) to authenticated;
revoke all on function public.cheongla_publish_meal_bill(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_publish_meal_bill(uuid,text,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
