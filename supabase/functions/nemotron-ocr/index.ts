// No document, credential, or upstream response logging.
Deno.serve(async (req: Request) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Cache-Control': 'no-store',
  };
  const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), {
    status, headers: { ...cors, 'Content-Type': 'application/json' },
  });
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  if (req.method !== 'POST') return reply(405, { error: 'METHOD' });
  const authorization = req.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) return reply(401, { error: 'AUTH' });
  try {
    const auth = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`, {
      headers: {
        authorization,
        apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      },
      signal: AbortSignal.timeout(10000),
    });
    if (!auth.ok || !(await auth.json()).id) return reply(401, { error: 'AUTH' });
    const key = Deno.env.get('NVIDIA_API_KEY');
    if (!key) return reply(503, { error: 'NOT_CONFIGURED' });
    const mime = req.headers.get('content-type')?.split(';')[0];
    if (mime !== 'image/jpeg' && mime !== 'image/png') return reply(415, { error: 'IMAGE_ONLY' });
    const chunks: Uint8Array[] = [];
    let size = 0;
    const reader = req.body?.getReader();
    if (!reader) return reply(400, { error: 'EMPTY' });
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 5 * 1024 * 1024) {
        await reader.cancel();
        return reply(413, { error: 'SIZE' });
      }
      chunks.push(value);
    }
    if (!size) return reply(400, { error: 'EMPTY' });
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const jpeg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
    const png = [137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => bytes[i] === v);
    if ((mime === 'image/jpeg' && !jpeg) || (mime === 'image/png' && !png)) return reply(415, { error: 'FORMAT' });
    let binary = '';
    for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    const upstream = await fetch('https://ai.api.nvidia.com/v1/cv/nvidia/nemotron-ocr-v2', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ input: [{ type: 'image_url', url: `data:${mime};base64,${btoa(binary)}` }], merge_levels: ['word'] }),
      signal: AbortSignal.timeout(60000),
    });
    if (!upstream.ok) return reply(upstream.status === 429 ? 429 : 502, { error: 'PROVIDER' });
    const result = await upstream.json();
    if (!Array.isArray(result.data)) return reply(502, { error: 'RESPONSE' });
    return reply(200, { data: result.data });
  } catch {
    return reply(502, { error: 'UNAVAILABLE' });
  }
});
