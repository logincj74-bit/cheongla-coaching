CREATE OR REPLACE FUNCTION cheongla_private.can_read_collection(fee_kind text, target_notice uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select cheongla_private.can_use_member_services() and exists(select 1 from cheongla_private.collection_notices n where n.fee_kind=can_read_collection.fee_kind and n.id=target_notice and (cheongla_private.can_manage_tuition() or (n.fee_kind='meal' and cheongla_private.can_manage_meal_forms()) or ((n.status='published' or exists(select 1 from cheongla_private.fee_payments fp where fp.notice_kind=n.fee_kind and fp.notice_id=n.id and fp.paid_at is not null)) and exists(select 1 from public.cheongla_profiles s where s.id=n.student_id and s.role='student' and s.approval_status='approved') and ((n.student_id=(select auth.uid()) and exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role='student')) or cheongla_private.is_parent_of(n.student_id)))));
$function$;

CREATE OR REPLACE FUNCTION public.cheongla_billing_list(target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rows jsonb;begin
 if not cheongla_private.can_use_member_services() or (target_month is not null and extract(day from target_month)<>1) then raise exception '승인 상태와 조회 월을 확인해 주세요.' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('_paymentReady',true,'_payment',(select jsonb_build_object('paid_at',p.paid_at,'paid_amount',p.paid_amount,'payment_updated_at',p.updated_at) from cheongla_private.fee_payments p where p.notice_kind=n.fee_kind and p.notice_id=n.id),'_report',(select to_jsonb(r) from cheongla_private.fee_deposit_reports r where r.fee_kind=n.fee_kind and r.notice_id=n.id order by (state='pending') desc,created_at desc,id desc limit 1)) order by n.student_name,n.fee_kind,n.id),'[]'::jsonb) into rows from cheongla_private.collection_notices n where (target_month is null or n.billing_month=target_month) and cheongla_private.can_read_collection(n.fee_kind,n.id);
 return jsonb_build_object('items',rows,'today',(now() at time zone 'Asia/Seoul')::date,'can_manage',cheongla_private.can_manage_tuition(),'settings',coalesce((select to_jsonb(s) from cheongla_private.billing_settings s where singleton),'{}'::jsonb));
end;$function$;

CREATE OR REPLACE FUNCTION cheongla_private.notify_collection(kind text, target uuid, admin_only boolean, label text, event_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n record;people uuid[];begin
 select * into n from cheongla_private.collection_notices where fee_kind=kind and id=target;if not found then return;end if;
 select array_agg(p.id) into people from public.cheongla_profiles p where p.is_app_admin or p.role in ('owner','english_director','math_director','manager') or (not admin_only and (p.id=n.student_id or (p.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.student_id=n.student_id and l.parent_id=p.id))));
 perform cheongla_private.send_notification(people,'fee_collection',target,n.student_id,n.student_name||' · '||to_char(n.billing_month,'YYYY-MM')||' · '||case kind when 'meal' then '도시락비' when 'exam' then '모의고사비' else '학원비' end||' · '||to_char(n.amount,'FM999,999,999')||'원 · '||label,'billing_dashboard',event_key);
end;$function$;


