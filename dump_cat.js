const fs=require('fs');
const html=fs.readFileSync('api_lua.html','utf8');
const m=html.match(/index: JSON\.parse\('((?:[^'\\]|\\.)*)'\)/);
const raw=JSON.parse('"'+m[1].replace(/"/g,'\\"')+'"');
const idx=JSON.parse(raw);
const cat=process.argv[2];
const kw=process.argv[3];
const cats={};
for(const e of idx){ (cats[e.category]=cats[e.category]||[]).push(e.name); }
if(cat==='--cats'){ for(const c of Object.keys(cats)) console.log(c+': '+cats[c].length); }
else if(cat==='--kw'){ for(const e of idx){ const hay=(e.name+' '+e.category+' '+(e.description||'')).toLowerCase(); if(hay.includes(kw.toLowerCase())) console.log(e.category+' | '+e.name); } }
else { for(const e of idx.filter(x=>x.category===cat)) console.log(e.name+' | '+(e.description||'')); }
