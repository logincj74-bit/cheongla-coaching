begin;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();n1 uuid:=gen_random_uuid();n2 uuid:=gen_random_uuid();n3 uuid:=gen_random_uuid();other uuid:=gen_random_uuid();
begin
 insert into auth.users(id,email,raw_user_meta_data)select x,'notification-trash-'||x||'@example.invalid','{"full_name":"알림휴지통검증","contact_phone":"01000000994"}'::jsonb from unnest(array[a,b])x;
 update public.cheongla_profiles set role='manager',approval_status='approved'where id in(a,b);
 insert into public.cheongla_notifications(id,recipient_id,source_kind,source_id,title,route,event_key,created_at,inbox_until)values
 (n1,a,'push_test',a,'최근 알림','notifications','trash-test:'||n1,clock_timestamp()-interval'1 hour',clock_timestamp()+interval'23 hours'),
 (n2,a,'push_test',a,'하루 지난 알림','notifications','trash-test:'||n2,clock_timestamp()-interval'25 hours',clock_timestamp()-interval'1 hour'),
 (n3,a,'push_test',a,'다른 최근 알림','notifications','trash-test:'||n3,clock_timestamp(),clock_timestamp()+interval'24 hours'),
 (other,b,'push_test',b,'다른 사람의 알림','notifications','trash-test:'||other,clock_timestamp(),clock_timestamp()+interval'24 hours');
 perform set_config('test.trash.actor',a::text,true);perform set_config('test.trash.other',other::text,true);perform set_config('test.trash.n1',n1::text,true);perform set_config('test.trash.n2',n2::text,true);perform set_config('test.trash.n3',n3::text,true);
 assert not has_function_privilege('anon','public.cheongla_notification_action(uuid,text)','execute'),'anonymous action access';
 assert not has_function_privilege('anon','public.cheongla_notification_trash(integer)','execute'),'anonymous trash access';
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.trash.actor'),true);
set local role authenticated;
do $$
declare n1 uuid:=current_setting('test.trash.n1')::uuid;n2 uuid:=current_setting('test.trash.n2')::uuid;n3 uuid:=current_setting('test.trash.n3')::uuid;other uuid:=current_setting('test.trash.other')::uuid;r jsonb;
begin
 r:=public.cheongla_my_notifications(20);perform set_config('test.trash.unread',r->>'unread_count',true);assert(select count(*)=2 from jsonb_array_elements(r->'items')x where x->>'event_key'like 'trash-test:%'),'expiry or own-only inbox failed';assert not exists(select 1 from public.cheongla_notifications where id=other),'other recipient RLS failed';
 r:=public.cheongla_notification_trash(20);assert(r->>'total_count')::int=1 and r->'items'->0->>'id'=n2::text,'24-hour automatic trash failed';
 begin perform public.cheongla_notification_action(other,'archive');raise exception 'other member archive accepted';exception when insufficient_privilege then null;end;
 perform public.cheongla_notification_action(n1,'archive');r:=public.cheongla_my_notifications(20);assert(r->>'unread_count')::int=current_setting('test.trash.unread')::int-1,'deleted notification still unread';
 r:=public.cheongla_notification_trash(20);assert(r->>'total_count')::int=2,'manual archive failed';
 perform public.cheongla_notification_action(n2,'restore');r:=public.cheongla_my_notifications(20);assert exists(select 1 from jsonb_array_elements(r->'items')x where x->>'id'=n2::text),'restore failed';assert(select inbox_until>clock_timestamp()+interval'23 hours'from public.cheongla_notifications where id=n2),'restore did not renew 24 hours';
 begin perform public.cheongla_notification_action(n2,'purge');raise exception 'live purge accepted';exception when raise_exception then if sqlerrm='live purge accepted'then raise;end if;end;
 perform public.cheongla_notification_action(n1,'purge');assert not exists(select 1 from public.cheongla_notifications where id=n1),'individual purge failed';
 perform public.cheongla_notification_action(n3,'archive');assert public.cheongla_notification_action(null,'empty')=1,'empty trash count failed';
 r:=public.cheongla_my_notifications(20);assert exists(select 1 from jsonb_array_elements(r->'items')x where x->>'id'=n2::text),'empty trash removed live inbox';
 assert(public.cheongla_notification_trash(20)->>'total_count')::int=0,'trash not empty';
end $$;
reset role;
do $$begin assert exists(select 1 from public.cheongla_notifications where id=current_setting('test.trash.other')::uuid),'other member notification removed';end $$;
rollback;
select 'PASS: 24-hour auto-trash without app activity, unread badge exclusion, manual delete/restore/purge/empty, restore renews 24 hours, real authenticated RLS and other-recipient protection; all fixtures rolled back' as result;
