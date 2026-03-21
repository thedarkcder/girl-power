import { z } from 'zod';
import type { EvaluateSessionRequest } from './types.ts';

export const EvaluateSessionRequestSchema = z.object({
  device_id: z.string().min(1, 'device_id is required'),
  attempt_index: z.number().int().nonnegative(),
  payload_version: z.string().min(1).default('v1'),
  input: z.object({
    prompt: z.string().min(1, 'prompt is required'),
    context: z.record(z.string(), z.any()).optional(),
  }),
  metadata: z.record(z.string(), z.any()).optional(),
});

export function parseEvaluateSessionRequest(request: unknown): EvaluateSessionRequest {
  return EvaluateSessionRequestSchema.parse(request);
}

export function buildRequestPayload(request: EvaluateSessionRequest): Record<string, unknown> {
  return {
    input: request.input,
    metadata: request.metadata ?? {},
    attempt_index: request.attempt_index,
  };
}
