import { findMockGradeTargets, acceptMockGradeVotes } from './mock_grade_recovery.js?v=20261104-1';
// Local OCR and image preparation. This module never uploads document bytes.
globalThis.univCropOcrTable = async (bytes, mime, top, bottom) => {
  const image = await createImageBitmap(new Blob([bytes], {type:mime}));
  try {
    const sy = Math.max(0, Math.floor(top * image.height));
    const height = Math.min(image.height-sy,Math.ceil((bottom-top)*image.height));
    if (height < 50) throw new Error('INVALID_CROP');
    const canvas=document.createElement('canvas');
    const scale=Math.min(1.5,3200/image.width);
    canvas.width=Math.round(image.width*scale);canvas.height=Math.round(height*scale);
    canvas.getContext('2d').drawImage(image,0,sy,image.width,height,0,0,canvas.width,canvas.height);
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',.96));
    return new Uint8Array(await blob.arrayBuffer());
  } finally { image.close(); }
};
const assets = new URL('vendor/ocr/', import.meta.url);
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const MAX_PDF_BYTES = 20 * 1024 * 1024;
const MAX_PAGES = 20;
const MAX_PIXELS = 12_000_000;
let active = null;
let pdfModule;
let tesseractLoader;

function fail(code) { throw new Error(code); }
function check(job) { if (job.cancelled) fail('CANCELLED'); }
function progress(job, message) {
  check(job);
  if (job.onProgress) job.onProgress(message);
}

function loadTesseract() {
  if (globalThis.Tesseract) return Promise.resolve(globalThis.Tesseract);
  if (!tesseractLoader) {
    tesseractLoader = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = new URL('tesseract/tesseract.min.js', assets).href;
      script.onload = () => resolve(globalThis.Tesseract);
      script.onerror = () => { tesseractLoader = null; reject(new Error('ASSETS_UNAVAILABLE')); };
      document.head.append(script);
    });
  }
  return tesseractLoader;
}

export function makeLines(words) {
  const rows = [];
  for (const word of [...words].sort((a, b) => a.y - b.y || a.x - b.x)) {
    const mid = word.y + word.h / 2;
    let row = rows.find((r) => Math.abs(r.mid - mid) <= Math.max(2, Math.min(r.height, word.h) * 0.55));
    if (!row) { row = { mid, height: word.h, words: [] }; rows.push(row); }
    row.words.push(word);
  }
  return rows.sort((a, b) => a.mid - b.mid).map((r) => {
    const words = r.words.sort((a, b) => a.x - b.x);
    return { text: words.map((w) => w.text).join(' '), words };
  });
}

async function workerFor(job, numeric = false) {
  const key = numeric ? 'numericWorker' : 'worker';
  if (!job[key]) {
    progress(job, '한국어·영어 인식 엔진 준비 중');
    const Tesseract = await loadTesseract();
    check(job);
    const worker = await Tesseract.createWorker(numeric ? 'eng' : 'kor', 1, {
      workerPath: new URL('tesseract/worker.min.js', assets).href,
      corePath: new URL('core/', assets).href,
      langPath: new URL('lang/', assets).href,
      workerBlobURL: false,
      cacheMethod: 'none',
      logger: (m) => {
        if (!job.cancelled && m.status === 'recognizing text') {
          job.onProgress?.(`글자 인식 중 ${Math.round(m.progress * 100)}%`);
        }
      },
    });
    job[key] = worker;
    check(job);
    await worker.setParameters({ preserve_interword_spaces: '1', tessedit_pageseg_mode: '6' });
    if (numeric) await worker.setParameters({ tessedit_char_whitelist: '0123456789.()-' });
  }
  return job[key];
}

async function recognizePass(canvas, job, segmentation) {
  const worker = await workerFor(job);
  await worker.setParameters({ tessedit_pageseg_mode: String(segmentation) });
  const { data } = await worker.recognize(canvas, {}, { blocks: true, text: true });
  check(job);
  const words = [];
  for (const block of data.blocks ?? []) {
    for (const paragraph of block.paragraphs ?? []) {
      for (const line of paragraph.lines ?? []) {
        for (const word of line.words ?? []) {
          if (!word.text?.trim()) continue;
          const b = word.bbox;
          words.push({ text: word.text, x: b.x0, y: b.y0, w: b.x1 - b.x0, h: b.y1 - b.y0, confidence: word.confidence });
        }
      }
    }
  }
  const lines = makeLines(words);
  const text = lines.map((line) => line.text).join('\n');
  const quality = scoreRecognition(text, words);
  return { text, lines, method: 'ocr', quality };
}

