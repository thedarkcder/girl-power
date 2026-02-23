import type { SupabaseClient } from '@supabase/supabase-js';
import type { RuntimeConfig } from './config.ts';
import type { RateLimitSnapshot } from './types.ts';

type RpcResult<T> = {
  data: T | null;
  error: { message: string } | null;
};

export class RateLimiter {
  constructor(
    private readonly client: SupabaseClient,
    private readonly config: Pick<RuntimeConfig, 'rateLimitAttempts' | 'rateLimitWindowSeconds'>,
  ) {}

  async evaluate(deviceId: string): Promise<RateLimitSnapshot> {
    const { data, error } = await this.client.rpc('check_device_attempt_limit', {
      p_device_id: deviceId,
      p_window_seconds: this.config.rateLimitWindowSeconds,
      p_max_attempts: this.config.rateLimitAttempts,
    }) as RpcResult<{ allowed: boolean; attempt_count: number; window_start: string }>;

    if (error) {
      throw new Error(`rate-limit rpc failed: ${error.message}`);
    }

    const snapshot = data ?? { allowed: true, attempt_count: 0, window_start: new Date().toISOString() };
    const attemptCount = typeof snapshot.attempt_count === 'number'
      ? snapshot.attempt_count
      : Number(snapshot.attempt_count ?? 0);
    return {
      allowed: Boolean(snapshot.allowed),
      attempt_count: Number.isFinite(attemptCount) ? attemptCount : 0,
      window_start: snapshot.window_start ?? new Date().toISOString(),
      limit: this.config.rateLimitAttempts,
      window_seconds: this.config.rateLimitWindowSeconds,
    };
  }
}
