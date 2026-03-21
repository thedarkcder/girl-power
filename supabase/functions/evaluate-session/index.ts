import { createClient } from '@supabase/supabase-js';
import { getRuntimeConfig } from './config.ts';
import { createLogger } from './logger.ts';
import { RateLimiter } from './rate-limit.ts';
import { SessionRepository } from './repository.ts';
import { LLMProvider } from './llm-provider.ts';
import { DemoQuotaRepository } from '../demo-quota/repository.ts';
import { buildEvaluateSessionHandler } from './handler.ts';

const config = getRuntimeConfig();
const supabase = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: { persistSession: false },
  global: { headers: { 'X-Client-Info': 'evaluate-session/1.0.0' } },
});
const logger = createLogger('evaluate-session');
const rateLimiter = new RateLimiter(supabase, config);
const repository = new SessionRepository(supabase, config);
const quotaRepository = new DemoQuotaRepository(supabase);
const llmProvider = new LLMProvider(config.llmModel);

Deno.serve(buildEvaluateSessionHandler({
  config,
  rateLimiter,
  sessionRepository: repository,
  quotaRepository,
  llmProvider,
  logger,
}));