export function scoreRecognition(text, words) {
  const compact = text.replace(/\s/g, '');
  const headers = ['과목', '학점', '단위', '원점수', '과목평균', '성취도', '석차등급'].filter((h) => compact.includes(h));
  const confidence = words.length ? words.reduce((s, w) => s + (w.confidence ?? 0), 0) / words.length : 0;
  const hangul = (compact.match(/[가-힣]/g) ?? []).length;
  const digits = (compact.match(/\d+(?:\.\d+)?/g) ?? []).length;
  return { headers: headers.length, confidence: Math.round(confidence),
    tableFound: compact.includes('과목') && headers.length >= 3,
    score: headers.length * 150 + Math.min(hangul, 120) + Math.min(digits, 60) * 2 + confidence };
}

function imageVariant(source, rotation = 0) {
  const canvas = document.createElement('canvas');
  const quarter = rotation === 90 || rotation === 270;
  canvas.width = quarter ? source.height : source.width;
  canvas.height = quarter ? source.width : source.height;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.translate(canvas.width / 2, canvas.height / 2);
  ctx.rotate(rotation * Math.PI / 180);
  ctx.drawImage(source, -source.width / 2, -source.height / 2);
  return canvas;
}

function thresholdImage(canvas) {
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const histogram = new Uint32Array(256);
  const values = new Uint8Array(canvas.width * canvas.height);
  for (let i = 0; i < values.length; i++) {
    values[i] = Math.round(image.data[i * 4] * 0.299 + image.data[i * 4 + 1] * 0.587 + image.data[i * 4 + 2] * 0.114);
    histogram[values[i]]++;
  }
  let sum = 0, background = 0, weighted = 0, maximum = -1, threshold = 160;
  for (let i = 0; i < 256; i++) sum += i * histogram[i];
  for (let i = 0; i < 256; i++) {
    background += histogram[i];
    if (!background) continue;
    const foreground = values.length - background;
    if (!foreground) break;
    weighted += i * histogram[i];
    const difference = weighted / background - (sum - weighted) / foreground;
    const variance = background * foreground * difference * difference;
    if (variance > maximum) { maximum = variance; threshold = i; }
  }
  threshold = Math.max(100, Math.min(210, threshold));
  for (let i = 0; i < values.length; i++) {
    const value = values[i] <= threshold ? 0 : 255;
    image.data[i * 4] = image.data[i * 4 + 1] = image.data[i * 4 + 2] = value;
  }
  ctx.putImageData(image, 0, 0);
}

// Photographed reports often have uneven grey paper and white-on-grey headers.
// Normalize the header polarity first, then threshold against a local mean.
function normalizePhoto(canvas) {
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const { width, height, data } = image;
  const grey = new Uint8Array(width * height);
  for (let i = 0; i < grey.length; i++) grey[i] = Math.round(data[i * 4] * .299 + data[i * 4 + 1] * .587 + data[i * 4 + 2] * .114);
  const left = Math.floor(width * .04), right = Math.ceil(width * .96);
  let bandStart = -1;
  const invertBand = (start, end) => {
    if (end - start < 8) return;
    let x0 = right, x1 = left;
    for (let x = left; x < right; x++) {
      let sum = 0;
      for (let y = start; y < end; y++) sum += grey[y * width + x];
      if (sum / (end - start) < 155) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); }
    }
    for (let y = start; y < end; y++) for (let x = x0; x <= x1; x++) grey[y * width + x] = 255 - grey[y * width + x];
  };
  for (let y = 0; y <= height; y++) {
    let dark = 0;
    if (y < height) for (let x = left; x < right; x++) if (grey[y * width + x] < 140) dark++;
    if (y < height && dark / (right - left) > .52) { if (bandStart < 0) bandStart = y; }
    else if (bandStart >= 0) { invertBand(bandStart, y); bandStart = -1; }
  }
  const stride = width + 1;
  const integral = new Uint32Array(stride * (height + 1));
  for (let y = 0; y < height; y++) {
    let sum = 0;
    for (let x = 0; x < width; x++) {
      sum += grey[y * width + x];
      integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + sum;
    }
  }
  const radius = Math.max(15, Math.round(Math.min(width, height) * .02));
  for (let y = 0; y < height; y++) {
    const top = Math.max(0, y - radius), bottom = Math.min(height, y + radius + 1);
    for (let x = 0; x < width; x++) {
      const l = Math.max(0, x - radius), r = Math.min(width, x + radius + 1);
      const sum = integral[bottom * stride + r] - integral[top * stride + r] - integral[bottom * stride + l] + integral[top * stride + l];
      const threshold = sum / ((bottom - top) * (r - l)) - 12;
      const value = grey[y * width + x] < threshold ? 0 : 255;
      const i = (y * width + x) * 4;
      data[i] = data[i + 1] = data[i + 2] = value;
    }
  }
  ctx.putImageData(image, 0, 0);
}

