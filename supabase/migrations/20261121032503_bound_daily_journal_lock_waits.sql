-- Bound journal lock waits so concurrent saves cannot tie up API connections.
alter function cheongla_private.seed_daily_journal(date) set lock_timeout = '2s';
alter function public.cheongla_daily_journal_save(date, jsonb, jsonb, bigint) set lock_timeout = '2s';
