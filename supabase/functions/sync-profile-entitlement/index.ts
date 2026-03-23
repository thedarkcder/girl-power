import { createClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { getRuntimeConfig } from '../evaluate-session/config.ts';
import { createLogger } from '../evaluate-session/logger.ts';
import { HttpError, jsonResponse, parseJson } from '../demo-quota/http.ts';

const RequestSchema = z.object({
  pro_platform: z.enum(['apple', 'external']),
});

type ProfileRow = {
  id: string;
  email: string | null;
  created_at: string;
  updated_at: string;
  is_pro: boolean;
  pro_platform: 'apple' | 'external' | null;
  onboarding_completed: boolean;
  last_login_at: string | null;
};

const config = getRuntimeConfig();
const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'sync-profile-entitlement/1.0.0' } },
});
const logger = createLogger('sync-profile-entitlement');

Deno.serve(async (req) => {
  const correlationId = crypto.randomUUID();

  try {
    if (req.method !== 'POST') {
      throw new HttpError(405, 'Only POST supported');
    }

    const accessToken = bearerToken(req);
    if (!accessToken) {
      throw new HttpError(401, 'Authenticated Supabase session required');
    }

    const payload = RequestSchema.parse(await parseJson(req));
    const authUser = await authenticatedUser(accessToken);
    const profile = await upsertProProfile(authUser.id, authUser.email, payload.pro_platform);
    return jsonResponse({ profile }, 200);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return jsonResponse({ correlation_id: correlationId, error: 'invalid_body', details: error.issues }, 400);
    }
    if (error instanceof HttpError) {
      return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
    }
    logger.error('Unhandled sync-profile-entitlement error', { correlationId, error: `${error}` });
    return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
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

async function upsertProProfile(
  userId: string,
  email: string | null | undefined,
  proPlatform: 'apple' | 'external',
): Promise<ProfileRow> {
  const now = new Date().toISOString();
  const { data: existing, error: existingError } = await supabase
    .from('profiles')
    .select('id')
    .eq('id', userId)
    .maybeSingle<{ id: string }>();

  if (existingError && existingError.code !== 'PGRST116') {
    throw new HttpError(500, 'Failed to read profile');
  }

  if (existing) {
    const { data, error } = await supabase
      .from('profiles')
      .update({
        email: email ?? undefined,
        is_pro: true,
        pro_platform: proPlatform,
        last_login_at: now,
      })
      .eq('id', userId)
      .select('id, email, created_at, updated_at, is_pro, pro_platform, onboarding_completed, last_login_at')
      .single<ProfileRow>();

    if (error || !data) {
      throw new HttpError(500, 'Failed to persist profile entitlement');
    }
    return data;
  }

  const { data, error } = await supabase
    .from('profiles')
    .insert({
      id: userId,
      email: email ?? null,
      is_pro: true,
      pro_platform: proPlatform,
      last_login_at: now,
    })
    .select('id, email, created_at, updated_at, is_pro, pro_platform, onboarding_completed, last_login_at')
    .single<ProfileRow>();

  if (error || !data) {
    throw new HttpError(500, 'Failed to create profile entitlement');
  }

  return data;
}
