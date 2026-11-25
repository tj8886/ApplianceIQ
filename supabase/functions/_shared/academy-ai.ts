// IQ Academy AI policy. The server, never the browser, picks the model, the
// maximum answer length and the thinking setting for each Academy feature, and
// every call is reserved against the company's limits before the model runs
// (see migration 20261125170000_academy_ai_spending_limits.sql).
//
// Model IDs are pinned here, not read from the AI_MODEL_* tier variables,
// because the dollar budget is enforced from a price per model: the database
// refuses any model it has no price for, so swapping a tier variable to a new
// model could otherwise stop the Academy or misprice it. Change the model here
// and in tj_private.academy_ai_cost_usd / academy_ai_feature_model together.
export type AcademyFeature = 'trainer' | 'beat_the_bot' | 'showroom' | 'grading' | 'content_ideas';
export type AcademyMessage = { role: 'user' | 'assistant'; content: string };
type Policy = { model: string; maxTokens: number; thinking: Record<string, string>; effort: 'low' | 'medium' };

export const ACADEMY_ROUTINE_MODEL = 'claude-haiku-5-5';
export const ACADEMY_GRADING_MODEL = 'claude-sonnet-5-5';
// Routine turns run with thinking off so the answer cap is the whole output.
// Sonnet 5.5 rejects {type:'disabled'}; 'between_tools' is its no-thinking mode.
const routine = (maxTokens: number): Policy => ({ model: ACADEMY_ROUTINE_MODEL, maxTokens, thinking: { type: 'disabled' }, effort: 'low' });
export const ACADEMY_POLICY: Readonly<Record<AcademyFeature, Policy>> = Object.freeze({
  trainer: routine(700),        // AI Trainer and coach questions: 2-4 short paragraphs
  showroom: routine(500),       // Academy role-plays and KPI coaching turns
  beat_the_bot: routine(500),   // Beat the Bot customer / expert turns
  content_ideas: routine(1200), // admin content suggestions (5 short JSON items)
  grading: { model: ACADEMY_GRADING_MODEL, maxTokens: 1800, thinking: { type: 'between_tools' }, effort: 'medium' },
});

export class AcademyLimitError extends Error {
  reason: string; limit: number | null;
  constructor(reason: string, limit: number | null = null) { super('academy_ai_limit'); this.reason = reason; this.limit = limit; }
}

// Plain messages shown to learners. Lessons, quizzes and progress never depend on AI.
export function academyLimitMessage(reason: string, limit: number | null = null): string {
  const still = ' Your lessons, quizzes and progress still work.';
  const n = (fallback: number) => limit ?? fallback;
  switch (reason) {
    case 'ai_paused_platform': return 'AI coaching is paused for everyone right now.' + still;
    case 'ai_paused_company': return 'Your company has paused AI coaching.' + still;
    case 'budget_not_set': return 'AI coaching is paused until your company admin sets a monthly AI budget.' + still;
    case 'no_academy_seats': return 'AI coaching needs an active Academy subscription with seats for your company.' + still;
    case 'company_budget_reached': return "Your company has used this month's AI budget, so AI coaching is paused until the 1st or until your admin raises the budget." + still;
    case 'trainer_question_limit': return `You've used all ${n(200)} AI Trainer questions for this month. They reset on the 1st.` + still;
    case 'company_trainer_question_pool': return "Your company has used all of this month's AI Trainer questions. They reset on the 1st." + still;
    case 'graded_roleplay_limit': return `You've used all ${n(10)} graded role-plays for this month. They reset on the 1st.` + still;
    case 'company_graded_roleplay_pool': return "Your company has used all of this month's graded role-plays. They reset on the 1st." + still;
    case 'roleplay_turn_limit': return `This role-play has reached its ${n(20)}-turn limit. End it to see your results, or start a new one.`;
    case 'roleplay_time_limit': return `This role-play has reached its ${n(15)}-minute limit. End it to see your results, or start a new one.`;
    case 'already_graded': case 'roleplay_ended': return 'This role-play has already been scored. Start a new one to keep practising.';
    case 'not_gradable': return "This practice chat isn't scored.";
    default: return 'AI coaching is unavailable right now.' + still;
  }
}

export function limitResponseBody(e: AcademyLimitError) {
  return { error: 'ai_limit_reached', reason: e.reason, message: academyLimitMessage(e.reason, e.limit) };
}

// UTF-8 bytes of the exact request content. A token always covers at least one
// byte, so this is an upper bound on input tokens; the JSON framing more than
// covers per-message overhead.
export function academyInputBytes(system: string, messages: AcademyMessage[]): number {
  return new TextEncoder().encode(JSON.stringify({ system, messages })).length + 64;
}

type Outcome = 'failed' | 'unknown';
class ProviderError extends Error { outcome: Outcome; constructor(outcome: Outcome, msg: string) { super(msg); this.outcome = outcome; } }

