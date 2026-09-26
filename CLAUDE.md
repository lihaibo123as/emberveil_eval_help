# EVAL_HELP 插件项目记忆（EmberVeil 全职业工具）

> 本文件只记**铁律 / 判据 / 关键注意项**：逐版本细节在 `CHANGELOG.md`、git 历史，以及同目录 **`CLAUDE_REFERENCE.md`（参考卷，不自动载入）**。
> ★★**指令预算 = 1 MiB**：唯一有效修法 = **web profile 补丁层按 id 覆盖 preset 声明行**（`%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml` 的 `- id: preset-standard / preset-ptc / preset-cordis` 覆盖块，**完整重述 `config`**，其 `plugins` 内 `agent-instructions.config.maxBytes: 1048576`）。
> · 生成/验证 = 仓库根 **`dsh_memory_budget.js`**（`apply` 重生成 + 先备份 / `check` 闸门 / `status` 列候选）；`check` 用「**临时 `DSH_HOME` + `dsh --profile web --dump-config`**」自证，纯读。★覆盖**替换整个 config**（少写字段 = preset 激活失败）⇒ 一律脚本生成。
> · **两条死路**：① 改安装内 `dsh-web-app\presets\<id>.patch.yml`（升级/换 `_npx` hash 即回 65536）；② profile 补丁只写**单层** `- id: agent-instructions`（被 web-app bundle 补丁 `disabled: true` 关掉，写了不生效）。生效时机 `patchReload = startup` ⇒ **必须重启 GUI、只对新会话生效**。★判「现在跑哪份安装」看**自己有没有 `ralph` 工具**（0.1.5 standard 有 / 0.1.7-rc.2 无），别猜 `_npx` hash。全案 = 参考卷 **R17**。
> ★**参考卷里有什么**：发布 release 9 步全文 + 打包脚本 · §六 历史教训 · §七 开源仓库/官方 API/待开发 · §八 项目位置与现状（文件结构 · toc 顺序 · 新增模块改哪几处 · 当前版本）· §九 版本要点 · §十四 任务线明细 · §十五~十七 速查/原文 · **附录 R1~R22**（各判据踩坑全案）。
> ★**写入纪律**：先查有没有同类条目——**宁可合并改写，不要追加流水账**；踩坑经过/版本叙事/截图佐证一律进参考卷附录 R。查「某功能/坑现在怎么写」→ 先看第五节判据，再看源码。

## ★★★不许用子代理 / 答复语种 = 中文 / 改完自动同步 / 「提交版本」≠ release

- **不许子代理**（用户 1.74.31 原话：「记住不要使用子代理模式处理任务」）：开发/排查/改代码**一律本人直接做**，不用 `subagent`/`subagent_fork`/`workflow`/`ralph`；上下文紧张就分段做，每段跑闸门。
- **答复一律中文**（用户：「英文我看不懂」）：报告/分析/清单都用中文；代码标识符/API 名/事件名原样保留。
- **改完代码自动同步**（用户 1.74.8）：主插件**本址即游戏目录**（`G:\game\uwow\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns\EvalHelp`）⇒ 不用复制；★但 `addons\` 子插件**必须复制到同级目录**（`node sync_game.js`，本机分支 = 主插件跳过 + 子插件复制，幂等，报「改0/同4」）。**次序：先过两道闸门再同步**。复制口径 = `.toc` 现算清单（含 `tools\`/`Locales\`/`examples\` 递归），**不带** `test_*`/`luacheck.js`/`tmp\`/`preview\`/`doc\`/`.git`；这条**不是** release 的一部分。
- **「提交版本」= 只 `git add` + `commit`**（用户 1.72.1：「提交版本不要触发 release」）；只有明确说 **release / 发布 / 出包 / 建 Release** 才走 9 步（详见参考卷）；不确定先问一句。推送走 `git@` + `--tags`；Release 页我做不了（无 gh/token）⇒ 如实请用户网页建。

## 一、铁律

### 1. ★★★改完必须跑闸门 = **只有 `node luacheck.js`**（本项目因语法错白丢过好几个版本的功能）
- Lua 语法错 ⇒ **整个插件载不进去**，且 UE 日志（`%LOCALAPPDATA%\Azeroth\Saved\Logs`）**是空的**（落盘通道全废）⇒ 只有它能兜。判据 = 输出 `SYNTAX OK: N files checked`（fengari 真解析、**逐个文件**）。
- ★★★**本项目没有测试**（用户 2026-09-26 定案：「**删除tests/下的文件.也不需要测试**」）：`tests/`（7 个源码检查 + 3 个断言组文件）· `test_assert.lua` · `test_engine.js` · `check.js` · `mutate.js` · `tmp/runcheck.js` **已全部删除**（历史仍在 git 里，要考古用 `git show <rev>:<path>`）。
  ⇒ 以前那套「**断言组 / 源码检查 / 变异验证 / 双闸门 exit 0**」**一律不再维护、也不再跑**；`STATUS`/`CHECK`/变异编号在旧文档与注释里仍会出现 —— 那是**历史记录**，不是现行要求。
  ★★**代价必须认并如实告知**：行为/接线/渲染/存档/清单结构这类**静默失效不再有自动判据兜底** ⇒ ① 改完**先自查调用点与数据流**（尤其 UI 接线、存档键、事件注册）；② 交付说明里写清「**本轮只过了语法闸门**」；③ 真机实测才是最终判据。★唯一留下的静态助手：`luacheck.js`（语法）+ `scan_dangling.js`/`probe_localorder.js`（文件内 local 顺序，按需手动跑）。

### 2. ★★★任务/地图类问题 → 先读 UnrealQuest 流程代码（用户 1.70.40：「碰到任务地图相关的问题优先排查任务插件的对应流程代码」）
- 按问题定位读：定时/生命周期 → `Core/Driver.lua`；当前看哪张图 → `Map/MapContext.lua`（`GetViewedZone`/`Inspect`）；怎么画/何时重绘 → `Map/WorldMapPins.lua`（`ViewSignature`/`Refresh`）；**某 API 能不能用** → `Compatibility/ClientAPI.lua`（实测配方库）；图标素材 → `Map/NpcPins.lua`。
- 重点是**大段注释**（对方把踩过的坑与 API 真假都留在里面）。★**停下信号**：在「加日志→看日志→猜」里转第二圈 ⇒ 立刻去读对方代码；读完仍未解决 ⇒ 转铁律 4 取证。

### 3. ★★★队伍/团队·血量/蓝量·buff/debuff → 先读 Heart 与 C 库（用户 1.70.46）
- **本机就是游戏主机**：EmberVeil 与 TurtleWoW（`D:\game\TurtleWoW`）都在本机，可直接读源码/进游戏实测。★完整「按问题查哪个文件」对照表 = 参考卷 **R16**。
- **必抄的五个机制**：① 隐形 tooltip 当 API 用（`C.xml` 的 `C_Tooltip` + 先清行再 `SetUnitBuff/SetUnitDebuff/SetSpell/SetAction` 再 `GetText`）；② **Tick 新鲜度**（`entry.Tick == CurrentTick` 才算「现在有」，结构上杜绝过期数据）；③ 贵调用只在**新出现**时做；④ 名字↔unit 反查先缓存再慢查，**缓存命中也要 `UnitExists` + 名字复核**；⑤ 共用更新函数的**单调用者仲裁**。
- ⚠️ 边界：Heart/C 是 **TurtleWoW** 插件，本机 `C\C.lua` 已被改成「治疗施法监控」且依赖 SuperWoW ⇒ **抄机制、不抄结论**，每个 API 必须在本客户端实测（本项目已定案：**无 SuperWoW / 无 UnitCastingInfo**）。

### 4. ★★★同一个问题两三轮没解决 → 转「操作日志 + 测试流程」取证（用户 1.70.46）
- **硬性计数**：同一现象「改一版→再试→还是不对」**第 3 轮必须转取证**。一次交付三样：① **操作日志**（插桩点在**分叉处**，必须能区分「代码没跑」与「条件没满足」；用不受 trace 门控的通道）；② **编号测试流程**（从 `/reload` 干净状态起，每步写「做什么→期望看到什么」；出错后**剩下的步骤也要走完**）；③ **回传物说明**（`/eh logdump` 或读 `%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`；★本客户端**只在 `/reload`/退出时落盘**）。
- ★**能做成命令就别让用户手工复现**（本项目范式：`/eh ds rnd`、`/eh ds hud`、`/eh go probe`、`/eh go mbicon`、`/eh go tsel`、`/eh go assist`）。**一次只验一个假设**；日志按自带时间戳对时间轴；出现两句自相矛盾 ⇒ 立刻怀疑同一变量两处绑定。

### 5. ★★★返工功能涉及 API → 先核「调用本身对不对」，再动逻辑（用户明确定）
- 逐条问：① 这函数/事件名在本客户端**真的存在吗**（`api_*.html` 1370 条索引 · UnrealQuest `ClientAPI.lua` · `emberveil.org/wiki/lua`）；② 参数个数/顺序/类型（如 `SendChatMessage(文, 类型, 语言, **频道号**)`）；③ 返回值/语义；④ 事件名/消息组名**不许猜**（现场探）。
- 配套：拿不准就**先写探针取证**。首案 = 频道进出屏蔽返工三次（参考卷 **R7**）。

## 二、频率防护总则

- **原则**：可能高频触发的流程**设计阶段**就要限频（不要等被踢线/刷屏再补）。服务器写动作 > ~1-2 次/s 必限频；客户端事件**先假设会连发**。
- 三类范式：① 服务器写动作 → `tbQ` + OnUpdate 滴出（`TB_RATE=0.3s`；教训：一帧 24 次 `UseContainerItem` 被反滥用踢线）＋逐笔验证状态机 `tbPending`（槽位消失=成功/超时 2s=失败）+ 执行前二次校验 + `MERCHANT_HIDE` 清待办；② 事件驱动 → 去抖（`MERCHANT_SHOW` 连发两次 ⇒ 1.5s 去重窗；`BAG_UPDATE` 0.5s 节流）；③ 执行入口 → 去抖窗（`EVAL_GO` 0.2s，可配 `cfg.goDebounce`，附 `EVAL_GO_TRACE`）。
- ★★★**分享分片必须限频发送**：一帧连发 N 片撞反刷屏限流 ⇒ 接收端**永远收不齐**（1.72.3 实案）⇒ 第 1 片立即发、其余 FIFO 每 `SH_SEND_RATE=0.5s` 一片（2 条/s），队列上限 `SH_MAX_QUEUE=200`；判据 = 组 106 + 变异 M7（全案 **R8**）。
- **Protected 函数**（`SendChatMessage`/`SpellStopCasting`）绕行 = `RunScript`（**本身也是队列**，连发同样会被踢）⇒ 通知类输出也要入限频队列。

## 三、本客户端已实测的 UI 配方

1. **拖动柄必须用 Button**（Frame 的 `OnDragStart` 不触发）；`SetFrameLevel(父+10)` 抬高（**用 strata 抬高是在案的失败法**）；`EnableMouse` + `RegisterForClicks` + `RegisterForDrag`；`StartMoving` 前 warm-up 两步。
2. **strata 陷阱**：配置窗是 DIALOG；其上方弹窗（技能编辑窗/导入导出窗）必须**同 DIALOG + `SetFrameLevel(90~100)`**（MEDIUM/HIGH 会被盖住）；弹窗也要 `uiOffscreen` 越界回归。
3. **纯色纹理**只有 `Interface\Buttons\WHITE8X8` + `SetVertexColor` 可靠。
4. **无原生 Slider / 无下拉控件**：滑条 = 自制轨道 + 拇指；**下拉一律 `EVAL_DD_OPEN(锚点, 选项, 回调)`**（UIParent+DIALOG+level250，多列 12 行/列，贴屏底自动上翻；宿主窗口 `OnHide` 里调 `EVAL_DD_HIDE()`）。
5. **可见性契约**：显隐走**显式控件清单** Show/Hide，不靠父子传播（容器 `EnableMouse(false)`，交互件单独 `EnableMouse(true)`）。
6. **位置记忆**：`GetCenter`/`GetLeft` **含缩放**，存取要除 `GetEffectiveScale`；每个记忆位置的窗口都要 `uiOffscreen` 回归。
7. **禁用 `SetScale`**（点击框漂移）⇒ 缩放 = 按 z 系数**几何重建**；字体链 `FZLBJW→FRIZQT→ARIALN` 全程 `pcall`。
8. **小地图按钮父级必须是 `UIParent`**；悬停用 `OnEnter`/`OnLeave` + GameTooltip，**不用 `SetHighlightTexture`**。
9. ★**纹理/FontString 都不吃鼠标事件** ⇒ 要悬停就盖一个**透明 Button**（几何上真盖住目标）。

## 四、架构要点 + 编辑工具注意事项 + 当前功能地图

### 4.1 架构要点
- ★★★**工具类功能一律独立文件，`Toolbox.lua` 只做开启/配置入口**（用户 1.74.34）：`tools/<模块>.lua` 自包含（真值 + 自己的存档子树 + 界面控件 + 读值口 + 自己的**有界**计时器）；Toolbox 里只允许「模块行数据 `t="mod", mod=, key=`」与「入口按钮」；机制 = **模块行注册表 `EVAL_TB_MOD_ROWS[mod]`**（模块载入期自登记 ⇒ 与 toc 顺序无关）；判据 = `TB MOD ROW CHECK`。现有：`LayerFix` / `DragFrames` / `SimpleMap` / `RareWatch` 等。
- ★★★**工具模块的读值口留在模块自己文件里**（`EVAL_XX_TEST_*`）—— 名字带 TEST，但它们是**生产诊断口**（`/eh go …` 探针与真机取证都走它们）⇒ **保留**。★原先配套的「断言组 `tests/tools/<模块>.lua` + 源码检查 `tests/checks/<模块>.js` + `test_engine.js` 载入对账」**已随 `tests/` 一并删除**（用户 2026-09-26：「删除tests/下的文件.也不需要测试」；全清单见铁律 1）。
- **状态表 `st`（`EVAL_HELP_STATE`）**：所有判定数据 `UPDATE_STATE()` **一次刷新、各处只读**；含 `playerBuffs`/`targetDebuffs`、`castLog`。
- **规则引擎**：规则 `{ skill, enabled, groups }`，组内 `&`、组间 `|`；`EVAL_RULE_RUN` 顺序执行第一条全过的；核心 = `condOne`/`groupsOK`/`EVAL_PARSE_CONDS`/`EVAL_COND_STR`/`EVAL_GROUP_STR`。
- **方案数据**：`cfg.war.profiles` + `activeProfile`；`EVAL_WAR_ENSURE_PROFILES` 做缺省迁移。方案切换 = 侧栏/激活选择器/战斗UI 方案行/**Shift+按宏**（Shift 已被占用 ⇒ 方案条件里用 Alt/Ctrl）。
- **文本格式**：`# 方案: 名` + `- 技能 | 条件`；技能名前 `!` = 停用；解析容忍 md 杂物行。
- **作用域**：`warCfg`/`c()` 是配置段 local ⇒ 更早的 UI 段用 `uiWarCfg()`（走 `EVAL_HELP_CONFIG`）；`wslots`/`WAR_SKILLS` 在配置段之前声明、之后可用。
- 受保护函数插件**不能调**：施法一律 `UseAction(slot)` + `pcall`；谓词返回 `true/false/nil`，**绝不 `==1`**。
- ★**`EVAL_GO` 无「无可攻击目标就 return」的全局前置**（1.21.7）：是否需目标交给**每条规则的条件**，否则纯自身 buff 方案永远不执行。
- **射程 API**：`IsActionInRange(slot)`→`true`/`0`(超程)/`1`(自动攻击不测距)/`nil`；`ActionHasRange(slot)`；`CheckInteractDistance(unit,idx)` 不分档。
- **物品 API**：`UseContainerItem(bag,slot)`；`GetContainerItemInfo`→texture,count,locked,quality,readable；`GetContainerItemLink`；`GetContainerItemCooldown`；`GetItemInfo` 第 9 返回 = 纹理。**无 `EquipItemByName`/`UseItemByName`**；`UseContainerItem` 是否被禁需实测（被禁是**静默失败**）。
- **`seBtn` 返回包裹表 `{btn,bg,text}`**：锚下拉/加 FontString 必须用 `.btn`（`mkSmall` 相反：直接返回 `b,bt`）。
- **Lua local 作用域从声明之后开始**：RHS 闭包捕获不到正在声明的 local ⇒ `local b = mk(..., function() 引用b end)` 里 `b` 是**全局 nil**，OnClick 要等赋值完再 `SetScript`。
- **EditBox 疑似不渲染**（pcall 全成功却看不见）⇒ 文本类 UI 一律给 FontString 保底（IO 窗预览区；单行输入用**回声行** `OnTextChanged` 镜像）；字体链先试 `SetFontObject(GameFontHighlightSmall/ChatFontNormal/GameFontNormal)`。

