/* SPDX-License-Identifier: MIT */
(function(root){
  'use strict';
  const encode=s=>{const bytes=new TextEncoder().encode(s);let v='';for(const b of bytes)v+=String.fromCharCode(b);return btoa(v);};
  const decode=s=>new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(atob(s),c=>c.charCodeAt(0)));
  const clean=s=>!!s&&!/[\x00-\x1f\x7f|\\]/.test(s);
  function normalize(s){return s.trim().replace(/^\/sdcard\//,'/storage/emulated/0/').replace(/^\/data\/media\/0\//,'/storage/emulated/0/').replace(/\/+$/,'');}
  function validateSource(value){
    const s=normalize(value);
    if(!clean(s)||new TextEncoder().encode(s).length>1024||s.includes('//')||/(^|\/)\.{1,2}(\/|$)/.test(s))throw Error('路径格式不正确');
    if(!/^\/storage\/emulated\/0\/(?:Android\/(?:data|media)\/[A-Za-z0-9._]+\/.+|(?:Download|Movies|DCIM)\/.+)$/.test(s))throw Error('请选择主用户内部存储中的实际下载子目录');
    if(s==='/storage/emulated/0/Movies/DirBridge'||s.startsWith('/storage/emulated/0/Movies/DirBridge/'))throw Error('不能把映射目录再次作为来源');
    return s;
  }
  function validate(m,all=[]){
    if(!/^[A-Za-z0-9_-]{1,48}$/.test(m.id))throw Error('映射 ID 无效');
    if(!clean(m.alias)||new TextEncoder().encode(m.alias).length>180||m.alias.startsWith('.')||/[\/]/.test(m.alias)||m.alias!==m.alias.trim())throw Error('文件夹名称不能含斜线、控制字符，或以点、空格开头；最多 180 UTF-8 字节');
    if(all.some(x=>x.id!==m.id&&x.alias===m.alias))throw Error('已有同名映射，请换一个文件夹名称');
    if(typeof m.enabled!=='boolean')throw Error('启用状态无效');
    return {...m,source:validateSource(m.source)};
  }
  function serialize(rows){
    if(rows.length>64)throw Error('最多添加 64 个目录');
    if(new Set(rows.map(x=>x.id)).size!==rows.length)throw Error('重复的映射 ID');
    return '# DirBridge schema=1\n'+rows.map(x=>{const m=validate(x,rows);return [m.id,m.enabled?1:0,encode(m.alias),encode(m.source)].join('|');}).join('\n')+'\n';
  }
  function parse(text){return text.split('\n').filter(x=>x&&!x.startsWith('#')).map(line=>{const parts=line.split('|');if(parts.length!==4||!['0','1'].includes(parts[1]))throw Error('配置格式错误');return validate({id:parts[0],enabled:parts[1]==='1',alias:decode(parts[2]),source:decode(parts[3])});});}
  const api={encode,decode,normalize,validateSource,validate,serialize,parse};
  if(typeof module==='object'&&module.exports)module.exports=api;else root.DBModel=api;
})(typeof window==='object'?window:globalThis);
