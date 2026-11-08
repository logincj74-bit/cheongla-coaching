create table public.cheongla_mbti_introductions (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null check (char_length(btrim(body)) between 1 and 20000),
  archived_at timestamptz,
  revision integer not null default 1
);

create unique index cheongla_one_published_mbti_introduction
  on public.cheongla_mbti_introductions ((true)) where archived_at is null;

alter table public.cheongla_mbti_introductions enable row level security;
revoke all on public.cheongla_mbti_introductions from public, anon, authenticated;
grant select, delete on public.cheongla_mbti_introductions to authenticated;
grant insert (title, body), update (title, body, archived_at)
  on public.cheongla_mbti_introductions to authenticated;

create policy mbti_introduction_member_read on public.cheongla_mbti_introductions
  for select to authenticated
  using (archived_at is null and (select exists (
    select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved' and membership_state = 'active'
  )));

create policy mbti_introduction_principal_manage on public.cheongla_mbti_introductions
  for all to authenticated
  using ((select exists (
    select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved'
      and membership_state = 'active' and role in ('owner', 'english_director', 'math_director')
  )))
  with check ((select exists (
    select 1 from public.cheongla_profiles
    where id = (select auth.uid()) and approval_status = 'approved'
      and membership_state = 'active' and role in ('owner', 'english_director', 'math_director')
  )));

create policy mbti_introduction_delete_only_from_trash on public.cheongla_mbti_introductions
  as restrictive for delete to authenticated using (archived_at is not null);

create function cheongla_private.bump_mbti_introduction_revision()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.revision := old.revision + 1;
  return new;
end;
$$;

revoke all on function cheongla_private.bump_mbti_introduction_revision() from public, anon, authenticated;
create trigger mbti_introduction_revision before update on public.cheongla_mbti_introductions
  for each row execute function cheongla_private.bump_mbti_introduction_revision();

