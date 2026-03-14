import { z } from 'zod';
import { HttpError, jsonResponse } from '../demo-quota/http.ts';
import type {
  DemoQuotaAttemptLog,
  DemoQuotaEvaluationDecision,
  DemoQuotaLockReason,
  DemoQuotaSnapshot,
} from '../demo-quota/types.ts';
import { transition, type EvaluateSessionState } from './state-machine.ts';
import type {
  EvaluateSessionRequest,
  EvaluateSessionResponse,
  LLMResult,
  RateLimitSnapshot,
} from './types.ts';

export type EvaluateSessionHandlerDependencies = {
  config: { llmTimeoutMs: number };
  rateLimiter: { evaluate(deviceId: string): Promise<RateLimitSnapshot> };
  sessionRepository: {
    findAttempt(deviceId: string, attemptIndex: number): Promise<{
      id: string;
      session_id: string;
      state: string;
      payload_version: string;
      fallback_used: boolean;
      request_payload: Record<string, unknown>;
      llm_response: Record<string, unknown>;
      moderation_payload: Record<string, unknown>;
      reason: string | null;
    } | null>;
    persist(
      request: EvaluateSessionRequest,
      llm: LLMResult,
      state: string,
      reason: string | undefined,
      correlationId: string,
      fallbackUsed: boolean,
    ): Promise<{
      session?: { id: string };
      demo_attempt?: {
        id: string;
        request_payload: Record<string, unknown>;
        llm_response: Record<string, unknown>;
        moderation_payload: Record<string, unknown>;
      };
    }>;
  };
  quotaRepository: {
    fetchSnapshot(deviceId: string): Promise<DemoQuotaSnapshot | null>;
    fetchAttemptLog(deviceId: string, attemptIndex: number): Promise<DemoQuotaAttemptLog | null>;
    snapshotFromDecision(
      existing: DemoQuotaSnapshot | null,
      attemptLogs: DemoQuotaAttemptLog[],
      decision: {
        allowAnotherDemo: boolean;
        type: 'allow' | 'deny' | 'timeout';
        message?: string;
        lockReason?: 'quota' | 'evaluation_denied' | 'evaluation_timeout' | 'server_sync';
        attemptsUsed: number;
        evaluatedAt: string;
      },
    ): DemoQuotaSnapshot;
    persistDecisionSnapshot(deviceId: string, snapshot: DemoQuotaSnapshot): Promise<DemoQuotaSnapshot>;
  };
  llmProvider: {
    generate(
      input: EvaluateSessionRequest['input'],
      opts?: { signal?: AbortSignal },
    ): Promise<LLMResult>;
  };
  logger: { error(message: string, context: Record<string, unknown>): void };
};

const RequestSchema = z.object({
  device_id: z.string().min(1, 'device_id is required'),
  attempt_index: z.number().int().positive(),
  payload_version: z.string().min(1).default('v1'),
  input: z.object({
    prompt: z.string().min(1, 'prompt is required'),
    context: z.record(z.string(), z.unknown()).optional(),
  }),
  metadata: z.record(z.string(), z.unknown()).optional(),
});

