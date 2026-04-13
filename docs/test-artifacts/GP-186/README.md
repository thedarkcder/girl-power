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

## CI PR-Triggered Validation After Auth Parsing Hardening (Observed)

- PR: https://github.com/thedarkcder/girl-power/pull/26
- Workflow: `PR TestFlight`
- Run ID: `24152908095`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24152908095
- Trigger: `pull_request` synchronize on `feature/GP-186` to `main`
- Job start/end: `2026-04-08T18:56:04Z` -> `2026-04-08T18:56:23Z`
- Conclusion: `failure`
- Observed markers:
  - `[CI_PRECHECK] Required secret/env key presence validated (values redacted).`
  - `[PR_TESTFLIGHT][AUTH] api_key_content_source=raw-pem base64=false`
  - `[PR_TESTFLIGHT][FAILED][CATEGORY=signing] IOS_SIGNING_STYLE must be either 'automatic' or 'manual'`
- Interpretation:
  - Auth parsing issue is resolved by lane hardening.
  - Next blocker moved to `IOS_SIGNING_STYLE` empty-string handling.
- Log captures in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24152908095.log`
  - `docs/test-artifacts/GP-186/pr-testflight-run-24152908095-metadata.json`

## CI PR-Triggered Validation After Signing Normalization (Observed)

- PR: https://github.com/thedarkcder/girl-power/pull/26
- Workflow: `PR TestFlight`
- Run ID: `24153142991`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24153142991
- Trigger: `pull_request` synchronize on `feature/GP-186` to `main`
- Job start/end: `2026-04-08T19:01:35Z` -> `2026-04-08T19:02:13Z`
- Conclusion: `failure`
- Observed markers:
  - `[CI_PRECHECK] Required secret/env key presence validated (values redacted).`
  - `[PR_TESTFLIGHT][PRECHECK] ... signing=automatic dry_run=false`
  - `[PR_TESTFLIGHT][FAILED][CATEGORY=build] Archive/build failed: Error building the application - see the log above`
  - `No profiles for 'com.route25.GirlPower' were found ... Automatic signing is disabled and unable to generate a profile.`
- Interpretation:
  - Auth + signing-style blockers are resolved.
  - Current blocker is provisioning profile/certificate availability for archive on CI.
- Log captures in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24153142991.log`
  - `docs/test-artifacts/GP-186/pr-testflight-run-24153142991-metadata.json`

## CI PR-Triggered Validation on Current PR Head Commit (Observed)

- PR: https://github.com/thedarkcder/girl-power/pull/26
- Workflow: `PR TestFlight`
- Run ID: `24153241603`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24153241603
- Trigger: `pull_request` synchronize on `feature/GP-186` to `main`
- Job start/end: `2026-04-08T19:03:59Z` -> `2026-04-08T19:04:37Z`
- Conclusion: `failure`
- Observed markers:
  - `[CI_PRECHECK] Required secret/env key presence validated (values redacted).`
  - `[PR_TESTFLIGHT][PRECHECK] ... signing=automatic dry_run=false`
  - `[PR_TESTFLIGHT][FAILED][CATEGORY=build] Archive/build failed: Error building the application - see the log above`
  - `No profiles for 'com.route25.GirlPower' were found ...`
- Interpretation:
  - Auth + signing-style blockers stay resolved on latest commit.
  - Current remaining blocker is provisioning profile/certificate availability for CI archive.
