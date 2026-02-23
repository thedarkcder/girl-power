export type EvaluateSessionInput = {
  prompt: string;
  context?: Record<string, unknown>;
};

export type EvaluateSessionRequest = {
  device_id: string;
  attempt_index: number;
  payload_version: string;
  input: EvaluateSessionInput;
  metadata?: Record<string, unknown>;
};

export type RateLimitSnapshot = {
  allowed: boolean;
  attempt_count: number;
  window_start: string;
  limit: number;
  window_seconds: number;
};

export type LLMResponse = {
  summary: string;
  guidance: string[];
  tokens_used: number;
};

export type LLMResult = {
  model: string;
  response: LLMResponse;
  moderation: {
    flagged: boolean;
    categories: string[];
  };
  reason?: string;
};

export type PersistedSession = {
  id: string;
  device_id: string;
  session_state: string;
  llm_payload: Record<string, unknown>;
  payload_version: string;
  fallback_used: boolean;
  decision: string | null;
  correlation_id: string;
  created_at: string;
};

export type PersistedAttempt = {
  id: string;
  session_id: string;
  device_id: string;
  attempt_index: number;
  payload_version: string;
  request_payload: Record<string, unknown>;
  llm_response: Record<string, unknown>;
  moderation_payload: Record<string, unknown>;
  state: string;
  reason: string | null;
  fallback_used: boolean;
  rate_limit_window_start: string | null;
  created_at: string;
};

export type PersistEvaluateSessionResult = {
  status: 'created' | 'duplicate' | 'rate_limited';
  session?: PersistedSession;
  demo_attempt?: PersistedAttempt;
  attempt_count?: number;
  window_start?: string;
};

export type EvaluateSessionResponse = {
  correlation_id: string;
  state: string;
  session_id?: string;
  attempt_id?: string;
  payload_version: string;
  fallback_used: boolean;
  reason?: string;
  request?: Record<string, unknown>;
  response?: Record<string, unknown>;
  moderation?: Record<string, unknown>;
  rate_limit: RateLimitSnapshot;
};
