# Girl Power Workspace

This repo hosts the Girl Power iOS app plus supporting Supabase Edge Functions. Use the instructions below to configure the new `evaluate-session` workflow locally.

## Environment Setup

1. Install prerequisites:
   - [Supabase CLI 2.75+](https://supabase.com/docs/guides/cli)
   - Docker Desktop (for the local stack)
   - [Deno 2](https://deno.com/manual/getting_started/installation)
2. Copy the provided env templates:
   ```bash
   cp .env.example .env
   cp supabase/functions/.env.example supabase/functions/.env.local
   ```
3. The Supabase CLI automatically injects `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` into the Edge runtime; keep them in `.env.example` for documentation and fill them in only if you plan to run the function outside the CLI. The remaining fields (`RATE_LIMIT_*`, `LLM_*`) already default to sane local values but can be tuned per developer.

## Helpful Scripts

| Command | Description |
| --- | --- |
| `scripts/supabase-start.sh` | Boots the Supabase Docker stack. Run once per terminal session. |
| `scripts/supabase-reset.sh` | Applies the latest migrations + `supabase/seed.sql`. Requires the stack to be running and enforces RLS/TTL policies described in the docs. |
| `scripts/serve-evaluate-session.sh` | Serves `evaluate-session` with hot reload using `supabase/functions/.env.local`. |

See [`docs/evaluate-session.md`](docs/evaluate-session.md) for the API contract, curl examples, rate-limit expectations, and additional operational notes.
