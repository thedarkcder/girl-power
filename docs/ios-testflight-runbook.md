# iOS TestFlight Runbook (`pr_testflight`)

This repository ships one iOS deployment lane: `pr_testflight`.

## Canonical Command (Lane Name Reconciliation)

Use this command locally and in CI:

```bash
bundle exec fastlane pr_testflight
```

Do not use `bundle exec fastlane ios pr_build`; there is no `pr_build` lane in [`fastlane/Fastfile`](../fastlane/Fastfile).

The lane executes an explicit state flow:
1. `preflight_validation`
2. `version_build_prep`
3. `archive_build`
4. `upload_testflight`
5. `completion`

Any failure exits non-zero and emits a Fastlane category marker: `auth`, `signing`, `build`, or `upload`.

## Prerequisites

1. Xcode command line tooling installed (`xcodebuild` available).
2. Ruby and Bundler installed.
3. Code-signing assets present on the machine for your signing mode.
4. App Store Connect API key material available to your local shell and CI secrets.

### Local Setup

1. Install gems:

```bash
bundle install --path vendor/bundle
```

2. Export required environment variables (example values shown as placeholders):

```bash
export APP_STORE_CONNECT_API_KEY_ID="<key-id>"
export APP_STORE_CONNECT_ISSUER_ID="<issuer-id>"
export APP_STORE_CONNECT_API_KEY_BASE64="<base64-p8-content>"
export APPLE_TEAM_ID="<apple-team-id>"
# Optional: export IOS_SIGNING_STYLE=automatic|manual
# Optional: export IOS_ALLOW_PROVISIONING_UPDATES=1
```

3. Optional dry-run validation (keeps state flow/log markers, skips archive + upload):

```bash
export PR_TESTFLIGHT_DRY_RUN=1
bundle exec fastlane pr_testflight
```

## Required Environment Variables

| Variable | Required | Description |
| --- | --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | Yes | App Store Connect API key ID. |
| `APP_STORE_CONNECT_ISSUER_ID` | Yes | App Store Connect issuer ID. |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Yes | Base64-encoded `.p8` key content. |
| `APPLE_TEAM_ID` | Yes | Apple Developer team ID used for signing. |
| `IOS_SIGNING_STYLE` | No (defaults `automatic`) | `automatic` or `manual`. |
| `IOS_PROVISIONING_PROFILE_SPECIFIER` | Manual only | Provisioning profile name/specifier for manual signing. |
| `IOS_CODE_SIGN_IDENTITY` | Manual only | Signing identity for manual signing. |

## Optional Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `APP_STORE_CONNECT_TEAM_ID` | unset | Optional App Store Connect team ID for multi-team accounts. |
| `IOS_XCODEPROJ` | `GirlPower.xcodeproj` | Xcode project path. |
| `IOS_SCHEME` | `GirlPower` | Build scheme. |
| `IOS_APP_IDENTIFIER` | `com.route25.GirlPower` | App bundle identifier. |
| `IOS_EXPORT_METHOD` | `app-store` | Export method passed to `gym`. |
| `IOS_ALLOW_PROVISIONING_UPDATES` | `1` | When `automatic` signing is active, pass `-allowProvisioningUpdates` (plus App Store Connect auth-key flags) to `xcodebuild`. Set to `0` to disable. |
| `IOS_MARKETING_VERSION` | project value | Override marketing version. |
| `IOS_BUILD_NUMBER` | UTC timestamp (`%Y%m%d%H%M`) | Override build number. |
| `PR_TESTFLIGHT_DRY_RUN` | unset | Set to `1` to skip archive/upload while validating lane wiring/log signatures. |

## Local Invocation

```bash
bundle install --path vendor/bundle
bundle exec fastlane pr_testflight
```

## CI Invocation

Workflow file: `.github/workflows/pr-testflight.yml`

CI lane execution step:

