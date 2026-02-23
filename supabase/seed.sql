insert into public.users (device_id, profile)
values ('seed-device-id', jsonb_build_object('seed', true))
on conflict (device_id) do nothing;

with inserted_session as (
  insert into public.sessions (
    user_id,
    device_id,
    session_state,
    payload_version,
    llm_payload,
    decision,
    fallback_used,
    correlation_id,
    attempt_count
  )
  select id,
         device_id,
         'COMPLETED',
         'v-seed',
         jsonb_build_object('payload_version','v-seed','request', jsonb_build_object('prompt','seed'), 'response', jsonb_build_object('text','seed'), 'moderation', jsonb_build_object('flagged', false)),
         'seed-only',
         false,
         'seed-correlation-' || device_id,
         1
  from public.users
  where device_id = 'seed-device-id'
  on conflict do nothing
  returning *
)
insert into public.demo_attempts (
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
select s.id,
       s.device_id,
       0,
       'v-seed',
       jsonb_build_object('prompt','seed'),
       jsonb_build_object('text','seed response'),
       jsonb_build_object('flagged', false),
       'COMPLETED',
       'seed data',
       false,
       timezone('utc', now()) - interval '60 seconds'
from inserted_session s
on conflict do nothing;
