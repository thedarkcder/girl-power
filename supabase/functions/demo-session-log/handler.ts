import { z } from 'zod';
import { HttpError, jsonResponse, parseJson, supportedDemoAttemptIndexSchema } from '../demo-quota/http.ts';
import type { DemoQuotaLogRequest } from '../demo-quota/types.ts';

const RequestSchema = z.object({
  device_id: z.string().min(1),
  attempt_index: supportedDemoAttemptIndexSchema,
  stage: z.enum(['start', 'completion']),
  metadata: z.record(z.string(), z.unknown()).optional(),
});

export type DemoSessionLogHandlerDependencies = {
  repository: {
    logAttempt(
      request: DemoQuotaLogRequest,
    ): Promise<{ attempt: unknown; snapshot: unknown }>;
  };
  logger: {
    error(message: string, context: Record<string, unknown>): void;
  };
};

export function buildDemoSessionLogHandler(deps: DemoSessionLogHandlerDependencies) {
  return async (req: Request): Promise<Response> => {
    const correlationId = crypto.randomUUID();

    try {
      if (req.method !== 'POST') {
        throw new HttpError(405, 'Only POST supported');
      }

      const request = RequestSchema.parse(await parseJson<DemoQuotaLogRequest>(req));
      const result = await deps.repository.logAttempt(request);
      return jsonResponse({
        correlation_id: correlationId,
        attempt: result.attempt,
        snapshot: result.snapshot,
      }, 200);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return jsonResponse({ correlation_id: correlationId, error: 'invalid_body', details: error.issues }, 400);
      }
      if (error instanceof HttpError) {
        return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
      }
      deps.logger.error('Unhandled demo-session-log error', { correlationId, error: `${error}` });
      return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
    }
  };
}