- Log captures in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24153241603.log`
  - `docs/test-artifacts/GP-186/pr-testflight-run-24153241603-metadata.json`

## CI PR-Triggered Validation After `-allowProvisioningUpdates` Enablement (Observed)

- PR: https://github.com/thedarkcder/girl-power/pull/26
- Workflow: `PR TestFlight`
- Run ID: `24153766410`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24153766410
- Trigger: `pull_request` synchronize on `feature/GP-186` to `main`
- Job start/end: `2026-04-08T19:16:16Z` -> `2026-04-08T19:18:58Z`
- Conclusion: `failure`
- Observed markers:
  - `[PR_TESTFLIGHT][PRECHECK] ... signing=automatic allow_provisioning_updates=true dry_run=false`
  - `[PR_TESTFLIGHT][SIGNING] Automatic signing includes xcodebuild auth key flags`
  - `xcodebuild ... CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -authenticationKeyPath ... -authenticationKeyID ... -authenticationKeyIssuerID ...`
  - `error: exportArchive Cloud signing permission error`
  - `error: exportArchive No profiles for 'com.route25.GirlPower' were found`
  - `[PR_TESTFLIGHT][FAILED][CATEGORY=build] Archive/build failed: Error packaging up the application`
- Interpretation:
  - Lane now reaches archive/export with explicit automatic provisioning flags.
  - Remaining failure is account-side permission/signing capability (`Cloud signing permission error`) rather than missing lane flags.
- Log captures in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24153766410.log`
  - `docs/test-artifacts/GP-186/pr-testflight-run-24153766410-metadata.json`

## CI PR-Triggered Validation on Latest Deployment Trigger Commit (Observed)

- PR: https://github.com/thedarkcder/girl-power/pull/26
- Workflow: `PR TestFlight`
- Run ID: `24154089686`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24154089686
- Trigger: `pull_request` synchronize on `feature/GP-186` to `main`
- Job start/end: `2026-04-08T19:24:23Z` -> `2026-04-08T19:26:03Z`
- Conclusion: `failure`
- Observed markers:
  - `[PR_TESTFLIGHT][PRECHECK] ... signing=automatic allow_provisioning_updates=true dry_run=false`
  - `[PR_TESTFLIGHT][SIGNING] Automatic signing includes xcodebuild auth key flags`
  - `xcodebuild ... CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -authenticationKeyPath ... -authenticationKeyID ... -authenticationKeyIssuerID ...`
  - `error: exportArchive Cloud signing permission error`
  - `error: exportArchive No profiles for 'com.route25.GirlPower' were found`
  - `[PR_TESTFLIGHT][FAILED][CATEGORY=build] Archive/build failed: Error packaging up the application`
- Interpretation:
  - Latest PR deployment-trigger commit confirms the new automatic-provisioning flags are active in CI.
  - Remaining blocker is Apple account/cloud-signing authorization and profile availability, not lane-command mismatch.
- Log captures in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24154089686.log`
  - `docs/test-artifacts/GP-186/pr-testflight-run-24154089686-metadata.json`

## CI PR-Triggered Validation on Latest Recorded PR-26 Run (Observed)

- PR: https://github.com/thedarkcder/girl-power/pull/26
- Workflow: `PR TestFlight`
- Run ID: `24154242938`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24154242938
- Trigger: `pull_request` synchronize on `feature/GP-186` to `main`
- Job start/end: `2026-04-08T19:32:40Z` -> `2026-04-08T19:33:36Z`
- Conclusion: `failure`
- Observed metadata evidence:
  - Job `Build and Upload (Fastlane pr_testflight)` failed at step `Archive/build and upload with Fastlane`.
  - Step `Preflight CI secret presence check` completed successfully.
- Interpretation:
  - PR-trigger path remains active and reaches the Fastlane archive/upload step.
  - Success criteria is still blocked by build/signing execution after preflight.
- Log/metadata captures in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24154242938-metadata.json`
  - Detailed raw step log for this run was not retrievable in this environment without authenticated Actions log download; the latest in-repo detailed log remains `24154089686`.

## CI PR-Triggered Validation After Pushing `e060d80` to PR #26 (Observed)

