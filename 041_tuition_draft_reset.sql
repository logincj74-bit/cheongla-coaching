begin;
set local search_path='';
alter table public.cheongla_tuition_notices add column if not exists archived_at timestamptz,add column if not exists archived_by uuid;
alter table public.cheongla_tuition_notices drop constraint if exists tuition_archived_draft_only;
alter table public.cheongla_tuition_notices add constraint tuition_archived_draft_only check(archived_at is null or status='draft');
create table if not exists cheongla_private.tuition_draft_actions(id bigint generated always as identity primary key,notice_id uuid not null,actor_id uuid not null,action text not null check(action in('reset','restore')),snapshot jsonb not null,created_at timestamptz not null default clock_timestamp());
alter table cheongla_private.tuition_draft_actions enable row level security;
revoke all on cheongla_private.tuition_draft_actions from public,anon,authenticated;
create or replace function public.cheongla_reset_tuition_draft(target_notice uuid,expected_updated_at timestamptz,restore_draft boolean default false)returns uuid language plpgsql security definer set search_path=''as $$
declare n public.cheongla_tuition_notices%rowtype;
begin
 if not cheongla_private.can_manage_tuition()then raise exception '원장·실장만 학원비 초안을 초기화할 수 있습니다.'using errcode='42501';end if;
 if restore_draft is null then raise exception '처리 내용을 확인해 주세요.';end if;
 perform cheongla_private.lock_collection('tuition',target_notice);
 select * into n from public.cheongla_tuition_notices where id=target_notice;
 if not found then raise exception '초안을 찾을 수 없습니다. 목록을 새로고침해 주세요.';end if;
 if n.updated_at is distinct from expected_updated_at then raise exception '안내가 변경되었습니다. 새로고침 후 다시 처리해 주세요.';end if;
 if n.status<>'draft'then raise exception '게시된 안내는 먼저 게시 취소한 뒤 초기화해 주세요.';end if;
 if exists(select 1 from cheongla_private.fee_payments p where p.notice_kind='tuition'and p.notice_id=n.id)
 or exists(select 1 from cheongla_private.fee_deposit_reports r where r.fee_kind='tuition'and r.notice_id=n.id)
 or exists(select 1 from cheongla_private.fee_payment_events e where e.fee_kind='tuition'and e.notice_id=n.id)then raise exception '입금 알림이나 수납 이력이 있는 안내는 초기화할 수 없습니다.';end if;
 if restore_draft and n.archived_at is null then raise exception '이미 복구되었거나 새 초안을 작성한 안내입니다.';end if;
 if not restore_draft and n.archived_at is not null then raise exception '이미 초기화한 초안입니다.';end if;
 insert into cheongla_private.tuition_draft_actions(notice_id,actor_id,action,snapshot)values(n.id,auth.uid(),case when restore_draft then 'restore'else 'reset'end,to_jsonb(n));
 update public.cheongla_tuition_notices set archived_at=case when restore_draft then null else clock_timestamp()end,archived_by=case when restore_draft then null else auth.uid()end,updated_at=clock_timestamp()where id=n.id;
 return n.id;
exception when unique_violation then raise exception '같은 스쿨 시즌 예약금이 다른 안내에 적용되어 복구할 수 없습니다. 다른 안내를 먼저 확인해 주세요.';
end;$$;
revoke all on function public.cheongla_reset_tuition_draft(uuid,timestamptz,boolean)from public,anon,authenticated;
grant execute on function public.cheongla_reset_tuition_draft(uuid,timestamptz,boolean)to authenticated;
-- Reuse a reset draft when the manager creates a fresh notice for that student/month.
-- Patch only the version that owns the calculation; v2 can be a compatibility wrapper after 040.
do $patch$
declare f record;source text;patched text;patched_count integer:=0;view_source text;
begin
 for f in select p.oid from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public'and p.proname in('cheongla_save_tuition_notice_v2','cheongla_save_tuition_notice_v3')and p.prosrc like '%old_notice.updated_at%'loop
 source:=pg_get_functiondef(f.oid);
 if source like '%old_notice.archived_at%'then patched_count:=patched_count+1;continue;end if;
 patched:=replace(source,'if old_notice.updated_at is distinct from expected_updated_at then',E'if old_notice.archived_at is not null and notice_action<>''draft''then raise exception ''초기화한 안내입니다. 새 초안을 저장하거나 복구해 주세요.'';end if;\n if old_notice.updated_at is distinct from expected_updated_at and not(old_notice.archived_at is not null and expected_updated_at is null and notice_action=''draft'')then');
 patched:=replace(patched,'t.deposit_credit>0 and t.id','t.deposit_credit>0 and t.archived_at is null and t.id');
 patched:=replace(patched,'do update set student_name=excluded.student_name,','do update set archived_at=null,archived_by=null,student_name=excluded.student_name,');
 if patched=source or patched not like '%do update set archived_at=null%'then raise exception '학원비 계산 함수 버전을 확인해 주세요. 초기화 설정은 적용되지 않았습니다.';end if;
 execute patched;patched_count:=patched_count+1;
 end loop;
 if patched_count=0 then raise exception '학원비 계산 함수를 먼저 설치해 주세요.';end if;
 view_source:=pg_get_viewdef('cheongla_private.collection_notices'::regclass,true);
 if view_source not like '%t.archived_at%'then
  patched:=replace(view_source,'FROM public.cheongla_tuition_notices t','FROM public.cheongla_tuition_notices t WHERE t.archived_at IS NULL');
  if patched=view_source then raise exception '납부 목록 뷰 버전을 확인해 주세요.';end if;
  execute 'create or replace view cheongla_private.collection_notices as '||patched;
 end if;
end;$patch$;
do $$begin if exists(select 1 from pg_attribute where attrelid='public.cheongla_tuition_notices'::regclass and attname='deposit_credit'and not attisdropped)then execute 'drop index if exists public.tuition_deposit_once_per_season';execute 'create unique index tuition_deposit_once_per_season on public.cheongla_tuition_notices(student_id,program,deposit_season)where deposit_credit>0 and archived_at is null';end if;end;$$;
notify pgrst,'reload schema';
commit;
