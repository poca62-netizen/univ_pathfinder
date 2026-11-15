import {chromium} from 'playwright-core';
import fs from 'node:fs/promises';
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
try{
 const page=await browser.newPage();
 const bytes=[...await fs.readFile('성적표/M2-9.jpg')];
 const cropped=await page.evaluate(async bytes=>{
  const image=await createImageBitmap(new Blob([Uint8Array.from(bytes)],{type:'image/jpeg'}));
  const left=.02,top=.078,right=.55,bottom=.302,scale=2;
  const canvas=document.createElement('canvas');canvas.width=Math.round((right-left)*image.width*scale);canvas.height=Math.round((bottom-top)*image.height*scale);
  const ctx=canvas.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(image,left*image.width,top*image.height,(right-left)*image.width,(bottom-top)*image.height,0,0,canvas.width,canvas.height);
  const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',.98));image.close();return [...new Uint8Array(await blob.arrayBuffer())];
 },bytes);
 await fs.writeFile('tools/ocr/test-output/private-mock-top.jpg',Buffer.from(cropped));
 console.log('Private upper-table crop prepared locally.');
}finally{await browser.close();}
