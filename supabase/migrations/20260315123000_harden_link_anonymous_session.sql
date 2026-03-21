set check_function_bodies = off;
set search_path to public;

create index if not exists demo_attempts_device_anon_session_idx
  on public.demo_attempts(
    device_id,
    ((request_payload -> 'metadata' ->> 'anon_session_id')),
    created_at desc
  );

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
  v_source_user_id uuid;
  v_existing public.anonymous_session_links%rowtype;
  v_linked_at timestamptz := timezone('utc', now());
begin
  perform pg_advisory_xact_lock(hashtextextended(coalesce(p_anon_session_id::text, ''), 0));

  select * into v_existing
  from public.anonymous_session_links
  where anon_session_id = p_anon_session_id
  limit 1;

  if found then
    if v_existing.device_id = p_device_id
       and v_existing.auth_user_id = p_auth_user_id then
      return 'duplicate';
    end if;
    return 'stale_session';
  end if;

  select sessions.user_id into v_source_user_id
  from public.demo_attempts
  join public.sessions on public.sessions.id = public.demo_attempts.session_id
  where public.demo_attempts.device_id = p_device_id
    and public.demo_attempts.request_payload -> 'metadata' ->> 'anon_session_id' = p_anon_session_id::text
  order by public.demo_attempts.created_at desc
  limit 1;

  if v_source_user_id is null then
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
    v_source_user_id
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
  where id = v_source_user_id;

  return 'linked';
end;
$$;

revoke all on function public.link_anonymous_session(text, uuid, uuid) from public;
grant execute on function public.link_anonymous_session(text, uuid, uuid) to service_role;