- PR: https://github.com/thedarkcder/girl-power/pull/26
- Workflow: `PR TestFlight`
- Run ID: `24362649675`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24362649675
- Trigger: `pull_request` synchronize on `feature/GP-186` to `main`
- Commit under test: `e060d801e21bb1d1e0d7262c967f48a62e110b18`
- Run status: `Failure` (duration shown by GitHub UI: `3m 20s`)
- Observed job/step evidence (from job page `71146111358`):
  - Job `Build and Upload (Fastlane pr_testflight)` concluded `failure`.
  - Step `Preflight CI secret presence check` concluded `success`.
  - Step `Archive/build and upload with Fastlane` concluded `failure` (`started_at=2026-04-13T19:29:33Z`, `completed_at=2026-04-13T19:32:31Z`).
  - Steps `Collect logs for diagnostics` and `Upload CI artifacts` both concluded `success`.
- Interpretation:
  - PR-trigger path is still active on the current head commit and advances through CI preflight.
  - Acceptance criteria remains unmet because archive/upload still fails on the live PR-triggered run.
- Log/metadata captures in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24362649675.html`
  - `docs/test-artifacts/GP-186/pr-testflight-run-24362649675-job-71146111358.html`
  - `docs/test-artifacts/GP-186/test-stage-pr-testflight-workflow-runs-live-20260413.json`
  - `docs/test-artifacts/GP-186/test-stage-pr26-run-summary-20260413.json`

## CI Concurrency Guardrail Evidence (Observed)

- Workflow: `PR TestFlight`
- Run ID: `24154059288`
- Run URL: https://github.com/thedarkcder/girl-power/actions/runs/24154059288
- Trigger: `pull_request` synchronize on `feature/GP-186`
- Conclusion: `cancelled`
- Observed marker:
  - `Canceling since a higher priority waiting request for pr-testflight-26 exists`
- Interpretation:
  - Workflow-level concurrency (`pr-testflight-${PR_NUMBER}` with `cancel-in-progress: true`) is operating as configured.
- Log captures in repo:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24154059288.log`
  - `docs/test-artifacts/GP-186/pr-testflight-run-24154059288-metadata.json`

## CI Workflow Status Snapshot (2026-04-13, Authoritative API Pull)

- Snapshot artifact:
  - `docs/test-artifacts/GP-186/pr-testflight-workflow-runs-snapshot-20260413.json`
- Captured at: `2026-04-13T19:14:51Z`
- Observed totals:
  - `totalCount=14`
  - `successCount=0`
- Latest run in workflow history:
  - Run ID: `24359004345`
  - Branch: `feature/GP-125`
  - Conclusion: `failure`
  - Failed step: `Archive/build and upload with Fastlane`
  - Metadata capture: `docs/test-artifacts/GP-186/pr-testflight-run-24359004345-metadata.json`
- Interpretation:
  - There is still no successful `PR TestFlight` run on any active PR path.
  - PR #26 remains unsatisfied on success criteria until a non-dry-run CI run reaches `[PR_TESTFLIGHT][COMPLETE]` with successful archive/upload.
- Supplemental update (`2026-04-13T19:33Z`, public HTML scrape due REST API `403` rate-limit in this environment):
  - Latest PR-26 run is now `24362649675` on commit `e060d80...`, and it also concluded `failure`.
  - Evidence artifacts:
    - `docs/test-artifacts/GP-186/pr-testflight-run-24362649675.html`
    - `docs/test-artifacts/GP-186/pr-testflight-run-24362649675-job-71146111358.html`
    - `docs/test-artifacts/GP-186/test-stage-pr-testflight-workflow-runs-live-20260413.json`

## Dev-Stage Remediation Refresh (2026-04-13, Attempt 5)

### Fastlane fallback hardening checks

- Command: `ruby -c fastlane/Fastfile`
  - Evidence: `docs/test-artifacts/GP-186/dev-stage-fastfile-syntax-20260413.log`
  - Result: `Syntax OK`.
- Command: `bundle exec fastlane lanes`
  - Evidence: `docs/test-artifacts/GP-186/dev-stage-fastlane-lanes-20260413.log`
  - Result: lane inventory includes `ios pr_testflight`.
