begin;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
create table if not exists cheongla_private.push_settings(
 singleton boolean primary key default true check(singleton),
 public_key text,private_key text,subject text,
 webhook_secret text not null default encode(extensions.gen_random_bytes(32),'hex'),
 dispatcher_url text not null default 'https://heghuzbppjzxixecuuwd.supabase.co/functions/v1/cheongla-push',
 enabled boolean not null default false
);
insert into cheongla_private.push_settings(singleton) values(true) on conflict do nothing;
revoke all on cheongla_private.push_settings from public,anon,authenticated;
create table if not exists public.cheongla_push_subscriptions(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.cheongla_profiles(id) on delete cascade,
 endpoint text not null unique,p256dh text not null,auth_key text not null,
 enabled boolean not null default true,updated_at timestamptz not null default clock_timestamp()
);
alter table public.cheongla_push_subscriptions enable row level security;
revoke all on public.cheongla_push_subscriptions from public,anon,authenticated;
create table if not exists cheongla_private.push_deliveries(
 id bigint generated always as identity primary key,
 notification_id uuid not null references public.cheongla_notifications(id) on delete cascade,
 subscription_id uuid not null references public.cheongla_push_subscriptions(id) on delete cascade,
 state text not null default 'pending' check(state in ('pending','processing','sent','failed','cancelled')),
 attempts integer not null default 0,next_attempt_at timestamptz not null default clock_timestamp(),
 last_attempt_at timestamptz,finished_at timestamptz,http_status integer,
 created_at timestamptz not null default clock_timestamp(),unique(notification_id,subscription_id)
);
create index if not exists cheongla_push_retry on cheongla_private.push_deliveries(state,next_attempt_at,created_at) where attempts<3 and state in ('pending','failed','processing');
create index if not exists cheongla_push_users on public.cheongla_push_subscriptions(user_id) where enabled;
revoke all on cheongla_private.push_deliveries from public,anon,authenticated;
create or replace function public.cheongla_push_config()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('enabled',s.enabled,'public_key',case when s.enabled then s.public_key else null end)
 from cheongla_private.push_settings s where singleton
 and exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved');
$$;
create or replace function public.cheongla_save_push_subscription(push_endpoint text,push_p256dh text,push_auth text)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;
begin
 if not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved') then raise exception '승인된 계정으로 이용해 주세요.' using errcode='42501';end if;
 if not exists(select 1 from cheongla_private.push_settings where singleton and enabled) then raise exception '푸시 서버 연결을 준비 중입니다.';end if;
 if push_endpoint is null or length(push_endpoint)>2000 or push_endpoint !~ '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-zA-Z0-9-]+\.push\.apple\.com|[a-zA-Z0-9.-]+\.notify\.windows\.com)/'
 or push_p256dh is null or push_p256dh !~ '^[A-Za-z0-9_-]{80,100}$'
 or push_auth is null or push_auth !~ '^[A-Za-z0-9_-]{16,32}$' then raise exception '휴대전화 알림 구독 정보를 확인해 주세요.';end if;
 insert into public.cheongla_push_subscriptions(user_id,endpoint,p256dh,auth_key)
 values((select auth.uid()),push_endpoint,push_p256dh,push_auth)
 on conflict(endpoint) do update set user_id=excluded.user_id,p256dh=excluded.p256dh,auth_key=excluded.auth_key,enabled=true,updated_at=clock_timestamp()
 where public.cheongla_push_subscriptions.user_id=(select auth.uid()) or (public.cheongla_push_subscriptions.p256dh=excluded.p256dh and public.cheongla_push_subscriptions.auth_key=excluded.auth_key)
 returning id into result_id;
 if result_id is null then raise exception '이 기기의 알림 연결을 다시 확인해 주세요.';end if;
 return result_id;
end;$$;
create or replace function public.cheongla_push_device_status(push_endpoint text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_push_subscriptions where user_id=(select auth.uid()) and endpoint=push_endpoint and enabled)
 and exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved');
$$;
create or replace function public.cheongla_disable_push_subscription(push_endpoint text)
returns void language sql security definer set search_path='' as $$
 update public.cheongla_push_subscriptions set enabled=false,updated_at=clock_timestamp()
 where user_id=(select auth.uid()) and endpoint=push_endpoint;
