# How to Test Girl Power App Flow

1. Build the app target:
   ```sh
   xcodebuild -scheme GirlPower -destination 'platform=iOS Simulator,name=iPhone 15' build
   ```
2. Run targeted regression tests for the state machine invariants:
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:GirlPowerTests/AppFlowStateMachineTests
   ```
3. Run demo quota unit tests:
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:GirlPowerTests/DemoQuotaCoordinatorTests
   ```
4. Run the full test suite (unit + UI tests):
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,name=iPhone 15'
   ```
5. Launch the app on the simulator:
   - First launch should show the splash, onboarding carousel (three slides), CTA, then demo stub.
   - Relaunching after completing onboarding should land directly on the CTA screen.
    - Launch with `-resetOnboarding` to force onboarding, `-returningUser` to verify skip logic.

## Demo quota gating checklist (GP-115)

1. Start Supabase locally:
   ```sh
   supabase start
   supabase functions serve evaluate-session
   ```
2. Export environment variables so the app uses Supabase mode:
   ```sh
   export DEMO_QUOTA_MODE=supabase
   export DEMO_QUOTA_SESSION_LOGGER_URL="http://127.0.0.1:54321/functions/v1/demo-session-log"
   export DEMO_QUOTA_EVALUATE_SESSION_URL="http://127.0.0.1:54321/functions/v1/evaluate-session"
   export DEMO_QUOTA_SNAPSHOT_FETCH_URL="http://127.0.0.1:54321/functions/v1/demo-snapshot-fetch"
   export DEMO_QUOTA_SNAPSHOT_MIRROR_URL="http://127.0.0.1:54321/functions/v1/demo-snapshot-mirror"
   export DEMO_QUOTA_IDENTITY_FETCH_URL="http://127.0.0.1:54321/functions/v1/demo-identity-fetch"
   export DEMO_QUOTA_IDENTITY_MIRROR_URL="http://127.0.0.1:54321/functions/v1/demo-identity-mirror"
   export DEMO_QUOTA_ANON_KEY="<your supabase anon key>"
   ```
3. Install/run the simulator build (clean install to exercise keychain provisioning). Observe:
   - Attempt #1 tap logs `stage=start` with metadata (check Supabase table or `supabase functions logs --function demo-session-log`).
   - Completing attempt #1 logs `stage=complete`, UI returns to CTA with “Checking eligibility…” and CTA disabled.
   - Edge Function receives exactly one evaluate-session call with the device_id/metadata payload.
4. When evaluate-session returns `allowAnotherDemo=true`, the CTA switches to “One more go”, metadata includes `cta_label = "One more go"`, and another tap starts attempt #2. Completion logs are written and the CTA locks with “You’ve used both free demos…”.
5. Force a deny/timeout path:
   - Stop the `evaluate-session` function or have it return `{ allowAnotherDemo: false, message: "custom message" }`.
   - After attempt #1 completion the CTA should immediately show the deny/timeout copy and never present a second attempt.
6. Delete the app (or run on a new simulator), relaunch, and verify the quota remains locked because the keychain + Supabase snapshot rehydrate the state.
7. Record manual notes in Jira (build hash, simulator version, key device_id) plus any cURL scripts used to seed Supabase so reviewers can replay the scenario.
