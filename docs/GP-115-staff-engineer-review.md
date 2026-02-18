1. Problem: Guarantee each device is limited to two Squat Coaching demos even across reinstalls while Supabase + LLM keep the gate authoritative.
2. Type: Workflow / long-running process
3. Invariants:
   - Device ID uniquely ties attempts so local + remote state never allow >2 tries.
   - Attempt #1 completion always triggers evaluate-session once and blocks CTA until decision stored.
   - attempt_index=2 never re-triggers evaluation and always transitions to locked/quota exhausted after completion.
   - Every attempt start/completion produces a Supabase log row with metadata.
4. Assumptions:
   - Supabase Edge Function evaluate-session is reachable via env-configured URL; if not, coordinator denies attempt #2 to fail closed.
   - Keychain identity persists for most devices; Supabase mirror recovers when local storage lost.
   - Supabase Edge Functions own LLM/service keys; the client only needs anon/service tokens already safe to ship.
5. Contract matrix:
   - No snapshot + remote attemptsUsed=0 ⇒ state fresh, allow attempt #1 start and emit start log, unchanged.
   - attemptsUsed=1 + no decision ⇒ gatePending, disable CTA, fire single evaluate-session request, intentional new behavior.
   - attemptsUsed=1 + decision.allow ⇒ secondAttemptEligible, show “One more go” CTA once then lock after second completion, intentional new.
   - attemptsUsed≥2 or decision deny/timeout/serverLock ⇒ locked(reason), route to paywall even after reinstall, intentional reinforcement.
6. Call-path impact scan:
   - AppFlowViewModel.startDemo() → DemoQuotaCoordinator.markAttemptStarted(); must short-circuit navigation when locked or pending.
   - DemoAttemptFlowView exit → DemoQuotaCoordinator.markAttemptCompleted(); needs metadata for logging.
   - GirlPowerApp cold start → coordinator.prepareForDemoStart(); hydrates local state from Supabase mirror/log repo before showing CTA.
7. Domain term contracts:
   - demo attempt = full Squat Coaching flow; counted even if crash after logging start.
   - device_id = keychain-backed UUID mirrored server-side; immutability ensures reinstall protection.
   - allowAnotherDemo = boolean from evaluate-session that can only open second attempt when attemptsUsed==1; persisted decision prevents re-evaluation.
8. Authorization & data-access contract:
   - Acting principal is device-level client using Supabase anon/service token scoped by tenant/project/device_id fields.
   - Edge Functions perform privileged writes with server-side keys, so client never handles LLM credentials.
9. Lifecycle & state matrix:
   - States: fresh → firstAttemptActive → gatePending → secondAttemptEligible → secondAttemptActive → locked(reason);
     resetFromServer can project into any state but locked is absorbing.
10. Proposed design:
   - Keep DemoQuotaStateMachine pure (already implemented) to drive side-effect intents.
   - Implement DemoQuotaCoordinator with serial async queue; inject persistence, identity, session logger, evaluation client, server snapshot fetcher.
   - Coordinator executes side effects (log start/completion, persist attempts, call evaluation, persist decisions) and publishes current state for UI binding.
   - Provide Supabase-backed DeviceIdentityMirroring + DemoAttempt remote snapshot fetcher to hydrate state on cold start/reinstall.
   - Expose immutable async getters + Combine publisher to Demo CTA so UI copies (“Start Free Demo”, “One more go”, “Checking…”, locked reason) stay in sync.
11. Patterns used:
   - Deterministic reducer + coordinator ensures explicit transitions.
   - Protocol-based DI for persistence/logging/evaluation allows unit tests without touching Supabase.
   - Keychain + remote mirror ensures durability without server reconciliation complexity.
12. Patterns not used:
   - No timer-based polling or sleeps; evaluation waits on single request with timeout-based denial.
13. Change surface:
   - GirlPower/DemoQuota: Coordinator, repository, device identity, Supabase services, plus new Supabase mirror client.
   - GirlPower/App/AppFlowViewModel & AppFlowStateMachine; GirlPower/Features/Demo views for CTA state.
   - docs/HOW_TO_TEST.md and new QA checklist plus coordinator unit tests.
14. Load shape & query plan:
   - Each attempt issues ≤4 HTTP calls (start log, completion log, evaluate-session, snapshot fetch/mirror) keyed by device_id indexes.
   - evaluate-session capped at ~3s timeout with no retries; logging may retry once because endpoints are idempotent.
15. Failure modes:
   - Edge Function timeout ⇒ coordinator emits evaluationTimeout, locks, surfaces paywall messaging.
   - Logging failure ⇒ retry once; on repeated failure mark state locked with serverSync reason to fail closed.
   - Keychain read failure ⇒ throw DeviceIdentityError, block CTA, prompt retry; prevents attempts without device_id.
16. Operational integrity:
   - Rollback by clearing local snapshot + letting resetFromServer hydrate from Supabase; no irreversible migrations.
   - Dependencies: evaluate-session POST JSON, 3s timeout, no retries; session logger POST with one retry/backoff; identity mirror fetch/mirror with exponential backoff + deny on failure; concurrency serialized via coordinator queue.
17. Tests:
   - Invariant 1 ⇒ Unit test: coordinator + fake repo ensures attemptsUsed never exceeds 2 even if startDemo called thrice.
   - Invariant 2 ⇒ Test gating: after attempt 1 completion, evaluation result persisted and CTA blocked until resolution.
   - Invariant 3 ⇒ Test reinstall: pre-populated remote snapshot leads to locked state.
   - Logging invariant ⇒ Verify session logger mock receives start/completion metadata for both attempts.
18. Verdict: ✅ Proceed — design is appropriate and scoped
