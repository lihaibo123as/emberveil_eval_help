# EVAL_HELP 记忆体 · 参考卷（CLAUDE_REFERENCE.md）

> 本文件是 `CLAUDE.md` 的**参考卷**：**不自动载入**（因此不占工作区指令预算），需要时由 AI 主动 `read`。
> 内容 = 发布 release 流程（9 步 + 打包脚本 + 推送信息） · §六 历史教训 · §七 开源仓库/官方文档/待开发 · §八 项目位置与现状 · §九 版本要点。
> ★任务涉及「发布 release / 项目位置 / 当前版本 / 工作流纪律 / 官方 API 文档 / 待开发计划 / 历史教训 / 某版本要点」时必须打开本文件。

## 发布 release 流程（9 步全文 + 打包脚本 + 推送信息）

## ★★★发布 release 流程（用户定；每次发版必做 **9 步**）

> ★★**「release / 发布版本」= 下面 9 步全做完**，不是只 git push（用户 1.72.0 明确：
> 「release 要做的事也包含以上」——指推送 + 打附注标签 + 出 zip 发布包 + 建 Release 页）。

1. **统计里程碑**：根据上一次 release 版本至最新，统计**跨越了哪些版本、每个版本的里程碑是什么**。
2. **项目说明更新信息**：`README.md` / `README_en.md` / `README_ru.md`；★项目说明里的**版本记录只保留最近 10 个**。
   ★★**版本行必须插进「更新日志」表里，不能插进开头的「模块」功能表**（README 有**两张**表：
   开头那张是「模块 / 入口 / 一览」功能表，「## 更新日志」下面那张才是版本表）——
   1.72.0 实事故：用脚本插行时按「**第一张**表的表头分隔行」定位，把 4 个版本行插进了**功能表**里，
   用户在 GitHub 首页一眼看到功能表里混着版本号（★脚本按结构定位但结构假设错了：不报错、只是位置不对）。
   ★判据已落成源码检查 **`README TABLE CHECK`**（3 个 README × 版本行必须全在更新日志标题之后 × 恰好 10 行；
   CHANGELOG 则保留完整历史 ≥20 行），变异 3/3 全捕获 —— 插错表/少一行/删历史都会当场响。
   ★★**README 板块顺序（用户 1.72.0 定）**：**`## 🏁 里程碑` 在 `## 更新日志` 上面**
   —— 即「**项目文件内的更新日志在里程碑下面**」；1.72.0 已把里程碑整块移到更新日志之前，顺序由 `MILESTONE CHECK` 守着（反了当场 FAIL）。
3. **扫描项目文件内的旧版信息**：版本号、文件结构、功能清单、过时描述 → 逐处排查并清理。
4. **按「上次 release → 最新」更新对应板块内容**：README 的功能/用法板块、`DEVELOPMENT.md` 的架构板块等。
   ★★**README 的 `## 🏁 里程碑` 必须同步**（这是第 1 步「统计里程碑」的落地处）：
   ① 标题范围改成最新版本（如 `1.52.0 → 1.72.0`）；
   ② ★★★**整个板块只留 10 条、每条一行**（用户 1.72.0 明确：「里程碑在精简下，控制在 **10 个点、10 行文字以内**」）
   —— **不再按 `### <上次> → <最新>` 分小节**：最新的写最前面，超过 10 条就删最旧的（细节全在 `CHANGELOG.md`）；
   ③ 每条 = `- **emoji 主题**（版本范围）：做了什么 + 一句关键判据/教训`（**一条就是一行**，别堆细节）；
   ★★★**每条必须以 `- ` 开头（列表项）** —— 1.72.0 实事故：10 条写成**连续普通段落行**，Markdown 把相邻行
   **合并成一大段**（用户在 GitHub 上看到的就是「排版混乱」一大坨）；★这类「内容对、只是渲染不对」的坑行为断言照不到，
   只能靠结构检查守 —— 已是 `MILESTONE CHECK` 第⑤条（把任一条的 `- ` 去掉 → 当场 FAIL）。
   ★★**三语言同步**：zh / en / ru **都已有该板块**（1.72.0 起补齐）—— **不许只给某个语种补一小段**（会孤悬），
   要加就三语一起加；**新增/翻译都要三语言都更新版本表**。
   ★★★**是「归纳」不是「罗列」**（用户 1.72.0 明确）：「里程碑是要你总结上个里程碑到最新版本的信息归纳，
   而不是把版本信息全部罗列，不然内容太多了 —— **每次里程碑归纳内容最终控制在 10 条以内**」，
   随后又收紧：「**控制在 10 个点、10 行文字以内**」→ 细节归 `CHANGELOG.md`，板块里每条只留一句话。
   ★另有 **`PACK LIST CHECK`**（第 18 道：1.73.0 加：记忆体第 9 步的发布包模块清单必须与 `EvalHelp.toc` 的顶层 `.lua` **逐个一致**，且「条目数基准」必须等于按打包口径现算的真实集合大小——守「新增模块后清单/基准过期，出包缺文件用户装不上」这一类**不报错、只是清单过时**的事故；变异：删掉清单里的 PetData.lua / 把基准 62 写回 60 / 清单塞不存在的模块 → 三发全中）。
   ★判据已落成源码检查 **`MILESTONE CHECK`**（第 17 道：3 个 README 都有 🏁 板块 + **里程碑在更新日志之前** +
   标题范围末端 == 当前 VERSION + **板块正文非空行 1..10** + **每条都是 `- ` 列表项**），变异全捕获。
   ★★**「如何总结里程碑」= 上面这三条**（① 归纳不罗列、**一条一行** ② 三语言一起 ③ **全板块 ≤10 行**），
   取素材走发布流程第 1 步（上次 release → 最新跨越的版本与各自的里程碑），细节一律留在 `CHANGELOG.md`。
5. **更新文件内的版本记录**：`CHANGELOG.md` 保留**完整**版本记录；`EvalHelp.lua` 的 `local VERSION` 与 `EvalHelp.toc` 的 `## Version` **同步**（`VERSION` 源码检查守着）。
6. **审计记忆体（本文件 `CLAUDE.md`）**：版本要点**汇总统计后放到文档末尾**；★**头部只保留比较新的记忆注意事项（最多 20 个版本）**
   —— ★**不要再把一堆逐版本记录堆到记忆体头部**（那是异常，会让文件超预算被截断，且把铁律挤出视野）。