### 4.2 编辑工具注意事项
- `run_code` 里**没有 `require`**；node 脚本一律写 `tmp/*.js` 再 `pwsh node tmp/x.js`（内联 `-e` 引号必被 PowerShell 拆坏）；`pwsh` 加 `2>&1 | Out-String`。
- `edit` 工具：本会话内须先 `read`；`old_string` 要精确（失败先 `grep` 核对）；**node 外部改过文件后必须重新 read**。大块插入 = 写块文件 + node 边界替换脚本。
- ★★★**绝不用 PowerShell 读/写文本**：`Get-Content` 把无 BOM UTF-8 读成 GBK（乱码），`Set-Content`/`>` 写成 UTF-16LE+BOM（node 读全是乱码），**含中文往返不可逆写坏**。⇒ 一律走 node（`fs.readFileSync(p,"utf8")`）或 `read`/`edit`；看 git 某版本用 `execSync("git show rev:file")`。
- **SavedVariables 路径**：`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`（★文件名是 `EvalHelp.lua`）；**只在 `/reload`/小退/退出时写盘**。
- DSH 策略 danger-full-access、审批关闭 ⇒ 可直接写游戏目录。

### 4.3 当前功能地图
- `/eh` 状态日志 | `/eh ui` 战斗信息UI（方案行 + 技能行 + 条件 tooltip + 实时亮金）| `/eh st` 状态信息UI。
- `/eh cfg` 配置窗 660×460（中文）/800×460（西文），**七个 Tab**（宽 84/间距 88）：① 全局 ② 一键宏设置 ③ 工具箱（`Toolbox.lua`）④ 任务线 & 装备（`DataSearch.lua`）⑤ 图标库（`IconBrowser.lua`）⑥ 抓宠帮手（`PetHelper.lua`+`PetData.lua`）⑦ 子插件。
- 技能编辑窗：点 `[编]`/技能图标打开；条件逐行配置（类型/参数/删/加），关系列切 `&`/`|`；条件类型分 5 组（`CTG_5` = 队友/团员状态）。
- **队友/团员用法**：① 只配条件（`队友血量% <60` 自己扫全队取最低、切目标、记 `st.allyUnit`）；② 要自定义筛选 = 加一行 `选取目标:队伍成员`，筛选条件写在**那一行**上，按血量升序取第一个全过的；规则按顺序执行。
- **定位**：通用职业一键宏框架（技能白名单只作下拉置顶）；`/run EVAL_GO()`；`EVAL_GO(2)` / `EVAL_GO1~4()` 绑多键；技能需拖上动作条，改动后 `/eh go rescan`；`/eh war` 是旧别名。
- 调试：`/eh debug` | `/eh go list` | `/eh logdump` | `/eh ds`、`/eh ds trace`。

## 五、关键判据汇总（每条 = 一句规则 + 追溯锚点；踩坑全案见参考卷附录 R）

