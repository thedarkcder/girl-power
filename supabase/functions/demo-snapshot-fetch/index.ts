import { createClient } from '@supabase/supabase-js';
import { getRuntimeConfig } from '../evaluate-session/config.ts';
import { createLogger } from '../evaluate-session/logger.ts';
import { HttpError, jsonResponse } from '../demo-quota/http.ts';
import { DemoQuotaRepository } from '../demo-quota/repository.ts';

const config = getRuntimeConfig();
const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'demo-snapshot-fetch/1.0.0' } },
});
const repository = new DemoQuotaRepository(supabase);
const logger = createLogger('demo-snapshot-fetch');

Deno.serve(async (req) => {
  const correlationId = crypto.randomUUID();

  try {
    if (req.method !== 'POST') {
      throw new HttpError(405, 'Only POST supported');
    }

    const body = await req.json().catch(() => {
      throw new HttpError(400, 'Invalid JSON body');
    });
    const deviceId = typeof body?.device_id === 'string' ? body.device_id : '';
    if (!deviceId) {
      throw new HttpError(400, 'device_id is required');
    }

    const snapshot = await repository.fetchSnapshot(deviceId);
    if (!snapshot) {
      return new Response(null, {
        status: 204,
        headers: { 'cache-control': 'no-store' },
      });
    }

    return jsonResponse(snapshot, 200);
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
    }
    logger.error('Unhandled demo-snapshot-fetch error', { correlationId, error: `${error}` });
    return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
  }
});
