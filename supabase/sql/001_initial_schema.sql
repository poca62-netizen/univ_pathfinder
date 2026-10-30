-- Univ Pathfinder 초기 스키마
-- profiles 및 grade_records 테이블, RLS 정책 포함
-- 실행 전 Supabase 프로젝트 환경 확인 필요
-- 2028학년도 대입부터 지원, 향후 학년도 확장 가능

-- UUID 생성용 확장 확인
create extension if not exists "pgcrypto";

-- profiles 테이블
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(btrim(nickname)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- achievement_distribution 검증 함수
create or replace function public.is_valid_achievement_distribution(dist jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  k text;
  v_val jsonb;
  v numeric;
  keys_present text[] := '{}';
  sum_val numeric := 0;
  has_all boolean := false;
begin
  -- 컬럼 NULL 허용
  if dist is null then
    return true;
  end if;

  -- 객체 타입 확인
  if jsonb_typeof(dist) <> 'object' then
    return false;
  end if;

  -- 키 및 값 검증
  for k in select jsonb_object_keys(dist) loop
    if k not in ('A','B','C','D','E') then
      return false;
    end if;

    v_val := dist->k;
    -- JSON 숫자 타입만 허용
    if jsonb_typeof(v_val) <> 'number' then
      return false;
    end if;

    -- JSON 숫자 → numeric 변환
    begin
      v := (v_val::text)::numeric;
    exception
      when others then
        return false;
    end;

    if v is null or v < 0 or v > 100 then
      return false;
    end if;

    keys_present := array_append(keys_present, k);
    sum_val := sum_val + v;
  end loop;

  -- A~E 다섯 구간 모두 존재 시 합계 약 100 검증
  if array_length(keys_present, 1) = 5 then
    has_all := true;
    for k in select unnest(array['A','B','C','D','E']) loop
      if not (k = ANY (keys_present)) then
        has_all := false;
        exit;
      end if;
    end loop;
    if has_all then
      -- 반올림 오차 허용: 99.5 ~ 100.5
      if sum_val < 99.5 or sum_val > 100.5 then
        return false;
      end if;
    end if;
  end if;

  return true;
exception
  when others then
    return false;
end;
$$;

-- grade_records 테이블
create table if not exists public.grade_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  school_year integer not null check (school_year between 1 and 3),
  semester integer not null check (semester in (1,2)),
  subject_name text not null check (char_length(btrim(subject_name)) > 0),
  credit numeric not null check (credit > 0),
  raw_score numeric check (raw_score is null or (raw_score >= 0 and raw_score <= 100)),
  subject_average numeric check (subject_average is null or (subject_average >= 0 and subject_average <= 100)),
  achievement text,
  grade_rank integer check (grade_rank is null or (grade_rank between 1 and 5)),
  achievement_distribution jsonb check (public.is_valid_achievement_distribution(achievement_distribution)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 기존 UNIQUE 제약 제거로 복수 기록 허용
alter table if exists public.grade_records drop constraint if exists grade_records_user_subject_key;

-- 인덱스
create index if not exists idx_grade_records_user_id on public.grade_records(user_id);
create index if not exists idx_grade_records_subject on public.grade_records(subject_name);

-- updated_at 자동 갱신 함수
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- 트리거
drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists trg_grade_records_updated_at on public.grade_records;
create trigger trg_grade_records_updated_at
before update on public.grade_records
for each row execute function public.set_updated_at();

-- RLS 활성화
alter table public.profiles enable row level security;
alter table public.grade_records enable row level security;

-- profiles 정책
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own" on public.profiles
  for delete to authenticated using ((select auth.uid()) = id);

-- grade_records 정책
drop policy if exists "grade_records_select_own" on public.grade_records;
create policy "grade_records_select_own" on public.grade_records
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "grade_records_insert_own" on public.grade_records;
create policy "grade_records_insert_own" on public.grade_records
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "grade_records_update_own" on public.grade_records;
create policy "grade_records_update_own" on public.grade_records
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "grade_records_delete_own" on public.grade_records;
create policy "grade_records_delete_own" on public.grade_records
  for delete to authenticated using ((select auth.uid()) = user_id);

-- 권한
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.grade_records to authenticated;

-- 비고
-- 성적표 원본 이미지, 학생 이름, 학교명, 생년월일, 학번은 저장하지 않음
-- 닉네임은 인증 수단이 아님
-- 2028학년도 대입 5등급 체계 기본, 향후 확장 가능
