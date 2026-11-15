// Deletes the signed-in user's account after PIN re-entry.
// PINs, tokens, credentials and upstream responses must never be logged.
// Deleting the Auth user cascades to profiles, grade_records, mock_exam_records,
// school_record_evidence and nickname_accounts (all reference auth.users on delete cascade).
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
};

Deno.serve(async (req: Request) => {
  const reply = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  if (req.method !== 'POST') return reply(405, { error: 'METHOD' });
  const authorization = req.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) return reply(401, { error: 'AUTH' });

  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  const call = (path: string, init: RequestInit = {}) =>
    fetch(`${url}${path}`, { ...init, headers: { ...admin, ...(init.headers ?? {}) }, signal: AbortSignal.timeout(15000) });

  try {
    // 1. Who is calling? Verified by Supabase Auth, not by anything in the body.
    const auth = await fetch(`${url}/auth/v1/user`, {
      headers: { authorization, apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? key },
      signal: AbortSignal.timeout(5000),
    });
    if (!auth.ok) return reply(401, { error: 'AUTH' });
    const userId = (await auth.json()).id;
    if (typeof userId !== 'string' || !userId) return reply(401, { error: 'AUTH' });

    // Bound the streamed body even if Content-Length is missing or forged.
    const reader = req.body?.getReader();
    if (!reader) return reply(400, { error: 'INPUT' });
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 256) { await reader.cancel(); return reply(413, { error: 'INPUT' }); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const input = JSON.parse(new TextDecoder().decode(bytes));
    const pin = typeof input?.pin === 'string' ? input.pin : '';
    if (!/^\d{4}$/.test(pin)) return reply(400, { error: 'INPUT' });

    // Same per-IP limit as nickname-auth.
    const address = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(address));
    const bucket = Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
    const rate = await call('/rest/v1/rpc/nickname_auth_rate_limit', { method: 'POST', body: JSON.stringify({ p_bucket: bucket }) });
    if (!rate.ok) return reply(503, { error: 'UNAVAILABLE' });
    if (await rate.json() !== true) return reply(429, { error: 'RATE_LIMIT' });

    // 2. The nickname comes from the server-side account row of this session's user.
    const lookup = await call(`/rest/v1/nickname_accounts?user_id=eq.${encodeURIComponent(userId)}&select=nickname_key`);
    if (!lookup.ok) return reply(503, { error: 'UNAVAILABLE' });
    const rows = await lookup.json();
    const nickname = Array.isArray(rows) && rows.length === 1 ? rows[0].nickname_key : null;
    if (typeof nickname !== 'string') return reply(409, { error: 'NO_NICKNAME_ACCOUNT' });

    // 3. PIN re-entry. Failures count toward the existing 5-try lockout.
    const checked = await call('/rest/v1/rpc/authenticate_nickname', {
      method: 'POST', body: JSON.stringify({ p_nickname: nickname, p_pin: pin }),
    });
    if (!checked.ok) return reply(503, { error: 'UNAVAILABLE' });
    const result = await checked.json();
    if (result.status === 'locked') return reply(429, { error: 'LOCKED' });
    if (result.status !== 'ok' || result.user_id !== userId) return reply(401, { error: 'INVALID_CREDENTIALS' });

    // 4. Delete the Auth user; all academic rows and the nickname credential cascade.
    const removed = await call(`/auth/v1/admin/users/${encodeURIComponent(userId)}`, { method: 'DELETE' });
    if (!removed.ok) return reply(503, { error: 'UNAVAILABLE' });

    // 5. Remove the login-attempt row so the nickname leaves no trace and is reusable at once.
    //    Best effort: the account itself is already gone.
    try {
      await call(`/rest/v1/nickname_login_attempts?nickname_key=eq.${encodeURIComponent(nickname)}`, { method: 'DELETE' });
    } catch { /* No credentials in logs. */ }

    return reply(200, { deleted: true });
  } catch {
    return reply(503, { error: 'UNAVAILABLE' });
  }
});
