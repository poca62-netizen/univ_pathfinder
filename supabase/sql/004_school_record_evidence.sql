begin;
create table if not exists public.school_record_evidence (
id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
calendar_year integer not null check(calendar_year between 2000 and 2100),school_year integer not null check(school_year between 1 and 3),
category text not null check(char_length(btrim(category)) between 1 and 100),evidence text not null check(char_length(btrim(evidence)) between 1 and 10000),source_location text not null check(char_length(btrim(source_location)) between 1 and 300),career_interest text check(char_length(career_interest)<=300),source_confirmed_at timestamptz not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create index if not exists idx_school_record_user_period on public.school_record_evidence(user_id,calendar_year,school_year);
alter table public.school_record_evidence enable row level security;
drop policy if exists school_record_select_own on public.school_record_evidence;
create policy school_record_select_own on public.school_record_evidence for select to authenticated using ((select auth.uid()) = user_id) ;
drop policy if exists school_record_insert_own on public.school_record_evidence;
create policy school_record_insert_own on public.school_record_evidence for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists school_record_update_own on public.school_record_evidence;
create policy school_record_update_own on public.school_record_evidence for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists school_record_delete_own on public.school_record_evidence;
create policy school_record_delete_own on public.school_record_evidence for delete to authenticated using ((select auth.uid()) = user_id) ;
drop trigger if exists set_school_record_updated_at on public.school_record_evidence;
create trigger set_school_record_updated_at before update on public.school_record_evidence for each row execute function public.set_updated_at();
grant select,insert,update,delete on public.school_record_evidence to authenticated;
notify pgrst, 'reload schema';
commit;