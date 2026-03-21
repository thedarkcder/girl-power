import { assertEquals } from 'std/assert';
import { buildDecision } from './decision.ts';

Deno.test('buildDecision maps completed responses to allow', () => {
  assertEquals(buildDecision('COMPLETED'), {
    outcome: 'allow',
  });
});

Deno.test('buildDecision maps fallback timeout responses to timeout', () => {
  assertEquals(buildDecision('FALLBACK_TIMEOUT', 'llm_timeout'), {
    outcome: 'timeout',
    message: 'Eligibility check timed out. Please retry.',
  });
});

Deno.test('buildDecision maps rate limited responses to deny with a user-facing message', () => {
  assertEquals(buildDecision('RATE_LIMITED', 'rate_limited'), {
    outcome: 'deny',
    message: 'Free demo eligibility is temporarily rate limited. Try again shortly.',
  });
});
