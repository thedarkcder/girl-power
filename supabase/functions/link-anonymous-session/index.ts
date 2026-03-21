import { createClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { responseForLinkStatus } from './linker.ts';

const RequestSchema = z.object({
  device_id: z.string().uuid('device_id must be a UUID'),
  anon_session_id: z.string().uuid('anon_session_id must be a UUID'),
});

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const supabaseUrl = requiredEnv('SUPABASE_URL');
const serviceRoleKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');
const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'link-anonymous-session/1.0.0' } },
});

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      throw new HttpError(405, 'Only POST supported');
    }

    const accessToken = bearerToken(req);
    if (!accessToken) {
      throw new HttpError(401, 'Authenticated Supabase session required');
    }

    const parsed = RequestSchema.parse(await parseBody(req));
    const authUser = await authenticatedUser(accessToken);
    const { data, error } = await supabase.rpc('link_anonymous_session', {
      p_device_id: parsed.device_id,
      p_anon_session_id: parsed.anon_session_id,
      p_auth_user_id: authUser.id,
    });

    if (error) {
      throw new HttpError(500, 'Failed to link anonymous session');
    }

    const response = responseForLinkStatus(String(data ?? ''));
    return jsonResponse({ status: response.status }, response.httpStatus);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return jsonResponse({ error: 'invalid_body', details: error.issues }, 400);
    }
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    return jsonResponse({ error: 'internal_error' }, 500);
  }
});

function bearerToken(req: Request): string | null {
  const header = req.headers.get('Authorization')?.trim() ?? '';
  if (!header.startsWith('Bearer ')) {
    return null;
  }
  const token = header.slice('Bearer '.length).trim();
  return token.length === 0 ? null : token;
}

async function authenticatedUser(accessToken: string) {
  const { data, error } = await supabase.auth.getUser(accessToken);
  if (error || !data.user) {
    throw new HttpError(401, 'Authenticated Supabase session required');
  }
  return data.user;
}

async function parseBody(req: Request): Promise<unknown> {
  try {
    return await req.json();
  } catch {
    throw new HttpError(400, 'Invalid JSON body');
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'cache-control': 'no-store',
      'content-type': 'application/json',
    },
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}
