const fs=require('fs');
const fengari=require('fengari');
const {lua,lauxlib,lualib,to_luastring}=fengari;
const L=lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
for(const f of ['test_stub.lua','Locales/zhCN.lua','Locales/enUS.lua','Locales/ruRU.lua','Core.lua','Engine.lua','EvalHelp.lua','test_assert.lua']){
  const src=fs.readFileSync(f);
  const st=lauxlib.luaL_loadbuffer(L,src,src.length,to_luastring(f));
  if(st!==lua.LUA_OK){ console.log('LOAD ERROR ['+f+']:',lua.lua_tojsstring(L,-1)); process.exit(1); }
  if(lua.lua_pcall(L,0,0,0)!==lua.LUA_OK){ console.log('RUNTIME ERROR ['+f+']:',lua.lua_tojsstring(L,-1)); process.exit(1); }
}
console.log('DONE');
