set check_function_bodies = off;
set search_path to public;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  is_pro boolean not null default false,
  pro_platform text check (
    pro_platform is null or pro_platform = any (array['apple', 'external'])
  ),
  onboarding_completed boolean not null default false,
  last_login_at timestamptz
);

drop trigger if exists profiles_touch_updated on public.profiles;

create trigger profiles_touch_updated
before update on public.profiles
for each row execute function public.touch_updated_at();

revoke all on public.profiles from authenticated;
grant select, insert on public.profiles to authenticated;
grant update (email, onboarding_completed, last_login_at) on public.profiles to authenticated;
grant select, insert, update on public.profiles to service_role;

alter table public.profiles enable row level security;

drop policy if exists "profiles-service-role-full" on public.profiles;

create policy "profiles-service-role-full" on public.profiles
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

drop policy if exists "profiles-authenticated-read-own" on public.profiles;

create policy "profiles-authenticated-read-own" on public.profiles
for select
using (auth.uid() = id);

drop policy if exists "profiles-authenticated-insert-own" on public.profiles;

create policy "profiles-authenticated-insert-own" on public.profiles
for insert
with check (auth.uid() = id);

drop policy if exists "profiles-authenticated-update-own" on public.profiles;

create policy "profiles-authenticated-update-own" on public.profiles
for update
using (auth.uid() = id)
with check (auth.uid() = id);
