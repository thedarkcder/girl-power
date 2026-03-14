import { createClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { getRuntimeConfig } from '../evaluate-session/config.ts';
import { createLogger } from '../evaluate-session/logger.ts';
import { HttpError, jsonResponse, parseJson } from '../demo-quota/http.ts';
import { DemoQuotaRepository } from '../demo-quota/repository.ts';
import type { DemoQuotaLogRequest } from '../demo-quota/types.ts';

const logger = createLogger('demo-session-log');

const RequestSchema = z.object({
  device_id: z.string().min(1),
  attempt_index: z.number().int().min(1).max(2),
  stage: z.enum(['start', 'completion']),
  metadata: z.record(z.string(), z.unknown()).optional(),
});

export function buildDemoSessionLogHandler(
  deps: { repository: Pick<DemoQuotaRepository, 'logAttempt'> },
) {
  return async (req: Request) => {
    const correlationId = crypto.randomUUID();

    try {
      if (req.method !== 'POST') {
        throw new HttpError(405, 'Only POST supported');
      }

      const request = RequestSchema.parse(await parseJson<DemoQuotaLogRequest>(req));
      const result = await deps.repository.logAttempt(request);
      return jsonResponse({
        correlation_id: correlationId,
        attempt: result.attempt,
        snapshot: result.snapshot,
      }, 200);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return jsonResponse({ correlation_id: correlationId, error: 'invalid_body', details: error.issues }, 400);
      }
      if (error instanceof HttpError) {
        return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
      }
      logger.error('Unhandled demo-session-log error', { correlationId, error: `${error}` });
      return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
    }
  };
}

if (import.meta.main) {
  const config = getRuntimeConfig();
  const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
    auth: { persistSession: false },
    global: { headers: { 'X-Client-Info': 'demo-session-log/1.0.0' } },
  });
  const repository = new DemoQuotaRepository(supabase);
  Deno.serve(buildDemoSessionLogHandler({ repository }));
}
