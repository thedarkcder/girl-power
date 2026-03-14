import { assertEquals } from 'std/assert';
import { buildEvaluateSessionHandler } from './handler.ts';
import type { DemoQuotaAttemptLog, DemoQuotaSnapshot } from '../demo-quota/types.ts';

type DependencyOverrides = {
  duplicateAttempt?: {
    id: string;
    session_id: string;
    state: string;
    payload_version: string;
    fallback_used: boolean;
    request_payload: Record<string, unknown>;
    llm_response: Record<string, unknown>;
    moderation_payload: Record<string, unknown>;
    reason: string | null;
  } | null;
  snapshot?: DemoQuotaSnapshot | null;
  attemptLog?: DemoQuotaAttemptLog | null;
  llmResult?: {
    model: string;
    response: { summary: string; guidance: string[]; tokens_used: number };
    moderation: { flagged: boolean; categories: string[] };
  } | null;
  llmError?: Error | null;
  persistedSnapshot?: DemoQuotaSnapshot | null;
};

Deno.test('evaluate-session returns allowAnotherDemo when attempt #1 completed and quota is open', async () => {
  const handler = buildEvaluateSessionHandler(makeDependencies({
    attemptLog: completedAttemptLog(),
    llmResult: {
      model: 'stub',
      response: { summary: 'approved', guidance: ['continue'], tokens_used: 4 },
      moderation: { flagged: false, categories: [] },
    },
    persistedSnapshot: {
      attempts_used: 1,
      active_attempt_index: null,
      last_decision: { type: 'allow', ts: '2026-03-14T00:00:00.000Z' },
      server_lock_reason: null,
      last_sync_at: '2026-03-14T00:00:00.000Z',
    },
  }));

  const response = await handler(makeRequest());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.allow_another_demo, true);
  assertEquals(body.attempts_used, 1);
  assertEquals(body.snapshot.last_decision.type, 'allow');
});

Deno.test('evaluate-session returns 409 duplicate response when the attempt was already evaluated', async () => {
  const handler = buildEvaluateSessionHandler(makeDependencies({
    duplicateAttempt: {
      id: 'attempt-1',
      session_id: 'session-1',
      state: 'COMPLETED',
      payload_version: 'v1',
      fallback_used: false,
      request_payload: { attempt_index: 1 },
      llm_response: {
        summary: 'approved',
        decision: {
          type: 'allow',
          allow_another_demo: true,
          attempts_used: 1,
          evaluated_at: '2026-03-14T00:00:00.000Z',
        },
      },
      moderation_payload: { flagged: false },
      reason: null,
    },
    snapshot: {
      attempts_used: 1,
      active_attempt_index: null,
      last_decision: { type: 'allow', ts: '2026-03-14T00:00:00.000Z' },
      server_lock_reason: null,
      last_sync_at: '2026-03-14T00:00:00.000Z',
    },
  }));

  const response = await handler(makeRequest());
  const body = await response.json();

  assertEquals(response.status, 409);
  assertEquals(body.allow_another_demo, true);
  assertEquals(body.reason, 'duplicate_attempt');
});

Deno.test('evaluate-session duplicate response prefers the persisted decision payload when snapshot persistence drifted', async () => {
  const handler = buildEvaluateSessionHandler(makeDependencies({
    duplicateAttempt: {
      id: 'attempt-1',
      session_id: 'session-1',
      state: 'FALLBACK_TIMEOUT',
      payload_version: 'v1',
      fallback_used: true,
      request_payload: { attempt_index: 1 },
      llm_response: {
        summary: 'timed out',
        decision: {
          type: 'timeout',
          allow_another_demo: false,
          attempts_used: 1,
          evaluated_at: '2026-03-14T01:02:03.000Z',
          lock_reason: 'evaluation_timeout',
        },
      },
      moderation_payload: { flagged: false },
      reason: 'llm_timeout',
    },
    snapshot: {
      attempts_used: 1,
      active_attempt_index: null,
      last_decision: { type: 'allow', ts: '2026-03-14T00:00:00.000Z' },
      server_lock_reason: null,
      last_sync_at: '2026-03-14T00:00:00.000Z',
    },
  }));

  const response = await handler(makeRequest());
  const body = await response.json();

  assertEquals(response.status, 409);
  assertEquals(body.allow_another_demo, false);
  assertEquals(body.lock_reason, 'evaluation_timeout');
  assertEquals(body.evaluated_at, '2026-03-14T01:02:03.000Z');
  assertEquals(body.snapshot.last_decision.type, 'timeout');
});