- Command: dry-run lane with required env names
  - Evidence: `docs/test-artifacts/GP-186/dev-stage-pr-testflight-dry-run-20260413.log`
  - Result markers include:
    - `[PR_TESTFLIGHT][PRECHECK] ... manual_fallback=false ...`
    - `[PR_TESTFLIGHT][COMPLETE] ... signing=automatic`
- Command: dry-run lane with fallback inputs armed
  - Evidence: `docs/test-artifacts/GP-186/dev-stage-pr-testflight-dry-run-fallback-armed-20260413.log`
  - Result markers include:
    - `[PR_TESTFLIGHT][SIGNING] Manual-signing fallback is armed for signing-category archive failures`
    - `[PR_TESTFLIGHT][PRECHECK] ... manual_fallback=true ...`
- Command: missing-auth negative path (omit `APP_STORE_CONNECT_API_KEY_ID`)
  - Evidence: `docs/test-artifacts/GP-186/dev-stage-pr-testflight-missing-auth-20260413.log`
  - Exit code: `docs/test-artifacts/GP-186/dev-stage-missing-auth-exit-code-20260413.txt` (`1`)
  - Marker: `[PR_TESTFLIGHT][FAILED][CATEGORY=auth] Missing required environment variable: APP_STORE_CONNECT_API_KEY_ID`

### CI precheck parity checks (manual-fallback validation)

- Valid input simulation:
  - Evidence: `docs/test-artifacts/GP-186/dev-stage-ci-precheck-valid-20260413.log`
  - Marker: `[CI_PRECHECK] ... manual_fallback=false`
- Invalid partial-fallback simulation (`IOS_PROVISIONING_PROFILE_SPECIFIER` set without `IOS_CODE_SIGN_IDENTITY`):
  - Evidence: `docs/test-artifacts/GP-186/dev-stage-ci-precheck-invalid-20260413.log`
  - Exit code: `docs/test-artifacts/GP-186/dev-stage-ci-precheck-invalid-exit-code-20260413.txt` (`1`)
  - Marker: `::error::When automatic signing fallback inputs are provided, both IOS_PROVISIONING_PROFILE_SPECIFIER and IOS_CODE_SIGN_IDENTITY must be set together.`

### Authoritative metadata refresh

- Snapshot refresh copy:
  - `docs/test-artifacts/GP-186/dev-stage-pr-testflight-workflow-runs-snapshot-20260413.json`
- Metadata refresh command outputs:
  - `docs/test-artifacts/GP-186/dev-stage-metadata-capture-24154242938-20260413.log`
  - `docs/test-artifacts/GP-186/dev-stage-metadata-capture-24154242938-20260413.err`
  - `docs/test-artifacts/GP-186/dev-stage-metadata-capture-24359004345-20260413.log`
  - `docs/test-artifacts/GP-186/dev-stage-metadata-capture-24359004345-20260413.err`

## Test-Stage Validation Refresh (2026-04-13)

### Fastlane lane and state-flow checks

- Command: `bundle exec fastlane lanes`
  - Evidence: `docs/test-artifacts/GP-186/test-stage-fastlane-lanes-20260413.log`
  - Result: lane inventory includes `ios pr_testflight`.
- Command: dry-run lane with required env names
  - Evidence: `docs/test-artifacts/GP-186/test-stage-pr-testflight-dry-run-20260413.log`
  - Result markers:
    - `[PR_TESTFLIGHT][ARCHIVE_BUILD_COMPLETE] dry-run (no archive executed)`
    - `[PR_TESTFLIGHT][TESTFLIGHT_UPLOAD_COMPLETE] dry-run (no upload executed)`
    - `[PR_TESTFLIGHT][COMPLETE] ...`
- Command: dry-run lane with manual-fallback inputs armed
  - Evidence: `docs/test-artifacts/GP-186/test-stage-pr-testflight-dry-run-fallback-armed-20260413.log`
  - Exit code: `docs/test-artifacts/GP-186/test-stage-pr-testflight-dry-run-fallback-armed-exit-20260413.txt` (`0`)
  - Result markers:
    - `[PR_TESTFLIGHT][SIGNING] Manual-signing fallback is armed for signing-category archive failures`
    - `[PR_TESTFLIGHT][PRECHECK] ... manual_fallback=true ...`
    - `[PR_TESTFLIGHT][COMPLETE] ...`
