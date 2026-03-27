import { assertEquals } from 'std/assert';
import { createSyncProfileEntitlementHandler, type ProfileRow } from './handler.ts';
import { HttpError } from '../demo-quota/http.ts';

Deno.test('sync-profile-entitlement rejects unauthenticated callers before any write', async () => {
  const handler = createSyncProfileEntitlementHandler({
    authenticate: async () => {
      throw new Error('should not authenticate');
    },
    verifyActiveEntitlement: async () => {
      throw new Error('should not verify');
    },
    syncProfile: async () => {
      throw new Error('should not write');
    },
  });

  const response = await handler(
    new Request('https://example.test/functions/v1/sync-profile-entitlement', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ transaction_jws: 'unused' }),
    }),
  );

  assertEquals(response.status, 401);
  assertEquals((await response.json()).error, 'Authenticated Supabase session required');
});

Deno.test('sync-profile-entitlement rejects unverifiable entitlements', async () => {
  let writes = 0;
  const handler = createSyncProfileEntitlementHandler({
    authenticate: async () => ({ id: 'user-1', email: 'member@example.com' }),
    verifyActiveEntitlement: async () => {
      throw new HttpError(403, 'Verified App Store entitlement required');
    },
    syncProfile: async () => {
      writes += 1;
      throw new Error('should not be called');
    },
  });

  const response = await handler(
    new Request('https://example.test/functions/v1/sync-profile-entitlement', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer token',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ transaction_jws: 'bad-jws' }),
    }),
  );

  assertEquals(response.status, 403);
  assertEquals((await response.json()).error, 'Verified App Store entitlement required');
  assertEquals(writes, 0);
});

Deno.test('sync-profile-entitlement persists pro profile only after verified entitlement', async () => {
  let writes = 0;
  const expectedProfile: ProfileRow = {
    id: 'user-1',
    email: 'member@example.com',
    created_at: '2026-03-23T12:00:00Z',
    updated_at: '2026-03-23T12:00:00Z',
    is_pro: true,
    pro_platform: 'apple',
    onboarding_completed: false,
    last_login_at: '2026-03-23T12:00:00Z',
  };
  const handler = createSyncProfileEntitlementHandler({
    authenticate: async (token) => {
      assertEquals(token, 'token');
      return { id: 'user-1', email: 'member@example.com' };
    },
    verifyActiveEntitlement: async (transactionJws) => {
      assertEquals(transactionJws, 'signed-jws');
    },
    syncProfile: async (userId, email) => {
      writes += 1;
      assertEquals(userId, 'user-1');
      assertEquals(email, 'member@example.com');
      return expectedProfile;
    },
  });

  const response = await handler(
    new Request('https://example.test/functions/v1/sync-profile-entitlement', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer token',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ transaction_jws: 'signed-jws' }),
    }),
  );

  assertEquals(response.status, 200);
  assertEquals((await response.json()).profile, expectedProfile);
  assertEquals(writes, 1);
});
