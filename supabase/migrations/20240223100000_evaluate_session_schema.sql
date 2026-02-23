set check_function_bodies = off;
set search_path to public;

-- Extensions required for UUID generation and cron cleanup
create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "pg_cron" with schema extensions;

-- Helper to keep updated_at in sync
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

grant execute on function public.touch_updated_at() to service_role;

create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  device_id text not null unique,
  profile jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  device_id text not null,
  session_state text not null check (
    session_state = any (array['RECEIVED','VALIDATING','RATE_LIMITED','REJECTED','DELEGATING_LLM','PERSISTING','COMPLETED','FALLBACK_DENY','FALLBACK_TIMEOUT'])
  ),
  payload_version text not null default 'v1',
  llm_payload jsonb not null default '{}'::jsonb,
  decision text,
  fallback_used boolean not null default false,
  correlation_id text not null,
  attempt_count integer not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz not null default timezone('utc', now()) + interval '30 days'
);

create table if not exists public.demo_attempts (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  device_id text not null,
  attempt_index integer not null check (attempt_index >= 0),
  payload_version text not null default 'v1',
  request_payload jsonb not null,
  llm_response jsonb not null,
  moderation_payload jsonb not null,
  state text not null check (
    state = any (array['RECEIVED','VALIDATING','RATE_LIMITED','REJECTED','DELEGATING_LLM','PERSISTING','COMPLETED','FALLBACK_DENY','FALLBACK_TIMEOUT'])
  ),
  reason text,
  fallback_used boolean not null default false,
  rate_limit_window_start timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz not null default timezone('utc', now()) + interval '30 days'
);

create unique index if not exists users_device_id_idx on public.users(device_id);
create index if not exists sessions_device_created_idx on public.sessions(device_id, created_at desc);
create index if not exists sessions_expires_idx on public.sessions(expires_at);
create unique index if not exists sessions_correlation_idx on public.sessions(correlation_id);
create unique index if not exists demo_attempts_device_attempt_idx on public.demo_attempts(device_id, attempt_index);
create index if not exists demo_attempts_device_created_idx on public.demo_attempts(device_id, created_at desc);
create index if not exists demo_attempts_expires_idx on public.demo_attempts(expires_at);

create trigger users_touch_updated
before update on public.users
for each row execute function public.touch_updated_at();

create trigger sessions_touch_updated
before update on public.sessions
for each row execute function public.touch_updated_at();

alter table public.users enable row level security;
alter table public.sessions enable row level security;
alter table public.demo_attempts enable row level security;

-- Service role gets full CRUD
create policy "users-service-role-full" on public.users
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create policy "sessions-service-role-full" on public.sessions
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create policy "demo_attempts-service-role-full" on public.demo_attempts
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

-- Authenticated users may read for analytics dashboards; anon remains blocked
create policy "users-authenticated-read" on public.users
for select
using (auth.role() in ('authenticated','service_role'));

create policy "sessions-authenticated-read" on public.sessions
for select
using (auth.role() in ('authenticated','service_role'));

create policy "demo_attempts-authenticated-read" on public.demo_attempts
for select
using (auth.role() in ('authenticated','service_role'));

