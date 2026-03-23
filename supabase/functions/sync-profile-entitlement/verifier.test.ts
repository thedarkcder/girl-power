import { assertEquals, assertRejects } from 'std/assert';
import { HttpError } from '../demo-quota/http.ts';
import { createEntitlementVerifier } from './verifier.ts';

Deno.test('entitlement verifier accepts active local-testing transactions only when explicitly allowed', async () => {
  const verifier = createEntitlementVerifier({
    allowLocalTesting: true,
    bundleId: 'com.route25.GirlPower',
    productIds: new Set(['com.girlpower.app.pro.monthly']),
  });

  const entitlement = await verifier.verifyActiveEntitlement(
    unsignedTransactionJws({
      environment: 'LocalTesting',
      bundleId: 'com.route25.GirlPower',
      productId: 'com.girlpower.app.pro.monthly',
      transactionId: 'tx-1',
      originalTransactionId: 'orig-1',
      signedDate: Date.now(),
      expiresDate: Date.now() + 60_000,
    }),
  );

  assertEquals(entitlement.productId, 'com.girlpower.app.pro.monthly');
  assertEquals(entitlement.transactionId, 'tx-1');
  assertEquals(entitlement.environment, 'LocalTesting');
});

Deno.test('entitlement verifier rejects unsigned local-testing transactions when local mode is disabled', async () => {
  const verifier = createEntitlementVerifier({
    allowLocalTesting: false,
    bundleId: 'com.route25.GirlPower',
    productIds: new Set(['com.girlpower.app.pro.monthly']),
  });

  await assertRejects(
    () => verifier.verifyActiveEntitlement(
      unsignedTransactionJws({
        environment: 'LocalTesting',
        bundleId: 'com.route25.GirlPower',
        productId: 'com.girlpower.app.pro.monthly',
        transactionId: 'tx-1',
        signedDate: Date.now(),
        expiresDate: Date.now() + 60_000,
      }),
    ),
    HttpError,
  );
});

Deno.test('entitlement verifier rejects expired transactions even when the JWS shape is otherwise valid', async () => {
  const verifier = createEntitlementVerifier({
    allowLocalTesting: true,
    bundleId: 'com.route25.GirlPower',
    productIds: new Set(['com.girlpower.app.pro.monthly']),
  });

  await assertRejects(
    () => verifier.verifyActiveEntitlement(
      unsignedTransactionJws({
        environment: 'Xcode',
        bundleId: 'com.route25.GirlPower',
        productId: 'com.girlpower.app.pro.monthly',
        transactionId: 'tx-1',
        signedDate: Date.now(),
        expiresDate: Date.now() - 1_000,
      }),
    ),
    HttpError,
    'Expired App Store entitlement',
  );
});

function unsignedTransactionJws(payload: Record<string, unknown>): string {
  const header = { alg: 'none', typ: 'JWT' };
  return [encodeBase64Url(header), encodeBase64Url(payload), ''].join('.');
}

function encodeBase64Url(value: Record<string, unknown>): string {
  return btoa(JSON.stringify(value))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}
