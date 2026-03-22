import { z } from 'zod';
import type {
  DemoQuotaAttemptLog,
  DemoQuotaEvaluationDecision,
  DemoQuotaLockReason,
  DemoQuotaSnapshot,
} from '../demo-quota/types.ts';
import { HttpError, jsonResponse, parseJson } from '../demo-quota/http.ts';
import { buildRequestPayload, parseEvaluateSessionRequest } from './contract.ts';
import { buildDecision } from './decision.ts';
import { transition, type EvaluateSessionState } from './state-machine.ts';
import type {
  EvaluateSessionRequest,
  EvaluateSessionResponse,
  LLMResult,
  PersistedDecisionPayload,
  RateLimitSnapshot,
} from './types.ts';

type DuplicateAttempt = {
  id: string;
  session_id: string;
  state: string;
  payload_version: string;
  fallback_used: boolean;
  request_payload: Record<string, unknown>;
  llm_response: Record<string, unknown>;
  moderation_payload: Record<string, unknown>;
  reason: string | null;
  rate_limit_payload: RateLimitSnapshot;
};

type PersistResult = {
  session?: { id: string };
  demo_attempt?: {
    id: string;
    request_payload: Record<string, unknown>;
    llm_response: Record<string, unknown>;
    moderation_payload: Record<string, unknown>;
  };
  status?: 'created' | 'duplicate' | 'rate_limited';
  attempt_count?: number;
  window_start?: string;
};