7. **提交 + 打「附注」标签**：`git commit` → `git tag -a vX.Y.Z -F <说明文件>`。
   ★★**必须是附注标签（`-a`），不是轻量标签** —— 轻量标签只是个 commit 指针、**没有说明**，
   而 Release 页要用它的说明当正文（1.72.0 踩过：先打了轻量标签，只能 `git tag -a ... -f` 重打再强推）。
   说明内容 = 该版本的「头条 + 里程碑 + 安装方式 + 质量声明」，与 CHANGELOG 的详情小节同源。
   ★★**写标签说明文件绝不能用 PowerShell 的 `>` 重定向** —— `>` 默认写 **UTF-16LE**，
   `git tag -F` 按原始字节读进去 → 标签说明**整段乱码**（1.72.0 实踩：
   `git cat-file -p v1.72.0` 出来是 "E v a l H e l p" 这种夹 null 字节的样子）。
   正解：用 `write` 工具写 UTF-8 文件（无 BOM），或 PowerShell 下 `Out-File -Encoding utf8`；
   ★打完后**必须回读复核**：`git cat-file -p vX.Y.Z | Select-Object -Skip 5 -First 3` 应正常显示中文。
8. **推送（三个都推）**：`git push origin master && git push github master`，然后**标签也要推**
   `git push origin --tags && git push github --tags`（★只推分支不推标签 = Release 页找不到 tag）。
9. **出发布包 + 建 Release 页**：
   - **发布包** `EvalHelp-vX.Y.Z.zip`（放在 `Interface/AddOns/` 下，与仓库同级——**不要放进仓库**）：
     顶层一个 `EvalHelp\` 文件夹，内容 = `.toc` 实际清单（**必须按 toc 逐个核对**：
     1.72.0 发现随包的 `EvalHelp-v1.71.2.zip` **只有 25 个文件、缺 `IconBrowser.lua` + 5 个 examples** →
     用户装那个包会**直接报错**；正确包是 **60 个文件**）。打包脚本见下方「发布包怎么打」。
   - **Release 页**：★**这一步我（AI）做不到，需要用户手动操作** ——
     建 Release 要走 **GitHub/Gitee API + token**，而本机 `gh` CLI **未安装**、环境变量与凭据文件里
     **都没有任何 token**（实测 `POST /repos/.../releases` 返回 **401 Unauthorized**）。
     ★按会话规则**不申请权限提升**，所以**如实告知用户去网页建**，并把 URL 与要填的标题/说明/附件给全。
     GitHub: `https://github.com/lihaibo123as/emberveil_eval_help/releases/new`（选已存在的 tag → 标题 →
     说明可从 `git tag -n99 vX.Y.Z` 取 → 附件拖 zip → Publish）；
     Gitee: `https://gitee.com/xeval/emberveil_eval_help/releases/new`（同样选 tag + 上传同一个 zip）。

**更新日志维护规则（1.28.0 起，用户定）**：① 详情写 `CHANGELOG.md` 的 `## 🎯 vX.Y.Z — 主题` 小节（要点 / 典型用法 / 设计亮点，配一个 emoji）；
② `README.md` 顶部「更新日志」速览表加一行（`| **X.Y.Z** | emoji 主题 | 一句话亮点 |`，**最新在上**）；③ **README 不再放版本详情**（保持精简，详情只进 CHANGELOG）。

**发布包怎么打（第 9 步的脚本，实测可用）**：★在 `Interface/AddOns/` 下执行（**不是插件目录**），产物与仓库同级。
```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$src = "$PWD\EvalHelp"; $out = "$PWD\EvalHelp-vX.Y.Z.zip"
$staging = "$env:TEMP\eh_pkg"
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path "$staging\EvalHelp" | Out-Null
# ★只装运行必需：.toc + 10 个顶层 .lua 模块 + **tools/ 子目录模块**（HunterHelper.lua）+ Locales + examples + media
#   + 三语言 README/CHANGELOG/DEVELOPMENT
# ★★1.74.5 教训：模块放进**子目录**后，PACK LIST CHECK 的旧判据只看「顶层 .lua」→ 本地测试全绿、出包却缺文件
#   （用户装了直接报错）。现有判据已扩成「toc 里带路径的 .lua：要么逐个列出、要么所在目录被整目录拷」。
# ★★清单必须**跟着 EvalHelp.toc 走**（下面的模块名与基准数由源码检查 PACK LIST CHECK 守着，改漏一处当场 FAIL）
Copy-Item "$src\EvalHelp.toc","$src\Core.lua","$src\Engine.lua","$src\EvalHelp.lua","$src\Toolbox.lua","$src\DataSearch.lua","$src\Share.lua","$src\IconSem.lua","$src\IconBrowser.lua","$src\PetData.lua","$src\PetHelper.lua" "$staging\EvalHelp\"
Copy-Item "$src\README.md","$src\README_en.md","$src\README_ru.md","$src\CHANGELOG.md","$src\DEVELOPMENT.md" "$staging\EvalHelp\"
Copy-Item "$src\Locales","$src\examples","$src\media","$src\tools" "$staging\EvalHelp\" -Recurse
Remove-Item "$staging\EvalHelp\media\Textures" -Recurse -Force -ErrorAction SilentlyContinue  # 主题素材不进包
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $out)
Remove-Item $staging -Recurse -Force
```
★**装完必须核对条目数**（1.74.27 基准 = **69 个**（+`tools/RareWatch.lua`）；1.74.12 时是 68、1.74.6 时是 66、1.73.5 时是 63；1.74.5 陆续加了 `tools/IconGrid.lua` / `tools/HunterHelper.lua` / `tools/ConsumableHelper.lua`，1.74.7 加 `tools/DismountHelper.lua`，1.74.27 加 `tools/RareWatch.lua`）：
  少一个就是缺文件，用户装了会**直接报错**。
  ★这一条与上面的模块清单都有源码检查 `PACK LIST CHECK` 守着（清单与 .toc 逐个比对 + 基准数按打包口径现算），过时当场 FAIL。
