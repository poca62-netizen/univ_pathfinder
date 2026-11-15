-- Additive migration: existing records keep unknown exam metadata.
begin;
alter table public.grade_records
  add column if not exists calendar_year integer
    check (calendar_year between 2000 and 2100),
  add column if not exists exam_kind text
    check (exam_kind in ('midterm', 'finalExam', 'semesterSummary')),
  add column if not exists source_confirmed_at timestamptz;
create index if not exists idx_grade_records_exam_period
  on public.grade_records(user_id, calendar_year, school_year, semester, exam_kind);
notify pgrst, 'reload schema';
commit;
