begin;
alter table public.cheongla_wordbook add column learned boolean not null default false;
grant update(learned) on public.cheongla_wordbook to authenticated;
create policy cheongla_wordbook_learning on public.cheongla_wordbook for update to authenticated
using(user_id=(select auth.uid()) and (select cheongla_private.can_use_member_services()))
with check(user_id=(select auth.uid()) and (select cheongla_private.can_use_member_services()));
notify pgrst,'reload schema';
commit;
