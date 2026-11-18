-- 008: AI 상담(앱 도움말·생기부 상담) 사용자별 하루 호출 횟수 제한.
-- Edge Function `app-help`가 Groq를 부르기 직전에 사용자 세션으로 consume_ai_quota(kind)를 호출한다.
-- 질문·답변 내용은 저장하지 않고, 날짜별 횟수만 남긴다. 날짜는 한국 시간(Asia/Seoul) 기준.
-- 한도: 앱 도움말 하루 30회, 생기부 상담 하루 10회, 전체 사용자 합계 하루 900회(Groq 무료 한도 1,000회 아래).
begin;

create table if not exists public.ai_usage_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null,
  help_count integer not null default 0 check (help_count >= 0),
  record_count integer not null default 0 check (record_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_date)
);

create index if not exists ai_usage_daily_date_idx on public.ai_usage_daily (usage_date);

alter table public.ai_usage_daily enable row level security;

-- 본인 사용량은 볼 수 있지만 직접 쓰거나 고칠 수는 없다(증가는 아래 함수로만).
drop policy if exists ai_usage_select_own on public.ai_usage_daily;
create policy ai_usage_select_own on public.ai_usage_daily
  for select to authenticated using ((select auth.uid()) = user_id);

revoke all on public.ai_usage_daily from public, anon;
grant select on public.ai_usage_daily to authenticated;

-- 한도 안이면 1회 차감하고 allowed=true. 한도를 넘으면 차감하지 않고 allowed=false와 사유를 돌려준다.
create or replace function public.consume_ai_quota(p_kind text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid := auth.uid();
  today date := (now() at time zone 'Asia/Seoul')::date;
  user_limit integer;
  global_limit constant integer := 900;
  used integer;
  total integer;
begin
  if owner_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_kind = 'help' then
    user_limit := 30;
  elsif p_kind = 'record' then
    user_limit := 10;
  else
    raise exception 'Unknown kind' using errcode = '22023';
  end if;

  -- 같은 사용자의 동시 요청이 한도를 넘지 않게 행을 만들고 잠근다.
  insert into public.ai_usage_daily (user_id, usage_date)
  values (owner_id, today)
  on conflict (user_id, usage_date) do nothing;

  select case when p_kind = 'help' then help_count else record_count end
    into used
    from public.ai_usage_daily
   where user_id = owner_id and usage_date = today
   for update;

  if used >= user_limit then
    return jsonb_build_object('allowed', false, 'reason', 'DAILY_LIMIT',
      'limit', user_limit, 'remaining', 0);
  end if;

  select coalesce(sum(help_count + record_count), 0) into total
    from public.ai_usage_daily where usage_date = today;
  if total >= global_limit then
    return jsonb_build_object('allowed', false, 'reason', 'SERVICE_LIMIT',
      'limit', user_limit, 'remaining', user_limit - used);
  end if;

  update public.ai_usage_daily
     set help_count = help_count + case when p_kind = 'help' then 1 else 0 end,
         record_count = record_count + case when p_kind = 'record' then 1 else 0 end,
         updated_at = now()
   where user_id = owner_id and usage_date = today;

  return jsonb_build_object('allowed', true, 'limit', user_limit,
    'remaining', user_limit - used - 1);
end;
$$;

revoke all on function public.consume_ai_quota(text) from public, anon;
grant execute on function public.consume_ai_quota(text) to authenticated;
notify pgrst, 'reload schema';

commit;
