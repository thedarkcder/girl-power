# Demo Quota Edge Functions

GP-115 uses a small Edge-function bundle:

- `evaluate-session`: authoritative second-attempt decision path
- `demo-session-log`: attempt start/completion audit logging
- `demo-snapshot-fetch` / `demo-snapshot-mirror`: quota snapshot hydration while the client still has its keychain-backed `device_id`

## API Contract

- **Endpoint:** `POST /functions/v1/evaluate-session`
- **Required headers:**
  - `Authorization: Bearer <SUPABASE_ANON_KEY>` (mobile callers only have the anon key)
  - `Content-Type: application/json`
- **Body schema:**

```jsonc
{
  "device_id": "uuid-or-string",
  "attempt_index": 1,
  "payload_version": "v1",
  "input": {
    "prompt": "Decide whether a second demo is allowed",
    "context": {
      "goal": "tempo",
      "reps_completed": 12,
      "duration_seconds": 48
    }
  },
  "metadata": {
    "app_version": "1.12.0"
  }
}
```

### Responses

| Status | When | Body pieces |
| --- | --- | --- |
| `200` | Decision resolved | `allow_another_demo`, `attempts_used`, `evaluated_at`, `lock_reason?`, `message?`, mirrored `snapshot`, plus persisted audit payloads |
| `400` | Invalid JSON/body shape or unsupported `attempt_index` | `error="invalid_body"` plus validation details |
| `409` | Duplicate (`device_id`, `attempt_index`) | Returns the persisted decision + audit payload with `reason="duplicate_attempt"` |
| `429` | Rate limit tripped (more than `RATE_LIMIT_ATTEMPTS` within window) | `state="RATE_LIMITED"`, `allow_another_demo=false`, `reason="rate_limited"` |
| `500` | Unexpected internal error | `error="internal_error"`, includes `correlation_id` for log lookup |

Example success body:

```jsonc
{
  "allow_another_demo": true,
  "attempts_used": 1,
  "evaluated_at": "2026-03-14T12:00:00.000Z",
  "snapshot": {
    "attempts_used": 1,
    "active_attempt_index": null,
    "last_decision": { "type": "allow", "ts": "2026-03-14T12:00:00.000Z" },
    "server_lock_reason": null,
    "last_sync_at": "2026-03-14T12:00:00.000Z"
  }
}
```

## Security Boundary

- Only the Edge functions run with the Supabase **service-role key**. New tables (`public.demo_quota_attempt_logs`, `public.demo_quota_snapshots`) and the earlier `users/sessions/demo_attempts` tables are all RLS-protected for service-role writes only.
- The mobile app uses the anon key solely to call the Edge endpoint; it can never talk to the tables directly.
- Secrets (`SUPABASE_SERVICE_ROLE_KEY`, future LLM provider keys) live in `supabase/functions/.env.local` locally and Supabase Edge secrets remotely—never in source control.

## Retention / TTL

- Both `sessions` and `demo_attempts` record an `expires_at` timestamp defaulting to **30 days**.
- `public.purge_expired_evaluate_session_data()` deletes expired attempts/sessions and dereferences users with no sessions older than 30 days.
- A `pg_cron` job (`evaluate_session_ttl`) runs hourly to execute the purge function so tables remain bounded.

## Local Development Workflow

1. **Install prereqs**: Supabase CLI (`supabase --version`), Docker, and Deno 2 (`deno --version`).
2. **Copy env templates**:
   ```bash
   cp .env.example .env
   cp supabase/functions/.env.example supabase/functions/.env.local
   # The Supabase CLI injects SUPABASE_* vars automatically, so you usually only need to tune RATE_LIMIT_* / LLM_*.
   # If you run the function outside the CLI, copy SUPABASE_URL/keys from `supabase status -o json`.
   ```