-- Rate limit helper returning deterministic counts
create or replace function public.check_device_attempt_limit(
  p_device_id text,
  p_window_seconds integer,
  p_max_attempts integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window_seconds integer := greatest(p_window_seconds, 0);
  v_limit integer := greatest(p_max_attempts, 1);
  v_window_start timestamptz := timezone('utc', now()) - make_interval(secs => v_window_seconds);
  v_attempts integer;
begin
  select count(*) into v_attempts
  from public.demo_attempts
  where device_id = p_device_id
    and created_at >= v_window_start;

  return jsonb_build_object(
    'allowed', v_attempts < v_limit,
    'attempt_count', v_attempts,
    'window_start', v_window_start
  );
end;
$$;

revoke all on function public.check_device_attempt_limit(text, integer, integer) from public;
grant execute on function public.check_device_attempt_limit(text, integer, integer) to service_role;

create or replace function public.persist_evaluate_session(
  p_device_id text,
  p_attempt_index integer,
  p_payload_version text,
  p_request jsonb,
  p_response jsonb,
  p_moderation jsonb,
  p_state text,
  p_reason text,
  p_fallback_used boolean,
  p_correlation_id text,
  p_decision text,
  p_rate_limit_window_seconds integer,
  p_max_attempts integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing_attempt public.demo_attempts%rowtype;
  v_window_seconds integer := greatest(p_rate_limit_window_seconds, 0);
  v_limit integer := greatest(p_max_attempts, 1);
  v_window_start timestamptz := timezone('utc', now()) - make_interval(secs => v_window_seconds);
  v_attempts integer;
  v_user_id uuid;
  v_session_record public.sessions%rowtype;
  v_attempt_record public.demo_attempts%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(coalesce(p_device_id,''), 0));

  select * into v_existing_attempt
  from public.demo_attempts
  where device_id = p_device_id and attempt_index = p_attempt_index
  limit 1;

  if found then
    return jsonb_build_object('status','duplicate','demo_attempt', row_to_json(v_existing_attempt));
  end if;

  select count(*) into v_attempts
  from public.demo_attempts
  where device_id = p_device_id
    and created_at >= v_window_start;

  if v_attempts >= v_limit then
    return jsonb_build_object('status','rate_limited','attempt_count', v_attempts,'window_start', v_window_start);
  end if;

  insert into public.users(device_id)
  values (p_device_id)
  on conflict (device_id) do update set device_id = excluded.device_id
  returning id into v_user_id;

  insert into public.sessions(user_id, device_id, session_state, payload_version, llm_payload, decision, fallback_used, correlation_id, attempt_count)
  values (
    v_user_id,
    p_device_id,
    p_state,
    coalesce(nullif(p_payload_version,''), 'v1'),
    jsonb_build_object(
      'payload_version', coalesce(nullif(p_payload_version,''), 'v1'),
      'request', coalesce(p_request, '{}'::jsonb),
      'response', coalesce(p_response, '{}'::jsonb),
      'moderation', coalesce(p_moderation, '{}'::jsonb)
    ),
    p_decision,
    coalesce(p_fallback_used, false),
    p_correlation_id,
    1
  )
  returning * into v_session_record;

  insert into public.demo_attempts(
    session_id,
    device_id,
    attempt_index,
    payload_version,
    request_payload,
    llm_response,
    moderation_payload,
    state,
    reason,
    fallback_used,
    rate_limit_window_start
  )
  values (
    v_session_record.id,
    p_device_id,
    p_attempt_index,
    coalesce(nullif(p_payload_version,''), 'v1'),
    coalesce(p_request, '{}'::jsonb),
    coalesce(p_response, '{}'::jsonb),
    coalesce(p_moderation, '{}'::jsonb),
    p_state,
    p_reason,
    coalesce(p_fallback_used, false),
    v_window_start
  )
  returning * into v_attempt_record;

  update public.sessions
  set attempt_count = (
    select count(*) from public.demo_attempts where session_id = v_session_record.id
  )
  where id = v_session_record.id
  returning * into v_session_record;

  return jsonb_build_object(
    'status','created',
    'session', row_to_json(v_session_record),
    'demo_attempt', row_to_json(v_attempt_record),
    'attempt_count', v_attempts + 1,
    'window_start', v_window_start
  );
end;
$$;

revoke all on function public.persist_evaluate_session(text, integer, text, jsonb, jsonb, jsonb, text, text, boolean, text, text, integer, integer) from public;
grant execute on function public.persist_evaluate_session(text, integer, text, jsonb, jsonb, jsonb, text, text, boolean, text, text, integer, integer) to service_role;

create or replace function public.purge_expired_evaluate_session_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.demo_attempts where expires_at <= timezone('utc', now());
  delete from public.sessions where expires_at <= timezone('utc', now());
  delete from public.users u
  where not exists (
    select 1 from public.sessions s where s.user_id = u.id
  )
  and u.created_at <= timezone('utc', now()) - interval '30 days';
end;
$$;

revoke all on function public.purge_expired_evaluate_session_data() from public;
grant execute on function public.purge_expired_evaluate_session_data() to service_role;

do $block$
begin
  if not exists (select 1 from cron.job where jobname = 'evaluate_session_ttl') then
    perform cron.schedule('evaluate_session_ttl', '0 * * * *', $cmd$call public.purge_expired_evaluate_session_data();$cmd$);
  end if;
end;
$block$;
