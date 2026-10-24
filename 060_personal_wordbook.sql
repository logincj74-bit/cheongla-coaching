begin;
create table public.cheongla_wordbook(
 user_id uuid not null references public.cheongla_profiles(id) on delete cascade,
 word text not null check(word=lower(btrim(word)) and word ~ '^[a-z][a-z0-9 .''-]{0,79}$'),
 meaning text not null check(length(btrim(meaning)) between 1 and 8000),
 pronunciation text not null default '' check(length(pronunciation)<=200),
 created_at timestamptz not null default clock_timestamp(),
 primary key(user_id,word)
);
alter table public.cheongla_wordbook enable row level security;
revoke all on public.cheongla_wordbook from public,anon,authenticated;
grant select,insert,delete on public.cheongla_wordbook to authenticated;
create policy cheongla_wordbook_read on public.cheongla_wordbook for select to authenticated
 using(user_id=(select auth.uid()) and (select cheongla_private.can_use_member_services()));
create policy cheongla_wordbook_save on public.cheongla_wordbook for insert to authenticated
 with check(user_id=(select auth.uid()) and (select cheongla_private.can_use_member_services()));
create policy cheongla_wordbook_delete on public.cheongla_wordbook for delete to authenticated
 using(user_id=(select auth.uid()) and (select cheongla_private.can_use_member_services()));
notify pgrst,'reload schema';
commit;