export function buildEvaluateSessionHandler(deps: EvaluateSessionHandlerDependencies) {
  return async (req: Request): Promise<Response> => {
    const correlationId = crypto.randomUUID();
    let state: EvaluateSessionState = 'RECEIVED';

    try {
      if (req.method !== 'POST') {
        throw new HttpError(405, 'Only POST supported');
      }

      const request = await parseRequest(req);
      const parsed = RequestSchema.parse(request) as EvaluateSessionRequest;
      state = transition(state, { type: 'VALIDATION_SUCCEEDED' });

      const duplicate = await deps.sessionRepository.findAttempt(parsed.device_id, parsed.attempt_index);
      const existingSnapshot = await deps.quotaRepository.fetchSnapshot(parsed.device_id);

      if (duplicate) {
        return jsonResponse(buildDuplicateResponse(parsed, duplicate, correlationId, existingSnapshot), 409);
      }

      const rateSnapshot = await deps.rateLimiter.evaluate(parsed.device_id);
      if (!rateSnapshot.allowed) {
        state = transition(state, { type: 'RATE_LIMITED' });
        return jsonResponse(buildRateLimitedResponse(parsed, rateSnapshot, correlationId, existingSnapshot), 429);
      }

      const attemptLog = await deps.quotaRepository.fetchAttemptLog(parsed.device_id, parsed.attempt_index);
      const evaluatedAt = new Date().toISOString();
      const completedAttemptCount = Math.max(
        existingSnapshot?.attempts_used ?? 0,
        attemptLog?.completed_at ? attemptLog.attempt_index : 0,
      );

      let decision: DemoQuotaEvaluationDecision;
      let llmResult: LLMResult;
      let fallbackUsed = false;
      let failureReason: string | undefined;
      let persistedState = 'COMPLETED';

      if (parsed.attempt_index !== 1) {
        decision = denyDecision('This device has already used its free demos.', 'quota', completedAttemptCount, evaluatedAt);
        llmResult = buildDecisionResponse(parsed, decision, 'quota_rule');
        persistedState = 'REJECTED';
      } else if (!attemptLog?.completed_at) {
        decision = denyDecision('We could not verify the completed demo session.', 'server_sync', completedAttemptCount, evaluatedAt);
        llmResult = buildDecisionResponse(parsed, decision, 'missing_completion');
        persistedState = 'REJECTED';
      } else if (completedAttemptCount >= 2 || existingSnapshot?.server_lock_reason === 'quota') {
        decision = denyDecision('This device has already used its free demos.', 'quota', Math.max(completedAttemptCount, 2), evaluatedAt);
        llmResult = buildDecisionResponse(parsed, decision, 'quota_rule');
        persistedState = 'REJECTED';
      } else if (existingSnapshot?.last_decision?.type === 'timeout') {
        decision = timeoutDecision(completedAttemptCount, existingSnapshot.last_decision.ts);
        llmResult = buildDecisionResponse(parsed, decision, 'prior_timeout');
        fallbackUsed = true;
        failureReason = 'llm_timeout';
        persistedState = 'FALLBACK_TIMEOUT';
      } else if (existingSnapshot?.last_decision?.type === 'deny') {
        decision = denyDecision(
          existingSnapshot.last_decision.message ?? 'We can’t offer another free demo right now.',
          coerceDenyLockReason(existingSnapshot.server_lock_reason),
          completedAttemptCount,
          existingSnapshot.last_decision.ts,
        );
        llmResult = buildDecisionResponse(parsed, decision, 'prior_deny');
        fallbackUsed = true;
        failureReason = 'llm_error';
        persistedState = 'FALLBACK_DENY';
      } else {
        state = transition(state, { type: 'LLM_DELEGATED' });
        try {
          llmResult = await deps.llmProvider.generate(parsed.input, {
            signal: AbortSignal.timeout(deps.config.llmTimeoutMs),
          });
          state = transition(state, { type: 'LLM_SUCCEEDED' });
          decision = allowDecision(completedAttemptCount || 1, evaluatedAt);
        } catch (error) {
          fallbackUsed = true;
          if (error instanceof DOMException && error.name === 'AbortError') {
            state = transition(state, { type: 'LLM_FAILED', reason: 'timeout' });
            failureReason = 'llm_timeout';
            decision = timeoutDecision(completedAttemptCount || 1, evaluatedAt);
            persistedState = 'FALLBACK_TIMEOUT';
          } else {
            state = transition(state, { type: 'LLM_FAILED', reason: 'provider_error' });
            failureReason = 'llm_error';
            decision = denyDecision('We can’t offer another free demo right now.', 'evaluation_denied', completedAttemptCount || 1, evaluatedAt);
            persistedState = 'FALLBACK_DENY';
          }
          llmResult = buildDecisionResponse(parsed, decision, failureReason);
        }
      }

      const persistResult = await deps.sessionRepository.persist(
        parsed,
        llmResult,
        persistedState,
        failureReason ?? decision.type,
        correlationId,
        fallbackUsed,
      );

      const snapshot = deps.quotaRepository.snapshotFromDecision(
        existingSnapshot,
        attemptLog ? [attemptLog] : [],
        {
          allowAnotherDemo: decision.allowAnotherDemo,
          type: decision.type,
          message: decision.message,
          lockReason: decision.lockReason,
          attemptsUsed: decision.attemptsUsed,
          evaluatedAt: decision.evaluatedAt,
        },
      );
      const persistedSnapshot = await deps.quotaRepository.persistDecisionSnapshot(parsed.device_id, snapshot);

      if (state === 'PERSISTING') {
        state = transition(state, { type: 'PERSISTED' });
      }

      return jsonResponse({
        correlation_id: correlationId,
        state: persistedState,
        session_id: persistResult.session?.id,
        attempt_id: persistResult.demo_attempt?.id,
        payload_version: parsed.payload_version,
        allow_another_demo: decision.allowAnotherDemo,
        attempts_used: persistedSnapshot.attempts_used,
        evaluated_at: decision.evaluatedAt,
        lock_reason: decision.lockReason,
        fallback_used: fallbackUsed,
        message: decision.message,
        reason: failureReason ?? decision.type,
        request: persistResult.demo_attempt?.request_payload ?? buildRequestPayload(parsed),
        response: llmResult.response,
        moderation: llmResult.moderation,
        snapshot: persistedSnapshot,
        rate_limit: rateSnapshot,
      } satisfies EvaluateSessionResponse, 200);
    } catch (error) {
      if (error instanceof z.ZodError) {
        const zodError = error as z.ZodError;
        return jsonResponse({
          correlation_id: correlationId,
          state,
          error: 'invalid_body',
          details: zodError.issues,
        }, 400);
      }
      if (error instanceof HttpError) {
        return jsonResponse({ correlation_id: correlationId, state, error: error.message }, error.status);
      }
      deps.logger.error('Unhandled evaluate-session error', { correlationId, error: `${error}` });
      return jsonResponse({
        correlation_id: correlationId,
        state,
        error: 'internal_error',
      }, 500);
    }
  };
}