create or replace function public.cheongla_collection_context(target_notice uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare n record;
begin
 select * into n from cheongla_private.collection_notices c where c.id=target_notice and cheongla_private.can_read_collection(c.fee_kind,c.id);
 if not found then raise exception '청구가 삭제되었거나 현재 계정에서 볼 수 없습니다.' using errcode='42501'; end if;
 return jsonb_build_object('kind',n.fee_kind,'month',to_char(n.billing_month,'YYYY-MM'));
end;$$;

revoke all on function public.cheongla_collection_context(uuid) from public,anon,authenticated;grant execute on function public.cheongla_collection_context(uuid) to authenticated;notify pgrst,'reload schema';
create or replace function public.cheongla_collection_message_recipients(fee_kind text,target_notice uuid,message_mode text,expected_updated_at timestamptz,expected_payment_updated_at timestamptz)
returns table(parent_id uuid,parent_name text,phone text)
language plpgsql stable security definer set search_path='' as $$
declare n record;p cheongla_private.fee_payments%rowtype;
begin
 if not cheongla_private.can_manage_tuition() then raise exception '원장·실장만 납부 문자를 준비할 수 있습니다.' using errcode='42501';end if;
 if message_mode is null or message_mode not in ('charge','receipt') then raise exception '문자 종류를 확인해 주세요.';end if;
 select * into n from cheongla_private.collection_notices c where c.fee_kind=cheongla_collection_message_recipients.fee_kind and c.id=target_notice;
 if not found or n.amount<=0 then raise exception '청구를 확인해 주세요.';end if;
 if n.updated_at is distinct from expected_updated_at then raise exception '청구가 변경되었습니다. 새로고침해 주세요.';end if;
 select * into p from cheongla_private.fee_payments f where f.notice_kind=cheongla_collection_message_recipients.fee_kind and f.notice_id=target_notice;
 if p.updated_at is distinct from expected_payment_updated_at then raise exception '입금 상태가 변경되었습니다. 새로고침해 주세요.';end if;
 if message_mode='receipt' then
  if p.paid_at is null or p.paid_amount is distinct from n.amount then raise exception '학원에서 입금 금액을 확인한 뒤 완료 문자를 보내 주세요.';end if;
 else
  if n.status<>'published' or not n.eligible or not n.source_current or p.paid_at is not null then raise exception '게시된 미납 청구를 확인해 주세요.';end if;
  if exists(select 1 from cheongla_private.fee_deposit_reports r where r.fee_kind=cheongla_collection_message_recipients.fee_kind and r.notice_id=target_notice and r.state='pending') then raise exception '입금 확인 대기 중입니다. 통장을 먼저 확인해 주세요.';end if;
 end if;
 return query select pr.id,pr.full_name::text,c.phone from public.cheongla_parent_students l
 join public.cheongla_profiles pr on pr.id=l.parent_id left join cheongla_private.member_contacts c on c.user_id=pr.id
 where l.student_id=n.student_id and pr.role='parent' and pr.approval_status='approved' and pr.membership_state='active' order by pr.full_name,pr.id;
end;$$;


revoke all on function public.cheongla_collection_message_recipients(text,uuid,text,timestamptz,timestamptz) from public,anon,authenticated;grant execute on function public.cheongla_collection_message_recipients(text,uuid,text,timestamptz,timestamptz) to authenticated;notify pgrst,'reload schema';
alter table public.cheongla_meal_submissions add column if not exists archived_at timestamptz;
alter table public.cheongla_meal_bills add column if not exists archived_at timestamptz;
create or replace function cheongla_private.protect_archived_meal() returns trigger language plpgsql set search_path='' as $$begin if old.archived_at is not null and new.archived_at is not null then raise exception '휴지통에 있는 신청서입니다. 원장이 복구한 뒤 수정해 주세요.';end if;return new;end;$$;
revoke all on function cheongla_private.protect_archived_meal() from public,anon,authenticated;
create trigger protect_archived_meal_submission before update on public.cheongla_meal_submissions for each row execute function cheongla_private.protect_archived_meal();
create trigger protect_archived_meal_bill before update on public.cheongla_meal_bills for each row execute function cheongla_private.protect_archived_meal();
CREATE OR REPLACE FUNCTION public.cheongla_archive_meal_submission(target_month date, target_student uuid, expected_submission_updated_at timestamp with time zone, expected_bill_updated_at timestamp with time zone, expected_payment_updated_at timestamptz, expected_report_updated_at timestamptz)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.cheongla_meal_submissions%rowtype;b public.cheongla_meal_bills%rowtype;result uuid;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 도시락 신청서를 삭제할 수 있습니다.'using errcode='42501';end if;
 perform 1 from public.cheongla_meal_forms where month=target_month for update;
 select * into s from public.cheongla_meal_submissions where month=target_month and student_id=target_student for update;
 if not found or s.archived_at is not null then raise exception '신청서를 찾을 수 없습니다. 명단을 새로고침해 주세요.';end if;
 if s.updated_at is distinct from expected_submission_updated_at then raise exception '신청 내용이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 select * into b from public.cheongla_meal_bills where month=target_month and student_id=target_student;
 if b.id is not null then
  perform cheongla_private.lock_collection('meal',b.id);
  select * into b from public.cheongla_meal_bills where month=target_month and student_id=target_student for update;
 end if;
 if b.updated_at is distinct from expected_bill_updated_at then raise exception '청구 내용이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 if b.id is not null then

  if (select p.updated_at from cheongla_private.fee_payments p where p.notice_kind='meal' and p.notice_id=b.id) is distinct from expected_payment_updated_at
  or (select r.updated_at from cheongla_private.fee_deposit_reports r where r.fee_kind='meal' and r.notice_id=b.id order by (r.state='pending') desc,r.created_at desc,r.id desc limit 1) is distinct from expected_report_updated_at
  then raise exception '입금 상태가 변경되었습니다. 새로고침 후 다시 삭제해 주세요.';end if;
  -- Keep payment/report/event records attached to the archived bill UUID.

 end if;
 insert into cheongla_private.meal_submission_trash(month,student_id,student_name,submission_snapshot,bill_snapshot,deleted_by)
 values(s.month,s.student_id,s.student_name,to_jsonb(s)||jsonb_build_object('_soft_archive',true),case when b.id is not null then to_jsonb(b)end,auth.uid())returning id into result;
 update public.cheongla_meal_bills set archived_at=clock_timestamp() where month=target_month and student_id=target_student;
 update public.cheongla_meal_submissions set archived_at=clock_timestamp() where month=target_month and student_id=target_student;
 return result;
end;$function$;


revoke all on function public.cheongla_archive_meal_submission(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz) from public,anon,authenticated;grant execute on function public.cheongla_archive_meal_submission(date,uuid,timestamptz,timestamptz,timestamptz,timestamptz) to authenticated;notify pgrst,'reload schema';
create or replace view cheongla_private.collection_notices as SELECT 'tuition'::text AS fee_kind,
    t.id,
    t.student_id,
    t.student_name,
    t.billing_month,
    (t.billing_month::text || ' '::text) ||
        CASE t.program
            WHEN 'repeat'::text THEN '재수생 학원비'::text
            WHEN 'school'::text THEN '재학생 학원비'::text
            WHEN 'winter'::text THEN '윈터스쿨 학원비'::text
            WHEN 'summer'::text THEN '썸머스쿨 학원비'::text
            WHEN 'civil'::text THEN '공시생 학원비'::text
            ELSE '학원비'::text
        END AS label,
    t.amount,
    t.due_on,
    t.note,
    t.status,
    t.updated_at,
    true AS eligible,
    true AS source_current,
    to_jsonb(t.*) AS details
   FROM cheongla_tuition_notices t
  WHERE t.archived_at IS NULL
UNION ALL
 SELECT 'exam'::text AS fee_kind,
    e.id,
    e.student_id,
    e.student_name,
    date_trunc('month'::text, e.exam_on::timestamp with time zone)::date AS billing_month,
    e.exam_title || ' 모의고사비'::text AS label,
    e.amount,
    e.due_on,
    e.note,
    e.status,
    e.updated_at,
    (EXISTS ( SELECT 1
           FROM cheongla_exam_applications a
             JOIN cheongla_exams x ON x.id = a.exam_id
          WHERE a.exam_id = e.exam_id AND a.student_id = e.student_id AND a.status = 'registered'::text AND (to_jsonb(x.*) ->> 'deleted_at'::text) IS NULL)) AS eligible,
    true AS source_current,
    to_jsonb(e.*) AS details
   FROM cheongla_exam_fee_notices e
UNION ALL
 SELECT 'meal'::text AS fee_kind,
    b.id,
    b.student_id,
    b.student_name,
    b.month AS billing_month,
    b.month::text || ' 도시락비'::text AS label,
    b.amount,
    b.due_on,
    b.note,
    b.status,
    b.updated_at,
    true AS eligible,
    (EXISTS ( SELECT 1
           FROM cheongla_meal_submissions s
          WHERE s.month = b.month AND s.student_id = b.student_id AND s.updated_at = b.source_updated_at)) AS source_current,
    to_jsonb(b.*) AS details
   FROM cheongla_meal_bills b WHERE b.archived_at is null;
CREATE OR REPLACE FUNCTION public.cheongla_read_meal_form(target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare manager boolean:=cheongla_private.can_manage_meal_forms();result jsonb;
begin
 if not manager and not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role in ('student','parent') and approval_status='approved' and membership_state='active') then raise exception '승인된 학생과 관리자만 이용할 수 있습니다.' using errcode='42501';end if;
 select jsonb_build_object('form',(select to_jsonb(f) from public.cheongla_meal_forms f where month=target_month),'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.student_name,s.student_id) from public.cheongla_meal_submissions s where month=target_month and s.archived_at is null and (manager or cheongla_private.can_apply_for(s.student_id))),'[]'::jsonb),'bills',case when manager then coalesce((select jsonb_agg(to_jsonb(b)) from public.cheongla_meal_bills b where b.month=target_month and b.archived_at is null),'[]'::jsonb) else '[]'::jsonb end,'today',(now() at time zone 'Asia/Seoul')::date) into result;
 return result;
end;$function$;

CREATE OR REPLACE FUNCTION public.cheongla_deleted_meal_submissions(target_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not cheongla_private.is_principal()then raise exception '원장만 삭제한 신청서를 확인할 수 있습니다.'using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'month',t.month,'student_id',t.student_id,'student_name',t.student_name,
 'lunch_count',jsonb_array_length(t.submission_snapshot->'lunch'),'dinner_count',jsonb_array_length(t.submission_snapshot->'dinner'),'deleted_at',t.deleted_at,'soft_archive',coalesce((t.submission_snapshot->>'_soft_archive')::boolean,false))order by t.deleted_at desc)
 from cheongla_private.meal_submission_trash t where t.month=target_month and t.restored_at is null),'[]'::jsonb);
