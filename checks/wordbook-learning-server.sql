begin;
do $$declare a uuid;b uuid;begin
select id into a from public.cheongla_profiles where role='student' and approval_status='approved' and membership_state='active' limit 1;
select id into b from public.cheongla_profiles where role='parent' and approval_status='approved' and membership_state='active' limit 1;
if a is null or b is null then raise exception 'missing roles';end if;
perform set_config('test.a',a::text,true);perform set_config('test.b',b::text,true);
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
insert into public.cheongla_wordbook(user_id,word,meaning)values(current_setting('test.a')::uuid,'learning-state-test','검증');
update public.cheongla_wordbook set learned=true where word='learning-state-test';
do $$begin
if not exists(select 1 from public.cheongla_wordbook where word='learning-state-test' and learned)then raise exception 'own update failed';end if;
begin update public.cheongla_wordbook set user_id=current_setting('test.b')::uuid where word='learning-state-test';raise exception 'owner mutable';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
do $$declare n int;begin
update public.cheongla_wordbook set learned=false where user_id=current_setting('test.a')::uuid and word='learning-state-test';get diagnostics n=row_count;if n<>0 then raise exception 'cross user update';end if;
end$$;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
update public.cheongla_wordbook set learned=false where word='learning-state-test';
do $$begin
if not exists(select 1 from public.cheongla_wordbook where word='learning-state-test' and not learned)then raise exception 'review restore failed';end if;
end$$;
reset role;rollback;
select 'PASS own learned/review state, cross-user denial, immutable owner; tests rolled back' as result;
