/* SPDX-License-Identifier: MIT */
(()=>{'use strict';
const M=window.DBModel,$=id=>document.getElementById(id),command="'/data/adb/modules/dirbridge/bin/dirbridge'";
let rows=[],states=[],paused=false,editing=null,currentFolder='',counter=0,busy=false;
function notice(text,error=false){$('notice').textContent=text;$('notice').classList.toggle('error',error);}
function exec(args){
  if(!window.ksu||typeof ksu.exec!=='function')return Promise.reject(Error('请从 KernelSU 模块页面打开此界面'));
  // All variable command arguments are base64 or fixed 0/1. No raw paths enter the shell.
  if(!args.every(x=>/^[A-Za-z0-9+/=_-]+$/.test(x)))return Promise.reject(Error('命令参数无效'));
  return new Promise((resolve,reject)=>{
    const name='dirbridgeResult'+Date.now()+'_'+counter++;
    const timer=setTimeout(()=>{delete window[name];reject(Error('操作尚未返回，请稍后刷新状态；不要重复点击'));},150000);
    window[name]=(errno,stdout,stderr)=>{clearTimeout(timer);delete window[name];Number(errno)===0?resolve(stdout):reject(Error((stderr||stdout||'操作失败').slice(0,1200)));};
    try{ksu.exec(command+' '+args.map(x=>"'"+x+"'").join(' '),'{}',name);}catch(e){clearTimeout(timer);delete window[name];reject(e);}
  });
}
async function run(fn){if(busy)return;busy=true;document.querySelectorAll('button').forEach(b=>b.disabled=true);try{await fn();}catch(e){notice(e.message,true);}finally{busy=false;document.querySelectorAll('button').forEach(b=>b.disabled=false);}}
function button(text,action,cls=''){const b=document.createElement('button');b.textContent=text;b.className=cls;b.addEventListener('click',action);return b;}
function render(){
  const container=$('mappings');container.replaceChildren();
  if(!rows.length){const empty=document.createElement('div');empty.className='empty';empty.textContent='还没有映射。添加电报、迅雷或其他应用的下载目录。';container.append(empty);}
  for(const m of rows){
    const card=document.createElement('article');card.className='mapping';const head=document.createElement('div');head.className='mapping-head';
    const title=document.createElement('h3');title.textContent=m.alias;head.append(title);
    const reports=states.filter(x=>x.id===m.id),problem=reports.find(x=>['error','conflict','busy'].includes(x.code)),waiting=reports.find(x=>x.code==='waiting');
    const good=reports.some(x=>x.code==='mounted');const badge=document.createElement('span');badge.className='badge'+(problem?' error':'');
    badge.textContent=!m.enabled?'已停用':paused?'全部暂停':problem?'需要处理':waiting?'等待源目录':good?'已挂载 · 待读取验证':'等待应用';head.append(badge);card.append(head);
    const path=document.createElement('p');path.className='path';path.textContent=m.source+'\n↓\n/storage/emulated/0/Movies/DirBridge/'+m.alias;path.style.whiteSpace='pre-line';card.append(path);
    if(problem||waiting){const p=document.createElement('p');p.className='message';p.textContent=(problem||waiting).detail;card.append(p);}
    const actions=document.createElement('div');actions.className='actions';
    actions.append(button('编辑',()=>openEditor(m)),button(m.enabled?'停用':'启用',()=>run(()=>persist(rows.map(x=>x.id===m.id?{...x,enabled:!x.enabled}:x)))));
    actions.append(button('移除映射',()=>run(()=>persist(rows.filter(x=>x.id!==m.id))),'danger'));
    card.append(actions);container.append(card);
  }
  $('pause').textContent=paused?'恢复全部':'暂停全部';
  if(busy)document.querySelectorAll('button').forEach(b=>b.disabled=true);
}
async function refresh(){
  const output=await exec(['status']);states=[];
  for(const line of output.trim().split('\n')){const p=line.split('|');if(p[0]==='ENV'){
    paused=p[4]==='1';$('environment').textContent=M.decode(p[3])+' · Android '+M.decode(p[2])+' (API '+p[1]+') · '+(p[5]==='1'?'自动映射服务运行中':'自动映射服务未运行，请重启')+(p[6]?' · '+M.decode(p[6]):'');
  }else if(p[0]==='CFG')rows=M.parse(M.decode(p[1]));else if(p[0]==='S')states.push({id:p[1],code:p[2],detail:M.decode(p[3]),ns:p[4]});}
  render();
  const globalProblem=states.find(x=>x.id==='-'&&x.code!=='disabled');if(globalProblem)notice(globalProblem.detail,true);
  return Boolean(globalProblem);
}
async function persist(next){
  const config=M.serialize(next);await exec(['save',M.encode(config)]);rows=next;render();notice('配置已保存，正在应用…');
  try{await exec(['apply']);const issue=await refresh();if(!issue)notice('配置已保存并处理。请查看各目录状态，再到播放器刷新。');}
  catch(e){await refresh().catch(()=>{});throw Error('配置已保存，但应用未完成：'+e.message);}
}
function openEditor(m){editing=m?m.id:null;$('editor-title').textContent=m?'编辑目录':'添加目录';$('alias').value=m?m.alias:'';$('source').value=m?m.source:'';$('enabled').checked=m?m.enabled:true;$('form-error').textContent='';$('editor').showModal();}
$('add').onclick=()=>openEditor();
for(const id of ['close-editor','cancel-editor'])$(id).onclick=()=>$('editor').close();
$('mapping-form').onsubmit=e=>{e.preventDefault();run(async()=>{
  let m;try{m=M.validate({id:editing||'m_'+Date.now().toString(16)+'_'+Math.random().toString(16).slice(2,8),alias:$('alias').value.trim(),source:$('source').value,enabled:$('enabled').checked},rows);}catch(e){$('form-error').textContent=e.message;return;}
  const next=editing?rows.map(x=>x.id===editing?m:x):[...rows,m];await persist(next);$('editor').close();
});};
$('apply').onclick=()=>run(async()=>{notice('正在重新应用…');await exec(['apply']);if(!await refresh())notice('已处理映射，请到 MX 刷新列表。');});
$('refresh').onclick=()=>run(async()=>{notice('');await refresh();});
$('pause').onclick=()=>run(async()=>{await exec(['pause',paused?'0':'1']);if(!await refresh())notice(paused?'已暂停；正在播放的文件可能需要停止播放后才能解除映射。':'已恢复映射。');});
async function browse(path){
  $('browse-error').textContent='';const output=await exec(['browse',M.encode(path)]);$('folders').replaceChildren();let count=0;
  for(const line of output.trim().split('\n')){const p=line.split('|');if(p[0]==='P'){currentFolder=M.decode(p[1]);$('browse-path').textContent=currentFolder;}else if(p[0]==='D'){$('folders').append(button('▸ '+M.decode(p[1]),()=>run(()=>browse(M.decode(p[2])))));count++;}else if(p[0]==='TRUNCATED')$('browse-error').textContent='仅显示前 500 个子目录；可直接填写完整路径。';}
  if(!count){const p=document.createElement('p');p.textContent='没有子文件夹，可选择当前目录。';$('folders').append(p);}
}
$('browse').onclick=()=>run(async()=>{$('picker').showModal();await browse('/storage/emulated/0/Android/data');});
$('close-picker').onclick=()=>$('picker').close();
document.querySelectorAll('[data-root]').forEach(b=>b.onclick=()=>run(()=>browse('/storage/emulated/0/'+b.dataset.root)));
$('parent').onclick=()=>run(async()=>{const parent=currentFolder.slice(0,currentFolder.lastIndexOf('/'));if(parent==='/storage/emulated/0/Android'||parent==='/storage/emulated/0')return;await browse(parent);});
$('select-folder').onclick=()=>{try{$('source').value=M.validateSource(currentFolder);$('picker').close();}catch(e){$('browse-error').textContent=e.message;}};
$('diagnose').onclick=()=>run(async()=>{$('diagnostic-text').value=await exec(['diagnose']);$('diagnostic').showModal();});
$('close-diagnostic').onclick=()=>$('diagnostic').close();
$('copy-diagnostic').onclick=()=>run(async()=>{try{await navigator.clipboard.writeText($('diagnostic-text').value);notice('诊断已复制');}catch{ $('diagnostic-text').select();document.execCommand('copy');notice('可长按诊断文字复制');}});
run(refresh);
})();
