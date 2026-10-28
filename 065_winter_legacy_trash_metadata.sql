-- Export the current trash state instead of the historical imported deletion date.
-- The original JSON record is not changed.
create or replace function public.cheongla_winter_booking_list()
 returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.can_manage_winter() then
  raise exception '원장·실장만 상담·예약을 관리할 수 있습니다.' using errcode='42501';
 end if;
 return jsonb_build_object(
  'items',(select coalesce(jsonb_agg(to_jsonb(r)-'receipt_hash'-'request_id' order by r.created_at desc),'[]') from cheongla_private.winter_bookings r where r.archived_at is null or cheongla_private.is_principal()),
  'legacy',(select coalesce(jsonb_agg(record||jsonb_build_object('source_id',source_id,'deleted_at',deleted_at)),'[]') from cheongla_private.winter_legacy_records where deleted_at is null),
  'legacy_trash',case when cheongla_private.is_principal() then
   (select coalesce(jsonb_agg(record||jsonb_build_object('source_id',source_id,'deleted_at',deleted_at) order by deleted_at desc),'[]') from cheongla_private.winter_legacy_records where deleted_at is not null)
   else '[]'::jsonb end);
end;
$$;
revoke all on function public.cheongla_winter_booking_list() from public,anon;
grant execute on function public.cheongla_winter_booking_list() to authenticated;
