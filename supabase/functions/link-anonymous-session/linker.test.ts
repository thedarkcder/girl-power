import { assertEquals, assertThrows } from 'std/assert';
import { responseForLinkStatus } from './linker.ts';

Deno.test('responseForLinkStatus maps linked to 200', () => {
  assertEquals(responseForLinkStatus('linked'), { httpStatus: 200, status: 'linked' });
});

Deno.test('responseForLinkStatus maps already_linked to 200', () => {
  assertEquals(responseForLinkStatus('already_linked'), { httpStatus: 200, status: 'already_linked' });
});

Deno.test('responseForLinkStatus maps relink_rejected to 409', () => {
  assertEquals(responseForLinkStatus('relink_rejected'), { httpStatus: 409, status: 'relink_rejected' });
});

Deno.test('responseForLinkStatus rejects unknown states', () => {
  assertThrows(() => responseForLinkStatus('unexpected'));
});
