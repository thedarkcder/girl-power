# How to Test Girl Power App Flow

Use the shared `GirlPower` scheme with the explicit simulator destination `platform=iOS Simulator,OS=17.0.1,name=iPhone 15 Pro`. The shared scheme does not persist a simulator choice, so all `xcodebuild` examples below include the required `-destination` flag.

1. Build the app target:
   ```sh
   xcodebuild -scheme GirlPower -destination 'platform=iOS Simulator,OS=17.0.1,name=iPhone 15 Pro' build
   ```
2. Run targeted regression tests for the state machine invariants:
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,OS=17.0.1,name=iPhone 15 Pro' -only-testing:GirlPowerTests/AppFlowStateMachineTests
   ```
3. Run demo quota unit tests:
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,OS=17.0.1,name=iPhone 15 Pro' -only-testing:GirlPowerTests/DemoQuotaCoordinatorTests
   ```
4. Run the full test suite (unit + UI tests):
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,OS=17.0.1,name=iPhone 15 Pro'
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
   - Expect `decision.outcome = "allow"` for the allow path.
   - `demo-session-log` should reject `attempt_index=3` with `400 invalid_body`; `evaluate-session` should reject any `attempt_index` other than `1` with the same boundary error.
4. Install/run the simulator build. Observe:
   - Attempt #1 tap logs `stage=start` with metadata (check Supabase table or `supabase functions logs --function demo-session-log`).
   - Completing attempt #1 logs `stage=complete`, UI returns to CTA with “Checking eligibility…” and CTA disabled.
   - Edge Function receives exactly one evaluate-session call with the canonical `device_id`, `input.context`, and top-level `metadata` payload.
5. When evaluate-session returns `decision.outcome = "allow"`, the CTA switches to “One more go”, metadata includes `cta_label = "One more go"`, and another tap starts attempt #2. Completion logs are written and the CTA locks with “You’ve used both free demos…”.
6. Force a deny/timeout path:
   - Stop the `evaluate-session` function or have it return `{"decision":{"outcome":"deny","message":"custom message"}}`.
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
8. Cold-launch the app again without deleting its keychain identity and verify the quota remains locked because the same keychain-backed `device_id` can rehydrate the mirrored snapshot.
   - Do not treat full uninstall/reinstall as deterministic recovery; that contract is intentionally unsupported in GP-115.
9. Record manual notes in Jira (build hash, simulator version, key device_id) plus any cURL scripts used to seed Supabase so reviewers can replay the scenario.

## GP-116 Summary + Paywall Flow

1. Launch the demo and complete at least one valid rep, then tap **Complete Set**.
   - Expect the Squat Post-Set Summary view to appear automatically with reps, tempo insight, and any coaching notes populated.
2. While DemoQuotaStateMachine = `.gatePending`, verify the summary CTA shows “Checking eligibility…” and the primary CTA is disabled.
3. Simulate `.secondAttemptEligible` (allow response) and confirm the primary CTA switches to “One more go”, secondary CTA reads “Continue to Paywall”, and tapping One more go starts attempt #2 with a fresh SquatSessionCoordinator.
4. Complete attempt #2 and confirm the summary only shows “Continue to Paywall” (no secondary button). Tapping it should clear the navigation stack and display the paywall placeholder without exposing any path back into SquatSessionView.
5. Relaunch the app; ensure the summary cache is cleared, DemoCTA respects the locked quota state, and the user cannot start a third attempt.
6. Force a denied/timeout path (e.g., return `{"decision":{"outcome":"deny","message":"custom message"}}` from `evaluate-session`) and verify the summary immediately switches to the locked message with only the Continue to Paywall CTA available.
7. During both flows, tail `supabase functions logs --function demo-session-log` (or watch Xcode os_log output) to ensure attempt start/completion and evaluation events emit exactly once; any duplication indicates a routing race that must be investigated.

## GP-117 StoreKit Paywall + Entitlements