async function parseRequest(req: Request): Promise<unknown> {
  try {
    return await req.json();
  } catch {
    throw new HttpError(400, 'Invalid JSON body');
  }
}

function buildDuplicateResponse(
  request: EvaluateSessionRequest,
  duplicate: {
    id: string;
    session_id: string;
    state: string;
    payload_version: string;
    fallback_used: boolean;
    request_payload: Record<string, unknown>;
    llm_response: Record<string, unknown>;
    moderation_payload: Record<string, unknown>;
    reason: string | null;
  },
  correlationId: string,
  snapshot: DemoQuotaSnapshot | null,
): EvaluateSessionResponse {
  const lastDecision = snapshot?.last_decision;
  return {
    correlation_id: correlationId,
    state: duplicate.state,
    session_id: duplicate.session_id,
    attempt_id: duplicate.id,
    payload_version: duplicate.payload_version,
    allow_another_demo: lastDecision?.type === 'allow',
    attempts_used: snapshot?.attempts_used ?? request.attempt_index,
    evaluated_at: lastDecision?.ts ?? new Date().toISOString(),
    lock_reason: snapshot?.server_lock_reason ?? undefined,
    fallback_used: duplicate.fallback_used,
    message: lastDecision?.message,
    reason: duplicate.reason ?? 'duplicate_attempt',
    request: duplicate.request_payload,
    response: duplicate.llm_response,
    moderation: duplicate.moderation_payload,
    snapshot: snapshot ?? emptySnapshot(),
    rate_limit: emptyRateLimitSnapshot(),
  };
}

function buildRateLimitedResponse(
  request: EvaluateSessionRequest,
  rateLimit: RateLimitSnapshot,
  correlationId: string,
  snapshot: DemoQuotaSnapshot | null,
): EvaluateSessionResponse {
  return {
    correlation_id: correlationId,
    state: 'RATE_LIMITED',
    payload_version: request.payload_version,
    allow_another_demo: false,
    attempts_used: snapshot?.attempts_used ?? 0,
    evaluated_at: new Date().toISOString(),
    lock_reason: snapshot?.server_lock_reason ?? 'evaluation_denied',
    fallback_used: true,
    message: 'Rate limit exceeded',
    reason: 'rate_limited',
    snapshot: snapshot ?? emptySnapshot(),
    rate_limit: { ...rateLimit, allowed: false },
  };
}

function buildRequestPayload(request: EvaluateSessionRequest): Record<string, unknown> {
  return {
    input: request.input,
    metadata: request.metadata ?? {},
    attempt_index: request.attempt_index,
  };
}

function buildDecisionResponse(
  request: EvaluateSessionRequest,
  decision: DemoQuotaEvaluationDecision,
  reason: string | undefined,
): LLMResult {
  return {
    model: 'quota-authority',
    response: {
      summary: decision.allowAnotherDemo
        ? 'Second demo attempt approved'
        : decision.message ?? 'Second demo attempt denied',
      guidance: [
        `attempt_index=${request.attempt_index}`,
        `decision=${decision.type}`,
      ],
      tokens_used: 0,
    },
    moderation: { flagged: false, categories: [] },
    reason,
  };
}

function allowDecision(attemptsUsed: number, evaluatedAt: string): DemoQuotaEvaluationDecision {
  return {
    allowAnotherDemo: true,
    type: 'allow',
    attemptsUsed: Math.max(1, attemptsUsed),
    evaluatedAt,
    source: 'llm',
  };
}

function denyDecision(
  message: string,
  lockReason: 'quota' | 'evaluation_denied' | 'evaluation_timeout' | 'server_sync',
  attemptsUsed: number,
  evaluatedAt: string,
): DemoQuotaEvaluationDecision {
  return {
    allowAnotherDemo: false,
    type: 'deny',
    message,
    lockReason,
    attemptsUsed: Math.max(1, attemptsUsed),
    evaluatedAt,
    source: 'quota',
  };
}

function coerceDenyLockReason(lockReason: DemoQuotaLockReason | null): 'quota' | 'evaluation_denied' | 'evaluation_timeout' | 'server_sync' {
  return lockReason ?? 'evaluation_denied';
}

function timeoutDecision(attemptsUsed: number, evaluatedAt: string): DemoQuotaEvaluationDecision {
  return {
    allowAnotherDemo: false,
    type: 'timeout',
    lockReason: 'evaluation_timeout',
    attemptsUsed: Math.max(1, attemptsUsed),
    evaluatedAt,
    source: 'llm',
  };
}

function emptySnapshot(): DemoQuotaSnapshot {
  return {
    attempts_used: 0,
    active_attempt_index: null,
    last_decision: null,
    server_lock_reason: null,
    last_sync_at: null,
  };
}

function emptyRateLimitSnapshot(): RateLimitSnapshot {
  return {
    allowed: true,
    attempt_count: 0,
    window_start: new Date().toISOString(),
    limit: 0,
    window_seconds: 0,
  };
}
