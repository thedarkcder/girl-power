import { z } from 'zod';
import { HttpError, jsonResponse, parseJson } from '../demo-quota/http.ts';

const RequestSchema = z.object({
  transaction_jws: z.string().trim().min(1, 'transaction_jws is required'),
});

export type ProfileRow = {
  id: string;
  email: string | null;
  created_at: string;
  updated_at: string;
  is_pro: boolean;
  pro_platform: 'apple' | 'external' | null;
  onboarding_completed: boolean;
  last_login_at: string | null;
};

export type AuthenticatedUser = {
  id: string;
  email?: string | null;
};

export type EntitlementPersistenceDeps = {
  authenticate(accessToken: string): Promise<AuthenticatedUser>;
  syncProfile(userId: string, email: string | null | undefined): Promise<ProfileRow>;
  verifyActiveEntitlement(transactionJws: string): Promise<unknown>;
  onUnexpectedError?(correlationId: string, error: unknown): void;
};

export function createSyncProfileEntitlementHandler(deps: EntitlementPersistenceDeps) {
  return async function handle(req: Request): Promise<Response> {
    const correlationId = crypto.randomUUID();

    try {
      if (req.method !== 'POST') {
        throw new HttpError(405, 'Only POST supported');
      }

      const accessToken = bearerToken(req);
      if (!accessToken) {
        throw new HttpError(401, 'Authenticated Supabase session required');
      }

      const payload = RequestSchema.parse(await parseJson(req));
      const authUser = await deps.authenticate(accessToken);
      await deps.verifyActiveEntitlement(payload.transaction_jws);
      const profile = await deps.syncProfile(authUser.id, authUser.email);
      return jsonResponse({ profile }, 200);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return jsonResponse({ correlation_id: correlationId, error: 'invalid_body', details: error.issues }, 400);
      }
      if (error instanceof HttpError) {
        return jsonResponse({ correlation_id: correlationId, error: error.message }, error.status);
      }
      deps.onUnexpectedError?.(correlationId, error);
      return jsonResponse({ correlation_id: correlationId, error: 'internal_error' }, 500);
    }
  };
}

function bearerToken(req: Request): string | null {
  const header = req.headers.get('Authorization')?.trim() ?? '';
  if (!header.startsWith('Bearer ')) {
    return null;
  }
  const token = header.slice('Bearer '.length).trim();
  return token.length === 0 ? null : token;
}
