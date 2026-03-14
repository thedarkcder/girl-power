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
   supabase functions serve evaluate-session --env-file supabase/functions/.env.local
   supabase functions serve demo-session-log --env-file supabase/functions/.env.local
   supabase functions serve demo-snapshot-fetch --env-file supabase/functions/.env.local
   supabase functions serve demo-snapshot-mirror --env-file supabase/functions/.env.local
   ```
2. Export environment variables so the app uses Supabase mode:
   ```sh
   export DEMO_QUOTA_MODE=supabase
   export DEMO_QUOTA_SESSION_LOGGER_URL="http://127.0.0.1:54321/functions/v1/demo-session-log"
   export DEMO_QUOTA_EVALUATE_SESSION_URL="http://127.0.0.1:54321/functions/v1/evaluate-session"
   export DEMO_QUOTA_SNAPSHOT_FETCH_URL="http://127.0.0.1:54321/functions/v1/demo-snapshot-fetch"
   export DEMO_QUOTA_SNAPSHOT_MIRROR_URL="http://127.0.0.1:54321/functions/v1/demo-snapshot-mirror"
   export DEMO_QUOTA_ANON_KEY="<your supabase anon key>"
   ```
3. Validate the server contract before launching the app:
   ```sh
   curl -s \
     -H "Authorization: Bearer $DEMO_QUOTA_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{"device_id":"11111111-1111-1111-1111-111111111111","attempt_index":1,"stage":"completion","metadata":{"source":"qa"}}' \
     http://127.0.0.1:54321/functions/v1/demo-session-log | jq

   curl -s \
     -H "Authorization: Bearer $DEMO_QUOTA_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{"device_id":"11111111-1111-1111-1111-111111111111","attempt_index":1,"payload_version":"v1","input":{"prompt":"Decide whether a second demo is allowed.","context":{"source":"qa"}},"metadata":{"source":"qa"}}' \
     http://127.0.0.1:54321/functions/v1/evaluate-session | jq
   ```
   - Expect `allow_another_demo=true`, `attempts_used=1`, and a mirrored snapshot whose `last_decision.type` is `allow`.
4. Install/run the simulator build (clean install to exercise keychain provisioning). Observe:
   - Attempt #1 tap logs `stage=start` with metadata (check Supabase table or `supabase functions logs --function demo-session-log`).
   - Completing attempt #1 logs `stage=complete`, UI returns to CTA with “Checking eligibility…” and CTA disabled.
   - Edge Function receives exactly one evaluate-session call with the device_id/metadata payload.
5. When evaluate-session returns `allow_another_demo=true`, the CTA switches to “One more go”, metadata includes `cta_label = "One more go"`, and another tap starts attempt #2. Completion logs are written and the CTA locks with “You’ve used both free demos…”.
6. Force a deny/timeout path:
   - Stop the `evaluate-session` function or have it return `{ "allow_another_demo": false, "message": "custom message" }`.
   - After attempt #1 completion the CTA should immediately show the deny/timeout copy and never present a second attempt.
7. Validate third-attempt blocking from the server after attempt #2:
   ```sh
   curl -s \
     -H "Authorization: Bearer $DEMO_QUOTA_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{"device_id":"11111111-1111-1111-1111-111111111111","attempt_index":2,"stage":"completion","metadata":{"source":"qa"}}' \
     http://127.0.0.1:54321/functions/v1/demo-session-log | jq

   curl -s \
     -H "Authorization: Bearer $DEMO_QUOTA_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{"device_id":"11111111-1111-1111-1111-111111111111"}' \
     http://127.0.0.1:54321/functions/v1/demo-snapshot-fetch | jq
   ```
   - Expect `attempts_used=2`, `server_lock_reason="quota"`, and no path back to `secondAttemptEligible`.
8. Delete and reinstall the app only if you are validating keychain continuity on the same simulator profile. The supported continuity model is the persisted keychain-backed `device_id`; if the keychain entry is removed, GP-115 now treats the install as a new local identity instead of attempting lookup-key recovery.
9. Record manual notes in Jira (build hash, simulator version, key device_id) plus any cURL scripts used to seed Supabase so reviewers can replay the scenario.

## GP-116 Summary + Paywall Flow

1. Launch the demo and complete at least one valid rep, then tap **Complete Set**.
   - Expect the Squat Post-Set Summary view to appear automatically with reps, tempo insight, and any coaching notes populated.
2. While DemoQuotaStateMachine = `.gatePending`, verify the summary CTA shows “Checking eligibility…” and the primary CTA is disabled.
3. Simulate `.secondAttemptEligible` (allow response) and confirm the primary CTA switches to “One more go”, secondary CTA reads “Continue to Paywall”, and tapping One more go starts attempt #2 with a fresh SquatSessionCoordinator.
4. Complete attempt #2 and confirm the summary only shows “Continue to Paywall” (no secondary button). Tapping it should clear the navigation stack and display the paywall placeholder without exposing any path back into SquatSessionView.
5. Relaunch the app; ensure the summary cache is cleared, DemoCTA respects the locked quota state, and the user cannot start a third attempt.
6. Force a denied/timeout path (e.g., return `{ "allow_another_demo": false, "message": "custom message" }` from `evaluate-session`) and verify the summary immediately switches to the locked message with only the Continue to Paywall CTA available.
7. During both flows, tail `supabase functions logs --function demo-session-log` (or watch Xcode os_log output) to ensure attempt start/completion and evaluation events emit exactly once; any duplication indicates a routing race that must be investigated.

## GP-117 StoreKit Paywall + Entitlements

1. Associate the StoreKit configuration with the GirlPower scheme:
   - In Xcode > **Product** > **Scheme** > **Edit Scheme** > **Run** > **Options**, set *StoreKit Configuration* to `GirlPower/StoreKit/Products.storekit`.
   - The config defines `com.girlpower.app.pro.monthly`; Sandbox testers must be signed in under Settings → App Store → Sandbox Account.
2. Run the new targeted entitlement + paywall tests prior to manual QA:
   ```sh
   xcodebuild test \
     -scheme GirlPower \
     -destination 'platform=iOS Simulator,name=iPhone 15' \
     -only-testing:GirlPowerTests/EntitlementStateMachineTests \
     -only-testing:GirlPowerTests/PaywallViewModelTests \
     -only-testing:GirlPowerTests/AppFlowViewModelProTests
   ```
3. Launch the app fresh (no subscription) and route to the paywall via the demo summary.
   - Confirm the price string matches the localized value from StoreKit (no hard-coded currency), feature bullets render, and Privacy/Terms links open in Safari.
4. Tap **Subscribe** while logged into the sandbox account, complete the subscription sheet, and verify within the same run:
   - The paywall shows the success banner momentarily then dismisses automatically.
   - `DemoCTAView` button text switches to “Start Coaching” and remains enabled across repeated sessions without DemoQuota blocking.
   - Post-set summary CTA becomes “Start Coaching” (no paywall secondary action) and locked states never reappear while the entitlement stays active.
5. Test the **Restore Purchases** flow:
   - With an active sandbox subscription, delete/reinstall the app, sign back into the sandbox account, and tap Restore to regain `isPro` without hitting the paywall.
   - Sign out (or use a fresh simulator) without an active subscription and tap Restore; expect an inline error message and no crashes.
6. Validate non-subscribed behavior:
   - Without a subscription, complete two demo attempts to confirm DemoQuota still locks at two and routes to the paywall.
   - Ensure tapping **Subscribe** while offline/error triggers the inline error banner but leaves buttons usable after hitting **Try again** or reloading.
