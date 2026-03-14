import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  DemoQuotaAttemptLog,
  DemoQuotaDecisionPayload,
  DemoQuotaLockReason,
  DemoQuotaLogRequest,
  DemoQuotaSnapshot,
} from './types.ts';

type SnapshotRow = {
  device_id: string;
  attempts_used: number;
  active_attempt_index: number | null;
  last_decision: DemoQuotaDecisionPayload | null;
  server_lock_reason: DemoQuotaLockReason | null;
  last_sync_at: string | null;
};

export class DemoQuotaRepository {
  constructor(private readonly client: SupabaseClient) {}

  async fetchAttemptLog(deviceId: string, attemptIndex: number): Promise<DemoQuotaAttemptLog | null> {
    const { data, error } = await this.client
      .from('demo_quota_attempt_logs')
      .select('id, device_id, attempt_index, start_metadata, completion_metadata, started_at, completed_at, created_at, updated_at')
      .eq('device_id', deviceId)
      .eq('attempt_index', attemptIndex)
      .maybeSingle<DemoQuotaAttemptLog>();

    if (error && error.code !== 'PGRST116') {
      throw new Error(`Failed to fetch demo quota attempt log: ${error.message}`);
    }

    return data ?? null;
  }

  async fetchSnapshot(deviceId: string): Promise<DemoQuotaSnapshot | null> {
    const [stored, logs] = await Promise.all([
      this.fetchStoredSnapshot(deviceId),
      this.fetchAttemptLogs(deviceId),
    ]);
    return this.buildAuthoritativeSnapshot(stored, logs);
  }

  async logAttempt(request: DemoQuotaLogRequest): Promise<{ attempt: DemoQuotaAttemptLog; snapshot: DemoQuotaSnapshot }> {
    const existingAttempt = await this.fetchAttemptLog(request.device_id, request.attempt_index);
    const now = new Date().toISOString();
    const payload = {
      device_id: request.device_id,
      attempt_index: request.attempt_index,
      start_metadata: request.stage === 'start' ? request.metadata ?? {} : existingAttempt?.start_metadata ?? {},
      completion_metadata: request.stage === 'completion' ? request.metadata ?? {} : existingAttempt?.completion_metadata ?? {},
      started_at: request.stage === 'start' ? existingAttempt?.started_at ?? now : existingAttempt?.started_at ?? null,
      completed_at: request.stage === 'completion' ? now : existingAttempt?.completed_at ?? null,
    };

    const { data, error } = await this.client
      .from('demo_quota_attempt_logs')
      .upsert(payload, { onConflict: 'device_id,attempt_index' })
      .select('id, device_id, attempt_index, start_metadata, completion_metadata, started_at, completed_at, created_at, updated_at')
      .single<DemoQuotaAttemptLog>();

    if (error || !data) {
      throw new Error(`Failed to persist demo quota attempt log: ${error?.message ?? 'unknown error'}`);
    }

    const currentSnapshot = await this.fetchStoredSnapshot(request.device_id);
    const mergedSnapshot = this.mergeSnapshot(currentSnapshot, await this.fetchAttemptLogs(request.device_id), {
      active_attempt_index: request.stage === 'start' ? request.attempt_index : null,
      attempts_used: request.stage === 'completion' ? request.attempt_index : currentSnapshot?.attempts_used ?? 0,
      server_lock_reason: request.stage === 'completion' && request.attempt_index >= 2 ? 'quota' : undefined,
      last_sync_at: now,
    });
    const snapshot = await this.persistSnapshot(request.device_id, mergedSnapshot);
    return { attempt: data, snapshot };
  }

  async mirrorSnapshot(deviceId: string, snapshot: DemoQuotaSnapshot): Promise<DemoQuotaSnapshot> {
    const stored = await this.fetchStoredSnapshot(deviceId);
    const attemptLogs = await this.fetchAttemptLogs(deviceId);
    const merged = this.mergeSnapshot(stored, attemptLogs, snapshot);
    return this.persistSnapshot(deviceId, merged);
  }

  persistDecisionSnapshot(deviceId: string, snapshot: DemoQuotaSnapshot): Promise<DemoQuotaSnapshot> {
    return this.persistSnapshot(deviceId, snapshot);
  }

  snapshotFromDecision(
    existing: DemoQuotaSnapshot | null,
    attemptLogs: DemoQuotaAttemptLog[],
    decision: {
      allowAnotherDemo: boolean;
      type: 'allow' | 'deny' | 'timeout';
      message?: string;
      lockReason?: DemoQuotaLockReason;
      attemptsUsed: number;
      evaluatedAt: string;
    },
  ): DemoQuotaSnapshot {
    const payload: DemoQuotaSnapshot = {
      attempts_used: decision.attemptsUsed,
      active_attempt_index: null,
      last_decision: {
        type: decision.type,
        message: decision.message,
        ts: decision.evaluatedAt,
      },
      server_lock_reason: decision.lockReason ?? null,
      last_sync_at: decision.evaluatedAt,
    };
    return this.mergeSnapshot(existing, attemptLogs, payload);
  }

