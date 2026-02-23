> **Attempt 2 re-verification — February 18, 2026:** Reviewed AppFlow + DemoQuota wiring before touching code this run. Invariants remain unchanged (exactly two demo attempts, summaries always render reps/tempo/notes, navigation must go summary → second attempt or paywall). Mismatch telemetry added in this run provides proof that attempt indexes and quota states stay in lock-step; no Decision Gate needed.

1. Problem: Transition every Squat Coaching demo attempt into a cached summary state that gates second-attempt eligibility via DemoQuotaCoordinator and routes locked devices directly into the paywall flow, eliminating loopholes beyond two attempts.
2. Type: Workflow / long-running process
3. Invariants:
   - Every attempt completion generates a SessionSummary (reps, tempo insight, coaching notes) before any navigation change and the summary payload is logged with DemoQuotaCoordinator metadata.
   - DemoQuotaCoordinator remains the single quota authority; summary CTAs only render “One more go” when the observable state is exactly `.secondAttemptEligible` and the completed attempt index is 1.
   - Locked/paywall states are terminal: once DemoQuotaStateMachine resolves to `.locked` or attempt #2 finishes, only the Continue to Paywall action is exposed and navigation back into SquatSessionCoordinator is blocked.
   - Summary surfaces survive background/resume/relaunch by caching SessionSummary in AppFlowViewModel and re-applying DemoQuota state updates so CTA visibility never desynchronizes from quota decisions.
4. Assumptions:
   - SessionSummary can be derived on-device from RepCounter temporal samples (no server data required) and storing it in-memory is sufficient between summary and CTA/pawall decisions.
   - PaywallRouter (GP-117) is represented by a placeholder SwiftUI scene today; clearing the NavigationStack before routing is acceptable because paywall is terminal for the demo experience.
   - Evaluate-session latency stays <3 s; if DemoQuotaCoordinator reports `.gatePending` longer, the summary UI can stay in a loading verdict state without retry logic.
   - RepCounter corrections plus timestamp deltas are accurate enough to infer tempo/coaching insights without extra Vision metadata.
5. Contract matrix:
   - Attempt #1 completes while DemoQuotaStateMachine = `.gatePending` ⇒ Summary state enters `awaitingDecision`, hides “One more go”, shows spinner, Continue to Paywall disabled (unchanged intent, new explicit UI).
   - Attempt #1 + `.secondAttemptEligible` ⇒ Summary state toggles “One more go” primary CTA, Continue to Paywall secondary CTA, starting CTA must call DemoQuotaCoordinator.markAttemptStarted (intentional new behavior).
   - Any attempt + `.locked(reason)` or request for attempt #2 ⇒ Summary renders locked copy, exposes only Continue to Paywall, pushes Paywall route (intentional new behavior, paywall terminal state).
   - Attempt #2 completion ⇒ DemoQuotaStateMachine transitions to `.locked(.quotaExhausted)`, summary caches final metrics, disables back navigation (intentional reinforcement of two-attempt quota).
6. Call-path impact scan:
   - DemoCTAView → AppFlowViewModel.startDemo() (metadata + quota guard) → DemoQuotaCoordinator.markAttemptStarted.
   - DemoAttemptFlowView (SquatSessionView) → SquatSessionCoordinator.completeSession() → RepCounter snapshot → AppFlowViewModel.presentSummary() → DemoQuotaCoordinator.markAttemptCompleted.
   - Summary UI actions → AppFlowViewModel.startOneMoreGo()/continueToPaywall() → DemoQuotaCoordinator / PaywallRouter routing.
   - AppFlowViewModel.observeDemoQuota() → updates SummaryViewModel CTA state; paywall telemetry emitted alongside router.
7. Domain term contracts:
   - SessionSummary = immutable struct capturing attemptIndex, total reps, average tempo classification, duration, and aggregated coaching notes; generated exactly once per attempt.
   - One more go CTA = primary action visible only when last attempt index == 1 and DemoQuota state == `.secondAttemptEligible`; triggers fresh SquatSessionCoordinator with cleared rep data.
   - Continue to Paywall CTA = absorbing action routing into PaywallRouter; once tapped the user cannot return to SquatSessionCoordinator without reinstall/quota reset.
   - Summary CTA State = view-model friendly projection of DemoQuotaStateMachine (.awaitingDecision, .secondAttemptEligible, .locked(message)).
