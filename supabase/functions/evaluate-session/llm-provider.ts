import type { EvaluateSessionInput, LLMResult } from './types.ts';

export class LLMProvider {
  constructor(private readonly model: string) {}

  async generate(
    input: EvaluateSessionInput,
    opts: { signal?: AbortSignal } = {},
  ): Promise<LLMResult> {
    if (opts.signal?.aborted) {
      throw new DOMException('Aborted', 'AbortError');
    }

    const prompt = input.prompt.trim();
    if (!prompt) {
      throw new Error('Prompt is empty after trimming');
    }

    // Deterministic stub: derive insights from prompt length/context keys
    const tokensUsed = Math.max(1, Math.ceil(prompt.length / 4));
    const contextGoal = typeof input.context?.goal === 'string'
      ? String(input.context?.goal)
      : undefined;
    const guidance = [
      'Maintain controlled tempo',
      contextGoal ? `Focus on goal: ${contextGoal}` : 'Track perceived exertion',
    ];
    const summary = `Coach insight for prompt hash ${prompt.slice(0, 32)}`;

    return {
      model: this.model,
      response: {
        summary,
        guidance,
        tokens_used: tokensUsed,
      },
      moderation: {
        flagged: false,
        categories: [],
      },
    };
  }
}
