-- Covers travel with the home content record and use its existing read/write policies.
alter table public.cheongla_home_features
 add column poster_data_url text,
 add column poster_video_path text,
 add constraint home_video_poster_format check(poster_data_url is null or
  (length(poster_data_url)<=160000 and poster_data_url ~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+=*$')),
 add constraint home_video_poster_pair check((poster_data_url is null)=(poster_video_path is null));

create function cheongla_private.bind_home_video_poster()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.original_video or new.video_path is null or new.poster_data_url is null
 or new.poster_video_path is distinct from new.video_path then
  new.poster_data_url:=null;new.poster_video_path:=null;
 end if;
 return new;
end;$$;
revoke all on function cheongla_private.bind_home_video_poster() from public,anon,authenticated;
create trigger home_feature_poster_binding before insert or update of video_path,original_video,poster_data_url,poster_video_path
 on public.cheongla_home_features for each row execute function cheongla_private.bind_home_video_poster();
notify pgrst,'reload schema';
