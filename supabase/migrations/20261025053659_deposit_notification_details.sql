CREATE OR REPLACE FUNCTION public.cheongla_report_fee_deposit(fee_kind text, target_notice uuid, depositor text, deposit_date date, deposit_amount integer, deposit_note text, expected_notice_updated_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 perform cheongla_private.notify_collection(fee_kind,target_notice,true,n.student_name||' 학생 · '||case fee_kind when 'tuition' then '학원비' when 'exam' then '모의고사비' else '도시락비' end||' 입금 알림'||chr(10)||'입금자: '||btrim(depositor)||' · 입금일: '||deposit_date::text||' · 금액: '||to_char(deposit_amount,'FM999,999,999,990')||'원'||chr(10)||'학원 통장 확인 전입니다.','fee_report:'||result::text);
 return result;
end;$function$
