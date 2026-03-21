import { assertEquals } from 'std/assert';
import {
  buildRequestPayload,
  parseEvaluateSessionRequest,
} from './contract.ts';

Deno.test('parseEvaluateSessionRequest preserves canonical requests', () => {
  const request = parseEvaluateSessionRequest({
    device_id: 'device-1',
    attempt_index: 1,
    payload_version: 'v2',
    input: {
      prompt: 'Evaluate this session',
      context: { goal: 'tempo' },
    },
    metadata: { anon_session_id: 'anon-1' },
  });

  assertEquals(request, {
    device_id: 'device-1',
    attempt_index: 1,
    payload_version: 'v2',
    input: {
      prompt: 'Evaluate this session',
      context: { goal: 'tempo' },
    },
    metadata: { anon_session_id: 'anon-1' },
  });
});

Deno.test('buildRequestPayload always persists metadata under the canonical metadata key', () => {
  const payload = buildRequestPayload({
    device_id: 'device-4',
    attempt_index: 1,
    payload_version: 'v1',
    input: {
      prompt: 'Evaluate this session',
      context: { goal: 'tempo' },
    },
    metadata: {
      anon_session_id: 'anon-4',
    },
  });

  assertEquals(payload, {
    input: {
      prompt: 'Evaluate this session',
      context: { goal: 'tempo' },
    },
    metadata: {
      anon_session_id: 'anon-4',
    },
    attempt_index: 1,
  });
});
