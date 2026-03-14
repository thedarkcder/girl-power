export type DemoQuotaDecisionType = 'allow' | 'deny' | 'timeout';

export type DemoQuotaLockReason = 'quota' | 'evaluation_denied' | 'evaluation_timeout' | 'server_sync';

export type DemoQuotaDecisionPayload = {
  type: DemoQuotaDecisionType;
  message?: string;
  ts: string;
};

export type DemoQuotaSnapshot = {
  attempts_used: number;
  active_attempt_index: number | null;
  last_decision: DemoQuotaDecisionPayload | null;
  server_lock_reason: DemoQuotaLockReason | null;
  last_sync_at: string | null;
};

export type DemoQuotaAttemptLog = {
  id: string;
  device_id: string;
  attempt_index: number;
  start_metadata: Record<string, unknown>;
  completion_metadata: Record<string, unknown>;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type DemoQuotaEvaluationDecision = {
  allowAnotherDemo: boolean;
  type: DemoQuotaDecisionType;
  message?: string;
  lockReason?: DemoQuotaLockReason;
  attemptsUsed: number;
  evaluatedAt: string;
  source: 'quota' | 'llm';
};

export type DemoQuotaLogRequest = {
  device_id: string;
  attempt_index: number;
  stage: 'start' | 'completion';
  metadata?: Record<string, unknown>;
};