- Command: missing-auth negative path (omit `APP_STORE_CONNECT_API_KEY_ID`)
  - Evidence: `docs/test-artifacts/GP-186/test-stage-pr-testflight-missing-auth-20260413.log`
  - Exit code: `docs/test-artifacts/GP-186/test-stage-pr-testflight-missing-auth-exit-20260413.txt` (`1`)
  - Marker: `[PR_TESTFLIGHT][FAILED][CATEGORY=auth] Missing required environment variable: APP_STORE_CONNECT_API_KEY_ID`

### Workflow parity checks

- CI precheck valid/invalid input simulation:
  - Valid evidence: `docs/test-artifacts/GP-186/test-stage-ci-precheck-valid-20260413.log`
  - Invalid (partial fallback pair) evidence: `docs/test-artifacts/GP-186/test-stage-ci-precheck-invalid-partial-fallback-20260413.log`
  - Invalid exit code: `docs/test-artifacts/GP-186/test-stage-ci-precheck-invalid-partial-fallback-exit-20260413.txt` (`1`)
- Classifier refinement simulation:
  - Evidence: `docs/test-artifacts/GP-186/test-stage-classifier-refinement-20260413.log`
  - Marker: `[PR_TESTFLIGHT][CLASSIFIER] category_refined=build->signing via gym log scan`

### Current authoritative status refresh

- PR-26 run summary refresh:
  - `docs/test-artifacts/GP-186/test-stage-pr26-run-summary-20260413.json`
  - Includes pushed-head run `24362649675` (`head_sha=e060d80...`) with `conclusion=failure`.
- Live run metadata refresh (public HTML scrape):
  - `docs/test-artifacts/GP-186/test-stage-pr-testflight-workflow-runs-live-20260413.json`
  - Captures step-level results for job `71146111358`.
- Run/job capture pages:
  - `docs/test-artifacts/GP-186/pr-testflight-run-24362649675.html`
  - `docs/test-artifacts/GP-186/pr-testflight-run-24362649675-job-71146111358.html`

## Local Lane Evidence (Observed)

Environment used for local validation in this run:
- Timestamp: `2026-04-13`
- Ruby: `ruby` (`2.7.8`)
- Bundler: `2.4.22`

### Local success-path-equivalent (dry run)

Command executed:

```bash
APP_STORE_CONNECT_API_KEY_ID=dummy_key \
APP_STORE_CONNECT_ISSUER_ID=dummy_issuer \
APP_STORE_CONNECT_API_KEY_BASE64=ZHVtbXk= \
APPLE_TEAM_ID=DUMMYTEAMID \
PR_TESTFLIGHT_DRY_RUN=1 \
bundle exec fastlane pr_testflight
```

Observed markers in `local-pr-testflight-dry-run-20260413.log`:
- `[PR_TESTFLIGHT][PRECHECK] ... signing=automatic allow_provisioning_updates=true dry_run=true`
- `[PR_TESTFLIGHT][ARCHIVE_BUILD_COMPLETE] dry-run (no archive executed)`
- `[PR_TESTFLIGHT][TESTFLIGHT_UPLOAD_COMPLETE] dry-run (no upload executed)`
- `[PR_TESTFLIGHT][COMPLETE] version=1.0 build=202604131843 scheme=GirlPower`

### Local failure-path verification

Command executed without `APP_STORE_CONNECT_API_KEY_ID`.

Observed markers in `local-pr-testflight-missing-auth-key-20260413.log`:
- `[PR_TESTFLIGHT][FAILED][CATEGORY=auth] Missing required environment variable: APP_STORE_CONNECT_API_KEY_ID`
- Exit code recorded in `local-missing-auth-exit-code-20260413.txt`: `1`

### Local classifier-refinement verification