export type EvaluateSessionHandlerDependencies = {
  config: { llmTimeoutMs: number };
  rateLimiter: { evaluate(deviceId: string): Promise<RateLimitSnapshot> };
  sessionRepository: {
    findAttempt(deviceId: string, attemptIndex: number): Promise<DuplicateAttempt | null>;
    persist(
      request: EvaluateSessionRequest,
      llm: LLMResult,
      state: string,
      reason: string | undefined,
      correlationId: string,
      fallbackUsed: boolean,
    ): Promise<PersistResult>;
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
        lockReason?: DemoQuotaLockReason;
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

export function buildEvaluateSessionHandler(deps: EvaluateSessionHandlerDependencies) {
  return async (req: Request): Promise<Response> => {
    const correlationId = crypto.randomUUID();
    let state: EvaluateSessionState = 'RECEIVED';

    try {
      if (req.method !== 'POST') {
        throw new HttpError(405, 'Only POST supported');
      }

      const request = await parseJson<unknown>(req);
      const parsed = parseEvaluateSessionRequest(request);
      state = transition(state, { type: 'VALIDATION_SUCCEEDED' });

      const existingSnapshot = await deps.quotaRepository.fetchSnapshot(parsed.device_id);
      const duplicate = await deps.sessionRepository.findAttempt(parsed.device_id, parsed.attempt_index);
      if (duplicate) {
        return jsonResponse(
          buildDuplicateResponse(parsed, duplicate, correlationId, existingSnapshot),
          409,
        );
      }

      const rateSnapshot = await deps.rateLimiter.evaluate(parsed.device_id);
      if (!rateSnapshot.allowed) {
        state = transition(state, { type: 'RATE_LIMITED' });
        return jsonResponse(
          buildRateLimitedResponse(parsed, rateSnapshot, correlationId),
          429,
        );
      }

      const attemptLog = await deps.quotaRepository.fetchAttemptLog(parsed.device_id, parsed.attempt_index);
      const evaluatedAt = new Date().toISOString();
      const completedAttemptCount = Math.max(
        existingSnapshot?.attempts_used ?? 0,
        attemptLog?.completed_at ? attemptLog.attempt_index : 0,
      );

      let authorityDecision: DemoQuotaEvaluationDecision;
      let llmResult: LLMResult;
      let fallbackUsed = false;
      let failureReason: string | undefined;
      let persistedState: EvaluateSessionState = 'COMPLETED';

      if (!attemptLog?.completed_at) {
        authorityDecision = denyDecision(
          'We could not verify the completed demo session.',
          'server_sync',
          completedAttemptCount,
          evaluatedAt,
        );
        llmResult = buildDecisionResponse(parsed, authorityDecision, 'missing_completion');
        persistedState = 'REJECTED';
      } else if (completedAttemptCount >= 2 || existingSnapshot?.server_lock_reason === 'quota') {
        authorityDecision = denyDecision(
          'This device has already used its free demos.',
          'quota',
          Math.max(completedAttemptCount, 2),
          evaluatedAt,
        );
        llmResult = buildDecisionResponse(parsed, authorityDecision, 'quota_rule');
        persistedState = 'REJECTED';
      } else if (existingSnapshot?.last_decision?.type === 'timeout') {
        authorityDecision = timeoutDecision(completedAttemptCount || 1, existingSnapshot.last_decision.ts);
        llmResult = buildDecisionResponse(parsed, authorityDecision, 'prior_timeout');
        fallbackUsed = true;
        failureReason = 'llm_timeout';
        persistedState = 'FALLBACK_TIMEOUT';
      } else if (existingSnapshot?.last_decision?.type === 'deny') {
        authorityDecision = denyDecision(
          existingSnapshot.last_decision.message ?? 'We can’t offer another free demo right now.',
          coerceDenyLockReason(existingSnapshot.server_lock_reason),
          completedAttemptCount || 1,
          existingSnapshot.last_decision.ts,
        );
        llmResult = buildDecisionResponse(parsed, authorityDecision, 'prior_deny');
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
          authorityDecision = allowDecision(completedAttemptCount || 1, evaluatedAt);
        } catch (error) {
          fallbackUsed = true;
          if (error instanceof DOMException && error.name === 'AbortError') {
            state = transition(state, { type: 'LLM_FAILED', reason: 'timeout' });
            failureReason = 'llm_timeout';
            authorityDecision = timeoutDecision(completedAttemptCount || 1, evaluatedAt);
            persistedState = 'FALLBACK_TIMEOUT';
          } else {
            state = transition(state, { type: 'LLM_FAILED', reason: 'provider_error' });
            failureReason = 'llm_error';
            authorityDecision = denyDecision(
              'We can’t offer another free demo right now.',
              'evaluation_denied',
              completedAttemptCount || 1,
              evaluatedAt,
            );
            persistedState = 'FALLBACK_DENY';
          }
          llmResult = buildDecisionResponse(parsed, authorityDecision, failureReason);
        }
      }

      const persistedLLMResult = attachPersistedDecision(llmResult, authorityDecision);
      const persistResult = await deps.sessionRepository.persist(
        parsed,
        persistedLLMResult,
        persistedState,
        failureReason ?? authorityDecision.type,
        correlationId,
        fallbackUsed,
      );

      await deps.quotaRepository.persistDecisionSnapshot(
        parsed.device_id,
        deps.quotaRepository.snapshotFromDecision(
          existingSnapshot,
          attemptLog ? [attemptLog] : [],
          {
            allowAnotherDemo: authorityDecision.allowAnotherDemo,
            type: authorityDecision.type,
            message: authorityDecision.message,
            lockReason: authorityDecision.lockReason,
            attemptsUsed: authorityDecision.attemptsUsed,
            evaluatedAt: authorityDecision.evaluatedAt,
          },
        ),
      );

      if (state === 'PERSISTING') {
        state = transition(state, { type: 'PERSISTED' });
      } else {
        state = persistedState;
      }

      return jsonResponse(
        buildSuccessResponse(
          parsed,
          persistResult,
          persistedLLMResult,
          correlationId,
          rateSnapshot,
          state,
          fallbackUsed,
          failureReason ?? authorityDecision.type,
          authorityDecision,
        ),
        200,
      );
    } catch (error) {
      if (error instanceof z.ZodError) {
        return jsonResponse({
          correlation_id: correlationId,
          state,
          error: 'invalid_body',
          details: error.issues,
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

function buildSuccessResponse(
  request: EvaluateSessionRequest,
  persistResult: PersistResult,
  llmResult: LLMResult,
  correlationId: string,
  rateLimit: RateLimitSnapshot,
  state: EvaluateSessionState,
  fallbackUsed: boolean,
  reason: string | undefined,
  authorityDecision: DemoQuotaEvaluationDecision,
): EvaluateSessionResponse {
  return {
    correlation_id: correlationId,
    state,
    session_id: persistResult.session?.id,
    attempt_id: persistResult.demo_attempt?.id,
    payload_version: request.payload_version,
    fallback_used: fallbackUsed,
    message: authorityDecision.message,
    reason,
    decision: buildDecision(state, reason, {
      message: authorityDecision.message,
      lockReason: authorityDecision.lockReason,
    }),
    request: persistResult.demo_attempt?.request_payload ?? buildRequestPayload(request),
    response: llmResult.response,
    moderation: llmResult.moderation,
    rate_limit: rateLimit,
  };
}

function buildDuplicateResponse(
  _request: EvaluateSessionRequest,
  duplicate: DuplicateAttempt,
  correlationId: string,
  snapshot: DemoQuotaSnapshot | null,
): EvaluateSessionResponse {
  const persistedDecision = parsePersistedDecision(duplicate.llm_response);
  const lastDecision = persistedDecision ?? persistedDecisionFromSnapshot(snapshot);
  return {
    correlation_id: correlationId,
    state: duplicate.state,
    session_id: duplicate.session_id,
    attempt_id: duplicate.id,
    payload_version: duplicate.payload_version,
    fallback_used: duplicate.fallback_used,
    message: lastDecision?.message,
    reason: 'duplicate_attempt',
    decision: lastDecision
      ? decisionFromPersisted(lastDecision)
      : buildDecision(duplicate.state as EvaluateSessionState, duplicate.reason),
    request: duplicate.request_payload,
    response: duplicate.llm_response,
    moderation: duplicate.moderation_payload,
    rate_limit: duplicate.rate_limit_payload,
  };
}

function buildRateLimitedResponse(
  request: EvaluateSessionRequest,
  rateLimit: RateLimitSnapshot,
  correlationId: string,
): EvaluateSessionResponse {
  return {
    correlation_id: correlationId,
    state: 'RATE_LIMITED',
    payload_version: request.payload_version,
    fallback_used: true,
    message: 'Free demo eligibility is temporarily rate limited. Try again shortly.',
    reason: 'rate_limited',
    decision: buildDecision('RATE_LIMITED', 'rate_limited'),
    rate_limit: { ...rateLimit, allowed: false },
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

function attachPersistedDecision(
  llmResult: LLMResult,
  decision: DemoQuotaEvaluationDecision,
): LLMResult {
  return {
    ...llmResult,
    response: {
      ...llmResult.response,
      decision: {
        type: decision.type,
        allow_another_demo: decision.allowAnotherDemo,
        attempts_used: decision.attemptsUsed,
        evaluated_at: decision.evaluatedAt,
        lock_reason: decision.lockReason,
        message: decision.message,
      },
    },
  };
}

function parsePersistedDecision(response: Record<string, unknown>): PersistedDecisionPayload | null {
  const candidate = response.decision;
  if (!candidate || typeof candidate !== 'object') {
    return null;
  }

  const decision = candidate as Record<string, unknown>;
  const type = decision.type;
  const allowAnotherDemo = decision.allow_another_demo;
  const attemptsUsed = decision.attempts_used;
  const evaluatedAt = decision.evaluated_at;

  if (
    (type !== 'allow' && type !== 'deny' && type !== 'timeout')
    || typeof allowAnotherDemo !== 'boolean'
    || typeof attemptsUsed !== 'number'
    || typeof evaluatedAt !== 'string'
  ) {
    return null;
  }

  return {
    type,
    allow_another_demo: allowAnotherDemo,
    attempts_used: attemptsUsed,
    evaluated_at: evaluatedAt,
    lock_reason: isDemoQuotaLockReason(decision.lock_reason) ? decision.lock_reason : undefined,
    message: typeof decision.message === 'string' ? decision.message : undefined,
  };
}

function persistedDecisionFromSnapshot(snapshot: DemoQuotaSnapshot | null): PersistedDecisionPayload | null {
  if (!snapshot?.last_decision) {
    return null;
  }

  return {
    type: snapshot.last_decision.type,
    allow_another_demo: snapshot.last_decision.type === 'allow',
    attempts_used: snapshot.attempts_used,
    evaluated_at: snapshot.last_decision.ts,
    lock_reason: snapshot.server_lock_reason ?? undefined,
    message: snapshot.last_decision.message ?? undefined,
  };
}

function decisionFromPersisted(decision: PersistedDecisionPayload) {
  switch (decision.type) {
    case 'allow':
      return buildDecision('COMPLETED');
    case 'timeout':
      return buildDecision('FALLBACK_TIMEOUT', 'llm_timeout', {
        message: decision.message,
        lockReason: decision.lock_reason,
      });
    case 'deny':
      return buildDecision('REJECTED', decision.lock_reason ?? 'deny', {
        message: decision.message,
        lockReason: decision.lock_reason,
      });
  }
}

function isDemoQuotaLockReason(value: unknown): value is DemoQuotaLockReason {
  return value === 'quota'
    || value === 'evaluation_denied'
    || value === 'evaluation_timeout'
    || value === 'server_sync';
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

function coerceDenyLockReason(
  lockReason: DemoQuotaLockReason | null,
): 'quota' | 'evaluation_denied' | 'evaluation_timeout' | 'server_sync' {
  return lockReason ?? 'evaluation_denied';
}