end;$function$;

CREATE OR REPLACE FUNCTION public.cheongla_restore_meal_submission(target_trash uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t cheongla_private.meal_submission_trash%rowtype;s public.cheongla_meal_submissions%rowtype;b public.cheongla_meal_bills%rowtype;f public.cheongla_meal_forms%rowtype;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 삭제한 신청서를 복구할 수 있습니다.'using errcode='42501';end if;
 select * into t from cheongla_private.meal_submission_trash where id=target_trash;
 if not found then raise exception '삭제한 신청서를 찾을 수 없습니다.';end if;
 select * into f from public.cheongla_meal_forms where month=t.month for update;
 if not found then raise exception '해당 월 신청서 설정을 확인해 주세요.';end if;
 select * into t from cheongla_private.meal_submission_trash where id=target_trash for update;
 if t.restored_at is not null then raise exception '이미 복구한 신청서입니다.';end if;

 if t.submission_snapshot->>'_soft_archive'='true' then
  if not exists(select 1 from public.cheongla_profiles where id=t.student_id and role='student' and approval_status='approved' and membership_state='active') then raise exception '승인된 재원생의 신청서만 복구할 수 있습니다.';end if;
  if not exists(select 1 from public.cheongla_meal_submissions x where x.month=t.month and x.student_id=t.student_id and x.archived_at is not null) then raise exception '현재 신청서 상태를 확인해 주세요.';end if;
  update public.cheongla_meal_submissions set archived_at=null where month=t.month and student_id=t.student_id;
  update public.cheongla_meal_bills set archived_at=null where month=t.month and student_id=t.student_id;
  update cheongla_private.meal_submission_trash set restored_at=clock_timestamp(),restored_by=auth.uid() where id=t.id;
  return;
 end if;
 if exists(select 1 from public.cheongla_meal_submissions where month=t.month and student_id=t.student_id)then raise exception '학생이 새 신청서를 제출했습니다. 현재 신청서를 확인해 주세요.';end if;
 if not exists(select 1 from public.cheongla_profiles where id=t.student_id and role='student'and approval_status='approved'and membership_state='active')then raise exception '승인된 재원생의 신청서만 복구할 수 있습니다.';end if;
 s:=jsonb_populate_record(null::public.cheongla_meal_submissions,t.submission_snapshot);
 s.updated_at:=clock_timestamp();
 insert into public.cheongla_meal_submissions select (s).*;
 if t.bill_snapshot is not null then
  b:=jsonb_populate_record(null::public.cheongla_meal_bills,t.bill_snapshot);
  if b.unit_price<>f.unit_price then raise exception '식사 단가가 변경되어 복구할 수 없습니다. 신청 내역과 청구 금액을 먼저 확인해 주세요.';end if;
  b.updated_at:=clock_timestamp();b.source_updated_at:=s.updated_at;if not exists(select 1 from cheongla_private.fee_payments p where p.notice_kind='meal' and p.notice_id=b.id and p.paid_at is not null) then b.status:='draft';b.published_at:=null;end if;
  insert into public.cheongla_meal_bills select (b).*;
 end if;
 update cheongla_private.meal_submission_trash set restored_at=clock_timestamp(),restored_by=auth.uid()where id=t.id;
end;$function$;

CREATE OR REPLACE FUNCTION cheongla_private.notify_meal_submission()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
declare people uuid[];
begin
 if tg_op='UPDATE' then if old.archived_at is distinct from new.archived_at then return new;end if;end if;
 select array_agg(id) into people from public.cheongla_profiles where approval_status='approved' and membership_state='active' and (is_app_admin or role in ('owner','english_director','math_director','manager'));
 perform cheongla_private.send_notification(people,'meal_submission',new.student_id,new.student_id,new.student_name||' · 도시락 '||case when tg_op='INSERT' then '신청완료' else '신청 변경' end,'meal_forms','meal:'||new.month::text||':'||new.student_id::text||':'||new.updated_at::text);
 return new;
end;$$;
