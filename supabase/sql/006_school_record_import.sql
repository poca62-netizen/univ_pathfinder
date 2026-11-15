begin;
alter table public.grade_records add column if not exists source_location text check(char_length(source_location)<=300);
alter table public.school_record_evidence add column if not exists career_evidence_enabled boolean not null default true;
alter table public.school_record_evidence add column if not exists import_key text;
create unique index if not exists school_evidence_import_unique on public.school_record_evidence(user_id,import_key) where import_key is not null;

-- Invoker rights retain all existing owner RLS policies. A single transaction
-- saves both kinds of reviewed data; retries never overwrite existing grades.
create or replace function public.import_school_record(p_grades jsonb, p_evidence jsonb)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare uid uuid := auth.uid(); g jsonb; e jsonb; item_key text;
  added_grades integer:=0; added_evidence integer:=0;
  skipped_grades integer:=0; skipped_evidence integer:=0;
  existing_periods jsonb; seen text[]:=array[]::text[]; period text;
begin
  if uid is null then raise exception 'Login required'; end if;
  if coalesce(jsonb_typeof(p_grades),'null')<>'array' or coalesce(jsonb_typeof(p_evidence),'null')<>'array'
     or jsonb_array_length(p_grades)>300 or jsonb_array_length(p_evidence)>300 then
    raise exception 'Invalid import';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 619));
  select coalesce(jsonb_agg(distinct concat(calendar_year,'/',school_year,'/',semester)), '[]'::jsonb)
    into existing_periods from public.grade_records where user_id=uid and exam_kind='semesterSummary';
  for g in select value from jsonb_array_elements(p_grades) loop
    if (g->>'calendar_year')::integer not between 2000 and 2100
       or g->>'calendar_year' is null or g->>'source_confirmed_at' is null
       or (g->>'calendar_year')::integer-(g->>'school_year')::integer+1 < 2025
       or g->>'exam_kind' is distinct from 'semesterSummary'
       or regexp_replace(g->>'subject_name','\s','','g') ~ '^(체육|음악|미술|과학탐구실험|교양|운동과건강|스포츠생활)'
       then raise exception 'Invalid school grade'; end if;
    period:=concat(g->>'calendar_year','/',g->>'school_year','/',g->>'semester');
    item_key:=concat(period,'/',regexp_replace(g->>'subject_name','\s','','g'));
    if item_key=any(seen) then raise exception 'Duplicate subject in selection'; end if;
    seen:=array_append(seen,item_key);
    if existing_periods ? period then skipped_grades:=skipped_grades+1; continue; end if;
    insert into public.grade_records(id,user_id,calendar_year,school_year,semester,subject_name,credit,raw_score,subject_average,achievement,grade_rank,achievement_distribution,exam_kind,source_confirmed_at,source_location)
    values((g->>'id')::uuid,uid,(g->>'calendar_year')::integer,(g->>'school_year')::integer,(g->>'semester')::integer,btrim(g->>'subject_name'),(g->>'credit')::numeric,(g->>'raw_score')::numeric,(g->>'subject_average')::numeric,g->>'achievement',(g->>'grade_rank')::integer,nullif(g->'achievement_distribution','null'::jsonb),'semesterSummary',(g->>'source_confirmed_at')::timestamptz,g->>'source_location');
    added_grades:=added_grades+1;
  end loop;
  for e in select value from jsonb_array_elements(p_evidence) loop
    if e->>'source_confirmed_at' is null then raise exception 'Source confirmation required'; end if;
    item_key:=md5(concat(e->>'calendar_year','/',e->>'school_year','/',regexp_replace(e->>'category','\s','','g'),'/',regexp_replace(e->>'evidence','\s','','g')));
    if exists(select 1 from public.school_record_evidence r where r.user_id=uid and
      (r.import_key=item_key or (r.calendar_year=(e->>'calendar_year')::integer and r.school_year=(e->>'school_year')::integer and regexp_replace(r.category,'\s','','g')=regexp_replace(e->>'category','\s','','g') and regexp_replace(r.evidence,'\s','','g')=regexp_replace(e->>'evidence','\s','','g')))) then
      skipped_evidence:=skipped_evidence+1; continue;
    end if;
    insert into public.school_record_evidence(id,user_id,calendar_year,school_year,category,evidence,source_location,career_interest,source_confirmed_at,import_key)
    values((e->>'id')::uuid,uid,(e->>'calendar_year')::integer,(e->>'school_year')::integer,e->>'category',e->>'evidence',e->>'source_location',e->>'career_interest',(e->>'source_confirmed_at')::timestamptz,item_key);
    added_evidence:=added_evidence+1;
  end loop;
  return jsonb_build_object('grades',added_grades,'evidence',added_evidence,'skipped_grades',skipped_grades,'skipped_evidence',skipped_evidence);
end; $$;
revoke all on function public.import_school_record(jsonb,jsonb) from public,anon;
grant execute on function public.import_school_record(jsonb,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;