$$;
create or replace function cheongla_private.push_source_allowed(reader uuid,kind text,target uuid,student uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare old_sub text=current_setting('request.jwt.claim.sub',true);old_claims text=current_setting('request.jwt.claims',true);allowed boolean;
begin
 if not exists(select 1 from public.cheongla_profiles where id=reader and approval_status='approved') then return false;end if;
 if kind='push_test' then return true;end if;
 perform set_config('request.jwt.claim.sub',reader::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reader)::text,true);
 begin
  allowed=cheongla_private.can_read_notification(kind,target,student);
 exception when others then
  perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);
  perform set_config('request.jwt.claims',coalesce(old_claims,''),true);
  raise;
 end;
 perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);
 perform set_config('request.jwt.claims',coalesce(old_claims,''),true);
 return allowed;
end;$$;
revoke all on function cheongla_private.push_source_allowed(uuid,text,uuid,uuid) from public,anon,authenticated;
-- 본인 알림함에서 테스트 알림도 확인할 수 있도록 정책을 확장합니다.
drop policy if exists cheongla_notification_read on public.cheongla_notifications;
create policy cheongla_notification_read on public.cheongla_notifications for select to authenticated
using (recipient_id=(select auth.uid()) and (
 (source_kind='push_test' and exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved'))
 or cheongla_private.can_read_notification(source_kind,source_id,student_id)));
create or replace function cheongla_private.wake_push_dispatcher()
returns void language plpgsql security definer set search_path='' as $$
declare s cheongla_private.push_settings%rowtype;
begin
 select * into s from cheongla_private.push_settings where singleton;
 if not s.enabled or not exists(select 1 from cheongla_private.push_deliveries where attempts<3 and ((state in ('pending','failed') and next_attempt_at<=clock_timestamp()) or (state='processing' and last_attempt_at<clock_timestamp()-interval '2 minutes'))) then return;end if;
 perform net.http_post(url:=s.dispatcher_url,body:='{"action":"dispatch"}'::jsonb,headers:=jsonb_build_object('Content-Type','application/json','x-cheongla-webhook',s.webhook_secret),timeout_milliseconds:=10000);
end;$$;
revoke all on function cheongla_private.wake_push_dispatcher() from public,anon,authenticated;
create or replace function cheongla_private.enqueue_push_notification()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from cheongla_private.push_settings where singleton and enabled) then
  insert into cheongla_private.push_deliveries(notification_id,subscription_id)
  select new.id,s.id from public.cheongla_push_subscriptions s where s.user_id=new.recipient_id and s.enabled on conflict do nothing;
  perform cheongla_private.wake_push_dispatcher();
 end if;
 return new;
