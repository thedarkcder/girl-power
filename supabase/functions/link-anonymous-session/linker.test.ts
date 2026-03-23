import { assertEquals, assertThrows } from 'std/assert';
import { responseForLinkStatus } from './linker.ts';

Deno.test('responseForLinkStatus maps linked to 200', () => {
  assertEquals(responseForLinkStatus('linked'), { httpStatus: 200, status: 'linked' });
});

Deno.test('responseForLinkStatus maps already_linked to 200', () => {
  assertEquals(responseForLinkStatus('already_linked'), { httpStatus: 200, status: 'already_linked' });
});

Deno.test('responseForLinkStatus rejects unknown states', () => {
  assertThrows(() => responseForLinkStatus('unexpected'));
});
