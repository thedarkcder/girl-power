import { createClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { getRuntimeConfig } from '../evaluate-session/config.ts';
import { createLogger } from '../evaluate-session/logger.ts';
import { HttpError, jsonResponse, parseJson } from '../demo-quota/http.ts';
import { DemoQuotaRepository } from '../demo-quota/repository.ts';

const config = getRuntimeConfig();
const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'demo-identity-mirror/1.0.0' } },
});
const repository = new DemoQuotaRepository(supabase);
const logger = createLogger('demo-identity-mirror');

const RequestSchema = z.object({
  lookup_key: z.string().min(1),
  device_id: z.string().min(1),
});

Deno.serve(async (req) => {
  const correlationId = crypto.randomUUID();

  try {
    if (req.method !== 'POST') {
      throw new HttpError(405, 'Only POST supported');
    }

    const body = RequestSchema.parse(await parseJson<{ lookup_key: string; device_id: string }>(req));
    await repository.mirrorDeviceIdentity(body.lookup_key, body.device_id);
    return jsonResponse({ correlation_id: correlationId, ok: true }, 200);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return jsonResponse({ correlation_id: correlationId, error: 'invalid_body', details: error.issues }, 400);
    }
    if (error instanceof HttpError) {
      return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
    }
    logger.error('Unhandled demo-identity-mirror error', { correlationId, error: `${error}` });
    return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
  }
});