end;$$;
revoke all on function cheongla_private.enqueue_push_notification() from public,anon,authenticated;
drop trigger if exists cheongla_enqueue_push on public.cheongla_notifications;
create trigger cheongla_enqueue_push after insert on public.cheongla_notifications for each row execute function cheongla_private.enqueue_push_notification();
create or replace function public.cheongla_push_server_config()
returns jsonb language sql security definer set search_path='' as $$ select to_jsonb(s) from cheongla_private.push_settings s where singleton;$$;
create or replace function public.cheongla_initialize_web_push(vapid_public text,vapid_private text,vapid_subject text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if vapid_public !~ '^[A-Za-z0-9_-]{87}$' or vapid_private !~ '^[A-Za-z0-9_-]{43}$' or vapid_subject is null or vapid_subject<>'https://logincj74-bit.github.io/cheongla-coaching/' or vapid_public is null or vapid_private is null then raise exception '서버 알림 키를 확인해 주세요.';end if;
 update cheongla_private.push_settings set public_key=coalesce(public_key,vapid_public),private_key=coalesce(private_key,vapid_private),subject=coalesce(subject,vapid_subject),enabled=true where singleton;
 return public.cheongla_push_server_config();
end;$$;
create or replace function public.cheongla_claim_push_deliveries()
returns jsonb language plpgsql security definer set search_path='' as $$
declare item record;batch jsonb='[]'::jsonb;
begin
 for item in
  select d.id as delivery_id,d.attempts,n.id as notification_id,n.recipient_id,n.source_kind,n.source_id,n.student_id,n.title,s.id as subscription_id,s.endpoint,s.p256dh,s.auth_key,s.enabled
  from cheongla_private.push_deliveries d join public.cheongla_notifications n on n.id=d.notification_id join public.cheongla_push_subscriptions s on s.id=d.subscription_id
  where d.attempts<3 and ((d.state in ('pending','failed') and d.next_attempt_at<=clock_timestamp()) or (d.state='processing' and d.last_attempt_at<clock_timestamp()-interval '2 minutes'))
  order by d.created_at,d.id limit 20 for update of d skip locked
 loop
  if not item.enabled or not exists(select 1 from public.cheongla_push_subscriptions where id=item.subscription_id and user_id=item.recipient_id)
  or not cheongla_private.push_source_allowed(item.recipient_id,item.source_kind,item.source_id,item.student_id) then
   update cheongla_private.push_deliveries set state='cancelled',finished_at=clock_timestamp() where id=item.delivery_id;continue;
  end if;
  update cheongla_private.push_deliveries set state='processing',attempts=attempts+1,last_attempt_at=clock_timestamp() where id=item.delivery_id;
  batch=batch||jsonb_build_array(to_jsonb(item));
 end loop;
 return batch;
end;$$;
create or replace function public.cheongla_finish_push_delivery(delivery bigint,response_status integer)
returns void language plpgsql security definer set search_path='' as $$
declare sub uuid;
begin
 update cheongla_private.push_deliveries set state=case when response_status between 200 and 299 then 'sent' when response_status in (404,410) then 'cancelled' else 'failed' end,
 http_status=response_status,finished_at=case when response_status between 200 and 299 or response_status in (404,410) then clock_timestamp() else null end,next_attempt_at=clock_timestamp()+interval '1 minute'
 where id=delivery and state='processing' returning subscription_id into sub;
 if response_status in (404,410) and sub is not null then update public.cheongla_push_subscriptions set enabled=false where id=sub;end if;
end;$$;
revoke all on function public.cheongla_push_server_config(),public.cheongla_initialize_web_push(text,text,text),public.cheongla_claim_push_deliveries(),public.cheongla_finish_push_delivery(bigint,integer) from public,anon,authenticated;
grant execute on function public.cheongla_push_server_config(),public.cheongla_initialize_web_push(text,text,text),public.cheongla_claim_push_deliveries(),public.cheongla_finish_push_delivery(bigint,integer) to service_role;
create or replace function public.cheongla_request_push_test()
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;
begin
 if not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved') then raise exception '승인된 계정으로 이용해 주세요.' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended((select auth.uid())::text,0));
 if exists(select 1 from public.cheongla_notifications where recipient_id=(select auth.uid()) and source_kind='push_test' and created_at>clock_timestamp()-interval '30 seconds') then raise exception '잠시 후 테스트 알림을 다시 요청해 주세요.';end if;
 if not exists(select 1 from public.cheongla_push_subscriptions where user_id=(select auth.uid()) and enabled) then raise exception '먼저 이 기기의 푸시 알림을 켜 주세요.';end if;
 insert into public.cheongla_notifications(recipient_id,source_kind,source_id,title,route,event_key)
 values((select auth.uid()),'push_test',(select auth.uid()),'청라 테스트 푸시 알림입니다.','notifications','push-test:'||gen_random_uuid()::text) returning id into result_id;
 return result_id;
end;$$;
-- 테스트 알림 읽음 처리를 포함합니다.
create or replace function public.cheongla_read_notification(target_notification uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 update public.cheongla_notifications set read_at=clock_timestamp() where recipient_id=(select auth.uid()) and read_at is null and (target_notification is null or id=target_notification)
 and cheongla_private.push_source_allowed((select auth.uid()),source_kind,source_id,student_id);
end;$$;
revoke all on function public.cheongla_push_config(),public.cheongla_save_push_subscription(text,text,text),public.cheongla_push_device_status(text),public.cheongla_disable_push_subscription(text),public.cheongla_request_push_test(),public.cheongla_read_notification(uuid) from public,anon,authenticated;
grant execute on function public.cheongla_push_config(),public.cheongla_save_push_subscription(text,text,text),public.cheongla_push_device_status(text),public.cheongla_disable_push_subscription(text),public.cheongla_request_push_test(),public.cheongla_read_notification(uuid) to authenticated;
select cron.schedule('cheongla-web-push-retry','* * * * *','select cheongla_private.wake_push_dispatcher();');
notify pgrst,'reload schema';
commit;
