create function cheongla_private.can_manage_office_sms()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and approval_status='approved' and membership_state='active'
 and role in('owner','english_director','math_director','manager'));
$$;
revoke all on function cheongla_private.can_manage_office_sms() from public,anon;
grant execute on function cheongla_private.can_manage_office_sms() to authenticated;
create table public.cheongla_office_sms_templates(
 id uuid primary key default gen_random_uuid(),
 title text not null check(length(btrim(title)) between 1 and 150),
 category text not null check(length(btrim(category)) between 1 and 60),
 audience text not null default 'both' check(audience in('parent','student','both')),
 body text not null check(length(btrim(body)) between 1 and 10000),
 deleted_at timestamptz,revision integer not null default 1,
 updated_at timestamptz not null default clock_timestamp(),updated_by uuid
);
alter table public.cheongla_office_sms_templates enable row level security;
revoke all on public.cheongla_office_sms_templates from public,anon,authenticated;
grant select,delete on public.cheongla_office_sms_templates to authenticated;
grant insert(title,category,audience,body),update(title,category,audience,body,deleted_at)
 on public.cheongla_office_sms_templates to authenticated;
create policy office_sms_staff on public.cheongla_office_sms_templates for all to authenticated
 using((select cheongla_private.can_manage_office_sms()))
 with check((select cheongla_private.can_manage_office_sms()));
create policy office_sms_trash_first on public.cheongla_office_sms_templates as restrictive for delete to authenticated
 using(deleted_at is not null);
create function cheongla_private.office_sms_revision()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' then new.revision:=old.revision+1;end if;
 new.updated_at:=clock_timestamp();new.updated_by:=auth.uid();return new;
end;$$;
revoke all on function cheongla_private.office_sms_revision() from public,anon,authenticated;
create trigger office_sms_revision before insert or update on public.cheongla_office_sms_templates
 for each row execute function cheongla_private.office_sms_revision();
-- Narrow contact lookup: only active students and their approved, linked parents.
create function public.cheongla_office_sms_students()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_office_sms() then raise insufficient_privilege;end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.student_name,q.student_id) from (
 select s.id student_id,s.full_name student_name,t.enrolled_on,t.monthly_fee,
 coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.full_name,'role',r.role,'phone',c.phone) order by r.role,r.full_name)
 from public.cheongla_profiles r left join cheongla_private.member_contacts c on c.user_id=r.id
 where r.approval_status='approved' and r.membership_state='active' and
 (r.id=s.id or (r.role='parent' and exists(select 1 from public.cheongla_parent_students l where l.student_id=s.id and l.parent_id=r.id)))),'[]'::jsonb) recipients
 from public.cheongla_profiles s left join public.cheongla_tuition_settings t on t.student_id=s.id
 where s.role='student' and s.approval_status='approved' and s.membership_state='active'
 )q),'[]'::jsonb);
