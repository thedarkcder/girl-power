import { assertEquals } from 'std/assert';
import { transition } from './state-machine.ts';

Deno.test('state machine transitions through success path', () => {
  let state = transition('RECEIVED', { type: 'VALIDATION_SUCCEEDED' });
  assertEquals(state, 'VALIDATING');
  state = transition(state, { type: 'LLM_DELEGATED' });
  assertEquals(state, 'DELEGATING_LLM');
  state = transition(state, { type: 'LLM_SUCCEEDED' });
  assertEquals(state, 'PERSISTING');
  state = transition(state, { type: 'PERSISTED' });
  assertEquals(state, 'COMPLETED');
});

Deno.test('state machine moves into fallback timeout on LLM failure', () => {
  const state = transition('DELEGATING_LLM', { type: 'LLM_FAILED', reason: 'timeout' });
  assertEquals(state, 'FALLBACK_TIMEOUT');
});

Deno.test('rate limiting keeps state sticky', () => {
  const state = transition('VALIDATING', { type: 'RATE_LIMITED' });
  assertEquals(state, 'RATE_LIMITED');
  const next = transition(state, { type: 'LLM_DELEGATED' });
  assertEquals(next, 'RATE_LIMITED');
});