★**不装**：`luacheck.js`/`test_*.lua`/`test_engine.js`（测试）、`preview/`（截图）、`node_modules/`、
`api_*.html`、`.git/`、`bindings/`、`_icons_scan/`、`pay/`。

**推送信息**：分支 `master`；远端 `origin`=gitee（`git@gitee.com:xeval/emberveil_eval_help.git`）、`github`=`git@github.com:lihaibo123as/emberveil_eval_help.git`（1.29.0 起双远程，每次**两端都推**：`git push origin master && git push github master`；本地仓库 = 插件目录本身）；★推送用**默认密钥 `~/.ssh/id_rsa`**（`gitee_id_rsa` 未被授权，别用 `-i` 指定它）。
★★**两个库一律走 SSH（`git@xxx` 形式）+ 本机默认密钥** —— 用户 1.72.0 明确：「发布两个库，记住都走 git@xxx 本地密钥形式」。
即：**不用 HTTPS、不用 token、不用 `-i` 另指密钥**；推送前先 `git remote -v` 核一眼**两个远端都是 `git@`**，
再用 `ssh -T git@github.com` / `ssh -T git@gitee.com` 双端验签（1.72.0 实测：GitHub `Hi lihaibo123as!`、Gitee `Hi eval(@xeval)!`）。
★两个远端名固定：**`origin` = gitee**、**`github` = github**。



## 六、历史教训汇总（1.70.0 ~ 1.70.36，按主题；不再逐版本）

### A. Lua `local` 作用域（累计 13 次，头号杀手）
- 作用域是**词法**的：引用点写在 `local` 声明**之前** → 那个名字**永远是全局**，与运行时调用顺序无关；防法 = 导出函数物理定义在被引用者之后 + `DECL ORDER CHECK` 自动扫。
- ★★**合并冲突在 Lua 里不报错（1.71.1）**：两分支给**同一个全局**赋值 → 后赋值者**静默获胜**（实测：测试桩的富版 `GetNumPartyMembers` 被简版盖掉 → 队伍扫描只扫到自己，组 66 `got=1 want=3`）。语法检查与单文件审查**都看不出来**，只有**跑测试**能发现；`git diff` 里同一函数名出现两次要立刻当错误。
- 不得不提前引用时用**前置声明** `local f`（**无 `=`**）+ 实现处 `function f(...)`（**不带 `local`**）。
- ★检查器盲区：看不见「无 `=` 的前置声明」与 CRLF 的 CR；且按**名字**判定 → 「A 函数里是 local、B 函数里当全局用」看不见（1.70.47 `texOf` 就这样漏掉，表现为「选人结果不对」而非报错）。**没被变异验证过的检查 = 没有**。

### B. 静默失败族
见 §5.2（此处不再重复）。

### C. 断言与测试（「绿」不代表对）
- **桩太宽松**：Show/Hide 空操作、IsShown 恒 nil、CreateFrame 丢 parent、GetWidth/GetHeight 恒 nil → 行为级/父级/尺寸断言全部失效；**写断言前先确认桩有状态**。
- **只测解析函数、不测调用点**（第 4 次发作）：要断言「A 产出配置、B 消费配置」**两边**；能点就点**真实按钮**。
- 结果相同的用例（等价变异）证明不了任何事；CRLF 上用 `\n` 锚点会**静默替换失败** → 变异后**必须回读确认结构真的变了**。

### D. 布局与 UI（本客户端实测）
- 同一行/栏**混用「顶边对齐」与「中线对齐」必然错位**（字体链不同时行高会变）→ 要么全顶边要么全中线（**按中线更稳**）；`中线 = 顶边 - 高度/2`（y 越往下越负）。
- **FontString 一律显式 `SetWidth`**，否则宽度随内容变、换语言就溢出压到别的控件；**改布局要一起改「隐形跟随件」**（占位提示/聚焦热区/背景纹理常写死宽度，grep 旧宽度值能找出来）。
- **`root:SetScript` 是单槽位**：多 Tab 共用根帧时先 `GetScript` 取旧处理器做**链式转发**，否则静默顶掉别人的滚轮。

### E. 兜底机制的设计纪律
- **前提被证伪的兜底必须删掉**（不能因为「留着无害」而保留——它在空转，还让人以为有保护）。

### F. 本客户端 API / 素材的真伪清单（用前必查，别按命名习惯猜）
- **`WorldMapFrame:IsShown()` 两个方向都会撒谎**（可能恒 false，关图后也可能恒 true）→ **绝不进分支**；判「有没有可标注视图」只用 `MapContext:GetViewedZone()` 的 `zoneIndex==0 → continentView`；开图一律 `ShowUIPanel`，**绝不 Toggle**。
- **`UnitBuff`/`UnitDebuff` 只有图标+层数、没有时长**；只有自身光环能查 `GetPlayerBuffTimeLeft`，**它返回 0 = 无限/无数据（不是 0 秒）**。
- **`UnitCreatureType` 返回带后缀的本地化名**（「人型生物」）→ 匹配要剥掉「生物」再比。
- **无 CombatLog API、无免疫查询函数、无 `UnitCastingInfo`、无 SuperWoW**（精确距离/挥击计时做不了）。

### F3. 官方文档现场核对记录（1.70.47 逐条查 emberveil.org，2026-09）
- **Protected（文档明写 addons cannot call this）**：`CastSpellByName`、`SpellTargetUnit`、`SpellStopCasting`；★`TargetUnit`/`TargetByName`/`ClearTarget`/`UseAction`/`IsUsableAction`/`IsActionInRange` 条目里**都没有 Protected 标记**——这正是「切目标 → UseAction」这条唯一可行路径的依据。
- ★**`UnitIsUnit` 相同返回 `true`、不同返回 `nil`（文档原话 never false）** → 只能看真值，**不能写 `== true`**。
- ★**`GetNumPartyMembers()` 在团队里返回「团队人数 - 1」**（不是 0），而 **party 索引只有 `party1..party4` 且不含自己** → **不能拿它当 party 循环上界**（40 人团会去试 party1..party39；已夹到 4 并有调用计数断言守着）。**`GetNumRaidMembers()` = 团队人数含自己，非团队时 0** → raid 直接 `raid1..N`。

