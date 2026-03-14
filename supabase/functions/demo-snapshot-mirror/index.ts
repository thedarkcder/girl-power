import { createLogger } from '../evaluate-session/logger.ts';
import { HttpError, jsonResponse } from '../demo-quota/http.ts';
const logger = createLogger('demo-snapshot-mirror');
export function buildDemoSnapshotMirrorHandler() {
  return (_req: Request) => {
    const correlationId = crypto.randomUUID();

    try {
      throw new HttpError(410, 'Snapshot recovery endpoint disabled; caller-supplied device IDs are no longer accepted.');
    } catch (error) {
      if (error instanceof HttpError) {
        return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
      }
      logger.error('Unhandled demo-snapshot-mirror error', { correlationId, error: `${error}` });
      return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
    }
  };
}

if (import.meta.main) {
  Deno.serve(buildDemoSnapshotMirrorHandler());
}
