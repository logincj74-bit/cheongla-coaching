-- End the temporary principal/manager collaboration at the principal's request.
-- Keep every document, revision, archive and prescription intact.
create or replace function cheongla_private.can_manage_mbti_operations()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles
 where id=(select auth.uid()) and approval_status='approved'
 and membership_state='active'
 and role in('owner','english_director','math_director'));
$$;
revoke all on function cheongla_private.can_manage_mbti_operations() from public,anon;
grant execute on function cheongla_private.can_manage_mbti_operations() to authenticated;

create or replace function cheongla_private.can_use_mbti_study()
returns boolean language sql stable security definer set search_path='' as $$
 select cheongla_private.can_manage_mbti_operations();
$$;
revoke all on function cheongla_private.can_use_mbti_study() from public,anon;
grant execute on function cheongla_private.can_use_mbti_study() to authenticated;

-- Apply the role gate to direct writes as well as reads of the former tables.
do $$declare table_name text;begin
 foreach table_name in array array['cheongla_mbti_preferences','cheongla_mbti_guides',
  'cheongla_mbti_introductions','cheongla_mbti_learning_articles',
  'cheongla_mbti_operation_references','cheongla_mbti_prescriptions'] loop
  execute format('drop policy if exists principal_only_role_release on public.%I',table_name);
  execute format('create policy principal_only_role_release on public.%I as restrictive for all to authenticated using((select cheongla_private.can_manage_mbti_operations())) with check((select cheongla_private.can_manage_mbti_operations()))',table_name);
 end loop;
end;$$;
notify pgrst,'reload schema';
