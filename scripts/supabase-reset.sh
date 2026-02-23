#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! supabase status >/dev/null 2>&1; then
  echo "Supabase local stack is not running. Run scripts/supabase-start.sh in another terminal first." >&2
  exit 1
fi

supabase db reset "$@"
