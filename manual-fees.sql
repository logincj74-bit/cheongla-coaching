create table public.cheongla_manual_fee_settings(singleton boolean primary key default true check(singleton),meal_price integer not null default 7500 check(meal_price between 0 and 1000000),updated_at timestamptz not null default clock_timestamp());
insert into public.cheongla_manual_fee_settings(singleton)values(true);
alter table public.cheongla_manual_fee_settings enable row level security;
create policy manual_settings_read on public.cheongla_manual_fee_settings for select to authenticated using(cheongla_private.can_manage_tuition());
grant select on public.cheongla_manual_fee_settings to authenticated;
create table public.cheongla_manual_fee_notices(id uuid primary key default gen_random_uuid(),kind text not null check(kind in('exam','meal')),student_id uuid not null references public.cheongla_profiles(id),student_name text not null default '',month date not null,title text not null check(length(title) between 1 and 200),exam_on date,due_on date not null,lunch integer not null default 0 check(lunch between 0 and 1000),dinner integer not null default 0 check(dinner between 0 and 1000),unit_price integer not null default 7500 check(unit_price between 0 and 1000000),adjustment integer not null default 0 check(abs(adjustment)<=10000000),amount integer not null check(amount between 0 and 10000000),note text not null default '' check(length(note)<=2000),status text not null default 'draft' check(status in('draft','published')),deleted_at timestamptz,updated_at timestamptz not null default clock_timestamp());
alter table public.cheongla_manual_fee_notices enable row level security;
create policy manual_fee_read on public.cheongla_manual_fee_notices for select to authenticated using(cheongla_private.can_use_member_services() and (cheongla_private.can_manage_tuition() or (status='published' and deleted_at is null and cheongla_private.can_read_tuition(student_id))));
grant select on public.cheongla_manual_fee_notices to authenticated;
create table cheongla_private.manual_fee_audit(id bigint generated always as identity primary key,notice_id uuid,actor uuid,action text,created_at timestamptz default clock_timestamp(),snapshot jsonb);
alter table cheongla_private.manual_fee_audit enable row level security;
revoke all on cheongla_private.manual_fee_audit from public,anon,authenticated;
create function public.cheongla_manual_fee_action(action text,payload jsonb)returns jsonb language plpgsql security definer set search_path='' as $$
declare n public.cheongla_manual_fee_notices%rowtype;v uuid;result jsonb;total integer;
begin
if not cheongla_private.can_manage_tuition()then raise insufficient_privilege;end if;
if action='price'then
 update public.cheongla_manual_fee_settings set meal_price=(payload->>'price')::integer,updated_at=clock_timestamp()where singleton and updated_at=(payload->>'version')::timestamptz returning to_jsonb(cheongla_manual_fee_settings.*) into result;
 if result is null then raise exception '단가가 변경되었습니다. 새로고침해 주세요.';end if;return result;
end if;
v:=nullif(payload->>'id','')::uuid;
if v is not null then
 select * into n from public.cheongla_manual_fee_notices where id=v for update;
 if not found or n.updated_at is distinct from (payload->>'version')::timestamptz then raise exception '안내가 변경되었습니다. 새로고침해 주세요.';end if;
end if;
if action='save'then
 if n.deleted_at is not null then raise exception '먼저 휴지통에서 복구해 주세요.';end if;
 if not exists(select 1 from public.cheongla_profiles where id=(payload->>'student_id')::uuid and role='student' and approval_status='approved' and membership_state='active')then raise exception '승인된 재원생을 선택해 주세요.';end if;
 total:=case when payload->>'kind'='meal' then ((payload->>'lunch')::integer+(payload->>'dinner')::integer)*(payload->>'unit_price')::integer+(payload->>'adjustment')::integer else (payload->>'amount')::integer end;
 insert into public.cheongla_manual_fee_notices(id,kind,student_name,student_id,month,title,exam_on,due_on,lunch,dinner,unit_price,adjustment,amount,note)
 values(coalesce(v,gen_random_uuid()),payload->>'kind',(select full_name from public.cheongla_profiles where id=(payload->>'student_id')::uuid),(payload->>'student_id')::uuid,(payload->>'month')::date,payload->>'title',nullif(payload->>'exam_on','')::date,(payload->>'due_on')::date,coalesce((payload->>'lunch')::integer,0),coalesce((payload->>'dinner')::integer,0),coalesce((payload->>'unit_price')::integer,7500),coalesce((payload->>'adjustment')::integer,0),total,coalesce(payload->>'note',''))
 on conflict(id)do update set student_name=excluded.student_name,student_id=excluded.student_id,month=excluded.month,title=excluded.title,exam_on=excluded.exam_on,due_on=excluded.due_on,lunch=excluded.lunch,dinner=excluded.dinner,unit_price=excluded.unit_price,adjustment=excluded.adjustment,amount=excluded.amount,note=excluded.note,status='draft',updated_at=clock_timestamp()returning id into v;
else
 if v is null or action is null or action not in('publish','withdraw','trash','restore','purge')then raise exception '처리 항목을 확인해 주세요.';end if;
 if action in('publish','withdraw','trash') and n.deleted_at is not null then raise exception '휴지통 항목입니다.';end if;
 if action in('restore','purge') and n.deleted_at is null then raise exception '휴지통에서 처리해 주세요.';end if;
 if action='purge'then delete from public.cheongla_manual_fee_notices where id=v;
 else update public.cheongla_manual_fee_notices set status=case when action='publish'then 'published'else 'draft'end,deleted_at=case when action='trash'then clock_timestamp()else null end,updated_at=clock_timestamp()where id=v;end if;
end if;
insert into cheongla_private.manual_fee_audit(notice_id,actor,action,snapshot)values(v,auth.uid(),action,case when action='purge'then '{}'::jsonb else to_jsonb(n)end);
if action='purge'then update cheongla_private.manual_fee_audit set snapshot='{}'::jsonb where notice_id=v;end if;
return jsonb_build_object('id',v);
end;$$;
revoke all on function public.cheongla_manual_fee_action(text,jsonb)from public,anon;
grant execute on function public.cheongla_manual_fee_action(text,jsonb)to authenticated;
create function public.cheongla_manual_fee_recipients(target_notice uuid,version timestamptz) returns table(parent_id uuid,parent_name text,phone text)language plpgsql security definer set search_path='' as $$
declare n public.cheongla_manual_fee_notices%rowtype;
begin
if not cheongla_private.can_manage_tuition()then raise insufficient_privilege;end if;
select * into n from public.cheongla_manual_fee_notices where id=target_notice;
if not found or n.status<>'published' or n.deleted_at is not null or n.updated_at is distinct from version then raise exception '최신 게시 안내를 확인해 주세요.';end if;
return query select p.id,p.full_name::text,c.phone from public.cheongla_parent_students l join public.cheongla_profiles p on p.id=l.parent_id left join cheongla_private.member_contacts c on c.user_id=p.id where l.student_id=n.student_id and p.role='parent'and p.approval_status='approved'and p.membership_state='active'order by p.full_name;
end;$$;
revoke all on function public.cheongla_manual_fee_recipients(uuid,timestamptz)from public,anon;
grant execute on function public.cheongla_manual_fee_recipients(uuid,timestamptz)to authenticated;
revoke all on public.cheongla_manual_fee_notices,public.cheongla_manual_fee_settings from anon,authenticated;
grant select on public.cheongla_manual_fee_notices,public.cheongla_manual_fee_settings to authenticated;
