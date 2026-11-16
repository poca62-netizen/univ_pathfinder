// 앱 도움말 챗봇 지식 베이스 생성.
// 설계·개발 문서를 제목 단위 조각으로 나눠 supabase/functions/app-help/help_kb.json 에 쓴다.
// 실행: node tools/build_help_kb.mjs   (외부 호출 없음)
//
// 넣지 않는 것: 코드 블록(실행 명령), 비밀키·환경변수·배포 명령이 나오는 줄, 개발자용 절,
// `성적표/` 폴더(실제 학생 개인정보). 사용자(학생·학부모·선생님·학원 관계자)에게 필요한 설명만 남긴다.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const OUTPUT = 'supabase/functions/app-help/help_kb.json';
export const MAX_CHUNK = 900;
const MIN_CHUNK = 40;

// weight: 검색 점수 배율. 사용 안내서를 먼저, 개발 기록은 뒤로.
export const SOURCES = [
  { path: 'docs/APP_GUIDE.md', label: '앱 사용 안내', weight: 1.5 },
  {
    path: 'README.md', label: 'README', weight: 1.0,
    skip: [/^앱 실행$/, /^코드 검증$/, /^개발 자료$/, /^Getting Started$/, /^버전 관리$/, /^NVIDIA 이미지 OCR 연결/],
  },
  { path: 'PRD.md', label: '제품 요구사항(PRD)', weight: 1.0, skip: [/^9\. 기술 스택$/] },
  { path: 'docs/ADMISSION_LIKELIHOOD_RESEARCH.md', label: '합격 가능성 비교 연구', weight: 0.9 },
  { path: 'docs/CSAT_MINIMUM_COMPARISON.md', label: '수능 최저 비교', weight: 0.9 },
  { path: 'docs/UNIVERSITY_CANDIDATES_2028.md', label: '2028 대학 후보', weight: 0.9 },
  { path: 'docs/KAKAO_MAP.md', label: '지도·통학', weight: 0.9 },
  { path: 'docs/LOCAL_OCR_IMPORT.md', label: '파일 인식', weight: 0.9 },
  { path: 'docs/NVIDIA_OCR.md', label: '이미지 OCR', weight: 0.9 },
  { path: 'docs/NICKNAME_AUTH.md', label: '닉네임 로그인', weight: 0.9 },
  { path: 'docs/SCHOOL_RECORD_CONSULTING_PLAN.md', label: '생기부 상담 계획', weight: 0.8 },
  { path: 'docs/ADMISSION_SOURCE_REVIEW_2028.md', label: '2028 전형 원문 대조', weight: 0.8 },
  { path: 'docs/AI_AND_DATA_PLAN.md', label: 'AI·자료 계획', weight: 0.8 },
  { path: 'docs/UI_DESIGN.md', label: '화면 설계', weight: 0.8 },
  { path: 'docs/NEXT_STEPS.md', label: '다음 개발 계획', weight: 0.8 },
  { path: 'DEVELOPMENT_LOG.md', label: '개발 기록', weight: 0.6 },
];

// 이런 줄은 지식 베이스에 넣지 않는다.
const SENSITIVE_LINE = [
  /_(API_)?KEY\b/i, /SECRET/i, /TOKEN\b/i, /service[_ ]role/i, /\.env\b/i, /\.env\./i,
  /secrets\s+set/i, /functions\s+(deploy|serve)/i, /project[-_ ]ref/i, /PROJECT_REF/,
  /\bgsk_/, /\bnvapi-/, /supabase\.co\b/i, /성적표\//, /rls_verification_test/, /live_[a-z_]+\.mjs/,
  /--dart-define/, /^\s*(?:flutter|dart|node|npm|npx|supabase|git)\s/,
];

export function sanitize(markdown) {
  const out = [];
  let inFence = false;
  for (const line of markdown.split(/\r?\n/)) {
    if (/^\s*(```|~~~)/.test(line)) { inFence = !inFence; continue; }
    if (inFence) continue;
    if (SENSITIVE_LINE.some((re) => re.test(line))) continue;
    out.push(line);
  }
  return out.join('\n');
}

// 링크는 글자만, 강조·코드 기호는 지운다. 표 구분선은 버린다.
function plain(text) {
  return text
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/\*\*|__|`/g, '')
    .split('\n')
    .filter((l) => !/^\s*\|?\s*:?-{3,}/.test(l))
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function splitLong(text, max) {
  if (text.length <= max) return [text];
  const parts = [];
  let cur = '';
  const push = () => { if (cur.trim()) parts.push(cur.trim()); cur = ''; };
  for (const para of text.split(/\n(?=\s*(?:[-*]|\d+\.|\|)?\s*\S)/)) {
    const pieces = para.length > max ? para.match(new RegExp(`[^]{1,${max}}(?=\\s|$)|[^]{1,${max}}`, 'g')) : [para];
    for (const p of pieces) {
      if (cur && cur.length + p.length + 1 > max) push();
      cur += (cur ? '\n' : '') + p;
    }
  }
  push();
  return parts;
}

export function chunkMarkdown(markdown, source) {
  const chunks = [];
  const stack = []; // 제목 경로
  let body = [];
  let skipping = false;
  const flush = () => {
    if (!skipping) {
      const text = plain(body.join('\n'));
      const title = stack.filter(Boolean).join(' > ') || source.label;
      for (const piece of splitLong(text, MAX_CHUNK)) {
        if (piece.length >= MIN_CHUNK) chunks.push({ title, text: piece });
      }
    }
    body = [];
  };
  for (const line of sanitize(markdown).split('\n')) {
    const h = /^(#{1,4})\s+(.*)$/.exec(line);
    if (h) {
      flush();
      const level = h[1].length;
      const name = plain(h[2]);
      stack.length = level - 1;
      stack[level - 1] = name;
      // 건너뛸 절은 그 아래 하위 절까지 함께 건너뛴다.
      skipping = stack.some((s) => s && (source.skip ?? []).some((re) => re.test(s)));
      continue;
    }
    body.push(line);
  }
  flush();
  return chunks;
}

export function buildKb(root = ROOT) {
  const chunks = [];
  for (const source of SOURCES) {
    const md = readFileSync(join(root, source.path), 'utf8');
    chunkMarkdown(md, source).forEach((c, i) => {
      chunks.push({
        id: `${source.path}#${i + 1}`,
        source: source.label,
        path: source.path,
        title: c.title,
        text: c.text,
        weight: source.weight,
      });
    });
  }
  return { note: '자동 생성 파일. 고치지 말고 node tools/build_help_kb.mjs 로 다시 만든다.', chunks };
}

export function serialize(kb) {
  return JSON.stringify(kb, null, 1) + '\n';
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const kb = buildKb();
  writeFileSync(join(ROOT, OUTPUT), serialize(kb));
  const chars = kb.chunks.reduce((s, c) => s + c.text.length, 0);
  console.log(`조각 ${kb.chunks.length}개, 본문 ${chars.toLocaleString()}자 → ${OUTPUT}`);
}
