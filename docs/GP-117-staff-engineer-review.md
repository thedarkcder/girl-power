> **Pre-flight — February 18, 2026:** Completed staff-engineer review before coding GP-117. Demo quota + paywall context taken from GP-116 branch; StoreKit + entitlement persistence design here ensures routing/business rules stay deterministic.

1. Problem: Unlock Girl Power’s coaching flow by replacing the static paywall with a StoreKit-driven entitlement service so real subscriptions flip demo users into unlimited access without relaunching.
2. Type: Workflow / long-running process
3. Invariants:
   - StoreKit’s transaction history (`Transaction.currentEntitlements` + `Transaction.updates`) is the single source of truth for `isPro`; cached state only accelerates routing but never overrides the feed.
   - Paywall UI must only enable Subscribe/Restore when localized pricing metadata is loaded from the StoreKit config (no literals) and Terms/Privacy links stay tappable before purchases.
   - Demo quota locks never apply to `isPro == true`; the CTA text switches to “Start Coaching” immediately and paywall routes stay hidden until entitlement expires.
   - Purchase and restore flows surface inline errors (no crashes) and leave the entitlement service in a consistent state (ready → error/ready, subscribed persists across launches).
4. Assumptions:
   - Apple sandbox testers will install the StoreKit configuration referenced by the `.storekit` bundle, so bundling the file plus documentation is sufficient for QA to run purchases.
   - Girl Power has only one subscription family today; we can model a single `ProMonthly` product ID and add more IDs later without redesigning the state machine.
   - Telemetry hooks remain fire-and-forget; logging purchase intent via `Logger` is enough for this release, keeping external analytics out of scope.
   - Persisting `isPro` + last product ID in UserDefaults is acceptable because StoreKit refresh happens on each launch to self-correct.
5. Contract matrix:
   - No entitlement + demo quota fresh/eligible ⇒ CTA says “Start Free Demo”, summary CTA states behave exactly as GP-116, paywall accessible when locked (unchanged behavior).
   - Entitlement subscribed (transaction exists) ⇒ CTA says “Start Coaching”, DemoCTA never disables, summary CTA surfaces “Unlimited access unlocked” copy, paywall navigation suppressed (intentional new behavior).
   - Purchase started but not finished ⇒ state machine stays in `.purchasing` until success/cancel; UI shows spinner + Cancel affordance, errors bubble into `.error` state with retry (intentional new behavior).
   - Restore tapped with no purchases ⇒ `.restoring` → `.error(noActiveSubscription)` and UI shows inline copy without crashing or lingering spinner (intentional new behavior).
6. Call-path impact scan:
   - App startup → `StoreKitEntitlementService.load()` → `EntitlementStateMachine` transitions → `AppFlowViewModel` observer updates `demoCTA`/summary/paywall routing.
   - PaywallViewModel Subscribe → `entitlementService.purchase()` → StoreKit `Product.purchase()` → `EntitlementStateMachine` `purchaseCompleted` ⇒ `AppFlowViewModel` receives `.subscribed` and dismisses paywall.
   - Restore CTA → `entitlementService.restore()` → `Transaction.currentEntitlements` scan → same state pipeline as purchase.
   - Demo quota flow remains AppFlowViewModel ↔ DemoQuotaCoordinator, but pro state short-circuits gating + navigation decisions.
7. Domain term contracts:
   - `isPro` = cached + real-time projection of StoreKit entitlements; true iff at least one verified, unrevoked `Transaction` matches the Girl Power subscription product family.
   - `EntitlementState` = `{ loading, ready(product), purchasing(product), restoring, subscribed(info), error(reason) }`; transitions validated via unit tests.
   - `PaywallProduct` = immutable struct with StoreKit `displayPrice`, period string, and feature bullets; derived solely from `Product` metadata.
   - `SummaryCTAState.proUnlocked` (new) communicates that DemoQuota locks are bypassed once `isPro` true; only state that surfaces the Start Coaching copy within the summary module.
8. Authorization & data-access contract:
   - StoreKit APIs run on-device; no new network scopes or Supabase access. Demo quota Supabase endpoints remain untouched by entitlement work.
   - Persisted entitlement snapshot stored in `UserDefaults` under a new key scoped to bundle identifier; contains no PII (only boolean + product ID string).
