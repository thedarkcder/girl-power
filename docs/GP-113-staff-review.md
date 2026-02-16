# GP-113 Staff Engineering Review & Flow Spec

## 1. Problem
Ensure Girl Power's first-run experience deterministically guides users from splash to onboarding to demo CTA with persistent completion state so returning users skip onboarding without regressions.

## 2. Type
UX / interaction flow

## 3. Invariants
- Splash screen is the only entry point on cold start and must lead somewhere (no stalls).
- Onboarding carousel renders exactly three ordered slides with swipe + indicator parity.
- Demo CTA always routes to demo stub and never dead-ends.
- Completion flag persists so post-onboarding launches bypass the carousel until cleared.

## 4. Assumptions
- Local persistence via `UserDefaults` is acceptable for onboarding completion since data is single-flag per device; no cross-device sync needed.
- Demo attempt flow can remain a stub view provided navigation contract exists; downstream teams will replace internals later.
- Analytics hooks can piggyback on state transitions later; current work only needs deterministic state machine for future instrumentation.

## 5. Contract Matrix
| Input / state | Event | Expected behavior |
| --- | --- | --- |
| Splash (fresh install) | splashFinished | Transition to onboarding index 0 |
| Splash (returning user) | splashFinished with `skipOnboardingAfterSplash = true` | Transition directly to demo CTA |
| Onboarding index _n_ | slideAdvance to _m_ where |m-n| <= 1 | Move to slide _m_ |
| Onboarding index last | onboardingCompleted | Transition to demo CTA + persist flag |
| Demo CTA | startDemo | Push demo stub on NavigationStack |
| Demo Stub | finishDemo | Pop back to CTA |
Invalid events (out-of-range slides, duplicate completion) are ignored and state remains unchanged.

## 6. Call-Path Impact Scan
- `GirlPowerApp` bootstraps `AppFlowViewModel` → `AppFlowRootView`.
- `SplashView` fires `onFinished` once on appear.
- `OnboardingCarouselView` drives `slideAdvance` via TabView binding and `Continue` CTA.
- `DemoCTAView` triggers `startDemo`.
- `DemoAttemptFlowView` triggers `finishDemo`.
No other modules touch these types, so impact is scoped to root flow and unit tests.

## 7. Domain Term Contracts
- "Onboarding completion" = user has finished slide index 2; enforced by checking final index before state transition/persist.
- "Demo CTA" = landing screen with Start Free Demo; must exist regardless of onboarding skip status.
- "Demo stub" = placeholder view reachable exclusively via CTA; ensures navigation contract for future feature.

## 8. Authorization & Data-Access Contract
- Entire flow is offline onboarding; no auth context or tenant data touched.
- Only data access is `UserDefaults` flag `onboarding.completed`; no PII stored or transmitted.

## 9. Lifecycle & State Matrix
States: `splash` → `onboarding(index 0..2)` → `demoCTA` → `demoStub` ↔ `demoCTA`.
- Allowed transitions defined in `AppFlowStateMachine`.
- Persisted lifecycle: once completion flag true, future lifecycles skip `onboarding` entirely but still start at `splash`.

## 10. Proposed Design
- Central `AppFlowStateMachine` (pure struct) modeling transitions.
- `AppFlowViewModel` orchestrates events, binds TabView index, and syncs NavigationStack routes.
- `UserDefaultsOnboardingCompletionRepository` handles persistence + test fake.
- SwiftUI feature views (`SplashView`, `OnboardingCarouselView`, `DemoCTAView`, `DemoAttemptFlowView`) remain declarative/pure; only callbacks bubble upwards.

## 11. Patterns Used
- Explicit state machine to avoid ad-hoc booleans.
- NavigationStack path syncing to keep CTA vs demo stub transitions deterministic.
- Dependency-injected repository for persistence/testability.

## 12. Patterns Not Used
- No timers/sleeps for sequencing (would be flaky and violate policy).
- No global singletons beyond `UserDefaults.standard` since DI handles testing needs.