async function ocrCanvas(source, job) {
  check(job);
  let best;
  if (job.enhanced) {
    const grid = await recognizeGrids(source, job);
    if (grid) best = grid;
  }
  const attempts = [
    { rotation: 0, psm: 6, rules: true },
    { rotation: 0, psm: 3, rules: false },
    ...(job.enhanced ? [
      { rotation: 0, psm: 6, rules: true, photo: true },
      { rotation: 0, psm: 3, rules: true, photo: true },
      { rotation: 0, psm: 6, rules: true, threshold: true },
      { rotation: 90, psm: 6, rules: true },
      { rotation: 270, psm: 6, rules: true },
      { rotation: 180, psm: 6, rules: true },
    ] : []),
  ];
  for (let i = 0; i < attempts.length; i++) {
    if (best?.quality.tableFound && best.quality.headers >= 5 && best.quality.confidence >= 70) break;
    const option = attempts[i];
    progress(job, `인식 방식 ${i + 1}/${attempts.length} 확인 중${option.rotation ? ` · ${option.rotation}° 회전` : ''}`);
    const canvas = imageVariant(source, option.rotation);
    try {
      if (option.threshold) thresholdImage(canvas);
      if (option.photo) normalizePhoto(canvas);
      if (option.rules) removeTableRules(canvas);
      const result = await recognizePass(canvas, job, option.psm);
      result.rotation = option.rotation;
      if (!best || result.quality.score > best.quality.score) best = result;
      if (best.quality.tableFound && best.quality.headers >= 5 && best.quality.confidence >= 70) break;
    } finally { canvas.width = 0; canvas.height = 0; }
  }
  return best;
}

