-- This subtransaction rolls back every test post, notification and pg_net request.
do $test$
declare principal uuid;actor uuid;saved jsonb;post uuid;expected integer;actual integer;affected integer;
begin
 begin
  select id into principal from public.cheongla_profiles where role='english_director'and approval_status='approved'and membership_state='active'limit 1;
  if principal is null then raise exception 'Principal missing';end if;
  perform set_config('request.jwt.claim.sub',principal::text,true);
  execute 'set local role authenticated';
  saved:=public.cheongla_save_daily_word(date '1900-01-02','게시 검증','검증 후 되돌릴 임시 글','published',null);post:=(saved->>'id')::uuid;
  if not cheongla_private.can_read_notification('daily_word',post,null)then raise exception 'Notification source rejected';end if;
  begin perform public.cheongla_save_daily_word(date '1900-01-02','','충돌 검증','published',null);raise exception 'Missing version accepted';exception when serialization_failure then null;end;
  execute 'reset role';
  select count(*)into expected from public.cheongla_profiles where approval_status='approved'and membership_state='active';
  select count(*)into actual from public.cheongla_notifications where source_kind='daily_word'and source_id=post;
  if actual<>expected then raise exception 'Notification recipients mismatch';end if;
  for actor in select id from public.cheongla_profiles where role in('student','parent','manager')loop
   perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';
   begin perform public.cheongla_save_daily_word(date '1900-01-03','','작성 금지 검증','draft',null);raise exception 'Non-principal RPC write allowed';exception when insufficient_privilege then null;end;
   begin insert into public.cheongla_daily_words(message_on,body)values(date '1900-01-03','직접 입력 금지 검증');raise exception 'Direct insert allowed';exception when insufficient_privilege then null;end;
   update public.cheongla_daily_words set body='직접 수정 금지 검증'where id=post;get diagnostics affected=row_count;if affected<>0 then raise exception 'Direct update allowed';end if;
   execute 'reset role';
  end loop;
  perform set_config('request.jwt.claim.sub','',true);execute 'set local role anon';
  if not exists(select 1 from public.cheongla_daily_words where id=post)then raise exception 'Public read blocked';end if;
  execute 'reset role';perform set_config('request.jwt.claim.sub',principal::text,true);execute 'set local role authenticated';
  saved:=public.cheongla_save_daily_word(date '1900-01-02','비공개 수정 검증','수정 확인용 임시 글','draft',(saved->>'updated_at')::timestamptz);
  if saved->>'body'<>'수정 확인용 임시 글'then raise exception 'Edit failed';end if;
  begin perform public.cheongla_save_daily_word(date '2026-11-20','','날짜 검증','draft',null);raise exception 'After-exam date allowed';exception when invalid_parameter_value then null;end;
  execute 'reset role';perform set_config('request.jwt.claim.sub','',true);execute 'set local role anon';
  if exists(select 1 from public.cheongla_daily_words where id=post)then raise exception 'Draft exposed';end if;
  execute 'reset role';
  raise sqlstate 'ZX058'using message='PASS';
 exception when sqlstate 'ZX058'then null;end;
 if exists(select 1 from public.cheongla_daily_words where id=post)or exists(select 1 from public.cheongla_notifications where source_id=post)then raise exception 'Test rollback failed';end if;
 raise notice 'PASS principal publish/edit, manager/student/parent and withdrawn write denial, public/draft read, conflict/date guards, all approved notification recipients, complete rollback';
end;$test$;
