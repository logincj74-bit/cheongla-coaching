begin;
alter table public.cheongla_new_inquiries
 add column if not exists consultation_status text not null default 'waiting' check (consultation_status in ('waiting','consulted','enrolled')),
 add column if not exists status_updated_by uuid references public.cheongla_profiles(id),
 add column if not exists status_updated_at timestamptz;
create or replace function public.cheongla_list_new_inquiries(page_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean:=false;result jsonb;max_rows integer;
begin
 if auth.uid() is not null then manager:=cheongla_private.can_manage_consultations();end if;
 max_rows:=greatest(1,least(coalesce(page_limit,20),200));
 select coalesce(jsonb_agg(item order by created_at desc,id desc),'[]'::jsonb) into result
 from (select id,created_at,jsonb_build_object('id',id,'title',title,'body',body,'visibility',visibility,
 'applicant_role',applicant_role,'created_at',created_at,'updated_at',updated_at,'reply_body',reply_body,'replied_at',replied_at)
 ||case when manager then jsonb_build_object('contact_name',contact_name,'contact_phone',contact_phone,'consultation_status',consultation_status,'status_updated_at',status_updated_at) else '{}'::jsonb end as item
 from public.cheongla_new_inquiries where manager or visibility='public' order by created_at desc,id desc limit max_rows) p;
 return jsonb_build_object('items',result,'can_manage',manager);
end;$$;

create or replace function public.cheongla_set_new_inquiry_status(target_inquiry uuid,next_status text,expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare old_row public.cheongla_new_inquiries%rowtype;
begin
 if not cheongla_private.can_manage_consultations() then raise exception '영어원장·수학원장·실장만 상담 상태를 변경할 수 있습니다.' using errcode='42501';end if;
 if next_status is null or next_status not in ('waiting','consulted','enrolled') then raise exception '상담 상태를 확인해 주세요.';end if;
 select * into old_row from public.cheongla_new_inquiries where id=target_inquiry for update;
 if not found then raise exception '해당 문의가 없습니다.';end if;
 if old_row.updated_at is distinct from expected_updated_at then raise exception '문의가 변경되었습니다. 새로고침 후 다시 저장해 주세요.';end if;
 if old_row.consultation_status=next_status then return target_inquiry;end if;
 update public.cheongla_new_inquiries set consultation_status=next_status,status_updated_by=(select auth.uid()),status_updated_at=clock_timestamp(),updated_at=clock_timestamp() where id=target_inquiry;
 return target_inquiry;
end;$$;
revoke all on function public.cheongla_set_new_inquiry_status(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_set_new_inquiry_status(uuid,text,timestamptz) to authenticated;
create or replace function cheongla_private.can_read_notification(kind text,target uuid,student uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;q record;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved';
 if not found then return false;end if;
 case kind
 when 'notice' then return exists(select 1 from public.cheongla_notices n where n.id=target and (n.audience='all' or n.audience=me.role or me.role in ('owner','english_director','math_director','korean_teacher','manager')));
 when 'question' then
  select student_id,subject into q from public.cheongla_questions where id=target;
  return found and cheongla_private.can_read_question(q.student_id,q.subject);
 when 'new_inquiry' then return cheongla_private.can_manage_consultations() and exists(select 1 from public.cheongla_new_inquiries where id=target);
 when 'board' then return cheongla_private.can_read_board_post(target);
 when 'tuition' then return exists(select 1 from public.cheongla_tuition_notices n where n.id=target and (cheongla_private.can_manage_tuition() or (n.status='published' and cheongla_private.is_parent_of(n.student_id))));
 when 'exam' then return exists(select 1 from public.cheongla_exams e where e.id=target and (cheongla_private.can_manage_exams() or (e.status in ('open','closed') and cheongla_private.can_view_exams())));
 when 'application' then return exists(select 1 from public.cheongla_exam_applications a where a.exam_id=target and a.student_id=student and (cheongla_private.can_manage_exams() or cheongla_private.is_parent_of(student) or me.id=student));
 when 'exam_fee' then return exists(select 1 from public.cheongla_exam_fee_notices n where n.id=target and (cheongla_private.can_manage_exams() or (n.status='published' and cheongla_private.can_read_exam_fee(n.exam_id,n.student_id))));
 when 'schedule' then return exists(select 1 from public.cheongla_schedule_events e where e.id=target and (cheongla_private.can_manage_schedule() or (e.status='published' and (e.audience='all' or e.audience=me.role))));
 else return false;
 end case;
end;$$;
revoke all on function cheongla_private.can_read_notification(text,uuid,uuid) from public,anon,authenticated;
grant execute on function cheongla_private.can_read_notification(text,uuid,uuid) to authenticated;

create or replace function cheongla_private.notify_new_inquiry()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.cheongla_notifications(recipient_id,source_kind,source_id,title,route,event_key)
 select id,'new_inquiry',new.id,'새 신규 상담 문의가 접수되었습니다.','new_inquiry','new_inquiry:'||new.id::text
 from public.cheongla_profiles where approval_status='approved' and role in ('owner','english_director','math_director','manager')
 on conflict(recipient_id,event_key) do nothing;
 return new;
end;$$;
revoke all on function cheongla_private.notify_new_inquiry() from public,anon,authenticated;
drop trigger if exists cheongla_notify_new_inquiry on public.cheongla_new_inquiries;
create trigger cheongla_notify_new_inquiry after insert on public.cheongla_new_inquiries for each row execute function cheongla_private.notify_new_inquiry();
notify pgrst,'reload schema';
commit;
