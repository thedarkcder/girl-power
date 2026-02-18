# GP-116 SquatSession Summary State Machine

## States
1. `idle`
2. `permissionsPending`
3. `configuringSession`
4. `running(PosePhase)`
5. `backgroundSuspended(previousPhase: PosePhase?)`
6. `interrupted(reason: SquatSessionInterruption, previousPhase: PosePhase?)`
7. `endingError(SquatSessionError)`
8. `summary(SummaryContext)` ← **new**

`SummaryContext` = `{ summary: SessionSummary, ctaState: SummaryCTAState }` where `SummaryCTAState ∈ { awaitingDecision, secondAttemptEligible, locked(message) }` derived from the active `DemoQuotaStateMachine.State` when the attempt finished.

## Events
| Event | Description |
| --- | --- |
| `requestPermissions` | Triggered when SquatSessionCoordinator starts.
| `permissionsGranted/permissionsDenied` | Permission outcomes.
| `configurationStarted/configurationSucceeded/configurationFailed` | Camera+Vision pipeline prep results.
| `posePhaseChanged(PosePhase)` | Continuous updates while running.
| `enteredBackground/resumedForeground` | Lifecycle notifications.
| `interruptionBegan/Ended` | Capture/audio interruptions.
| `fatalError` | Hard failure anywhere in the pipeline.
| `sessionEnded` | Legacy stop path (no summary) → resets to `idle`.
| `summaryReady(SummaryContext)` | **New**: emitted by `SquatSessionCoordinator.completeSession` after computing `SessionSummary` and mapping the latest DemoQuota-derived CTA state. Transitions `running` → `summary`.

## Transition sketch
```
idle --requestPermissions--> permissionsPending
permissionsPending --granted--> configuringSession --succeeded--> running
running --posePhase--> running (loop)
running --enteredBackground--> backgroundSuspended --resumedForegound--> configuringSession
running --interruptionBegan--> interrupted --interruptionEnded--> configuringSession
running --summaryReady--> summary --sessionEnded/startNextAttempt--> idle/configuringSession
running --fatalError--> endingError --sessionEnded--> idle
```

When `summaryReady` fires:
- Coordinator stops capture + pose pipeline.
- `SessionSummary` snapshot + `SummaryCTAState` cached via AppFlowViewModel.
- Further `posePhaseChanged` events are ignored; state machine stays in `summary` until the user exits or starts another attempt.

## Summary CTA mapping rules
| DemoQuota state | SummaryCTAState | Persistence |
| --- | --- | --- |
| `.gatePending` | `.awaitingDecision` | summary metadata + DemoQuota snapshot already persisted; summary VM listens for future transitions.
| `.secondAttemptEligible` | `.secondAttemptEligible` | cached summary keeps attempt index=1 to guard One More Go visibility.
| `.locked(reason)` or attempt index 2 | `.locked(message)` | `message` derived from lock reason; summary view shows only paywall CTA.

## Persistence & relaunch safety
- `SessionSummary` cached in `AppFlowViewModel` (MainActor) until another attempt starts or paywall is entered. No disk storage needed.
- DemoQuota state already persisted (Keychain + Supabase snapshot); upon relaunch the summary screen recomputes CTA state by reusing the stored SessionSummary and observed DemoQuota state.
- Attempt index tracked on AppFlowViewModel so relaunch cannot mis-classify One More Go visibility.

## Allowed transitions out of summary
- `summary` + `.startDemo` (from AppFlowStateMachine) → new attempt (resets NavigationStack, re-enters requesting permissions flow).
- `summary` + `.continueToPaywall` → PaywallRouter invoked; state machine resets to `idle` via `sessionEnded` once the coordinator is torn down.

## Notes
- Summary state is pure/view-only: no camera or Vision resources active.
- No timers allowed; DemoQuota state stream updates drive CTA toggles.