export function detectGrids(source) {
  const { width, height } = source;
  const pixels = source.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, width, height).data;
  const grey = (x, y) => {
    const p = (Math.max(0, Math.min(height - 1, y)) * width + Math.max(0, Math.min(width - 1, x))) * 4;
    return pixels[p] * .299 + pixels[p + 1] * .587 + pixels[p + 2] * .114;
  };
  const left = Math.floor(width * .04), right = Math.floor(width * .96);
  const bands = [];
  let start = -1;
  for (let y = 0; y <= height; y++) {
    let dark = 0;
    if (y < height) for (let x = left; x < right; x += 3) if (grey(x, y) < 145) dark++;
    const isBand = y < height && dark / Math.ceil((right - left) / 3) > .56;
    if (isBand && start < 0) start = y;
    else if (!isBand && start >= 0) {
      if (y - start >= 10) {
        const previous = bands.at(-1);
        if (previous && start - previous.end < 35) previous.end = y;
        else bands.push({ start, end: y });
      }
      start = -1;
    }
  }
  const groups = (values) => {
    const runs = [];
    for (const v of values) {
      const last = runs.at(-1);
      if (last && v - last.at(-1) <= 2) last.push(v); else runs.push([v]);
    }
    return runs.map((r) => Math.round((r[0] + r.at(-1)) / 2));
  };
  const tables = [];
  for (const band of bands.slice(0, 8)) {
    if (band.end - band.start > height * .12) continue;
    const mid = Math.round((band.start + band.end) / 2);
    let x0 = left, x1 = right;
    while (x0 < right && grey(x0, mid) > 145) x0++;
    while (x1 > left && grey(x1, mid) > 145) x1--;
    if (x1 - x0 < width * .5) continue;
    let bottom = band.end, missing = 0;
    for (let y = band.end + 2; y < Math.min(height, band.end + height * .4); y++) {
      let hit = false;
      for (let x = Math.max(0, x0 - 18); x <= Math.min(width - 1, x0 + 18); x++) if (grey(x, y) < 110) { hit = true; break; }
      if (hit) { bottom = y; missing = 0; } else if (++missing > 18) break;
    }
    if (bottom - band.end < 30) continue;
    const hits = [];
    const sampleEnd = Math.min(bottom - 4, band.end + 300);
    const samples = Math.max(1, Math.ceil((sampleEnd - band.end - 8) / 3));
    for (let x = x0 - 8; x <= x1 + 8; x++) {
      let count = 0;
      for (let y = band.end + 8; y < sampleEnd; y += 3) {
        let hit = false;
        for (let dx = -4; dx <= 4; dx++) if (grey(x + dx, y) < 110) { hit = true; break; }
        if (hit) count++;
      }
      if (count / samples > .7) hits.push(x);
    }
    const columns = groups(hits);
    if (columns.length < 4 || columns.length > 24) continue;
    const rowHits = [];
    for (let y = band.end; y <= bottom; y++) {
      let count = 0, total = 0;
      for (let x = columns[0] + 8; x < columns.at(-1) - 8; x += 4) {
        total++;
        for (let dy = -4; dy <= 4; dy++) if (grey(x, y + dy) < 110) { count++; break; }
      }
      if (count / total > .46) rowHits.push(y);
    }
    const rows = [];
    for (const y of groups(rowHits)) {
      if (rows.length && y - rows.at(-1) < 22) rows[rows.length - 1] = Math.round((rows.at(-1) + y) / 2);
      else rows.push(y);
    }
    if (!rows.length || rows[0] - band.end > 20) rows.unshift(band.end);
    if (bottom - rows.at(-1) > 20) rows.push(bottom);
    if (rows.length >= 2) tables.push({ headerTop: band.start, headerBottom: band.end, columns, rows });
  }
  return tables;
}

