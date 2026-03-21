import type { EvaluateSessionDecision } from './types.ts';
import type { EvaluateSessionState } from './state-machine.ts';

const DEFAULT_DENY_MESSAGE = 'We can’t offer another free demo right now.';
const RATE_LIMIT_MESSAGE = 'Free demo eligibility is temporarily rate limited. Try again shortly.';
const TIMEOUT_MESSAGE = 'Eligibility check timed out. Please retry.';

export function buildDecision(
  state: EvaluateSessionState,
  reason?: string | null,
): EvaluateSessionDecision {
  switch (state) {
    case 'COMPLETED':
      return { outcome: 'allow' };
    case 'FALLBACK_TIMEOUT':
      return {
        outcome: 'timeout',
        message: TIMEOUT_MESSAGE,
      };
    case 'RATE_LIMITED':
      return {
        outcome: 'deny',
        message: RATE_LIMIT_MESSAGE,
      };
    case 'FALLBACK_DENY':
    case 'REJECTED':
      return {
        outcome: 'deny',
        message: messageForReason(reason) ?? DEFAULT_DENY_MESSAGE,
      };
    case 'RECEIVED':
    case 'VALIDATING':
    case 'DELEGATING_LLM':
    case 'PERSISTING':
      return {
        outcome: 'timeout',
        message: TIMEOUT_MESSAGE,
      };
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
