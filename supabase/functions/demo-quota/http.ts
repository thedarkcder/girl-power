export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

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
