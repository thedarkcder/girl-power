#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="supabase/functions/.env.local"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy supabase/functions/.env.example and fill in the Supabase keys." >&2
  exit 1
fi

supabase functions serve evaluate-session --env-file "$ENV_FILE" "$@"
