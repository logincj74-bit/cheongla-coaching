begin;
create table if not exists cheongla_private.trash_action_history(
 id bigint generated always as identity primary key,source_event text not null unique,kind text not null check(kind in('tuition','meal')),
 source_id uuid not null,action text not null check(action in('reset','restore','delete','undelete','purge')),actor_id uuid not null,month date,created_at timestamptz not null
);
alter table cheongla_private.trash_action_history enable row level security;
revoke all on cheongla_private.trash_action_history from public,anon,authenticated;
insert into cheongla_private.trash_action_history(source_event,kind,source_id,action,actor_id,month,created_at)
select source_event,kind,source_id,action,actor_id,month,created_at from(
 select 'ta:'||a.id::text source_event,'tuition' kind,a.notice_id source_id,a.action,a.actor_id,coalesce((a.snapshot->>'billing_month')::date,n.billing_month) as month,a.created_at
 from cheongla_private.tuition_draft_actions a left join public.cheongla_tuition_notices n on n.id=a.notice_id
 union all select 'md:'||t.id::text,'meal',t.id,'delete',t.deleted_by,t.month,t.deleted_at from cheongla_private.meal_submission_trash t
 union all select 'mr:'||t.id::text,'meal',t.id,'restore',t.restored_by,t.month,t.restored_at from cheongla_private.meal_submission_trash t where t.restored_at is not null
 union all select 'p:'||p.id::text,p.kind,p.source_id,'purge',p.actor_id,null::date,p.created_at from cheongla_private.trash_purge_events p
)x order by created_at,source_event on conflict(source_event)do nothing;
create or replace function cheongla_private.record_trash_action()returns trigger language plpgsql security definer set search_path=''as $$
declare label text;k text;sid uuid;act text;actor uuid;m date;stamp timestamptz;
begin
 if tg_table_name='tuition_draft_actions'then label:='ta:'||new.id::text;k:='tuition';sid:=new.notice_id;act:=new.action;actor:=new.actor_id;m:=(new.snapshot->>'billing_month')::date;stamp:=new.created_at;
 elsif tg_table_name='meal_submission_trash'then k:='meal';sid:=new.id;m:=new.month;
  if tg_op='INSERT'then label:='md:'||new.id::text;act:='delete';actor:=new.deleted_by;stamp:=new.deleted_at;
  elsif new.restored_at is not null and old.restored_at is null then label:='mr:'||new.id::text;act:='restore';actor:=new.restored_by;stamp:=new.restored_at;
  else return new;end if;
 else label:='p:'||new.id::text;k:=new.kind;sid:=new.source_id;act:='purge';actor:=new.actor_id;stamp:=new.created_at;
  if k='tuition'then select billing_month into m from public.cheongla_tuition_notices where id=sid;
  else select month into m from cheongla_private.meal_submission_trash where id=sid;end if;
 end if;
 insert into cheongla_private.trash_action_history(source_event,kind,source_id,action,actor_id,month,created_at)values(label,k,sid,act,actor,m,stamp)on conflict(source_event)do nothing;
 return new;
end;$$;
revoke all on function cheongla_private.record_trash_action()from public,anon,authenticated;
drop trigger if exists tuition_trash_history on cheongla_private.tuition_draft_actions;
create trigger tuition_trash_history after insert on cheongla_private.tuition_draft_actions for each row execute function cheongla_private.record_trash_action();
drop trigger if exists meal_trash_history on cheongla_private.meal_submission_trash;
create trigger meal_trash_history after insert or update on cheongla_private.meal_submission_trash for each row execute function cheongla_private.record_trash_action();
drop trigger if exists purge_trash_history on cheongla_private.trash_purge_events;
create trigger purge_trash_history after insert on cheongla_private.trash_purge_events for each row execute function cheongla_private.record_trash_action();
create or replace function public.cheongla_trash_history(target_kind text)
returns jsonb language plpgsql stable security definer set search_path=''as $$
begin
 if not cheongla_private.is_principal()then raise exception '원장만 삭제 처리 이력을 확인할 수 있습니다.'using errcode='42501';end if;
 if target_kind is null or target_kind not in('tuition','meal')then raise exception '이력 종류를 확인해 주세요.';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)order by x.created_at desc,x.id desc)from(
 select h.id,h.kind,h.source_id,h.action,h.month,h.created_at,coalesce(p.full_name,'삭제된 계정')actor_name
 from cheongla_private.trash_action_history h left join public.cheongla_profiles p on p.id=h.actor_id
 where h.kind=target_kind order by h.created_at desc,h.id desc limit 100)x),'[]'::jsonb);
end;$$;
create or replace function public.cheongla_empty_trash(target_kind text,target_month date,expected_items jsonb)
returns integer language plpgsql security definer set search_path=''as $$
declare x jsonb;live_ids uuid[];wanted_ids uuid[];total integer;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 휴지통 전체를 비울 수 있습니다.'using errcode='42501';end if;
 if target_kind is null or target_kind not in('tuition','meal')or target_month is null or extract(day from target_month)<>1 or expected_items is null or jsonb_typeof(expected_items)<>'array'then raise exception '삭제할 월과 목록을 확인해 주세요.';end if;
 total:=jsonb_array_length(expected_items);
 if total<1 or total>1000 then raise exception '휴지통에 있는 1~1,000건을 확인해 주세요.';end if;
 select array_agg((v->>'id')::uuid order by(v->>'id')::uuid)into wanted_ids from jsonb_array_elements(expected_items)v;
 if array_position(wanted_ids,null)is not null or(select count(distinct i)from unnest(wanted_ids)i)<>total then raise exception '삭제 목록을 새로고침해 주세요.';end if;
 if target_kind='tuition'then select array_agg(id order by id)into live_ids from public.cheongla_tuition_notices where billing_month=target_month and deleted_at is not null;
 else select array_agg(id order by id)into live_ids from cheongla_private.meal_submission_trash where month=target_month and restored_at is null;end if;
 if live_ids is distinct from wanted_ids then raise exception '휴지통 목록이 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 for x in select value from jsonb_array_elements(expected_items)order by(value->>'id')::uuid loop
  if target_kind='tuition'then perform public.cheongla_purge_tuition_draft((x->>'id')::uuid,(x->>'version')::timestamptz);
  else perform public.cheongla_purge_meal_submission((x->>'id')::uuid,(x->>'version')::timestamptz);end if;
 end loop;
 return total;
end;$$;
revoke all on function public.cheongla_trash_history(text),public.cheongla_empty_trash(text,date,jsonb)from public,anon,authenticated;
grant execute on function public.cheongla_trash_history(text),public.cheongla_empty_trash(text,date,jsonb)to authenticated;
notify pgrst,'reload schema';
commit;