async function recognizeGrids(source, job) {
  const tables = detectGrids(source);
  if (!tables.length) return null;
  const worker = await workerFor(job);
  const lines = [];
  // Keep only academic-period context from the region above the first table.
  // Names and unrelated identity lines are not included in the table result.
  const context = document.createElement('canvas');
  context.width = source.width; context.height = tables[0].headerTop;
  context.getContext('2d').drawImage(source, 0, 0);
  try {
    normalizePhoto(context);
    const result = await recognizePass(context, job, 6);
    lines.push(...result.lines.filter((line) => /학\s*년|학\s*기/.test(line.text)));
  } finally { context.width = 0; context.height = 0; }
  let cellsRead = 0;
  async function cell(x0, y0, x1, y1, invert, numeric = false) {
    if (++cellsRead > 240) return null;
    check(job);
    const w = x1 - x0 - 8, h = y1 - y0 - 8;
    if (w < 10 || h < 10) return null;
    const canvas = document.createElement('canvas');
    const scale = Math.min(2, 130 / h);
    canvas.width = Math.ceil(w * scale) + 20; canvas.height = Math.ceil(h * scale) + 20;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(source, x0 + 4, y0 + 4, w, h, 10, 10, w * scale, h * scale);
    const image = ctx.getImageData(10, 10, canvas.width - 20, canvas.height - 20);
    const histogram = new Uint32Array(256);
    for (let i = 0; i < image.data.length; i += 4) {
      let value = image.data[i] * .299 + image.data[i + 1] * .587 + image.data[i + 2] * .114;
      if (invert) value = 255 - value;
      image.data[i] = image.data[i + 1] = image.data[i + 2] = value;
      histogram[Math.round(value)]++;
    }
    const total = image.data.length / 4;
    const percentile = (fraction) => {
      let sum = 0;
      for (let value = 0; value < 256; value++) { sum += histogram[value]; if (sum >= total * fraction) return value; }
      return 255;
    };
    const low = percentile(.02), high = percentile(.90);
    if (high - low < 15) { canvas.width = 0; canvas.height = 0; return null; }
    for (let i = 0; i < image.data.length; i += 4) {
      const value = Math.max(0, Math.min(255, (image.data[i] - low) * 255 / (high - low)));
      image.data[i] = image.data[i + 1] = image.data[i + 2] = value;
    }
    ctx.putImageData(image, 10, 10);
    thresholdImage(canvas);
    removeTableRules(canvas);
    if (invert && typeof globalThis.univGradeOcrCellPreview === 'function') globalThis.univGradeOcrCellPreview(canvas.toDataURL('image/png'));
    try {
      const engine = numeric ? await workerFor(job, true) : worker;
      await engine.setParameters({ tessedit_pageseg_mode: numeric ? '7' : '6' });
      const { data } = await engine.recognize(canvas, {}, { text: true });
      const text = (data.text ?? '').replace(/\s+/g, ' ').trim();
      return text ? { text, x: x0 + 4, y: y0 + 4, w, h: y1 - y0 - 8, confidence: data.confidence } : null;
    } finally { canvas.width = 0; canvas.height = 0; }
  }
  for (const table of tables) {
    progress(job, '표 칸을 나누어 머리글·과목·점수 읽는 중');
    const headers = [];
    for (let c = 0; c < table.columns.length - 1; c++) {
      headers.push(await cell(table.columns[c], table.headerTop, table.columns[c + 1], table.headerBottom, true));
    }
    const compact = headers.map((h) => h?.text ?? '').join('').replace(/\s/g, '');
    if (typeof globalThis.univGradeOcrGridDiagnostics === 'function') {
      globalThis.univGradeOcrGridDiagnostics(headers.map((h) => h?.text ?? ''));
    }
    if (!compact.includes('과목') || !compact.includes('원점수')) continue;
    const useful = headers.map((h) => {
      const t = (h?.text ?? '').replace(/\s/g, '');
      return /과목|원점수|학점|단위|석차등급/.test(t) || (t.includes('성취도') && !t.includes('분포'));
    });
    lines.push({ text: headers.filter(Boolean).map((h) => h.text).join(' '), words: headers.filter(Boolean) });
    for (let r = 0; r < table.rows.length - 1; r++) {
      if (table.rows[r + 1] - table.rows[r] < 20) continue;
      const words = [];
      for (let c = 0; c < headers.length; c++) if (useful[c]) {
        const header = (headers[c]?.text ?? '').replace(/\s/g, '');
        const numeric = /원점수|평균|학점|단위|석차등급/.test(header);
        const word = await cell(table.columns[c], table.rows[r], table.columns[c + 1], table.rows[r + 1], false, numeric);
        if (word) words.push(word);
      }
      lines.push({ text: words.map((w) => w.text).join(' '), words });
    }
  }
  if (!lines.length) return null;
  const words = lines.flatMap((l) => l.words), text = lines.map((l) => l.text).join('\n');
  return { text, lines, quality: scoreRecognition(text, words), method: 'ocr', rotation: 0, grid: true };
}

// Long table rules can make OCR discard entire cells. Remove rules, not glyphs.
function removeTableRules(canvas) {
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const { data, width, height } = image;
  const mask = new Uint8Array(width * height);
  const dark = (x, y) => data[(y * width + x) * 4] < 180 && data[(y * width + x) * 4 + 1] < 180;
  for (let y = 0; y < height; y++) {
    let start = -1;
    for (let x = 0; x <= width; x++) {
      if (x < width && dark(x, y)) { if (start < 0) start = x; }
      else if (start >= 0) {
        if (x - start > Math.max(80, width * 0.12)) {
          for (let i = start; i < x; i++) mask[y * width + i] = 1;
        }
        start = -1;
      }
    }
  }
  for (let x = 0; x < width; x++) {
    let start = -1;
    for (let y = 0; y <= height; y++) {
      if (y < height && dark(x, y)) { if (start < 0) start = y; }
      else if (start >= 0) {
        if (y - start > Math.max(60, height * 0.06)) {
          for (let i = start; i < y; i++) mask[i * width + x] = 1;
        }
        start = -1;
      }
    }
  }
  for (let i = 0; i < mask.length; i++) {
    if (mask[i]) data[i * 4] = data[i * 4 + 1] = data[i * 4 + 2] = 255;
  }
  ctx.putImageData(image, 0, 0);
}