end;$$;
revoke all on function public.cheongla_office_sms_students() from public,anon;
grant execute on function public.cheongla_office_sms_students() to authenticated;

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('첫 문의 감사 · 학원 소개','상담','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
문의주셔서 감사합니다🤗

우리 자녀분이 공부에 전념할 수 있도록 성실하고 꼼꼼하게 관리하겠습니다.

⭐ 청라에서 함께하는 학습 관리
✔ 영어·수학 원장님과 국어 전문 선생님의 학습 상담 및 과목별 1:1 질의응답
✔ 수능·내신 학습자료 제공📚
✔ 남녀 분리 열람실과 학습에 집중할 수 있는 쾌적한 환경

편하신 시간에 방문 상담을 예약해 주시면 자세히 안내드리겠습니다.

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('방문상담 예약 확정','상담','both','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
문의주셔서 감사합니다.

{{상담일시}}로 {{학생이름}} 학생의 방문 상담을 예약했습니다.
주차 안내: {{주차안내}}
상담 때 뵙겠습니다😊

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('방문상담 후 · 윈터','상담','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
소중한 시간 내어 방문해 주셔서 감사합니다🤗

{{학생이름}} 학생이 자기주도학습을 체화하고 공부에 전념할 수 있도록 성실하고 꼼꼼하게 관리하겠습니다!

[청라 {{시즌연도}} 윈터스쿨 모집]
● 운영기간: {{운영시작일}} ~ {{운영종료일}}
* 학교별 방학일에 맞춰 시작일을 지정할 수 있습니다.
● 모집대상: {{모집대상}}
● 운영시간: {{운영시간}}
(의무 학습: {{의무학습종료}}까지)
* 일요일 자율등원
* 교육비는 계좌이체 및 카드 결제가 가능합니다.

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('방문상담 후 · 썸머','상담','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
소중한 시간 내어 방문해 주셔서 감사합니다🤗

{{학생이름}} 학생이 자기주도학습을 체화하고 공부에 전념할 수 있도록 성실하고 꼼꼼하게 관리하겠습니다!

[청라 {{시즌연도}} 썸머스쿨 모집]
● 운영기간: {{운영시작일}} ~ {{운영종료일}}
* 학교별 방학일에 맞춰 시작일을 지정할 수 있습니다.
● 모집대상: {{모집대상}}
● 운영시간: {{운영시간}}
(의무 학습: {{의무학습종료}}까지)
* 일요일 자율등원
* 교육비는 계좌이체 및 카드 결제가 가능합니다.

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('방문상담 후 · 재수 우선선발','상담','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
방문해 주셔서 감사합니다🤗

{{학생이름}} 학생이 자기주도학습을 체화하고 공부에 전념할 수 있도록 성실하고 꼼꼼하게 관리하겠습니다!

[{{수능학년도}}학년도 수능 재수 우선선발 모집]

✔ 모집대상: {{수능학년도}}학년도 수능 재수/N수생
✔ 개강일: {{개강일}}
* 개강 전 등원은 상담 후 조정할 수 있습니다.
✔ 주기적인 학습 상담과 국어·영어·수학 질의응답
✔ 좌석 선택은 등록 상황에 따라 안내드립니다.
✔ 철저한 생활 관리와 쾌적한 시설, 풍부한 학습자료📚

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('등록 후 · 재수 감사 안내','등록','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
{{학생이름}} 학생의 앞날을 청라가 함께하게 되어 뜻깊습니다🤗

첫 등원일은 {{첫등원일}}입니다. 등원 전 교육비 안내와 준비사항을 다시 보내드리겠습니다.
등원 전 미리 오셔서 짐을 정리하실 수 있습니다.
학생의 모든 걸음이 꿈을 향해갈 수 있도록 언제나 귀 기울이겠습니다🍀

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('재수 우선선발 모집','모집','both','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
문의주셔서 감사합니다.

[{{수능학년도}}학년도 수능 재수 우선선발 모집]

✔ 모집대상: {{수능학년도}}학년도 수능 재수/N수생
✔ 개강일: {{개강일}}
* 개강 전 등원은 상담 후 조정할 수 있습니다.
✔ 주기적인 학습 상담과 국어·영어·수학 질의응답
✔ 좌석 선택은 등록 상황에 따라 안내드립니다.
✔ 철저한 생활 관리와 쾌적한 시설, 풍부한 학습자료📚

꿈이 이루어지는 모든 걸음을 청라가 함께하겠습니다🤗🍀
접수방법: 전화 또는 방문 상담

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('재수 정규 모집','모집','both','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
다시 도전하는 소중한 시간과 간절함이 결실을 맺을 수 있도록 성실하고 꼼꼼하게 관리하겠습니다.

[{{수능학년도}}학년도 수능 재수생 모집]
● 모집대상: 재수/N수생
● 모집기한: {{모집기한}}
● 신청방법: 전화 또는 방문 상담
* 등록 상황에 따라 조기 마감될 수 있습니다.

⭐ 청라에서 함께하는 학습 관리
✔ 영어·수학 원장님과 국어 전문 선생님의 학습 상담 및 과목별 1:1 질의응답
✔ 수능·내신 학습자료 제공📚
✔ 남녀 분리 열람실과 학습에 집중할 수 있는 쾌적한 환경

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('재학생 모집 안내','모집','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
문의주셔서 감사합니다🤗

{{학생이름}} 학생이 자기주도학습을 체화하고 공부에 전념할 수 있도록 성실하고 꼼꼼하게 관리하겠습니다!

[청라 {{시즌연도}} 재학생 모집]
● 모집기간: {{모집기한}}
● 모집대상: {{모집대상}}
● 운영시간: 하교 후 ~ {{의무학습종료}}
* 토요일·공휴일 08:00 등원, 일요일 자율등원
* 자율 학습 운영시간: {{운영시간}}

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('등원 전 교육비 · 윈터','교육비','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
📌 {{학생이름}} 학생 윈터스쿨 교육비 안내입니다.

월 교육비: {{교육비}}원
(30일 기준, 식비 별도)
청구기간: {{청구시작일}} ~ {{청구종료일}}
이번 납부금액: {{청구금액}}원
납부기한: {{납부기한}}

<학원 계좌>
{{은행명}} {{계좌번호}} {{예금주}}
입금자명은 학생 이름으로 부탁드립니다. 송금 후 입금자명을 문자로 알려주세요.
💳 카드 결제도 가능합니다. 결제 방법은 학원으로 문의해 주세요.

이미 납부하셨다면 양해 부탁드립니다. 청라를 믿고 맡겨주셔서 감사합니다😊

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('재수 교육비 안내','교육비','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
📌 {{학생이름}} 학생 재수 교육비 안내입니다.

월 교육비: {{교육비}}원
(30일 기준, 식비 별도)
청구기간: {{청구시작일}} ~ {{청구종료일}}
이번 납부금액: {{청구금액}}원
납부기한: {{납부기한}}

<학원 계좌>
{{은행명}} {{계좌번호}} {{예금주}}
입금자명은 학생 이름으로 부탁드립니다. 송금 후 입금자명을 문자로 알려주세요.
💳 카드 결제도 가능합니다. 결제 방법은 학원으로 문의해 주세요.

이미 납부하셨다면 양해 부탁드립니다. 청라를 믿고 맡겨주셔서 감사합니다😊

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('등원 전 교육비 · 재수 우선선발 할인','교육비','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
📌 {{학생이름}} 학생 교육비 안내입니다.

월 교육비: {{교육비}}원 (30일 기준, 식비 별도)
우선선발 할인율: {{할인율}}%
할인 운영기간: {{할인시작일}} ~ {{할인종료일}}
청구기간: {{청구시작일}} ~ {{청구종료일}}
이번 납부금액: {{청구금액}}원
납부기한: {{납부기한}}

<학원 계좌>
{{은행명}} {{계좌번호}} {{예금주}}
입금자명은 학생 이름으로 부탁드립니다. 송금 후 입금자명을 문자로 알려주세요.
💳 카드 결제도 가능합니다. 결제 방법은 학원으로 문의해 주세요.

이미 납부하셨다면 양해 부탁드립니다. 감사합니다😊

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('첫 등원 안내 · 학생·학부모','등원','both','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
{{첫등원일}}은 {{학생이름}} 학생의 청라 첫 등원일입니다🤗
등원 전 아래 사항을 확인해 주세요.

✔ 준비물: 실내용 슬리퍼, 텀블러, 공부할 책·필기도구와 개인용품
✖ 흡연, 학습 집중을 방해하는 물품·행위는 금지합니다.
✔ 식사 신청·취소는 식사 전날까지 학원에 말씀해 주세요. 당일 취소는 어렵습니다.
✔ 평일·토요일 08:00 등원, 의무 학습은 {{의무학습종료}}까지입니다.
✔ 출결카드를 찍으면 등록된 번호로 등원 문자가 발송될 예정입니다.
✔ 외부 수업 등 일정은 보호자 확인 후 가능합니다. 첫날 드리는 일정표를 작성해 보호자 확인 후 제출해 주세요.

공부를 다짐한 처음 마음을 잃지 않길 바랍니다. 지치거나 고민될 때는 언제든 편하게 말씀해 주세요. 꿈이 이루어지는 날까지 청라가 함께하겠습니다😊🍀

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('윈터스쿨 마감 임박','모집','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
윈터스쿨 등록이 마감에 가까워져 안내드립니다.

[청라 {{시즌연도}} 윈터스쿨 모집]
● 운영기간: {{운영시작일}} ~ {{운영종료일}}
* 학교별 방학일에 맞춰 시작일을 지정할 수 있습니다.
● 모집대상: {{모집대상}}
● 운영시간: {{운영시간}}
(의무 학습: {{의무학습종료}}까지)
* 일요일 자율등원

⭐ 청라에서 함께하는 학습 관리
✔ 영어·수학 원장님과 국어 전문 선생님의 학습 상담 및 과목별 1:1 질의응답
✔ 수능·내신 학습자료 제공📚
✔ 남녀 분리 열람실과 학습에 집중할 수 있는 쾌적한 환경

할인·장학 안내: {{할인장학안내}}
* 교육비는 계좌이체 및 카드 결제가 가능합니다.

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('등록 후 감사 · 따뜻한 안내','등록','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
{{학생이름}} 학생이 소중한 시간 내어 방문해 주었습니다. 감사합니다🤗

입시를 준비하며 고민과 불안으로 지치는 순간에도 청라의 선생님과 실장은 학생의 말에 귀 기울이고 든든한 버팀목이 되겠습니다.
간절한 걸음이 꿈을 향하도록 늘 함께하겠습니다🥰🍀

청라를 믿고 맡겨주셔서 감사합니다.

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('등록 후 감사 · 간단한 안내','등록','both','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
{{학생이름}} 학생의 앞날을 청라가 함께하게 되어 뜻깊습니다🤗

첫 등원일 {{첫등원일}}에 뵙겠습니다. 보내드린 준비사항을 확인해 주세요. 등원 전 미리 오셔서 짐을 정리하실 수 있습니다.
만나게 될 날을 기다리겠습니다🍀

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('재수 방문상담 후 · 학부모','상담','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
{{학생이름}} 학생과 소중한 시간 내어 방문해 주셔서 감사합니다🤗

입시를 준비하며 고민하고 흔들리는 순간에도 청라의 선생님과 실장은 학생의 말에 귀 기울이고 든든한 버팀목이 되겠습니다.
간절한 걸음이 꿈을 향하도록 청라가 함께하길 바랍니다🥰🍀

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('재수 방문상담 후 · 학생','상담','student','{{학생이름}} 학생, 안녕하세요🌿
소중한 시간 내어 청라에 방문해 주셔서 감사합니다🤗

수능까지 고민되거나 지치는 순간에도 언제든 편하게 말씀해 주세요. 청라의 선생님과 실장은 늘 귀 기울일 준비가 되어 있습니다.

주기적인 학습 상담, 국어·영어·수학 질의응답, 집중할 수 있는 시설과 분위기, 수능 후 대학 지원 상담까지 학생의 앞날을 위해 함께하겠습니다.
꿈을 향한 모든 걸음을 응원합니다🥰🍀

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('모의고사 응시 안내','모의고사','both','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
{{학생이름}} 학생 모의고사 안내입니다.

● 시험명: {{시험명}}
● 시험일: {{시험일}}
상세 일정과 준비물은 청라앱 공지사항을 확인해 주세요.

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

insert into public.cheongla_office_sms_templates(title,category,audience,body)values('모의고사 응시료 안내','모의고사','parent','“합격하는 공부 자세”
독학재수학원 청라입니다.🌿
{{학생이름}} 학생 모의고사 응시료 안내입니다.

시험명: {{시험명}}
시험일: {{시험일}}
응시료: {{청구금액}}원
납부기한: {{납부기한}}

<학원 계좌>
{{은행명}} {{계좌번호}} {{예금주}}
입금자명은 학생 이름으로 부탁드립니다. 송금 후 입금자명을 문자로 알려주세요.
💳 카드 결제도 가능합니다. 결제 방법은 학원으로 문의해 주세요.

궁금하신 사항은 언제든 연락해 주세요. 감사합니다😊🍀
______
카카오톡 {{카카오톡}}
인스타그램 {{인스타그램}}
{{학원전화}}
{{학원휴대폰}}');

notify pgrst,'reload schema';