## 13. Change Surface
- Files: `GirlPower/App/*.swift`, `Features/{Splash,Onboarding,Demo}/*.swift`, new documentation (`docs/GP-113-staff-review.md`).
- Contracts: `AppFlowStateMachine`, `AppFlowViewModel`, `OnboardingCompletionRepository`, UI views, tests.

## 14. Load Shape & Query Plan
- Pure client UI, negligible QPS. No network/database queries beyond constant-time `UserDefaults` read/write.

## 15. Failure Modes
- Persistence write failure: `UserDefaults` best-effort; fallback replays onboarding (acceptable).
- Invalid slide index inputs: state machine guards by range + step size.
- Navigation path drift: view model resets path when leaving demo stub.
- Re-entrancy: `SplashView` ensures `onFinished` fires once.

## 16. Operational Integrity
- Rollback: revert app update; persistence flag remains compatible (bool).
- No external dependencies besides system frameworks.
- Concurrency: UI main-thread only; state machine pure ensures deterministic behavior even if events fired quickly.

## 17. Tests
- `AppFlowStateMachineTests` cover initial state, skip logic, slide progression, CTA/demo transitions.
- `AppFlowViewModelTests` verify persistence flag writes, navigation path sync, and returning-user skip scenario.

## 18. Verdict
✅ Proceed — design is appropriate and scoped

## State Machine Diagram
States: `splash` → `onboarding(0)` ↔ `onboarding(1)` ↔ `onboarding(2)` → `demoCTA` ↔ `demoStub`. Events: `splashFinished`, `slideAdvance(i)`, `onboardingCompleted`, `startDemo`, `finishDemo`. Persisted flag toggles whether the `splashFinished` edge goes to onboarding or CTA.

## Explicit State/Event Enumeration (State Machine Guidance)
- **States**: `splash` (branding entry), `onboarding(index: 0..2)` (exactly three ordered slides), `demoCTA` (Start Free Demo landing), `demoStub` (placeholder view pushed from CTA).
- **Events**: `appLaunched` (implicit -> `splash`), `splashFinished`, `slideAdvance(index)`, `onboardingCompleted`, `startDemo`, `finishDemo`.
- **Transition table highlights**:
  - `splash` + `splashFinished` → `onboarding(0)` when flag is false; same event → `demoCTA` when flag true.
  - `onboarding(i)` + `slideAdvance(j)` where `|i-j| <= 1` and `j in 0...2` → `onboarding(j)`; invalid jumps ignored.
  - `onboarding(2)` + `onboardingCompleted` → `demoCTA` and persists flag; earlier indices ignore completion event.
  - `demoCTA` + `startDemo` → `demoStub` (pushes NavigationStack route); `demoStub` + `finishDemo` → `demoCTA` and clears push.
This satisfies the `state_machine_guidance` skill mandate by keeping transitions pure/deterministic while documenting them for reviewers.

## UI/UX Copy, Imagery, Accessibility Brief
- **Splash**: Icon `bolt.heart.fill`, title "Girl Power", subtitle "Amplify fearless teams". Accessibility: `Image` marked decorative; text provides spoken branding. Background gradient ensures contrast >4.5:1 (white on magenta/purple).
- **Onboarding Slides**: Copy per `OnboardingSlide.defaultSlides`. Symbols: `sparkles`, `target`, `person.3.fill` with tinted circle background. Add `.accessibilityLabel` to each symbol describing intent (implemented inline). TabView uses `.accessibilityIdentifier("onboarding_tabview")` for UI tests; progress indicator uses `Capsule` views with `accessibilityValue` "Step X of 3" via wrapper.
- **CTA Screen**: Headline "You're Ready" + "Start your free momentum-building demo experience." CTA button text "Start Free Demo" with `.accessibilityAddTraits(.isButton)`, `accessibilityIdentifier("start_demo_button")`.
- **Demo Stub**: Title "Demo Starting Soon" plus explanatory text and "Back to CTA" button for deterministic exit.
