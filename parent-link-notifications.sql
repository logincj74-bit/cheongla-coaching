CREATE OR REPLACE FUNCTION cheongla_private.can_read_notification(kind text, target uuid, student uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me public.cheongla_profiles%rowtype;q record;
begin
 select * into me from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved' and membership_state='active';
 if not found then return false;end if;
 if kind='member_request' then return cheongla_private.is_principal()and exists(select 1 from public.cheongla_profiles where id=target);end if;
 if kind='parent_link' then return target=me.id and me.role='parent' and exists(select 1 from public.cheongla_parent_students l join public.cheongla_profiles s on s.id=l.student_id where l.parent_id=me.id and l.student_id=student and s.role='student' and s.approval_status='approved' and s.membership_state='active');end if;
 if kind='member_approved' then return target=me.id;end if;
 if kind='fee_collection' then return exists(select 1 from cheongla_private.collection_notices n where n.id=target and cheongla_private.can_read_collection(n.fee_kind,n.id));end if;
 if kind='contact_update' then return cheongla_private.can_manage_tuition();end if;
 if kind='meal_submission' then return cheongla_private.can_manage_meal_forms();end if;
 if kind='daily_word' then return exists(select 1 from public.cheongla_daily_words where id=target and status='published' and message_on <= (now() at time zone 'Asia/Seoul')::date);end if;
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
end;$function$
;
create or replace function cheongla_private.notify_parent_link()
returns trigger language plpgsql security definer set search_path='' as $$
declare child_name text;
begin
 select full_name into child_name from public.cheongla_profiles where id=new.student_id and role='student' and approval_status='approved' and membership_state='active';
 if not found then return new;end if;
 perform cheongla_private.send_notification(array[new.parent_id],'parent_link',new.parent_id,new.student_id,
 coalesce(child_name,'자녀')||' 학생과 자녀 연결이 완료되었습니다. 연결된 자녀에서 확인해 주세요.',
 'account_childrenPanel','parent-link:'||new.parent_id::text||':'||new.student_id::text||':'||new.created_at::text);
 return new;
end;$$;
revoke all on function cheongla_private.notify_parent_link() from public,anon,authenticated;
create trigger cheongla_parent_link_notification after insert on public.cheongla_parent_students for each row execute function cheongla_private.notify_parent_link();

