1. Problem
Ensure the first-run iOS experience deterministically guides users from the Girl Power splash through a fixed onboarding carousel into the demo CTA while skipping onboarding after completion.

2. Type
UX / interaction flow

3. Invariants
- Splash always renders first on cold launch and never blocks progression from firing automatically.
- Exactly three onboarding slides exist, present in order, and drive the progress indicator without duplication.
- "Start Free Demo" CTA always routes into the demo attempt stub without crashes or dead routes.
- Completing onboarding flips a persisted device-level flag so subsequent launches land on the CTA immediately.

4. Assumptions
- `UserDefaults` persistence is acceptable for the onboarding completion flag because scope is single-device, unauthenticated usage.
- SwiftUI lifecycle (iOS 16+) is available, so `NavigationStack`, `AppStorage`, and observable view models are safe primitives.
- Demo attempt flow is a stub today; we only need to navigate there with a placeholder view while retaining explicit hooks for future work.

5. Contract matrix
- Launch without completion flag → Splash → Onboarding(0) → CTA (intentional new flow).
- Launch with completion flag true → CTA immediately (intentional behavior change from empty app).
- Swipe or tap next while in onboarding(i) with i < 2 → transitions to onboarding(i+1) and updates progress indicator (stateful but deterministic).
- Tap Continue on final onboarding slide → onboardingComplete event transitions to CTA and persists flag (new behavior).
- Tap Start Free Demo from CTA → pushes demo stub route and keeps CTA as base (new behavior, ensures navigation stack consistency).

6. Call-path impact scan
- `GirlPowerApp` bootstraps the view model + repository, determines initial state, and hosts the navigation shell.
- `AppFlowViewModel` accepts UI events, runs them through `AppFlowStateMachine`, persists onboarding completion, and updates navigation.
- `SplashView` emits a `splashFinished` event on appear; no other callers.
- `OnboardingCarouselView` renders slide data, surfaces swipe/page-change callbacks, and emits completion events.
- `DemoCTAView` shows CTA copy and invokes `startDemo` callback; also home for analytics hooks later.
- `DemoAttemptFlowView` is the placeholder presented after CTA; currently a simple stub.

7. Domain term contracts
- "Onboarding Completed" → persisted bool meaning the user reached CTA via the final onboarding action; enforced by repository + state machine before skipping slides.
- "Demo Attempt Flow" → first screen after CTA representing future interactive demo; currently a stub view but must remain routable.
- "Splash" → single-brand state that auto-advances; no manual dismiss action allowed.

8. Authorization & data-access contract
- Single-user local app: no auth contexts. Only `UserDefaults.standard` key `onboarding.completed` is written/read; no cross-tenant leakage.

9. Lifecycle & state matrix
- States: `splash` → `onboarding(index 0..2)` → `demoCTA` → `demoStub` (push) → pop back to `demoCTA`.
- Returning users with completion flag: `demoCTA` (initial) → optionally `demoStub`.
- Events: `appLaunch`, `splashFinished`, `slideAdvance`, `onboardingComplete`, `startDemo`, `returnFromDemo`, `returningUser`.

10. Proposed design
- Build `AppFlowStateMachine` pure struct (enum state + transition reducer) with exhaustive transitions for defined events.
- Implement `AppFlowViewModel` as `ObservableObject` storing current state + `NavigationPath`, injecting `OnboardingCompletionRepository`.
- Create `OnboardingSlide` model + static inventory of three slides (title, subtitle, image/system symbol).
- Add SwiftUI feature views: `SplashView`, `OnboardingCarouselView`, `DemoCTAView`, `DemoAttemptFlowView`, each receiving closures for events.
- Persist onboarding completion via repository (`UserDefaults` implementation) invoked once the final onboarding action fires; hydrate flag on launch to choose initial state.
- Compose `NavigationStack` shell that renders different feature views based on state machine output without timers; CTA pushes demo stub on Start Free Demo.

11. Patterns used
- Explicit enum-based state machine with pure reducer for determinism.
- Protocol-based persistence for onboarding completion flag with injectable in-memory fake for tests.
- NavigationStack + ObservableObject coordination keeping side-effects at edges.

12. Patterns not used
- Timer/sleep-based delays for splash transitions are rejected to keep flow deterministic and avoid flakiness.

13. Change surface
- Add SwiftUI app files (`GirlPowerApp.swift`, state machine, view model, slides, repository, feature views).
- Add persistence implementation + unit tests for state machine + repository.
- Add UI test covering splash → onboarding → CTA → demo stub and relaunch skip.
- Update docs with review + how-to-test guidance.

14. Load shape & query plan
- Local-only workflow; no network I/O. UserDefaults writes/read are O(1); NavigationStack depth ≤ 2, so no scalability risk.

15. Failure modes
- UserDefaults write failure → onboarding flag remains false, so user repeats onboarding (safe fallback, can log later).
- Incorrect transition mapping → UI could desync; mitigated via reducer tests + default case fallback to CTA.
- UI test flake → use element existence expectations instead of sleeps.

16. Operational integrity
- Rollback by shipping previous app build; no migrations.
- Dependencies limited to SwiftUI + Foundation; no remote services.
- Concurrency: reducer invoked on main thread; UserDefaults bool writes are atomic enough for this scope.

17. Tests
- Invariant coverage via reducer tests (splash→onboarding, onboarding bounds, CTA/demostub transitions) and repository persistence test.
- UI test verifying initial flow plus relaunch skip path to CTA and demo stub navigation.

18. Verdict
✅ Proceed — design is appropriate and scoped.
