const fs=require('fs');
const html=fs.readFileSync('api_lua.html','utf8');
const m=html.match(/index: JSON\.parse\('((?:[^'\\]|\\.)*)'\)/);
if(!m){console.log('no index json found');process.exit(1);}
const raw=JSON.parse('"'+m[1].replace(/"/g,'\\"')+'"');
const idx=JSON.parse(raw);
console.log('total entries:',idx.length);
const kw=process.argv.slice(2).map(s=>s.toLowerCase());
for(const e of idx){
  const hay=(e.name+' '+e.category+' '+(e.description||'')).toLowerCase();
  if(kw.some(k=>hay.includes(k))) console.log(e.category+' | '+e.name+' | '+(e.description||'')+' | '+e.url);
}
