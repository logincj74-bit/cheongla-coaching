-- 처음부터 끝까지 실행하세요. 기존 회원·시험은 삭제하지 않으며 검증 자료는 모두 자동 취소합니다.
-- 실패하면 서버 설정도 저장되지 않습니다.
rollback;
begin;
create table if not exists cheongla_private.exam_purge_events(
 id bigint generated always as identity primary key,exam_id uuid not null,actor_id uuid not null,
 application_count integer not null,fee_count integer not null,created_at timestamptz not null default clock_timestamp()
);
alter table cheongla_private.exam_purge_events enable row level security;
revoke all on cheongla_private.exam_purge_events from public,anon,authenticated;
create or replace function public.cheongla_purge_deleted_exam(target_exam uuid,expected_updated_at timestamptz,expected_deleted_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare e public.cheongla_exams%rowtype;notice uuid;fees uuid[];applications integer;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 삭제한 시험을 영구 삭제할 수 있습니다.'using errcode='42501';end if;
 select * into e from public.cheongla_exams where id=target_exam for update;
 if not found then raise exception '이미 영구 삭제되었거나 없는 시험입니다.';end if;
 if e.updated_at is distinct from expected_updated_at or e.deleted_at is distinct from expected_deleted_at then raise exception '시험 정보가 변경되었습니다. 시험 새로고침 후 확인해 주세요.';end if;
 if e.deleted_at is null then raise exception '삭제한 시험 목록의 시험만 영구 삭제할 수 있습니다.';end if;
 -- Root and application locks prevent concurrent re-application/new fee notices.
 perform 1 from public.cheongla_exam_applications where exam_id=e.id order by student_id for update;
 select count(*) into applications from public.cheongla_exam_applications where exam_id=e.id;
 select coalesce(array_agg(id order by id),'{}'::uuid[])into fees from public.cheongla_exam_fee_notices where exam_id=e.id;
 foreach notice in array fees loop perform cheongla_private.lock_collection('exam',notice);end loop;
 if exists(select 1 from cheongla_private.fee_payments where notice_kind='exam'and notice_id=any(fees))
 or exists(select 1 from cheongla_private.fee_deposit_reports where fee_kind='exam'and notice_id=any(fees))
 or exists(select 1 from cheongla_private.fee_payment_events where fee_kind='exam'and notice_id=any(fees))
 or exists(select 1 from cheongla_private.bank_confirmations where fee_kind='exam'and notice_id=any(fees))then
  raise exception '수납·입금 알림 이력이 있는 시험은 기록 보존을 위해 영구 삭제할 수 없습니다. 삭제 상태로 보관해 주세요.';
 end if;
 insert into cheongla_private.exam_purge_events(exam_id,actor_id,application_count,fee_count)values(e.id,auth.uid(),applications,cardinality(fees));
 -- Remove stale links; push queue rows cascade from notification deletion.
 delete from public.cheongla_notifications where(source_kind in('exam','application')and source_id=e.id)
 or(source_kind in('exam_fee','fee_collection')and source_id=any(fees));
 -- Existing FK cascades remove the applications, uncollected fee notices and fee settings.
 delete from public.cheongla_exams where id=e.id;
 return e.id;
end;$$;
revoke all on function public.cheongla_purge_deleted_exam(uuid,timestamptz,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_purge_deleted_exam(uuid,timestamptz,timestamptz)to authenticated;
notify pgrst,'reload schema';

do $verify$
declare actor uuid;reader uuid;student uuid;target uuid;fee uuid;v timestamptz;deleted timestamptz;result uuid;
begin
 begin
  update cheongla_private.push_settings set enabled=false where singleton;
  select id into actor from public.cheongla_profiles where approval_status='approved'and membership_state='active'and role in('owner','english_director','math_director')order by case role when 'owner'then 0 else 1 end,id limit 1;
  if actor is null then raise exception '검증할 원장 계정이 없습니다. 변경 사항을 저장하지 않습니다.';end if;
  select id into student from public.cheongla_profiles where role='student'and approval_status='approved'and membership_state='active'order by id limit 1;
  if student is null then raise exception '검증할 승인 학생 계정이 없습니다. 변경 사항을 저장하지 않습니다.';end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
  insert into public.cheongla_exams(title,exam_on,deadline,body,status)values('영구 삭제 검증: 자동 취소','2097-11-10','2097-11-09T10:00:00Z','검증 후 자동 취소','draft')returning id,updated_at into target,v;
  begin
   perform public.cheongla_purge_deleted_exam(target,v,null);raise exception 'FAIL active exam';
  exception when raise_exception then if sqlerrm like'FAIL%'then raise;end if;end;
  update public.cheongla_exams set deleted_at=clock_timestamp(),updated_at=clock_timestamp()where id=target returning updated_at,deleted_at into v,deleted;
  for reader in select id from public.cheongla_profiles where role in('manager','student','parent')and approval_status='approved'and membership_state='active'loop
   perform set_config('request.jwt.claim.sub',reader::text,true);
   perform set_config('request.jwt.claims',jsonb_build_object('sub',reader)::text,true);
   begin perform public.cheongla_purge_deleted_exam(target,v,deleted);raise exception 'FAIL unauthorized purge';exception when insufficient_privilege then null;end;
  end loop;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
  begin perform public.cheongla_purge_deleted_exam(target,v-interval '1 day',deleted);raise exception 'FAIL stale version';exception when raise_exception then if sqlerrm like'FAIL%'then raise;end if;end;
  insert into public.cheongla_exam_applications(exam_id,student_id,student_name,status)values(target,student,'영구 삭제 검증','registered');
  insert into public.cheongla_exam_fee_notices(exam_id,student_id,student_name,exam_title,exam_on,amount,due_on,status)values(target,student,'영구 삭제 검증','영구 삭제 검증','2097-11-10',1000,'2097-11-09','draft')returning id into fee;
  insert into public.cheongla_exam_fee_settings(exam_id,amount,due_on)values(target,1000,'2097-11-09');
  insert into cheongla_private.fee_payments(notice_kind,notice_id,paid_at,paid_amount)values('exam',fee,clock_timestamp(),1000);
  begin perform public.cheongla_purge_deleted_exam(target,v,deleted);raise exception 'FAIL payment protection';exception when raise_exception then if sqlerrm like'FAIL%'then raise;end if;end;
  if not exists(select 1 from public.cheongla_exams where id=target)or not exists(select 1 from public.cheongla_exam_fee_notices where id=fee)then raise exception 'FAIL partial delete';end if;
  delete from cheongla_private.fee_payments where notice_kind='exam'and notice_id=fee;
  insert into cheongla_private.fee_payment_events(fee_kind,notice_id,is_paid,amount,actor_id)values('exam',fee,false,1000,actor);
  begin perform public.cheongla_purge_deleted_exam(target,v,deleted);raise exception 'FAIL cancelled payment history protection';exception when raise_exception then if sqlerrm like'FAIL%'then raise;end if;end;
  delete from cheongla_private.fee_payment_events where fee_kind='exam'and notice_id=fee;
  result:=public.cheongla_purge_deleted_exam(target,v,deleted);
  if result is distinct from target or exists(select 1 from public.cheongla_exams where id=target)or exists(select 1 from public.cheongla_exam_applications where exam_id=target)or exists(select 1 from public.cheongla_exam_fee_notices where id=fee)or exists(select 1 from public.cheongla_exam_fee_settings where exam_id=target)then raise exception 'FAIL permanent delete/cascade';end if;
  if not exists(select 1 from cheongla_private.exam_purge_events where exam_id=target and actor_id=actor and application_count=1 and fee_count=1)then raise exception 'FAIL purge audit';end if;
  if exists(select 1 from public.cheongla_notifications where source_kind in('exam','application','exam_fee','fee_collection')and source_id in(target,fee))then raise exception 'FAIL stale notification';end if;
  if has_function_privilege('anon','public.cheongla_purge_deleted_exam(uuid,timestamptz,timestamptz)','execute')then raise exception 'FAIL anonymous permission';end if;
  raise exception using errcode='PZ001',message='EXAM_PURGE_VERIFICATION_ROLLBACK';
 exception when sqlstate 'PZ001'then if sqlerrm<>'EXAM_PURGE_VERIFICATION_ROLLBACK'then raise;end if;end;
end;$verify$;
commit;
select 'PASS · 시험 영구삭제 서버 설정 및 검증 완료' as "결과";