1. Associate the StoreKit configuration with the GirlPower scheme:
   - In Xcode > **Product** > **Scheme** > **Edit Scheme** > **Run** > **Options**, set *StoreKit Configuration* to `GirlPower/StoreKit/Products.storekit`.
   - The config defines `com.girlpower.app.pro.monthly`; Sandbox testers must be signed in under Settings → App Store → Sandbox Account.
2. Run the new targeted entitlement + paywall tests prior to manual QA:
   ```sh
   xcodebuild test \
     -scheme GirlPower \
     -destination 'platform=iOS Simulator,OS=17.0.1,name=iPhone 15 Pro' \
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

## GP-122 Auth Gate Regression

1. Run the targeted auth/app-flow regressions:
   ```sh
   xcodebuild test \
     -scheme GirlPower \
     -destination 'platform=iOS Simulator,OS=17.0.1,name=iPhone 15 Pro' \
     -only-testing:GirlPowerTests/AuthSystemTests \
     -only-testing:GirlPowerTests/AppFlowViewModelProTests
   ```
2. Verify the build-specific auth metadata resolves as expected:
   ```sh
   xcodebuild -scheme GirlPower -showBuildSettings -configuration Debug | rg 'PRODUCT_BUNDLE_IDENTIFIER|SUPABASE_CALLBACK_SCHEME|SUPABASE_AUTH_REDIRECT_URL|SUPABASE_APPLE_SERVICE_ID|SUPABASE_PROJECT_URL|CODE_SIGN_ENTITLEMENTS'
   xcodebuild -scheme GirlPower -showBuildSettings -configuration Release | rg 'PRODUCT_BUNDLE_IDENTIFIER|SUPABASE_CALLBACK_SCHEME|SUPABASE_AUTH_REDIRECT_URL|SUPABASE_APPLE_SERVICE_ID|SUPABASE_PROJECT_URL|CODE_SIGN_ENTITLEMENTS'
   ```
   - Debug should resolve to `com.route25.GirlPower`, `girlpower`, `girlpower://auth/callback`, and `com.route25.GirlPower.auth`.
   - Release should resolve to `com.route25.GirlPower`, `girlpower`, `girlpower://auth/callback`, and `com.route25.GirlPower.auth`.
   - Confirm the signed app target still reports `CODE_SIGN_ENTITLEMENTS = GirlPower/GirlPower.entitlements`.
3. Run the edge-function regression checks:
   ```sh
   cd supabase/functions
   deno lint link-anonymous-session
   deno test link-anonymous-session/linker.test.ts
   ```
4. Verify the local Supabase Apple configuration stays local-first:
   ```sh
   supabase start
   supabase functions serve link-anonymous-session
   supabase status | rg 'API URL|Studio URL'
   rg -n 'enabled =|client_id|redirect_uri' supabase/config.toml
   ```
   - The committed config should keep `[auth.external.apple] enabled = false` so `supabase start` does not require `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET`.
   - `client_id` should still be `com.route25.GirlPower.auth`.
   - No `redirect_uri = https://ktgapnamhpdbmhhgydnl.supabase.co/auth/v1/callback` override should remain in `supabase/config.toml`; local auth should use the CLI stack callback.
   - For manual Apple Sign In verification only, export `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` and flip `enabled = true` in an uncommitted local change before restarting Supabase.
5. Manual simulator regression for refresh + link behavior:
   - Install a clean Debug build on the iPhone 15 Pro (iOS 17.0.1) simulator, complete the first anonymous demo, then trigger the protected second-demo or paywall path.
   - Confirm the auth sheet appears until a real `.authenticated` state is reached; a refreshing cached session must not unlock the second demo or paywall early.
   - If you force refresh failure (for example by invalidating the refresh token in Supabase), the prompt should remain blocked and show the re-auth message instead of continuing.
   - After successful email/password or Apple sign-in, retry the protected action and confirm the app proceeds without creating duplicate anonymous-link rows on repeated attempts.
