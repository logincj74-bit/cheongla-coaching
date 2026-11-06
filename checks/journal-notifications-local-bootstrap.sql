-- Isolated in-memory PostgreSQL only. No network, live credentials or users.
create role anon;create role authenticated;create role service_role;
create schema auth;create schema cheongla_private;
grant usage on schema auth,cheongla_private to authenticated;
create function auth.uid()returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;$$;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb);
create table public.cheongla_profiles(id uuid primary key,full_name text,role text default'student',approval_status text default'pending',membership_state text default'active');
create table public.cheongla_push_subscriptions(id uuid primary key default gen_random_uuid(),user_id uuid,enabled boolean default true);
create function auth.fixture_profile()returns trigger language plpgsql as $$begin
 insert into public.cheongla_profiles(id,full_name)values(new.id,new.raw_user_meta_data->>'full_name');
 insert into public.cheongla_push_subscriptions(user_id)values(new.id);return new;end;$$;
create trigger fixture_profile after insert on auth.users for each row execute function auth.fixture_profile();
create table public.cheongla_notifications(id uuid primary key default gen_random_uuid(),recipient_id uuid references public.cheongla_profiles(id),source_kind text,source_id uuid,student_id uuid,title text,route text,event_key text,created_at timestamptz default clock_timestamp(),read_at timestamptz,inbox_until timestamptz default clock_timestamp()+interval'24 hours',archived_at timestamptz,unique(recipient_id,event_key));
alter table public.cheongla_notifications enable row level security;
grant select on public.cheongla_notifications to authenticated;
create table cheongla_private.push_deliveries(id uuid primary key default gen_random_uuid(),notification_id uuid,subscription_id uuid,unique(notification_id,subscription_id));
create table cheongla_private.staff_journals(id uuid primary key,work_on date,archived_at timestamptz,created_at timestamptz,closed_at timestamptz,author_id uuid,ink_color text,field_inks jsonb);
create table cheongla_private.staff_journal_comments(id uuid primary key,journal_id uuid,field_key text,deleted_at timestamptz,created_at timestamptz,body text,ink_runs jsonb,ink_color text);
create table cheongla_private.staff_journal_history(journal_id uuid);
-- Unrelated notification branches need catalog objects but are not exercised here.
create table public.cheongla_director_posts(id uuid,state text,archived_at timestamptz);
create table cheongla_private.account_help_requests(id uuid);
create table cheongla_private.winter_bookings(id uuid,archived_at timestamptz,owner_id uuid);
create function cheongla_private.can_manage_account_recovery()returns boolean language sql as $$select false;$$;
create function cheongla_private.can_manage_winter()returns boolean language sql as $$select false;$$;
create function cheongla_private.can_use_member_services()returns boolean language sql as $$select false;$$;
create function cheongla_private.can_read_notification_before_winter(text,uuid,uuid)returns boolean language sql as $$select false;$$;
