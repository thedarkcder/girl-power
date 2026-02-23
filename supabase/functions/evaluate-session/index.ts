import { createClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { getRuntimeConfig } from './config.ts';
import { createLogger } from './logger.ts';
import { RateLimiter } from './rate-limit.ts';
import { SessionRepository } from './repository.ts';
import { LLMProvider } from './llm-provider.ts';
import { transition, type EvaluateSessionState } from './state-machine.ts';
import type { EvaluateSessionRequest, EvaluateSessionResponse, LLMResult, RateLimitSnapshot } from './types.ts';

const config = getRuntimeConfig();
const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'evaluate-session/1.0.0' } },
});
const logger = createLogger('evaluate-session');
const rateLimiter = new RateLimiter(supabase, config);
const repository = new SessionRepository(supabase, config);
const llmProvider = new LLMProvider(config.llmModel);

const RequestSchema = z.object({
  device_id: z.string().min(1, 'device_id is required'),
  attempt_index: z.number().int().nonnegative(),
  payload_version: z.string().min(1).default('v1'),
  input: z.object({
    prompt: z.string().min(1, 'prompt is required'),
    context: z.record(z.string(), z.any()).optional(),
  }),
  metadata: z.record(z.string(), z.any()).optional(),
});

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

Deno.serve(async (req) => {
  const correlationId = crypto.randomUUID();
  let state: EvaluateSessionState = 'RECEIVED';

  try {
    if (req.method !== 'POST') {
      throw new HttpError(405, 'Only POST supported');
    }

    const request = await parseRequest(req);
    const parsed = RequestSchema.parse(request) as EvaluateSessionRequest;
    state = transition(state, { type: 'VALIDATION_SUCCEEDED' });

    const duplicate = await repository.findAttempt(parsed.device_id, parsed.attempt_index);
    if (duplicate) {
      return jsonResponse({
        correlation_id: correlationId,
        state: duplicate.state,
        session_id: duplicate.session_id,
        attempt_id: duplicate.id,
        payload_version: duplicate.payload_version,
        fallback_used: duplicate.fallback_used,
        reason: 'duplicate_attempt',
        request: duplicate.request_payload,
        response: duplicate.llm_response,
        moderation: duplicate.moderation_payload,
        rate_limit: await defaultRateLimitSnapshot(parsed.device_id),
      }, 409);
    }

    const rateSnapshot = await rateLimiter.evaluate(parsed.device_id);
    if (!rateSnapshot.allowed) {
      state = transition(state, { type: 'RATE_LIMITED' });
      return jsonResponse(buildRateLimitedResponse(parsed, rateSnapshot, correlationId), 429);
    }

    state = transition(state, { type: 'LLM_DELEGATED' });

    let finalState: EvaluateSessionState = 'COMPLETED';
    let fallbackUsed = false;
    let failureReason: string | undefined;
    let llmResult: LLMResult;

    try {
      llmResult = await llmProvider.generate(parsed.input, {
        signal: AbortSignal.timeout(config.llmTimeoutMs),
      });
      state = transition(state, { type: 'LLM_SUCCEEDED' });
    } catch (error) {
      fallbackUsed = true;
      const timeout = error instanceof DOMException && error.name === 'AbortError';
      failureReason = timeout ? 'llm_timeout' : 'llm_error';
      finalState = transition(state, {
        type: 'LLM_FAILED',
        reason: timeout ? 'timeout' : 'provider_error',
      });
      llmResult = buildFallbackResponse(parsed.input.prompt, failureReason);
    }

    const targetState = fallbackUsed ? finalState : 'COMPLETED';
    const persistResult = await repository.persist(
      parsed,
      llmResult,
      targetState,
      failureReason,
      correlationId,
      fallbackUsed,
    );

    if (persistResult.status === 'rate_limited') {
      state = transition(state, { type: 'RATE_LIMITED' });
      const limitedSnapshot = {
        allowed: false,
        attempt_count: persistResult.attempt_count ?? rateSnapshot.attempt_count,
        window_start: persistResult.window_start ?? rateSnapshot.window_start,
        limit: rateSnapshot.limit,
        window_seconds: rateSnapshot.window_seconds,
      };
      return jsonResponse(buildRateLimitedResponse(parsed, limitedSnapshot, correlationId), 429);
    }

    if (persistResult.status === 'duplicate' && persistResult.demo_attempt) {
      return jsonResponse({
        correlation_id: correlationId,
        state: persistResult.demo_attempt.state,
        session_id: persistResult.demo_attempt.session_id,
        attempt_id: persistResult.demo_attempt.id,
        payload_version: persistResult.demo_attempt.payload_version,
        fallback_used: persistResult.demo_attempt.fallback_used,
        reason: 'duplicate_attempt',
        request: persistResult.demo_attempt.request_payload,
        response: persistResult.demo_attempt.llm_response,
        moderation: persistResult.demo_attempt.moderation_payload,
        rate_limit: rateSnapshot,
      }, 409);
    }

    if (!fallbackUsed) {
      state = transition(state, { type: 'PERSISTED' });
    } else {
      state = targetState;
    }

    const finalRateSnapshot = {
      ...rateSnapshot,
      attempt_count: persistResult.attempt_count ?? rateSnapshot.attempt_count + 1,
      window_start: persistResult.window_start ?? rateSnapshot.window_start,
    };

    return jsonResponse({
      correlation_id: correlationId,
      state,
      session_id: persistResult.session?.id,
      attempt_id: persistResult.demo_attempt?.id,
      payload_version: parsed.payload_version,
      fallback_used: fallbackUsed,
      reason: failureReason,
      request: persistResult.demo_attempt?.request_payload ?? buildRequestPayload(parsed),
      response: llmResult.response,
      moderation: llmResult.moderation,
      rate_limit: finalRateSnapshot,
    }, 200);
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
    logger.error('Unhandled evaluate-session error', { correlationId, error: `${error}` });
    return jsonResponse({
      correlation_id: correlationId,
      state,
      error: 'internal_error',
    }, 500);
  }
});

async function parseRequest(req: Request): Promise<unknown> {
  try {
    return await req.json();
  } catch (error) {
    throw new HttpError(400, 'Invalid JSON body');
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
    },
  });
}

async function defaultRateLimitSnapshot(deviceId: string) {
  return rateLimiter.evaluate(deviceId);
}

function buildRateLimitedResponse(
  request: EvaluateSessionRequest,
  snapshot: RateLimitSnapshot,
  correlationId: string,
): EvaluateSessionResponse {
  return {
    correlation_id: correlationId,
    state: 'RATE_LIMITED',
    payload_version: request.payload_version,
    fallback_used: true,
    reason: 'rate_limited',
    rate_limit: { ...snapshot, allowed: false },
  };
}

function buildFallbackResponse(prompt: string, reason: string | undefined): LLMResult {
  return {
    model: config.llmModel,
    response: {
      summary: `Fallback response for prompt ${prompt.slice(0, 24)}`,
      guidance: ['Retry shortly', 'Check network connectivity'],
      tokens_used: 0,
    },
    moderation: { flagged: false, categories: [] },
    reason,
  };
}

function buildRequestPayload(request: EvaluateSessionRequest) {
  return {
    input: request.input,
    metadata: request.metadata ?? {},
    attempt_index: request.attempt_index,
  };
}
