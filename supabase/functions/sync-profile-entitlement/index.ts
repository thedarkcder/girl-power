import { createClient } from '@supabase/supabase-js';
import { getRuntimeConfig } from '../evaluate-session/config.ts';
import { createLogger } from '../evaluate-session/logger.ts';
import { HttpError } from '../demo-quota/http.ts';
import { createSyncProfileEntitlementHandler, type ProfileRow } from './handler.ts';
import { createEntitlementVerifier } from './verifier.ts';

const config = getRuntimeConfig();
const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'sync-profile-entitlement/1.0.0' } },
});
const logger = createLogger('sync-profile-entitlement');
const entitlementVerifier = createEntitlementVerifier();

Deno.serve(createSyncProfileEntitlementHandler({
  authenticate: authenticatedUser,
  verifyActiveEntitlement: (transactionJws) => entitlementVerifier.verifyActiveEntitlement(transactionJws),
  syncProfile: (userId, email) => upsertProProfile(userId, email, 'apple'),
  onUnexpectedError: (correlationId, error) => {
    logger.error('Unhandled sync-profile-entitlement error', { correlationId, error: `${error}` });
  },
}));

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
