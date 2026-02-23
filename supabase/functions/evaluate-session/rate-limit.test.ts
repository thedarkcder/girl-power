import { assertEquals, assertRejects } from 'std/assert';
import { RateLimiter } from './rate-limit.ts';

class FakeClient {
  constructor(private readonly payload: unknown, private readonly shouldError = false) {}

  rpc() {
    if (this.shouldError) {
      return Promise.resolve({ data: null, error: { message: 'boom' } });
    }
    return Promise.resolve({ data: this.payload, error: null });
  }
}

Deno.test('rate limiter returns snapshot when allowed', async () => {
  const limiter = new RateLimiter(new FakeClient({ allowed: true, attempt_count: 1, window_start: '2024-01-01T00:00:00Z' }) as any, {
    rateLimitAttempts: 3,
    rateLimitWindowSeconds: 60,
  });
  const snapshot = await limiter.evaluate('device');
  assertEquals(snapshot.allowed, true);
  assertEquals(snapshot.attempt_count, 1);
  assertEquals(snapshot.limit, 3);
});

Deno.test('rate limiter throws when rpc errors', async () => {
  const limiter = new RateLimiter(new FakeClient({}, true) as any, {
    rateLimitAttempts: 3,
    rateLimitWindowSeconds: 60,
  });
  await assertRejects(() => limiter.evaluate('device'));
});