8. Authorization & data-access contract:
   - All summary data stays on-device within the SquatCoaching module; only DemoQuotaCoordinator touches Supabase endpoints with the existing anon key. Paywall routing operates locally.
9. Lifecycle & state matrix:
   - SquatSessionStateMachine: idle → permissionsPending → configuringSession → running(PosePhase) → summary(SummaryContext) → idle (new terminal state for each attempt). Fatal/permission errors still jump to endingError before idle.
   - AppFlowStateMachine: demoCTA ↔ demoStub (session) ↔ sessionSummary ↔ paywall terminal; summary transitions depend on DemoQuota state.
10. Proposed design:
    - Introduce `SessionSummary` + `RepCounter.Snapshot` to capture reps, tempo samples, and correction counts; SquatSessionCoordinator exposes `completeSession(attemptIndex:ctaState:)` to compute it and drive the new summary state.
    - Extend SquatSessionStateMachine with `State.summary(SummaryContext)` and `Event.summaryReady`, keeping summary CTA metadata decoupled from DemoQuota types.
    - AppFlowViewModel caches the latest SummaryContext, instantiates `SquatPostSetSummaryViewModel`, feeds DemoQuota state updates, and owns the navigation path for summary/paywall routes.
    - Build `SquatPostSetSummaryView` (SwiftUI) that renders reps + tempo cards, coaching notes list, LLM verdict status, and CTA stack wired to AppFlowViewModel actions.
    - Implement `PaywallRouter` abstraction that clears the NavigationStack and pushes the paywall scene; treat paywall as terminal and emit final telemetry stub.
11. Patterns used:
    - Pure reducers/state machines for SquatSession/AppFlow with explicit events.
    - View-model composition (AppFlowViewModel + SquatPostSetSummaryViewModel) with dependency injection for PaywallRouter and DemoQuotaCoordinator.
    - Snapshot-based data contract (RepCounter → SessionSummary) to avoid recomputing after navigation.
12. Patterns not used:
    - No timer/sleep-based waits for evaluation decisions; UI reacts to DemoQuota state stream instead of polling.
    - No global singletons for summary cache; data stays in view-model scope.
13. Change surface:
    - `GirlPower/SquatCoaching`: RepCounter, SquatSessionStateMachine, SquatSessionCoordinator/ViewModel, new SessionSummary model, new summary view files.
    - `GirlPower/App`: AppFlowStateMachine/ViewModel/RootView, PaywallRouter wiring, Demo attempt view updates.
    - `GirlPower/Features/Demo`: DemoAttemptFlowView restructuring, new summary UI assets.
    - `GirlPowerTests`: new/updated tests for state machines, summary VM, AppFlow transitions.
    - Docs: this review, state-machine diagram, HOW_TO_TEST manual steps.
14. Load shape & query plan:
    - Summary computation is O(reps) over in-memory arrays (<50 entries). No new network traffic beyond existing DemoQuota evaluate/log calls. Paywall placeholder is static SwiftUI.
15. Failure modes:
    - DemoQuota evaluation timeout keeps summary in loading state indefinitely → mitigate by surfacing timeout copy and disabling One More Go.
    - SessionSummary snapshot fails (e.g., no samples) → still generate summary with zero reps and default coaching note so metadata/logging doesn’t crash.
    - Paywall routing fails to clear NavigationStack → user could back-navigate into SquatSessionView; guard by forcing path reset inside router.
16. Operational integrity:
    - SummaryContext stored in AppFlowViewModel (MainActor) so concurrent state updates stay serialized. DemoQuota state stream already serialized via actor.
    - Rollback simply removes summary files; no migrations nor persistence format changes beyond DemoQuota existing snapshot.
    - PaywallRouter invoked only once per lock; telemetry/calls happen on main queue.
17. Tests:
    - Invariant 1 → SquatSessionStateMachineTests + new SessionSummary unit verifying summary state emitted.
    - Invariant 2 → AppFlowStateMachineTests + SummaryViewModelTests covering CTA gating permutations.
    - Invariant 3 → Integration-style AppFlowViewModel test ensuring locked state pushes paywall and disallows restart.
    - Invariant 4 → DemoQuotaCoordinatorTests reusing stream stub to simulate background/relaunch updates feeding summary VM.
18. Verdict: ✅ Proceed — design is appropriate and scoped.
