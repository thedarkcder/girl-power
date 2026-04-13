#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 <run_id> [output_dir] [owner/repo]" >&2
  echo "Example: $0 24154242938 docs/test-artifacts/GP-186 thedarkcder/girl-power" >&2
  exit 64
fi

run_id="$1"
output_dir="${2:-docs/test-artifacts/GP-186}"
repo_slug="${3:-thedarkcder/girl-power}"

if ! [[ "$run_id" =~ ^[0-9]+$ ]]; then
  echo "run_id must be numeric: $run_id" >&2
  exit 64
fi

api_root="https://api.github.com/repos/${repo_slug}/actions"
run_json="$(mktemp)"
jobs_json="$(mktemp)"
trap 'rm -f "$run_json" "$jobs_json"' EXIT

curl -sSfL "${api_root}/runs/${run_id}" -o "$run_json"
curl -sSfL "${api_root}/runs/${run_id}/jobs?per_page=100" -o "$jobs_json"

mkdir -p "$output_dir"
out_path="${output_dir}/pr-testflight-run-${run_id}-metadata.json"

jq -c -n \
  --slurpfile run "$run_json" \
  --slurpfile jobs "$jobs_json" \
  '{
    databaseId: $run[0].id,
    status: $run[0].status,
    conclusion: $run[0].conclusion,
    event: $run[0].event,
    createdAt: $run[0].created_at,
    updatedAt: $run[0].updated_at,
    headSha: $run[0].head_sha,
    url: $run[0].html_url,
    jobs: (($jobs[0].jobs // []) | map({
      databaseId: .id,
      name,
      status,
      conclusion,
      startedAt: .started_at,
      completedAt: .completed_at,
      url: .html_url,
      steps: ((.steps // []) | map({
        number,
        name,
        status,
        conclusion,
        startedAt: .started_at,
        completedAt: .completed_at
      }))
    }))
  }' > "$out_path"

echo "wrote ${out_path}"
