> **2026-03-14 Decision Gate resolution:** GP-115 supports quota recovery only while the client retains its keychain-backed `device_id`. Full uninstall/reinstall recovery is out of scope until an approved durable identity contract exists.
1. Problem: Guarantee each device is limited to two Squat Coaching demos while its keychain-backed identity remains available and Supabase + LLM keep the gate authoritative.
2. Type: Workflow / long-running process
3. Invariants:
   - Device ID uniquely ties attempts so local + remote state never allow >2 tries.
   - Attempt #1 completion always triggers evaluate-session once and blocks CTA until decision stored.
   - attempt_index=2 never re-triggers evaluation and always transitions to locked/quota exhausted after completion.
   - Every attempt start/completion produces a Supabase log row with metadata.
4. Assumptions:
   - Supabase Edge Function evaluate-session is reachable via env-configured URL; if not, coordinator denies attempt #2 to fail closed.
   - The supported identity contract is the keychain-backed device UUID; if that identity is removed, the server does not attempt to recover it from another lookup key.
   - Supabase Edge Functions own LLM/service keys; the client only needs anon/service tokens already safe to ship.
5. Contract matrix:
   - No snapshot + remote attemptsUsed=0 ⇒ state fresh, allow attempt #1 start and emit start log, unchanged.
   - attemptsUsed=1 + no decision ⇒ gatePending, disable CTA, fire single evaluate-session request, intentional new behavior.
   - attemptsUsed=1 + decision.allow ⇒ secondAttemptEligible, show “One more go” CTA once then lock after second completion, intentional new.
   - attemptsUsed≥2 or decision deny/timeout/serverLock ⇒ locked(reason), route to paywall while the keychain-backed identity remains available, intentional reinforcement.
6. Call-path impact scan:
   - AppFlowViewModel.startDemo() → DemoQuotaCoordinator.markAttemptStarted(); must short-circuit navigation when locked or pending.
   - DemoAttemptFlowView exit → DemoQuotaCoordinator.markAttemptCompleted(); needs metadata for logging.
   - GirlPowerApp cold start → coordinator.prepareForDemoStart(); hydrates local state from Supabase mirror/log repo before showing CTA when the same keychain-backed identity is still present.
7. Domain term contracts:
   - demo attempt = full Squat Coaching flow; counted even if crash after logging start.
   - device_id = keychain-backed UUID generated and persisted on-device; server snapshot state is keyed by that identifier and does not claim reinstall-safe recovery.
   - decision = canonical evaluate-session response object; `decision.outcome = "allow"` is the only path that can open the second attempt when attemptsUsed==1, and the persisted decision prevents re-evaluation.
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
   - Provide keychain-backed device identity generation plus Supabase snapshot fetch/mirror to hydrate state on cold start while that identity remains available.
   - Expose immutable async getters + Combine publisher to Demo CTA so UI copies (“Start Free Demo”, “One more go”, “Checking…”, locked reason) stay in sync.
11. Patterns used:
   - Deterministic reducer + coordinator ensures explicit transitions.
   - Protocol-based DI for persistence/logging/evaluation allows unit tests without touching Supabase.
   - Keychain identity + remote snapshot mirror preserves deterministic same-device continuity without inventing an unapproved recovery contract.
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
   - Dependencies: evaluate-session POST JSON, 3s timeout, no retries; session logger POST with one retry/backoff; snapshot fetch/mirror keyed by the existing device_id; concurrency serialized via coordinator queue.
17. Tests:
   - Invariant 1 ⇒ Unit test: coordinator + fake repo ensures attemptsUsed never exceeds 2 even if startDemo called thrice.
   - Invariant 2 ⇒ Test gating: after attempt 1 completion, evaluation result persisted and CTA blocked until resolution.
   - Invariant 3 ⇒ Test cold start: pre-populated remote snapshot leads to locked state while the same keychain-backed identity is reused.
   - Logging invariant ⇒ Verify session logger mock receives start/completion metadata for both attempts.
18. Verdict: ✅ Proceed — design is appropriate and scoped
