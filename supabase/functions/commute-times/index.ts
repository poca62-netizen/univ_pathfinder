const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
};

type Point = { x: number; y: number };

function isPoint(value: unknown): value is Point {
  if (!value || typeof value !== 'object') return false;
  const { x, y } = value as Point;
  return Number.isFinite(x) && Math.abs(x) <= 180 && Number.isFinite(y) && Math.abs(y) <= 90;
}

Deno.serve(async (req: Request) => {
  const reply = (status: number, body: unknown) => Response.json(body, { status, headers });
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return reply(405, { error: 'METHOD' });
  const authorization = req.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ')) return reply(401, { error: 'AUTH' });
  try {
    const auth = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`, {
      headers: { authorization, apikey: Deno.env.get('SUPABASE_ANON_KEY') ?? '' },
      signal: AbortSignal.timeout(5000),
    });
    if (!auth.ok || !(await auth.json()).id) return reply(401, { error: 'AUTH' });
    const key = Deno.env.get('KAKAO_REST_API_KEY');
    if (!key) return reply(503, { error: 'NOT_CONFIGURED' });
    const body = await req.json().catch(() => null);
    const origin = body?.origin;
    const destinations = body?.destinations;
    if (!isPoint(origin) || !Array.isArray(destinations) || destinations.length < 1 ||
        destinations.length > 20 || !destinations.every(isPoint)) {
      return reply(400, { error: 'INVALID_POINTS' });
    }
    const signal = AbortSignal.timeout(24000);
    const routes = [];
    for (let i = 0; i < destinations.length; i += 3) {
      const batch = await Promise.all(destinations.slice(i, i + 3).map(async (destination: Point) => {
        if (signal.aborted) return null;
        const query = new URLSearchParams({
          origin: `${origin.x},${origin.y}`,
          destination: `${destination.x},${destination.y}`,
          priority: 'TIME',
          summary: 'true',
        });
        try {
          const response = await fetch(`https://apis-navi.kakaomobility.com/v1/directions?${query}`, {
            headers: { Authorization: `KakaoAK ${key}` }, signal,
          });
          if (!response.ok) return null;
          const route = (await response.json()).routes?.[0];
          const { distance, duration } = route?.summary ?? {};
          if (route?.result_code !== 0 || !Number.isInteger(distance) || distance < 0 ||
              !Number.isInteger(duration) || duration < 0) return null;
          return { distance, duration };
        } catch {
          return null;
        }
      }));
      routes.push(...batch);
    }
    return reply(200, { routes });
  } catch {
    return reply(502, { error: 'UNAVAILABLE' });
  }
});
