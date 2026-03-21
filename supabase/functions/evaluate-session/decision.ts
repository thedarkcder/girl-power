import type { EvaluateSessionDecision } from './types.ts';
import type { DemoQuotaLockReason } from '../demo-quota/types.ts';
import type { EvaluateSessionState } from './state-machine.ts';

const DEFAULT_DENY_MESSAGE = 'We can’t offer another free demo right now.';
const RATE_LIMIT_MESSAGE = 'Free demo eligibility is temporarily rate limited. Try again shortly.';
const TIMEOUT_MESSAGE = 'Eligibility check timed out. Please retry.';

export function buildDecision(
  state: EvaluateSessionState,
  reason?: string | null,
  overrides: {
    message?: string;
    lockReason?: DemoQuotaLockReason | null;
  } = {},
): EvaluateSessionDecision {
  switch (state) {
    case 'COMPLETED':
      return { outcome: 'allow' };
    case 'FALLBACK_TIMEOUT':
      return withLockReason({
        outcome: 'timeout',
        message: overrides.message ?? TIMEOUT_MESSAGE,
      }, overrides.lockReason);
    case 'RATE_LIMITED':
      return withLockReason({
        outcome: 'deny',
        message: overrides.message ?? RATE_LIMIT_MESSAGE,
      }, overrides.lockReason);
    case 'FALLBACK_DENY':
    case 'REJECTED':
      return withLockReason({
        outcome: 'deny',
        message: overrides.message ?? messageForReason(reason) ?? DEFAULT_DENY_MESSAGE,
      }, overrides.lockReason);
    case 'RECEIVED':
    case 'VALIDATING':
    case 'DELEGATING_LLM':
    case 'PERSISTING':
      return withLockReason({
        outcome: 'timeout',
        message: overrides.message ?? TIMEOUT_MESSAGE,
      }, overrides.lockReason);
  }
}

function messageForReason(reason?: string | null): string | undefined {
  switch (reason) {
    case 'rate_limited':
      return RATE_LIMIT_MESSAGE;
    case 'llm_timeout':
      return TIMEOUT_MESSAGE;
    case 'provider_error':
    case 'llm_error':
      return DEFAULT_DENY_MESSAGE;
    default:
      return undefined;
  }
}

function withLockReason(
  decision: EvaluateSessionDecision,
  lockReason?: DemoQuotaLockReason | null,
): EvaluateSessionDecision {
  if (!lockReason) {
    return decision;
  }
  return {
    ...decision,
    lock_reason: lockReason,
  };
}
