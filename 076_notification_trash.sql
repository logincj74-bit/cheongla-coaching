-- An explicit expiry implements auto-trash even while the app is closed.
alter table public.cheongla_notifications add column if not exists inbox_until timestamptz;
alter table public.cheongla_notifications add column if not exists archived_at timestamptz;
update public.cheongla_notifications set inbox_until=created_at+interval '24 hours'where inbox_until is null;
alter table public.cheongla_notifications alter column inbox_until set default(clock_timestamp()+interval '24 hours');
alter table public.cheongla_notifications alter column inbox_until set not null;
create index if not exists cheongla_notification_owner_expiry on public.cheongla_notifications(recipient_id,inbox_until);

create or replace function public.cheongla_my_notifications(page_limit integer default 20)returns jsonb language plpgsql stable set search_path='' as $$
declare items jsonb;unread bigint;
begin
 if page_limit is null or page_limit not between 1 and 200 then raise exception '알림 조회 범위를 확인해 주세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(n)order by n.created_at desc,n.id desc),'[]')into items from(select *from public.cheongla_notifications where archived_at is null and inbox_until>clock_timestamp()order by created_at desc,id desc limit page_limit)n;
 select count(*)into unread from public.cheongla_notifications where read_at is null and archived_at is null and inbox_until>clock_timestamp();
 return jsonb_build_object('items',items,'unread_count',unread);
end;$$;

create or replace function public.cheongla_notification_trash(page_limit integer default 20)returns jsonb language plpgsql security definer set search_path='' as $$
declare items jsonb;total bigint;
begin
 if not cheongla_private.can_use_member_services()then raise exception '로그인 후 본인의 알림만 확인할 수 있습니다.'using errcode='42501';end if;
 if page_limit is null or page_limit not between 1 and 200 then raise exception '조회 범위를 확인해 주세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(n)order by n.trashed_at desc,n.id desc),'[]')into items from(select id,title,created_at,read_at,coalesce(archived_at,inbox_until)as trashed_at,case when archived_at is null then 'expired'else 'manual'end as trash_reason from public.cheongla_notifications where recipient_id=auth.uid()and(archived_at is not null or inbox_until<=clock_timestamp())order by coalesce(archived_at,inbox_until)desc,id desc limit page_limit)n;
 select count(*)into total from public.cheongla_notifications where recipient_id=auth.uid()and(archived_at is not null or inbox_until<=clock_timestamp());
 return jsonb_build_object('items',items,'total_count',total);
end;$$;

create or replace function public.cheongla_notification_action(target_notification uuid,notification_action text)returns integer language plpgsql security definer set search_path='' as $$
declare n public.cheongla_notifications%rowtype;affected integer;
begin
 if not cheongla_private.can_use_member_services()then raise exception '로그인 후 본인의 알림만 관리할 수 있습니다.'using errcode='42501';end if;
 if notification_action='empty'then
  delete from public.cheongla_notifications where recipient_id=auth.uid()and(archived_at is not null or inbox_until<=clock_timestamp());get diagnostics affected=row_count;return affected;
 end if;
 select *into n from public.cheongla_notifications where id=target_notification and recipient_id=auth.uid()for update;
 if not found then raise exception '본인의 알림을 찾을 수 없습니다.'using errcode='42501';end if;
 if notification_action='archive'then
  update public.cheongla_notifications set archived_at=coalesce(archived_at,clock_timestamp())where id=n.id;
  update cheongla_private.push_deliveries set state='cancelled'where notification_id=n.id and state in('pending','failed');
 elsif notification_action='restore'and(n.archived_at is not null or n.inbox_until<=clock_timestamp())then
  update public.cheongla_notifications set archived_at=null,inbox_until=clock_timestamp()+interval '24 hours'where id=n.id;
 elsif notification_action='purge'and(n.archived_at is not null or n.inbox_until<=clock_timestamp())then delete from public.cheongla_notifications where id=n.id;
 else raise exception '휴지통 상태와 처리 항목을 확인해 주세요.';end if;
 return 1;
end;$$;
revoke all on function public.cheongla_notification_trash(integer),public.cheongla_notification_action(uuid,text)from public,anon;
grant execute on function public.cheongla_notification_trash(integer),public.cheongla_notification_action(uuid,text)to authenticated;
notify pgrst,'reload schema';
CREATE OR REPLACE FUNCTION public.cheongla_claim_push_deliveries()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item record;batch jsonb='[]'::jsonb;
begin
 for item in
  select d.id as delivery_id,d.attempts,n.id as notification_id,n.recipient_id,n.source_kind,n.source_id,n.student_id,n.title,n.archived_at,n.inbox_until,s.id as subscription_id,s.endpoint,s.p256dh,s.auth_key,s.enabled
  from cheongla_private.push_deliveries d join public.cheongla_notifications n on n.id=d.notification_id join public.cheongla_push_subscriptions s on s.id=d.subscription_id
  where d.attempts<6 and ((d.state in ('pending','failed') and d.next_attempt_at<=clock_timestamp()) or (d.state='processing' and d.last_attempt_at<clock_timestamp()-interval '3 minutes'))
  order by d.created_at,d.id limit 40 for update of d skip locked
 loop
  if item.archived_at is not null or item.inbox_until<=clock_timestamp()or not item.enabled or not exists(select 1 from public.cheongla_push_subscriptions where id=item.subscription_id and user_id=item.recipient_id)
  or not cheongla_private.push_source_allowed(item.recipient_id,item.source_kind,item.source_id,item.student_id) then
   update cheongla_private.push_deliveries set state='cancelled',finished_at=clock_timestamp() where id=item.delivery_id;continue;
  end if;
  update cheongla_private.push_deliveries set state='processing',attempts=attempts+1,last_attempt_at=clock_timestamp() where id=item.delivery_id;
  batch=batch||jsonb_build_array(to_jsonb(item));
 end loop;
 return batch;
end;$function$
;

CREATE OR REPLACE FUNCTION public.cheongla_read_notification(target_notification uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 update public.cheongla_notifications set read_at=clock_timestamp() where recipient_id=(select auth.uid()) and read_at is null and archived_at is null and inbox_until>clock_timestamp()and (target_notification is null or id=target_notification)
 and cheongla_private.push_source_allowed((select auth.uid()),source_kind,source_id,student_id);
end;$function$
;