9. Lifecycle & state matrix:
   - Entitlement state machine transitions:
     - `loading` —initial → (`productsLoaded` → `ready(product)` | `entitlementFound` → `subscribed`).
     - `ready(product)` —(purchaseRequested)→ `purchasing` —(purchaseSucceeded)→ `subscribed` —(revoked)→ `ready`.
     - `ready(product)` —(restoreRequested)→ `restoring` —(restorationSuccess)→ `subscribed` or `(restorationEmpty/error)`→ `error`.
     - `error` —(retry)→ `loading/ready` depending on cached product, ensuring we never stay stuck forever.
   - AppFlow state machine gains implicit transitions triggered by entitlement changes: any `.paywall` state automatically transitions to `.demoCTA` once `isPro` toggles true.
10. Proposed design:
    - Create `Subscriptions` module housing `EntitlementStateMachine`, `EntitlementState`, `PaywallProduct`, and `EntitlementSnapshotPersisting` implementations (UserDefaults-backed).
    - Implement `StoreKitEntitlementService` (`@MainActor` `ObservableObject`) that drives the state machine, fetches StoreKit products, refreshes current entitlements on init, and listens to `Transaction.updates` via detached Task.
    - Build `PaywallModule` (view + view model) that binds to the service, renders localized price/bullets, exposes Subscribe & Restore actions, Terms/Privacy links, and shows inline error banners per state.
    - Update `AppFlowViewModel` / `DemoCTAView` / `SquatPostSetSummaryViewModel` to observe `entitlementService.state`, derive `isPro`, adjust CTA copy/enablement, and auto-dismiss paywall when entitlement flips.
    - Extend routing + telemetry so purchase success triggers `finishDemo(reason: "paywall_purchase_success")`, and maintain DemoQuota compatibility by skipping quota checks when `isPro`.
11. Patterns used:
    - Explicit reducer-based state machine for entitlements, mirroring DemoQuota approach for testability.
    - Dependency injection: `AppFlowViewModel` receives `EntitlementServicing`, `PaywallViewModel` accepts service protocol for easy testing.
    - Swift Concurrency (async/await + AsyncSequence) for StoreKit transactions without sleep-based polling.
12. Patterns not used:
    - No Combine/NotificationCenter observers—state is delivered via structured async tasks to avoid hidden threading.
    - No general service locator/singleton for entitlements; service injected from `GirlPowerApp` for clarity.
13. Change surface:
    - New `GirlPower/Subscriptions` directory for service/state machine/persistence + tests.
    - New `GirlPower/StoreKit/Products.storekit` bundle and Xcode project resource wiring.
    - `GirlPower/App`: AppFlow view model/root view updates, paywall routing, wiring entitlements.
    - `GirlPower/Features/Paywall`: new SwiftUI module (view + view model).
    - `GirlPowerTests`: entitlement state machine tests, paywall view model tests, expanded AppFlow tests covering pro flows.
    - `docs`: staff review (this), HOW_TO_TEST sandbox instructions, PR How-to-Test updates.
14. Load shape & query plan:
    - StoreKit product fetch is single-call and cached; no server load. Transaction updates are event-driven per Apple services with negligible frequency (<1 per minute).
    - Demo quota Supabase invocations unchanged; pro bypass simply stops calling start/complete when unlimited is active.
15. Failure modes (detection + recovery):
    - StoreKit product fetch fails (offline) → state machine emits `.error` with retry button; cached `isPro` snapshot keeps CTA in Start Coaching if previously subscribed.
    - Purchase cancelled/Apple ID mismatch → `.purchasing` rolls back to `.ready`, inline banner instructs user; telemetry records cancellation reason.
    - Restore returns revoked transactions → `.error("No active subscription")`; user stays locked, documentation directs them to Apple support.
    - Transaction.updates dropped → persisted snapshot remains false until next manual refresh (Restore button) or forced reload at app start.
16. Operational integrity:
    - Rollback: remove StoreKit files + entitlements module, revert AppFlow changes; no migrations or irreversible data writes.
    - Dependencies: StoreKit operations rely on Apple frameworks with built-in retries; we wrap calls and timeouts via async/await and do not add loops.
    - Concurrency: StoreKitEntitlementService serializes state transitions on MainActor; transaction listener Task switches back to MainActor before mutating state machine to avoid races.
17. Tests:
    - Invariant 1 → `EntitlementStateMachineTests` covering current entitlement + transaction updates.
    - Invariant 2 → `PaywallViewModelTests` verifying price formatting, Terms links, Subscribe button enablement, and error presentation.
    - Invariant 3 → `AppFlowViewModelTests` ensuring `isPro` toggles CTA copy (“Start Coaching”) and bypasses paywall/locked states.
    - Invariant 4 → Integration-style test simulating restore failure path to confirm `.error` messaging and state resets.
18. Verdict: ✅ Proceed — design is appropriate and scoped.
