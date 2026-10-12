begin;
create or replace function cheongla_private.can_use_schedule()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved');
$$;
create or replace function cheongla_private.can_manage_schedule()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and approval_status='approved' and (is_app_admin or role='manager'));
$$;
create or replace function cheongla_private.can_read_schedule(audience text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid())
 and approval_status='approved' and (audience='all' or audience=role));
$$;
revoke all on function cheongla_private.can_use_schedule(),cheongla_private.can_manage_schedule(),cheongla_private.can_read_schedule(text) from public,anon,authenticated;
grant execute on function cheongla_private.can_use_schedule(),cheongla_private.can_manage_schedule(),cheongla_private.can_read_schedule(text) to authenticated;
create table if not exists public.cheongla_schedule_events (
 id uuid primary key default gen_random_uuid(),
 title text not null check(length(btrim(title)) between 1 and 150),
 starts_on date not null,ends_on date not null,event_time time,
 kind text not null check(kind in ('exam','counseling','academy','holiday','other')),
 audience text not null default 'all' check(audience in ('all','student','parent')),
 body text not null default '' check(length(body)<=5000),
 status text not null default 'draft' check(status in ('draft','published')),
 updated_by uuid references public.cheongla_profiles(id),
 updated_at timestamptz not null default clock_timestamp(),check(ends_on>=starts_on)
);
create index if not exists cheongla_schedule_dates on public.cheongla_schedule_events(starts_on,ends_on);
alter table public.cheongla_schedule_events enable row level security;
revoke all on public.cheongla_schedule_events from anon,authenticated;
grant select on public.cheongla_schedule_events to authenticated;
drop policy if exists cheongla_schedule_read on public.cheongla_schedule_events;
create policy cheongla_schedule_read on public.cheongla_schedule_events for select to authenticated
 using ((select cheongla_private.can_manage_schedule())
 or (status='published' and (select cheongla_private.can_read_schedule(audience))));
create or replace function public.cheongla_schedule_month(target_month date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;exam_items jsonb;
begin
 if not cheongla_private.can_use_schedule() then raise exception '승인된 학원 계정으로 확인해 주세요.' using errcode='42501';end if;
 if target_month is null or extract(day from target_month)<>1 then raise exception '조회할 월을 확인해 주세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.starts_on,e.event_time,e.title,e.id),'[]'::jsonb)
 into result from public.cheongla_schedule_events e
 where e.starts_on<(target_month+interval '1 month')::date and e.ends_on>=target_month;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.exam_on,e.title,e.id),'[]'::jsonb) into exam_items
 from public.cheongla_exams e where
 (e.exam_on>=target_month and e.exam_on<(target_month+interval '1 month')::date)
 or (e.deadline>=(target_month::timestamp at time zone 'Asia/Seoul') and e.deadline<((target_month+interval '1 month')::timestamp at time zone 'Asia/Seoul'));
 return jsonb_build_object('events',result,'exams',exam_items);
end;$$;
create or replace function public.cheongla_save_schedule(
 target_event uuid,event_title text,start_date date,end_date date,start_time time,
 event_kind text,event_audience text,event_body text,event_status text,
 expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_stamp timestamptz;result_id uuid;
begin
 if not cheongla_private.can_manage_schedule() then raise exception '실장과 앱 관리자만 일정을 관리할 수 있습니다.' using errcode='42501';end if;
 if event_title is null or length(btrim(event_title)) not between 1 and 150 or start_date is null or end_date is null or end_date<start_date
 or event_kind is null or event_kind not in ('exam','counseling','academy','holiday','other')
 or event_audience is null or event_audience not in ('all','student','parent') or event_body is null or length(event_body)>5000
 or event_status is null or event_status not in ('draft','published') then raise exception '제목, 날짜, 공개 대상과 내용을 확인해 주세요.';end if;
 if target_event is not null then
  select updated_at into old_stamp from public.cheongla_schedule_events where id=target_event for update;
  if not found then raise exception '해당 일정이 없습니다.';end if;
 end if;
 if old_stamp is distinct from expected_updated_at then raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 저장해 주세요.';end if;
 if target_event is null then
  insert into public.cheongla_schedule_events(title,starts_on,ends_on,event_time,kind,audience,body,status,updated_by)
  values(btrim(event_title),start_date,end_date,start_time,event_kind,event_audience,event_body,event_status,(select auth.uid())) returning id into result_id;
 else
  update public.cheongla_schedule_events set title=btrim(event_title),starts_on=start_date,ends_on=end_date,event_time=start_time,
  kind=event_kind,audience=event_audience,body=event_body,status=event_status,updated_by=(select auth.uid()),updated_at=clock_timestamp()
  where id=target_event returning id into result_id;
 end if;
 return result_id;
end;$$;
create or replace function public.cheongla_delete_schedule(target_event uuid,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_stamp timestamptz;
begin
 if not cheongla_private.can_manage_schedule() then raise exception '실장과 앱 관리자만 일정을 삭제할 수 있습니다.' using errcode='42501';end if;
 select updated_at into old_stamp from public.cheongla_schedule_events where id=target_event for update;
 if not found then raise exception '해당 일정이 없습니다.';end if;
 if old_stamp is distinct from expected_updated_at then raise exception '다른 담당자가 수정했습니다. 새로고침 후 다시 확인해 주세요.';end if;
 delete from public.cheongla_schedule_events where id=target_event;return target_event;
end;$$;
revoke all on function public.cheongla_schedule_month(date),public.cheongla_save_schedule(uuid,text,date,date,time,text,text,text,text,timestamptz),public.cheongla_delete_schedule(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_schedule_month(date),public.cheongla_save_schedule(uuid,text,date,date,time,text,text,text,text,timestamptz),public.cheongla_delete_schedule(uuid,timestamptz) to authenticated;
notify pgrst,'reload schema';
commit;