### G. 任务/地图专题的关键事实
- tick 帧必须挂 **`WorldFrame`**；视图签名必须含 **areaId + mapFile + continent + zoneIndex**（只比 areaId 会让「关图再开同一张图」被判「未变」）。
- 采集点数据在 `meta.herbs/mines/chests/fish` 里是**负 ID**（负号 = 类型编码），查 objects 表要取反。
- 对方地图标注层**没有地图事件可用，全靠 `REFRESH_INTERVAL=0.25` 轮询**——不要自己发明事件层。

### H. Lua 5.1 / 本客户端语言坑
- `string.find(s, "^14|", 1, true)`：**plain=true 会把 `^` 也当普通字符**；`|` 在 Lua 模式里是**字面量**（不是交替）。
- ★★**中文/多字节串上的模式匹配（1.70.47 一次踩中两个，代价是「整类条件解析不出来」）**：① `|` 不是交替（`(队伍|团队)` 只在匹配字面串时成立）；② **字符组 `[伍团]` 按字节匹配**——set 只吃**一个字节**，`[伍团]` 实际是 `{228,188,141,229,155,162}`，匹配到「伍」首字节后剩两尾字节对不上后续 `buff`，照样失败。**正确写法：用 `(.+)` 抓下来再 `==` 比较**。★症状有欺骗性：**编辑窗能存、导出也正常，但重新导入时条件静默消失**；只有「导出→导入」**往返断言**能抓住（组 66 当场定位）。

### I. 参考代码路径（**先读对方**，见铁律 2 / 3）
- **UnrealQuest**：`...\Interface\AddOns\UnrealQuest\Compatibility\ClientAPI.lua`（实测配方库，注释里全是坑）、`Core/Driver.lua`（帧父级/生命周期）、`Map/MapContext.lua`、`Map/WorldMapPins.lua`、`Map/NpcPins.lua`（CATEGORIES/RANK_ICONS）。
- **Cat（TurtleWoW）**：`D:\game\TurtleWoW\Interface\AddOns\Cat`（状态变量设计参考）；**OneJudge**（最初的参考：纯色纹理配方）。
- **Heart + C（TurtleWoW）**：`D:\game\TurtleWoW\Interface\AddOns\Heart`（团队/治疗框架）与共享库 `...\AddOns\C`（隐形 tooltip + 单位/buff 采集）——**队伍/血量/蓝量/buff 检测见铁律 3**。
## 七、开源仓库 / 官方 API 文档 / 待开发计划

### 7.1 开源仓库（1.21.0 起）
- 库内含：`README.md`（开源门面 + `preview/` 界面图）、`CHANGELOG.md`（更新日志详情）、`DEVELOPMENT.md`（开发者指南）、`CLAUDE.md`（AI 记忆体副本，改主记忆后同步过去）、`luacheck.js`、`test_engine.js`/`test_stub.lua`/`test_assert.lua`（冒烟测试）、`example/zs_wq.md`。
- **更新日志维护规则（1.28.0 起，用户定）**：① 详情写 `CHANGELOG.md` 的 `## 🎯 vX.Y.Z — 主题` 小节（要点/典型用法/设计亮点，配一个 emoji）；② README 顶部「更新日志」速览表加一行（`| **X.Y.Z** | emoji 主题 | 一句话亮点 |`，**最新在上**）；③ **README 不再放版本详情**（保持精简）。
- **`preview/` 图片只用用户提供的**（当前 main.png=全局页 / cfg.png=一键宏设置页 / skill_cfg.png=技能编辑窗 / info.png=战斗信息UI+状态信息UI）；我加的截图已被用户要求删除——**别再自行往里放图**。

### 7.2 官方 API 文档（用户提供 2026）
- **Lua API 清单：https://emberveil.org/wiki/lua**（1370 条目，页面内嵌**全量 JSON 索引可脚本解析**；分类页如 `/wiki/lua/globals/Action` 有签名 + 返回值文档）。
- ★**本机就是游戏主机**：EmberVeil 与 TurtleWoW 都在本机，改码 → `node luacheck.js`/`test_engine.js` → `/reload` 实测都在同一台机器上完成（推送 gitee 仅为备份/发布）。

### 7.3 待开发计划（搁置项）
- **免疫学习器**（✅ 1.36.0 已完成实装：探针验证 → 事件解析 → 学习表 → 引擎跳过；探针 `/eh go probe immune/dump` 保留作诊断工具）：
  - 已排查结论：**无 CombatLog API、无免疫查询函数**、wiki 无事件文档页（`/wiki/lua/events` 404）；但 `Frame:RegisterEvent`/`RegisterAllEvents` 可用。
  - 设计方向：订阅 `CHAT_MSG_*` 战斗文字事件，从消息串解析「免疫」→ `cfg.war.immune["技能@怪名"]` 持久化 → `EVAL_RULE_RUN` 对同名怪自动跳过该技能（可流血黑白名单 `EVAL_BLEED_BLACKLIST` 的自动化升级版）。
  - 前置步骤：先做探针 `/eh go probe`（30s 事件抓取写调试日志缓存）拿真实事件名 + 免疫文本格式，再写解析器；复用 `autoFrame` OnEvent 三态兼容范式（事件名在 1 参 / 2 参 / 全局 event）。
  - 相关基建：`st.canBleed` 判定链（白名单 > 黑名单 > 生物类型排除）。

## 八、项目位置与现状

