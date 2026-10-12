-- 도시락 신청·취소·식비·정산 기록과 전용 기능을 삭제합니다.
-- 회원, 공지, 학원비, 모의고사, 질의응답 자료는 유지합니다.
begin;
drop function if exists public.cheongla_meal_month_accounts(date);
drop function if exists public.cheongla_save_meal_bill(uuid,date,text,date,integer,text,boolean,text,timestamptz);
drop function if exists public.cheongla_meal_month_ready();
drop function if exists public.cheongla_meal_roster(uuid);
drop function if exists public.cheongla_cancel_meal_order(uuid,uuid,text,timestamptz);
drop function if exists public.cheongla_apply_meal(uuid,text);
drop function if exists public.cheongla_apply_meal_month(date,uuid[]);
drop function if exists public.cheongla_open_meal_month(date,integer[],integer[],text);
drop function if exists public.cheongla_save_meal(uuid,text,date,timestamptz,text,text,timestamptz);
drop table if exists public.cheongla_meal_adjustment_ledger;
drop table if exists public.cheongla_meal_bills;
drop table if exists public.cheongla_meal_orders;
drop table if exists public.cheongla_meals;
drop function if exists cheongla_private.can_view_meals();
drop function if exists cheongla_private.can_manage_meals();
notify pgrst,'reload schema';
commit;
