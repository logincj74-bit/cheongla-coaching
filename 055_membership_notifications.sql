begin;
create table if not exists cheongla_private.membership_sms_settings(
 singleton boolean primary key default true check(singleton),enabled boolean not null default false,
 principal_receiver text check(principal_receiver~'^01[016789][0-9]{7,8}$'),daily_limit integer not null default 50 check(daily_limit between 1 and 500),
 webhook_secret text not null default encode(extensions.gen_random_bytes(32),'hex')
);
insert into cheongla_private.membership_sms_settings(singleton)values(true)on conflict do nothing;
revoke all on cheongla_private.membership_sms_settings from public,anon,authenticated;
create table if not exists cheongla_private.membership_sms_jobs(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in('request','approved')),member_id uuid not null,
 version text not null,to_phone text not null,state text not null default 'pending'check(state in('pending','processing','accepted','failed','unknown','cancelled')),
 claim_token uuid,provider_id text,created_at timestamptz not null default clock_timestamp(),claimed_at timestamptz,finished_at timestamptz,
 unique(kind,member_id,version)
);
revoke all on cheongla_private.membership_sms_jobs from public,anon,authenticated;
alter table cheongla_private.membership_sms_jobs enable row level security;
create or replace function cheongla_private.notify_membership_event()returns trigger language plpgsql security definer set search_path=''as $$
declare people uuid[];kind text;stamp text;phone text;s cheongla_private.membership_sms_settings%rowtype;
begin
 if new.membership_state<>'active'then return new;end if;
 if tg_op='INSERT'and new.approval_status='pending'then
  kind:='request';stamp:=new.created_at::text;
  select array_agg(id)into people from public.cheongla_profiles where approval_status='approved'and membership_state='active'and role in('owner','english_director','math_director');
  perform cheongla_private.send_notification(people,'member_request',new.id,null,'새 가입신청이 접수되었습니다. 가입 및 이용 권한 관리에서 확인해 주세요.','account_approvalPanel','member-request:'||new.id::text);
 elsif tg_op='UPDATE'and new.approval_status='approved'and old.approval_status='pending'then
  kind:='approved';stamp:=new.membership_updated_at::text;
  perform cheongla_private.send_notification(array[new.id],'member_approved',new.id,null,'가입승인이 완료됐습니다. 청라앱을 이용하실 수 있습니다.','my_membership','member-approved:'||new.id::text||':'||stamp);
 else return new;end if;
 select *into s from cheongla_private.membership_sms_settings where singleton;
 if not s.enabled then return new;end if;
 if kind='request'then phone:=s.principal_receiver;else select c.phone into phone from cheongla_private.member_contacts c where c.user_id=new.id;end if;
 if phone is null then return new;end if;
 insert into cheongla_private.membership_sms_jobs(kind,member_id,version,to_phone)values(kind,new.id,stamp,phone)on conflict do nothing;
 return new;
end;$$;
revoke all on function cheongla_private.notify_membership_event()from public,anon,authenticated;
drop trigger if exists cheongla_membership_notifications on public.cheongla_profiles;
create trigger cheongla_membership_notifications after insert or update of approval_status on public.cheongla_profiles for each row execute function cheongla_private.notify_membership_event();
create or replace function public.cheongla_configure_membership_sms(receiver text,turn_on boolean)returns void language plpgsql security definer set search_path=''as $$
declare number text:=regexp_replace(coalesce(receiver,''),'[^0-9]','','g');begin
 if not cheongla_private.is_principal()then raise exception '원장만 알림 수신번호를 설정할 수 있습니다.'using errcode='42501';end if;
 if number!~'^01[016789][0-9]{7,8}$'or turn_on is null then raise exception '수신번호와 발송 여부를 확인해 주세요.';end if;
 update cheongla_private.membership_sms_settings set principal_receiver=number,enabled=turn_on where singleton;
end;$$;
revoke all on function public.cheongla_configure_membership_sms(text,boolean)from public,anon,authenticated;
grant execute on function public.cheongla_configure_membership_sms(text,boolean)to authenticated;
create or replace function public.cheongla_membership_sms_server_config()returns jsonb language sql security definer set search_path=''as $$select jsonb_build_object('enabled',enabled,'webhook_secret',webhook_secret)from cheongla_private.membership_sms_settings where singleton$$;
create or replace function public.cheongla_claim_membership_sms()returns jsonb language plpgsql security definer set search_path=''as $$
declare j record;s cheongla_private.membership_sms_settings%rowtype;batch jsonb:='[]';capacity integer;token uuid;current_phone text;
begin
 perform pg_advisory_xact_lock(7492053);
 select *into s from cheongla_private.membership_sms_settings where singleton;
 if not s.enabled then return batch;end if;
 -- An interrupted send may already have incurred a charge. Never resend blindly.
 update cheongla_private.membership_sms_jobs set state='unknown',finished_at=clock_timestamp()where state='processing'and claimed_at<clock_timestamp()-interval '5 minutes';
 select s.daily_limit-count(*)into capacity from cheongla_private.membership_sms_jobs where claimed_at>clock_timestamp()-interval '24 hours'and state in('processing','accepted','unknown','failed');
 if capacity<=0 then return batch;end if;
 for j in select *from cheongla_private.membership_sms_jobs where state='pending'order by created_at,id limit least(5,capacity)for update skip locked loop
  current_phone:=null;
  if j.created_at<clock_timestamp()-interval '24 hours'then update cheongla_private.membership_sms_jobs set state='cancelled'where id=j.id;continue;end if;
  if j.kind='request'then
   if exists(select 1 from public.cheongla_profiles where id=j.member_id and approval_status='pending'and membership_state='active')then current_phone:=s.principal_receiver;end if;
  else
   select c.phone into current_phone from cheongla_private.member_contacts c join public.cheongla_profiles p on p.id=c.user_id where p.id=j.member_id and p.approval_status='approved'and p.membership_state='active'and p.membership_updated_at::text=j.version;
  end if;
  if current_phone is distinct from j.to_phone then update cheongla_private.membership_sms_jobs set state='cancelled'where id=j.id;continue;end if;
  token:=gen_random_uuid();update cheongla_private.membership_sms_jobs set state='processing',claim_token=token,claimed_at=clock_timestamp()where id=j.id;
  batch:=batch||jsonb_build_array(jsonb_build_object('id',j.id,'token',token,'kind',j.kind,'to',j.to_phone));
 end loop;return batch;
