// 사용자별 하루 AI 호출 한도(supabase/sql/008_ai_usage_limits.sql의 consume_ai_quota).
// Groq를 부르기 직전에만 호출해, 모델을 부르지 않는 답(문서 없음·입력 오류)은 횟수에 넣지 않는다.
// 사용자 세션으로 부르므로 남의 횟수를 쓰거나 고칠 수 없다.

export const QUOTA_KINDS = ['help', 'record'];

/**
 * @returns {Promise<{ allowed: boolean, reason?: string, limit?: number, remaining?: number }>}
 * 한도 함수를 부를 수 없으면(마이그레이션 미적용 등) 예외를 던진다 — 한도 없이 모델을 부르지 않는다.
 */
export async function consumeQuota({ fetch, env, authorization, kind }) {
  if (!QUOTA_KINDS.includes(kind)) throw new Error('quota kind');
  const response = await fetch(`${env('SUPABASE_URL')}/rest/v1/rpc/consume_ai_quota`, {
    method: 'POST',
    headers: { authorization, apikey: env('SUPABASE_ANON_KEY') ?? '', 'content-type': 'application/json' },
    body: JSON.stringify({ p_kind: kind }),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error('quota');
  const result = await response.json();
  if (typeof result?.allowed !== 'boolean') throw new Error('quota');
  return result;
}