- **插件目录**：`G:\game\u5wow\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns\EvalHelp\`（1.21 后由 EVAL_HELP 改名 **EvalHelp**；★**目录名 == toc 基名**才加载；改名时游戏必须关闭，否则 Access denied）。
- **文件结构（1.39.0 起模块化，不是单文件）**：`EvalHelp.toc` + `Locales/{zhCN,enUS,ruRU}.lua` + `Core.lua`（输出/i18n/状态采集）+ `Engine.lua`（规则引擎）+ `EvalHelp.lua`（UI/斜杠命令/init）+ `Toolbox.lua`（工具箱 Tab3）+ `DataSearch.lua`（数据检索 Tab4）+ `Share.lua`（方案分享，1.71.0）+ `IconBrowser.lua`（图标库 Tab5）+ `PetData.lua`/`PetHelper.lua`（抓宠 Tab6，1.73.0）+ `IconSem.lua`（**图标语义表**，1.73.5）+ **`tools/IconGrid.lua`（通用图标网格选择器，1.74.5：单选/多选、高度自适应、分页、滚轮、夹取） + `tools/HunterHelper.lua`（猎人助手 · 一键喂食） + `tools/ConsumableHelper.lua`（消耗品助手 · 多选横排各自点用）—— 都在 `tools/` 子目录里**
  + `examples/*.lua`（**11 个数据文件**）；文档 `README.md`/`README_en.md`/`README_ru.md`/`CHANGELOG.md`/`DEVELOPMENT.md`/`CLAUDE.md`；测试 `luacheck.js`/`test_engine.js`/`test_stub.lua`/`test_assert.lua`。**行数随开发变化，别当固定值引用**。
- ★**toc 载入顺序（以 `EvalHelp.toc` 为唯一真值）**：`Locales/{zhCN,enUS,ruRU}` → `Core` → `Engine` → `EvalHelp` → **`examples/*`（11 个数据文件，必须排在 EvalHelp.lua 之后）** → `Toolbox` → `DataSearch` → `Share` → **`IconSem`** → `IconBrowser` → `PetData` → `PetHelper` → **`tools\IconGrid.lua`（共用网格件，必须在两个助手之前）** → **`tools\HunterHelper.lua`** → **`tools\ConsumableHelper.lua`**（★`EXAMPLES TOC CHECK` 守着「磁盘 ↔ .toc 双向一致 + 顺序 = 选单顺序」；`IconSem` 必须在 `IconBrowser` **之前**——后者读它的 `EVAL_ICON_SEM`）。
  ★子目录模块（`tools/`）在 toc 里写 **`tools\HunterHelper.lua`**；它们**载入期零副作用**（只定义函数与常量），图标帧在用户打开开关时才建。
  ★**共用件纪律**：喂食与消耗品助手共用 `tools/IconGrid.lua`（网格 + `EVAL_IG_SCAN_BAGS` 扫背包 + `EVAL_IG_TOPLEFT` 位置换算）——
    同一内容不许两处各写（本项目铁律）；1.74.5 实踩一次「`IG.pages` 一名两义」（页号表被总页数覆盖 → 选完食物点格子报错且不收起），已拆成 `pageOf`/`pages`。
- ★**新增 .lua 模块要同时改四处**：① `EvalHelp.toc` 载入列表；② `test_engine.js` 的加载数组
  （**7 处清单**：DECL ORDER / LANG KEY / LANG SOURCE（自动发现，已含 `tools/`）/ COMMENT SWALLOW /
  FRAME NAME CLASH / COLOR CODE LEN / 主加载循环 —— 漏一处就是那一类检查的盲区，本项目踩过）；
  ③ `DECL ORDER CHECK` 的文件清单（**目前 13 个**：EvalHelp/Core/Engine/Toolbox/DataSearch/Share/IconSem/
  IconBrowser/PetData/PetHelper/**tools/IconGrid**/**tools/HunterHelper**/**tools/ConsumableHelper**）；④ ★**发布包清单**（第 9 步的 Copy-Item 行）——
  **放进子目录时尤其容易漏**：1.74.5 实事故预警 = `PACK LIST CHECK` 旧判据只看「顶层 .lua」，
  子目录模块被静默漏掉（本地测试全绿、出包缺文件、用户装了报错）
  → 判据已扩成「toc 里带路径的 `.lua`：要么逐个列出、要么所在目录被 `Copy-Item -Recurse` 整拷」，基准数也把 `tools/` 数进去。★1.73.5 实事故：新增 `IconSem.lua` 后**主加载循环**漏加 → `EVAL_ICON_SEM` 在测试里是 nil，图标库语义/过滤整组断言**全红**（这正是「检查存在 ≠ 覆盖到位」）。
- ★**案例模版数据文件（1.71.2 新增 `examples/*.lua`）只需改两处**：`EvalHelp.toc` + `test_engine.js` 加载数组（它们没有顶层 local，故不进 DECL ORDER 清单）。
- ★**在途（未发版）**：**1.74.5 猎人助手 · 一键喂食**（`tools/HunterHelper.lua` + 工具箱「猎人助手」分组）：
  · 交互 = 图标**左键一键喂食** / **右键选背包食物**（选完图标变该食物）；食物**只存名字**，每次实时重解析包格。
  · 「选食物」= **背包式图标网格**（用户要求「图标搭配 tooltip，类似背包四方格布局 8×N」）：8 列 × 5 行 = 40 格/页，
    **高度按实际行数自适应**（`hhGridHeight(rows)` 单一来源；2 件→115px、2 行→172、满格→343；底栏按钮只改 y 不重算 x），
    **图标 26×26 px、格子=图标尺寸**（★1.74.5 两次用户反馈的最终口径：「图标尺寸缩小到 55」→ 又「打开选择框内的图标也太大了，和外层图标尺寸对齐」
    ⇒ 与外层悬浮图标/配置入口统一为 **26**；步进 28）、**格子不自绘边框**（用户：「物品隐藏边框，图标已经自带边框了」；悬停改为提亮图标），
    ★面板宽 = **max(网格宽 242, 底栏最小宽 278)** —— 格子缩小后底栏会互相压（实发现），宽度下限落成几何断言；
    池子复用、数量角标、tooltip（名字/数量/包格/spec.hint）、`[上翻][下翻]` + 计数「1-40 / N」（绝不静默截断）、
    滚轮翻页走 `EVAL_WHEEL_DIR`（已纳入 `WHEEL DIRECTION CHECK`，8 处）、左键点格即选并收起、贴边夹取、网格不可用时降级文本下拉；
    ★**点框体外部自动关闭**（用户要求）：面板下垫一张**全屏透明 Button 捕手**（层 239 < 面板 240；Frame 收不到 OnClick，
    同「拖动柄必须用 Button」实测）；显隐**只由面板 OnHide 统一负责**（常驻可见 = 吞掉整屏点击）；组 176⑯/177⑦c⑦d。组 176⑯。
  · 工具箱那一行**右侧挂「待测试」黄感叹号**（用户要求；插件本地图 `media/icons/mark-test`，路径单一来源
    `EVAL_UI_MARK_TEST`；12×12 独立小 Button —— 纹理不吃鼠标事件，挂不了 tooltip；组 176⑭）。
  · ★**登录恢复**（用户实测：开着一键喂食、拖好图标、`/reload` 后图标**不见了**）：根因 = 开关只存状态，
    图标帧是「点开关那一下」才懒建的 ⇒ 登录流程里没人重建；修法 = `EVAL_HH_RESTORE()` 由 `VARIABLES_LOADED` 调用
    （+ 工具箱事件帧的 `PLAYER_ENTERING_WORLD` 二次恢复，按真实尺寸重算锚点，幂等）；**关着时一个帧都不建**（懒加载仍成立）。组 176⑰。
  · ★1.74.5 **共用件 `tools/IconGrid.lua`**：把上面那份网格抽成通用件（single/multi 两种模式、spec 给候选与回调），
    喂食助手通过 `EVAL_HH_GRID_*` 薄封装继续用它（既有名字/读值口不变，组 176⑮⑯⑰ 一字未改照跑）。
  · ★1.74.5 **消耗品助手**（`tools/ConsumableHelper.lua` + 工具箱「消耗品助手」分组，默认关）：
    **主图标 = 第 1 个选中项**（左键用掉它；★没选中时左键**不弹面板** —— 用户明确「左键不要触发弹窗选择」，只如实提示走右键；**右键 = 开/关面板**，唯一入口）·
    **横排 = 第 2 个起**（第 1 个已在主图标上，**不重复画** —— 用户截图：「选中一个多了个重复的」「选中第二个的时候才增加」）·
    **重复点格子 = 取消选中**（多选开关，状态落盘）。
    ★**两个助手的主图标都是 26×26**（用户截图：「两个助手的图标都太大了，需要和配置的图标相同」
    ⇒ 与 `EvalHelp.lua` 的配置入口/小地图按钮同尺寸 `mb:SetWidth(26)`；位置记忆存的是「中心偏移」，改尺寸不影响老存档）；
    横排每枚 26×26（步进 28 = 26+2，相对主图标 +4/+32；贴屏幕右缘整条自动翻到左侧）；左键横排 = 用该物品
    （`UseContainerItem(bag,slot)`，包格**按名字实时解析**）、右键横排 = 取消选中；多选状态落盘（`tb.chUse`，顺序=点击顺序，上限 10 如实提示）；
    使用是**服务器写动作 → 0.3s 限频**（同一时刻再点如实拒绝）；
    ★**用完/不在背包 → 图标灰显留在原地**（用户要求；贴图在选中时记进 `tb.chTex` 跟着存档走，找不到时用记住的贴图 +
    顶点色 0.35 三通道同值；补货即恢复白显；判据读真控件 `GetVertexColor`）；登录恢复同喂食助手（`VARIABLES_LOADED` + 进世界二次恢复）；组 177。
  · ★1.74.5 **方案「作者/来源」**（`prof.author` + `prof.src`）：唯一标签函数 `EVAL_PROF_AUTHOR_LABEL(prof)` 分四类 ——
    自创（`src ~= "text"`；★**只显示「自创」** —— 用户澄清：「别称的意思就是方案内显示自创（实际值是自己名字）」⇒ 自己的名字照旧记进 `prof.author` 存档**但不上屏**；老存档无 author 同样显示「自创」）· 案例模版（显示**真实作者**：`技能学院`）· 别人分享（显示**真实作者**：发送者名）· 导入（文本粘贴无作者）。
    三处导入点各自盖章：手建 `EvalHelp.lua` = `UnitName("player")` · 案例模版选单 `ioImportText(p.text, "技能学院")` · 分享弹窗 `EVAL_IMPORT_TEXT(p.text, p.sender)`。
    方案列表 tooltip（一键宏 Tab）= 方案名 + **评级**（品阶名 + 分数）+ **来源**（作者标签）+ 技能数；判据 **组 179**（四类 + 三导入点 + 真 OnEnter + 换一组再比）+ **`SHARE AUTHOR WIRING CHECK`**（源码级接线）。
  · ★1.74.5 **头衔评定只算自创方案**（用户：「角色头衔评定标准是只有自己创建的方案才加入评定分计算」）：
    `EVAL_TITLE_COUNTS()` 按 `p.src ~= "text"` 过滤；`EVAL_TITLE_STATE()` 与创世者彩蛋闸门同源；组 147⑦b。
  · ★1.74.5 **分享「不弹窗」原因全部落日志**（用户：「现在为弹窗原因在日志内显示」）：统一入口 `shNoPop()`，前缀 `[分享] 不弹窗：` ——
    接收开关关着 / 载荷不完整 / 分片超上限 / hex 还原失败 / 重复收齐 / 暂未收齐 / 超时丢弃 / 在途超上限，八条分叉**不再静默**（此前只有「弹窗/过大/自己的回声」三条落盘）；组 178。
  · ★1.74.5 **分享「场景描述」**（用户：「接收方案完成后再加一句模版：<头衔> 根据当前所在<地点>、<有无目标> 做场景描述，背景=魔兽世界」+「头衔根据等级染色」）：
    点 [导入]/[忽略] ⇒ 彩蛋反应（立即发）之后**再补一句**场景描述（进 `shTxQ` 限频队列，≥1s 滴出）；
    分派 = op × `UnitExists("target")` ⇒ **4 张表各 10 条**（`SH_SCENE_{IMP,IGN}_{IDLE,TGT}`，三语言齐）；
    占位符优先级 ① 头衔（句首，**按档位染色** `EVAL_TITLE_CURRENT().color`；没入档→玩家名且**不猜色**）② 地点（`GetRealZoneText`）③ 目标（仅 _TGT 两张表）；
    ★★★**形态铁律（实测事故）**：客户端**不画「有色码但没有链接」的消息** ⇒ 头衔必须包成与封皮 A 行同款的链接
      `|c<档位色>|HEHPF:<传输id> 0/1:0|h[<头衔>]|h|r`（第一版写成「色码 + 纯文本」→ 用户实测整条不显示）；
      拿不到传输 id / 合法 8 位色码 → 退回纯文本（无链接无染色，但**能显示**）。整条**只许一段色码**；地点**永不写死**（只用魔兽世界通用意象）；组 180 + `SHARE SCENE WIRING CHECK`。
  · ★1.74.5 **「取消彩蛋」的口径（用户随后澄清）**：「我说的是删除场景描述的彩蛋，而不是把彩蛋功能删除」⇒
    [导入]/[忽略] **不再发**角色扮演反应句（改发上一条「场景描述」），但彩蛋**功能与三语言 50 格文案全部保留**、只是**未接线**；
    闸门：`SH FUN CHECK` 钉「机制都在（频道映射/两表/抽奖/名链接/超长守卫）**且** 两处调用点未接」，组 170① 仍验文案结构，
    组 82④⑤ 是**反向哨兵**（点了不许发出任何 `SH_FUN_*` 句子）。★恢复接线 = 把 `shSendReaction("imp"/"ign")` 加回回调并**同步改那条检查**。
  · ★1.74.6 **自身/目标 debuff 支持「负面类型」**（用户：「查看自身/目标debuff 条件类型配置项，需要参考队伍debuff 配置支持 debuff 负面类型功能」）：
    队伍/团员/候选者 debuff 本来就有「负面类型」（1.73.2 多选），**自身（`pDebuff`）/目标（`hasDebuff`）**这次补齐，四族走**同一套**：
    | 环节 | 做法 |
    |---|---|
    | 状态层 | 层数表**保持数字**（`st.playerDebuffs/targetDebuffs`，读侧一字不改），类型另存**平行表** `st.playerDebuffType/targetDebuffType`（`UnitDebuff` 第 3 返回） |
    | 解析 | `auraStackSplit()`：**先剥层数后缀再拆名字/类型** ⇒ `断筋(魔法)` / `断筋(魔法) >=2` / `魔法` / `魔法 >=2` 全能解析；**没写括号时与旧行为逐字一致**（`dt=nil`，存量文本一个字节不变） |
    | 求值 | `auraCountOf(cd, 层数表, key, provider, 类型表)`：**名字对上但类型不符 → 视为没有**（`dispelMatch`）；**名称留空 + 类型 = 「有任意该类型」**（按类型表数命中项、层数取命中项**最大值** ⇒ lim=1 是存在性、lim=N 是「有一条叠到 N 层」） |
    | 导出/显示 | **同一份** `dtSuffix()`：导出英文 token（`(Magic/Poison)`）、界面显示本地化名（`(魔法)`）；顺手补上 `candDebuff` 原先**漏掉的类型后缀**（它以前存不住类型） |
    | 编辑窗 | 类型格 `row.dtBtn` 对 pDebuff/hasDebuff 也 Show；判据读 `EVAL_TEST_SE_ROW_DT(i)`（自身/目标两行都要有、**buff 行不许有**） |
    ★判据 **组 181**（解析 / 存量导出不变 / 类型过滤 / 名称留空=任意该类型 / 往返 / 编辑窗三态）；**变异 M181**（拿掉「类型不符=没有」那一行）→ 当场红：`ASSERT FAIL[③★★★名字对上了但类型不符 → 不命中]`。
    ★已知限制：编辑窗光环名下拉**没有「清空回任意」这一项**（自由文本空串被忽略）⇒「名称留空 + 类型」目前靠**默认空名**或文本导入配；要 GUI 化就给 `SE_AURA_MENU` 加一条「任意（按类型）」（会动到菜单顺序断言，故本轮没做）。
  · 位置：**默认落在窗口正中**（用户指定）；拖动后记住「中心偏移」、越界位置夹回屏幕内 —— 换算单一来源
    `hhTopLeft(sw,sh,cx,cy)`（★修掉两个错写法：y 方向写反会落到屏幕上方之外、x 少减 s/2 恒偏 18px）；组 176⑬。
  · **懒加载结论（用户要求分析）**：本客户端**无 `io/os`（无文件读取 API）**、`LoadAddOn` 又是 **Protected**
    ⇒ **文件级懒加载不可能**；能做的是「toc 预载 + 载入期零副作用 + 首次使用才建帧/扫包/建 tick」。
  · 喂食链路 = `RunScript('CastSpellByName("喂食宠物")')` → 等 `SpellIsTargeting()==1` → `PickupContainerItem(包,格)`；
    守卫：没进待选态**绝不点包**（否则把食物捡到光标上）、光标被退回就 `ClearCursor` 还原。判据 = **组 176** + `HH WIRING CHECK`。
  · 取证命令 `/eh go 喂食探针`（`扫书` / `施放 <名>` / `喂 <包> <格>` / `拖` / `收光标`）——**真机四项待实测**见该文件头部注释。
    ★含「**点击分派**」一行（注册右键结果 / 左右键计数 / 最近 button 与**原始参数形状**）。
  · ★★★**本客户端 OnClick 的参数形态不固定**（用户实测：右键「选食物」打不开）：照教科书写 `function(_, button)`
    会在 `self` 占第一位时拿到 **nil** → **右键掉进左键分支**（去喂食了）。正解 = 主程序已实测的**四候选**写法
    （`(type(a)=="string" and a) or (type(b)=="string" and b) or (type(arg1)=="string" and arg1) or "LeftButton"`）；
    判据 组 176⑮（四种形态 + 「左键不许开菜单」反向哨兵）。
  · ★**状态（用户决定）**：用户说「这个工具先放着以后测试」→ **停在「已实现 + 双闸门绿 + 未提交/未实测」**；
    默认**关**（`tb.feedPet` 空 = 关）+ 载入期零副作用 ⇒ **放着不影响任何现有功能**。
    回来继续时：读 `.dsh/reports/hunter-helper-impl.md`（实现说明 + 16 步真机测试流程 + 四个待实测项）。
- **当前版本（源码唯一真值）**：`EvalHelp.lua` 的 `local VERSION` == `EvalHelp.toc` 的 `## Version` = **1.74.27**（待发布 v1.74.27）
  （已发布；`CHANGELOG.md` 最新小节 v1.74.0 已把 **1.73.35 ~ 1.74.0**（85 个提交）归纳成 7 条里程碑）。
  ★1.73.35~1.73.67 那批工作（分享封皮/品阶评分/头衔抽卡/彩蛋/角色扮演反应/标题栏徽标/取证探针）已随 **v1.74.0** 一起发布。
  ★**逐版本流水一律不进本文件**（见文件头写作纪律）——要点查源码注释 / `CHANGELOG.md` / `git log`；
  本节只保留**在途专题的结论**（下面那条方案分享）。
- ★★★**方案分享「隐藏载荷 + 信息行」**（1.73.41~1.73.67，分支 `probe/share-hide-link`）→ **已随 v1.74.0 发布**，
  细节见 `CHANGELOG.md` 的 v1.74.0 小节与 §5.2 的分享条目。这里只留**必须随时可查的硬事实**：
  · 分片形态 `|cff9ad4ff|HEHPF:<id> <i>/<n>:<hex>|h[秘籍传输中...p%]|h|r`（标签**不带方案名**、只报进度，文案走 `SH_CHUNK_LABEL` 三语言，判据 组 144②）；速率 `SH_SEND_RATE=1.0`（每秒 1 片；0.5 秒会时好时坏）。
  · 信息行（最后一步，一段色码）`|c<品阶色>|HEHPF:<id> 0/1:0|h[<符号><品阶>秘籍·<名>]|h|r  <评语>`。
  · **点聊天里的分享链接 = 只弹出确认窗，绝不自动导入**（[导入] 是唯一写入路径，判据 组 144③ / 145③④⑥）。
  · 色码与形态规则见 §5.2；源码检查 `SHARE MSG SHAPE CHECK` / `COLOR CODE LEN CHECK` / `SHARE PALETTE CHECK`。
  · 取证命令：`/eh go 封皮测`（编号变异测）· `分享探针`（发送留痕）· `色码测`（在用色码逐条实发）· `名号色`（彩蛋名号色候选）。
- **★工作流铁律（用户定）**：**默认**——用户实测验证通过之前**不发版、不推送**（改动只落工作区文件，让用户 `/reload` 直接实测；
  ★**报告里不要催促提交**）。
  ★★**1.71.6 起用户追加**：「**下次完成测试可以直接提交版本**」——即**本地测试双绿（两条都 exit 0）即可直接 commit + 打 tag**，不必等游戏内实测；
  **推送仍需用户明确要求**（v1.71.3~v1.71.24 已提交 + 打 tag；★**v1.72.0 是用户明确要求发布后推送的**——
  这批 22 个版本积压太久，合并成 1.72.0 一次推到 origin + github 两端）。★1.71.1/1.71.2 两次发版也是用户明确要求的结果。
- **数据检索 Tab4（在途主功能）**：
  - **数据源**：`UnrealQuestData` 全局表**懒惰读取**（EvalHelp 载入早于 UnrealQuest，载入期拿不到）；对方缺席时整页只显示**安装引导**并**收起全部交互控件**（1.70.46）。
  - **硬依赖**：地图/图钉/坐标/tooltip 全部复用 UnrealQuest API（1.70.9 用户拍板，自实现回退已删）；引用它的素材必须**原样抄它的路径常量**。
  - **分层**：`EVAL_DS_SEARCH`/`DETAIL`/`SHOWMAP` 逻辑层与 UI 分离，可 node 直测；反查索引懒构建 + 会话缓存。
  - **标注层**：统一单池 + 16 类别 + 地图绑定（`DS_ANN_MAX=500`）；**tick 帧必须挂 `WorldFrame`**（挂 `UIParent` 会因全屏地图隐藏 UI 而整个停摆）。
  - **测试**：组 42 系列（搜索/详情/地图/标注层/日志通道）+ 组 61~65（窗口尺寸/剩余时间/依赖提示/真实接线）。
- **自查清单**：任何 .lua 改完必跑 `node luacheck.js` + `node test_engine.js`（见第一节铁律 1），**两条都要 exit 0**。

## 九、版本要点汇总（最近 10 版，每版一行；完整记录见 CHANGELOG.md 与 git log）
1. **1.74.27** — 🧹 稀有提醒转播**提取为独立模块** `tools/RareWatch.lua`（主程序只留两个接线点）+ **工具箱开关**（读写走实现自己的单一来源；打包基准 69）。
2. **1.74.26** — 🧹 点名字**只做一件事**：`TargetByName(名字)` 选中它，选不中**就报错**；按用户定案删掉所有与任务插件**机制**的耦合（坐标 / 最近刷新点 / 地图投影 / 开图 / 距离文案）。
3. **1.74.25** — 📏 切目标文案纠错：用户截图实锤「它没刷」而真因是**客户端只认附近单位**（556 码）⇒ 改成说清限制 + 报出距离；新增 `/eh go 稀有 目标探针`。
4. **1.74.24** — 🎨 稀有提醒名字按**品阶染色**（银 / 蓝 / 紫 / 橙，整条只一段 8 位色码）+ 可点链接。
5. **1.74.23** — 🔔 **稀有提醒转播**：包住 UnrealQuest 弹窗唯一出口 `RareAlert:Show`（返回值透传、原错照抛），装不上自动退化为轮询它的公开计数。
6. **1.74.22** — 🧩 模版收录「神圣风暴」（骑士·Rainbow 分享）+ 模版按**艾泽拉斯体系 × 自身品阶**重命名 + 作者 / 备注字段 + 神级配色改亮蓝。
7. **1.74.21** — 🎯 神级门槛 120 → **50**；封顶与示例全部**从档位表现算**。
8. **1.74.20** — 👤 **配置分角色存**：三个助手整块（15 个键）搬到 `EVAL_HELP_CHAR`；`tbCfg()` 改路由代理（零改动点）。
9. **1.74.19** — 🏅 **评级与头衔重做**：空技能 0 分、条件按类加权 1/2/3、单条上限 12、**覆盖封顶**、头衔逐级满足。
10. **1.74.18** — ⇕️ 战斗 UI 技能图标带**自动换行 + 自适应高度**；行数公式 BUILD 与 tick 共用一份。
