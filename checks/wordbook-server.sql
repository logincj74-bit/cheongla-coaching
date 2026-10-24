begin;
do $$declare a uuid;b uuid;w uuid;
begin
 select id into a from public.cheongla_profiles where role='student'and approval_status='approved'and membership_state='active'limit 1;
 select id into b from public.cheongla_profiles where role='parent'and approval_status='approved'and membership_state='active'limit 1;
 select id into w from public.cheongla_profiles where membership_state='withdrawn'limit 1;
 if a is null or b is null or w is null then raise exception 'missing test roles';end if;
 perform set_config('test.wordbook_a',a::text,true);perform set_config('test.wordbook_b',b::text,true);perform set_config('test.wordbook_w',w::text,true);
end;$$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.wordbook_a'),true);
insert into public.cheongla_wordbook(user_id,word,meaning)values(current_setting('test.wordbook_a')::uuid,'wordbook-regression-test','[명사] 검증 단어');
insert into public.cheongla_wordbook(user_id,word,meaning)values(current_setting('test.wordbook_a')::uuid,'wordbook-regression-test','중복 검증')on conflict(user_id,word)do nothing;
do $$begin
 if(select count(*)from public.cheongla_wordbook where word='wordbook-regression-test')<>1 then raise exception 'FAIL own read or dedup';end if;
 begin
  insert into public.cheongla_wordbook(user_id,word,meaning)values(current_setting('test.wordbook_b')::uuid,'wordbook-regression-test','다른 회원으로 저장 차단');raise exception 'FAIL spoofed owner';
 exception when insufficient_privilege then null;end;
 begin
  update public.cheongla_wordbook set user_id=current_setting('test.wordbook_b')::uuid where word='wordbook-regression-test';raise exception 'FAIL reassignment';
 exception when insufficient_privilege then null;end;
 begin
  insert into public.cheongla_wordbook(user_id,word,meaning)values(current_setting('test.wordbook_a')::uuid,'../invalid','잘못된 단어');raise exception 'FAIL invalid word';
 exception when check_violation then null;end;
end;$$;
select set_config('request.jwt.claim.sub',current_setting('test.wordbook_b'),true);
do $$declare n integer;
begin
 if exists(select 1 from public.cheongla_wordbook where word='wordbook-regression-test')then raise exception 'FAIL another user read';end if;
 delete from public.cheongla_wordbook where user_id=current_setting('test.wordbook_a')::uuid and word='wordbook-regression-test';get diagnostics n=row_count;if n<>0 then raise exception 'FAIL another user delete';end if;
end;$$;
select set_config('request.jwt.claim.sub',current_setting('test.wordbook_w'),true);
do $$begin
 begin
  insert into public.cheongla_wordbook(user_id,word,meaning)values(current_setting('test.wordbook_w')::uuid,'wordbook-regression-test','탈퇴 계정 저장 차단');raise exception 'FAIL withdrawn write';
 exception when insufficient_privilege then null;end;
 if exists(select 1 from public.cheongla_wordbook)then raise exception 'FAIL withdrawn read';end if;
end;$$;
select set_config('request.jwt.claim.sub',current_setting('test.wordbook_a'),true);
delete from public.cheongla_wordbook where word='wordbook-regression-test';
do $$begin if exists(select 1 from public.cheongla_wordbook where word='wordbook-regression-test')then raise exception 'FAIL own delete';end if;end;$$;
reset role;
set local role anon;
do $$begin
 begin perform 1 from public.cheongla_wordbook;raise exception 'FAIL anonymous read';exception when insufficient_privilege then null;end;
end;$$;
reset role;
rollback;
select 'PASS: own account save/read/delete, duplicate prevention, other-user/withdrawn/anonymous denial, invalid-word and owner reassignment rejection. All test data rolled back.' as result;