async function pdfPages(bytes, job, forceOcr) {
  pdfModule ??= await import(new URL('pdfjs/pdf.mjs', assets).href);
  check(job);
  pdfModule.GlobalWorkerOptions.workerSrc = new URL('pdfjs/pdf.worker.mjs', assets).href;
  const task = pdfModule.getDocument({
    data: bytes.slice(), isEvalSupported: false,
    cMapUrl: new URL('pdfjs/cmaps/', assets).href, cMapPacked: true,
    standardFontDataUrl: new URL('pdfjs/standard_fonts/', assets).href,
    wasmUrl: new URL('pdfjs/wasm/', assets).href,
  });
  job.pdfTask = task;
  task.onPassword = () => { job.password = true; void task.destroy(); };
  const doc = await task.promise;
  if (doc.numPages > MAX_PAGES) fail('TOO_MANY_PAGES');
  const pages = [];
  for (let p = 1; p <= doc.numPages; p++) {
    progress(job, `PDF ${p}/${doc.numPages}쪽 읽는 중`);
    const page = await doc.getPage(p);
    const viewport = page.getViewport({ scale: 1 });
    const content = await page.getTextContent();
    const words = [];
    for (const item of content.items) {
      if (!('str' in item) || !item.str.trim()) continue;
      const transform = pdfModule.Util.transform(viewport.transform, item.transform);
      const height = Math.max(1, Math.hypot(transform[2], transform[3]));
      const parts = [...item.str.matchAll(/\S+/g)];
      for (const part of parts) {
        words.push({ text: part[0], x: transform[4] + item.width * part.index / item.str.length,
          y: transform[5] - height, w: item.width * part[0].length / item.str.length, h: height });
      }
    }
    const lines = makeLines(words);
    const text = lines.map((l) => l.text).join('\n');
    if (!forceOcr && text.replace(/\s/g, '').length >= 30) {
      pages.push({ page: p, width: viewport.width, height: viewport.height, method: 'pdf-text', text, lines });
    } else {
      const scale = Math.min(2.5, Math.sqrt(MAX_PIXELS / (viewport.width * viewport.height)));
      const renderViewport = page.getViewport({ scale });
      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(renderViewport.width);
      canvas.height = Math.ceil(renderViewport.height);
      try {
        const render = page.render({ canvasContext: canvas.getContext('2d'), viewport: renderViewport });
        job.renderTask = render;
        await render.promise;
        check(job);
        pages.push({ page: p, width: canvas.width, height: canvas.height, ...await ocrCanvas(canvas, job) });
      } finally { canvas.width = 0; canvas.height = 0; job.renderTask = null; }
    }
    page.cleanup();
  }
  return pages;
}

function validSignature(bytes, mime) {
  if (mime === 'application/pdf') return new TextDecoder().decode(bytes.slice(0, 5)) === '%PDF-';
  if (mime === 'image/png') return [137, 80, 78, 71, 13, 10, 26, 10].every((v, i) => bytes[i] === v);
  return mime === 'image/jpeg' && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
}

globalThis.univGradeOcrCancel = () => {
  const job = active;
  if (!job) return;
  job.cancelled = true;
  job.renderTask?.cancel();
  if (job.worker) void job.worker.terminate();
  if (job.numericWorker) void job.numericWorker.terminate();
  if (job.pdfTask) void job.pdfTask.destroy();
};

