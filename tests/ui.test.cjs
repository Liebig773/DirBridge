// Tests only this project's local WebUI with a mocked KernelSU bridge.
const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),http=require('node:http'),path=require('node:path');
let playwright;try{playwright=require('playwright');}catch{playwright=require(process.env.PLAYWRIGHT_MODULE);}
const root=path.resolve(__dirname,'../module/webroot');
test('mobile WebUI: configuration, picker, XSS, toggles and layout',async()=>{
  const server=http.createServer((req,res)=>{const name=decodeURIComponent(req.url.split('?')[0]);const file=path.join(root,name==='/'?'index.html':name);if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}try{const types={'.html':'text/html','.js':'text/javascript','.css':'text/css'};res.setHeader('Content-Type',(types[path.extname(file)]||'text/plain')+'; charset=utf-8');res.end(fs.readFileSync(file));}catch{res.writeHead(404).end();}});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const browser=await playwright.chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
  try{
    const page=await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{
      let config='# DirBridge schema=1\n',paused=false;
      const enc=s=>btoa(unescape(encodeURIComponent(s))),dec=s=>decodeURIComponent(escape(atob(s)));
      window.mockCommands=[];
      window.ksu={exec(command,options,callback){
        window.mockCommands.push(command);
        const args=[...command.matchAll(/'([^']*)'/g)].map(x=>x[1]).slice(1);
        let output='';
        if(args[0]==='status'){
          output='ENV|37|'+enc('17')+'|'+enc('Android 17 · 模拟设备')+'|'+(paused?1:0)+'|1|'+enc('2026-10-22 18:00:00')+'\nCFG|'+enc(config)+'\n';
          for(const line of config.split('\n')){if(!line||line.startsWith('#'))continue;const p=line.split('|');output+='S|'+p[0]+'|'+(paused||p[1]==='0'?'disabled':'mounted')+'|'+enc('模拟挂载状态')+'|mnt:[123]\n';}
          if(window.mockGlobalProblem)output+='S|-|busy|'+enc('目录正在使用，停止播放后重试')+'|mnt:[123]\n';
        }else if(args[0]==='save'){config=dec(args[1]);output='SAVED';}
        else if(args[0]==='pause')paused=args[1]==='1';
        else if(args[0]==='browse'){
          const p=dec(args[1]);output='P|'+enc(p)+'\n';
          const child=p.endsWith('/Android/data')?'org.telegram.messenger':p.endsWith('org.telegram.messenger')?'files':p.endsWith('files')?'Telegram Video':null;
          if(child)output+='D|'+enc(child)+'|'+enc(p+'/'+child)+'\n';
        }else if(args[0]==='diagnose')output='DirBridge test diagnostics\nNo user data';
        setTimeout(()=>window[callback](0,output,''),5);
      }};
    });
    await page.goto('http://127.0.0.1:'+server.address().port);
    await page.locator('#add').click();await page.locator('#alias').fill('电报 视频');
    await page.locator('#browse').click();
    for(const text of ['▸ org.telegram.messenger','▸ files','▸ Telegram Video'])await page.getByRole('button',{name:text,exact:true}).click();
    await page.locator('#select-folder').click();
    assert.match(await page.locator('#source').inputValue(),/Telegram Video$/);
    await page.locator('#save').click();await page.waitForFunction(()=>!document.querySelector('#editor').open);
    assert.equal(await page.locator('.mapping').count(),1);
    assert.match(await page.locator('.badge').innerText(),/已挂载/);
    await page.locator('#add').click();await page.locator('#alias').fill('电报 视频');await page.locator('#source').fill('/sdcard/Download/a');await page.locator('#save').click();
    await page.waitForFunction(()=>document.querySelector('#form-error').textContent.includes('同名'));
    await page.locator('#alias').fill('<img src=x onerror=alert(1)>');
    await page.locator('#source').fill('/sdcard/Download/$(touch NEVER)');await page.locator('#save').click();
    await page.waitForFunction(()=>!document.querySelector('#editor').open);
    assert.equal(await page.locator('.mapping').count(),2);assert.equal(await page.locator('img').count(),0);
    assert.equal(await page.evaluate(()=>mockCommands.some(c=>c.includes('touch NEVER'))),false,'No raw path in shell commands');
    for(const width of [320,390,430]){await page.setViewportSize({width,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`horizontal overflow at ${width}`);}
    await page.setViewportSize({width:390,height:844});
    fs.mkdirSync(path.resolve(__dirname,'../test-results'),{recursive:true});
    await page.screenshot({path:path.resolve(__dirname,'../test-results/webui-390.png'),fullPage:true});
    await page.locator('.mapping').first().getByRole('button',{name:'停用',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.badge').textContent==='已停用');
    await page.locator('#pause').click();await page.waitForFunction(()=>document.querySelector('#pause').textContent==='恢复全部');
    await page.locator('#pause').click();await page.waitForFunction(()=>document.querySelector('#pause').textContent==='暂停全部');
    await page.locator('.mapping').last().getByRole('button',{name:'移除映射'}).click();await page.waitForFunction(()=>document.querySelectorAll('.mapping').length===1);
    await page.evaluate(()=>window.mockGlobalProblem=true);
    await page.locator('#apply').click();await page.waitForFunction(()=>!document.querySelector('#apply').disabled);
    assert.match(await page.locator('#notice').innerText(),/停止播放后重试/,'Busy warning must not be overwritten by a success notice');
    await page.locator('#diagnose').click();await page.waitForFunction(()=>document.querySelector('#diagnostic').open);
    assert.match(await page.locator('#diagnostic-text').inputValue(),/test diagnostics/);
    assert.deepEqual(errors,[]);
  }finally{await browser.close();await new Promise(r=>server.close(r));}
});
