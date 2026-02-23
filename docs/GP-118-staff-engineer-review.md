> **Pre-flight — February 23, 2026:** Staff review for GP-118 covering Supabase evaluate-session orchestration before writing migrations or edge code.

1. Problem: Persist each coaching session evaluation plus the associated LLM delegation audits so the mobile client can call one idempotent endpoint and always observe consistent state.
2. Type: Workflow / long-running process
3. Invariants:
   - Only Edge Functions using the service-role Supabase key may create or mutate session/attempt rows; anonymous clients can only read via RLS-safe views.
   - (`device_id`, `attempt_index`) uniquely identifies a demo attempt and can be traced back to one session lifecycle regardless of retries.
   - Every evaluation invocation either persists a terminal COMPLETED/FALLBACK state exactly once or fails without side effects (transactional boundary).
   - Retention TTL keeps `sessions` and `demo_attempts` bounded by automatically expiring rows past 30 days, while payload JSON versions allow schema drift without migrations.
4. Assumptions:
   - Mobile only holds anon key + `device_id`, so the Edge function must pass the service-role key internally—safe because secrets are injected via Supabase Edge config.
   - Deno 2 runtime plus Supabase CLI are available locally to mimic production; LLM calls can be stubbed by deterministic providers during dev/testing to avoid external dependencies.
   - Per-device rate limits can be enforced through DB-side helper SQL (locking or counters) without needing Redis.
   - Payload schema evolution is managed with a `payload_version` number so clients can ignore unknown fields safely.
5. Contract matrix:
   - Null/malformed body ⇒ HTTP 400, validation errors logged, no DB writes (unchanged rest of system).
   - Duplicate attempt (same `device_id` + `attempt_index`) ⇒ HTTP 409, return existing session payload, idempotent (intentional new behavior).
   - Rate-limit/quota breach ⇒ HTTP 429, response flagged `fallback_used=true`, `reason="rate_limited"`, no new rows (new behavior).
   - Valid invocation ⇒ state machine enters RECEIVED→…→COMPLETED with `sessions` + `demo_attempts` persisted plus JSON payload referencing `payload_version` (new behavior).
   - Internal failure ⇒ HTTP 500 with correlation ID, transaction rolls back so no partial writes (enforced behavior).
6. Call-path impact scan:
   - Mobile app → HTTPS POST `/functions/v1/evaluate-session` with anon key headers.
   - Edge function uses service-role Supabase client + helper repo modules to validate, rate-limit, orchestrate LLM call, persist rows, and return payload.
   - No other components write to new tables; analytics/reporting may eventually read via service-role but out of scope now.
7. Domain term contracts:
   - `session` = conversational grouping covering one or more `demo_attempts`, keyed by server-generated UUID.
   - `demo_attempt` = single prompt/response attempt keyed by (`device_id`, `attempt_index`) plus foreign key to session.
   - `LLM payload` = JSON object `{ payload_version, request, response, moderation, fallback_used }` stored on both session + attempt for audit.
   - `evaluate-session` endpoint = idempotent POST that runs reducer-driven state machine ensuring monotonic transitions.
8. Authorization & data-access contract:
   - Poster (mobile) holds anon key, limited to invoking Edge function; RLS prevents direct inserts/updates.
   - Edge function authenticates using service-role key pulled from secrets to call `supabase.functions` and `supabase.from` with elevated permissions.
   - Authenticated dashboard users (future) may get read policies but never writes; for now only service-role can mutate tables.
9. Lifecycle & state matrix:
   - States: RECEIVED → VALIDATING → (RATE_LIMITED | REJECTED | DELEGATING_LLM) → (PERSISTING) → (COMPLETED | FALLBACK_DENY | FALLBACK_TIMEOUT).
   - Each state transition driven by reducer events (e.g., `validation_failed`, `rate_limit_tripped`, `llm_success`, `llm_timeout`).
   - Terminal states recorded in session row; demo attempt inherits final state for auditing.
10. Proposed design:
    - SQL migrations to create `users`, `sessions`, `demo_attempts` tables, supporting indexes, enums (text), and TTL via `expires_at default now() + interval '30 days'` plus pg_cron cleanup function.
    - Enable RLS with policies allowing insert/update/delete only for service-role and select for authenticated (if needed) while blocking anon.
    - Helper SQL function `check_device_attempt_limit(device_id uuid, window_lag interval, max_attempts int)` returning status + counters, invoked inside Edge function.
    - Evaluate-session Edge Function written in Deno 2 TypeScript using reducer-style state machine, Supabase JS client, and structured logging/correlation IDs.
    - Shared utils for logging, validation, advisory lock helper, deterministic LLM stub, and transactional persistence repository.
    - Developer scripts (`scripts/supabase-reset.sh`, `scripts/serve-evaluate-session.sh`) plus docs describing workflow + curl examples.
11. Patterns used:
    - Explicit reducer to encode states/events separate from IO, improving testability.
    - Repository/service layer isolating Supabase client interactions for sessions/attempts.
    - Advisory lock per (`device_id`,`attempt_index`) to serialize attempts.
    - Structured logging with correlation IDs to trace flows.
12. Patterns not used:
    - No background job/queue (Edge function handles entire workflow synchronously; queues unnecessary at <5 QPS load).
13. Change surface:
    - `supabase/migrations/*` plus `supabase/seed.sql` for schema + policies + helper functions/cron jobs.
    - `supabase/functions/evaluate-session/*` containing Deno TS code, tests, config, and `.env.local` template.
    - `scripts/*` for supabase start/reset helpers.
    - `docs/evaluate-session.md` describing API contract + local dev instructions.
    - Possibly `package.json` or `deno.json` for lint/test config within functions folder.
14. Load shape & query plan:
    - Expected <5 QPS burst (demo + QA). Queries: select user by `device_id`, upsert session + attempt with indexes on (`device_id`, `attempt_index`), `session_id`, `created_at`.
    - Unique index ensures duplicate rejection; `created_at` indexes support TTL job and analytics.
    - Rate-limit helper uses `select ... for update` or `pg_try_advisory_lock` to avoid races.
15. Failure modes:
    - LLM provider timeout ⇒ fallback path returns deterministic deny payload + sets FALLBACK_DENY; log metric.
    - DB unavailable ⇒ respond 503, no writes; correlation ID surfaces root cause.
    - Rate limit storage contention ⇒ advisory locks/backoff; on failure return 500 but with no writes.
    - Malformed JSON/payload version drift ⇒ validation rejects with 400; schema tolerant due to JSONB fields.
16. Operational integrity:
    - Rollback by reverting migrations + removing function; TTL job ensures no long-lived data.
    - Dependencies: Supabase Postgres (transaction boundaries), LLM provider (bounded timeout), pg_cron (cleanup). All run with timeouts and error logging.
    - Concurrency: per-device attempts wrapped in advisory locks; DB transaction ensures single insert/upsert; idempotent by returning existing attempt when conflict occurs.
17. Tests:
    - Reducer unit tests verifying all transitions and terminal states.
    - Rate-limit helper test hitting duplicate attempts > threshold verifying 429 path.
    - Integration harness hitting local function to assert session + attempt rows created and payload_version stored; second call returns 409.
    - SQL policy test verifying anon cannot insert while service-role can (via `supabase test` or simple script).
18. Verdict: ✅ Proceed — design is appropriate and scoped.
