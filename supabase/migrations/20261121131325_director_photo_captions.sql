alter table public.cheongla_director_files
 add column caption text not null default '',
 add constraint director_file_caption_length check (char_length(caption) <= 160);

create function public.cheongla_save_director_photo_post(
 target_post uuid, post_title text, post_body text, post_state text,
 expected_updated_at timestamptz, file_ids uuid[], photo_captions jsonb
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
 saved jsonb;
 photo record;
begin
 -- The existing save enforces author access, checks the revision and locks the post.
 saved := public.cheongla_save_director_post(
  target_post, post_title, post_body, post_state, expected_updated_at, file_ids
 );
 if saved->>'category' is distinct from 'photos'
    or jsonb_typeof(photo_captions) is distinct from 'object' then
  raise exception '사진 설명을 확인해 주세요.';
 end if;

 for photo in select key, value from jsonb_each(photo_captions) loop
  if jsonb_typeof(photo.value) is distinct from 'string'
     or char_length(photo.value #>> '{}') > 160 then
   raise exception '사진 설명은 160자까지 입력할 수 있습니다.';
  end if;

  update public.cheongla_director_files
  set caption = btrim(photo.value #>> '{}')
  where id = photo.key::uuid and post_id = target_post and state = 'ready'
    and removal_requested_at is null and filename ~* '\.(jpg|jpeg|png|webp|gif)$';
  if not found then
   raise exception '사진이 변경되었습니다. 글을 새로 열어 확인해 주세요.';
  end if;
 end loop;
 return saved;
end;
$$;

revoke all on function public.cheongla_save_director_photo_post(uuid,text,text,text,timestamptz,uuid[],jsonb)
 from public, anon, authenticated;
grant execute on function public.cheongla_save_director_photo_post(uuid,text,text,text,timestamptz,uuid[],jsonb)
 to authenticated;
notify pgrst, 'reload schema';
