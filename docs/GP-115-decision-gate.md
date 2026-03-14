# GP-115 Decision Gate

## Why a decision is required
- GP-115 originally claimed reinstall-safe quota recovery, but the implemented lookup key was `UIDevice.identifierForVendor`, which is not an approved durable identity and does not establish ownership-safe recovery semantics.
- Shipping that contract as-is would misstate product behavior and leave the server-side recovery path without a trustworthy rebinding model.

## What we're trying to achieve
- Outcome: keep the two-attempt demo quota deterministic without promising recovery guarantees the system cannot safely prove.
- Who it impacts: iOS demo users, QA, and reviewers validating quota persistence behavior.
- Constraints (security/compliance/cost/timeline): no approved durable recovery identity exists for this run; the fix must stay scoped to GP-115 and preserve idempotent server-side quota state.

## Options (pick one)
### Option A — MVP / quick test
- What it means: support quota recovery only while the client retains its keychain-backed `device_id`; remove reinstall-safe claims and disable the unsupported lookup-key recovery endpoints.
- Pros: truthful contract, no unsafe identity rebinding, minimal reversible diff, no new auth surface.
- Cons / risks: full uninstall/reinstall is no longer a supported recovery path.
- What we are explicitly not doing (out of scope): no server-verifiable durable identity, no account-linking trust model, no migration for orphaned lookup keys.

### Option B — Scale-ready / production grade
- What it means: introduce an approved reinstall-stable recovery identity with ownership checks and idempotent server-side binding rules.
- Pros: would support deterministic uninstall/reinstall recovery.
- Cons / risks: requires product/security approval, a trust model, migration/backfill strategy, and additional validation not present in GP-115.
- What it requires (infra, observability, reliability, cost): new identity contract, server auth rules, rebinding policy, rollout monitoring, and explicit acceptance from PM/security.

## Questions (max 5)
1. Should GP-115 ship truthful same-install continuity now, or wait for a durable recovery identity design?
2. Is there any approved ownership proof available for rebinding a recovery key to a `device_id`?
3. Must full uninstall/reinstall remain in scope for MVP acceptance, or can it be deferred?

## Recommendation
- Recommend Option A because it is the only safe contract supported by current evidence, and it removes a misleading reinstall guarantee without expanding scope.

## Tags
- [NEEDS-PM]
- [NEEDS-BA]
- [NEEDS-SECURITY]
- [NEEDS-ENG]

## Resolution
- This run implements **Option A**.
- Supported behavior: quota state rehydrates only while the same keychain-backed `device_id` remains available to the client.
- Unsupported behavior: full uninstall/reinstall recovery and lookup-key identity reconstruction.

## Objective
- Keep the GP-115 demo quota deterministic and truthful without promising reinstall-safe recovery that the current design cannot safely enforce.

## Scope
- Remove the client lookup-key recovery path.
- Disable the unsupported identity-recovery edge functions.
- Preserve quota snapshot hydration keyed by the existing keychain-backed `device_id`.
- Fix duplicate completion-log idempotency and update docs/tests.

## Acceptance Criteria
- Docs and code no longer claim reinstall-safe recovery.
- `identifierForVendor` is not used as proof of quota recovery.
- Duplicate completion submissions preserve the first completion audit payload.
- Swift and Deno coverage validate the narrowed recovery contract and idempotent retry behavior.

## How to test
- Run the targeted Swift demo-quota tests.
- Run the targeted Deno repository idempotency test.
- Run the relevant full Swift and Deno suites.
- Verify docs instruct cold-start/keychain continuity rather than uninstall/reinstall recovery.
