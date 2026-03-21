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

type DependencyCallCounts = {
  rateLimitEvaluations: number;
  findAttemptCalls: number;
  persistCalls: number;
  fetchSnapshotCalls: number;
  fetchAttemptLogCalls: number;
  persistDecisionSnapshotCalls: number;
  llmGenerateCalls: number;
};

Deno.test('evaluate-session returns canonical allow decision when attempt #1 completed and quota is open', async () => {
  const harness = makeDependencies({
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
  });
  const handler = buildEvaluateSessionHandler(harness.deps);

  const response = await handler(makeRequest());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.decision, { outcome: 'allow' });
  assertEquals(body.fallback_used, false);
});

Deno.test('evaluate-session returns 409 duplicate response with the persisted canonical decision', async () => {
  const harness = makeDependencies({
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
  });
  const handler = buildEvaluateSessionHandler(harness.deps);

  const response = await handler(makeRequest());
  const body = await response.json();

  assertEquals(response.status, 409);
  assertEquals(body.reason, 'duplicate_attempt');
  assertEquals(body.decision, { outcome: 'allow' });
});

Deno.test('evaluate-session fails closed when the LLM decision path times out', async () => {
  const timeoutError = new DOMException('Aborted', 'AbortError');
  const harness = makeDependencies({
    attemptLog: completedAttemptLog(),
    llmError: timeoutError,
    persistedSnapshot: {
      attempts_used: 1,
      active_attempt_index: null,
      last_decision: { type: 'timeout', ts: '2026-03-14T00:00:00.000Z' },
      server_lock_reason: 'evaluation_timeout',
      last_sync_at: '2026-03-14T00:00:00.000Z',
    },
  });
  const handler = buildEvaluateSessionHandler(harness.deps);

  const response = await handler(makeRequest());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.decision, {
    outcome: 'timeout',
    message: 'Eligibility check timed out. Please retry.',
    lock_reason: 'evaluation_timeout',
  });
  assertEquals(body.fallback_used, true);
});

Deno.test('evaluate-session rejects invalid request bodies', async () => {
  const harness = makeDependencies({});
  const handler = buildEvaluateSessionHandler(harness.deps);
  const response = await handler(new Request('http://local.test/functions/v1/evaluate-session', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ device_id: 'device-1' }),
  }));

  assertEquals(response.status, 400);
});

Deno.test('evaluate-session rejects attempt indexes beyond the first attempt at the API boundary', async () => {
  const harness = makeDependencies({});
  const handler = buildEvaluateSessionHandler(harness.deps);
  const response = await handler(makeRequest(2));
  const body = await response.json();

  assertEquals(response.status, 400);
  assertEquals(body.error, 'invalid_body');
  assertEquals(harness.calls.rateLimitEvaluations, 0);
  assertEquals(harness.calls.findAttemptCalls, 0);
  assertEquals(harness.calls.fetchSnapshotCalls, 0);
  assertEquals(harness.calls.fetchAttemptLogCalls, 0);
  assertEquals(harness.calls.persistCalls, 0);
  assertEquals(harness.calls.persistDecisionSnapshotCalls, 0);
  assertEquals(harness.calls.llmGenerateCalls, 0);
});

function makeDependencies(overrides: DependencyOverrides) {
  const deps = { ...baseDependencies(), ...overrides };
  const calls: DependencyCallCounts = {
    rateLimitEvaluations: 0,
    findAttemptCalls: 0,
    persistCalls: 0,
    fetchSnapshotCalls: 0,
    fetchAttemptLogCalls: 0,
    persistDecisionSnapshotCalls: 0,
    llmGenerateCalls: 0,
  };

  return {
    calls,
    deps: {
      config: { llmTimeoutMs: 1000 },
      rateLimiter: {
        evaluate: () => {
          calls.rateLimitEvaluations += 1;
          return Promise.resolve({
            allowed: true,
            attempt_count: 1,
            window_start: '2026-03-14T00:00:00.000Z',
            limit: 3,
            window_seconds: 60,
          });
        },
      },
      sessionRepository: {
        findAttempt: () => {
          calls.findAttemptCalls += 1;
          return Promise.resolve(deps.duplicateAttempt ?? null);
        },
        persist: () => {
          calls.persistCalls += 1;
          return Promise.resolve({
            session: { id: 'session-1' },
            demo_attempt: {
              id: 'attempt-1',
              request_payload: { attempt_index: 1 },
              llm_response: deps.llmResult?.response ?? { summary: 'denied' },
              moderation_payload: deps.llmResult?.moderation ?? { flagged: false },
            },
          });
        },
      },
      quotaRepository: {
        fetchSnapshot: () => {
          calls.fetchSnapshotCalls += 1;
          return Promise.resolve(deps.snapshot ?? null);
        },
        fetchAttemptLog: () => {
          calls.fetchAttemptLogCalls += 1;
          return Promise.resolve(deps.attemptLog ?? null);
        },
        snapshotFromDecision: () => deps.persistedSnapshot ?? defaultSnapshot(),
        persistDecisionSnapshot: () => {
          calls.persistDecisionSnapshotCalls += 1;
          return Promise.resolve(deps.persistedSnapshot ?? defaultSnapshot());
        },
      },
      llmProvider: {
        generate: () => {
          calls.llmGenerateCalls += 1;
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
    },
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

function makeRequest(attemptIndex = 1) {
  return new Request('http://local.test/functions/v1/evaluate-session', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      device_id: 'device-1',
      attempt_index: attemptIndex,
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
    start_metadata: { source: 'test' },
    completion_metadata: { source: 'test' },
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
