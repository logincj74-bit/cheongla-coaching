create or replace function cheongla_private.can_purge_information_file(object_name text)
returns boolean language sql stable security definer set search_path = ''
as $$
 select auth.uid() is not null
 and cheongla_private.can_manage_life()
 and exists(
   select 1 from public.cheongla_information_files f
   join public.cheongla_information_posts p on p.id=f.post_id
   join cheongla_private.content_purge_claims j
     on j.post_id=p.id and j.record_version=p.updated_at
   where f.object_path=object_name and p.deleted_at is not null
 );
$$;
revoke all on function cheongla_private.can_purge_information_file(text) from public, anon;
grant execute on function cheongla_private.can_purge_information_file(text) to authenticated;
alter policy information_storage_trash_remove on storage.objects
to authenticated using (
 bucket_id='cheongla-information'
 and cheongla_private.can_purge_information_file(name)
);