### 5.1 Lua / 解析
- ★★★**local 声明顺序 = 词法作用域**：引用点写在 `local` 之前 ⇒ 绑成全局 nil（运行时 `attempt to call a nil value`，**不是**语法错误）。判据：① 新段先问「它用到的东西声明在哪」；② 跨段共享件放所有使用方之前，或走 `_G[...]`/全局桥；③ 闸门 `DECL ORDER CHECK` + `ADDON DECL ORDER CHECK`。★**盲区**：按名字比对，文件内有**缩进的同名 local** 就整名跳过 ⇒ 「闸门绿 ≠ 没问题」（仍要用 `scan_dangling.js` + 真机红字反查）；比对前**先剥字符串字面量**。连踩 = **R2**。
- ★★★**工具模块必须自带 `local function L(k)`**（走 `EVAL_L`）：项目里 `L` 一律是文件局部，模块裸调 `L("…")` 会绑全局 nil，被 `pcall` 吞掉 ⇒ 「文案没设上/点击没挂」而代码看着正常。判据 = `MODULE L SCOPE CHECK`；写法照 `tools/ConsumableHelper.lua`。
- ★★★**模块只准调「全局桥」，绝不调宿主 local**：`tbCfg`/`say`/`logLine` 在模块里是全局 nil ⇒ 「读永远 false、写一次不生效、播报静默」；跨文件走 `EVAL_TB_CFG`/`EVAL_SAY`/`EVAL_LOGLINE`/`EVAL_L`，或模块自带同名 local。判据 = `MODULE HOST LOCAL CHECK`。
- ★★★**「关掉零动作」= 总开关闸在任何探测/读写之前**（1.75.7）：闸门块要**清「已应用」标记 + `return`**；「关掉时把改过的几何还回去」必须**当场做**（寄托常驻 tick = 关掉还在跑）；反向哨兵不许把功能关死。判据 = 组 230 + `SM OFF SILENT CHECK`。
- ★★★**改别人的几何前先探测「客户端自己会不会跟随缩放」**（1.75.9）：先**只读探测**（`smFitDetect`：外框缩放走一档看屏幕几何跟不跟）；只有结论 `true` 才折算，`nil`/`false` 一个几何都不碰；原值**只在自然档抓一次**（`smFitCapture` 临时 `SetScale 1`），`smFitApply` 里**绝不记原值**、`smFitRestore` **绝不清 `SMFIT.rec`**；记录键用**纹理名**（枚举序号会漂移）；开关都要收钩子（`featTeardown`）。★同案雷：模块在**文件执行期**缓存 `EVAL_HELP_CONFIG.simpleMapCfg`（那时是空表）⇒ 设置与记录一个都没落盘 ⇒ 改**懒代理**。判据 = 组 232 + `SM FIT CASCADE CHECK`；全案 **R20**。
- ★★★**世界地图「位置记忆」不许跨会话**（1.75.10）：口径 = **每次载入后第一次开图一律居中**（`FEAT.posArmed` 载入即 true），本会话内拖动后才记位置。① `featCenterOnce` **先清存档 `SM_CFG.px/py`** 再摆正中（旧值是含缩放折算出来的屏幕中心偏移，口径不符会被永久继承 = 用户看到的「乱跳」）；② 居中配**有界窗口期**（`SM_RECENTER_TICKS`，`featKeep` 逐拍重申 —— 客户端可能在我们 `featApply` **之后**才摆位置）；③ 窗口期**可被拖拽打断**；④ `featApply` 里「首次居中」**排在位置记忆之前**（顺序即判据）；⑤ `featCenterNow` 已居中就不写（读回自证）。判据 = 组 237 + `SM POS CENTER CHECK`；全案 **R20b**。
- ★★★**「探索层」的定位信息只在会话内存、绝不落存档**（1.75.4 报障 → 1.75.5 定案；用户提问原话：「这个探索层每个地区的定位是从缓存读取的吗?理论上每次打开地图都要重新计算的，不需要缓存区记录这个定位信息?」）：`WorldMapOverlay1..N` 是客户端**按序号逐图复用**的（`WorldMapFrame_Update` 每图重摆，用不到的 `:Hide()` 且**不清几何**）⇒ **同一个纹理名在不同地图上是完全不同的矩形**，而**客户端每次开图都会自己重摆**。⇒ ① 存盘只会带来脏值（旧 schema 按名字记一份 = 跨图污染，真机存档实证 8 条里 **6 条完全相同** = 把「还没布局/本图不用」的残留几何记下来了 ⇒ 用户报的「坐标丢失 + 全挤在左下」）；② 唯一必须记住的是**本会话内按图**那一份（`SMFIT.recMap[地图身份]`，切走存回/切回取出 —— 不记的话，切回时会把**折后值当原值再折一遍**）；③ 老存档里的 `mapFitOrig`/`mapFitVer` **一次性清掉**，且**不再写版本戳**（判据 = 「老键还在就丢」，天然幂等）。★另五条仍在的硬判据：**只碰本图在用**的层（`smFitInUse`：`IsShown()==false`/`GetTexture()==nil` 跳过，**读不到就放行**）· 客户端自报 `GetNumMapOverlays()==0` 就一个几何都不碰 · 抓原值要**先筛候选再动缩放 + 有界重试 1s**（1.75.4 事故：不落闩 ⇒ tick 每帧重跑、而它内部把地图缩放按 1 再放回 ⇒ **缩放每帧抖一次**、取证环 1 秒被刷满）· 折算**逐层记账**（`wroteKeys[名]=地图身份`）⇒ 还原只还本图写过的层 · ★★★**落闩判据 = 「真的读到了原值」**（用户 1.75.5 报障原话：「**/reload 载入时为什么原值为 0 也定义为原值抓取完成?这个流程本身就不对**」）：`todo` 空有**两种**来法，「目标都已有记录」才落闩；「**候选一个都不在用**（客户端还没摆版式/贴图）」= **一条都没读到 ⇒ 绝不落闩**，由 1 秒一次的有界重试等它摆出来（旧写法一视同仁 ⇒ 0 条也报「已抓到原值」+ 一个几何都不折 = 地图缩了、探索层没缩）。
  ★★★**1.75.5 起「关图即清空原值」**（用户要求原话：「**每次地图关闭都把原值数据清理,不要保存这个值.每次打开地图.都重启获取原值.重新缩放大地图**」；前一句是「每次打开地图都当做是第一次打开」+「每次 reload 载入也都当第一次」）：① **清空在关图那一刻做**（`smFitDropOnClose`，门 = 总开关 ∧ 叠加层适配 ∧ **折算档**；`closedNow = (not open) and SMFIT.open`，挡在「抓原值窗口」块之前）—— 关图时地图不可见、不闪、也不跟客户端的版式计算抢；② **顺序铁律 = 先还回自然档、再清空**，且还回要**按本档口径严格自验**（`|读回 − 原值| ≤ 0.75`；★两种读回口径在数值上长得一样 ⇒ 只信 `smFitRestore` 的宽松 `okA or okB` 会把「客户端把我们的写盖掉」放过）⇒ **验不过就绝不清理**（保留记录 + 如实播报，宁可退化成老行为，也绝不把折后的值当原值 = 折两遍）；③ `/reload` 本来就等于第一次（原值只在会话内存）⇒ 载入后首次开图必然重读；④ 真值 `SM_CFG.mapFitFresh`（**nil = 开**；`/ehm mapfit fresh off` 回退成「本会话内按图记住」）；⑤ **不折算的档不许开「先不缩放」窗口**（`smFitNeedFold()` 门；否则 nofold 的地图会白满尺寸 2 秒）。
  ★★**抓原值的播报 = 安静档（默认）+ 详细档开关**（用户先说「获取原值的地方添加日志信息,打印出来」，功能确认后说「**好的功能正常了.清理下这些调试日志**」）：
  · **安静档**（`SM_CFG.mapFitVerbose ~= true`，**nil = 关**）每次开图只留**两行** —— `抓原值：已读到 N 条原值（地图=…，第 M 次尝试）⇒ 落闩` + 本图**首次**折算的 `叠加层适配：按读回口径 0.70 对齐 N 个…`；关图**一行**（`关图：已清空本图原值 N 条、M 个折过的几何已还回自然档`）。
    ★真出问题**必须出声**（且各只一次）：`抓原值**读不到**…`（`saidFail`）· 窗口结束仍没读到（`saidEmpty`）· `关图…**没能还回自然档**` · `WorldMapDetailFrame 下没有可用纹理`。
    ★真机教训：旧写法那条「叠加层适配：对齐 8 个」**开一次图重复 6 次以上**（每次重排/重抓都再来一轮）⇒ 必须加**每次开图只报一次**的门（`SMFIT.saidFold`，与 `saidLatch/saidFail/saidEmpty` 一起在**换图**与**关图**时归零）。
  · **详细档**（`/ehm mapfit verbose on`，真值 `SM_CFG.mapFitVerbose = true`）才上屏：第 N 次尝试（入口行）· **逐条原值**（`读回 ÷系数 ⇒ 原值 ｜ 锚点`）· 逐次小结（记几条/读失败几个/归一系数/落闩）· 每次折算细节 · 窗口开/收 · 「候选一个都不在用 ⇒ 不算抓到、1 秒后重试」。★详细档**不跨会话**（与 `mapFitMode` 同族：诊断用、忘了关就一直刷屏 ⇒ `EH_SM_MODEGUARD` 在 `VARIABLES_LOADED` 一并清掉）。
  · ★两档都走**同一个出口族**：`smFitSay`（常开档：`EVAL_SAY_FORCE`，**不受「调试日志」闸门管**）/ `smFitSayV`（详细档）；**两档都进 `mapFitTrace` 取证环**（安静档只是不上屏 ⇒ `/ehm mapfit trace`、`mapFitCapLog` 事后一律查得到）。
  · ★窗口收口措辞**必须与实际条数挂钩**（0 条时改说「还没读到」——真机出过「0 条也报『已抓到原值』」）。
  · ★同族：`/ehm fitnow`（别名 适配/修正）= 手动适配全过程五步逐步打印（`ShowUIPanel` 开图 → 置自然档 1.00 → **等满 2s** 才读原值 → 逐条打印原值 → 套缩放并打印「设置值/自身 GetScale/父链连乘」→ 折算并逐条打印「原值→写入」），期间 `smFixActive` 让自动逻辑**整段让位**、跑完（**出错也**）必放掉 —— 它属于**用户主动触发**，不受安静档限制（只在敲命令时打）。
  ★判据/断言组（组 253~256、`SM MAP KEY CHECK` ⑯⑰⑱）**已随 tests/ 删除** ⇒ 现在靠**取证命令**：`/ehm mapfit dump`（只读清单 + 最近 10 次抓原值小结）· `/ehm fitnow`（手动五步）· `/ehm mapfit verbose on|off`。全案 **R20c/R20d**。
