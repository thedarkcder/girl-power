import { HttpError, jsonResponse } from '../demo-quota/http.ts';

const REMOVAL_MESSAGE = 'demo identity lookup recovery is unsupported; rely on the persisted keychain device_id';

Deno.serve((req) => {
  const correlationId = crypto.randomUUID();

  try {
    if (req.method !== 'POST') {
      throw new HttpError(405, 'Only POST supported');
    }

    throw new HttpError(410, REMOVAL_MESSAGE);
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
    }
    return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
  }
});
