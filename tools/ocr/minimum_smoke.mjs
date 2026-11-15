import {chromium} from 'playwright-core';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=path.resolve('build/minimum-preview');
const server=createServer(async(req,res)=>{
  try {
    const file=path.resolve(root,'.'+new URL(req.url,'http://local').pathname.replace(/\/$/,'/index.html'));
    if(!file.startsWith(root+path.sep)){res.writeHead(403);return res.end();}
    res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json'})[path.extname(file)]??'application/octet-stream');
    res.end(await readFile(file));
  }catch{res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser;
try {
  browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
  for(const [name,width,height] of [['desktop',1440,1100],['mobile',390,844]]) {
    const context=await browser.newContext({viewport:{width,height}});
    const page=await context.newPage();
    const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error' && /overflowed|Exception|assertion/i.test(m.text()))errors.push(m.text());});
    async function reveal(locator){
      for(let i=0;i<35;i++){
        const box=await locator.boundingBox({timeout:500}).catch(()=>null);
        if(box && box.y>65 && box.y+box.height<height-20)return;
        await page.mouse.move(width/2,height/2);
        await page.mouse.wheel(0,box && box.y<65?-350:350);
        await page.waitForTimeout(120);
      }
      throw Error('Cannot reveal '+await page.locator('body').innerText());
    }
    async function clickLocator(l){await reveal(l);await l.click();await page.waitForTimeout(250);}
    async function clickText(text,exact=true){console.log(name+' click '+text);await clickLocator(page.getByText(text,{exact}).first());}
    async function enable(){
      await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:60000});
      await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
    }
    async function generate(){
      const input=page.getByRole('textbox',{name:'관심 학과·분야',exact:true});
      await input.click();
      await page.waitForFunction(()=>['INPUT','TEXTAREA'].includes(document.activeElement?.tagName));
      await page.keyboard.press('Control+A');
      await page.keyboard.insertText('컴퓨터공학');
      await page.keyboard.press('Tab');
      await page.getByRole('button',{name:/등록 자료로 10개 대학 보기/}).click();
      await page.getByText('가상검증대',{exact:true}).waitFor({timeout:10000}).catch(async e=>{console.log((await page.locator('body').innerText()).slice(-7000));throw e;});
      await clickText('전형 2개 · 지원조건');
      await clickText('학생부교과 · 일반전형',false);
    }
    await page.goto(`http://127.0.0.1:${server.address().port}`);await enable();await generate();
    await page.getByText('모의고사 대비 수능 최저: 미달 수준',{exact:true}).waitFor();
    await page.getByText('등급 합 3.0 개선 필요',{exact:true}).waitFor();
    await clickLocator(page.getByRole('button',{name:/수능 최저 비교할 모의고사/}));
    await page.getByRole('menuitem',{name:'2026년 2학년 6월 · 교육청',exact:true}).click();
    await page.getByText('모의고사 대비 수능 최저: 충족 수준',{exact:true}).waitFor({timeout:10000}).catch(async e=>{console.log((await page.locator('body').innerText()).slice(-6500));throw e;});
    const check=page.getByRole('checkbox',{name:'지원자격 · 확인 필요',exact:true});await reveal(check);await check.click();
    await page.getByRole('checkbox',{name:'지원자격 · 본인 확인',exact:true}).waitFor();
    assert.ok(await page.getByRole('checkbox',{name:'지원자격 · 본인 확인',exact:true}).isChecked());
    await clickText('학생부교과 · 학과별전형',false);
    await page.getByText('모의고사 대비 수능 최저: 원문 확인 필요',{exact:true}).waitFor();
    await clickLocator(page.getByRole('button',{name:/실제 지원할 학과·계열의 최저 기준/}));
    await page.getByRole('menuitem',{name:'일반학과',exact:true}).click();
    await page.getByText('모의고사 대비 수능 최저: 충족 수준',{exact:true}).last().waitFor({timeout:10000});
    await reveal(page.getByText('선택 기준 원문:',{exact:false}).last());
    await page.screenshot({path:`tools/ocr/test-output/design/minimum-${name}.png`});
    await page.reload();await enable();await generate();
    await page.getByRole('checkbox',{name:'지원자격 · 본인 확인',exact:true}).waitFor();
    assert.ok(await page.getByRole('checkbox',{name:'지원자격 · 본인 확인',exact:true}).isChecked());
    await page.getByText('모의고사 대비 수능 최저: 미달 수준',{exact:true}).waitFor();
    assert.deepEqual(errors,[]);
    console.log(`PASS ${name}: latest exam below → other exam met; branch selection; check marks restored after reload; no rendering errors`);
    await context.close();
  }
}finally{await browser?.close();await new Promise(r=>server.close(r));}
