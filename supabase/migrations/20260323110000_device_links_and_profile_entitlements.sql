set check_function_bodies = off;
set search_path to public;

create table if not exists public.device_links (
  device_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  linked_at timestamptz not null default timezone('utc', now()),
  primary key (device_id, user_id)
);

create index if not exists device_links_user_linked_idx
  on public.device_links(user_id, linked_at desc);

create index if not exists device_links_device_linked_idx
  on public.device_links(device_id, linked_at desc);

alter table public.device_links enable row level security;

drop policy if exists "device_links-service-role-full" on public.device_links;

create policy "device_links-service-role-full" on public.device_links
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create or replace function public.link_authenticated_device(
  p_device_id text,
  p_auth_user_id uuid,
  p_anon_session_id uuid default null
)
returns table (
  status text,
  attempts_used integer,
  active_attempt_index integer,
  last_decision jsonb,
  server_lock_reason text,
  last_sync_at timestamptz,
  linked_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := timezone('utc', now());
  v_insert_count integer := 0;
  v_linked_at timestamptz := v_now;
  v_source_user_id uuid;
  v_attempts_used integer := 0;
  v_active_attempt_index integer;
  v_last_decision jsonb;
  v_server_lock_reason text;
  v_last_sync_at timestamptz;
begin
  if p_auth_user_id is null then
    raise exception 'p_auth_user_id is required';
  end if;

  if p_device_id is null or btrim(p_device_id) = '' then
    raise exception 'p_device_id is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(coalesce(p_auth_user_id::text, ''), 0));

  insert into public.device_links (
    device_id,
    user_id,
    linked_at
  ) values (
    p_device_id,
    p_auth_user_id,
    v_now
  )
  on conflict (device_id, user_id) do nothing;

  get diagnostics v_insert_count = row_count;

  if v_insert_count = 0 then
    select public.device_links.linked_at
    into v_linked_at
    from public.device_links
    where public.device_links.device_id = p_device_id
      and public.device_links.user_id = p_auth_user_id
    limit 1;
  end if;

  if p_anon_session_id is not null then
    select sessions.user_id
    into v_source_user_id
    from public.demo_attempts
    join public.sessions on public.sessions.id = public.demo_attempts.session_id
    where public.demo_attempts.device_id = p_device_id
      and public.demo_attempts.request_payload -> 'metadata' ->> 'anon_session_id' = p_anon_session_id::text
    order by public.demo_attempts.created_at desc
    limit 1;

    if v_source_user_id is not null then
      insert into public.anonymous_session_links (
        anon_session_id,
        device_id,
        auth_user_id,
        user_id
      ) values (
        p_anon_session_id,
        p_device_id,
        p_auth_user_id,
        v_source_user_id
      )
      on conflict (anon_session_id) do update
      set
        device_id = excluded.device_id,
        auth_user_id = excluded.auth_user_id,
        user_id = excluded.user_id,
        updated_at = timezone('utc', now())
      where public.anonymous_session_links.device_id = excluded.device_id
        and public.anonymous_session_links.auth_user_id = excluded.auth_user_id
        and public.anonymous_session_links.user_id = excluded.user_id;
    end if;
  end if;

  with linked_devices as (
    select distinct device_links.device_id
    from public.device_links
    where device_links.user_id = p_auth_user_id
  ),
  device_authority as (
    select
      linked_devices.device_id,
      least(
        2,
        greatest(
          coalesce(demo_quota_snapshots.attempts_used, 0),
          coalesce(log_summary.highest_completed_attempt, 0)
        )
      ) as attempts_used,
      case
        when least(
          2,
          greatest(
            coalesce(demo_quota_snapshots.attempts_used, 0),
            coalesce(log_summary.highest_completed_attempt, 0)
          )
        ) >= 2 then null
        else coalesce(log_summary.active_attempt_index, demo_quota_snapshots.active_attempt_index)
      end as active_attempt_index,
      demo_quota_snapshots.last_decision,
      case
        when least(
          2,
          greatest(
            coalesce(demo_quota_snapshots.attempts_used, 0),
            coalesce(log_summary.highest_completed_attempt, 0)
          )
        ) >= 2 then 'quota'
        else demo_quota_snapshots.server_lock_reason
      end as server_lock_reason,
      demo_quota_snapshots.last_sync_at
    from linked_devices
    left join public.demo_quota_snapshots
      on demo_quota_snapshots.device_id = linked_devices.device_id
    left join lateral (
      select
        max(case when completed_at is not null then attempt_index end) as highest_completed_attempt,
        max(case when started_at is not null and completed_at is null then attempt_index end) as active_attempt_index
      from public.demo_quota_attempt_logs
      where demo_quota_attempt_logs.device_id = linked_devices.device_id
    ) as log_summary on true
  ),
  aggregate_snapshot as (
    select
      least(2, coalesce(sum(device_authority.attempts_used), 0))::integer as attempts_used,
      (
        select device_authority.active_attempt_index
        from device_authority
        where device_authority.device_id = p_device_id
      ) as active_attempt_index,
      (
        select device_authority.last_decision
        from device_authority
        where device_authority.last_decision is not null
        order by (device_authority.last_decision ->> 'ts')::timestamptz desc nulls last
        limit 1
      ) as last_decision,
      (
        case
          when least(2, coalesce(sum(device_authority.attempts_used), 0)) >= 2 then 'quota'
          else (
            select device_authority.server_lock_reason
            from device_authority
            where device_authority.server_lock_reason is not null
            order by
              case when device_authority.device_id = p_device_id then 0 else 1 end,
              device_authority.last_sync_at desc nulls last
            limit 1
          )
        end
      ) as server_lock_reason,
      max(device_authority.last_sync_at) as last_sync_at
    from device_authority
  )
  select
    aggregate_snapshot.attempts_used,
    case
      when aggregate_snapshot.attempts_used >= 2 then null
      else aggregate_snapshot.active_attempt_index
    end,
    aggregate_snapshot.last_decision,
    aggregate_snapshot.server_lock_reason,
    aggregate_snapshot.last_sync_at
  into
    v_attempts_used,
    v_active_attempt_index,
    v_last_decision,
    v_server_lock_reason,
    v_last_sync_at
  from aggregate_snapshot;

  insert into public.demo_quota_snapshots (
    device_id,
    attempts_used,
    active_attempt_index,
    last_decision,
    server_lock_reason,
    last_sync_at
  ) values (
    p_device_id,
    v_attempts_used,
    v_active_attempt_index,
    v_last_decision,
    v_server_lock_reason,
    v_last_sync_at
  )
  on conflict (device_id) do update
  set
    attempts_used = excluded.attempts_used,
    active_attempt_index = excluded.active_attempt_index,
    last_decision = excluded.last_decision,
    server_lock_reason = excluded.server_lock_reason,
    last_sync_at = excluded.last_sync_at;

  return query
  select
    case when v_insert_count > 0 then 'linked' else 'already_linked' end,
    v_attempts_used,
    v_active_attempt_index,
    v_last_decision,
    v_server_lock_reason,
    v_last_sync_at,
    v_linked_at;
end;
$$;

revoke all on function public.link_authenticated_device(text, uuid, uuid) from public;
grant execute on function public.link_authenticated_device(text, uuid, uuid) to service_role;
