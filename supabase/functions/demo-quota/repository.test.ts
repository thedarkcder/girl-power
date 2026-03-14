import { assertEquals } from 'std/assert';
import { buildAttemptPayload } from './repository.ts';
import type { DemoQuotaAttemptLog, DemoQuotaLogRequest } from './types.ts';

Deno.test('buildAttemptPayload preserves original completion fields for idempotent retries', () => {
  const existingAttempt: DemoQuotaAttemptLog = {
    id: 'attempt-1',
    device_id: 'device-1',
    attempt_index: 2,
    start_metadata: { source: 'original-start' },
    completion_metadata: { source: 'original-completion' },
    started_at: '2026-03-14T00:00:00.000Z',
    completed_at: '2026-03-14T00:00:10.000Z',
    created_at: '2026-03-14T00:00:00.000Z',
    updated_at: '2026-03-14T00:00:10.000Z',
  };
  const request: DemoQuotaLogRequest = {
    device_id: 'device-1',
    attempt_index: 2,
    stage: 'completion',
    metadata: { source: 'retry-completion' },
  };

  const payload = buildAttemptPayload(existingAttempt, request, '2026-03-14T00:00:20.000Z');

  assertEquals(payload.completion_metadata, { source: 'original-completion' });
  assertEquals(payload.completed_at, '2026-03-14T00:00:10.000Z');
  assertEquals(payload.start_metadata, { source: 'original-start' });
});
