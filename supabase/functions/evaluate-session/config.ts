export type RuntimeConfig = {
  supabaseUrl: string;
  serviceRoleKey: string;
  anonKey?: string;
  rateLimitAttempts: number;
  rateLimitWindowSeconds: number;
  llmTimeoutMs: number;
  llmModel: string;
};

let cachedConfig: RuntimeConfig | null = null;

const intFromEnv = (key: string, fallback: number): number => {
  const raw = Deno.env.get(key);
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};

export function getRuntimeConfig(): RuntimeConfig {
  if (cachedConfig) return cachedConfig;
  const supabaseUrl = mustGetEnv('SUPABASE_URL');
  const serviceRoleKey = mustGetEnv('SUPABASE_SERVICE_ROLE_KEY');
  cachedConfig = {
    supabaseUrl,
    serviceRoleKey,
    anonKey: Deno.env.get('SUPABASE_ANON_KEY') ?? undefined,
    rateLimitAttempts: intFromEnv('RATE_LIMIT_ATTEMPTS', 3),
    rateLimitWindowSeconds: intFromEnv('RATE_LIMIT_WINDOW_SECONDS', 60),
    llmTimeoutMs: intFromEnv('LLM_TIMEOUT_MS', 5000),
    llmModel: Deno.env.get('LLM_MODEL') ?? 'gpt-4o-mini',
  };
  return cachedConfig;
}

function mustGetEnv(key: string): string {
  const value = Deno.env.get(key);
  if (!value) {
    throw new Error(`Missing required environment variable ${key}`);
  }
  return value;
}
