set check_function_bodies = off;
set search_path to public;

create table if not exists public.anonymous_session_links (
  id uuid primary key default gen_random_uuid(),
  anon_session_id uuid not null unique,
  device_id text not null,
  auth_user_id uuid not null,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists anonymous_session_links_device_created_idx
  on public.anonymous_session_links(device_id, created_at desc);

create trigger anonymous_session_links_touch_updated
before update on public.anonymous_session_links
for each row execute function public.touch_updated_at();

alter table public.anonymous_session_links enable row level security;

create policy "anonymous_session_links-service-role-full" on public.anonymous_session_links
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create or replace function public.link_anonymous_session(
  p_device_id text,
  p_anon_session_id uuid,
  p_auth_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_existing public.anonymous_session_links%rowtype;
  v_linked_at timestamptz := timezone('utc', now());
begin
  perform pg_advisory_xact_lock(hashtextextended(coalesce(p_anon_session_id::text, ''), 0));

  select id into v_user_id
  from public.users
  where device_id = p_device_id
  limit 1;

  if v_user_id is null then
    return 'stale_session';
  end if;

  select * into v_existing
  from public.anonymous_session_links
  where anon_session_id = p_anon_session_id
  limit 1;

  if found then
    if v_existing.device_id = p_device_id
       and v_existing.auth_user_id = p_auth_user_id
       and v_existing.user_id = v_user_id then
      return 'duplicate';
    end if;
    return 'stale_session';
  end if;

  insert into public.anonymous_session_links (
    anon_session_id,
    device_id,
    auth_user_id,
    user_id
  ) values (
    p_anon_session_id,
    p_device_id,
    p_auth_user_id,
    v_user_id
  );

  update public.users
  set profile = jsonb_strip_nulls(
    coalesce(profile, '{}'::jsonb) || jsonb_build_object(
      'auth_link',
      jsonb_build_object(
        'auth_user_id', p_auth_user_id,
        'last_anon_session_id', p_anon_session_id,
        'linked_at', v_linked_at
      )
    )
  )
  where id = v_user_id;

  return 'linked';
end;
$$;

revoke all on function public.link_anonymous_session(text, uuid, uuid) from public;
grant execute on function public.link_anonymous_session(text, uuid, uuid) to service_role;
