-- 011 모의고사 설정 후 추가 실행합니다.
begin;
create table if not exists public.cheongla_exam_fee_settings (
 exam_id uuid primary key references public.cheongla_exams(id) on delete cascade,
 amount integer not null check(amount between 0 and 1000000),
 due_on date not null,
 note text not null default '' check(length(note)<=2000),
 updated_at timestamptz not null default clock_timestamp()
);
create table if not exists public.cheongla_exam_fee_notices (
 id uuid primary key default gen_random_uuid(),
 exam_id uuid not null,
 student_id uuid not null,
 student_name text not null,
 exam_title text not null,
 exam_on date not null,
 amount integer not null check(amount between 0 and 1000000),
 due_on date not null,
 note text not null default '' check(length(note)<=2000),
 status text not null default 'draft' check(status in ('draft','published')),
 published_at timestamptz,
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 unique(exam_id,student_id),
 foreign key(exam_id,student_id) references public.cheongla_exam_applications(exam_id,student_id) on delete cascade
);
alter table public.cheongla_exam_fee_settings enable row level security;
alter table public.cheongla_exam_fee_notices enable row level security;
revoke all on public.cheongla_exam_fee_settings,public.cheongla_exam_fee_notices from anon,authenticated;
grant select on public.cheongla_exam_fee_settings,public.cheongla_exam_fee_notices to authenticated;
create or replace function cheongla_private.can_read_exam_fee(target_exam uuid,target_student uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.is_parent_of(target_student)
 and exists(select 1 from public.cheongla_exam_applications where exam_id=target_exam
 and student_id=target_student and status='registered');
$$;
revoke all on function cheongla_private.can_read_exam_fee(uuid,uuid) from public,anon,authenticated;
grant execute on function cheongla_private.can_read_exam_fee(uuid,uuid) to authenticated;
drop policy if exists cheongla_exam_fee_settings_read on public.cheongla_exam_fee_settings;
create policy cheongla_exam_fee_settings_read on public.cheongla_exam_fee_settings for select to authenticated
 using ((select cheongla_private.can_manage_exams()));
drop policy if exists cheongla_exam_fee_notice_read on public.cheongla_exam_fee_notices;
create policy cheongla_exam_fee_notice_read on public.cheongla_exam_fee_notices for select to authenticated
 using ((select cheongla_private.can_manage_exams()) or (status='published'
 and (select cheongla_private.can_read_exam_fee(exam_id,student_id))));

create or replace function public.cheongla_save_exam_fee_settings(
 target_exam uuid,fee_amount integer,payment_due date,fee_note text,
 expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_stamp timestamptz;
begin
 if not cheongla_private.can_manage_exams() then
  raise exception '실장과 앱 관리자만 응시료 안내를 관리할 수 있습니다.' using errcode='42501';end if;
 perform 1 from public.cheongla_exams where id=target_exam for update;
 if not found then raise exception '해당 모의고사가 없습니다.';end if;
 if fee_amount is null or fee_amount<0 or fee_amount>1000000 or payment_due is null
 or fee_note is null or length(fee_note)>2000 then raise exception '응시료, 납부기한과 안내 내용을 확인해 주세요.';end if;
 select updated_at into old_stamp from public.cheongla_exam_fee_settings where exam_id=target_exam for update;
 if old_stamp is distinct from expected_updated_at then
  raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 저장해 주세요.';end if;
 insert into public.cheongla_exam_fee_settings(exam_id,amount,due_on,note)
 values(target_exam,fee_amount,payment_due,fee_note)
 on conflict(exam_id) do update set amount=excluded.amount,due_on=excluded.due_on,note=excluded.note,
 updated_at=clock_timestamp();return target_exam;
end;
$$;
create or replace function public.cheongla_generate_exam_fee_notices(
 target_exam uuid,expected_settings_updated_at timestamptz)
returns integer language plpgsql security definer set search_path='' as $$
declare e public.cheongla_exams%rowtype;cfg public.cheongla_exam_fee_settings%rowtype;
 affected integer;
begin
 if not cheongla_private.can_manage_exams() then
  raise exception '실장과 앱 관리자만 응시료 안내를 관리할 수 있습니다.' using errcode='42501';end if;
 select * into e from public.cheongla_exams where id=target_exam for update;
 if not found then raise exception '해당 모의고사가 없습니다.';end if;
 if e.status='draft' then raise exception '시험을 먼저 학생에게 게시해 주세요.';end if;
 select * into cfg from public.cheongla_exam_fee_settings where exam_id=target_exam for update;
 if not found then raise exception '응시료와 납부기한을 먼저 저장해 주세요.';end if;
 if cfg.updated_at is distinct from expected_settings_updated_at then
  raise exception '응시료 설정이 변경됐습니다. 새로고침 후 다시 생성해 주세요.';end if;
 insert into public.cheongla_exam_fee_notices(exam_id,student_id,student_name,exam_title,exam_on,amount,due_on,note)
 select e.id,a.student_id,a.student_name,e.title,e.exam_on,cfg.amount,cfg.due_on,cfg.note
 from public.cheongla_exam_applications a join public.cheongla_profiles p on p.id=a.student_id
 where a.exam_id=target_exam and a.status='registered' and p.role='student' and p.approval_status='approved'
 on conflict(exam_id,student_id) do update set student_name=excluded.student_name,exam_title=excluded.exam_title,
 exam_on=excluded.exam_on,amount=excluded.amount,due_on=excluded.due_on,note=excluded.note,updated_at=clock_timestamp()
 where public.cheongla_exam_fee_notices.status='draft';
 get diagnostics affected=row_count;
 return affected;
end;
$$;
create or replace function public.cheongla_set_exam_fee_notice(
 target_notice uuid,notice_action text,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare n public.cheongla_exam_fee_notices%rowtype;target_exam uuid;
begin
 if not cheongla_private.can_manage_exams() then
  raise exception '실장과 앱 관리자만 응시료 안내를 관리할 수 있습니다.' using errcode='42501';end if;
 if notice_action is null or notice_action not in ('publish','withdraw') then
  raise exception '게시 또는 게시 취소를 선택해 주세요.';end if;
 select exam_id into target_exam from public.cheongla_exam_fee_notices where id=target_notice;
 if not found then raise exception '해당 응시료 안내가 없습니다.';end if;
 perform 1 from public.cheongla_exams where id=target_exam for update;
 select * into n from public.cheongla_exam_fee_notices where id=target_notice for update;
 if not found then raise exception '해당 응시료 안내가 없습니다.';end if;
 if n.updated_at is distinct from expected_updated_at then
  raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 처리해 주세요.';end if;
 if notice_action='publish' then
  if n.status<>'draft' then raise exception '이미 게시된 안내입니다.';end if;
  if not exists(select 1 from public.cheongla_exam_applications a join public.cheongla_profiles p on p.id=a.student_id
   where a.exam_id=n.exam_id and a.student_id=n.student_id and a.status='registered'
   and p.role='student' and p.approval_status='approved') then
   raise exception '현재 신청 완료 상태의 승인된 학생만 안내할 수 있습니다.';end if;
  update public.cheongla_exam_fee_notices set status='published',published_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=n.id;
 else
  if n.status<>'published' then raise exception '게시된 안내가 아닙니다.';end if;
  update public.cheongla_exam_fee_notices set status='draft',published_at=null,updated_at=clock_timestamp() where id=n.id;
 end if;
 return n.id;
end;
$$;
revoke all on function public.cheongla_save_exam_fee_settings(uuid,integer,date,text,timestamptz) from public,anon,authenticated;
revoke all on function public.cheongla_generate_exam_fee_notices(uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.cheongla_set_exam_fee_notice(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_save_exam_fee_settings(uuid,integer,date,text,timestamptz) to authenticated;
grant execute on function public.cheongla_generate_exam_fee_notices(uuid,timestamptz) to authenticated;
grant execute on function public.cheongla_set_exam_fee_notice(uuid,text,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