insert into public.cheongla_mbti_introductions (title, body) values (
  '나를 이해하는 공부, 나에게 맞는 학습법',
  $article$MBTI로 시작하는 자기주도학습의 새로운 접근

청라학원 | 나의 MBTI 학습법

같은 교실에서, 같은 교재로, 같은 시간을 공부하는 학생들.

그런데 왜 어떤 학생은 계획표를 꼼꼼하게 작성할 때 공부가 잘되고, 어떤 학생은 큰 목표를 먼저 세워야 공부의 방향을 잡을 수 있을까요?

어떤 학생은 혼자 조용히 생각하며 문제를 해결하는 것을 좋아하고, 또 어떤 학생은 누군가에게 설명하거나 질문을 주고받는 과정에서 이해가 깊어집니다.

우리는 흔히 이런 차이를 집중력이나 의지, 공부 습관의 차이로 설명합니다.

그러나 여기에는 한 가지 더 살펴볼 문제가 있습니다.

학생마다 정보를 받아들이고, 생각을 정리하고, 학습을 계획하는 방식이 다를 수 있다는 사실입니다.

청라학원은 바로 이 지점에서 출발합니다.

1. 공부를 잘하는 방법은 모두에게 같을까요?

많은 학생이 공부를 잘하는 친구의 방법을 따라 합니다.

성적이 우수한 학생의 계획표를 그대로 작성하고, 유명 강사의 학습법을 적용하며, 다른 사람이 효과를 보았다는 공부 습관을 자신의 일상에 옮겨 놓습니다.

물론 이러한 시도는 도움이 될 수 있습니다.

하지만 다른 사람에게 효과적이었던 방법이 나에게도 반드시 효과적인 것은 아닙니다.

학습에는 개인차가 존재하기 때문입니다.

학생마다 선행지식과 이해 속도, 학습 동기, 주의집중의 특성, 정서적 반응, 생활환경이 다릅니다. 같은 학습 방법이라도 학생의 현재 상황에 따라 효과가 달라질 수 있습니다.

따라서 중요한 것은 단순히 좋은 공부법을 찾는 일이 아닙니다.

나에게 어떤 공부법이 효과적인지 직접 확인하고 발전시키는 일입니다.

2. MBTI는 공부를 이해하는 하나의 출발점입니다.

MBTI는 개인이 선호하는 인식과 판단의 경향을 네 가지 선호 지표로 살펴보는 성격유형 도구입니다.

• 외향(E)과 내향(I): 에너지를 얻고 주의를 기울이는 방향
• 감각(S)과 직관(N): 정보를 받아들이고 해석할 때 선호하는 방식
• 사고(T)와 감정(F): 판단할 때 상대적으로 중시하는 기준
• 판단(J)과 인식(P): 외부 세계에 접근하고 생활을 조직하는 방식

이러한 차이는 학생이 자신의 평소 행동과 공부 습관을 돌아보는 데 흥미로운 질문을 제공합니다.

다만 MBTI 유형만으로 학생의 지능, 학업 능력, 성적 또는 가장 효과적인 학습법을 예측할 수는 없습니다.

청라학원은 MBTI를 학생의 가능성을 규정하는 기준으로 사용하지 않습니다.

오히려 자신의 선호를 이해하고, 익숙하지 않은 학습 방법까지 탐색하며, 더 유연한 공부 습관을 만들어 가기 위한 참고 도구로 활용합니다.

3. 청라학원은 성격유형보다 학생의 실제 학습을 중요하게 생각합니다.

예를 들어 계획을 세우는 것을 선호하는 학생이라면 세부적인 주간 계획과 점검표를 활용해 볼 수 있습니다.

반대로 유연한 접근을 선호하는 학생이라면 핵심 목표를 먼저 정하고 학습 순서를 선택할 수 있는 방식을 시도해 볼 수 있습니다.

혼자 생각하는 시간이 필요한 학생은 개별 문제 풀이와 자기 설명을 활용하고, 대화를 통해 생각을 정리하는 학생은 질문과 설명 활동을 병행해 볼 수 있습니다.

그러나 이것은 특정 MBTI 유형에 반드시 적합하다고 검증된 공식이 아닙니다.

학생의 선호를 바탕으로 시도해 볼 수 있는 여러 학습 전략의 예시입니다.

중요한 것은 성격유형에 맞춰 공부법을 고정하는 것이 아니라, 실제 학습 결과를 통해 자신에게 효과적인 방법을 발견하는 것입니다.

4. 청라앱의 ‘나의 MBTI 학습법’은 이렇게 활용합니다.

첫째, 나를 이해합니다.

자신의 성격적 선호와 평소 학습 습관을 살펴봅니다. 공부할 때 편안하게 느끼는 환경, 계획을 실천하는 방식, 어려운 문제에 대처하는 태도를 돌아봅니다.

둘째, 나의 공부 습관을 점검합니다.

계획을 세우는 데 시간을 지나치게 사용하지는 않는지, 문제를 충분히 이해하기 전에 풀이부터 시작하지는 않는지, 복습이나 오답 정리를 미루고 있지는 않은지 살펴봅니다.

셋째, 다양한 학습 전략을 시도합니다.

과목별 학습 목표와 자신의 현재 수준에 맞춰 계획 수립, 인출 연습, 간격을 둔 복습, 문제 풀이, 자기 설명 등의 방법을 실천합니다.

넷째, 결과를 확인하고 개선합니다.

학습 시간만이 아니라 계획 달성률, 오답의 변화, 이해도, 기억 유지 정도를 살펴봅니다.

효과가 있었던 방법은 발전시키고, 효과가 부족했던 방법은 수정합니다.

이러한 과정이 반복될 때 학생은 자신에게 맞는 공부 방법을 스스로 선택하는 능력을 키울 수 있습니다.

5. 학부모님께 드리는 말씀

자녀가 부모님의 기대와 다른 방식으로 공부한다고 해서 반드시 잘못된 방법으로 공부하고 있는 것은 아닙니다.

반대로 자녀가 좋아하는 방식이라고 해서 언제나 효과적인 공부법인 것도 아닙니다.

중요한 것은 자녀의 성향을 존중하면서도 실제 학습 성과를 함께 살펴보는 균형 잡힌 태도입니다.

MBTI를 통해 자녀를 특정 유형으로 단정하거나 행동의 한계를 정하기보다는, 자녀가 어떤 상황에서 공부를 어려워하는지, 어떤 도움을 필요로 하는지 대화를 시작해 보시기 바랍니다.

청라학원은 학생을 하나의 성격유형으로 판단하지 않습니다.

학생의 학습 기록과 상담, 실제 성취 수준, 생활 습관을 종합적으로 살피며 각자의 성장 방향을 함께 찾아가고자 합니다.

6. 청라학원이 생각하는 진정한 자기주도학습

자기주도학습은 단순히 혼자 공부하는 것이 아닙니다.

자신의 학습 상태를 이해하고, 목표를 세우며, 적절한 전략을 선택하고, 결과를 점검하여 스스로 개선하는 과정입니다.

청라학원의 MBTI 학습법은 이러한 자기주도학습을 시작하는 하나의 계기가 되고자 합니다.

성격유형은 학생의 미래를 결정하지 않습니다.

오늘의 공부 습관 또한 평생 변하지 않는 것이 아닙니다.

학생은 경험하고, 배우고, 실패하고, 다시 시도하면서 성장합니다.

MBTI는 나를 가두는 네 글자가 아니라, 나를 이해하기 위해 던지는 네 가지 질문의 시작입니다.

그리고 청라학원이 궁극적으로 지향하는 것은 MBTI 유형에 맞는 학생을 만드는 일이 아니라, 자기 자신을 이해하고 스스로 공부할 줄 아는 학생을 길러내는 일입니다.

나를 이해하는 공부에서, 스스로 성장하는 공부로.

청라학원은 학생 한 사람 한 사람의 가능성을 함께 발견하겠습니다.

청라학원 | 나의 MBTI 학습법

⸻

※ 안내: MBTI는 학업 능력이나 성적을 진단하는 검사가 아닙니다. 청라학원의 MBTI 학습법은 자기이해와 학습 상담을 위한 보조적 접근이며, 학습 전략의 효과는 학생의 실제 학습 기록과 성취 결과를 바탕으로 판단합니다.$article$
);
