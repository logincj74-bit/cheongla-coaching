-- Per-work-item attention rules; unread priority applies before pagination.
alter table cheongla_private.journal_handovers add column handover_kind text not null default 'general' check(handover_kind in('daily','general','long'));

create or replace function public.cheongla_journal_handovers(work_date date,include_completed boolean default false,page_offset integer default 0,page_limit integer default 50)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare items jsonb;total integer;unread_total integer;today date:=(now()at time zone'Asia/Seoul')::date;
begin
 if auth.uid()is null or not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 인계를 확인할 수 있습니다.'using errcode='42501';end if;
 if work_date is null or include_completed is null or page_offset is null or page_offset<0 or page_limit is null or page_limit not between 1 and 100 then raise exception '조회 범위를 확인해 주세요.';end if;
 select count(*),count(*)filter(where not include_completed and not exists(select 1 from cheongla_private.journal_handover_checks c where c.handover_id=h.id and c.staff_id=auth.uid()))into total,unread_total
 from cheongla_private.journal_handovers h join cheongla_private.daily_journals d on d.work_on=h.source_date
 where h.source_date<=work_date and d.archived_at is null and d.purged_at is null and(h.completed_at is not null)=include_completed;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.is_unread desc,x.attention_level desc,x.sort_at,x.id),'[]')into items from(
  select h.*,
  not include_completed and not exists(select 1 from cheongla_private.journal_handover_checks c where c.handover_id=h.id and c.staff_id=auth.uid())as is_unread,
  greatest(0,today-h.source_date)as days_elapsed,
  case when include_completed then 0
   when today-h.source_date>=case h.handover_kind when 'daily'then 2 when 'long'then 14 else 4 end then 2
   when today-h.source_date>=case h.handover_kind when 'daily'then 1 when 'long'then 7 else 2 end then 1 else 0 end as attention_level,
  case when include_completed then -extract(epoch from h.completed_at)else extract(epoch from h.source_date::timestamp)end as sort_at,
  coalesce(p.full_name,'이전 근무자')as author_name,cp.full_name as completed_name,
  strpos(d.fields->>h.source_field,h.excerpt)=0 as source_changed,
  (select count(*)from cheongla_private.journal_handover_notes n where n.handover_id=h.id)as note_count,
  coalesce((select jsonb_agg(jsonb_build_object('staff_id',c.staff_id,'name',s.full_name,'checked_at',c.checked_at)order by c.checked_at)from cheongla_private.journal_handover_checks c join public.cheongla_profiles s on s.id=c.staff_id where c.handover_id=h.id),'[]')as checks
  from cheongla_private.journal_handovers h join cheongla_private.daily_journals d on d.work_on=h.source_date left join public.cheongla_profiles p on p.id=h.created_by left join public.cheongla_profiles cp on cp.id=h.completed_by
  where h.source_date<=work_date and d.archived_at is null and d.purged_at is null and(h.completed_at is not null)=include_completed
  order by is_unread desc,attention_level desc,sort_at,h.id offset page_offset limit page_limit
 )x;
 return jsonb_build_object('items',items,'total',total,'unread_total',unread_total);
end;$$;

create or replace function public.cheongla_journal_handover_action(target_handover uuid,handover_action text,expected_revision bigint)returns jsonb language plpgsql security definer set search_path=''as $$
declare h cheongla_private.journal_handovers%rowtype;
begin
 if auth.uid()is null or not cheongla_private.can_use_staff_journal()then raise exception '승인된 근무자만 인계를 처리할 수 있습니다.'using errcode='42501';end if;
 -- All handover mutations lock the source first, matching archive/purge lock order.
 perform 1 from cheongla_private.daily_journals d where d.work_on=(select source_date from cheongla_private.journal_handovers where id=target_handover)and d.archived_at is null and d.purged_at is null for update;
 if not found then raise exception '원래 일지가 삭제되었거나 인계를 찾을 수 없습니다.';end if;
 select *into h from cheongla_private.journal_handovers where id=target_handover for update;
 if handover_action='check'then
  insert into cheongla_private.journal_handover_checks(handover_id,staff_id)values(h.id,auth.uid())on conflict(handover_id,staff_id)do update set checked_at=clock_timestamp();
 elsif handover_action in('kind:daily','kind:general','kind:long')then
  if h.revision is distinct from expected_revision then raise exception '다른 근무자가 처리했습니다. 새로고침 후 확인해 주세요.'using errcode='40001';end if;
  if h.completed_at is not null then raise exception '완료한 인계의 업무 구분은 변경할 수 없습니다.';end if;
  update cheongla_private.journal_handovers set handover_kind=substring(handover_action from 6),revision=revision+1 where id=h.id returning *into h;
 elsif handover_action in('complete','reopen')then
  if h.revision is distinct from expected_revision then raise exception '다른 근무자가 처리했습니다. 새로고침 후 확인해 주세요.'using errcode='40001';end if;
  if(handover_action='complete'and h.completed_at is not null)or(handover_action='reopen'and h.completed_at is null)then return to_jsonb(h);end if;
  update cheongla_private.journal_handovers set completed_at=case when handover_action='complete'then clock_timestamp()end,completed_by=case when handover_action='complete'then auth.uid()end,revision=revision+1 where id=h.id returning *into h;
 else raise exception '인계 처리 방법을 확인해 주세요.';end if;
 insert into cheongla_private.journal_handover_events(handover_id,actor_id,action)values(h.id,auth.uid(),handover_action);return to_jsonb(h);
end;$$;
