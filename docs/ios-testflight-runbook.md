# iOS TestFlight Runbook (`pr_testflight`)

This repository ships one iOS deployment lane: `pr_testflight`.

The lane executes an explicit state flow:
1. `preflight_validation`
2. `version_build_prep`
3. `archive_build`
4. `upload_testflight`
5. `completion`

Any failure exits non-zero and logs a category marker: `auth`, `signing`, `build`, or `upload`.

## Prerequisites

1. Xcode command line tooling installed (`xcodebuild` available).
2. Ruby + Bundler installed.
3. Code-signing assets present on the machine (certificate/profile) for the selected signing mode.

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
| `IOS_XCODEPROJ` | `GirlPower.xcodeproj` | Xcode project path. |
| `IOS_SCHEME` | `GirlPower` | Build scheme. |
| `IOS_APP_IDENTIFIER` | `com.route25.GirlPower` | App bundle identifier. |
| `IOS_EXPORT_METHOD` | `app-store` | Export method passed to `gym`. |
| `IOS_MARKETING_VERSION` | project value | Override marketing version. |
| `IOS_BUILD_NUMBER` | UTC timestamp (`%Y%m%d%H%M`) | Override build number. |
| `PR_TESTFLIGHT_DRY_RUN` | unset | Set to `1` to skip archive/upload while validating lane wiring/log signatures. |

## Local Invocation

```bash
bundle install
bundle exec fastlane pr_testflight
```

## CI Invocation

Inject required variables through CI secrets, then run:

```bash
bundle install --path vendor/bundle
bundle exec fastlane pr_testflight
```

## Expected Success Log Signatures

- `[PR_TESTFLIGHT][ARCHIVE_BUILD_COMPLETE] ...`
- `[PR_TESTFLIGHT][TESTFLIGHT_UPLOAD_COMPLETE] ...`

## Failure Category Signatures

- `[PR_TESTFLIGHT][FAILED][CATEGORY=auth] ...`
- `[PR_TESTFLIGHT][FAILED][CATEGORY=signing] ...`
- `[PR_TESTFLIGHT][FAILED][CATEGORY=build] ...`
- `[PR_TESTFLIGHT][FAILED][CATEGORY=upload] ...`

## Triage Guide

- `auth`: verify API key ID/issuer/key content and key validity.
- `signing`: verify team ID, signing style, certs, and provisioning profile mapping.
- `build`: inspect `xcodebuild` compile/archive output.
- `upload`: inspect `pilot`/transporter output and App Store Connect status.