globalThis.univGradeOcrExtract = async (bytes, mime, forceOcr, onProgress, enhanced = false) => {
  if (active) fail('BUSY');
  const maxBytes = mime === 'application/pdf' ? MAX_PDF_BYTES : MAX_IMAGE_BYTES;
  if (!bytes.length || bytes.length > maxBytes) fail('INVALID_SIZE');
  if (!validSignature(bytes, mime)) fail('INVALID_FILE');
  const job = { cancelled: false, onProgress, enhanced };
  active = job;
  try {
    let pages;
    if (mime === 'application/pdf') {
      pages = await pdfPages(bytes, job, forceOcr);
    } else {
      const bitmap = await createImageBitmap(new Blob([bytes], { type: mime }));
      const canvas = document.createElement('canvas');
      try {
        // Keep small table glyphs: the old fixed 1800px downscale lost detail.
        const shortSide = Math.min(bitmap.width, bitmap.height);
        const longSide = Math.max(bitmap.width, bitmap.height);
        const scale = Math.min(2.5, Math.max(1, 1800 / shortSide), 3600 / longSide,
          Math.sqrt(MAX_PIXELS / (bitmap.width * bitmap.height)));
        canvas.width = Math.max(1, Math.floor(bitmap.width * scale));
        canvas.height = Math.max(1, Math.floor(bitmap.height * scale));
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
        pages = [{ page: 1, ...await ocrCanvas(canvas, job) }];
      } finally { bitmap.close(); canvas.width = 0; canvas.height = 0; }
    }
    check(job);
    return JSON.stringify({ pages });
  } catch (error) {
    if (job.cancelled) fail('CANCELLED');
    if (job.password) fail('PASSWORD_PROTECTED');
    const known = ['TOO_MANY_PAGES', 'INVALID_FILE', 'ASSETS_UNAVAILABLE'];
    fail(known.includes(error.message) ? error.message : 'EXTRACTION_FAILED');
  } finally {
    if (job.worker) { try { await job.worker.terminate(); } catch { /* already stopped */ } }
    if (job.numericWorker) { try { await job.numericWorker.terminate(); } catch { /* already stopped */ } }
    if (job.pdfTask) { try { await job.pdfTask.destroy(); } catch { /* already stopped */ } }
    active = null;
  }
};

// Extra pass stays on the device and is only requested for mock-exam images.
globalThis.univRecoverMockGrades = async (bytes, mime, responseJson, onProgress) => {
  if(active) fail('BUSY');
  const targets=findMockGradeTargets(JSON.parse(responseJson));
  if(!targets.length)return JSON.stringify({recovered:[],attempted:[]});
  const job={cancelled:false,onProgress};active=job;let image;
  try{
    image=await createImageBitmap(new Blob([bytes],{type:mime}));
    const worker=await workerFor(job,true);
    await worker.setParameters({tessedit_pageseg_mode:'8',tessedit_char_whitelist:'123456789'});
    const recovered=[];
    for(const target of targets){
      progress(job,target.subject+' 등급 칸을 기기에서 다시 읽고 있습니다.');
      const votes=[];
      for(const centerOffset of [0,.15,-.15]) {
      for(const widthFactor of [.7,.9,1.1]){
        check(job);
        const half=target.halfWidth*widthFactor;
        const center=target.x+target.halfWidth*centerOffset;
        const left=center-half,right=center+half,top=target.y-target.halfHeight,bottom=target.y+target.halfHeight;
        if(left<0||top<0||right>1||bottom>1)continue;
        const canvas=document.createElement('canvas'),pad=20,scale=4;
        canvas.width=Math.round((right-left)*image.width*scale)+pad*2;
        canvas.height=Math.round((bottom-top)*image.height*scale)+pad*2;
        if(canvas.width*canvas.height>1000000)continue;
        const ctx=canvas.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,canvas.width,canvas.height);
        ctx.drawImage(image,left*image.width,top*image.height,(right-left)*image.width,(bottom-top)*image.height,pad,pad,canvas.width-pad*2,canvas.height-pad*2);
        const pixels=ctx.getImageData(0,0,canvas.width,canvas.height);
        for(let i=0;i<pixels.data.length;i+=4){const v=(pixels.data[i]+pixels.data[i+1]+pixels.data[i+2])/3<160?0:255;pixels.data[i]=pixels.data[i+1]=pixels.data[i+2]=v;}
        ctx.putImageData(pixels,0,0);
        const {data}=await worker.recognize(canvas);check(job);
        votes.push({text:data.text.trim(),confidence:data.confidence});canvas.width=0;canvas.height=0;
      }
      }
      globalThis.univMockGradeDiagnostics?.({subject:target.subject,target,votes});
      const accepted=acceptMockGradeVotes(votes);
      if(accepted)recovered.push({subject:target.subject,...accepted});
    }
    return JSON.stringify({recovered,attempted:targets.map(t=>t.subject)});
  }finally{
    image?.close();if(job.numericWorker){try{await job.numericWorker.terminate();}catch{}}
    active=null;
  }
};
