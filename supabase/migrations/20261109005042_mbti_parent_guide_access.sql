alter policy mbti_learning_article_member_read on public.cheongla_mbti_learning_articles
  using (
    archived_at is null and (select exists (
      select 1 from public.cheongla_profiles as profile
      where profile.id = (select auth.uid())
        and profile.approval_status = 'approved'
        and profile.membership_state = 'active'
        and (category = 'groups' or profile.role in ('parent', 'owner', 'english_director', 'math_director', 'manager'))
    ))
  );
