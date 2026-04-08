# GP-186 TestFlight Workflow Evidence

## Scope

Issue: `GP-186`  
Purpose: traceable evidence for PR-to-TestFlight documentation and validation.

## CI Failure-Path Evidence (Observed)

- Workflow: `PR TestFlight`
- Run ID: `24149572001`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24149572001
- Trigger: `pull_request` on `feature/GP-185` to `main`
- Started: `2026-04-08T17:36:25Z`
- Completed: `2026-04-08T17:37:13Z`
- Conclusion: `failure`
- Failing step: `Preflight CI secret presence check`
- Observed marker/error:
  - `Missing required CI secret/env keys: APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_API_KEY_BASE64 APPLE_TEAM_ID`
- Log capture in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24149572001.log`

## CI PR-Triggered Validation on GP-186 Branch (Observed)

- PR: https://github.com/thedarkcder/girl-power/pull/26
- Workflow: `PR TestFlight`
- Run ID: `24152730438`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24152730438
- Trigger: `pull_request` on `feature/GP-186` to `main`
- Job start/end: `2026-04-08T18:51:51Z` -> `2026-04-08T18:52:34Z`
- Conclusion: `failure`
- Observed markers:
  - `[CI_PRECHECK] Required secret/env key presence validated (values redacted).`
  - `[PR_TESTFLIGHT][FAILED][CATEGORY=auth] Preflight failed: string contains null byte`
- Interpretation:
  - Required key names are now present in CI.
  - Failure moved to Fastlane auth parsing; `APP_STORE_CONNECT_API_KEY_BASE64` content format is likely invalid/malformed.
- Log captures in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24152730438.log`
  - `docs/test-artifacts/GP-186/pr-testflight-run-24152730438-metadata.json`

## Local Lane Evidence (Observed)

Environment used for local validation in this run:
- Ruby: `/opt/homebrew/opt/ruby@2.7/bin/ruby` (`2.7.8`)
- Bundler: `2.4.22`

### Local success-path-equivalent (dry run)

Command executed:

```bash
APP_STORE_CONNECT_API_KEY_ID=dummy_key \
APP_STORE_CONNECT_ISSUER_ID=dummy_issuer \
APP_STORE_CONNECT_API_KEY_BASE64=ZHVtbXk= \
APPLE_TEAM_ID=DUMMYTEAMID \
PR_TESTFLIGHT_DRY_RUN=1 \
BUNDLE_PATH=vendor/bundle-ruby27 \
bundle _2.4.22_ exec fastlane pr_testflight
```

Observed markers in `local-pr-testflight-dry-run-ruby27.log`:
- `[PR_TESTFLIGHT][ARCHIVE_BUILD_COMPLETE] dry-run (no archive executed)`
- `[PR_TESTFLIGHT][TESTFLIGHT_UPLOAD_COMPLETE] dry-run (no upload executed)`
- `[PR_TESTFLIGHT][COMPLETE] version=1.0 build=202604081850 scheme=GirlPower`

### Local failure-path verification

Command executed without `APP_STORE_CONNECT_API_KEY_ID`.

Observed markers in `local-pr-testflight-missing-auth-key-ruby27.log`:
- `[PR_TESTFLIGHT][FAILED][CATEGORY=auth] Missing required environment variable: APP_STORE_CONNECT_API_KEY_ID`
- Exit code recorded in `local-missing-auth-exit-code-ruby27.txt`: `1`

## Local Artifacts Produced

- `docs/test-artifacts/GP-186/local-bundle-install-ruby27.log`
- `docs/test-artifacts/GP-186/local-pr-testflight-dry-run-ruby27.log`
- `docs/test-artifacts/GP-186/local-pr-testflight-missing-auth-key-ruby27.log`
- `docs/test-artifacts/GP-186/local-missing-auth-exit-code-ruby27.txt`
- `docs/test-artifacts/GP-186/pr-testflight-run-24149572001.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24152730438.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24152730438-metadata.json`
- `docs/test-artifacts/GP-186/workflow-pause-resume-check.txt`

## Pause / Re-enable Verification (Observed)

- Timestamp: `2026-04-08T18:50:30Z`
- Command evidence file: `docs/test-artifacts/GP-186/workflow-pause-resume-check.txt`
- Result:
  - Workflow hidden from `gh workflow list` after disable step.
  - Workflow listed as `active` after re-enable step:
    - `PR TestFlight active 258042100`

## PR-Triggered Success Evidence (Current State)

- No successful PR-triggered TestFlight upload has completed yet for GP-186.
- Current blocker marker from latest run (`24152730438`):
  - `[PR_TESTFLIGHT][FAILED][CATEGORY=auth] Preflight failed: string contains null byte`
- Next required remediation: rotate/fix `APP_STORE_CONNECT_API_KEY_BASE64` to valid base64-encoded `.p8`, then re-run PR workflow.
