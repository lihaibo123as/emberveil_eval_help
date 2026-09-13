const fs=require('fs');
const fengari=require('fengari');
const {lua,lauxlib,to_luastring}=fengari;
const f="G:\\game\\u5wow\\Azeroth\\Binaries\\Win64\\Games\\Emberveil\\live\\Azeroth\\Interface\\AddOns\\EvalHelp\\EVAL_HELP.lua";
const src=fs.readFileSync(f);
const L=lauxlib.luaL_newstate();
const st=lauxlib.luaL_loadbuffer(L,src,src.length,to_luastring("EVAL_HELP.lua"));
if(st!==lua.LUA_OK){ console.log("SYNTAX ERROR:", lua.lua_tojsstring(L,-1)); process.exit(1); }
console.log("SYNTAX OK");