export async function callAcademyModel(feature: AcademyFeature, key: string, system: string, messages: AcademyMessage[], fetchImpl: typeof fetch = fetch) {
  const p = ACADEMY_POLICY[feature];
  let r: Response;
  try {
    r = await fetchImpl('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({ model: p.model, max_tokens: p.maxTokens, system, messages, thinking: p.thinking, output_config: { effort: p.effort } }),
      signal: AbortSignal.timeout(45000),
    });
  } catch { throw new ProviderError('unknown', 'model_call_unconfirmed'); }
  // An error status is not billed. A lost or unreadable success body may have been.
  if (!r.ok) throw new ProviderError('failed', 'provider_status_' + r.status);
  let data: any;
  try { data = await r.json(); } catch { throw new ProviderError('unknown', 'provider_response_unreadable'); }
  const input = Number(data?.usage?.input_tokens ?? NaN), output = Number(data?.usage?.output_tokens ?? NaN);
  if (!Number.isInteger(input) || !Number.isInteger(output) || input < 0 || output < 0) throw new ProviderError('unknown', 'provider_usage_missing');
  const text = (Array.isArray(data.content) ? data.content : []).filter((b: any) => b?.type === 'text' && typeof b.text === 'string').map((b: any) => b.text).join('\n');
  return { answer: text, stopReason: String(data.stop_reason ?? ''), model: p.model, usage: { input_tokens: input, output_tokens: output } };
}

// Reserve → call → settle. Throws AcademyLimitError when a limit applies (no
// model call is made); any other failure is recorded and rethrown.
// checkReservation can refuse a call after the turn is known (for example, a
// chat history longer than the role-play's recorded turns); the reservation is
// then released and the turn given back.
export class AcademyRequestError extends Error { constructor(msg: string) { super(msg); } }
export async function runAcademyCall({ service, nativeUser, organizationId, feature, sessionKey = null, newTurn = false, system, messages, env, fetchImpl = fetch, checkReservation }: {
  service: any; nativeUser: string; organizationId: string; feature: AcademyFeature; sessionKey?: string | null; newTurn?: boolean;
  system: string; messages: AcademyMessage[]; env: (n: string) => string | undefined; fetchImpl?: typeof fetch;
  checkReservation?: (reservation: { turns: number | null }) => string | null;
}) {
  const policy = ACADEMY_POLICY[feature];
  if (!policy) throw new Error('unknown_feature');
  const key = env('ANTHROPIC_API_KEY');
  if (!key) throw new Error('model_configuration_unavailable');
  const reserved = await service.rpc('aiq_academy_ai_reserve', {
    p_native_user: nativeUser, p_organization_id: organizationId, p_feature: feature, p_model: policy.model,
    p_max_output_tokens: policy.maxTokens, p_input_bytes: academyInputBytes(system, messages), p_session_key: sessionKey, p_new_turn: newTurn,
  });
  if (reserved.error) throw Object.assign(new Error('limit_check_failed'), { code: reserved.error.code });
  if (!reserved.data?.allowed) throw new AcademyLimitError(String(reserved.data?.reason ?? 'unavailable'), Number.isInteger(reserved.data?.limit) ? reserved.data.limit : null);
  const callId = reserved.data.call_id;
  const refusal = checkReservation?.(reserved.data) ?? null;
  if (refusal) {
    await service.rpc('aiq_academy_ai_settle', { p_call_id: callId, p_outcome: 'failed', p_input_tokens: 0, p_output_tokens: 0, p_error: refusal.slice(0, 200) });
    throw new AcademyRequestError(refusal);
  }
  let result;
  try { result = await callAcademyModel(feature, key, system, messages, fetchImpl); }
  catch (e) {
    const outcome: Outcome = e instanceof ProviderError ? e.outcome : 'unknown';
    await service.rpc('aiq_academy_ai_settle', { p_call_id: callId, p_outcome: outcome, p_input_tokens: 0, p_output_tokens: 0, p_error: String((e as Error).message).slice(0, 200) });
    throw new Error('model_call_failed');
  }
  const settled = await service.rpc('aiq_academy_ai_settle', { p_call_id: callId, p_outcome: 'ok', p_input_tokens: result.usage.input_tokens, p_output_tokens: result.usage.output_tokens });
  if (settled.error) throw new Error('cost_record_failed');
  const refused = result.stopReason === 'refusal';
  return {
    ...result,
    answer: refused || !result.answer ? "I can't help with that one. Try asking about the lesson or the role-play in a different way." : result.answer,
    refused, costUsd: Number(settled.data?.cost_usd ?? 0), callId,
    turns: reserved.data.turns as number | null, turnsLimit: reserved.data.turns_limit as number, minutesLimit: reserved.data.minutes_limit as number,
  };
}