Deno.test('evaluate-session duplicate response reconstructs snapshot from the persisted decision when snapshot write never landed', async () => {
  const handler = buildEvaluateSessionHandler(makeDependencies({
    duplicateAttempt: {
      id: 'attempt-1',
      session_id: 'session-1',
      state: 'REJECTED',
      payload_version: 'v1',
      fallback_used: false,
      request_payload: { attempt_index: 1 },
      llm_response: {
        summary: 'quota exhausted',
        decision: {
          type: 'deny',
          allow_another_demo: false,
          attempts_used: 2,
          evaluated_at: '2026-03-14T02:00:00.000Z',
          lock_reason: 'quota',
          message: 'This device has already used its free demos.',
        },
      },
      moderation_payload: { flagged: false },
      reason: 'quota_rule',
    },
    snapshot: null,
  }));

  const response = await handler(makeRequest());
  const body = await response.json();

  assertEquals(response.status, 409);
  assertEquals(body.allow_another_demo, false);
  assertEquals(body.attempts_used, 2);
  assertEquals(body.lock_reason, 'quota');
  assertEquals(body.message, 'This device has already used its free demos.');
  assertEquals(body.snapshot.server_lock_reason, 'quota');
  assertEquals(body.snapshot.last_decision.type, 'deny');
});

Deno.test('evaluate-session fails closed when the LLM decision path times out', async () => {
  const timeoutError = new DOMException('Aborted', 'AbortError');
  const handler = buildEvaluateSessionHandler(makeDependencies({
    attemptLog: completedAttemptLog(),
    llmError: timeoutError,
    persistedSnapshot: {
      attempts_used: 1,
      active_attempt_index: null,
      last_decision: { type: 'timeout', ts: '2026-03-14T00:00:00.000Z' },
      server_lock_reason: 'evaluation_timeout',
      last_sync_at: '2026-03-14T00:00:00.000Z',
    },
  }));

  const response = await handler(makeRequest());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.allow_another_demo, false);
  assertEquals(body.lock_reason, 'evaluation_timeout');
  assertEquals(body.fallback_used, true);
});

Deno.test('evaluate-session rejects invalid request bodies', async () => {
  const handler = buildEvaluateSessionHandler(makeDependencies({}));
  const response = await handler(new Request('http://local.test/functions/v1/evaluate-session', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ device_id: 'device-1' }),
  }));

  assertEquals(response.status, 400);
});

function makeDependencies(overrides: DependencyOverrides) {
  const deps = { ...baseDependencies(), ...overrides };
  return {
    config: { llmTimeoutMs: 1000 },
    rateLimiter: {
      evaluate: () => Promise.resolve({ allowed: true, attempt_count: 1, window_start: '2026-03-14T00:00:00.000Z', limit: 3, window_seconds: 60 }),
    },
    sessionRepository: {
      findAttempt: () => Promise.resolve(deps.duplicateAttempt ?? null),
      persist: () => Promise.resolve({
        session: { id: 'session-1' },
        demo_attempt: {
          id: 'attempt-1',
          request_payload: { attempt_index: 1 },
          llm_response: deps.llmResult?.response ?? { summary: 'denied' },
          moderation_payload: deps.llmResult?.moderation ?? { flagged: false },
        },
      }),
    },
    quotaRepository: {
      fetchSnapshot: () => Promise.resolve(deps.snapshot ?? null),
      fetchAttemptLog: () => Promise.resolve(deps.attemptLog ?? null),
      snapshotFromDecision: () => deps.persistedSnapshot ?? defaultSnapshot(),
      persistDecisionSnapshot: () => Promise.resolve(deps.persistedSnapshot ?? defaultSnapshot()),
    },
    llmProvider: {
      generate: () => {
        if (deps.llmError) {
          throw deps.llmError;
        }
        return Promise.resolve(deps.llmResult ?? {
          model: 'stub',
          response: { summary: 'approved', guidance: ['continue'], tokens_used: 4 },
          moderation: { flagged: false, categories: [] },
        });
      },
    },
    logger: { error: () => {} },
  };
}

function baseDependencies() {
  return {
    duplicateAttempt: null as DependencyOverrides['duplicateAttempt'],
    snapshot: null as DemoQuotaSnapshot | null,
    attemptLog: null as DemoQuotaAttemptLog | null,
    llmResult: null as DependencyOverrides['llmResult'],
    llmError: null as Error | null,
    persistedSnapshot: null as DemoQuotaSnapshot | null,
  };
}

function makeRequest() {
  return new Request('http://local.test/functions/v1/evaluate-session', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      device_id: 'device-1',
      attempt_index: 1,
      payload_version: 'v1',
      input: {
        prompt: 'Evaluate eligibility for attempt #2',
        context: { reps: 8 },
      },
      metadata: { reps: 8 },
    }),
  });
}

function completedAttemptLog(): DemoQuotaAttemptLog {
  return {
    id: 'log-1',
    device_id: 'device-1',
    attempt_index: 1,
    start_metadata: {},
    completion_metadata: { reps: 8 },
    started_at: '2026-03-14T00:00:00.000Z',
    completed_at: '2026-03-14T00:00:10.000Z',
    created_at: '2026-03-14T00:00:00.000Z',
    updated_at: '2026-03-14T00:00:10.000Z',
  };
}

function defaultSnapshot(): DemoQuotaSnapshot {
  return {
    attempts_used: 1,
    active_attempt_index: null,
    last_decision: { type: 'allow', ts: '2026-03-14T00:00:00.000Z' },
    server_lock_reason: null,
    last_sync_at: '2026-03-14T00:00:00.000Z',
  };
}
