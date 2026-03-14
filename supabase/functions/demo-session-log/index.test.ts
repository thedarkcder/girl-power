import { assertEquals } from 'std/assert';
import { buildDemoSessionLogHandler } from './index.ts';

Deno.test('demo-session-log rejects attempt indices above 2', async () => {
  const handler = buildDemoSessionLogHandler({
    repository: {
      logAttempt: () => Promise.reject(new Error('should not be called')),
    },
  });

  const response = await handler(new Request('http://local.test/functions/v1/demo-session-log', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      device_id: 'device-1',
      attempt_index: 3,
      stage: 'completion',
    }),
  }));
  const body = await response.json();

  assertEquals(response.status, 400);
  assertEquals(body.error, 'invalid_body');
});
