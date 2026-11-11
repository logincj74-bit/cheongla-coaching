-- Authenticated principals only. No image storage or external API calls.
create table if not exists cheongla_private.score_extraction_requests(user_id uuid primary key references public.cheongla_profiles(id)on delete cascade,window_at timestamptz not null,attempts integer not null);
alter table cheongla_private.score_extraction_requests enable row level security;
revoke all on cheongla_private.score_extraction_requests from public,anon,authenticated;
create or replace function public.cheongla_claim_score_extraction()returns void language plpgsql security definer set search_path='' as $$
declare r cheongla_private.score_extraction_requests%rowtype;
begin
 if not cheongla_private.is_principal()then raise insufficient_privilege;end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1111));
 select *into r from cheongla_private.score_extraction_requests where user_id=auth.uid();
 if found and r.window_at>clock_timestamp()-interval '1 minute'and r.attempts>=5 then raise exception '1분 후 다시 시도해 주세요.';end if;
 insert into cheongla_private.score_extraction_requests values(auth.uid(),clock_timestamp(),1)on conflict(user_id)do update set window_at=case when r.window_at>clock_timestamp()-interval '1 minute'then r.window_at else excluded.window_at end,attempts=case when r.window_at>clock_timestamp()-interval '1 minute'then r.attempts+1 else 1 end;
end;$$;
revoke all on function public.cheongla_claim_score_extraction()from public,anon;
grant execute on function public.cheongla_claim_score_extraction()to authenticated;
notify pgrst,'reload schema';
