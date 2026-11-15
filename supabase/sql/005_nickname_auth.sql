begin;
create table if not exists public.nickname_accounts (
 nickname_key text primary key check (nickname_key ~ '^[a-z0-9가-힣_]{2,20}$'),
 user_id uuid not null unique references auth.users(id) on delete cascade,
 pin_hash text not null,
 created_at timestamptz not null default now()
);
create table if not exists public.nickname_login_attempts (
 nickname_key text primary key,
 failures integer not null default 0,
 locked_until timestamptz,
 updated_at timestamptz not null default now()
);
create table if not exists public.nickname_auth_rate_limits (
 bucket text primary key, requests integer not null, window_start timestamptz not null
);
alter table public.nickname_accounts enable row level security;
alter table public.nickname_login_attempts enable row level security;
alter table public.nickname_auth_rate_limits enable row level security;
revoke all on public.nickname_accounts, public.nickname_login_attempts, public.nickname_auth_rate_limits from anon, authenticated;
grant all on public.nickname_accounts, public.nickname_login_attempts, public.nickname_auth_rate_limits to service_role;

create or replace function public.nickname_auth_rate_limit(p_bucket text)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
 insert into public.nickname_auth_rate_limits(bucket,requests,window_start) values(p_bucket,1,now())
 on conflict(bucket) do update set
 requests=case when nickname_auth_rate_limits.window_start < now()-interval '15 minutes' then 1 else nickname_auth_rate_limits.requests+1 end,
 window_start=case when nickname_auth_rate_limits.window_start < now()-interval '15 minutes' then now() else nickname_auth_rate_limits.window_start end
 returning requests into n;
 return n<=30;
end; $$;

create or replace function public.register_nickname_account(p_nickname text,p_pin text,p_user_id uuid)
returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
begin
 if p_nickname !~ '^[a-z0-9가-힣_]{2,20}$' or p_pin !~ '^[0-9]{4}$' then raise exception 'INVALID_INPUT'; end if;
 insert into public.nickname_accounts(nickname_key,user_id,pin_hash) values(p_nickname,p_user_id,extensions.crypt(p_pin,extensions.gen_salt('bf',12)));
 insert into public.profiles(id,nickname) values(p_user_id,p_nickname) on conflict(id) do update set nickname=excluded.nickname;
end; $$;

create or replace function public.authenticate_nickname(p_nickname text,p_pin text)
returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a public.nickname_accounts; t public.nickname_login_attempts; next_failures integer;
begin
 if p_nickname !~ '^[a-z0-9가-힣_]{2,20}$' or p_pin !~ '^[0-9]{4}$' then return jsonb_build_object('status','invalid'); end if;
 insert into public.nickname_login_attempts(nickname_key) values(p_nickname) on conflict do nothing;
 select * into t from public.nickname_login_attempts where nickname_key=p_nickname for update;
 if t.locked_until>now() then return jsonb_build_object('status','locked'); end if;
 select * into a from public.nickname_accounts where nickname_key=p_nickname;
 if a.user_id is not null and a.pin_hash=extensions.crypt(p_pin,a.pin_hash) then
  update public.nickname_login_attempts set failures=0,locked_until=null,updated_at=now() where nickname_key=p_nickname;
  return jsonb_build_object('status','ok','user_id',a.user_id);
 end if;
 if a.user_id is null then perform extensions.crypt(p_pin,extensions.gen_salt('bf',12)); end if;
 next_failures=case when t.updated_at < now()-interval '15 minutes' then 1 else t.failures+1 end;
 update public.nickname_login_attempts set failures=next_failures,locked_until=case when next_failures>=5 then now()+interval '15 minutes' else null end,updated_at=now() where nickname_key=p_nickname;
 return jsonb_build_object('status',case when next_failures>=5 then 'locked' else 'invalid' end);
end; $$;
revoke all on function public.nickname_auth_rate_limit(text),public.register_nickname_account(text,text,uuid),public.authenticate_nickname(text,text) from public,anon,authenticated;
grant execute on function public.nickname_auth_rate_limit(text),public.register_nickname_account(text,text,uuid),public.authenticate_nickname(text,text) to service_role;
notify pgrst,'reload schema';
commit;
