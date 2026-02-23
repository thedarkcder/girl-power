import type { SupabaseClient } from '@supabase/supabase-js';
import type { RuntimeConfig } from './config.ts';
import type {
  EvaluateSessionRequest,
  LLMResult,
  PersistEvaluateSessionResult,
  PersistedAttempt,
} from './types.ts';

export class SessionRepository {
  constructor(
    private readonly client: SupabaseClient,
    private readonly config: Pick<RuntimeConfig, 'rateLimitAttempts' | 'rateLimitWindowSeconds'>,
  ) {}

  async findAttempt(deviceId: string, attemptIndex: number): Promise<PersistedAttempt | null> {
    const { data, error } = await this.client
      .from('demo_attempts')
      .select(
        'id, session_id, device_id, attempt_index, payload_version, request_payload, llm_response, moderation_payload, state, reason, fallback_used, rate_limit_window_start, created_at',
      )
      .eq('device_id', deviceId)
      .eq('attempt_index', attemptIndex)
      .maybeSingle<PersistedAttempt>();

    if (error && error.code !== 'PGRST116') {
      throw new Error(`Failed to query demo_attempt: ${error.message}`);
    }

    return data ?? null;
  }

  async persist(
    request: EvaluateSessionRequest,
    llm: LLMResult,
    state: string,
    reason: string | undefined,
    correlationId: string,
    fallbackUsed: boolean,
  ): Promise<PersistEvaluateSessionResult> {
    const { data, error } = await this.client.rpc('persist_evaluate_session', {
      p_device_id: request.device_id,
      p_attempt_index: request.attempt_index,
      p_payload_version: request.payload_version,
      p_request: buildRequestPayload(request),
      p_response: llm.response,
      p_moderation: llm.moderation,
      p_state: state,
      p_reason: reason ?? null,
      p_fallback_used: fallbackUsed,
      p_correlation_id: correlationId,
      p_decision: llm.reason ?? 'completed',
      p_rate_limit_window_seconds: this.config.rateLimitWindowSeconds,
      p_max_attempts: this.config.rateLimitAttempts,
    }) as { data: PersistEvaluateSessionResult | null; error: { message: string } | null };

    if (error || !data) {
      throw new Error(`persist_evaluate_session failed: ${error?.message ?? 'unknown error'}`);
    }

    return data;
  }
}

function buildRequestPayload(request: EvaluateSessionRequest): Record<string, unknown> {
  return {
    input: request.input,
    metadata: request.metadata ?? {},
    attempt_index: request.attempt_index,
  };
}
