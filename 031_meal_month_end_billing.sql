begin;
create table public.cheongla_meal_bills (
 id uuid primary key default gen_random_uuid(),
 month date not null,
 student_id uuid not null,
 student_name text not null,
 lunch_count integer not null,
 dinner_count integer not null,
 unit_price integer not null,
 adjustment integer not null default 0,
 amount integer not null check(amount>=0),
 due_on date not null,
 note text not null default '',
 source_updated_at timestamptz not null,
 updated_at timestamptz not null default clock_timestamp(),
 unique(month,student_id),
 foreign key(month,student_id) references public.cheongla_meal_submissions(month,student_id)
);
alter table public.cheongla_meal_bills enable row level security;
revoke all on public.cheongla_meal_bills from public,anon,authenticated;
grant select on public.cheongla_meal_bills to authenticated;
create policy meal_bills_manager on public.cheongla_meal_bills for select to authenticated using(cheongla_private.can_manage_meal_forms());
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
 on conflict(month,student_id) do update set student_name=excluded.student_name,lunch_count=excluded.lunch_count,dinner_count=excluded.dinner_count,unit_price=excluded.unit_price,adjustment=excluded.adjustment,amount=excluded.amount,due_on=excluded.due_on,note=excluded.note,source_updated_at=excluded.source_updated_at,updated_at=clock_timestamp() returning id into result;
 return result;
end;$$;
create or replace function public.cheongla_meal_bill_sms_recipients(target_bill uuid,expected_updated_at timestamptz)
returns table(parent_id uuid,parent_name text,phone text)
language plpgsql stable security definer set search_path='' as $$
declare b public.cheongla_meal_bills%rowtype;
begin
 if not cheongla_private.can_manage_meal_forms() then raise exception '원장과 실장만 도시락비 문자를 준비할 수 있습니다.' using errcode='42501';end if;
 select * into b from public.cheongla_meal_bills where id=target_bill;
 if not found or b.updated_at is distinct from expected_updated_at then raise exception '청구 내용이 변경되었습니다. 새로고침해 주세요.';end if;
 if b.amount<=0 then raise exception '청구할 금액이 없습니다.';end if;
 if not exists(select 1 from public.cheongla_meal_submissions s join public.cheongla_profiles p on p.id=s.student_id where s.month=b.month and s.student_id=b.student_id and s.updated_at=b.source_updated_at and p.role='student' and p.approval_status='approved') then raise exception '신청이 변경되었거나 학생 승인이 변경되었습니다. 명단에서 청구 내용을 다시 확인해 주세요.';end if;
 return query select p.id,p.full_name::text,c.phone from public.cheongla_parent_students l
 join public.cheongla_profiles p on p.id=l.parent_id
 left join cheongla_private.member_contacts c on c.user_id=p.id
 where l.student_id=b.student_id and p.role='parent' and p.approval_status='approved' order by p.full_name,p.id;
end;$$;
revoke all on function public.cheongla_save_meal_bill_v2(date,uuid,date,integer,text,timestamptz,timestamptz),public.cheongla_meal_bill_sms_recipients(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_save_meal_bill_v2(date,uuid,date,integer,text,timestamptz,timestamptz),public.cheongla_meal_bill_sms_recipients(uuid,timestamptz) to authenticated;
create or replace function public.cheongla_read_meal_form(target_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean:=cheongla_private.can_manage_meal_forms();result jsonb;
begin
 if not manager and not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role='student' and approval_status='approved') then raise exception '승인된 학생과 관리자만 이용할 수 있습니다.' using errcode='42501';end if;
 select jsonb_build_object('form',(select to_jsonb(f) from public.cheongla_meal_forms f where month=target_month),'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.student_name,s.student_id) from public.cheongla_meal_submissions s where month=target_month and (manager or s.student_id=(select auth.uid()))),'[]'::jsonb),'bills',case when manager then coalesce((select jsonb_agg(to_jsonb(b)) from public.cheongla_meal_bills b where b.month=target_month),'[]'::jsonb) else '[]'::jsonb end,'today',(now() at time zone 'Asia/Seoul')::date) into result;
 return result;
end;$$;
notify pgrst,'reload schema';
commit;
