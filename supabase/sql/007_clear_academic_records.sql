begin;

create or replace function public.clear_academic_records()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := auth.uid();
begin
  if owner_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  delete from public.grade_records where user_id = owner_id;
  delete from public.mock_exam_records where user_id = owner_id;
  delete from public.school_record_evidence where user_id = owner_id;
end;
$$;

revoke all on function public.clear_academic_records() from public, anon;
grant execute on function public.clear_academic_records() to authenticated;
notify pgrst, 'reload schema';

commit;
