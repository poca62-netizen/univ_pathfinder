// 앱 도움말 지식 베이스 검색 (BM25, 외부 호출 없음).
// Edge Function(Deno)과 Node 테스트가 같은 파일을 쓴다.
// 한국어는 조사가 붙어 낱말이 자주 달라지므로(리포트는/리포트를) 한글 2글자 조각과 낱말을 함께 색인한다.

const HANGUL = /[가-힣]/;

// 질문에 흔히 붙지만 내용과 상관없는 낱말. 2글자 조각을 만들기 전에 지운다.
const STOP_WORDS = new Set([
  '이', '그', '저', '것', '거', '수', '좀', '뭐', '뭘', '왜', '어떻게', '어디', '어디서', '언제', '무엇',
  '앱', '앱에서', '이앱', '이앱에서', '여기', '여기서', '해야', '해야돼', '해야되', '해야하나요', '하나요',
  '되나요', '돼요', '되요', '있어', '있어요', '있나요', '없어', '없어요', '알려줘', '알려주세요', '해줘',
  '하면', '하려면', '싶어', '싶어요', '나요', '인가요', '뭐야', '뭐예요', '뭔가요', '건가요', '어떤',
  '처음', '먼저', '돼', '되', '해', '줘', '요', '나', '내가', '제가',
  '그건', '그거', '그게', '그럼', '그러면', '거기', '거기서', '이건', '이거', '해요', '하죠', '하나', '되죠',
]);

export function normalize(text) {
  return String(text ?? '')
    .toLowerCase()
    .replace(/[`*_#>|\[\](){}"'“”‘’.,!?;:~·•…\-–—/\\=+<>]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// 낱말 + 한글 2글자 조각. 영문·숫자 낱말은 그대로 쓴다.
export function tokenize(text, { dropStopWords = false } = {}) {
  const out = [];
  for (const word of normalize(text).split(' ')) {
    if (!word) continue;
    if (dropStopWords && STOP_WORDS.has(word)) continue;
    if (!HANGUL.test(word)) {
      if (word.length >= 2) out.push(word);
      continue;
    }
    out.push(`w:${word}`);
    const chars = [...word];
    if (chars.length === 1) out.push(word);
    for (let i = 0; i + 1 < chars.length; i++) out.push(chars[i] + chars[i + 1]);
  }
  return out;
}

const K1 = 1.2;
const B = 0.75;
const TITLE_REPEAT = 3; // 제목 낱말은 본문보다 세 배로 친다.

export function buildIndex(chunks) {
  const docs = chunks.map((c) => {
    const tokens = [
      ...Array(TITLE_REPEAT).fill(tokenize(c.title)).flat(),
      ...tokenize(c.text),
    ];
    const tf = new Map();
    for (const t of tokens) tf.set(t, (tf.get(t) ?? 0) + 1);
    return { chunk: c, tf, length: tokens.length };
  });
  const df = new Map();
  for (const d of docs) for (const t of d.tf.keys()) df.set(t, (df.get(t) ?? 0) + 1);
  const avgLength = docs.reduce((s, d) => s + d.length, 0) / Math.max(1, docs.length);
  return { docs, df, avgLength, n: docs.length };
}

export function search(index, query, k = 5) {
  const terms = [...new Set(tokenize(query, { dropStopWords: true }))];
  if (terms.length === 0) return [];
  const scored = [];
  for (const d of index.docs) {
    let score = 0;
    for (const t of terms) {
      const f = d.tf.get(t);
      if (!f) continue;
      const df = index.df.get(t);
      const idf = Math.log(1 + (index.n - df + 0.5) / (df + 0.5));
      score += idf * (f * (K1 + 1)) / (f + K1 * (1 - B + B * d.length / index.avgLength));
    }
    if (score > 0) scored.push({ chunk: d.chunk, score: score * (d.chunk.weight ?? 1) });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, k);
}

// 무료 등급의 분당 토큰 한도에 맞춰 보낼 조각의 총 글자 수를 제한한다.
// 가장 관련 높은 조각 점수의 minRatio 미만인 조각은 관련이 약해 보내지 않는다.
export function selectContext(results, maxChars = 2500, minRatio = 0.4) {
  const picked = [];
  let used = 0;
  const floor = (results[0]?.score ?? 0) * minRatio;
  for (const r of results) {
    if (r.score < floor) continue;
    const size = r.chunk.title.length + r.chunk.text.length;
    if (picked.length > 0 && used + size > maxChars) continue;
    picked.push(r.chunk);
    used += size;
  }
  return picked;
}
