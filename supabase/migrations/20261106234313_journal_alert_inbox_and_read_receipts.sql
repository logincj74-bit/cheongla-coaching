-- Minimal institutional acknowledgement metadata, independent of inbox deletion.
create table if not exists cheongla_private.journal_notification_receipts(
 event_id uuid not null references cheongla_private.journal_notification_events(id)on delete cascade,
 recipient_id uuid not null references public.cheongla_profiles(id)on delete cascade,
 recipient_name text not null,recipient_role text not null,received_at timestamptz not null,read_at timestamptz,
 primary key(event_id,recipient_id)
);
alter table cheongla_private.journal_notification_receipts enable row level security;
revoke all on cheongla_private.journal_notification_receipts from public,anon,authenticated;
create or replace function cheongla_private.capture_journal_alert_receipt()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.source_kind<>'staff_journal'or not exists(select 1 from cheongla_private.journal_notification_events where id=new.source_id)then return new;end if;
 insert into cheongla_private.journal_notification_receipts(event_id,recipient_id,recipient_name,recipient_role,received_at,read_at)
 select new.source_id,p.id,coalesce(nullif(p.full_name,''),'근무자'),p.role,new.created_at,new.read_at from public.cheongla_profiles p where p.id=new.recipient_id
 on conflict(event_id,recipient_id)do update set read_at=coalesce(cheongla_private.journal_notification_receipts.read_at,excluded.read_at);
 return new;
end;$$;
revoke all on function cheongla_private.capture_journal_alert_receipt()from public,anon,authenticated;
create or replace trigger journal_alert_receipt after insert or update of read_at on public.cheongla_notifications
 for each row when(new.source_kind='staff_journal')execute function cheongla_private.capture_journal_alert_receipt();
insert into cheongla_private.journal_notification_receipts(event_id,recipient_id,recipient_name,recipient_role,received_at,read_at)
select n.source_id,p.id,coalesce(nullif(p.full_name,''),'근무자'),p.role,n.created_at,n.read_at from public.cheongla_notifications n
 join cheongla_private.journal_notification_events e on e.id=n.source_id join public.cheongla_profiles p on p.id=n.recipient_id
 where n.source_kind='staff_journal'on conflict(event_id,recipient_id)do update set read_at=coalesce(cheongla_private.journal_notification_receipts.read_at,excluded.read_at);

create or replace function public.cheongla_my_journal_notifications(page_limit integer default 20)
returns jsonb language plpgsql stable set search_path='' as $$
declare items jsonb;unread bigint;
begin
 if not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 근무일지 알림을 확인할 수 있습니다.'using errcode='42501';end if;
 if page_limit is null or page_limit not between 1 and 200 then raise exception '조회 범위를 확인해 주세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(n)order by n.created_at desc,n.id desc),'[]')into items from(
  select *from public.cheongla_notifications where recipient_id=auth.uid()and source_kind='staff_journal'and archived_at is null and inbox_until>clock_timestamp()
  order by created_at desc,id desc limit page_limit)n;
 select count(*)into unread from public.cheongla_notifications where recipient_id=auth.uid()and source_kind='staff_journal'and read_at is null and archived_at is null and inbox_until>clock_timestamp();
 return jsonb_build_object('items',items,'unread_count',unread);
end;$$;
revoke all on function public.cheongla_my_journal_notifications(integer)from public,anon;
grant execute on function public.cheongla_my_journal_notifications(integer)to authenticated;

create or replace function public.cheongla_journal_alert_activity(page_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;
begin
 if not cheongla_private.can_use_staff_journal()or not cheongla_private.is_principal()then raise exception '원장만 근무일지 알림의 읽음 현황을 확인할 수 있습니다.'using errcode='42501';end if;
 if page_limit is null or page_limit not between 1 and 100 then raise exception '조회 범위를 확인해 주세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.opened_at desc,x.id desc),'[]')into items from(
  select e.id,e.work_on,e.action,e.opened_at,e.last_changed_at,e.change_count,p.full_name as author_name,
   (select count(*)from cheongla_private.journal_notification_receipts r where r.event_id=e.id)as recipient_count,
   (select count(*)from cheongla_private.journal_notification_receipts r where r.event_id=e.id and r.read_at is not null)as read_count,
   coalesce((select jsonb_agg(jsonb_build_object('name',r.recipient_name,'role',r.recipient_role,'received_at',r.received_at,'read_at',r.read_at,
    'currently_active',rp.approval_status='approved'and rp.membership_state='active'and rp.role in('owner','english_director','math_director','manager','korean_teacher'))
    order by(r.read_at is not null),r.recipient_name,r.recipient_id)
    from cheongla_private.journal_notification_receipts r join public.cheongla_profiles rp on rp.id=r.recipient_id where r.event_id=e.id),'[]')as recipients
  from cheongla_private.journal_notification_events e join public.cheongla_profiles p on p.id=e.actor_id
  order by e.opened_at desc,e.id desc limit page_limit)x;
 return jsonb_build_object('items',items);
end;$$;
revoke all on function public.cheongla_journal_alert_activity(integer)from public,anon;
grant execute on function public.cheongla_journal_alert_activity(integer)to authenticated;
notify pgrst,'reload schema';
