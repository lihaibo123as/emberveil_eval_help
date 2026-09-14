const fs=require('fs');
const fengari=require('fengari');
const {lua,lauxlib,to_luastring}=fengari;
const candidates=[process.argv[2],"G:\\game\\u5wow\\Azeroth\\Binaries\\Win64\\Games\\Emberveil\\live\\Azeroth\\Interface\\AddOns\\EvalHelp\\EVAL_HELP.lua","EVAL_HELP.lua"].filter(Boolean);
const f=candidates.find(p=>fs.existsSync(p));
if(!f){ console.log("SYNTAX ERROR: EVAL_HELP.lua not found"); process.exit(1); }
const src=fs.readFileSync(f);
console.log("checking:", f);
const L=lauxlib.luaL_newstate();
const st=lauxlib.luaL_loadbuffer(L,src,src.length,to_luastring("EVAL_HELP.lua"));
if(st!==lua.LUA_OK){ console.log("SYNTAX ERROR:", lua.lua_tojsstring(L,-1)); process.exit(1); }
console.log("SYNTAX OK");