import { createClient } from '@supabase/supabase-js';
import { assertEquals, assertExists } from 'std/assert';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const integrationEnabled = supabaseUrl.length > 0 && serviceRoleKey.length > 0;

type LinkResult = {
  status: string;
  attempts_used: number | null;
  active_attempt_index: number | null;
  last_decision: unknown;
  server_lock_reason: string | null;
  last_sync_at: string | null;
  linked_at: string | null;
};

Deno.test({
  name: 'link_authenticated_device merges locked quota across devices and stays idempotent for a second linked device',
  ignore: !integrationEnabled,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const email = `gp124-${crypto.randomUUID()}@example.com`;
    const password = 'Password123!';
    const deviceA = crypto.randomUUID();
    const deviceB = crypto.randomUUID();

    const { data: created, error: createError } = await client.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (createError) throw createError;
    const userId = created.user?.id;
    assertExists(userId);

    try {
      const { error: seedError } = await client.from('demo_quota_snapshots').insert({
        device_id: deviceA,
        attempts_used: 2,
        active_attempt_index: null,
        last_decision: null,
        server_lock_reason: 'quota',
        last_sync_at: new Date().toISOString(),
      });
      if (seedError) throw seedError;

      const firstLink = await client.rpc('link_authenticated_device', {
        p_device_id: deviceA,
        p_auth_user_id: userId,
        p_anon_session_id: null,
      });
      if (firstLink.error) throw firstLink.error;
      const firstPayload = firstLink.data?.[0] as LinkResult | undefined;
      if (!firstPayload) throw new Error('Expected first link payload');
      assertEquals(firstPayload.status, 'linked');
      assertEquals(firstPayload.attempts_used, 2);
      assertEquals(firstPayload.server_lock_reason, 'quota');

      const secondLink = await client.rpc('link_authenticated_device', {
        p_device_id: deviceB,
        p_auth_user_id: userId,
        p_anon_session_id: null,
      });
      if (secondLink.error) throw secondLink.error;
      const secondPayload = secondLink.data?.[0] as LinkResult | undefined;
      if (!secondPayload) throw new Error('Expected second link payload');
      assertEquals(secondPayload.status, 'linked');
      assertEquals(secondPayload.attempts_used, 2);
      assertEquals(secondPayload.server_lock_reason, 'quota');

      const repeatedSecondLink = await client.rpc('link_authenticated_device', {
        p_device_id: deviceB,
        p_auth_user_id: userId,
        p_anon_session_id: null,
      });
      if (repeatedSecondLink.error) throw repeatedSecondLink.error;
      const repeatedPayload = repeatedSecondLink.data?.[0] as LinkResult | undefined;
      if (!repeatedPayload) throw new Error('Expected repeated link payload');
      assertEquals(repeatedPayload.status, 'already_linked');
      assertEquals(repeatedPayload.attempts_used, 2);
      assertEquals(repeatedPayload.server_lock_reason, 'quota');

      const linkedDevices = await client
        .from('device_links')
        .select('device_id')
        .eq('user_id', userId);
      if (linkedDevices.error) throw linkedDevices.error;
      const linkedDeviceIDs = (linkedDevices.data as Array<{ device_id: string }> | null)?.map((row) => row.device_id).sort();
      assertEquals(linkedDeviceIDs, [deviceA, deviceB].sort());

      const mirroredSnapshot = await client
        .from('demo_quota_snapshots')
        .select('attempts_used, server_lock_reason')
        .eq('device_id', deviceB)
        .single<{ attempts_used: number; server_lock_reason: string | null }>();
      if (mirroredSnapshot.error) throw mirroredSnapshot.error;
      assertEquals(mirroredSnapshot.data.attempts_used, 2);
      assertEquals(mirroredSnapshot.data.server_lock_reason, 'quota');
    } finally {
      await client.from('demo_quota_snapshots').delete().in('device_id', [deviceA, deviceB]);
      await client.from('device_links').delete().eq('user_id', userId);
      await client.auth.admin.deleteUser(userId);
    }
  },
});

Deno.test({
  name: 'link_authenticated_device rejects cross-account relink attempts and preserves the original device binding',
  ignore: !integrationEnabled,
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const deviceID = crypto.randomUUID();
    const firstEmail = `gp124-owner-${crypto.randomUUID()}@example.com`;
    const secondEmail = `gp124-other-${crypto.randomUUID()}@example.com`;
    const password = 'Password123!';

    const { data: firstUser, error: firstUserError } = await client.auth.admin.createUser({
      email: firstEmail,
      password,
      email_confirm: true,
    });
    if (firstUserError) throw firstUserError;
    const { data: secondUser, error: secondUserError } = await client.auth.admin.createUser({
      email: secondEmail,
      password,
      email_confirm: true,
    });
    if (secondUserError) throw secondUserError;
    const firstUserID = firstUser.user?.id;
    const secondUserID = secondUser.user?.id;
    assertExists(firstUserID);
    assertExists(secondUserID);

    try {
      const initialLink = await client.rpc('link_authenticated_device', {
        p_device_id: deviceID,
        p_auth_user_id: firstUserID,
        p_anon_session_id: null,
      });
      if (initialLink.error) throw initialLink.error;
      const initialPayload = initialLink.data?.[0] as LinkResult | undefined;
      if (!initialPayload) throw new Error('Expected initial link payload');
      assertEquals(initialPayload.status, 'linked');

      const rejectedRelink = await client.rpc('link_authenticated_device', {
        p_device_id: deviceID,
        p_auth_user_id: secondUserID,
        p_anon_session_id: null,
      });
      if (rejectedRelink.error) throw rejectedRelink.error;
      const rejectedPayload = rejectedRelink.data?.[0] as LinkResult | undefined;
      if (!rejectedPayload) throw new Error('Expected rejected relink payload');
      assertEquals(rejectedPayload.status, 'relink_rejected');
      assertEquals(rejectedPayload.attempts_used, null);
      assertEquals(rejectedPayload.server_lock_reason, null);

      const linkedRows = await client
        .from('device_links')
        .select('device_id, user_id')
        .eq('device_id', deviceID);
      if (linkedRows.error) throw linkedRows.error;
      assertEquals(linkedRows.data, [{ device_id: deviceID, user_id: firstUserID }]);
    } finally {
      await client.from('device_links').delete().eq('device_id', deviceID);
      await client.auth.admin.deleteUser(firstUserID);
      await client.auth.admin.deleteUser(secondUserID);
    }
  },
});
