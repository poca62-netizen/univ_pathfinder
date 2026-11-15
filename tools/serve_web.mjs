import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const web = fileURLToPath(new URL('../build/web/', import.meta.url));
const types = {'.html':'text/html; charset=utf-8','.js':'text/javascript',
  '.mjs':'text/javascript','.wasm':'application/wasm','.json':'application/json',
  '.png':'image/png','.jpg':'image/jpeg','.pdf':'application/pdf',
  '.ttf':'font/ttf','.otf':'font/otf'};
createServer(async (req,res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const target = path.resolve(web, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!target.startsWith(path.resolve(web) + path.sep)) { res.writeHead(403); res.end(); return; }
    const bytes = await readFile(target);
    res.writeHead(200, {'Content-Type':types[path.extname(target)] ?? 'application/octet-stream', 'Cache-Control':'no-store'});
    res.end(bytes);
  } catch { res.writeHead(404); res.end(); }
}).listen(53789, '127.0.0.1', () => console.log('Web app: http://localhost:53789/'));
