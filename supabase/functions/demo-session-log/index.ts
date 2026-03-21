import { createClient } from '@supabase/supabase-js';
import { getRuntimeConfig } from '../evaluate-session/config.ts';
import { createLogger } from '../evaluate-session/logger.ts';
import { DemoQuotaRepository } from '../demo-quota/repository.ts';
import { buildDemoSessionLogHandler } from './handler.ts';

const config = getRuntimeConfig();
const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'demo-session-log/1.0.0' } },
});
const repository = new DemoQuotaRepository(supabase);
const logger = createLogger('demo-session-log');

Deno.serve(buildDemoSessionLogHandler({ repository, logger }));
