-- Roll the existing featured CSAT countdown forward and keep the daily editor open year-round.
update public.cheongla_home_features
set title = '2028학년도 수능까지', target_date = date '2027-11-18'
where kind = 'countdown' and archived_at is null and not hidden
  and featured and title = '2027학년도 수능까지' and target_date = date '2026-11-19';

alter table public.cheongla_daily_words
  drop constraint if exists cheongla_daily_words_message_on_check;

CREATE OR REPLACE FUNCTION public.cheongla_save_daily_word(target_day date, post_title text, post_body text, post_status text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare old_row public.cheongla_daily_words%rowtype; saved public.cheongla_daily_words%rowtype;
begin
 if not cheongla_private.can_manage_app_content() then raise exception '원장 계정만 글을 작성하고 수정할 수 있습니다.' using errcode='42501';end if;
 if target_day is null or target_day > (now() at time zone 'Asia/Seoul')::date then
  raise exception '게시일은 오늘 또는 이전 날짜로 선택해 주세요.' using errcode='22023';end if;
 if post_status is null or post_status not in ('draft','published') or post_body is null or char_length(btrim(post_body)) not between 1 and 6000 or char_length(coalesce(post_title,''))>120 then
  raise exception '본문은 1~6,000자, 제목은 120자 이내로 입력해 주세요.' using errcode='22023';end if;
 select * into old_row from public.cheongla_daily_words where message_on=target_day for update;
 if found then
  if expected_updated_at is null or old_row.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 새로고침한 뒤 다시 수정해 주세요.' using errcode='40001';end if;
  update public.cheongla_daily_words set title=coalesce(post_title,''),body=post_body,status=post_status where id=old_row.id returning * into saved;
 else
  if expected_updated_at is not null then raise exception '수정할 글을 다시 확인해 주세요.' using errcode='40001';end if;
  insert into public.cheongla_daily_words(message_on,title,body,status) values(target_day,coalesce(post_title,''),post_body,post_status) returning * into saved;
 end if;
 return to_jsonb(saved);
exception when unique_violation then raise exception '이 날짜의 글이 이미 저장되었습니다. 새로고침 후 수정해 주세요.' using errcode='40001';
end;$function$
