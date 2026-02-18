# GP-115 Demo Quota State Machine

## Purpose
Enforce the two-attempt demo quota per device while keeping Supabase logging + LLM gate authoritative. The state machine is pure and provides the intent-level side effects that `DemoQuotaCoordinator` executes (Supabase calls, persistence, UI routing).

## States
| State | Meaning |
| --- | --- |
| `Fresh` | No attempts recorded locally or remotely. Device can start attempt #1 immediately. |
| `FirstAttemptActive` | Attempt #1 session started and in progress. Start log was emitted. |
| `GatePending` | Attempt #1 finished and logging completed. Waiting on the Supabase `evaluate-session` Edge Function response. UI shows “Checking…” and the CTA is disabled. |
| `SecondAttemptEligible` | Supabase explicitly allowed exactly one more attempt. CTA copy switches to “One more go”. |
| `SecondAttemptActive` | Attempt #2 session is running. Logging for attempt #2 start was sent. |
| `Locked(reason)` | No further demos allowed. CTA routes to paywall. `reason` tracks whether the lock comes from quota exhausted, evaluation deny, timeout, or server sync. |

## Events
| Event | Description |
| --- | --- |
| `startAttempt` | User tapped the CTA and coordinator authorized the next attempt. State determines the attempt index (1 or 2). |
| `attemptCompleted` | Demo flow finished and coordinator has emitted the completion log. |
| `evaluationAllow` | Supabase Edge Function responded with `allowAnotherDemo=true`. |
| `evaluationDeny` | Supabase Edge Function responded false or returned a validation error. |
| `evaluationTimeout` | Evaluate call timed out (>3 s) or failed (network/server). This is treated as a deny. |
| `resetFromServer(snapshot)` | Local repo backfilled from Supabase mirror logs (during cold start or reinstall). Snapshot contains `{attemptsUsed, lastDecision}`. |

## Reducer signature
```swift
struct DemoQuotaStateMachine {
    struct Result {
        let state: State
        let sideEffects: [SideEffect]
    }

    func reduce(state: State, event: Event) -> Result
}
```

### Side effects intents
| Intent | When emitted |
| --- | --- |
| `.logAttemptStart(index)` | `startAttempt` transitioning `Fresh → FirstAttemptActive` or `SecondAttemptEligible → SecondAttemptActive`. Coordinator sends Supabase session log (`stage=start`). |
| `.logAttemptCompletion(index)` | `attemptCompleted` from active states. Coordinator sends completion log (`stage=complete`). |
| `.persistAttemptsUsed(count)` | After completion events move the machine forward so attempt counts survive restarts. |
| `.requestEvaluation(attemptIndex: 1)` | `FirstAttemptActive → GatePending`. Coordinator invokes evaluate-session with device_id metadata. |
| `.persistEvaluationDecision(decision)` | When `GatePending` resolves. Decision is `.allowSecondAttempt` or `.locked(reason)`. |
| `.syncFromServer(snapshot)` | `resetFromServer` reduces directly to the server-reported state and persists it. |

## Transition matrix (superset)
| Current | Event | Next | Supabase call? | Persistence |
| --- | --- | --- | --- | --- |
| `Fresh` | `startAttempt` | `FirstAttemptActive` | log attempt start (index 1) | mark active attempt index 1 |
| `FirstAttemptActive` | `attemptCompleted` | `GatePending` | log completion index 1 | `attemptsUsed = 1`, request evaluation |
| `GatePending` | `evaluationAllow` | `SecondAttemptEligible` | none (coordinator already has response) | store decision `.allowSecondAttempt` |
| `GatePending` | `evaluationDeny` / `evaluationTimeout` | `Locked(reason)` | none | store decision `.locked(reason)` |
| `SecondAttemptEligible` | `startAttempt` | `SecondAttemptActive` | log start index 2 | persist active attempt index 2 |
| `SecondAttemptActive` | `attemptCompleted` | `Locked(.quotaExhausted)` | log completion index 2 | `attemptsUsed = 2` |
| Any non-`Locked` | `resetFromServer(snapshot)` | depends on snapshot | none | persist snapshot |
| Any | `resetFromServer(snapshot)` where `attemptsUsed >= 2` or decision deny | `Locked` | none | persist snapshot |

## Diagram
```
Fresh --start--> FirstAttemptActive --complete--> GatePending --allow--> SecondAttemptEligible --start--> SecondAttemptActive --complete--> Locked
                                        \--deny/timeout--> Locked
resetFromServer(snapshot) projects directly into Fresh / SecondAttemptEligible / Locked depending on attemptsUsed + decision.
```

## Notes
- Only attempt #1 triggers the evaluate-session Edge Function. Attempt #2 completion transitions straight to `Locked` and never re-enters GatePending.
- Network failures (timeout/error) while calling `evaluate-session` must emit `evaluationTimeout` so the reducer lands in `Locked` but still captures the decision for audits.
- Locked is absorbing. Any future quota resets must come from a top-level Reset (e.g., purchase) and would use a new event, not `resetFromServer`.
- The reducer remains pure; all HTTP, Keychain, and persistence work happens in the coordinator when it processes the side-effect intents returned alongside the next state.
