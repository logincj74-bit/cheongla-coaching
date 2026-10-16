begin;
alter table public.cheongla_exams add column if not exists exam_kind text not null default 'other' check(exam_kind in ('daesung','survival','kice_june','kice_september','other'));
update public.cheongla_exams set exam_kind=case
 when title~'(평가원|모의평가)' and title~'6월' then 'kice_june'
 when title~'(평가원|모의평가)' and title~'9월' then 'kice_september'
 when title~'(시대인재|서프|서바이벌)' then 'survival'
 when title~'(대성|프리미엄|더 프)' then 'daesung' else 'other' end where exam_kind='other';
create or replace function public.cheongla_save_exam_v2(target_exam uuid,exam_title text,exam_date date,application_deadline timestamptz,exam_body text,exam_status text,exam_kind text,expected_updated_at timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if exam_kind is null or exam_kind not in('daesung','survival','kice_june','kice_september','other') then raise exception '모의고사 구분을 선택해 주세요.';end if;
 result:=public.cheongla_save_exam(target_exam,exam_title,exam_date,application_deadline,exam_body,exam_status,expected_updated_at);
 update public.cheongla_exams set exam_kind=cheongla_save_exam_v2.exam_kind where id=result;
 return result;
end;$$;
revoke all on function public.cheongla_save_exam_v2(uuid,text,date,timestamptz,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_save_exam_v2(uuid,text,date,timestamptz,text,text,text,timestamptz) to authenticated;
-- Token issuance and refresh must fail for a withdrawn member. Enable this function
-- as the project's Custom Access Token hook after installation, without replacing another hook.
create or replace function public.cheongla_account_access_hook(event jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if exists(select 1 from public.cheongla_profiles where id=(event->>'user_id')::uuid and membership_state='withdrawn') then
  return jsonb_build_object('error',jsonb_build_object('http_code',403,'message','CHEONGLA_WITHDRAWN: 탈퇴한 계정은 로그인할 수 없습니다.'));
 end if;
 return jsonb_build_object('claims',event->'claims');
end;$$;
revoke all on function public.cheongla_account_access_hook(jsonb) from public,anon,authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.cheongla_account_access_hook(jsonb) to supabase_auth_admin;
notify pgrst,'reload schema';
commit;
