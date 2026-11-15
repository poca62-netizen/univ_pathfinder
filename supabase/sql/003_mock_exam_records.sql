begin;
create table if not exists public.mock_exam_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  calendar_year integer not null check (calendar_year between 2000 and 2100),
  school_year integer not null check (school_year between 1 and 3),
  exam_month integer not null check (exam_month between 1 and 12),
  institution text,
  subject text not null check (char_length(btrim(subject)) > 0),
  elective text,
  raw_score numeric check (raw_score between 0 and 100),
  standard_score numeric check (standard_score >= 0 and standard_score < 'Infinity'::numeric),
  percentile numeric check (percentile between 0 and 100),
  grade_rank integer check (grade_rank between 1 and 9),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(raw_score, standard_score, percentile, grade_rank) > 0)
);
create index if not exists idx_mock_exam_user_period on public.mock_exam_records(user_id, calendar_year, school_year, exam_month);
alter table public.mock_exam_records enable row level security;
drop policy if exists mock_exam_select_own on public.mock_exam_records;
create policy mock_exam_select_own on public.mock_exam_records for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists mock_exam_insert_own on public.mock_exam_records;
create policy mock_exam_insert_own on public.mock_exam_records for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists mock_exam_update_own on public.mock_exam_records;
create policy mock_exam_update_own on public.mock_exam_records for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists mock_exam_delete_own on public.mock_exam_records;
create policy mock_exam_delete_own on public.mock_exam_records for delete to authenticated using ((select auth.uid()) = user_id);
drop trigger if exists set_mock_exam_updated_at on public.mock_exam_records;
create trigger set_mock_exam_updated_at before update on public.mock_exam_records for each row execute function public.set_updated_at();
grant select, insert, update, delete on public.mock_exam_records to authenticated;
notify pgrst, 'reload schema';
commit;