Command executed:

```bash
ruby <<'RUBY'
module UI
  def self.important(message)
    puts(message)
  end
  def self.success(_message); end
  def self.message(_message); end
  def self.error(_message); end
  def self.user_error!(message)
    raise(message)
  end
end

def fastlane_version(*); end
def default_platform(*); end
def platform(*); end
def desc(*); end
def lane(*); end

load "fastlane/Fastfile"
category = prtf_refined_error_category(StandardError.new("Error packaging up the application"), fallback: "build")
puts "category=#{category}"
RUBY
```

Fixture source before the command:
- `~/Library/Logs/gym/gp-186/classifier-fixture.log`
  - `error: exportArchive Cloud signing permission error`
  - `error: exportArchive No profiles for 'com.route25.GirlPower' were found`

Observed markers in `local-classifier-refinement-20260413.log`:
- `[PR_TESTFLIGHT][CLASSIFIER] category_refined=build->signing via gym log scan`
- `category=signing`

### Local Xcode project metadata verification

Command executed:

```bash
xcodebuild -list -project GirlPower.xcodeproj
```

Observed output markers in `local-xcodebuild-list-20260413.log`:
- Target list includes `GirlPower`, `GirlPowerTests`, `GirlPowerUITests`
- Scheme list includes `GirlPower`

### Local lane inventory verification

Command executed:

```bash
bundle exec fastlane lanes
```

Observed output markers in `local-fastlane-lanes-20260413.log`:
- `fastlane ios pr_testflight`

## Local Artifacts Produced