  private async fetchStoredSnapshot(deviceId: string): Promise<DemoQuotaSnapshot | null> {
    const { data, error } = await this.client
      .from('demo_quota_snapshots')
      .select('device_id, attempts_used, active_attempt_index, last_decision, server_lock_reason, last_sync_at')
      .eq('device_id', deviceId)
      .maybeSingle<SnapshotRow>();

    if (error && error.code !== 'PGRST116') {
      throw new Error(`Failed to fetch demo quota snapshot: ${error.message}`);
    }

    if (!data) {
      return null;
    }

    return {
      attempts_used: data.attempts_used,
      active_attempt_index: data.active_attempt_index,
      last_decision: data.last_decision,
      server_lock_reason: data.server_lock_reason,
      last_sync_at: data.last_sync_at,
    };
  }

  private async fetchAttemptLogs(deviceId: string): Promise<DemoQuotaAttemptLog[]> {
    const { data, error } = await this.client
      .from('demo_quota_attempt_logs')
      .select('id, device_id, attempt_index, start_metadata, completion_metadata, started_at, completed_at, created_at, updated_at')
      .eq('device_id', deviceId)
      .order('attempt_index', { ascending: true });

    if (error) {
      throw new Error(`Failed to fetch demo quota attempt logs: ${error.message}`);
    }

    return data ?? [];
  }

  private async persistSnapshot(deviceId: string, snapshot: DemoQuotaSnapshot): Promise<DemoQuotaSnapshot> {
    const { data, error } = await this.client
      .from('demo_quota_snapshots')
      .upsert({
        device_id: deviceId,
        attempts_used: snapshot.attempts_used,
        active_attempt_index: snapshot.active_attempt_index,
        last_decision: snapshot.last_decision,
        server_lock_reason: snapshot.server_lock_reason,
        last_sync_at: snapshot.last_sync_at,
      }, { onConflict: 'device_id' })
      .select('attempts_used, active_attempt_index, last_decision, server_lock_reason, last_sync_at')
      .single<Omit<SnapshotRow, 'device_id'>>();

    if (error || !data) {
      throw new Error(`Failed to persist demo quota snapshot: ${error?.message ?? 'unknown error'}`);
    }

    return {
      attempts_used: data.attempts_used,
      active_attempt_index: data.active_attempt_index,
      last_decision: data.last_decision,
      server_lock_reason: data.server_lock_reason,
      last_sync_at: data.last_sync_at,
    };
  }

  private buildAuthoritativeSnapshot(
    stored: DemoQuotaSnapshot | null,
    attemptLogs: DemoQuotaAttemptLog[],
  ): DemoQuotaSnapshot | null {
    if (!stored && attemptLogs.length === 0) {
      return null;
    }

    return this.mergeSnapshot(stored, attemptLogs);
  }

  private mergeSnapshot(
    stored: DemoQuotaSnapshot | null,
    attemptLogs: DemoQuotaAttemptLog[],
    override?: Partial<DemoQuotaSnapshot>,
  ): DemoQuotaSnapshot {
    const highestCompletedAttempt = attemptLogs
      .filter((attempt) => attempt.completed_at)
      .reduce((highest, attempt) => Math.max(highest, attempt.attempt_index), 0);
    const activeAttempt = attemptLogs
      .filter((attempt) => attempt.started_at && !attempt.completed_at)
      .reduce<number | null>((highest, attempt) => {
        if (!highest) return attempt.attempt_index;
        return Math.max(highest, attempt.attempt_index);
      }, null);
    const attemptsUsed = Math.min(
      2,
      Math.max(stored?.attempts_used ?? 0, override?.attempts_used ?? 0, highestCompletedAttempt),
    );
    const lastDecision = latestDecision(stored?.last_decision ?? null, override?.last_decision ?? null);
    const overrideLockReason = hasOwn(override, 'server_lock_reason') ? override?.server_lock_reason ?? null : undefined;
    const overrideActiveAttempt = hasOwn(override, 'active_attempt_index') ? override?.active_attempt_index ?? null : undefined;
    const serverLockReason = attemptsUsed >= 2
      ? 'quota'
      : overrideLockReason ?? stored?.server_lock_reason ?? lockReasonFromDecision(lastDecision);
    const lastSyncAt = override?.last_sync_at ?? stored?.last_sync_at ?? new Date().toISOString();
    const activeAttemptIndex = attemptsUsed >= 2
      ? null
      : activeAttempt ?? overrideActiveAttempt ?? stored?.active_attempt_index ?? null;

    return {
      attempts_used: attemptsUsed,
      active_attempt_index: activeAttemptIndex,
      last_decision: lastDecision,
      server_lock_reason: serverLockReason,
      last_sync_at: lastSyncAt,
    };
  }
}

function hasOwn<T extends object>(value: T | undefined, key: keyof T): boolean {
  return Boolean(value && Object.prototype.hasOwnProperty.call(value, key));
}

function latestDecision(
  left: DemoQuotaDecisionPayload | null,
  right: DemoQuotaDecisionPayload | null,
): DemoQuotaDecisionPayload | null {
  if (!left) return right;
  if (!right) return left;
  return Date.parse(right.ts) >= Date.parse(left.ts) ? right : left;
}

function lockReasonFromDecision(decision: DemoQuotaDecisionPayload | null): DemoQuotaLockReason | null {
  if (!decision) {
    return null;
  }
  switch (decision.type) {
    case 'allow':
      return null;
    case 'deny':
      return 'evaluation_denied';
    case 'timeout':
      return 'evaluation_timeout';
  }
}
