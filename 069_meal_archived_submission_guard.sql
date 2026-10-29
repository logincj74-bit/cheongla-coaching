-- Deleted applications retain billing/payment history and require principal restoration.
-- Report their actual state instead of an unrecoverable optimistic-lock error.
CREATE OR REPLACE FUNCTION public.cheongla_submit_student_meal(target_student uuid, target_month date, lunch_dates date[], dinner_dates date[], student_note text, expected_updated_at timestamp with time zone, expected_form_updated_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.cheongla_meal_forms%rowtype;s public.cheongla_meal_submissions%rowtype;n text;today date:=(clock_timestamp() at time zone 'Asia/Seoul')::date;l date[];d date[];
begin
 select full_name into n from public.cheongla_profiles where id=target_student and cheongla_private.can_apply_for(target_student);
 if not found then raise exception '승인된 학생 계정으로 신청해 주세요.' using errcode='42501';end if;
 select * into f from public.cheongla_meal_forms where month=target_month for update;
 if not found then raise exception '아직 등록되지 않은 월의 신청서입니다.';end if;
 if f.updated_at is distinct from expected_form_updated_at then raise exception '신청 안내가 변경되었습니다. 새로고침 후 확인해 주세요.';end if;
 if lunch_dates is null or dinner_dates is null or cardinality(lunch_dates)>31 or cardinality(dinner_dates)>31 or student_note is null or length(student_note)>1000 then raise exception '신청 내용과 비고를 확인해 주세요.';end if;
 if exists(select 1 from unnest(lunch_dates||dinner_dates) x where x is null or x<target_month or x>=(target_month+interval '1 month')::date or extract(isodow from x)=7) then raise exception '해당 월의 월요일부터 토요일까지 선택해 주세요.';end if;
 select coalesce(array_agg(distinct x order by x),'{}') into l from unnest(lunch_dates) x;
 select coalesce(array_agg(distinct x order by x),'{}') into d from unnest(dinner_dates) x;
 select * into s from public.cheongla_meal_submissions where month=target_month and student_id=target_student for update;
 if s.archived_at is not null then raise exception '원장이 삭제한 신청서가 휴지통에 있습니다. 원장님이 도시락 신청 현황의 휴지통에서 복구한 뒤 다시 신청해 주세요.' using errcode='P0001';end if;
 if s.updated_at is distinct from expected_updated_at then raise exception '다른 화면에서 신청 내용이 변경되었습니다. 새로고침 후 확인해 주세요.';end if;

 if s.student_id is not null and (not s.lunch<@l or not s.dinner<@d) then raise exception '도시락 취소는 전날까지 학원 휴대폰으로 전화 또는 문자 문의해 주세요. 앱에서는 직접 취소할 수 없습니다.';end if;
 if today>f.deadline and (s.student_id is null or not l<@s.lunch or not d<@s.dinner) then raise exception '제출 기한이 지났습니다. 추가 신청은 관리자에게 문의해 주세요.';end if;
 if exists(select 1 from ((select unnest(l) except select unnest(coalesce(s.lunch,'{}'))) union all (select unnest(coalesce(s.lunch,'{}')) except select unnest(l)) union all (select unnest(d) except select unnest(coalesce(s.dinner,'{}'))) union all (select unnest(coalesce(s.dinner,'{}')) except select unnest(d))) changes(x) where x<=today) then raise exception '식사 당일과 지난 날짜는 신청·취소할 수 없습니다.';end if;
 insert into public.cheongla_meal_submissions(month,student_id,student_name,lunch,dinner,note) values(target_month,target_student,n,l,d,student_note)
 on conflict(month,student_id) do update set student_name=excluded.student_name,lunch=excluded.lunch,dinner=excluded.dinner,note=excluded.note,updated_at=clock_timestamp();
end;$function$
;
CREATE OR REPLACE FUNCTION public.cheongla_submit_meal_form(target_month date, lunch_dates date[], dinner_dates date[], student_note text, expected_updated_at timestamp with time zone, expected_form_updated_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.cheongla_meal_forms%rowtype;s public.cheongla_meal_submissions%rowtype;n text;today date:=(clock_timestamp() at time zone 'Asia/Seoul')::date;l date[];d date[];
begin
 select full_name into n from public.cheongla_profiles where id=(select auth.uid()) and role='student' and approval_status='approved' and membership_state='active';
 if not found then raise exception '승인된 학생 계정으로 신청해 주세요.' using errcode='42501';end if;
 select * into f from public.cheongla_meal_forms where month=target_month for update;
 if not found then raise exception '아직 등록되지 않은 월의 신청서입니다.';end if;
 if f.updated_at is distinct from expected_form_updated_at then raise exception '신청 안내가 변경되었습니다. 새로고침 후 확인해 주세요.';end if;
 if lunch_dates is null or dinner_dates is null or cardinality(lunch_dates)>31 or cardinality(dinner_dates)>31 or student_note is null or length(student_note)>1000 then raise exception '신청 내용과 비고를 확인해 주세요.';end if;
 if exists(select 1 from unnest(lunch_dates||dinner_dates) x where x is null or x<target_month or x>=(target_month+interval '1 month')::date or extract(isodow from x)=7) then raise exception '해당 월의 월요일부터 토요일까지 선택해 주세요.';end if;
 select coalesce(array_agg(distinct x order by x),'{}') into l from unnest(lunch_dates) x;
 select coalesce(array_agg(distinct x order by x),'{}') into d from unnest(dinner_dates) x;
 select * into s from public.cheongla_meal_submissions where month=target_month and student_id=(select auth.uid()) for update;
 if s.archived_at is not null then raise exception '원장이 삭제한 신청서가 휴지통에 있습니다. 원장님이 도시락 신청 현황의 휴지통에서 복구한 뒤 다시 신청해 주세요.' using errcode='P0001';end if;
 if s.updated_at is distinct from expected_updated_at then raise exception '다른 화면에서 신청 내용이 변경되었습니다. 새로고침 후 확인해 주세요.';end if;

 if s.student_id is not null and (not s.lunch<@l or not s.dinner<@d) then raise exception '도시락 취소는 전날까지 학원 휴대폰으로 전화 또는 문자 문의해 주세요. 앱에서는 직접 취소할 수 없습니다.';end if;
 if today>f.deadline and (s.student_id is null or not l<@s.lunch or not d<@s.dinner) then raise exception '제출 기한이 지났습니다. 추가 신청은 관리자에게 문의해 주세요.';end if;
 if exists(select 1 from ((select unnest(l) except select unnest(coalesce(s.lunch,'{}'))) union all (select unnest(coalesce(s.lunch,'{}')) except select unnest(l)) union all (select unnest(d) except select unnest(coalesce(s.dinner,'{}'))) union all (select unnest(coalesce(s.dinner,'{}')) except select unnest(d))) changes(x) where x<=today) then raise exception '식사 당일과 지난 날짜는 신청·취소할 수 없습니다.';end if;
 insert into public.cheongla_meal_submissions(month,student_id,student_name,lunch,dinner,note) values(target_month,(select auth.uid()),n,l,d,student_note)
 on conflict(month,student_id) do update set student_name=excluded.student_name,lunch=excluded.lunch,dinner=excluded.dinner,note=excluded.note,updated_at=clock_timestamp();
end;$function$
;
notify pgrst,'reload schema';
