export type EvaluateSessionState =
  | 'RECEIVED'
  | 'VALIDATING'
  | 'RATE_LIMITED'
  | 'REJECTED'
  | 'DELEGATING_LLM'
  | 'PERSISTING'
  | 'COMPLETED'
  | 'FALLBACK_DENY'
  | 'FALLBACK_TIMEOUT';

export type EvaluateSessionEvent =
  | { type: 'VALIDATION_SUCCEEDED' }
  | { type: 'VALIDATION_FAILED' }
  | { type: 'RATE_LIMITED' }
  | { type: 'LLM_DELEGATED' }
  | { type: 'LLM_FAILED'; reason: 'timeout' | 'provider_error' }
  | { type: 'LLM_SUCCEEDED' }
  | { type: 'PERSISTING' }
  | { type: 'PERSISTED' }
  | { type: 'PERSIST_FAILED' };

export function transition(
  current: EvaluateSessionState,
  event: EvaluateSessionEvent,
): EvaluateSessionState {
  switch (current) {
    case 'RECEIVED':
      if (event.type === 'VALIDATION_SUCCEEDED') return 'VALIDATING';
      if (event.type === 'VALIDATION_FAILED') return 'REJECTED';
      break;
    case 'VALIDATING':
      if (event.type === 'RATE_LIMITED') return 'RATE_LIMITED';
      if (event.type === 'LLM_DELEGATED') return 'DELEGATING_LLM';
      if (event.type === 'VALIDATION_FAILED') return 'REJECTED';
      break;
    case 'DELEGATING_LLM':
      if (event.type === 'LLM_FAILED') {
        return event.reason === 'timeout' ? 'FALLBACK_TIMEOUT' : 'FALLBACK_DENY';
      }
      if (event.type === 'LLM_SUCCEEDED') return 'PERSISTING';
      break;
    case 'PERSISTING':
      if (event.type === 'PERSISTED') return 'COMPLETED';
      if (event.type === 'PERSIST_FAILED') return 'FALLBACK_DENY';
      break;
    case 'RATE_LIMITED':
    case 'REJECTED':
    case 'FALLBACK_DENY':
    case 'FALLBACK_TIMEOUT':
    case 'COMPLETED':
      return current;
  }
  return current;
}