```bash
bundle config set path vendor/bundle
bundle install --jobs 4 --retry 3
bundle exec fastlane pr_testflight | tee ci-artifacts/logs/fastlane-pr-testflight.log
```

When `IOS_SIGNING_STYLE=automatic`, the lane appends `-allowProvisioningUpdates` and App Store Connect auth-key flags (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`) to the archive build to allow CI profile generation.

### Required CI Secret/Variable Keys

Configure the following repository-level CI values before non-dry-run uploads:

| Key | Source | Required | Description |
| --- | --- | --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | Secret | Yes | App Store Connect API key ID. |
| `APP_STORE_CONNECT_ISSUER_ID` | Secret | Yes | App Store Connect issuer ID. |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Secret | Yes | Base64-encoded App Store Connect `.p8` content. |
| `APPLE_TEAM_ID` | Secret | Yes | Apple Developer Team ID used for signing. |
| `IOS_SIGNING_STYLE` | Variable | No (defaults `automatic`) | `automatic` or `manual`. |
| `IOS_ALLOW_PROVISIONING_UPDATES` | Variable | No (defaults `1`) | Enables/disables automatic provisioning updates for `xcodebuild` when signing style is `automatic`. |
| `IOS_PROVISIONING_PROFILE_SPECIFIER` | Secret | Manual only | Provisioning profile specifier for manual signing. |
| `IOS_CODE_SIGN_IDENTITY` | Secret | Manual only | Code signing identity for manual signing. |
| `APP_STORE_CONNECT_TEAM_ID` | Secret | No | Optional App Store Connect team ID for multi-team accounts. |

The workflow has a preflight shell check that fails fast when required CI key names are missing.

`APP_STORE_CONNECT_API_KEY_BASE64` should contain base64-encoded `.p8` contents. The lane now retries raw-PEM interpretation on null-byte parse failures, but canonical configuration remains base64. Example (macOS):

```bash
base64 -i AuthKey_XXXXXX.p8 | tr -d '\n'
```

## GitHub PR Workflow Behavior (Exact)

The workflow behavior below matches `.github/workflows/pr-testflight.yml` exactly:

- Event: `pull_request`
- PR event types: `opened`, `synchronize`, `reopened`, `ready_for_review`
- Base-branch filter: `main`
- Path filters:
  - `.github/workflows/pr-testflight.yml`
  - `fastlane/**`
  - `Gemfile`
  - `Gemfile.lock`
  - `GirlPower/**`
  - `GirlPower.xcodeproj/**`
  - `docs/ios-testflight-runbook.md`
- Draft PR guard: job runs only when `!github.event.pull_request.draft`
- Runner: `macos-latest`
- Concurrency: `group: pr-testflight-${{ github.event.pull_request.number }}`
- Concurrency cancellation: `cancel-in-progress: true`
- Artifact upload: `pr-testflight-${{ github.event.pull_request.number }}-${{ github.run_id }}`
- Artifact retention: `retention-days: 14`

## Log Markers and Artifact Paths

### Expected success markers (Fastlane lane output)

- `[PR_TESTFLIGHT][ARCHIVE_BUILD_COMPLETE] ...`
- `[PR_TESTFLIGHT][TESTFLIGHT_UPLOAD_COMPLETE] ...`
- `[PR_TESTFLIGHT][COMPLETE] version=<...> build=<...> scheme=<...>`

### Failure category markers (Fastlane lane output)

- `[PR_TESTFLIGHT][FAILED][CATEGORY=auth] ...`
- `[PR_TESTFLIGHT][FAILED][CATEGORY=signing] ...`
- `[PR_TESTFLIGHT][FAILED][CATEGORY=build] ...`
- `[PR_TESTFLIGHT][FAILED][CATEGORY=upload] ...`

### CI artifact and log retrieval paths

For each CI run, download artifact `pr-testflight-<PR_NUMBER>-<RUN_ID>` from GitHub Actions and inspect:

- `ci-artifacts/logs/fastlane-pr-testflight.log`
- `ci-artifacts/fastlane/report.xml` (when present)
- `ci-artifacts/fastlane/gym-logs/*` (when present)
- `ci-artifacts/logs/build-files.txt` (when build outputs exist)

## Triage Guide

- `auth`: verify API key ID, issuer ID, and key content are configured and valid.
- `auth` null-byte preflight error (`Preflight failed: string contains null byte`): secret value is usually malformed base64. Recreate `APP_STORE_CONNECT_API_KEY_BASE64` as single-line base64 of the `.p8` file.
- `signing`: verify team ID, signing style, certs, and provisioning profile mapping.
- `signing` invalid-style error (`IOS_SIGNING_STYLE must be either 'automatic' or 'manual'`): if GitHub variable is unset/blank, ensure lane normalizes blank to `automatic` or set repository variable `IOS_SIGNING_STYLE=automatic`.
- `build`: inspect `xcodebuild` compile/archive output in Fastlane and gym logs.
- `build` provisioning-profile error (`No profiles for 'com.route25.GirlPower' were found`): verify automatic provisioning is enabled (`IOS_ALLOW_PROVISIONING_UPDATES` not set to `0`) and App Store Connect key values are valid. If CI still cannot provision profiles, configure manual-signing secrets (`IOS_PROVISIONING_PROFILE_SPECIFIER`, `IOS_CODE_SIGN_IDENTITY`) with matching certificate/profile assets.
- `upload`: inspect `pilot`/transporter output and App Store Connect processing state.
- CI preflight secret-name failure (before Fastlane lane starts): look for `Missing required CI secret/env keys: ...` in the `Preflight CI secret presence check` step.

## Rollback / Pause / Re-enable Playbook

### Pause PR TestFlight for one PR

1. Convert the PR to draft.
2. Push updates as needed.
3. Mark the PR as ready for review when you want CI delivery to resume.

Reason: the job guard `if: ${{ !github.event.pull_request.draft }}` skips deployment for drafts without changing workflow code.

### Pause PR TestFlight repo-wide

Option A (UI):
1. Open GitHub Actions -> `PR TestFlight` workflow.
2. Click `Disable workflow`.

Option B (`gh` CLI):

```bash
gh workflow disable pr-testflight.yml --repo thedarkcder/girl-power
```

### Re-enable PR TestFlight repo-wide

Option A (UI): click `Enable workflow` in GitHub Actions.

Option B (`gh` CLI):

```bash
gh workflow enable pr-testflight.yml --repo thedarkcder/girl-power
```

## Dependencies / Risks

### Dependencies

- Fastlane lane definition in `fastlane/Fastfile` (`pr_testflight`).
- GitHub Actions workflow `.github/workflows/pr-testflight.yml`.
- App Store Connect API key + issuer + key content secrets.
- Apple code-signing assets and team configuration.

### Operational risks and mitigations

- Risk: missing CI secret names causes immediate preflight failure.
  - Mitigation: keep required key list synchronized with workflow `env` and preflight check.
- Risk: manual-signing mismatch (`IOS_SIGNING_STYLE=manual` without profile/identity) fails signing preflight.
  - Mitigation: set `IOS_PROVISIONING_PROFILE_SPECIFIER` and `IOS_CODE_SIGN_IDENTITY` together.
- Risk: automatic provisioning requires App Store Connect key permissions capable of profile operations.
  - Mitigation: use an API key with sufficient role and keep `IOS_ALLOW_PROVISIONING_UPDATES=1` for automatic path.
- Risk: repeated pushes create concurrent redundant runs.
  - Mitigation: workflow-level `concurrency` with `cancel-in-progress: true`.
- Risk: PR unintentionally uploads while still under review.
  - Mitigation: draft PR state suppresses job execution until ready.

## Verification Evidence

See [`docs/test-artifacts/GP-186/README.md`](test-artifacts/GP-186/README.md) for run IDs, timestamps, local command evidence, and CI references.
