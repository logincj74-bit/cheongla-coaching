-- Match the existing column-specific editor grants. RLS still requires an active principal.
grant insert(poster_data_url,poster_video_path),update(poster_data_url,poster_video_path)
 on public.cheongla_home_features to authenticated;
notify pgrst,'reload schema';
