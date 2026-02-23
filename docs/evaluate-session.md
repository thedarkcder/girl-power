# Evaluate Session Edge Function

The `supabase/functions/evaluate-session` Deno Edge Function orchestrates per-device coaching attempts, persists session + demo attempt records, enforces idempotency on (`device_id`, `attempt_index`), and responds to mobile clients with a structured payload that captures both LLM results and fallback paths.

## API Contract

- **Endpoint:** `POST /functions/v1/evaluate-session`
- **Required headers:**
  - `Authorization: Bearer <SUPABASE_ANON_KEY>` (mobile callers only have the anon key)
  - `Content-Type: application/json`
- **Body schema:**

```jsonc
{
  "device_id": "uuid-or-string",
  "attempt_index": 0,
  "payload_version": "v1",
  "input": {
    "prompt": "Explain how I should pace my next set",
    "context": {
      "goal": "tempo",
      "reps_completed": 12
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
| `200` | Attempt succeeded or deterministic fallback produced | `session_id`, `attempt_id`, `state`, `payload_version`, `request`, `response`, `moderation`, `rate_limit`, `fallback_used=false` unless fallback executed |
| `409` | Duplicate (`device_id`, `attempt_index`) | Returns persisted attempt payload, `reason="duplicate_attempt"`, `fallback_used` reflects stored record |
| `429` | Rate limit tripped (more than `RATE_LIMIT_ATTEMPTS` within window) | `state="RATE_LIMITED"`, `fallback_used=true`, `reason="rate_limited"`, `rate_limit.allowed=false` |
| `500` | Unexpected internal error | `error="internal_error"`, includes `correlation_id` for log lookup |

## Security Boundary

- Only the Edge function runs with the Supabase **service-role key**. New tables (`public.users`, `public.sessions`, `public.demo_attempts`) have RLS enabled with service-role-only write policies and authenticated read policies; anon clients cannot insert/update/delete.
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
5. **Serve the function with hot reload**: `scripts/serve-evaluate-session.sh`
6. **Call the endpoint** using the anon key printed by `supabase start`:

   ```bash
   export SUPABASE_ANON_KEY="$(supabase status --json | jq -r '.services | .[] | select(.service_name=="api") | .env | .SUPABASE_ANON_KEY')"

   curl -s \
     -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "device_id": "11111111-1111-1111-1111-111111111111",
       "attempt_index": 0,
       "payload_version": "v1",
       "input": { "prompt": "Give me coaching cues", "context": { "goal": "tempo" } }
     }' \
     http://localhost:54321/functions/v1/evaluate-session | jq
   ```

7. **Rate-limit scenario**: send more than `RATE_LIMIT_ATTEMPTS` (default 3) within the window to observe `429` and `fallback_used=true`.

   ```bash
   for i in 0 1 2 3; do
     curl -s -o /dev/null -w "Attempt $i => %\{http_code\}\n" \
       -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
       -H "Content-Type: application/json" \
       -d "{\"device_id\":\"11111111-1111-1111-1111-111111111111\",\"attempt_index\":$i,\"payload_version\":\"v1\",\"input\":{\"prompt\":\"rep $i\"}}" \
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
| `cd supabase/functions && deno task test` | Runs the reducer + rate-limit unit tests. |
| `supabase db reset && psql ...` | Validate schema applied (`select expires_at from sessions limit 1;`). |

## Observability

- Each response includes a `correlation_id`; logs emitted from `logger.ts` include the same field for tracing.
- Structured logging ensures rate-limit hits, fallback paths, and DB failures are distinguishable without parsing string logs.
