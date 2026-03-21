import { assertEquals } from 'std/assert';
import { DemoQuotaRepository } from './repository.ts';
import type { DemoQuotaAttemptLog, DemoQuotaSnapshot } from './types.ts';

Deno.test('logAttempt preserves the first completion audit payload when completion logging is retried', async () => {
  const existingAttempt = makeAttemptLog({
    completion_metadata: { source: 'first-write', reps: 12 },
    completed_at: '2026-03-14T12:01:00.000Z',
  });
  const client = new DemoQuotaClientStub(existingAttempt);
  const repository = new DemoQuotaRepository(client as never);
  const repositoryInternals = repository as unknown as Record<string, unknown>;

  repositoryInternals.fetchAttemptLog = () => Promise.resolve(existingAttempt);
  repositoryInternals.fetchStoredSnapshot = () => Promise.resolve(null);
  repositoryInternals.fetchAttemptLogs = () => Promise.resolve([existingAttempt]);
  repositoryInternals.persistSnapshot = (_deviceId: string, snapshot: DemoQuotaSnapshot) => Promise.resolve(snapshot);

  const result = await repository.logAttempt({
    device_id: existingAttempt.device_id,
    attempt_index: existingAttempt.attempt_index,
    stage: 'completion',
    metadata: { source: 'retry-write', reps: 1 },
  });

  assertEquals(client.upsertPayload?.completion_metadata, existingAttempt.completion_metadata);
  assertEquals(client.upsertPayload?.completed_at, existingAttempt.completed_at);
  assertEquals(result.attempt.completion_metadata, existingAttempt.completion_metadata);
  assertEquals(result.attempt.completed_at, existingAttempt.completed_at);
  assertEquals(result.snapshot.last_sync_at, existingAttempt.completed_at);
  assertEquals(result.snapshot.attempts_used, 1);
});

class DemoQuotaClientStub {
  upsertPayload: Record<string, unknown> | null = null;

  constructor(private readonly existingAttempt: DemoQuotaAttemptLog) {}

  from(table: string) {
    if (table !== 'demo_quota_attempt_logs') {
      throw new Error(`Unexpected table ${table}`);
    }

    return {
      upsert: (payload: Record<string, unknown>) => {
        this.upsertPayload = payload;
        return {
          select: () => ({
            single: <T>() => ({
              data: {
                ...this.existingAttempt,
                ...payload,
              } as T,
              error: null,
            }),
          }),
        };
      },
    };
  }
}

function makeAttemptLog(overrides: Partial<DemoQuotaAttemptLog> = {}): DemoQuotaAttemptLog {
  return {
    id: 'attempt-1',
    device_id: 'device-1',
    attempt_index: 1,
    start_metadata: { source: 'first-start' },
    completion_metadata: { source: 'first-complete' },
    started_at: '2026-03-14T12:00:00.000Z',
    completed_at: '2026-03-14T12:01:00.000Z',
    created_at: '2026-03-14T12:00:00.000Z',
    updated_at: '2026-03-14T12:01:00.000Z',
    ...overrides,
  };
}
