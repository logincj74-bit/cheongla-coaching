begin;
alter table public.cheongla_notices add column channel text not null default 'director' check(channel in ('director','desk'));
update public.cheongla_notices n set channel='desk' from public.cheongla_profiles p where n.created_by=p.id and p.role='manager';
create index cheongla_notice_channel_order on public.cheongla_notices(channel,audience,pinned desc,created_at desc);
create or replace function cheongla_private.can_manage_notice_channel(target_channel text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved' and membership_state='active' and ((target_channel='director' and role in ('owner','english_director','math_director')) or (target_channel='desk' and role in ('owner','english_director','math_director','manager'))));
$$;
revoke all on function cheongla_private.can_manage_notice_channel(text) from public,anon,authenticated;
grant execute on function cheongla_private.can_manage_notice_channel(text) to authenticated;
-- Column-level grants also prevent changing the channel of an existing notice.
revoke insert,update on public.cheongla_notices from authenticated;
grant insert(title,body,audience,pinned,created_by,channel) on public.cheongla_notices to authenticated;
grant update(title,body,audience,pinned) on public.cheongla_notices to authenticated;
drop policy if exists cheongla_notice_create on public.cheongla_notices;
create policy cheongla_notice_create on public.cheongla_notices for insert to authenticated with check(cheongla_private.can_manage_notice_channel(channel) and created_by=(select auth.uid()));
drop policy if exists cheongla_notice_edit on public.cheongla_notices;
create policy cheongla_notice_edit on public.cheongla_notices for update to authenticated using(cheongla_private.can_manage_notice_channel(channel)) with check(cheongla_private.can_manage_notice_channel(channel));
drop policy if exists cheongla_notice_delete on public.cheongla_notices;
create policy cheongla_notice_delete on public.cheongla_notices for delete to authenticated using(cheongla_private.can_manage_notice_channel(channel));
-- Replace only the notice trigger, preserving notifications for every other feature.
drop trigger if exists cheongla_notify_event on public.cheongla_notices;
create or replace function cheongla_private.notify_channel_notice() returns trigger language plpgsql security definer set search_path='' as $$
declare people uuid[];destination text;label text;
begin
 if tg_op='UPDATE' and (new.title,new.body,new.audience,new.channel) is not distinct from (old.title,old.body,old.audience,old.channel) then return new;end if;
 select array_agg(id) into people from public.cheongla_profiles where new.audience='all' or role=new.audience or role in ('owner','english_director','math_director','korean_teacher','manager');
 destination:=case when new.channel='desk' then 'desk_notice_'||new.audience else new.audience end;
 label:=case when new.channel='desk' then '실장 업무 공지' else '원장 공지' end||' · '||case new.audience when 'student' then '재원생' when 'parent' then '학부모' else '전체' end;
 perform cheongla_private.send_notification(people,'notice',new.id,null,label,destination,'notice:'||new.id::text||':'||new.updated_at::text);
 return new;
end;$$;
create trigger cheongla_notify_event after insert or update on public.cheongla_notices for each row execute function cheongla_private.notify_channel_notice();
-- Fix destinations of earlier notifications to match the preserved notice category.
update public.cheongla_notifications a set route=case when n.channel='desk' then 'desk_notice_'||n.audience else n.audience end from public.cheongla_notices n where a.source_kind='notice' and a.source_id=n.id;
notify pgrst,'reload schema';
commit;