- 多字节字符禁入 Lua `[...]`（按字节匹配）、`|` 非交替：`[:：]` 会吃掉「：」首字节 ⇒ 解析全线静默失效 ⇒ 入口 `colonNorm()` 归一。★`string.sub` 也按**字节**取（前缀判据写错 = 命令静默失效）。
- 模式里 `%` 是转义符（`%.`/`%%`）；plain 模式找 `%` 写 `"%"`。方括号成对解析用 `[^%]]-`（半/全角分匹配）；空集 ≠ 没写。
- 主 chunk ≤200 局部队变量；`do...end` 不开函数作用域；`ipairs` 遇 nil 即停。
- `cond and f() or fallback` 在 `f()` 返 false 时恒取 fallback ⇒ 分两步写。
- 空串是真值（`""` 也算有键）⇒「键存在」≠「有内容」；`string.len` 是**字节数** ⇒ 宽度按字符估。
- ★★★**OnUpdate 回调「一个参数都不传」**：回调**一律零形参**，dt 只能从全局 `arg1` 取。判据 = `ONUPDATE ARG CHECK`（★盲区：间接注册 `pcall(f.SetScript, f, "OnUpdate", h)` 正则抓不到）。★测试要注入 dt 必须走 `EVAL_TEST_FIRE_UPDATE(frame, dt)`（设 `arg1` → 零参数点火）；`pcall(f, dt)` 对零形参回调**等于什么都没传**（dt 静默退回 0.05，1.75.1 组 204 点红即此）。

### 5.2 静默失败族（数据 / 序列化 / 开关）
- ★★★分享「自我回声」必须锚在**发送者是我**（`shIsSelfEcho(sender)`，剥色码/后缀），**不能锚在「内容像我」**（会误杀别人同款方案不弹窗）；组 82 + 变异 M569/M570；★「按日志判没发生」≠ 真没发生（日志是环缓冲会覆盖）。全案 **R1**。
- 分享分片取证：`SH.dbgChunks`（环形 8 条）在 `shOnMsg` 各分叉点记原文+走到哪步（`/eh go 分享事件` ⑤ 摊开）。★`IsEventRegistered` 返 **`1` 不是 `true`** ⇒ 判据写 `(r == true or r == 1)`。全案 **R1**。
- 具名帧顶掉同名全局函数 ⇒ `type(X)=="function"` 不成立 ⇒ 命令静默失效；桩须把具名帧挂全局；`FRAME NAME CLASH CHECK`；组 54。
- 分享接收：>2s 未收齐如实提醒但不删缓冲；>60s 才丢；只认 `[EHPF#<id> i/n]<hex>`；组 106/107。
- **「查不到」≠「没有」**：查不到必须如实报错，否则 `cnt=0` ⇒「否/无」成立 ⇒ 规则无限重放刷屏。
- 静默丢弃 = 那行变无条件施法 ⇒ 写几条成员条件解析后就必须几条。
- **导出形态与解析侧必须成对验**（读不回 = 导入即丢条件）；「有过滤」≠「过滤得住」。
- ★★★**聊天输出总闸门 = 配置项「调试日志」(`cfg.log.on`)**：关掉 ⇒ 插件**一个字都不往聊天框刷**（模块 say 全委托 `EVAL_SAY` ⇒ 一处门控全生效），且 `logLine` 一个字都不记；★闸门在**第一次输出之前**；★关掉必须留**看得见的回头路**（开关自己的确认行 + 「引擎未加载完整」兜底走常开的 `EVAL_SAY_FORCE`）。`cfg.wdebug`（「方案技能日志」）是更细一层、**不是**总闸门；自建打印口的模块读 `EVAL_CHAT_ON()`（有意例外：子插件 `EH_DebugBox`）。判据 = 组 231 + `CHAT GATE CHECK`；全案 **R19**。
- 判据表照客户端真实文案抄；「尝试过」≠「挂上了」⇒ 载入即挂必须失败重试。
- 按序号做键的表删中间项要整体左移（`bindKeys`/`bindSlots` + `SaveBindings`）；组 131。
- function 不是 table（身份判定用 `cur == TB.chanWrapper`）；标记只加显示串；「还原/撤回」≠ 回退到有 bug 状态。
- 借别人的 UI 对象 = 静默破坏界面：`local WTT = GameTooltip` 读会清空玩家 tooltip ⇒ 自建 `EVAL_HELP_WTT` + 守卫 `EVAL_WTT_MAY_READ_PURE`；`WTT ISOLATION CHECK`；组 126。
- 「写成功」≠「写进去生效」：`frame.AddMessage=wrapper` 会被吞 ⇒ 写完**读回确认**（`_G.ChatFrame_OnEvent ~= wrapper`）＋改挂普通全局函数入口（新文本回写全局 `arg1`）；`CHAT COLOR WIRING CHECK`；组 123/124⑧。
- ★★★**「配好了却看不见」= 贴图口静默失败 + 兜底被自己盖住**（1.75.10 用户报障「插件配置的图标……黑色的没有图标」）：① **症状定案手法 = 截图取色**（`#1D180E` ≈ 按钮创建时的 `WHITE8X8×(0.12,0.10,0.06)` ⇒ 那是「一次都没贴上过」的暗底，不是「贴了张黑图」）；② 贴图口必须**读回自证**（`GetTexture()` → `mbBack`）＋**alpha 还原**；③ 兜底必须**真的看得见**（金框在 BACKGROUND、暗底是不透明 ARTWORK ⇒ 不透明掉暗底；每次进兜底把「EH」字写回）；④ **一次性载入接线不可靠** ⇒ 自愈口 `EVAL_HELP_MB_RETRY`（**已贴上就早退**）+ 两个时机（`PLAYER_ENTERING_WORLD`/悬停）；⑤ 探针 `/eh go mbicon` + **专属有界落盘** `cfg.mbProbe`（`say` 不落日志环 ⇒ 探针不自存一份 AI 读不到）。判据 = 组 238 + `MB ICON WIRING CHECK`（变异 12/12；教训：检查一律「标签 + **紧跟的取值表达式**」一起匹配；「只建空箱子」要钉 append 那行）。全案 **R22**。
- ★★★**默认图标 = 头龙**（用户定稿：「头龙 配置为插件默认图标」）：`EVAL_HELP_MB_PICKICON` 第一条 = **`^INV_MISC_HEAD_DRAGON_01`**（宏图标 **670**），力量祝福第二顺位；★`_01` 尾号是判据（BLACK/BLUE/Bronze/Green **不算命中**，组 95 有反向哨兵）；★**旧自定义一次性清掉**（只清 `INV_Misc_ShadowEgg_TEX` 那一个确切值 + 如实播报）⇒ 否则用户永远看不到头龙。判据 = `MB ICON WIRING CHECK ⑨`。
- ★★★**改属性前先把「原始值」读下来**：宽/高这类没有系统默认值的属性，重置只能靠「第一次改之前记下的原值」⇒ 读原值→写新值→读回自证，**顺序不许换**；原值缺失时**如实说「无法还原」并保留字段**（绝不拿当前值冒充）。组 206 三变异全捕获。
- 深入 API：`GetChatWindowMessages`/`RemoveChatWindowMessages`/`AddChatWindowMessages` = 官方「某类消息不显示」开关（**组名不许猜**）。
- 分享行形态：只有「一段色码 + 链接」能画 ⇒ 色码打头 + 带链接 + 每条一段 8 位码 + 间隔 ≥1s；色清单从 `SH_CHUNK_COLOR`/`SH_SEAL_TIERS`/`SH_TITLE_COLORS` 现取；组 144/158/159。
- ★1.73.24~41 弹窗/菜单/滚动条细则 → **R11**。

### 5.3 测试与断言
> ⚠️ **本节整体作废（2026-09-26）**：用户定案「**删除tests/下的文件.也不需要测试**」⇒ `tests/` · `test_assert.lua` · `test_engine.js` · `check.js` · `mutate.js` 已全部删除，**以下内容只作历史记录**：当年设计判据的思路（桩的坑、夹具自清、变异验证、载入顺序、握手对账…）仍然值得一读，但**这些文件已经不存在、也没有任何自动判据在跑**。现行的唯一闸门 = `node luacheck.js`（语法），其余靠自查 + 真机实测（见铁律 1）。
- ★桩默认值也属桩（真帧默认显示、桩 `shown=false` ⇒「没 Hide 却断言 `IsShown()==false`」恒真）；隐式前置改显式建立；桩要记每状态。★★**桩的帧 mock 对未知键返回函数**（truthy）⇒ 判「是不是我们的控件」必须 `字段 == true` / `rawget`。
- 测试够不着生产 local ⇒ 加钩子走**真实** OnEnter；桩对无效调用要如实无效；tooltip 桩 = 另建对象 + 真 GameTooltip 记账 + 普通 table。
- ★★★**改了夹具 `TEST.*` 之后必须 `EVAL_HELP_UPDATE_STATE()` 再用**：`condOne` 读**状态表 `st`**（一次刷新各处只读）⇒ 只改 `TEST.*` 不刷新 = 断言看旧值（组 240 第一版即此）。判据 = 「被测代码读的是 `st` 还是桩」。
- 断言打**真实调用点/入口** + 反向哨兵；模块级状态入 `EVAL_TB_TEST_RESET_TIMERS`（文件末尾，否则 `DECL ORDER CHECK` FAIL）；「没执行」≠「没入队」；写死布局常量 = 测自己 ⇒ 用读值口（如 `EVAL_TEST_CFG_LAYOUT()`）。
- 期望值不许用语言包/不许同源自比 ⇒ 字面或绝对值夹具；颜色三通道一起比；夹具走真实解析入口。
- 变异：锚点唯一定位（整行 / 命中==1 / 摘 CR / 语法合法）；还原用运行前内存原文（绝不 `git show HEAD:<file>`）；判捕获看退出码 + 文本。
- ★★★**「测试文件存在但没人跑」是头号静默失效** ⇒ 跑到底握手（`EVAL_TEST_MOD_DONE`）+ 文件数对账 + `TOOL TEST FILES CHECK` + `DF GROUP ROSTER CHECK`（组号集合/升序/每组有真 `eq(` 与 PASS 收尾 —— 「整组被删/掏空」只有它抓得住）。
- ★★★**检查文件（`tests/checks/*.js`）导出函数里不许有顶层 `return`**（写成 `return (function(){…})();` ⇒ 后面追加的检查全是死代码，看得到、从不打印）；判据 = `TOOL TEST FILES CHECK` 的「顶层 return」。
- ★★★**测试里不许有「跳过分支」**（`if 条件 then 断言 else eq(true,true,"跳过") end` = 静默逃生口）⇒ 前置一律**断言存在**。
- ★★★**读值口按「稳定键」找条目，不许缓存条目对象**（列表重扫整体重建 ⇒ 缓存的对象全失效，采到假数字还不报错）：按**帧对象**找、「行里的条目指向哪个帧」、跨重扫在同一代重取。
- ★★★**harness 载入清单里 `test_assert.lua` 必须排在所有 `tools/*.lua` 之后**（工具模块载入期自登记模块行，而断言走真实渲染路径取它）；判据 = `TEST LOAD ORDER CHECK`。★同一机制第二个后果：`test_assert.lua` 里**任何一条断言抛错 ⇒ harness 立刻 exit 1**，排在后面的 `tests/tools/*.lua` **整批不跑**（「修好一个红点冒出下一批」不是新 bug）。

