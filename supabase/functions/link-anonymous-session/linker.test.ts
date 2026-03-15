import { assertEquals, assertThrows } from 'std/assert';
import { responseForLinkStatus } from './linker.ts';

Deno.test('responseForLinkStatus maps linked to 200', () => {
  assertEquals(responseForLinkStatus('linked'), { httpStatus: 200, status: 'linked' });
});

Deno.test('responseForLinkStatus maps duplicate to 409', () => {
  assertEquals(responseForLinkStatus('duplicate'), { httpStatus: 409, status: 'duplicate' });
});

Deno.test('responseForLinkStatus maps stale_session to 412', () => {
  assertEquals(responseForLinkStatus('stale_session'), { httpStatus: 412, status: 'stale_session' });
});

Deno.test('responseForLinkStatus rejects unknown states', () => {
  assertThrows(() => responseForLinkStatus('unexpected'));
});