3. **Start the local stack**: `scripts/supabase-start.sh`
4. **Apply migrations** (requires the stack running): `scripts/supabase-reset.sh`
5. **Serve the function bundle with hot reload**:
   ```bash
   scripts/serve-evaluate-session.sh
   supabase functions serve demo-session-log --env-file supabase/functions/.env.local
   supabase functions serve demo-snapshot-fetch --env-file supabase/functions/.env.local
   supabase functions serve demo-snapshot-mirror --env-file supabase/functions/.env.local
   ```
6. **Call the endpoint** using the anon key printed by `supabase start`:

   ```bash
   export SUPABASE_ANON_KEY="$(supabase status --json | jq -r '.services | .[] | select(.service_name=="api") | .env | .SUPABASE_ANON_KEY')"

   curl -s \
     -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "device_id": "11111111-1111-1111-1111-111111111111",
       "attempt_index": 1,
       "payload_version": "v1",
       "input": { "prompt": "Decide whether a second demo is allowed", "context": { "goal": "tempo" } },
       "metadata": { "source": "curl" }
   }' \
     http://localhost:54321/functions/v1/evaluate-session | jq
   ```

   `demo-session-log` accepts only `attempt_index` values `1` and `2`; `evaluate-session` accepts only `attempt_index=1`.

7. **Snapshot validation**:

   ```bash
   curl -s \
     -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{"device_id":"11111111-1111-1111-1111-111111111111","attempt_index":2,"stage":"completion","metadata":{"source":"curl"}}' \
     http://localhost:54321/functions/v1/demo-session-log | jq

   curl -s \
     -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{"device_id":"11111111-1111-1111-1111-111111111111"}' \
     http://localhost:54321/functions/v1/demo-snapshot-fetch | jq
   ```

   The snapshot should report `attempts_used=2` and `server_lock_reason="quota"` while the same keychain-backed `device_id` is still available on the client. Full uninstall/reinstall recovery is intentionally unsupported until a durable identity contract is approved.

8. **Invalid attempt boundary checks**:

   ```bash
   curl -s \
     -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{"device_id":"11111111-1111-1111-1111-111111111111","attempt_index":3,"stage":"start"}' \
     http://localhost:54321/functions/v1/demo-session-log | jq

   curl -s \
     -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{"device_id":"11111111-1111-1111-1111-111111111111","attempt_index":2,"payload_version":"v1","input":{"prompt":"invalid"}}' \
     http://localhost:54321/functions/v1/evaluate-session | jq
   ```

   Both requests should return `400` with `error="invalid_body"` and should not write new attempt or snapshot state.

9. **Rate-limit scenario**: send more than `RATE_LIMIT_ATTEMPTS` (default 3) within the window to observe `429` and `allow_another_demo=false`.

   ```bash
   for i in 1 2 3 4; do
     curl -s -o /dev/null -w "Attempt $i => %\{http_code\}\n" \
       -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
       -H "Content-Type: application/json" \
       -d "{\"device_id\":\"11111111-1111-1111-1111-111111111111\",\"attempt_index\":1,\"payload_version\":\"v1\",\"input\":{\"prompt\":\"rep $i\"}}" \
       http://localhost:54321/functions/v1/evaluate-session
   done
   ```

   The fourth request returns `429` with `reason="rate_limited"` and no additional rows written.

## Helpful Scripts & Commands

| Command | Purpose |
| --- | --- |
| `scripts/supabase-start.sh` | Boots the Supabase local stack (`docker compose` under the hood). |
| `scripts/supabase-reset.sh` | Runs `supabase db reset` (migrations + `supabase/seed.sql`). Requires the stack to be running. |
| `scripts/serve-evaluate-session.sh` | Serves the `evaluate-session` Edge function with `--env-file supabase/functions/.env.local`. |
| `cd supabase/functions && deno task test` | Runs the decision-path, reducer, and rate-limit unit tests. |
| `supabase db reset && psql ...` | Validate schema applied (`select expires_at from sessions limit 1;`). |

## Observability

- Each response includes a `correlation_id`; logs emitted from `logger.ts` include the same field for tracing.
- Structured logging ensures rate-limit hits, fallback paths, and DB failures are distinguishable without parsing string logs.
