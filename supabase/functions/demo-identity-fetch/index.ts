import { createClient } from '@supabase/supabase-js';
import { getRuntimeConfig } from '../evaluate-session/config.ts';
import { createLogger } from '../evaluate-session/logger.ts';
import { HttpError, jsonResponse } from '../demo-quota/http.ts';
import { DemoQuotaRepository } from '../demo-quota/repository.ts';

const config = getRuntimeConfig();
const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'demo-identity-fetch/1.0.0' } },
});
const repository = new DemoQuotaRepository(supabase);
const logger = createLogger('demo-identity-fetch');

Deno.serve(async (req) => {
  const correlationId = crypto.randomUUID();

  try {
    if (req.method !== 'GET') {
      throw new HttpError(405, 'Only GET supported');
    }

    const url = new URL(req.url);
    const lookupKey = url.searchParams.get('lookup_key');
    if (!lookupKey) {
      throw new HttpError(400, 'lookup_key is required');
    }

    const deviceId = await repository.fetchDeviceIdentity(lookupKey);
    if (!deviceId) {
      return new Response(null, {
        status: 204,
        headers: { 'cache-control': 'no-store' },
      });
    }

    return jsonResponse({ device_id: deviceId }, 200);
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
    }
    logger.error('Unhandled demo-identity-fetch error', { correlationId, error: `${error}` });
    return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
  }
});
