import { assertEquals } from 'std/assert';
import { buildDemoIdentityFetchHandler } from './demo-identity-fetch/index.ts';
import { buildDemoIdentityMirrorHandler } from './demo-identity-mirror/index.ts';
import { buildDemoSnapshotFetchHandler } from './demo-snapshot-fetch/index.ts';
import { buildDemoSnapshotMirrorHandler } from './demo-snapshot-mirror/index.ts';

const cases = [
  ['demo-identity-fetch', buildDemoIdentityFetchHandler(), 'GET'],
  ['demo-identity-mirror', buildDemoIdentityMirrorHandler(), 'POST'],
  ['demo-snapshot-fetch', buildDemoSnapshotFetchHandler(), 'POST'],
  ['demo-snapshot-mirror', buildDemoSnapshotMirrorHandler(), 'POST'],
] as const;

for (const [name, handler, method] of cases) {
  Deno.test(`${name} returns 410`, async () => {
    const response = await handler(new Request(`http://local.test/functions/v1/${name}`, { method }));
    const body = await response.json();

    assertEquals(response.status, 410);
    assertEquals(typeof body.error, 'string');
  });
}
