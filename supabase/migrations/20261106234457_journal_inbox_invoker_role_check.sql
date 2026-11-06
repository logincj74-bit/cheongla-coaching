create or replace function public.cheongla_my_journal_notifications(page_limit integer default 20)
returns jsonb language plpgsql stable set search_path='' as $$
declare items jsonb;unread bigint;
begin
 if not exists(select 1 from public.cheongla_profiles where id=auth.uid()and approval_status='approved'and membership_state='active'and role in('owner','english_director','math_director','manager','korean_teacher'))then raise exception '승인된 근무자만 근무일지 알림을 확인할 수 있습니다.'using errcode='42501';end if;
 if page_limit is null or page_limit not between 1 and 200 then raise exception '조회 범위를 확인해 주세요.';end if;
 select coalesce(jsonb_agg(to_jsonb(n)order by n.created_at desc,n.id desc),'[]')into items from(
  select *from public.cheongla_notifications where recipient_id=auth.uid()and source_kind='staff_journal'and archived_at is null and inbox_until>clock_timestamp()
  order by created_at desc,id desc limit page_limit)n;
 select count(*)into unread from public.cheongla_notifications where recipient_id=auth.uid()and source_kind='staff_journal'and read_at is null and archived_at is null and inbox_until>clock_timestamp();
 return jsonb_build_object('items',items,'unread_count',unread);
end;$$;
revoke all on function public.cheongla_my_journal_notifications(integer)from public,anon;
grant execute on function public.cheongla_my_journal_notifications(integer)to authenticated;

notify pgrst,'reload schema';
