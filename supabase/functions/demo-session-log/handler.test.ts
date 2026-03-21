import { assertEquals } from 'std/assert';
import { buildDemoSessionLogHandler } from './handler.ts';

Deno.test('demo-session-log rejects attempt_index values outside the supported quota range', async () => {
  const harness = makeHarness();
  const handler = buildDemoSessionLogHandler(harness.deps);

  const response = await handler(makeRequest(3));
  const body = await response.json();

  assertEquals(response.status, 400);
  assertEquals(body.error, 'invalid_body');
  assertEquals(harness.logAttemptCalls, 0);
});

Deno.test('demo-session-log persists valid attempt logs', async () => {
  const harness = makeHarness();
  const handler = buildDemoSessionLogHandler(harness.deps);

  const response = await handler(makeRequest(2, 'completion'));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(harness.logAttemptCalls, 1);
  assertEquals(body.attempt.attempt_index, 2);
  assertEquals(body.snapshot.attempts_used, 2);
});

function makeHarness() {
  const result = {
    attempt: {
      id: 'attempt-1',
      device_id: 'device-1',
      attempt_index: 2,
      start_metadata: {},
      completion_metadata: {},
      started_at: '2026-03-14T00:00:00.000Z',
      completed_at: '2026-03-14T00:00:10.000Z',
      created_at: '2026-03-14T00:00:00.000Z',
      updated_at: '2026-03-14T00:00:10.000Z',
    },
    snapshot: {
      attempts_used: 2,
      active_attempt_index: null,
      last_decision: null,
      server_lock_reason: 'quota',
      last_sync_at: '2026-03-14T00:00:10.000Z',
    },
  };

  const harness = {
    logAttemptCalls: 0,
    deps: {
      repository: {
        logAttempt: () => {
          harness.logAttemptCalls += 1;
          return Promise.resolve(result);
        },
      },
      logger: { error: () => {} },
    },
  };

  return harness;
}

function makeRequest(attemptIndex: number, stage: 'start' | 'completion' = 'start') {
  return new Request('http://local.test/functions/v1/demo-session-log', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      device_id: 'device-1',
      attempt_index: attemptIndex,
      stage,
      metadata: { source: 'test' },
    }),
  });
}
