create or replace function cheongla_private.guard_phone_login_identity()
returns trigger language plpgsql security definer set search_path='' as $$
declare number text;canonical text;
begin
 if lower(coalesce(new.email,'')) like '%@phone.cheongla.invalid' then
  if tg_op='UPDATE' and new.email is distinct from old.email then raise exception '로그인 번호 변경은 학원에 문의해 주세요.'using errcode='22023';end if;
  number:=regexp_replace(coalesce(new.raw_user_meta_data->>'contact_phone',''),'[^0-9]','','g');
  canonical:=encode(extensions.digest(number,'sha256'),'hex')||'@phone.cheongla.invalid';
  if number!~'^01[016789][0-9]{7,8}$'or lower(new.email)<>canonical then raise exception '휴대전화번호 가입 정보를 확인해 주세요.'using errcode='22023';end if;
  new.email:=canonical;
  new.raw_app_meta_data:=coalesce(new.raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('login_method','phone');
 elsif tg_op='INSERT' then
  new.raw_app_meta_data:=coalesce(new.raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('login_method','email');
 end if;
 return new;
end;$$;
revoke all on function cheongla_private.guard_phone_login_identity()from public,anon,authenticated;
create trigger cheongla_phone_login_identity before insert or update of email on auth.users for each row execute function cheongla_private.guard_phone_login_identity();

create or replace function public.cheongla_meal_submission_message_recipients(target_month date,target_student uuid,expected_updated_at timestamptz)
returns table(parent_id uuid,parent_name text,phone text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_meal_forms()then raise exception '담당 관리자만 신청 접수 문자를 준비할 수 있습니다.'using errcode='42501';end if;
 if not exists(select 1 from public.cheongla_meal_submissions s join public.cheongla_profiles p on p.id=s.student_id where s.month=target_month and s.student_id=target_student and s.archived_at is null and s.updated_at=expected_updated_at and p.role='student'and p.approval_status='approved'and p.membership_state='active')then raise exception '신청서가 변경되었거나 삭제되었습니다. 새로고침 후 다시 준비해 주세요.';end if;
 return query select p.id,p.full_name::text,c.phone from public.cheongla_parent_students l join public.cheongla_profiles p on p.id=l.parent_id left join cheongla_private.member_contacts c on c.user_id=p.id where l.student_id=target_student and p.role='parent'and p.approval_status='approved'and p.membership_state='active'order by p.full_name,p.id;
end;$$;
revoke all on function public.cheongla_meal_submission_message_recipients(date,uuid,timestamptz)from public,anon,authenticated;
grant execute on function public.cheongla_meal_submission_message_recipients(date,uuid,timestamptz)to authenticated;

