import { createClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { getRuntimeConfig } from '../evaluate-session/config.ts';
import { createLogger } from '../evaluate-session/logger.ts';
import { HttpError, jsonResponse, parseJson } from '../demo-quota/http.ts';
import { DemoQuotaRepository } from '../demo-quota/repository.ts';
import type { DemoQuotaSnapshot } from '../demo-quota/types.ts';

const config = getRuntimeConfig();
const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'demo-snapshot-mirror/1.0.0' } },
});
const repository = new DemoQuotaRepository(supabase);
const logger = createLogger('demo-snapshot-mirror');

const RequestSchema = z.object({
  device_id: z.string().min(1),
  snapshot: z.object({
    attempts_used: z.number().int().min(0).max(2),
    active_attempt_index: z.number().int().min(1).max(2).nullable(),
    last_decision: z.object({
      type: z.enum(['allow', 'deny', 'timeout']),
      message: z.string().optional(),
      ts: z.string().min(1),
    }).nullable(),
    server_lock_reason: z.enum(['quota', 'evaluation_denied', 'evaluation_timeout', 'server_sync']).nullable(),
    last_sync_at: z.string().nullable(),
  }),
});

Deno.serve(async (req) => {
  const correlationId = crypto.randomUUID();

  try {
    if (req.method !== 'POST') {
      throw new HttpError(405, 'Only POST supported');
    }

    const body = RequestSchema.parse(await parseJson<{ device_id: string; snapshot: DemoQuotaSnapshot }>(req));
    const snapshot = await repository.mirrorSnapshot(body.device_id, body.snapshot);
    return jsonResponse(snapshot, 200);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return jsonResponse({ correlation_id: correlationId, error: 'invalid_body', details: error.issues }, 400);
    }
    if (error instanceof HttpError) {
      return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
    }
    logger.error('Unhandled demo-snapshot-mirror error', { correlationId, error: `${error}` });
    return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
  }
});
