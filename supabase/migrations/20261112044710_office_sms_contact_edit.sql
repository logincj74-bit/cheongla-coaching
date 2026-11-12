create table cheongla_private.office_sms_contact_history(
 id uuid primary key default gen_random_uuid(),actor_id uuid not null,student_id uuid not null,
 member_id uuid not null,before_phone text,after_phone text not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table cheongla_private.office_sms_contact_history enable row level security;
revoke all on cheongla_private.office_sms_contact_history from public,anon,authenticated;
create function public.cheongla_office_sms_update_contact(target_student uuid,target_member uuid,new_phone text,expected_phone text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old_phone text;number text;old_expected text;had_contact boolean;
begin
 if not cheongla_private.can_manage_office_sms() then raise insufficient_privilege;end if;
 if not exists(select 1 from public.cheongla_profiles s where s.id=target_student and s.role='student'
  and s.approval_status='approved' and s.membership_state='active')
 or not exists(select 1 from public.cheongla_profiles r where r.id=target_member
  and r.approval_status='approved' and r.membership_state='active'
  and ((r.id=target_student and r.role='student') or (r.role='parent' and exists(
   select 1 from public.cheongla_parent_students l where l.student_id=target_student and l.parent_id=r.id)))) then
  raise exception '선택한 학생과 연결된 학생·학부모 연락처만 변경할 수 있습니다.' using errcode='42501';
 end if;
 number:=regexp_replace(coalesce(new_phone,''),'[^0-9]','','g');
 if number!~'^01[016789][0-9]{7,8}$' then raise exception '올바른 휴대전화번호를 입력해 주세요.' using errcode='22023';end if;
 old_expected:=nullif(regexp_replace(coalesce(expected_phone,''),'[^0-9]','','g'),'');
 perform pg_advisory_xact_lock(hashtextextended('office_sms_contact:'||target_member::text,0));
 select phone into old_phone from cheongla_private.member_contacts where user_id=target_member for update;
 had_contact:=found;
 if old_phone is distinct from old_expected then raise exception '연락처가 다른 곳에서 변경되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 if had_contact then
  update cheongla_private.member_contacts set phone=number,updated_at=clock_timestamp() where user_id=target_member;
 else
  insert into cheongla_private.member_contacts(user_id,phone)values(target_member,number)on conflict(user_id)do nothing;
  if not found then raise exception '연락처가 다른 곳에서 등록되었습니다. 새로고침 후 다시 확인해 주세요.';end if;
 end if;
 insert into cheongla_private.office_sms_contact_history(actor_id,student_id,member_id,before_phone,after_phone)
 values(auth.uid(),target_student,target_member,old_phone,number);
 return jsonb_build_object('member_id',target_member,'phone',number);
end;$$;
revoke all on function public.cheongla_office_sms_update_contact(uuid,uuid,text,text) from public,anon;
grant execute on function public.cheongla_office_sms_update_contact(uuid,uuid,text,text) to authenticated;
notify pgrst,'reload schema';
