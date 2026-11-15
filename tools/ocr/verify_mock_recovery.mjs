// Cached-photo verification through the production browser bridge. No uploads.
import {chromium} from 'playwright-core';
import {createServer} from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const web=path.resolve('web');
const server=createServer(async(req,res)=>{try{const route=new URL(req.url,'http://local').pathname;if(route==='/'){res.setHeader('Content-Type','text/html');return res.end('<script type="module" src="/grade_ocr.js"></script>');}const file=path.resolve(web,'.'+route);if(!file.startsWith(web+path.sep)){res.writeHead(403);return res.end();}res.setHeader('Content-Type',({'.js':'text/javascript','.wasm':'application/wasm'})[path.extname(file)]??'application/octet-stream');res.end(await fs.readFile(file));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});const page=await browser.newPage();const base=`http://127.0.0.1:${server.address().port}`;const external=[];
 await page.route('**/*',r=>{if(r.request().url().startsWith(base))return r.continue();external.push(r.request().url());return r.abort();});
 await page.goto(base);await page.waitForFunction(()=>typeof univRecoverMockGrades==='function');
 const bytes=[...await fs.readFile('성적표/M2-9.jpg')],response=await fs.readFile('tools/ocr/test-output/private-mock-response.json','utf8');
 const result=await page.evaluate(async({bytes,response})=>{globalThis.univMockGradeDiagnostics=d=>{globalThis.diags??=[];globalThis.diags.push(d);};const r=JSON.parse(await univRecoverMockGrades(Uint8Array.from(bytes),'image/jpeg',response,()=>{}));r.diagnostics=globalThis.diags;return r;},{bytes,response});
 await fs.writeFile('tools/ocr/test-output/private-mock-recovered.json',JSON.stringify(result));
 const expected=JSON.parse((await fs.readFile('tools/ocr/test-output/private-mock-expected.json','utf8')).replace(/^\uFEFF/,''));
 assert.deepEqual(result.attempted.sort(),['영어','한국사'].sort());
 assert.equal(result.recovered.length,2);
 for(const row of result.recovered)assert.equal(row.grade,expected.find(e=>e.label===row.subject).grade);
 assert.equal(external.length,0);
 console.log(JSON.stringify({success:true,recovered:result.recovered.length,externalRequests:external.length,confidence:result.recovered.map(r=>r.confidence)}));
}finally{await browser?.close();await new Promise(r=>server.close(r));}
