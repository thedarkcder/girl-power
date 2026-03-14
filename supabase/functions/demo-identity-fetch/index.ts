import { createLogger } from '../evaluate-session/logger.ts';
import { HttpError, jsonResponse } from '../demo-quota/http.ts';
const logger = createLogger('demo-identity-fetch');

export function buildDemoIdentityFetchHandler() {
  return (_req: Request) => {
    const correlationId = crypto.randomUUID();

    try {
      throw new HttpError(410, 'Identity recovery endpoint disabled; the app now relies on local keychain identity only.');
    } catch (error) {
      if (error instanceof HttpError) {
        return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
      }
      logger.error('Unhandled demo-identity-fetch error', { correlationId, error: `${error}` });
      return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
    }
  };
}

if (import.meta.main) {
  Deno.serve(buildDemoIdentityFetchHandler());
}