- `docs/test-artifacts/GP-186/local-bundle-install-20260413.log`
- `docs/test-artifacts/GP-186/local-classifier-refinement-20260413.log`
- `docs/test-artifacts/GP-186/local-fastlane-lanes-20260413.log`
- `docs/test-artifacts/GP-186/local-pr-testflight-dry-run-20260413.log`
- `docs/test-artifacts/GP-186/local-pr-testflight-missing-auth-key-20260413.log`
- `docs/test-artifacts/GP-186/local-missing-auth-exit-code-20260413.txt`
- `docs/test-artifacts/GP-186/local-xcodebuild-list-20260413.log`
- `docs/test-artifacts/GP-186/local-bundle-install-ruby27.log`
- `docs/test-artifacts/GP-186/local-pr-testflight-dry-run-ruby27.log`
- `docs/test-artifacts/GP-186/local-pr-testflight-missing-auth-key-ruby27.log`
- `docs/test-artifacts/GP-186/local-missing-auth-exit-code-ruby27.txt`
- `docs/test-artifacts/GP-186/pr-testflight-run-24149572001.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24152730438.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24152730438-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24152908095.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24152908095-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24153142991.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24153142991-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24153241603.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24153241603-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24153766410.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24153766410-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24153956396.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24153956396-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24154059288.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24154059288-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24154089686.log`
- `docs/test-artifacts/GP-186/pr-testflight-run-24154089686-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24154242938-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24359004345-metadata.json`
- `docs/test-artifacts/GP-186/pr-testflight-workflow-runs-snapshot-20260413.json`
- `docs/test-artifacts/GP-186/dev-stage-bundle-install-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-fastfile-syntax-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-fastlane-lanes-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-pr-testflight-dry-run-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-pr-testflight-dry-run-fallback-armed-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-pr-testflight-missing-auth-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-missing-auth-exit-code-20260413.txt`
- `docs/test-artifacts/GP-186/dev-stage-ci-precheck-valid-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-ci-precheck-invalid-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-ci-precheck-invalid-exit-code-20260413.txt`
- `docs/test-artifacts/GP-186/dev-stage-metadata-capture-24154242938-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-metadata-capture-24154242938-20260413.err`
- `docs/test-artifacts/GP-186/dev-stage-metadata-capture-24359004345-20260413.log`
- `docs/test-artifacts/GP-186/dev-stage-metadata-capture-24359004345-20260413.err`
- `docs/test-artifacts/GP-186/dev-stage-pr-testflight-workflow-runs-snapshot-20260413.json`
- `docs/test-artifacts/GP-186/test-stage-bundle-install-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-fastlane-lanes-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-pr-testflight-dry-run-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-pr-testflight-dry-run-fallback-armed-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-pr-testflight-dry-run-fallback-armed-exit-20260413.txt`
- `docs/test-artifacts/GP-186/test-stage-pr-testflight-missing-auth-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-missing-auth-exit-code-20260413.txt`
- `docs/test-artifacts/GP-186/test-stage-pr-testflight-missing-auth-exit-20260413.txt`
- `docs/test-artifacts/GP-186/test-stage-ci-precheck-valid-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-ci-precheck-valid-exit-20260413.txt`
- `docs/test-artifacts/GP-186/test-stage-ci-precheck-invalid-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-ci-precheck-invalid-exit-code-20260413.txt`
- `docs/test-artifacts/GP-186/test-stage-ci-precheck-invalid-partial-fallback-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-ci-precheck-invalid-partial-fallback-exit-20260413.txt`
- `docs/test-artifacts/GP-186/test-stage-classifier-refinement-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-xcodebuild-list-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-metadata-capture-24359004345-20260413.log`
- `docs/test-artifacts/GP-186/test-stage-metadata-capture-24359004345-20260413.err`
- `docs/test-artifacts/GP-186/test-stage-pr-testflight-workflow-runs-snapshot-20260413.json`
- `docs/test-artifacts/GP-186/test-stage-pr-testflight-workflow-runs-live-20260413.json`
- `docs/test-artifacts/GP-186/test-stage-pr26-run-summary-20260413.json`
- `docs/test-artifacts/GP-186/pr-testflight-run-24362649675.html`
- `docs/test-artifacts/GP-186/pr-testflight-run-24362649675-job-71146111358.html`
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
- Workflow-level status snapshot (`pr-testflight-workflow-runs-snapshot-20260413.json`) confirms `successCount=0` across recorded `PR TestFlight` runs as of `2026-04-13T19:14:51Z`.
- Fresh PR-26 run after pushing `feature/GP-186` head `e060d80`:
  - Run `24362649675` (triggered `2026-04-13T19:29:17Z`) concluded `failure`.
  - Step-level outcome from job `71146111358`:
    - `Preflight CI secret presence check` -> `success`
    - `Archive/build and upload with Fastlane` -> `failure`
    - `Collect logs for diagnostics` -> `success`
    - `Upload CI artifacts` -> `success`
- Current blocker from latest PR-26 run (`24362649675`):
  - Step-level failure at `Archive/build and upload with Fastlane` after preflight checks pass.
  - Latest detailed in-repo marker set with category text remains `24154089686` (new run logs require authenticated download):
    - `[PR_TESTFLIGHT][FAILED][CATEGORY=build] Archive/build failed: Error packaging up the application`
    - `error: exportArchive Cloud signing permission error`
    - `error: exportArchive No profiles for 'com.route25.GirlPower' were found`
- Expected marker behavior on the next PR-triggered run after this remediation:
  - Cloud-signing/profile failures above should classify as `[CATEGORY=signing]` for direct triage routing.
  - When gym returns a generic archive exception, lane should emit:
    - `[PR_TESTFLIGHT][CLASSIFIER] category_refined=build->signing via gym log scan`
  - If manual-signing fallback inputs are configured, lane should emit:
    - `[PR_TESTFLIGHT][SIGNING][FALLBACK] Automatic signing failed with category=signing; retrying archive with manual inputs`
    - `[PR_TESTFLIGHT][SIGNING][FALLBACK] Archive succeeded using manual-signing fallback` (success case)
- Next required remediation: configure account-side signing/upload capability so PR #26 can complete one non-dry-run run with `[PR_TESTFLIGHT][COMPLETE]` (or upload the run artifact logs for `24362649675` to confirm the exact terminal Fastlane category in this attempt).
