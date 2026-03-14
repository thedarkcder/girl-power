set check_function_bodies = off;
set search_path to public;

create table if not exists public.demo_quota_attempt_logs (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  attempt_index integer not null check (attempt_index between 1 and 2),
  start_metadata jsonb not null default '{}'::jsonb,
  completion_metadata jsonb not null default '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists demo_quota_attempt_logs_device_attempt_idx
  on public.demo_quota_attempt_logs(device_id, attempt_index);

create index if not exists demo_quota_attempt_logs_device_updated_idx
  on public.demo_quota_attempt_logs(device_id, updated_at desc);

create table if not exists public.demo_quota_snapshots (
  device_id text primary key,
  attempts_used integer not null default 0 check (attempts_used between 0 and 2),
  active_attempt_index integer check (active_attempt_index is null or active_attempt_index between 1 and 2),
  last_decision jsonb,
  server_lock_reason text check (
    server_lock_reason is null or server_lock_reason = any (array['quota', 'evaluation_denied', 'evaluation_timeout', 'server_sync'])
  ),
  last_sync_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.device_identity_mirrors (
  lookup_key text primary key,
  device_id text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create trigger demo_quota_attempt_logs_touch_updated
before update on public.demo_quota_attempt_logs
for each row execute function public.touch_updated_at();

create trigger demo_quota_snapshots_touch_updated
before update on public.demo_quota_snapshots
for each row execute function public.touch_updated_at();

create trigger device_identity_mirrors_touch_updated
before update on public.device_identity_mirrors
for each row execute function public.touch_updated_at();

alter table public.demo_quota_attempt_logs enable row level security;
alter table public.demo_quota_snapshots enable row level security;
alter table public.device_identity_mirrors enable row level security;

create policy "demo_quota_attempt_logs-service-role-full" on public.demo_quota_attempt_logs
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create policy "demo_quota_snapshots-service-role-full" on public.demo_quota_snapshots
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create policy "device_identity_mirrors-service-role-full" on public.device_identity_mirrors
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');
