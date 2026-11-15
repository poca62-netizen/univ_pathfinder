import { cp, mkdir, readdir, copyFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const modules = path.join(root, 'node_modules');
const dest = path.resolve(root, '../../web/vendor/ocr');
await mkdir(dest, { recursive: true });
for (const name of ['pdf.mjs', 'pdf.worker.mjs']) {
  await mkdir(path.join(dest, 'pdfjs'), { recursive: true });
  await copyFile(path.join(modules, 'pdfjs-dist/build', name), path.join(dest, 'pdfjs', name));
}
for (const name of ['cmaps', 'standard_fonts', 'wasm']) {
  await cp(path.join(modules, 'pdfjs-dist', name), path.join(dest, 'pdfjs', name), { recursive: true });
}
await copyFile(path.join(modules, 'pdfjs-dist/LICENSE'), path.join(dest, 'pdfjs/LICENSE'));
await mkdir(path.join(dest, 'tesseract'), { recursive: true });
for (const name of ['tesseract.min.js', 'worker.min.js']) {
  await copyFile(path.join(modules, 'tesseract.js/dist', name), path.join(dest, 'tesseract', name));
}
await copyFile(path.join(modules, 'tesseract.js/LICENSE.md'), path.join(dest, 'tesseract/LICENSE'));
await mkdir(path.join(dest, 'core'), { recursive: true });
for (const name of await readdir(path.join(modules, 'tesseract.js-core'))) {
  if (name.endsWith('.wasm') || name.endsWith('.wasm.js') || name === 'LICENSE') {
    await copyFile(path.join(modules, 'tesseract.js-core', name), path.join(dest, 'core', name));
  }
}
await mkdir(path.join(dest, 'lang'), { recursive: true });
for (const lang of ['kor', 'eng']) {
  await copyFile(path.join(modules, `@tesseract.js-data/${lang}/4.0.0_best_int/${lang}.traineddata.gz`), path.join(dest, 'lang', `${lang}.traineddata.gz`));
  await copyFile(path.join(modules, `@tesseract.js-data/${lang}/package.json`), path.join(dest, 'lang', `${lang}-package.json`));
  await copyFile(path.join(modules, `@tesseract.js-data/${lang}/README.md`), path.join(dest, 'lang', `${lang}-README.md`));
}
await writeFile(path.join(dest, 'README.txt'), 'Local browser OCR assets. Reproduce with npm ci --ignore-scripts && npm run vendor in tools/ocr. Versions are pinned in package-lock.json. PDF.js and Tesseract.js are Apache-2.0; see the included LICENSE files. Language npm packages declare MIT; package metadata and README files are retained in lang/. Source: https://github.com/naptha/tessdata ; upstream models: https://github.com/tesseract-ocr/tessdata . No student files are sent to npm or a CDN.\n');
console.log('Copied pinned OCR runtime, workers and Korean/English models into web/vendor/ocr.');