### 5.4 UI 与布局
- ★★★标题栏（两窗同实现）= 玩家名→头衔→品阶徽标→方案名 + 右侧两开关；两窗各自 BUILD + tick 刷；头衔取 `EVAL_TITLE_CURRENT()`；色码→RGB `EVAL_COLOR_RGB`；CHECK `UI TITLE*` 四道；组 162/163/164/166/168。
- ★★品阶唯一源 `SH_SEAL_TIERS`（≤11 普通 / 12-23 稀有 / 24-35 珍稀 / 36-49 绝版 / **≥50 神级 = 亮蓝 |cff00bfff**）；`SHARE PALETTE CHECK` 守色码不重复；组 143/146/147/195/196。
- ★★★**评分口径**：`EVAL_PROFILE_SCORE` = Σ(每条)[有条件 ? 1+Σ条件权重 : 0]，空技能 0 分；权重 **自身/技能 1 · 目标/光环 2 · 队伍/候选 3**（`SE_TYPE_GROUPS` 的 `w`/`cov` 是唯一来源）；单条上限 12；同一行完全一样的条件只算一次；`EVAL_NO_SLOT_OK` 的技能无条件**保留 1 分**。
- ★★★**覆盖封顶**：覆盖 1/2/3 个大类封顶 **23/35/49**（从 `SH_SEAL_TIERS[n+1].max` 现算），**≥4 类才不封顶** ⇒ 神级必须跨类；带方案表的调用点一律走 `EVAL_PROFILE_TIER(p)`（coverage 传 nil = 不封顶）；`COVERAGE CAP WIRING CHECK`。
- ★★★**头衔晋升**：`SH_TITLE_REQ = {1,2,3,3,2}` + 逐级满足；★命令/闸门/样例的分数**一律现算**（`EVAL_SEAL_GOD_SCORE()`/`EVAL_SEAL_TIER_SAMPLE(i)`），不写死（旧口径 **R3**）。
- ★★★**配置分角色存**：角色级存档 `EVAL_HELP_CHAR`（toc 有 `## SavedVariablesPerCharacter`）；**角色键唯一来源 = `Toolbox.lua` 的 `TB_CHAR_KEYS`**；`tbCfg()` 是路由代理 ⇒ 上百处 `tb.xxx` 一行未改；★★代理 `__index` **绝不能写 `at and at[k] or nil`**（`false or nil` 仍是 nil ⇒ 用户关掉的开关自己又开）。判据 `SAVEDVARS SPLIT CHECK` + 组 79/197。
- ★★★**图层树的层级只能来自「扫描时写下的层号」**，不许数路径里的 `/`（缩进与层深过滤同一口径）；折叠 `ui.treeCollapsed[路径]` 落存档；层深唯一写入点 `uiDepthApply`（`0` = 一个标记都不清）。判据 `DBX TREE WIRING CHECK` + 组 205；**R15 ④**。
- ★★★**「算出来却写进一个从没被创建过的控件」= 静默死代码**：`if ui.X then` 守卫让「控件名写错」与「条件不满足」长得一样 ⇒ ① 写完 UI 文案先问「这个控件存在吗」；② 这类坑行为断言照不到 ⇒ 用源码检查钉（凡被写入的句柄都要有**赋值点**）。
- ★★★**滚动模式唯一标准（连续窗口）**：范式 = `PetHelper.lua` ≈566~595 —— `off` = **行偏移**、双侧夹 `0..max(0, n-cap)`；滚轮**逐行**；滚轮**链式接管**；按钮一屏但夹到 `maxOff`；容量 `cap` **恒定**；计数器常显；切分优先组边界。**禁止**整页跳/变长页/覆盖式接管滚轮。判据 = 组 120 + 组 201；读值口 `EVAL_TB_TEST_WHEEL/WHEEL_PREV/LAYOUT`（不许复刻映射逻辑）。三段布局（计数器←8px→按钮组←10px→关闭 · 几何唯一源 `EVAL_HELP_CFG_BOTTOM()`）→ **R15 ⑥l**。
- ★★★滚轮方向唯一源 `EVAL_WHEEL_DIR(a,b)`（归一 ±1），6 处全走它；`WHEEL DIRECTION CHECK`（禁位移与方向同号）+ 组 115；★断言把方向写反 ⇒ 反向 bug 被「验证」通过。
- ★★★**数据刷新不许改可见性**：`EVAL_WAR_TAB_REFRESH()` 是数据刷新却被开配置窗/`EVAL_PM_APPLY` 调用 ⇒ 可见性只由 Tab 切换负责（`EVAL_HELP_CFG_SETTAB` 的清单）；数据照旧每次刷；组 165 + `EVAL_TEST_WAR_ROWS()`。
- ★★★**列表「文本压到下一列」= 那一格从来没设过宽度**（1.75.10 用户截图）：症状 = 技能名与条件列叠成一串糊字；根因 = 名字格只锚 TOPLEFT 没设宽度（自动伸展），条件列钉死 `RX2+102`。判据：① 两列各自**明确宽度**、条件列起点 = 名字格右缘 + gap（单一来源）；② 条件列右缘停在进行内按钮带（`W−88−16`，读**真控件 ▲** 的锚点算）左边；③ 超长**截断补 `…`**、短文本**逐字不变**。★★★**截断按「字符」算宽，绝不按字节**（一个汉字 3 字节 ⇒ 按字节会把「测试技能」算成 12 单位，组 111⑤ 的「测试技能(等级 2)」当场被截成「测试技能(等…」）：`uiClip(s, maxUnits)` 按 UTF-8 首字节判字符长度（≥0xF0→4 / ≥0xE0→3 / ≥0xC0→2 / 否则 1），汉字 1、ASCII 0.55。**完整内容交给悬停提示**（列宽固定 + 悬停给全）：热区 = **覆盖文字的透明 Button**（FontString 不吃鼠标）；`OnEnter` 复用既有 `TIP_ON/TIP_OFF/TIP_COND_H/TIP_NOCOND`，只有操作提示另立 `W_ROW_TIP`（战斗UI 的 `TIP_CLICK` 不许共用）；★★热区**必须进页控件清单 + 每行 widgets 清单**（否则切 Tab 后**在别的页面吃鼠标**、空行会弹上一行 tooltip）。判据 = 组 244。
- ★**视图切换/入口控件/分列切点/工具箱两列/弹窗高度自适应/职业着色/聊天窗名字着色/主动查询四闸门** → **R12**/**R15**。
- ★★★**索引「任意全局」/走父子链的扫描**（动手前看 **R15 ⑥k**）：① 索引前先过守卫（不可索引的 userdata 会抛错并**打断整个探针**；只收 `GetObjectType()` 报 Frame 的）；② **匿名窗口 `_G` 扫描永远看不到** ⇒ 只能 `GetChildren()` 父子链 + 具名子件当指纹；③ 真机存档**带 BOM**、`a and f()` **只保留第一个返回值**、桩里 `unpack` 在 fengari **不存在** ⇒ 都表现为「静默取不到值」。判据 = `DF GLOBAL SCAN GUARD CHECK` + 组 209/211/213。
- ★★**判定「别人的帧」用对象身份、别用名字**（`GetName()` 可能 nil）⇒ 比对象（`p == rawget(_G,"UIParent")`）；组 209⑤ + `DF BARS WIRING CHECK`；哨兵做法 **R15 ⑤**。
- ★★★**框拖拽 / 图层工具判据总表**（完整写法与踩坑 → **参考卷 §十六**）：① **图层选择**名单：真值 `dragFrames.pick[名]=true`（**表不存在 = 全选**）；唯一写入口 `EVAL_DF_PICK_SET`（★**首写先物化全选快照**，否则一次取消勾选 = 其余几十层静默全关）；判据 = 组 214 + `DF PICK WIRING CHECK`。② **窗口图标/头部拖拽带**：图标 = **346 号宏图标**（按号现取，取不到退回「配」）；**左键只拖窗口、属性窗挂右键**；判据 = 组 212/215 + `DF ICON ART CHECK`。③ **位移一律「按屏幕算 + 量回自证」**：`base.l/base.b` = 拖前实测屏幕位置；落锚唯一入口 `dfPlaceFrom`（首猜按 `GetEffectiveScale` 折算 → 量回 → 手量折算修正）；★必须**解仿射**；判据 = 组 217①~⑦。④ ★★★**宽/高只对「聊天窗」开放 + 持久化**：唯一真值 `dfSizeOK(name)`（`^ChatFrame%d+$` **只许出现一次**）⇒ 目标表项 `noSize` 由它现算；读它三处 = 属性弹窗（聊天窗**建并显示**宽/高 + `DF_POP_H_SIZE`；其余 **Hide** 不是灰掉）· `dfAttrsApply` 的 `allowSize` 门（没给 tgt 按不允许）· 启动清理（**只清 `noSize == true`** 的并还原 `ow/oh`，没原值不去猜；聊天窗 w/h 一个字段都不动）；★顺序铁律 = **先抓原值 → 再写新值**。判据 = 组 206/208④⑥/220/222 + `DF OPEN HOOK CHECK`。⑤ **图层隐藏**（1.75.x 由「图层特殊处理」改名；★**改名只动语言包显示值 + 模块内 say 前缀**，键名 `TB_DFFIX` / 模块名 `LayerFix` / 存档键 `layerFix.fix` 一个都不动）：真值 `layerFix.fix[key]`（★**表不存在 = 一条都不选**，与 pick 相反）；三处执行（勾选当场/载入期/有界复查到点摘脚本）；层不在或对象数不够 ⇒ 一个都不动 + 如实播报；判据 = 组 223 + `LAYER FIX WIRING CHECK`/`TB MOD ROW CHECK`。⑥ **工具箱模块行的配置项只在 `[设置]` 悬停里显示**（行上不许重复，模块行必须 `r.extra:Hide()`）；判据 = `TB MOD ROW CHECK ④`。⑦ ★**「柄」按池位号复用** ⇒ 验「某目标有没有柄」要按**目标名**查当前**显示中**那条；★同一带上两个控件 = 遮挡（断言盲区）。
- ★★★队伍菜单三条条件：**邀请队伍** = 对方不在我队伍/团队 且（我不在队伍 或 我是队长）· **踢出队伍** = 我是队长 且 被右键的是队友 · **离开队伍** = 在队伍内显示（`LeaveParty()`）；队长 = `IsPartyLeader()` 或 `IsRaidLeader()`（助理踢人无 `IsRaidAssistant` 可判 ⇒ 如实接受边界）；成员判定 `EVAL_TB_NAME_INMYGROUP`（party 只扫 1..4）。组 130⑥e/⑥e3 + 组 173；变异 M564~M568；定案 **R5**。
- ★★★技能格按键分派：战斗信息UI 技能小图标 **左键 = 切换启用/停用**（写 `r.enabled` **配置真值** + 如实播报 + 双刷新 `EVAL_WAR_TAB_REFRESH`/`EVAL_HELP_UI_TICK`）· **右键 = 技能配置弹窗**（开被点那格、不动状态）；格子必须注册 `RightButtonUp`（光注册左键 ⇒ 右键永远到不了分派代码）；读值口 `EVAL_TEST_UI_CLICK_CELL`/`EVAL_TEST_SE_SHOWN`；`UI CELL MOUSE CHECK`；组 174。
- ★两道杂项检查（改了对应区域必须继续过）：**`COND WEIGHT CHECK`**（新条件类型必须进 `SE_TYPE_GROUPS` 的某个 `ids`，否则权重漏计）· **`GO ALIAS UNIQUE CHECK`**（`/eh go` 别名不许两家共用，`go icons` 曾撞车）。★品阶显示现算等细则 → **R15 ⑦⑧**。
- ★布局总纪律：需求验**性质**不验数字；同一行中线对齐；中文宽度按字符数估；布局常量单一源（`IO_BW/IO_GAP/IO_PAD`、`CLOSE_LEFT/CLOSE_MIDY`）。

### 5.5 API 与客户端事实
- `SpellStopCasting()` 覆盖读条/自动射击/魔杖；**Protected** ⇒ 须 `RunScript`；「进度条没了」≠ 取消。
- `AttackTarget()` = Toggles 须先 `IsCurrentAction(攻击格)`；Movement 仅 `FollowByName`/`FollowUnit` 非 Protected；`FollowByName` 空名 = 当前目标、只搜已知玩家、无返回值、不走 RunScript。
- `GetRaidRosterInfo(i)` 九返回；越界/非团队回 nil。
- 1370 API **无 aura 专用函数**；`GetPlayerBuff(i,f)` = 增益条 **0 基**下标；**无文件读取 API** ⇒ 载入唯一形式 = 列进 `.toc`；★`LoadAddOn` 是 **Protected** ⇒ 不能文件级懒加载，只能「toc 预载 + 载入期零副作用 + 首用才建帧」（范式 `tools/HunterHelper.lua`）。
- `GetQuestReward` 会再触发 `QUEST_COMPLETE` ⇒ 三层防护（同名去重/领取窗口闸门/全局频率上限）；`UnitDebuff` 第 3 返回 = dispel token；`UnitMana` 有显示缩放（怒气÷10、幸福÷1000）⇒ 判蓝量前先 `UnitPowerType(unit)==0`。
- **施法 API 全 Protected**（`CastSpellByName` 仅 onSelf/CastSpell/SpellTargetUnit/SpellStopTargeting/SpellStopCasting）；**`TargetUnit` 非 Protected = 唯一安全路径**（切目标 → `UseAction(slot)` → 还原）。
- ★★★`CHAT_MSG_PARTY_LEADER`/`CHAT_MSG_RAID_LEADER` 是**独立事件**：接收帧**必须也注册**（只注册 `CHAT_MSG_PARTY`/`RAID` ⇒ 队长一分享**一片都进不来**，且静默）；来源判据 = 触发事件名；发送侧只留 公会/队伍/说；自查 `/eh go 分享事件`；`SHARE RECV EVENTS CHECK`；组 175。
- ★★★**黑幕（`WorldMapBlackout` / `BlackoutWorld`）遮蔽要两手，缺一不可**（缩放大地图，1.75.5 用户三连： 「地图每次打开.会闪烁一次背景黑幕?这个如何避免?」→「能否直接设置黑幕透明度是0」→「然后关闭地图不要恢复这个背景的透明度」）：
  ① **`SetAlpha(0)` = 硬抗闪**（客户端每次开图都会自己 `Show` 它、而且**在我们之后** ⇒ 只 `Hide` 的话「开图→藏住」最多空 0.2s = 那一下黑闪；alpha 已 0 则即使被 Show 出来也是全透明）；
  ② **`Hide()` 必须保留 = 保鼠标** —— ★「**显示着但透明的全屏帧照样吃点击/悬停**」⇒ 只归零 alpha 会让**地图点不动**（比黑闪更糟；源码检查有反向哨兵）；
  ③ **有界瞬时窗口**：开图那一拍起 `SM_BLACKOUT_SEC`(**0.6s**) 内**逐帧**重申（与「开图后逐拍重申居中」同一手法）⇒ 窗口一过回 0.2s 节拍；
  ④ **关图不还原**（用户明确要求）：关图只失效窗口，**不写** alpha、不写地图帧的透明度/缩放/位置（客户端下次开图自己 Show，而它保持 alpha=0 ⇒ 下次也不闪）；
  ⑤ **只有关功能才还原**：`featBlackoutRestore` 唯一调用点 = `featTeardown`；★**改属性前先抓原 alpha**（`FEAT.boA[帧名]`），读不到就记 `false`（关功能时如实说「无法还原、保留现状」，**绝不拿 0 冒充原值**）+ 归零后**读回自证**；
  ⑥ 动作**单一出口** `featHideBlackout`（featApply / featKeep / tick 瞬时窗口三处调用）；取证行 = 「黑幕遮蔽：开图后 N ms 藏住 M 层」（进 `mapFitTrace`，详细档上屏 ⇒ 不闪了可量化确认）。★原先的 `SM BLACKOUT CHECK` **已随 tests/ 删除** ⇒ 只剩真机看「开图还会不会闪」+ 那条耗时取证行。
- 纹理路径 = `/Game/Interface/Icons/<名>_TEX`（写错显 ?）；`GetNumMacroIcons`/`GetMacroIconInfo` = 唯一合法路径入口（本机 1033 枚，`doc/图标路径清单.txt` 1018 条且**按字母排序 ⇒ 行号 ≠ 宏图标号**）；`PET ICON CHECK` 校验真存在。★IconSem.lua：基础名须剥 `_TEX`；纹理字面量须在白名单；两反斜杠须按两反斜杠匹配。
- `api_*.html` = 1370 条索引；**无**：`PlaySoundFile`（只有 `PlaySound`）/`hooksecurefunc`/`Frame:HookScript`/`UIDropDownMenu_GetSelectedID`；**有**：GuildRoster/Who/Friend/NumGuildMembers/NumWhoResults/NumFriends/GuildControlGetNumRanks/GetRealZoneText/RemoveChatWindowMessages/`GameTooltip:SetMinimumWidth`。★`GetWidth`/`GetHeight` **含缩放**（384×512 + 0.7 ⇒ 268.8×358.4）⇒ 与未缩放配置值直接比会假报不符（**R15 ⑥d**）。
- ★★★**帧名未知的层（候选名解析 + 探针）与「按需出现」的层**：帧名只能**现场探**（UI 编译在 pak 里）⇒ `cands` 候选表 + 唯一解析口 `dfTargetFrame` + 探针 `/edb bars`（先报队友/团员数；单人时候选全不在是正常的）；候选全落空就**如实缺席**（`DF BARS WIRING CHECK` + 组 207）。★**解析到 ≠ 补上了**：队伍/团队框「按需出现」⇒ 配**事件驱动**跟随 `DF_ROSTER_EVENTS`（★`GROUP_ROSTER_UPDATE` 不许当注册依据；1.75.1 起 + 宠物动作条 · 事件 `UNIT_PET`）→ 出现即 `dfApplyOne` + 重贴柄；**有界** `DF_ROSTER_TRIES`（不做常驻轮询）；判据 `DF ROSTER WIRING CHECK` + 组 208；细节 **R15 ⑤/⑥d**。
- ★★★**跨插件：捕获 UnrealQuest 稀有提醒 → `tools/RareWatch.lua`**（主文件只两处接线：VARIABLES_LOADED 的 `pcall(EVAL_RW_INSTALL)` + `/eh go 稀有`；开关单一来源 `EVAL_RW_ENABLED/SET`）：捕获点 = 包住对方弹窗唯一出口 `RareAlert:Show(...)`（**安装必须等 VARIABLES_LOADED**）、返回值逐个透传 + 抛错照原样 `error(a,0)`、兜底轮询 `GetStatus().alerts`（tick 父级必须 **WorldFrame**）；名字按品阶染色且整条**只许一段 8 位色码**；点名字 = 一次 `TargetByName` **并核对**，「选不到」要同时报距离+下一步。判据 = 组 199 + `RARE WATCH WIRING CHECK`（反向守「不许再耦合地图机制」）；**新增文件要同步 9 处清单**；全案 **R4**。
- ★★★**任务线（明细 → 参考卷 §十四）**：数据以 `database.emberveil.org/quests` 为准；`quest/QuestData.lua` 是**生成物**（改 `chains.js` → `node quest/build.js` 重建，**绝不手改**）；列表 cap=0 全量 + 跨块统一排序；系列记录单一来源 `qcSeriesRec`；等级档 **L6=60+**；缺图占位 = **宏 961**；请求队列按列排 + 请求泵**常驻开启**（弹窗 Hide ⇒ OnUpdate 停摆）；判据 = `QUEST TOC CHECK` + 组 191/192；**闸门 = `node check.js`**（`--full` 另加 `quest/audit.js`）。★**步骤名判据 = 不在「进包任务表」**（不是「列表页」），反了会把「有页但无装备奖励」的步骤名丢光；闸门 = **audit H 段**（解析生成物，阈值 0；先确认表形态 `s` 是**序列**，按错形态 ⇒ 0 条 = 假绿）。★**同一个名字坑有两层**：生成期按「进包任务表」判 + **运行期必须把名字传下去** ⇒ 修一处不算修好；判据 = **组 228**。
- ★★★**条件类型「目标死亡」**（`kind = "bool"`，取值 `st.tDead`）：布尔类不需要新 UI，但要改**五处**：`SE_TYPES` · **CTG_2 的 `ids`** · **三语 `CT_TDEAD`**（标签是运行时拼键 `L("CT_"..upper(id))`，静态 `LANG KEY CHECK` 扫不到 ⇒ 靠逐语言无缺键/无重名断言）· `condOne` 求值 · `EVAL_COND_STR` 与 `COND_BOOL` **成对**。★取值由 Core 的 `UPDATE_STATE` 用 `UnitIsDeadOrGhost("target")` 填，**没有目标时被显式清成 false**；★★口径与「目标存在/可攻击/可流血」一致：**没有目标时「否」成立**（要「必须有目标且已死」就再配一条「目标存在 = 是」，要如实告诉用户）。判据 = 组 241（含真实点击翻转 + 求值四态 + 文本往返）；变异 6/6。★读值口：布尔类的是/否在 **`row.valBtn`**，与 pname 用的 `row.immBtn` 是**两个控件** ⇒ `EVAL_TEST_SE_ROW_VAL(i)`/`EVAL_TEST_SE_CLICK_VAL(i)`。
- ★★★**条件类型「目标玩家:X」**（`kind = "pname"`，名字存 `cd.nm`；用户要「名称支持自定义输入」+ 是/否）：**注册四处**（`SE_TYPES` · **`SE_TYPE_GROUPS` 的 CTG_2 `ids`** · **三语 `CT_TPLAYER`** · `SE_TN_PLAYER` 输入框标题）；编辑器复用 `row.skillText`/`row.sHit`（点它 → `EVAL_TN_OPEN`）+ `row.immBtn`（★三个控件进 `row.all`，进分支前已统一 Hide ⇒ **必须逐个 Show**）。求值：**未填名 / 无目标 / 无 `UnitIsPlayer`** 全部 `return false`（★**「否」方向也要失败**，否则「查不到」被当「不是他」放行）；名字比对**大小写不敏感**；`UnitIsPlayer` 返 **nil = 非玩家**。文本：`目标玩家:X` / `目标不是玩家:X`（英文 `tPlayer=`/`notplayer=`；`!` 也认）；**空名 = 写法错误 ⇒ 整条丢弃**；导出侧空名写「未填」。★★★**踩过的坑**：`condOne`（≈2173 行）里调 `condTrim`（≈3506 行才声明的 local）绑到的是**全局 nil** ⇒ 走全局桥 `EVAL_COND_TRIM`（`DECL ORDER CHECK` + 运行时红字当场抓到）。判据 = 组 240；变异 7/7。
- ★★★**追踪状态（草药/采矿/野兽/人型…）只有三条 API，没有枚举接口**（全案 **R18**）：① `GetTrackingTexture()`（Mapping）= 当前追踪图标纹理，什么都没追踪 = nil；② `GameTooltip:SetTrackingSpell()`（走**自建隐形 tooltip** `EVAL_HELP_WTT`）= **唯一**能拿「是哪种追踪」**本地化名字**的入口；③ `CancelTrackingBuff()`（Buff）取消。★三条**都没有 Protected 行** ⇒ 可直接调；而 `CastSpell`/`CastSpellByName` 是 Protected ⇒ **开追踪只能走动作条 `UseAction(slot)`**。**不存在** `GetNumTrackingTypes`/`GetTrackingInfo`/`SetTracking`；**小地图圆点无法枚举**（Minimap 只有 `SetBlipTexture`/`SetIconTexture`）；**事件名官方未公开** ⇒ 只能实测（别抄 pfUI 的 `PLAYER_AURAS_CHANGED`）。官方另两条：`GetPlayerBuff` **skip** hidden/tracking auras、Buff 页明文「Tracking auras are not listed here」⇒ **光环路线只能当旁证**。★★真机形态：`GetTrackingTexture()` 返 `/Game/Interface/Icons/<Base>_TEX.<Base>_TEX` ⇒ `EVAL_TRACK_BASE` 取最后一段后**只认第一个「.」之前**；纹理→种类一律 **剥壳归一 + 全等比对** `TRK.hint`（**不许子串匹配**：`INV_Misc_Flower_02` 会假命中 `..._02_Copy`），表由 `TRACK ICON CHECK` 钉在本机图标清单上。★落成条件类型：`{ id="tracking", kind="track", s="any" }` 归 CTG_1，求值唯一入口 `EVAL_TRACK_MATCH(id)`（内部按纹理缓存 ⇒ 贵调用只在追踪变化时做一次）；导出走 id（`追踪:beast`/`未追踪:beast`）、界面走本地化标签；认不出**整条丢弃**。★★两个坑：① **函数名以 `L` 结尾 + 字面量参数**（`EVAL_TRACK_LABEL("any")`）会被 `LANG KEY CHECK` 当成语言键 ⇒ 走局部变量；② `EVAL_DD_OPEN` 的 `opts.selected` **只在 `multi = true` 时生效**（单选要自己加标记）。判据 = 组 229 + `TRACK ICON CHECK`（查键前**先剥注释**）；取证 = `/eh go 追踪探针`/`监听`/`表`/`存档`；组 189。

### 5.6 内容 / 数据质量
- ★★★**助手弹窗候选按物品类型过滤**：判定收在共用件 `EVAL_IG_ITEM_KIND`（三级早停）；★**判不出就不剔**；★★**只在「弹窗候选」路径开**（按名解析包格那条路**绝不过滤** = 判错一类就静默找不到）；判据 = 组 187；细则 **R15 ⑥f**。
- ★★★**可驱散「负面类型」多选**：`cd.dt` 空集 = 任意；求值**一律走 `dispelMatch`**（名字对上但类型不符 = 没有）；**名称留空 + 类型 = 「有任意该类型」**；**buff 行不许有类型格**；组 114/181；细则 **R15 ⑥i**。
- 指定等级 = `技能名(等级 3)`（与法术书 subtext **逐字相符**；跨语言不通用 ⇒ 没该串即如实失败）；下拉按等级升序、无 subtext 排最后，`table.sort` 在 5.1 不稳定须「数字+原下标」装饰排序（组 108①b/110②/111）。
- 不占动作条唯一判据 = `skillNoSlotOk`（`EVAL_NO_SLOT_OK`）（`STOP ATTACK WIRING CHECK`；组 111⑤）。
- `CLASS_LIST` 缺圣骑士 ⇒ 模版 `[职业:圣骑士]` 被静默丢弃；须**末尾追加**（组 111⑥ + 组 2）。
- 模版四条体检：名字非空 / 同组不重名 / 首行 `# 方案: X` 等于模版名 / ≥1 条技能行。
- 职业过滤三处一起放开（解析白名单 + 导出 `teamFilterSuffix` + 编辑器格）；单条条件按自己 `cs/gs`，选取器行按行内条件并集。
- 成员过滤**空集 = 不过滤**（与「目标职业空 = 永不满足」**相反**，不共用判据/文案）；成员类条件必须写在一行**最前面**（它负责扫人+切目标）。
- 拆数据文件 = 一处真值变两处同步（磁盘 + `.toc`）；`EXAMPLES TOC CHECK` 四条（双向一致 · toc 顺序 = 选单顺序 · 数据不搬回生产文件 · examples 在 `EvalHelp.lua` 之后）。
- `LANG KEY CHECK`：菜单标签运行时拼键 ⇒ 须配逐语言无重名/无缺键；文本往返走单一通道（`EVAL_PARSE_ONE` 剥 / `teamFilterSuffix` 写）。
- 光环判定 = 两级 + 三态：① 纹理快路径（学习表 > 动作条）② 名字慢路径（`auraNameHit` 0.5s 缓存、命中即 `learnAuraTex` 自愈）③ 两条都不可用才如实失败（**查不到 ≠ 没有**）；扫描可信度三态 `true`=命中/`false`=扫描干净确实没有/`nil`=不可信；诊断 `/eh go tex|texdel|texclear|texscan`；桩补 `SlashCmdList` + 组 104。
- ★★★**抓宠帮手 = 生成物 + 家族属性表 + 真机探针**（全案 **R21**）：`PetData.lua` 是 **`gen_petdata.js` 生成物**（技能/家族/图标三处数据都在生成器里，**手改必被下次生成冲掉**）；家族卡 = `families[id]`（`label/icon/cname/dmg/armor/hp/foods/sk`）+ `famOrder`（= 图片行序，界面与探针唯一顺序来源）；`other` **故意不带三加成**（未收录 ≠ 0）；`cname` 是 `UnitCreatureFamily` 的匹配候选，**精确匹配 + 禁子串**（认不出 → nil，不猜）。取证 = `/eh go 宠物家族`（别名 `/eh pet fam`）｜`表`｜`存档`｜`清`，读数落**有界环** `cfg.petProbe`（40 行，已进残渣键清单），读不到分四态如实报。★**技能图标 = 宏图标号**（撕咬 139 · 爪击 255 · 嚎叫 695 · 冲锋 700 · 甲壳护盾 710 · 暗影抗性 133）；号进 `PetData.skills[].iconIdx`、**运行期按号解析**（唯一入口 `EVAL_PH_SKILL_ICON(sk)`，取不到退回 `skills[].icon`）；★★**绝不能离线把号翻成路径**（清单按字母排序 ⇒ 行号 ≠ 宏图标号）。判据 = 组 235/236 + `PET FAMILY CHECK ⑦c/⑦d`（兜底走**绝对值**夹具）。★技能详情页宠物行 tooltip = 最终形态（用户定：**不做家族视图 UI**、家族**不进一键宏条件**）。⏳**押后（用户「现在没测试环境」）**：真机 `UnitCreatureFamily`/`GetPetFoodTypes` 真值 + 家族属性表逐格复核 —— **恢复环境后只需跑一次探针 + 对图扫一眼**，在那之前别当 bug 反复改。

### 5.7 流程与纪律
- 载入提示与新手引导**每次加载都打**（`cfg.guideSeen` 已废弃）；组 105：VARIABLES_LOADED 第二次仍须打出引导标题与步骤。
- 审计/排查须落成**可执行闸门**；数据变的刷新放**写入点**（`ioImportText`）；组归属是用户偏好，需求一改须钉新归属与顺序。
- 只有 `quiet=true` 且带 `why` 才写日志；接收端只有**同一发送者**开新的一笔才作废旧缓冲；四道上限超限**整笔拒收**、提示限频 5s。

### 5.8 队伍 / 团队 · 目标切换
- ★★★**「目标的目标」= `TargetUnit("targettarget")`，绝不是 `AssistUnit`**（官方两条硬事实：`conventions#unit-ids` 明文 `targettarget` = 当前目标的目标；Targetting 页 `TargetUnit` = 「解析不到**什么都不做**」，而 `AssistUnit` 解析不到会**清掉当前目标**；两者**都没有 Protected 行**）。实现 = `TARGET_SEL` 里 `{ id="targetTarget", fn="TargetUnit", arg="targettarget" }`（**不许**改成 AssistUnit）；技能级/条件级都是 `pcall(fn, arg)`。★边界（如实告知）：**没目标/目标自己没目标 ⇒ 空操作**，而「选取目标」是**副作用条件求值恒 true** ⇒ 规则不会失败，后面那手会打在**原目标**上。取证 = `/eh go tsel`（报存在与名字 + 接口在不在；有目标的目标才真切一次，否则**一次都不切**），读数落 `cfg.tselProbe`（有界 12，已进残渣键清单）。判据 = 组 239；读值口 `EVAL_TSEL_ID`/`EVAL_TSEL_FN`。
- ★★★**「玩家的目标」= `AssistByName(名字)`**（用户要「参考指定名称的编辑方式，但选的是**指定玩家的目标**」）：与「指定名称」**同族**（名字存 `cd.nm`、`needsName=true`、同一个名字下拉 + `EVAL_TN_OPEN`、同一份 `TARGET_SEL` 表），**只差客户端函数**（byName = `TargetByName` 选**那个人** / playerTarget = `AssistByName` 选**他的目标**）；官方明文「Assists a **nearby** player: sets the target to that player's target」，**无 Protected 行**。★**单一来源三个标记表**（别再各写 `cd.s == "byName"`）：`TARGET_SEL_NM`（需要名字：求值两处 + 编辑器显示/名字下拉 + 导出都读它）· `TARGET_SEL_NEEDTGT`（**调用后必须有目标**，当前只有 playerTarget）· 读值口 `EVAL_TSEL_NM`/`EVAL_TSEL_NEEDTGT`。★★**失败必须如实**：官方只承诺「附近」，名字不在附近/不存在时**是否清目标文档没写** ⇒ 用 `UnitExists("target")` 兜底：调用后没目标 ⇒ 条件级 `return false, "…未生效"`、技能级 `return false` + 如实日志（不兜底 ⇒ 没协助到也放行、后面那手打在旧目标上而日志写着成功）；★`dry` 预览**不切也不判**。判据 = 组 242 + 组 243（`/eh go assist [名]` 取证：三态如实 + 零副作用 + `cfg.assistProbe` 有界落盘 + 残渣键）。
- ★★**「英文 id 形态」要在解析入口归一**：`parseOneRaw` 里 `^byName[:=]` 那两条**原本写在 `if tg then` 里面** ⇒ 是**死代码**（`byName=嗜血者` 连门都进不来）⇒ 入口把 `byName=`/`playerTarget=`/`assistbyname=`/裸 id 归一成中文形态再走原路；判据 = 组 242④。
- ★★**菜单文案是「按串回查 id」的键**：两个要填名字的选取器必须给**不同**文案（`SE_PICK_TGT` / `SE_PICK_TGT_PLAYER`），同串 ⇒ 两行分不清、`seApplySkillPick` 与 `targetSelOf` 也分不出是哪种（组 242②）。
- ★★**测试里「按名字找行」、不许写死下标**：新插一项后「清除目标」从 9 挪到 10 ⇒ 写死 `EVAL_DD_TEST_ROW_TEX(9)` 的反向哨兵会**悄悄指向别人的图标却照样通过**；同理「表总条数」会绑架无关改动 ⇒ 改数 `teamSel` 标记。
- 唯一路径 = `TargetUnit`（非 Protected）切目标 → `UseAction` → 还原；条件命中即记人 + 切目标（`st.allyUnit`，单条 `队友血量<60` 自足）；只在**非 dry** 时切（dry = 0.15s 预览求值）；`EVAL_GO` 开头清空 `st.allyUnit`。
- 切目标只在**有意义方向**（血量/蓝量、debuff 有、缺 buff）；存在性判定不切；选取器 = 扫描 + 过滤（血量% 升序、须真切过去判定）；全员不满足须**还原**（`UnitIsUnit` 反查 unit id 优先；`TargetByName` 只认「附近」）。
- 成员选取器**跳过常规条件预判**（`TARGET_SEL_TEAMSEL`，不经 `condOne` ⇒ 两处都要测）；`UPDATE_STATE` 只丢缓存不扫描，真扫描在 `EVAL_HELP_TEAM_ENSURE`（缓存复用）；诚实失败。
- ★★★**「选取目标」调用点取证**（1.75.12；用户报障「**没按键**时目标也在尸体与活怪之间来回跳」）：**静态审计结论 = 插件里没有任何定时器会切目标**（两条 0.15s 心跳都走 `groupsOK(r, true)`，而 condOne 的选取分支被 `if not dry then` 包住 ⇒ 预览**不调也不记**；`EVAL_RULE_RUN` 只被 `EVAL_GO` 调，`EVAL_GO` 的调用点只有宏与动作格接管，`bindSlots` 空时接管一次都不触发）⇒ **「没按键却在跳」只能是调用在源源不断地来**：`/run` 宏走 RunScript pending 队列，松手后旧调用仍按**客户端自己的节奏**冲刷，而去抖窗只是「两次被接受调用的最小间隔」——**节奏大于窗口就每一发都放行**（实测 0.5s 节奏 vs 0.3/0.45/0.55 窗口，日志里全是执行、没有一次被挡）。判据落在**调用点**：唯一调用口 **`tselInvoke`**（技能行/条件/队伍命中/队伍候选/队伍·名字枚举还原 全走它；裸 `pcall(fn…)` 由 `SEL TRACE WIRING CHECK` 禁掉）· 读值口 **`EVAL_TSEL_PROBE()`** · 命令 **`/eh go tsel log [行数]`｜`clear`** · 落盘 **`cfg.selProbe`**（有界 40，已进 Core 残渣键）。每条 = `#调用号 p<按键轮> 谁调的 函数(参数) 前快照 ⇒ 后快照 变/没变`；快照 = 名字+血量%+是否尸体（★**客户端读不到 GUID** ⇒ 同名怪只能靠血量%区分，日志如实写「快照相同=可能同一只」，不冒充身份判定）；另记 **接受发 / 被去抖丢弃** 两条腿 ⇒ 区分**队列余震**与**键连发**。判据 = 组 250。
- ★★★**「补自动攻击」必须目标可攻击才按 + 排在规则之后**（1.75.12 用户确认的修复，全案见上一条取证）：本客户端的「攻击」= `AttackTarget()` **会顺带切目标**（官方文档只写 Toggles，**实测会切**）⇒ 旧版两个口子叠加成「先被它把目标切走 → 再被 选取目标 切回来」= 用户看到的尸体↔活怪无限来回跳。修法两条（缺一不可）：① **目标守卫** = `UnitExists("target")` + 非 `UnitIsDeadOrGhost` + `UnitCanAttack("player","target")`，**一律实时 API 判定**（★**不用 `st.canAttack`**：规则可能刚切过目标、那是这一轮开头采的**过期值**；实时 API 缺失才退回它）；尸体/无目标/不可攻击 ⇒ **一次都不按**；② **次序** = 从「规则评估之前」挪到「之后」（`if acted then return end` **之前**，出手了也照样补）。★限频**三层且口径不许混**：外层 `EVAL_GO` 执行去抖（`cfg.goDebounce`：只决定"这一发进不进"）+ 自动攻击**自己的 2 秒硬节流**（`wLastAttackTry`，写死、**不受** `goDebounce` 控制；因此最大按压频率恒为 1 次/2s）+ 目标守卫；★守卫不过时**不消耗**节流（目标一变可打就能立刻补）。判据 = 组 251（含「实时 API 而非过期 st」「`[攻击]` 行必须排在出手行之后」「关掉开关仍不按」三条 + 反向哨兵）。
- ★**harness 陷阱（1.75.12 实测）**：`test_assert.lua` **跑到后半段**时，自建 tooltip 的 `SetAction` 已被前面的用例折腾掉（实测 `EVAL_HELP_WTT.SetAction = nil`）⇒ `wactionName` 恒 nil ⇒ `EVAL_GO_RESCAN` **扫不到任何技能**（`wslots` 恒空）。**晚出现的组要 `wslots` 必须显式注入 `EVAL_WSLOTS`**（它与引擎的 `wslots` 是**同一张表**，1.46.0 注释已说明"原地清空不重新赋值"）。

### 5.9 已整段迁参考卷
- **关键标识符索引** → §十七；**分享消息模板 / 取证命令全表 / 关键 CHECK 明细** → §十五；**DF/LF 判据原文** → §十六。

## 六、§六 ~ §九 已移到 `CLAUDE_REFERENCE.md`
> ★**何时必须读它**：发布 release、查项目位置/当前版本/工作流纪律（§八）、历史教训 / API 真伪（§六）、官方文档 / 待开发计划（§七）、某版本做了什么（§九）、任务线明细（§十四）、某条判据的踩坑全案（附录 R）。
