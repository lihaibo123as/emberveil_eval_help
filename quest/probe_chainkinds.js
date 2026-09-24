/** quest/probe_chainkinds.js —— 只读探针：任务线「类型（种类）」筛选到底有没有生效
 *  用户实测：「任务线推荐 → 任务线 → 类型筛选 对当前列表无效，需要筛出包含该类型奖励的任务线」。
 *  本探针把两件事分开量：① **数据层** EVAL_QC_SEARCH(kinds) 有没有真的收窄；② **界面真实点击路径**
 *  （F2 按钮的 OnClick → 多选下拉点一下）之后命中条数有没有跟着变。
 *  用法：node quest/probe_chainkinds.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const root = path.join(__dirname, '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const files = ['test_stub.lua', 'Locales/zhCN.lua', 'Locales/enUS.lua', 'Locales/ruRU.lua', 'Core.lua', 'Engine.lua',
  'EvalHelp.lua', 'Toolbox.lua', 'quest/QuestData.lua', 'quest/QuestBulk.lua', 'quest/QuestChains.lua',
  'DataSearch.lua', 'Share.lua', 'IconSem.lua', 'IconBrowser.lua', 'PetData.lua', 'PetHelper.lua',
  'tools/IconGrid.lua', 'tools/HunterHelper.lua', 'tools/ConsumableHelper.lua', 'tools/DismountHelper.lua', 'tools/RareWatch.lua'];
for (const f of files) {
  const src = fs.readFileSync(path.join(root, f));
  const st = lauxlib.luaL_loadbuffer(L, src, src.length, to_luastring(f));
  if (st !== lua.LUA_OK) { console.error('LOAD FAIL ' + f + ': ' + to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) { console.error('RUN FAIL ' + f + ': ' + to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
}

const chunk = `
  EVAL_HELP_CONFIG = EVAL_HELP_CONFIG or {}
  EVAL_HELP_CONFIG.cfgTab = 4
  EVAL_DS_BUILD_FOR_TEST()          -- 弹窗的 EVAL_QP_* 只在 EVAL_DS_BUILD 里定义 ⇒ 必须先建一次
  local function cnt(f) return table.getn(EVAL_QC_SEARCH("", 0, f) or {}) end
  PROBE0 = cnt(nil)
  PROBE_EMPTY = cnt({ kinds = {} })
  local kinds, kindNames = EVAL_QC_KIND_LIST() or {}, {}
  for i = 1, table.getn(kinds) do kindNames[i] = tostring(kinds[i].k) end
  PROBE_KINDLIST = table.concat(kindNames, ",")
  local kk = nil
  for i = 1, table.getn(kindNames) do if kindNames[i] == "剑" then kk = kindNames[i] break end end
  if not kk then kk = kindNames[1] end
  PROBE_K = tostring(kk)
  PROBE_N = cnt({ kinds = { [kk] = true } })
  -- 越界检查：筛出来的每条，其奖励里**真的**含该种类（独立复算，不读生产判定）
  local h = EVAL_QC_SEARCH("", 0, { kinds = { [kk] = true } }) or {}
  local bad, noRw = 0, 0
  for i = 1, table.getn(h) do
    local rw = (type(h[i].c) == "table") and h[i].c.rw or nil
    if type(rw) ~= "table" then noRw = noRw + 1
    else
      local ok = false
      for j = 1, table.getn(rw) do
        local it = EVAL_QC_ITEM(rw[j]) or EVAL_QC_BULK_ITEM(rw[j])
        if it and EVAL_QC_ITEM_KIND(it) == kk then ok = true break end
      end
      if not ok then bad = bad + 1 end
    end
  end
  PROBE_BAD, PROBE_NORW = bad, noRw
  -- ==== 界面真实点击路径：F2 按钮 OnClick → 下拉点该种类 ====
  EVAL_QP_SHOW()
  EVAL_QP_SET_TAB("chain")
  EVAL_QP_SET_QUERY("")
  EVAL_QP_SET_FILTER("ALL", "ALL")
  EVAL_QP_SET_KINDS({})
  PROBE_UI0 = table.getn(EVAL_QP_HITS())
  PROBE_UI_LABEL0 = tostring(EVAL_QP_KIND_LABEL())
  EVAL_DD_TEST_RESET_ANCHOR()
  local f2 = EVAL_QP_TEST_F2()
  local on = (f2 and f2.GetScript) and f2:GetScript("OnClick") or nil
  PROBE_UI_ONCLICK = (type(on) == "function") and 1 or 0
  if type(on) == "function" then on() end
  local txts = EVAL_DD_TEST_VISIBLE_TEXTS() or {}
  local idx = nil
  -- ★标签形态是「色码 + 方框 + 空格 + 种类名」（形如 |cff6a6a6a + 方框 + |r + 空格 + 剑）⇒ 按**后缀**匹配
  --   （首版用精确相等 ⇒ 一个都找不到，idx 恒 -1，等于没点 —— 探针自身的坑）
  for i = 1, table.getn(txts) do
    local t = tostring(txts[i])
    if string.sub(t, -string.len(kk)) == kk then idx = i break end
  end
  PROBE_UI_IDX = idx or -1
  PROBE_TXTS = table.concat(txts, " | ")
  if idx then EVAL_DD_TEST_CLICK(idx) end
  local sel = {}
  local s = EVAL_QP_KINDS()
  for k, v in pairs(s) do if v then sel[table.getn(sel) + 1] = k end end
  PROBE_UI_SEL = table.concat(sel, ",")
  PROBE_UI_LABEL1 = tostring(EVAL_QP_KIND_LABEL())
  PROBE_UI1 = table.getn(EVAL_QP_HITS())
  -- 再点一次（取消勾选）应当回到全部
  EVAL_DD_TEST_RESET_ANCHOR()
  local f2b = EVAL_QP_TEST_F2()
  local onb = (f2b and f2b.GetScript) and f2b:GetScript("OnClick") or nil
  if type(onb) == "function" then onb() end
  local txts2 = EVAL_DD_TEST_VISIBLE_TEXTS() or {}
  if idx and txts2[idx] then EVAL_DD_TEST_CLICK(idx) end
  PROBE_UI2 = table.getn(EVAL_QP_HITS())
  -- 顺带验一下真机取证命令的核心函数（EVAL_QP_KIND_DIAG）真的能跑、且给出行
  EVAL_QP_SET_KINDS({})
  local dg = EVAL_QP_KIND_DIAG()
  PROBE_DIAG = table.concat(dg or {}, " ⏎ ")
`;
if (lauxlib.luaL_dostring(L, to_luastring(chunk)) !== lua.LUA_OK) {
  console.error('RUN FAIL: ' + to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
const g = n => { lua.lua_getglobal(L, to_luastring(n)); const v = lua.lua_tointeger(L, -1); lua.lua_pop(L, 1); return v; };
const gs = n => { lua.lua_getglobal(L, to_luastring(n)); const v = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); return v; };
console.log('种类清单               = ' + gs('PROBE_KINDLIST'));
console.log('数据层 counts(nil)     = ' + g('PROBE0'));
console.log('数据层 counts({})      = ' + g('PROBE_EMPTY') + '   （空集 = 不过滤，应与上一行相同）');
console.log('数据层 counts({"' + gs('PROBE_K') + '"}) = ' + g('PROBE_N'));
console.log('  越界（奖励里其实没有该种类）= ' + g('PROBE_BAD') + ' · 记录没有奖励清单 rw = ' + g('PROBE_NORW'));
console.log('界面 初始命中          = ' + g('PROBE_UI0') + ' · 标签="' + gs('PROBE_UI_LABEL0') + '"');
console.log('下拉可见项             = [' + gs('PROBE_TXTS') + ']');
console.log('界面 F2 有 OnClick     = ' + g('PROBE_UI_ONCLICK') + ' · 下拉里找到该种类 = ' + g('PROBE_UI_IDX'));
console.log('界面 点选后 DS.qpKinds = "' + gs('PROBE_UI_SEL') + '" · 标签="' + gs('PROBE_UI_LABEL1') + '"');
console.log('界面 点选后命中        = ' + g('PROBE_UI1') + '   （★应 < 初始命中）');
console.log('界面 再点一次（取消）  = ' + g('PROBE_UI2') + '   （应回到初始命中）');
console.log('取证命令 EVAL_QP_KIND_DIAG = ' + gs('PROBE_DIAG'));
