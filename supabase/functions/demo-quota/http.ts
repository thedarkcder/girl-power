import { z } from 'zod';

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export const supportedDemoAttemptIndexSchema = z
  .number()
  .int()
  .min(1, 'attempt_index must be between 1 and 2')
  .max(2, 'attempt_index must be between 1 and 2');

export const evaluableDemoAttemptIndexSchema = supportedDemoAttemptIndexSchema.refine(
  (attemptIndex) => attemptIndex === 1,
  { message: 'attempt_index must be 1 for evaluate-session' },
);

export function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
    },
  });
}

export async function parseJson<T>(req: Request): Promise<T> {
  try {
    return await req.json() as T;
  } catch {
    throw new HttpError(400, 'Invalid JSON body');
  }
}
