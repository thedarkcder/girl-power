import { jsonResponse } from '../demo-quota/http.ts';

Deno.serve((req) => {
  if (req.method !== 'GET') {
    return jsonResponse({ error: 'Only GET supported' }, 405);
  }

  return jsonResponse({
    error: 'unsupported_identity_recovery',
    message: 'Reinstall-safe identity recovery is disabled until an approved durable identity contract exists.',
  }, 410);
});