6. Run the full app suite:
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,OS=17.0.1,name=iPhone 15 Pro'
   ```

## GP-123 Profiles Contract Hardening

1. Reset the local Supabase stack onto the latest migration set:
   ```sh
   scripts/supabase-reset.sh
   ```
2. Run the targeted auth/profile regressions:
   ```sh
   xcodebuild test \
     -scheme GirlPower \
     -destination 'platform=iOS Simulator,name=iPhone 15' \
     -only-testing:GirlPowerTests/AuthSystemTests \
     -only-testing:GirlPowerTests/AppFlowViewModelProTests \
     -only-testing:GirlPowerTests/OnboardingCompletionRepositoryTests
   ```
3. Replay the `profiles` REST contract locally:
   ```sh
   eval "$(supabase status -o env | sed '/^Stopped services/d;/^A new version/d;/^We recommend/d')"
   EMAIL='gp123-verify@example.com'
   PASSWORD='Password-123!'
   LOGIN_ONE='2026-03-22T21:00:00Z'
   LOGIN_TWO='2026-03-22T21:05:00Z'

   CREATE_RESPONSE=$(curl -sS -X POST "$API_URL/auth/v1/admin/users" \
     -H "apikey: $SERVICE_ROLE_KEY" \
     -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
     -H 'Content-Type: application/json' \
     -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"email_confirm\":true}")
   USER_ID=$(printf '%s' "$CREATE_RESPONSE" | jq -r '.id')
   SIGN_IN_RESPONSE=$(curl -sS -X POST "$API_URL/auth/v1/token?grant_type=password" \
     -H "apikey: $ANON_KEY" \
     -H 'Content-Type: application/json' \
     -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
   ACCESS_TOKEN=$(printf '%s' "$SIGN_IN_RESPONSE" | jq -r '.access_token')

   curl -sS -X POST "$REST_URL/profiles?select=id,email,is_pro,pro_platform,onboarding_completed,last_login_at" \
     -H "apikey: $ANON_KEY" \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H 'Content-Type: application/json' \
     -H 'Prefer: return=representation' \
     -d "[{\"id\":\"$USER_ID\",\"email\":\"$EMAIL\",\"last_login_at\":\"$LOGIN_ONE\"}]" | jq

   curl -sS "$REST_URL/profiles?id=eq.$USER_ID&select=id,email,is_pro,pro_platform,onboarding_completed,last_login_at" \
     -H "apikey: $ANON_KEY" \
     -H "Authorization: Bearer $ACCESS_TOKEN" | jq

   curl -sS -X PATCH "$REST_URL/profiles?id=eq.$USER_ID&select=id,email,last_login_at,is_pro,pro_platform" \
     -H "apikey: $ANON_KEY" \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H 'Content-Type: application/json' \
     -H 'Prefer: return=representation' \
     -d "{\"email\":\"updated-$EMAIL\",\"last_login_at\":\"$LOGIN_TWO\"}" | jq

   curl -sS -X PATCH "$REST_URL/profiles?id=eq.$USER_ID&select=id,onboarding_completed,is_pro,pro_platform" \
     -H "apikey: $ANON_KEY" \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H 'Content-Type: application/json' \
     -H 'Prefer: return=representation' \
     -d '{"onboarding_completed":true}' | jq

   curl -sS -X PATCH "$REST_URL/profiles?id=eq.$USER_ID&select=id,is_pro,pro_platform" \
     -H "apikey: $ANON_KEY" \
     -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H 'Content-Type: application/json' \
     -H 'Prefer: return=representation' \
     -d '{"is_pro":true,"pro_platform":"apple"}' | jq

   curl -sS -X PATCH "$REST_URL/profiles?id=eq.$USER_ID&select=id,is_pro,pro_platform" \
     -H "apikey: $SERVICE_ROLE_KEY" \
     -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
     -H 'Content-Type: application/json' \
     -H 'Prefer: return=representation' \
     -d '{"is_pro":true,"pro_platform":"apple"}' | jq
   ```
   - Expect the insert/read/login/onboarding calls to succeed.
   - Expect the client entitlement PATCH to fail with `code = "42501"`.
   - Expect the service-role entitlement PATCH to succeed.
4. Run the full app suite:
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,name=iPhone 15'
   ```
