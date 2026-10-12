-- 001~005 실행 후 실행하세요. 기존 회원, 공지, 자녀 연결을 유지합니다.
begin;
create table if not exists public.cheongla_questions(
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.cheongla_profiles(id),
 student_name text not null default '',
 subject text not null check(subject in ('english','math','korean')),
 title text not null check(char_length(btrim(title)) between 1 and 150),
 body text not null check(char_length(btrim(body)) between 1 and 10000),
 created_at timestamptz not null default now()
);
create index if not exists cheongla_questions_student_idx on public.cheongla_questions(student_id,created_at desc,id desc);
create index if not exists cheongla_questions_subject_idx on public.cheongla_questions(subject,created_at desc,id desc);
create table if not exists public.cheongla_answers(
 question_id uuid primary key references public.cheongla_questions(id) on delete cascade,
 teacher_id uuid not null references public.cheongla_profiles(id),
 teacher_name text not null,
 teacher_role text not null,
 body text not null check(char_length(btrim(body)) between 1 and 10000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.cheongla_questions enable row level security;
alter table public.cheongla_answers enable row level security;
revoke all on public.cheongla_questions,public.cheongla_answers from public,anon,authenticated;
grant select on public.cheongla_questions,public.cheongla_answers to authenticated;
grant insert(student_id,subject,title,body) on public.cheongla_questions to authenticated;

create or replace function cheongla_private.can_read_question(target_student uuid,target_subject text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles p where p.id=(select auth.uid()) and p.approval_status='approved'
 and (p.is_app_admin or p.role in ('english_director','math_director')
 or (p.role='korean_teacher' and target_subject='korean')
 or (p.role='student' and p.id=target_student)));
$$;
create or replace function cheongla_private.can_answer_question(target_subject text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles p where p.id=(select auth.uid()) and p.approval_status='approved'
 and (p.is_app_admin or (p.role='english_director' and target_subject='english')
 or (p.role='math_director' and target_subject='math')
 or (p.role='korean_teacher' and target_subject='korean')));
$$;
revoke all on function cheongla_private.can_read_question(uuid,text),cheongla_private.can_answer_question(text) from public,anon,authenticated;
grant execute on function cheongla_private.can_read_question(uuid,text),cheongla_private.can_answer_question(text) to authenticated;

create or replace function cheongla_private.prepare_question()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.student_id is distinct from (select auth.uid()) then
  raise exception '본인 계정으로 질문을 등록해 주세요.' using errcode='42501';
 end if;
 select p.full_name into new.student_name from public.cheongla_profiles p
 where p.id=new.student_id and p.role='student' and p.approval_status='approved';
 if not found then raise exception '승인된 학생만 질문할 수 있습니다.' using errcode='42501';end if;
 new.created_at=now();return new;
end;
$$;
revoke all on function cheongla_private.prepare_question() from public,anon,authenticated;
drop trigger if exists cheongla_prepare_question on public.cheongla_questions;
create trigger cheongla_prepare_question before insert on public.cheongla_questions
for each row execute function cheongla_private.prepare_question();
drop policy if exists cheongla_question_read on public.cheongla_questions;
create policy cheongla_question_read on public.cheongla_questions for select to authenticated
using(cheongla_private.can_read_question(student_id,subject));
drop policy if exists cheongla_question_create on public.cheongla_questions;
create policy cheongla_question_create on public.cheongla_questions for insert to authenticated
with check(student_id=(select auth.uid()) and exists(select 1 from public.cheongla_profiles p
 where p.id=(select auth.uid()) and p.role='student' and p.approval_status='approved'));
drop policy if exists cheongla_answer_read on public.cheongla_answers;
create policy cheongla_answer_read on public.cheongla_answers for select to authenticated
using(exists(select 1 from public.cheongla_questions q where q.id=question_id
 and cheongla_private.can_read_question(q.student_id,q.subject)));

-- 담당 과목 선생님과 앱 관리자만 답변합니다. 두 원장은 전체 과목을 읽을 수 있습니다.
-- 같은 질문의 동시 답변은 기존 수정 시각을 비교해 덮어쓰기를 막습니다.
create or replace function public.cheongla_save_answer(target_question uuid,answer_body text,expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare
 q public.cheongla_questions%rowtype;
 existing public.cheongla_answers%rowtype;
 teacher public.cheongla_profiles%rowtype;
 has_answer boolean;
begin
 if answer_body is null or char_length(btrim(answer_body)) not between 1 and 10000 then
  raise exception '답변은 1~10000자로 입력해 주세요.' using errcode='22023';end if;
 select * into q from public.cheongla_questions where id=target_question for update;
 if not found then raise exception '질문을 찾을 수 없습니다.' using errcode='P0002';end if;
 if not cheongla_private.can_answer_question(q.subject) then
  raise exception '담당 과목 선생님과 앱 관리자만 답변할 수 있습니다.' using errcode='42501';end if;
 select * into teacher from public.cheongla_profiles where id=(select auth.uid());
 select * into existing from public.cheongla_answers where question_id=q.id;
 has_answer=found;
 if (has_answer and existing.updated_at is distinct from expected_updated_at)
 or (not has_answer and expected_updated_at is not null) then
  raise exception '답변이 변경됐습니다. 질문 목록을 새로고침하고 확인해 주세요.' using errcode='40001';end if;
 insert into public.cheongla_answers(question_id,teacher_id,teacher_name,teacher_role,body)
 values(q.id,teacher.id,teacher.full_name,teacher.role,btrim(answer_body))
 on conflict(question_id) do update set teacher_id=excluded.teacher_id,teacher_name=excluded.teacher_name,
 teacher_role=excluded.teacher_role,body=excluded.body,updated_at=clock_timestamp();
 return q.id;
end;
$$;
revoke all on function public.cheongla_save_answer(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_save_answer(uuid,text,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
