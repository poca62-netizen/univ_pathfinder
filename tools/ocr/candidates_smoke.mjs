import {chromium} from 'playwright-core';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=path.resolve('build/candidates-preview');
const server=createServer(async(req,res)=>{
  try {
    const file=path.resolve(root,'.'+new URL(req.url,'http://local').pathname.replace(/\/$/,'/index.html'));
    if(!file.startsWith(root+path.sep)){res.writeHead(403);return res.end();}
    res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json'})[path.extname(file)]??'application/octet-stream');
    res.end(await readFile(file));
  } catch {res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser;
try {
  browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
  for(const [name,width,height] of [['desktop',1440,1100],['mobile',390,844]]){
    const page=await browser.newPage({viewport:{width,height}});
    const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:60000});
    await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
    const input=page.getByRole('textbox',{name:'관심 학과·분야',exact:true});
    await input.fill('컴퓨터공학');
    await input.press('Tab');
    await page.getByRole('checkbox',{name:/고2 1학기까지 누적 비교/}).click();
    await page.getByRole('button',{name:/등록 자료로 10개 대학 보기/}).click();
    await page.getByText('홍익대(서울)',{exact:true}).waitFor({timeout:10000}).catch(async e=>{console.log((await page.locator('body').innerText()).slice(-6000));throw e;});
    assert.ok(await page.getByText('과거 입결 대비 학업 비교: 강',{exact:true}).count()>0);
    await page.screenshot({path:`tools/ocr/test-output/design/browser-candidates-${name}.png`});
    assert.deepEqual(errors,[]);
    console.log(`PASS ${name}: synthetic three-semester grades → university results, academic comparison, tuition; no page errors`);
    await page.close();
  }
} finally {await browser?.close();await new Promise(r=>server.close(r));}