end;$$;
create or replace function public.cheongla_finish_membership_sms(job uuid,token uuid,result text,message_id text default null)returns void language plpgsql security definer set search_path=''as $$begin
 if result not in('accepted','failed','unknown')or result is null then raise exception 'Invalid dispatch state';end if;
 update cheongla_private.membership_sms_jobs set state=result,provider_id=left(message_id,100),finished_at=clock_timestamp()where id=job and claim_token=token and state='processing';
end;$$;
revoke all on function public.cheongla_membership_sms_server_config(),public.cheongla_claim_membership_sms(),public.cheongla_finish_membership_sms(uuid,uuid,text,text)from public,anon,authenticated;
grant execute on function public.cheongla_membership_sms_server_config(),public.cheongla_claim_membership_sms(),public.cheongla_finish_membership_sms(uuid,uuid,text,text)to service_role;
create or replace function cheongla_private.wake_membership_sms()returns void language plpgsql security definer set search_path=''as $$declare s cheongla_private.membership_sms_settings%rowtype;begin
 select *into s from cheongla_private.membership_sms_settings where singleton;
 if not s.enabled or not exists(select 1 from cheongla_private.membership_sms_jobs where state='pending')then return;end if;
 perform net.http_post(url:='https://heghuzbppjzxixecuuwd.supabase.co/functions/v1/cheongla-membership-sms',body:='{}'::jsonb,headers:=jsonb_build_object('Content-Type','application/json','x-cheongla-webhook',s.webhook_secret),timeout_milliseconds:=10000);
 exception when others then raise warning '가입 문자 발송 대기열은 보관됩니다. 연결을 확인해 주세요.';end;$$;
revoke all on function cheongla_private.wake_membership_sms()from public,anon,authenticated;
select cron.schedule('cheongla-membership-sms','* * * * *','select cheongla_private.wake_membership_sms();');
create or replace function cheongla_private.can_read_notification(kind text,target uuid,student uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;q record;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved' and membership_state='active';
 if not found then return false;end if;
 if kind='member_request' then return cheongla_private.is_principal()and exists(select 1 from public.cheongla_profiles where id=target);end if;
 if kind='member_approved' then return target=me.id;end if;
 if kind='fee_collection' then return exists(select 1 from cheongla_private.collection_notices n where n.id=target and cheongla_private.can_read_collection(n.fee_kind,n.id));end if;
 if kind='contact_update' then return cheongla_private.can_manage_tuition();end if;
 if kind='meal_submission' then return cheongla_private.can_manage_meal_forms();end if;
 if kind='information' then return exists(select 1 from public.cheongla_information_posts where id=target and status='published' and deleted_at is null);end if;
 case kind
 when 'notice' then return exists(select 1 from public.cheongla_notices n where n.id=target and (n.audience='all' or n.audience=me.role or me.role in ('owner','english_director','math_director','korean_teacher','manager')));
 when 'question' then
  select student_id,subject into q from public.cheongla_questions where id=target;
  return found and cheongla_private.can_read_question(q.student_id,q.subject);
 when 'new_inquiry' then return cheongla_private.can_manage_consultations() and exists(select 1 from public.cheongla_new_inquiries where id=target);
 when 'board' then return cheongla_private.can_read_board_post(target);
 when 'tuition' then return exists(select 1 from public.cheongla_tuition_notices n where n.id=target and (cheongla_private.can_manage_tuition() or (n.status='published' and cheongla_private.is_parent_of(n.student_id))));
 when 'exam' then return exists(select 1 from public.cheongla_exams e where e.id=target and e.deleted_at is null and (cheongla_private.can_manage_exams() or (e.status in ('open','closed') and cheongla_private.can_view_exams())));
 when 'application' then return exists(select 1 from public.cheongla_exam_applications a where a.exam_id=target and a.student_id=student and (cheongla_private.can_manage_exams() or cheongla_private.is_parent_of(student) or me.id=student));
 when 'exam_fee' then return exists(select 1 from public.cheongla_exam_fee_notices n where n.id=target and (cheongla_private.can_manage_exams() or (n.status='published' and cheongla_private.can_read_exam_fee(n.exam_id,n.student_id))));
 when 'schedule' then return exists(select 1 from public.cheongla_schedule_events e where e.id=target and (cheongla_private.can_manage_schedule() or (e.status='published' and (e.audience='all' or e.audience=me.role))));
 else return false;
 end case;
end;$$;

create or replace function cheongla_private.membership_sms_insert_wake()returns trigger language plpgsql security definer set search_path=''as $$begin perform cheongla_private.wake_membership_sms();return null;end;$$;
revoke all on function cheongla_private.membership_sms_insert_wake()from public,anon,authenticated;
drop trigger if exists cheongla_sms_job_wake on cheongla_private.membership_sms_jobs;
create trigger cheongla_sms_job_wake after insert on cheongla_private.membership_sms_jobs for each statement execute function cheongla_private.membership_sms_insert_wake();
notify pgrst,'reload schema';
commit;
