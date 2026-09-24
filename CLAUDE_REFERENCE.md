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
# quest/ 只拷插件要用的三个 .lua（fetch.js/sweep*.js/build*.js/audit.js/chains.js 是开发脚本、cache/ 是抓取缓存，都不进包）
New-Item -ItemType Directory -Force "$staging\EvalHelp\quest" | Out-Null
Copy-Item "$src\quest\QuestData.lua","$src\quest\QuestBulk.lua","$src\quest\QuestChains.lua" "$staging\EvalHelp\quest\"
Remove-Item "$staging\EvalHelp\media\Textures" -Recurse -Force -ErrorAction SilentlyContinue  # 主题素材不进包
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $out)
Remove-Item $staging -Recurse -Force
```
★**装完必须核对条目数**（1.75.0 基准 = **72 个**（+`quest/QuestData.lua`、`quest/QuestBulk.lua`、`quest/QuestChains.lua`；1.75.9 新增 QuestBulk = 全量任务/装备数据）；1.74.30 时是 69（+`tools/RareWatch.lua`）；1.74.12 时是 68、1.74.6 时是 66、1.73.5 时是 63；1.74.5 陆续加了 `tools/IconGrid.lua` / `tools/HunterHelper.lua` / `tools/ConsumableHelper.lua`，1.74.7 加 `tools/DismountHelper.lua`，1.74.27 加 `tools/RareWatch.lua`）：
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
- ★**toc 载入顺序（以 `EvalHelp.toc` 为唯一真值）**：`Locales/{zhCN,enUS,ruRU}` → `Core` → `Engine` → `EvalHelp` → **`examples/*`（11 个数据文件，必须排在 EvalHelp.lua 之后）** → `Toolbox` → **`quest\QuestData.lua` → `quest\QuestChains.lua`（★1.75.0 任务线：数据 → 逻辑，**必须排在 DataSearch 之前**——后者读 `EVAL_QC_*`；同目录的 `fetch.js`/`chains.js`/`build.js` 是**开发脚本、不进发布包**）** → `DataSearch` → `Share` → **`IconSem`** → `IconBrowser` → `PetData` → `PetHelper` → **`tools\IconGrid.lua`（共用网格件，必须在两个助手之前）** → **`tools\HunterHelper.lua`** → **`tools\ConsumableHelper.lua`**（★`EXAMPLES TOC CHECK` 守着「磁盘 ↔ .toc 双向一致 + 顺序 = 选单顺序」；`IconSem` 必须在 `IconBrowser` **之前**——后者读它的 `EVAL_ICON_SEM`）。
  ★子目录模块（`tools/`）在 toc 里写 **`tools\HunterHelper.lua`**；它们**载入期零副作用**（只定义函数与常量），图标帧在用户打开开关时才建。
  ★**共用件纪律**：喂食与消耗品助手共用 `tools/IconGrid.lua`（网格 + `EVAL_IG_SCAN_BAGS` 扫背包 + `EVAL_IG_TOPLEFT` 位置换算）——
    同一内容不许两处各写（本项目铁律）；1.74.5 实踩一次「`IG.pages` 一名两义」（页号表被总页数覆盖 → 选完食物点格子报错且不收起），已拆成 `pageOf`/`pages`。
- ★**新增 .lua 模块要同时改四处**：① `EvalHelp.toc` 载入列表；② `test_engine.js` 的加载数组
  （**7 处清单**：DECL ORDER / LANG KEY / LANG SOURCE（自动发现，已含 `tools/`）/ COMMENT SWALLOW /
  FRAME NAME CLASH / COLOR CODE LEN / 主加载循环 —— 漏一处就是那一类检查的盲区，本项目踩过）；
  ③ `DECL ORDER CHECK` 的文件清单（**目前 17 个**：EvalHelp/Core/Engine/Toolbox/DataSearch/Share/IconSem/
  IconBrowser/PetData/PetHelper/**tools/IconGrid**/**tools/HunterHelper**/**tools/ConsumableHelper**/
  **tools/DismountHelper**/**tools/RareWatch**/**quest/QuestData**/**quest/QuestChains**）；④ ★**发布包清单**（第 9 步的 Copy-Item 行）——
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
- **当前版本（源码唯一真值）**：`EvalHelp.lua` 的 `local VERSION` == `EvalHelp.toc` 的 `## Version` = **1.75.0**（未发布；v1.74.27 是最后一个 tag）
  （**v1.74.27 已发布**；`CHANGELOG.md` 的 `## 详情小节` 最新到 **v1.74.6**，`v1.74.7 ~ v1.74.28` 只保留**顶部速览表**一行一版（1.74.28 = 两个助手弹窗候选按物品类型过滤）。
  ★`CHANGELOG.md` 的 `## 🎯 v1.74.0` 小节已把 **1.73.35 ~ 1.74.0**（85 个提交）归纳成 7 条里程碑）。
  ★1.73.35~1.73.67 那批工作（分享封皮/品阶评分/头衔抽卡/彩蛋/角色扮演反应/标题栏徽标/取证探针）已随 **v1.74.0** 一起发布。
- **1.74.9 记忆体瘦身（本机会话）**：常驻卷 `CLAUDE.md` **86,364 → 63,984 字节**（回落到 65,536 预算内，尾部不再被截断）：§3 对照表 / §5.2 两条长案例 / §5.4 UI 全量 / §5.5 API 全量 → 参考卷 **§十**（原文照存）；新增常驻卷「**记忆体写入纪律**」+ 参考卷 **§十一**（上下文成本实测 · 度量法 · 搬迁套路）；`sync_game.js` 加「本机无需同步」自检。
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
1. **1.75.0** — 🧭 **数据检索新增「任务线」+ 地图标注右侧的「任务线推荐」弹窗**（`quest/` 独立目录）：10-30 级 **22 条经典链 / 88 任务 / 62 奖励（39 武器）**逐条抓自 `database.emberveil.org`；**奖励优先**（精良武器排最前）+ **完整上下级步骤**；奖励行悬停出原生物品详情、步骤行点击进任务详情；抓取脚本（`fetch.js`/`chains.js`/`build.js`）**与插件零耦合**；数据自带 ⇒ **UnrealQuest 缺席照样能查**；★**弹窗 v2**（数据检索 · 地图标注右侧）：**装备优先**（按可获得等级列装备 + 真实物品图标 → 点装备**反查来源任务线**与完整步骤 → **[在数据检索中查询]** 直连 `EVAL_DS_SEARCH_NAME`）+ 两个视图 Tab（装备/任务线）+ 9 行分页列表 + ▲▼/滚轮 + 四档筛选（等级/类型/档位/阵营）+ 拖动柄；默认关、OnHide 收下拉。
  ★1.75.7 调（用户要求「将返回放置在下一页右边 · 整体按钮左对齐」）：底部按钮顺序改为 **[上页] [下页] [← 返回]** —— 按钮组起点 `QP_NAV_X = QP_PAD`（整体左对齐），返回按钮 x = `QP_NAV_X + (QP_BTN_W + QP_BTN_GAP) * 2`（第三位）。判据 = CHECK（按钮组起点 = 内边距 + 返回必须在第三位）+ 组 192 ⑧h（读真控件 `GetLeft` 验 x 递增；桩不返回几何就如实降级由 CHECK 守）。变异 M14 捕获。
★1.75.6 修（用户截图「样式有点重叠」）：详情**标题压住副标题** —— 根因 = 标题用 `SetPoint("LEFT", qpDetIcon, "RIGHT")` 锚在 **36 高**的大图标上 = **垂直居中**（≈ y −74），而副标题正好也在 −74 ⇒ 必然压字。正解 = 两者都以**图标右上角**为锚、**垂直依次排**（标题 −2 · 副标题 −20），字号/语言变化都不会再压。判据 = `QUEST PANEL CHECK`（钉锚点写法 + **禁**旧的 `LEFT` 写法）+ 组 192 ⑧i（读 `GetTop` 验几何；**桩不支持就如实降级**，绝不假红）。
★1.75.5 修（用户截图「底部按钮不见了」）：翻页按钮**同时进了 listWidgets 与 detWidgets 两份互斥清单** ⇒ `qpShowView` 先 Show（list）后 Hide（det），列表视图下**整个消失**。正解 = **不进任何互斥清单**，由 `qpShowView` **末尾显式 Show**（两视图都常显、位置不跳）。★★可见性契约的又一实例：**同一控件只能属于一份显隐清单**；判据补 CHECK（禁进互斥清单 + 必须显式 Show）与组 192 ⑧h（**两视图下翻页按钮都必须可见** —— 这正是漏过的那条：只验了「详情控件在列表视图要隐藏」，没验「列表自己的按钮要显示」）。变异 M13 捕获。
★1.75.4 追加（用户要求，三条）：① 翻页**不用图标**，改**文字按钮 [上一页][下一页]**（复用图标库 `IB_PREV`/`IB_NEXT` 键），放**底部 [返回] 旁边左对齐**（位置由 `QP_NAV_X = QP_PAD + 64 + QP_BTN_GAP` 单一来源算）；② **焦点离开必须隐藏装备信息**（旧实现 `OnLeave` 只复原底色 ⇒ 原生 tooltip 残留）；③ **详情大图标可获取焦点并显示装备信息**（Texture 收不到鼠标 ⇒ 加了 36×36 的覆盖 Button）。★顺带修：`EVAL_QP_SHOW` 从不调 `qpShowView` ⇒ **首次打开**时详情专用控件（返回/大图标/数据检索钮）在列表视图里露着（用户截图里正是这个）。变异 M12（翻页改回图标式）被 CHECK 捕获。
★1.75.3 追加（用户要求，三条）：① **滚动区铺满窗口** —— 行数**按窗口高度现算**（纯函数 `EVAL_QP_ROWS_FOR(h, top, rowH, tail)`，17 行/页），**禁写死**（图标库那种 `IB_ROWS = 9` 照搬会留白，用户在图 3 圈出）；② 装备详情 **36×36 大图标 + 12 号大标题（品质色）+ 副标题（属性）**，图标仍只取 `GetItemInfo`；③ 放大镜素材换成**本插件自带** `Interface\AddOns\EvalHelp\media\icons\database`（与图标库同款），点击后**不关窗**，只回执一行「已送数据检索：<任务名>」（★旧判据「点完应收起」已按要求**反转**成「必须仍在显示」）。变异 M10（又关窗）/M11（行数写死）均捕获。
★1.75.1 追加（用户要求）：**阵营严格三分类**（联盟/部落/共有 —— 旧写法把「共有」并进联盟/部落，`c.f ~= "B"` 那半句已删）；**每个任务节点左侧放大镜**（素材 `INV_Misc_Spyglass_01_TEX`，与 PetHelper 同源；点了按**任务名**（不是链名）走 `EVAL_DS_SEARCH_NAME` 直达数据检索）；装备视图三个筛选（等级/类型/阵营）⇒ 读值口 `EVAL_QP_SET_FILTER(a,b,c)` 三参。
  ★v1 事故（务必记住）：`local b = dsBtn(..., function() b.btn ... end)` 里的 b 是**全局 nil**（local 作用域从声明之后开始）→ 点按钮当场红字；另有「label 传空串 = 空白按钮」「详情行压住底部按钮」两处 UI 事故 —— 判据分别落在 `QUEST PANEL CHECK`（自引用检测/空白按钮检测/**布局重叠独立验算**）与组 192。变异 M3/M4/M5/M7 全捕获。
2. **1.74.30** — ⏱️ **射击计时 + 条件「距下次射击」**：探针真机定案（法术频道含「自动射击」的原文 = 锚点、`UnitRangedDamage[1]` = 射速 2.09s，与近战**双锚点互不干扰**）；数值条件 `shotLeft`（文本 `距射击<0.5`、初始值 0）；修「切换条件类型把 30.0 带进时间型」；消耗品助手左键不再弹窗。
3. **1.74.29** — 🖼️ 战斗UI **激活方案格品阶色边框** + 两个助手弹窗候选**原生物品详情** + 喂食助手 `GetPetHappiness()` **快乐度边框**（开心亮绿 / 一般金 / 不开心红 / 无宠物默认金）。
4. **1.74.28** — 🧺 两个助手弹窗候选**按物品类型过滤**（品质 → `GetItemInfo(链接)` → **自建 tooltip 兜底并自愈客户端缓存**；药草矿物材料等全剔，判不出不剔）+ 验证命令。
5. **1.74.27** — 🧹 稀有提醒转播**提取为独立模块** `tools/RareWatch.lua`（主程序只留两个接线点）+ **工具箱开关**（打包基准 69）。
6. **1.74.26** — 🧹 点名字**只做一件事**：`TargetByName(名字)` 选中它，选不中**就报错**；删掉所有与任务插件机制的耦合。
7. **1.74.25** — 📏 切目标文案纠错（真因 = 客户端只认附近单位）+ 目标探针。
8. **1.74.24** — 🎨 稀有提醒名字按**品阶染色** + 可点链接。
9. **1.74.23** — 🔔 **稀有提醒转播**：包住 UnrealQuest 弹窗唯一出口 `RareAlert:Show`。
10. **1.74.22** — 🧩 模版收录「神圣风暴」+ 模版按品阶重命名 + 作者/备注 + 神级改亮蓝。

## 十、常驻卷瘦身移出（1.74.9 审计 · 原文照存）

> 常驻卷 `CLAUDE.md` 超出工作区指令预算（65536）会被**截断加载**，故把下列**明细整段**移到这里（**原文未改一字**），常驻卷里保留一句话索引与必须随时可见的铁律。
> 要查下列内容按标题搜本节即可。

### §3 铁律 3：Heart / C 参考实现「按问题查哪个文件」9 行对照表（原文）

### 3. ★★★队伍/团队·血量/蓝量·buff/debuff 检测 → 先读 Heart（及它依赖的 C 库）（用户明确定，1.70.46）
- **用户原话**：「涉及到团队/队伍信息获取，血量，蓝量，buff/debuff 等检测 参考 `D:\game\TurtleWoW\Interface\AddOns\Heart` 插件的实现机制」。
- **触发条件**：凡涉及 **队伍/团队（party/raid）成员枚举 · 单位解析（名字 ↔ unit id）· 血量/蓝量/资源与百分比 · buff/debuff 检测（有没有 / 层数 / tooltip 文本 / 已持续时长）**，或遇到「**客户端根本没给这个 API**」——第一个动作是去读 Heart 与 C 的对应实现，不要自己从零推。
- ★**本机就是游戏主机**（用户 1.70.46 明确）：**EmberVeil**（`G:\...\Emberveil\live\Azeroth`）与 **TurtleWoW**（`D:\game\TurtleWoW`）都在本机，**可直接读对方源码、也可直接进游戏实测**——不存在「另一台机器」，不要再拿远端当借口。
- **读哪里（按问题定位）**：

  | 问题 | 先读 |
  |---|---|
  | 名字 → unit id（从聊天/战斗文字里的人名反查单位） | `C\C_GetUnitID.lua`（缓存 `C_player_map` + `UnitExists`/名字复核 + 「慢查」遍历 `raid1..N`/`raidpetN`、`party1..N`/`partypetN`、`player`/`pet`、`target`/`targettarget`/`mouseover`） |
  | `target`/`mouseover` → 具体队伍成员 | `C\C_AKA.lua`（用 `UnitIsUnit` 逐个比对，返回 `raid3`/`party1` 之类；便于把当前目标当成员查数据） |
  | buff/debuff 全量采集的数据结构 | `C\C_SetPlayerData.lua`（**16 buff + 16 debuff 槽**扫描 → `C_player_data[名字].Buff[纹理] = {Name,Type,Text,Count,Tick,Time}`） |
  | 采集驱动 + 多插件共用时的仲裁 | `C\C_UpdatePlayerData.lua`（遍历 raid/party/target/targettarget/mouseover/pet；★**同一轮更新只允许一个调用者**） |
  | 「某单位有没有某 buff/debuff」 | `C\C_UnitGotBuff.lua` / `C\C_UnitGotDebuff.lua`（按**名字**查 `C_buff_texture_map` → 纹理 → **要求 `Tick == CurrentTick`** 才算「有」，且返回**数据条目**而非布尔） |
  | **用 tooltip 读客户端没暴露的信息** | `C\C.xml`（隐形 `C_Tooltip`）+ `C_GetBuffData` / `C_GetDebuffData` / `C_GetSpellData` |
  | 队伍/团队主逻辑、血量优先级与治疗决策 | `Heart\Heart.lua`、`Heart\Heart_Helper.lua`（`UnitHealth`/`UnitHealthMax`/`UnitMana`/`UnitPowerType`；`hpDeficit = UnitHealthMax - UnitHealth`、`priority * (healvalue / UnitHealthMax)` 的权重算法） |
  | 事件与跨插件通信 | `Heart\Heart_event.lua`（`RegisterEvent` / `SendAddonMessage`）、`Heart\Heart_Hooks.lua` + `Plugins\*_Clicks.lua`（**钩各种单位框插件**） |
  | 图腾 / 需要 tooltip 扫描的跟踪 | `Heart\Heart_Totem.lua`（31 处 tooltip 调用） |

- **★必抄的五个机制（「实现机制」的干货）**：
  1. **隐形 tooltip 当 API 用**（`C.xml`）：`<GameTooltip name="C_Tooltip" hidden="true" inherits="GameTooltipTemplate">` + `PLAYER_LOGIN` 时 `SetOwner(UIParent,"ANCHOR_NONE")`（1.10 hack）与 `SetClampedToScreen(0)`（1.11 hack）。读取时**先清要用的行再 Set**（`C_TooltipTextLeft1:SetText()` 无参 = 清空），再 `C_Tooltip:SetUnitBuff(unit, slot)` / `SetUnitDebuff` / `SetSpell` / `SetAction`，然后 `GetText()` 取行——**buff 的名称/类型、第二行文本（常含剩余时长）、法术的耗蓝/射程/施法时间都从这里来**。
  2. **Tick 新鲜度**：每轮刷新把 `CurrentTick + 1`；查询侧要求 `entry.Tick == CurrentTick` 才算「现在有」——**从结构上杜绝把上一轮/过期数据当成现行状态**（比「加时间戳自己判过期」更简单可靠）。
  3. **贵调用只在「新出现」时做**：tooltip 调用很贵 → 只有**首次见到**该 buff 才去读；已知且**层数未变**时只刷新 Tick 并累加 `Time`，不做 tooltip；扫描时 **buff 与 debuff 槽都空就提前 return**（正合「频率防护总则」）。
  4. **名字 ↔ unit 解析与宠物命名约定**：宠物一律 `主人名-宠物名`；反查先走缓存再「慢查」，**缓存命中也要用 `UnitExists` + 名字复核**（unit id 会变）。
  5. **共用更新函数的单调用者仲裁**：`C_UpdatePlayerData` 用 `C_last_update_player_data_caller == this:GetName()` 判断，**别人正在这一轮更新就直接 return**，并用 `GetTime()` 统计本次耗时——多插件共用一份数据时的去重与自测。
- **⚠️ 重要边界（别抄错东西）**：Heart/C 是 **TurtleWoW** 客户端插件，本项目跑在 **EmberVeil**；本机的 `C\C.lua` **已被用户改写**成「治疗施法监控（CastingSpeed）」并依赖 **SuperWoW** 扩展（`SUPERWOW_STRING`、`UNIT_CASTEVENT`、`UnitExists(unit)` 第二返回值 = GUID）。→ **参考它的机制与范式，但每个 API 在 EmberVeil 上是否可用必须实测**（本项目另有「EmberVeil 无 SuperWoW / 无 UnitCastingInfo」的记录，别因为 Heart 能用就假定我们也能用）。


### §5.2 两条长案例：1.74.5 回声忽略真凶 + 1.74.4 分片取证探针（原文）

- ★★★1.74.5 **「回声忽略」误判真凶**（用户报「盗贼方案分享无弹窗，其他正常」+ 探针 ⑤ 实锤「收齐 → 回声忽略 IS_MINE=true」）：
  【根因】旧「自己方案回声忽略」判据 = `EVAL_SHARE_IS_MINE(text)`（**接收方库里有没有这份方案**的文本比对）——
    只要接收方**恰好已有**这份方案（同账号共享库 / 以前导入过），就把**别人发的**误判成「自己的回声」吞掉、不弹窗。
    ★本意是「忽略**我自己发**的回声」，但旧判据只看「我有没有」、不看「**是不是我发的**」。
  【修法】判据改成 **`shIsSelfEcho(sender)`（发送者是不是本机玩家，剥色码/剥「-服务器」后缀）**：我发的才是我的回声；
    别人发的，哪怕我库里有同款，也是**别人的分享**，该弹。`EVAL_SHARE_IS_MINE` 函数保留（它自身的单测 5193/8182 仍验它，只是不再用于这一刀）。
  【判据】组 82 ①/①b/③：本人(测试玩家)发 → 忽略；**非本人**(彩虹)发、库里有同款 → **该弹**；说来源照旧弹。
    端到端复现：iotol 发盗贼（接收方库里有同款）→ 待导入=盗贼（修复前=被吞）；本人自发 → 仍忽略。变异 M569/M570 捕获。
  ★★两个教训：① 「自我回声」的判据**必须锚在「发送者是我」**，不能锚在「内容像我」—— 内容匹配会把「别人发的同款」误杀；
    ② 上轮（1.74.4）我按存档日志判「IS_MINE 没触发」是**误判**（日志环缓冲没覆盖到 / 搜索没命中），是探针 ⑤ 一屏定案它其实触发了 ——
    「能做成命令就别让用户手工复现」的价值又一次实证；★「按日志判没发生」≠ 真没发生，日志是环缓冲会覆盖。
- ★★1.74.4 **「分片到了却不弹」取证探针**（用户报「某角色(iotol)分享，对方不弹窗，其他角色正常」，静态查不出因）：
  新增 `SH.dbgChunks`（环形 8 条）+ `shDbgChunk(stage,msg,extra)`，在 `shOnMsg` 的**解析 / 入缓冲 / 收齐 / hex还原失败 / 过大 / 回声忽略 / 弹窗**
  各分叉点记录**原文+走到哪一步**，`/eh go 分享事件` ⑤ 摊开 —— 只记含 `EHPF` 的消息（低量，不碰普通聊天）。
  ★价值：把「分片到了却没弹」从「猜」变成「看到真实载荷 + 死在哪一步」（解析✗=载荷格式不对 / 只入缓冲没收齐=丢片 /
  回声忽略=IS_MINE 误判 / hex还原失败=坏 hex / 过大丢弃 / 弹窗=其实弹了）。
  ★同案顺手修探针假「未注册」：本客户端 `IsEventRegistered` 返回 **`1` 不是 `true`**，旧探针按 `== true` 判 → 全显示「未注册」，
  与实际收到事件（③）自相矛盾、把排查带偏；改判 `(r == true or r == 1)`。
  ★排查过程坐实（排除项）：当前代码对 队伍/队长/私聊 三事件**都能走完弹窗**（harness 复现全过）· IS_MINE 回声忽略**没触发**
  （存档日志无「已忽略（自己的方案回声）」）· 接收配置 recv=true · 分片载荷 `i/n:hex` 自 `975e6f1` 起就有（带「秘籍传输中」标签即新格式）。


### §5.4 UI 与布局 全部逐条判据（原文：品阶色/评分口径/覆盖封顶/头衔晋升/分角色存档/滚动分页/滚轮/弹窗/菜单/技能格等）

### 5.4 UI 与布局
- ★★★标题栏（两窗同一实现）＝玩家名→头衔→品阶徽标→方案名＋右侧两开关；两窗各自 BUILD＋tick 刷（只开状态UI 也要跟·组 168⑤）；头衔取 `EVAL_TITLE_CURRENT()`；色码→RGB `EVAL_COLOR_RGB`（8 位）；CHECK `UI TITLE BADGES CHECK`/`UI TIER BADGE CHECK`/`UI TITLEBAR CHECK`/`UI TITLE NAME CHECK`；组 162/163/164/166/168。
- ★★品阶唯一源 `SH_SEAL_TIERS`：**1.74.21 起** ≤11 普通/12-23 稀有/24-35 珍稀/36-49 绝版/**≥50 神级**（用户定神级 = 50；低四档把 0~49 四等分）；色走 `SH_SEAL_TIERS[].color`（★1.74.22 用户定：**神级 = 亮蓝 |cff00bfff**；配色史 暗金 b87333 → 亮蓝 00bfff → 深红 c00000 → 亮金 ffcc00（试色）→ 亮蓝 00bfff）；`SHARE PALETTE CHECK` 守色码不重复；判据钉边界两侧（11/12 · 23/24 · 35/36 · 49/50）；组 143/146/147/195/196
- ★★★**评分口径（1.74.19 重做，用户「增加评级难度」）**：`EVAL_PROFILE_SCORE` = Σ(每条技能)[ 有条件 ? 1+Σ条件权重 : 0 ]；
  **空技能 0 分**（旧口径白送 1 分 ⇒ 25 条空技能就神级，实测复现过）；条件按类加权 **自身/技能 1 · 目标/光环 2 · 队伍/候选 3**（表在 `SE_TYPE_GROUPS` 的 `w`/`cov`，**唯一来源**）；
  单条上限 12 分；同一行里**完全一样**的条件只算一次；★不占动作条的特殊技能（`EVAL_NO_SLOT_OK`）无条件**保留 1 分**（用户定）。
- ★★★**覆盖封顶**：覆盖 1/2/3 个大类分别封顶 **23/35/49**（值从 `SH_SEAL_TIERS[n+1].max` **现算**），**≥4 类才不封顶** ⇒ 神级必须跨类写；
  ★**带方案表的调用点一律走单入口 `EVAL_PROFILE_TIER(p)`**（`EVAL_SHARE_SEAL_TIER(score, coverage)`；**coverage 传 nil = 不封顶**，别把纯分数调用点误伤）；`COVERAGE CAP WIRING CHECK` 守「没人再写 `EVAL_SHARE_SEAL_TIER(EVAL_PROFILE_SCORE(p))`」。
- ★★★**头衔晋升（1.74.19）**：`SH_TITLE_REQ = { 1, 2, 3, 3, 2 }`（稀有+≥2 · 珍稀+≥3 · 绝版+≥3 · 神级≥2）＋**逐级满足**（断在哪一档就停在哪）；旧口径 2~5 档全是「≥1 个」⇒ 头衔满档只要 1 个方案，连带彩蛋闸门形同虚设。
  ★命令/闸门/样例的分数**一律现算**（`EVAL_SEAL_GOD_SCORE()` / `EVAL_SEAL_TIER_SAMPLE(i)`），不再写死 25 / {3,9,15,21,26} / {1,4,7,10,13}。
- ★★★**配置分角色存（1.74.20，用户「消耗品助手 + 喂食助手 + 骑乘助手整块按角色」）**：新增**角色级存档** `EVAL_HELP_CHAR`（toc 里 `## SavedVariablesPerCharacter` —— 本客户端实测支持：UnrealQuest 已在用、磁盘上 `Saved/Account/<账号>/<服务器>/<角色>/SavedVariables/`）；
  **角色键清单 = `Toolbox.lua` 的 `TB_CHAR_KEYS`（唯一来源，15 个：三个助手的开关/列表/贴图缓存/悬浮件位置）**；`tbCfg()` 返回**路由代理**（`tbMakeRouter()`：角色键落角色表、其余落账号表）⇒ 上百处 `tb.xxx` 调用点**一行未改**；
  ★★**代理的 `__index` 绝不能写 `at and at[k] or nil`** —— `false or nil` 还是 nil，会让所有值为 false 的账号开关被读成 nil（= 用户关掉的开关自己又开了；组 79 当场抓到）。必须 `if not at then return nil end return at[k]`。
  三个助手各自改走 `EVAL_TB_CHAR_STORE()`；老存档里那些键**一次性继承**到每个角色（**账号里那份副本保留** = 还没登录过的角色的种子），迁移挂在 `VARIABLES_LOADED`（**账号表没到位时不许标记**，否则从空表继承出空配置、种子永久丢）；方案库/语言/日志/分享开关**仍旧账号级**；
  `SAVEDVARS SPLIT CHECK`（toc 声明 + 清单唯一来源 + 三助手接线 + **无「按角色键读账号表」的泄漏** + 代理无 and/or）＋组 197（含 false 读回、迁移不覆盖、账号表未就位不标记）。
- ★**COND WEIGHT CHECK 的实战价值**：它上线当场抓到 `target`（「选取目标」，hidden 存量类型）**不在任何分组**里 ⇒ 新口径下会被按 0 分算、也不计覆盖（静默少算）。★「新增条件类型必须进组」由它兜底。
- ★★品阶显示现算（不硬编品阶）：文字＝品阶色、底色×（激活 0.45/否则 0.22）；组 160/167。图标＝IconSem 真纹理 13px；★纯黑＝`EVAL_SHARE_SEAL_ICON` 两返回值内联进 `pcall(t.SetTexture,…)`⇒多返回值禁内联进可变参数调用；`PROF ICON PROBE WIRING CHECK`；组 160⑥⑦。★重锚前 `ClearAllPoints`；文字框留富余（`TPL_TEXT_PAD=4`·组 91）。
- ★★★滚动/翻页/分页标准做法：三段 `[计数]`←8px→`[按钮组]`←10px→`[关闭]`；文字按钮（`IB_PREV/IB_NEXT`、`TB_UP/TB_DN`）、不用 ▲▼；几何唯一源 `EVAL_HELP_CFG_BOTTOM()`（`midY/closeLeft/closeW/rowY/rowH`；拿不到按 `-(H-10-11)`/`W-12-64` 回退）；判据＝中线==关闭中线、按钮组右端 ≤ 关闭左−4、真实 OnClick 能滚；读值口 `EVAL_IB_TEST_BOTTOM()`（组 92）/`EVAL_TB_TEST_SCROLL()`（组 118）。
- ★★★滚轮方向唯一源 `EVAL_WHEEL_DIR(a,b)`（幅度归一 ±1）；6 处全走它；`WHEEL DIRECTION CHECK`（禁位移与方向同号）＋组 115；★断言把方向写反⇒反向 bug 被「验证」通过。
- ★★★数据刷新不许改可见性：`EVAL_WAR_TAB_REFRESH()` 又被开配置窗与 `EVAL_PM_APPLY` 调用⇒可见性只由 Tab 切换负责（`EVAL_HELP_CFG_SETTAB` 的清单）；数据照旧每次刷；组 165＋`EVAL_TEST_WAR_ROWS()`。
- ★★视图切换要把另一视图控件整块隐藏（整表 Show/Hide·组 113②）；`Hide` 过的逐个 `Show`（少一个＝永久不显示·组 113③）；布局审查读真实矩形（`EVAL_PH_TEST_GEOM()`·组 113④）；输入框唯一入口 `EVAL_PH_SET_QUERY`（退回列表）、回写前 `GetText` 比对（否则递归）。
- ★入口控件永远不许藏（默认文案「不限」）；查不到≠没有⇒如实说明（`SE_RANK_NONE`）、不弹单项下拉（组 110⑨）；「隐藏」＝不画不是 `Hide()`⇒背板＋挪出可视区 `DD_SEARCH_PARK=-4000`；锚点＝邻居哪条边（`Minimap` 是圆的⇒`RIGHT` 对 `LEFT`）。
- ★分列切点＝允许切点里两列行数差最小；组是不拆的最小单位；版式抽纯函数；组标题不许孤悬行尾；绝不静默截断（`DD_MAX_ROWS=96` 末行「…… 还有 N 项未显示」、`SH_DETAIL_MAX=6`）；不变量读真实几何（本列内/同 y 两列各自成行/不跨列/行数差 ≤2）。
- ★★类别独立一行＝标题独占一行＋本组按钮从下一行排、放不下换行；窗高变高（660×240→660×340）；`rowsOf` 与摆放循环必须逐字一致，用「自报 `rowsL/rowsR` vs 真实控件行数」钉住（组 91）。
- ★工具箱两列（按组边界切、取两列行数差最小）：列宽＝(可用宽−列缝×(列数−1))/列数、< 200 退单列；列不相交要几何断言（每控件显式限宽·组 120③）；★★★读值口绝不许复刻映射逻辑（`EVAL_TB_TEST_LAYOUT` 又算一遍⇒变异存活）。
- ★弹窗高度自适应条目：唯一源 `EVAL_TB_MENU_HEIGHT(条数)`；判据要换一组条目再比；同一行 y 单一源⇒`TB_ROW_TXT_DY`；判据读真实控件顶边；★别用 FontString 高度算中心⇒配反向哨兵。
- ★自绘风格两步：① 先问能否借用官方件（`UnitPopupMenus`/`UnitPopupButtons`）但必须先取证；② 不成则半透明底、宽度上限 ≤4 汉字＝62px、条目 ≤4 字、保留原有入口。
- ★多段一行居中（弹窗「接收方案」勾选）：与配置窗同一开关同一真值＋弹出时刷新；判据两段（生产数字验居中＋真实控件验落地）；标签宽实测优先 `GetStringWidth`、拿不到按字符数估（`string.len` 是字节）。
- ★导出 token、界面本地化＝同一份格式化＋一个开关：`EVAL_COND_STR(cd,disp)`/`EVAL_GROUP_STR(groups,disp)` 让界面走语言包、导出与往返一律 false⇒英文 token 逐字不变；读值口 `EVAL_TEST_SE_PREVIEW()`＋反向哨兵；组 125＋`DEBUFF DISPLAY CHECK`。
- ★职业着色＝描述表 `TB_PAINT_LISTS`＋painter＋三纯函数；包装＝先调原函数再叠色＋幂等守卫＋备份存 local；开关关掉＝不再叠色＋立刻重刷；禁用 `hooksecurefunc`；拿不到就不猜；组 119＋`PAINT WIRING CHECK`。
- ★★聊天窗名字着色：一个包装体管两功能（`EVAL_TB_CHAN_INSTALL_ONE`）不叠两层；覆盖所有窗（`ChatFrame1`＝`DEFAULT_CHAT_FRAME`，幂等按入口判、不按名字去重）；缓存唯一 `tbNameClass`；不做自动 /who（`SendWho` 等都是服务器查询）⇒查不到不上色；纯函数 `EVAL_TB_CHAT_COLOR_LINE` 拿不准就不碰；三坑：前 11 字节判富文本会染链接名·字符数≠字节数·`EVAL_SAY` 行不着色；颜色码长度禁写死（`|c%x+`）、诊断分开打（`EVAL_TB_CHATCOLOR_ROUTES`）；`CHAT COLOR WIRING CHECK`（先摘注释）；组 121①⑭。
- ★主动查询（四道闸门）：`TB_WHO_GAP=5s`、`TB_WHO_PEND=8s`、`TB_WHO_MISS_TTL=1800s`、`TB_WHO_QMAX=20`；查询日志只进调试日志（`EVAL_LOGLINE`⇒`/eh logdump`）；「查谁」更严：只认发送者位置的方括号名；`SendWho` 只许在 `tbWhoTick` 里。
- ★分享弹窗：摘要行⇒「X 分享的 [品阶秘籍·名]」带品阶色；品阶行只留图标、删重复文字、没连图标一起删（`EVAL_SHARE_SEAL_ROW` 被组 145 等用）；坐标 `SH_SEAL_ROW_Y` -50→-46·`SH_DETAIL_Y1` -74→-66·dPanel 顶 -46→-42；组 145；★改 UI 文案要同步反转旧判据。
- ★可点品阶色链接（`|HEHPF:<id>` 形态，封皮 B 行与场景描述头衔同款）：点它靠 `EVAL_SHARE_CLICK_OPEN("EHPF:<id>")` 在 `SH.recent` 找（用 `SH.pending.idh`）⇒ 重填 `SH.pending` 弹出接收页；超 `SH_MSG_MAX`/缺 id ⇒ 退回纯文本；`shReactionNameLink(p)` 现在是**保留但未接线**（彩蛋取消）；判据组 180②（点头衔链接打开接收页）。
- ★彩蛋角色扮演反应（1.73.64 建 · **1.74.5 起未接线**）：机制/频道表/抽奖/名链接/三语言 50 格文案**全部保留**，但 [导入]/[忽略] **不再发**（改发「场景描述」，见下条）；`SH FUN CHECK` 钉「机制都在 **且** 调用点未接」＋组 170① 仍验每句恰 2 个 `%s`；组 82④⑤ 是**反向哨兵**（点了不发反应句）。
- ★彩蛋创世者亲临闸门：手动创建的方案有**神级**（1.74.19 起 = 封顶后有效分 ≥50，读 `EVAL_SEAL_GOD_SCORE()` 现算，不写死）· 手动方案 **≥3 个**（1.74.19 用户定：不变）· 头衔满档 5；`src`：手工点写 `"manual"`、文本解析在唯一出口 `EVAL_PROFILE_FROM_TEXT` 盖 `"text"`、老存档无 `src`⇒按手动；堵两条路 `EVAL_TITLE_CREATOR_OPEN` 与 `EVAL_TITLE_CREATOR_TRY`；`EVAL_TITLE_EGG_CHECK()` 挂 `EVAL_WAR_TAB_REFRESH`＋登录、只播一次；组 169＋组 150/150⑥＋`CREATOR GATE CHECK`。
- ★★★队伍菜单三条条件（1.74.1，审计定案）：**邀请队伍** = 不在队伍 或 我是队长（修「队长反而邀不了人」的旧 bug）；
- ★1.74.4 邀请队伍再补一刀（用户截图：对方已入队却仍显示邀请队伍）：条件只看「我」的状态是 bug → 改为「**对方不在我队伍/团队里 且 （不在队伍 或 我是队长）**」；队友已入队 → 邀请藏掉（踢出/离开照常）。组 130⑥e2 反转；变异 M568。
  **踢出队伍** = 我是队长 且 被右键的是队友（非队长根本不出现这条，不再是「点了才说不是队长」）；**离开队伍** = 在队伍内显示
  （退队不需权限，与右键的人无关，动作 `LeaveParty()`）。判队长 = `IsPartyLeader()` 或 `IsRaidLeader()`；★助理踢人没有
  `IsRaidAssistant` 接口可判 → 如实接受边界（助理看不到这条，动作里仍有「不是队长」兜底）。成员判定 = `EVAL_TB_NAME_INMYGROUP`
  （UnitInParty/UnitInRaid 反查，party 只扫 1..4）。组 130⑥e/⑥e2/⑥e3 + 组 173 + ⑤b；变异 M564~M567 捕获。
- ★★★技能格按键分派（1.74.2，用户定）：战斗信息UI 技能小图标 **左键 = 快速切换启用/停用**（写 `r.enabled` **配置真值** + 如实播报 + 双刷新 `EVAL_WAR_TAB_REFRESH`/`EVAL_HELP_UI_TICK`）· **右键 = 技能配置弹窗**（开被点那格、不动状态）；格子必须注册 `RightButtonUp`（光注册左键 = 右键永远到不了分派代码）；读值口 `EVAL_TEST_UI_CLICK_CELL` / `EVAL_TEST_SE_SHOWN`；`UI CELL MOUSE CHECK`；组 174。
- ★布局总纪律：需求验性质不验数字；相对量验相对量；同一行中线对齐；中文宽度按字符数估；布局常量单一源（`IO_BW/IO_GAP/IO_PAD`、`CLOSE_LEFT/CLOSE_MIDY`）。



### §5.5 API 与客户端事实 全部逐条（原文：射程/物品 API/纹理路径/IconSem/api 索引有无清单）

### 5.5 API 与客户端事实
- SpellStopCasting()：读条/自动射击/魔杖三类全覆；Protected→须 RunScript（直调无效）；「进度条没了」≠取消。
- AttackTarget()=Toggles 须 IsCurrentAction(攻击格)；Movement 仅 FollowByName/FollowUnit 非 Protected（MoveForwardStart/Stop、TurnLeftStart 是）；FollowByName 空名=当前目标、只搜已知玩家、无返回值、不走 RunScript。
- GetRaidRosterInfo(i) 九返回；越界/非团队只回 nil。
- 1370 API 无 aura 专用函数；GetPlayerBuff(i,f)=增益条 0 基下标；无文件读取 API（无 io/os）→载入文件唯一形式=列进 .toc；★`LoadAddOn` 是 **Protected**（全表仅 13 个）⇒ **文件级懒加载不可能**，只能「toc 预载 + 载入期零副作用 + 首用才建帧」（范式：`tools/HunterHelper.lua`）。
- GetQuestReward 会再触发 QUEST_COMPLETE→须三层防护（同名去重/领取窗口闸门/全局频率上限）；UnitDebuff 第 3 返回=dispel token；UnitMana=主能量且有显示缩放（怒气÷10、幸福÷1000）→判蓝量前先 UnitPowerType(unit)==0。
- 施法 API 全 Protected（CastSpellByName 仅 onSelf/CastSpell/SpellTargetUnit/SpellStopTargeting/SpellStopCasting）；TargetUnit 非 Protected=唯一路径（切目标→UseAction(slot)→还原）；Targetting 另有 TargetLastTarget/ClearTarget/TargetByName/TargetNearestPartyMember。
- ★★★`CHAT_MSG_PARTY_LEADER`/`CHAT_MSG_RAID_LEADER` 是**独立事件**（队长/团长发言）：接收帧**必须也注册**这两个——只注册 `CHAT_MSG_PARTY`/`RAID` 时队长一分享**一片都进不来**（接收端静默、发送端照样报「已发送 N 片」；1.74.3 修的正是这个）；来源判据=触发事件名（队长版映射到「队伍/团队」）；发送侧只留 公会/队伍/说；自查 `/eh go 分享事件`；`SHARE RECV EVENTS CHECK`；组 175。
- 纹理路径=/Game/Interface/Icons/<名>_TEX，写错显 ?；GetNumMacroIcons/GetMacroIconInfo=唯一合法路径入口（1018 条 → doc/图标路径清单.txt）；PET ICON CHECK 校验真存在。
- IconSem.lua（用户要求：名称+多标签+按名/路径过滤）：基础名须剥 _TEX（组 117①b）；过滤=四命中+分组叠加；纹理字面量须在白名单（PET ICON CHECK）；两反斜杠须按两反斜杠匹配（组 112）。
- api_*.html=1370 条索引；无：GetDifficultyColor（有垫片）/PlaySoundFile（只有 PlaySound）/hooksecurefunc/UIDropDownMenu_GetSelectedID；有：GetGuildRosterInfo/GetWhoInfo/GetFriendInfo/GetNumGuildMembers/GetNumWhoResults/GetNumFriends/GuildControlGetNumRanks/GetRealZoneText/RemoveChatWindowMessages。

- ★★★**跨插件：捕获 UnrealQuest 的稀有提醒**（1.74.23，用户「只要知道他发现稀有的那一时刻，在对话框内输出一段文字」）：
  弹窗唯一出口 = `World/RareAlert.lua` 的 `RareAlert:Show(entry, distance, dx, dy, others)`（内部 `SetAlertWindowText → UpdateArrow → Client.ShowObject → shownUntil → 音 → 聊天 → 计数`）
  ⇒ **包住它、在返回后回调 = 卡片已经在屏幕上的那一刻**。模块注册表是**公开**的：全局 `UnrealQuest`（`Core/Namespace.lua:17`）+ `UnrealQuest:GetModule("RareAlert")`（就是 `UQ.modules[name]` 那张**普通表**，`NewModule` 只塞 name/enabled、无元表保护）；
  ★**安装必须等 VARIABLES_LOADED**（AddOns 按目录名排序，**EvalHelp(E) 先于 UnrealQuest(U)**，载入期拿不到对方 —— 与 DataSearch 的 `dsUQModule` 同因；那个是文件内 local，本处提成全局 `EVAL_UQ_MODULE`）；
  ★包装纪律 = **返回值逐个透传 + 原函数抛错照原样 `error(a,0)` 抛出**（吞掉别人的错 = 把别人的 bug 藏起来），只在抛错时如实计数；
  兜底 = `Show` 不可包时轮询对方**公开读值口** `RareAlert:GetStatus().alerts`（单调累计计数；**首读只立基准**，否则会把本次登录前的历史计数当成刚弹过）；兜底 tick 父级必须是 **WorldFrame**（挂 UIParent 开全屏地图会停摆，见 1.70.39）；
  载荷：名字走 `Database:GetUnitName(entry.unitId)`、品阶 `entry.rank`（1 精英/2 稀有精英/3 首领/4 稀有）、`distance` 已是整码、`others` = 同刻另有几只；频率上对方自带「同怪 180s 冷却 + inRange 抖动带」，不会刷屏；
  命令 `/eh go 稀有`（状态/开/关/试；`试` 直接调对方 `TestNearest` 走完整链路自证）；判据 = 组 199 + 源码检查 `RARE WATCH WIRING CHECK`（安装点 / 命令前缀字节数 / 包装透传与照抛 / 兜底 tick 父级）
  染色（**1.74.24** 用户「对稀有精英染色」）：名字按品阶上色（精英 银 c0c0c0 · 稀有 蓝 0070dd · 稀有精英 紫 a335ee · 首领 橙 ff8000 —— 物品品质那套玩家一眼就懂；与「方案品阶」五色是**两个维度**，项目纪律要求错开，故最低档用银不用白）；★**整条消息只许一段 8 位色码**（一条多段会整条不画）⇒ 色码由调用方按品阶给，语言包里不再写死金。
  可点（**1.74.24 → 1.74.26** 用户「点击他可以定位目标」＋「点击头像相当于目标切换到稀有精英目标」＋定案原话「点击名字逻辑很简单.不要和那边插件的机制管理.需求只要是调用类似目标函数选中目标就可以了.如果目标不存在就报错.」）：名字做成链接 `|c..|HEHRW:<名字>|h[名]|h|r`（形态照抄分享封皮那条真机配方：色码在外、链接在里）⇒ **点名字 = 一次 `TargetByName(名字)`**，选中报「已选中目标：X」、选不中报「选不中目标：X」—— **就这一个动作，没有第二动作、没有退路**。★1.74.26 按用户定案**删掉**了所有与那边插件机制的耦合：不再有坐标 / 最近刷新点 / 地图投影 / `EVAL_DS_SHOWMAP` 开图；token 从 `EHRW:areaId:x:y:unitId` 收成 `EHRW:<名字>`（名字是唯一需要的东西）—— 源码检查现在**反向守**：稀有转播里出现 `EVAL_DS_SHOWMAP`/`EVAL_RW_NEAREST_LOC`/`GetCurrentZoneView` 即 FAIL。
  ★★★**1.74.27 提取为独立模块 + 工具箱开关**（用户：「将以上功能提取到独立文件内 ./tools 然后再工具箱内设置开关.」）：整块搬到 `tools/RareWatch.lua`（**主文件只留两个接线点**：VARIABLES_LOADED 的 `pcall(EVAL_RW_INSTALL)`、命令分支 `/eh go 稀有`）；新模块只走**全局桥**（`EVAL_SAY`/`EVAL_LOGLINE`/`EVAL_L`/`rawget(_G,"EVAL_HELP_CONFIG")`），绝不引用主程序文件内 local；工具箱新增「稀有提醒」组 + 开关（Toolbox 的 `t="rw"` 行型）——★**读写走实现自己的单一来源** `EVAL_RW_ENABLED`/`EVAL_RW_SET`，不另存 `tb.rareWatch`（两处真值必然打架）；★工具箱模型 28 条 > 每页容量 26 ⇒ **第 2 页**，判据必须翻页后取控件（`EVAL_TB_TEST_SCROLL_CLICK("dn")` + 新读值口 `EVAL_TEST_TB_CHK_FOR`）；★**新增文件要同步 7 处清单**：toc / 测试载入清单 / DECL ORDER / LANG KEY / COMMENT SWALLOW / WHEEL / COLOR CODE LEN / FRAME NAME CLASH（漏一处就是「新文件永远不被检查」的静默盲区），打包基准 68 → 69（参考卷）；`RARE WATCH WIRING CHECK` 改成**分两段扫**（接线点看主文件、实现模式看两份并集）。判据 = 组 120⑥ + 组 199。
  ★`TargetByName`：**官方 API 索引里有**（category=Targetting），且**不是 Protected**（参考卷 §F3:138 逐条核过）；但它在「附近没有这只」时**静默失败**（官方文档明文「只认附近单位」，`Engine.lua:735-736` 早已记过）⇒ **必须核对结果**：调用后读一次 `UnitName("target")`（否则「点了没反应」会被报成成功）。★对方 RareAlert **明确不做**这件事（自动扫描会抢玩家目标，RareAlert.lua:23-27 有明文），我们只在**玩家主动点一下**时做。
  ★★★**1.74.25 实锤（用户截图，这是本条最重要的事实）**：截图上任务插件导航箭头显示那只稀有在 **556 码**外，而我们写的文案是「它没刷 / 它不在这儿」→ **真因是客户端限制**：`TargetByName` **只认客户端附近的单位**，远处**静默失败**（官方文档 `Targetting#targetbyname` 明文；本项目 `Engine.lua:735-736`、参考卷 §F3 早已记过；参考卷 §F3:138 还确认它**不是** Protected —— 所以「切不到」≠「调用非法」）。
  ★★教训 = **「把自己的限制说成对方/世界的状态」是造谣**：`选不到「X」` 必须**同时报出距离**（`约 N 码`，取转播时对方给的那个数）+ 给出下一步（走近再点 / 右键地图定位），并且**一句话说完**（上一版太长，被聊天框折成两行 —— 截图可见）。反向哨兵：文案里绝不许再出现「它没刷」。
  ★取证命令 `/eh go 稀有 目标探针`：拿**当前目标自己的名字**（必然存在且必然在附近）——先 `ClearTarget()` 再按名字选回来，报 4 步判定。**这是唯一能区分**「客户端只认附近」与「TargetByName 对本插件是空操作」的实验（两者从结果上长得一模一样）；顺带打印库里那份名字与**字节数**，排掉「库名 ≠ 客户端名」这第三种可能。判据 = 组 199⑫（含「它没刷」反向哨兵 + 距离必须出现）与 ⑯。
  ★链接的失败模式是「**整条不画**」⇒ 留了 `稀有 链接` 开关，一键退回**已验证的「只有色码」形态**；命令 `/eh go 稀有 目标|链接|目标探针`；判据 = 组 199⑩~⑯ + `RARE WATCH WIRING CHECK`（4 色逐项 8 位 · 链接**只带名字** · Toolbox 的 `EHRW:` 分派**必须以该语句开头** —— 只查「文件里出现过这串」会被 `if false and …` 骗过，本轮变异测当场撞到 · **反向守**不许再耦合地图机制）。
## 十一、记忆体写入 / 上下文成本实测（1.74.9）

> 常驻卷会随会话反复注入 ⇒「怎么写记忆体」本身就是成本。本节存**实测数据 + 度量方法 + 搬迁套路**（常驻卷只留一句话纪律）。

### 11.1 成本实测（会话 session-3b7c5d3f，5,178 条记录）
- 磁盘日志 6.31 MB（zstd）→ 展开 **19.26 M 字符**；压缩帧 **1,924 个**；JSONL 记录 5,178 条。
- **整份 `CLAUDE.md` 被注入 45 次**（单份解码文本 ≈2.4 万字符 ≈1.5 万 tokens）——每次文件变更都会再注入一份整卷。
- 上次压缩后活动窗口（1,945,361 字符，模型可见）构成：`assistant/message` **66%**（长回复 + `run_code` 脚本正文）· `user/message` + `agent/inbox/spliced` **19%**（注入类）· `tool/call` + `tool/result` **12%**。
- ⇒ **最省的两刀**：① 大段脚本写文件再 `node`（**别塞进 `run_code.code`**）；② 记忆体改动**批量化**、明细进参考卷。

### 11.2 怎么量上下文（别凭感觉）
- 日志路径：`<DSH_HOME>\sessions\--<规范化 cwd>--\<session-id>\session.v3.jsonl.zstd`（本机 `DSH_HOME=C:\Users\EVAL\.dsh`）。
- `request/context` 事件 = **窗口声明**（`contextWindow`）；`compaction/summary` 的 `usage.cacheReadTokens` = **压缩那一刻的真实 prompt**，`shadowedTokenCount` = 被压掉的量。
- 实测：3 次压缩的真实 prompt **393,472 / 393,984 / 446,336** tokens，都在窗口的 **56%~64%** 触发（窗口当时声明 700,000；最新一次请求已声明 1,000,000）。
- **校准法**：把某次压缩之前的可见记录估一遍（CJK×0.95 + 非 CJK÷3.8），与真实 `cacheReadTokens` 相除 —— 干净窗口比例 ≈ **0.61**，据此折算当前窗口的真实量级（实测当前 ≈**40 万** tokens，不是 700k）。
- ★**坑**：`.jsonl.zstd` 是**多帧 zstd 拼接**；Node 的 `zstdDecompressSync` **只解第一帧**（流式解码器读到第二帧报 `Unknown frame descriptor`）⇒ 按 magic `28 B5 2F FD` 扫描切片、逐帧解再拼。

### 11.3 常驻卷瘦身套路（1.74.9 实战：86,364 → 62,810 字节，再补纪律后 63,984）
1. node 统计**每节字节数**（按 `^#{2,3} ` 切段）→ 挑最大的几节下手。
2. node 脚本按**标题锚点**取整段（`findOne` 断言命中唯一、`secEnd` 找下一个标题），**原文照存**追加到参考卷新编号节（§十），常驻卷原地换成「索引 + 铁律 + CHECK 名」。
3. 锚点命中数 ≠1 直接 `exit 2`；替换**从后往前**做，行号不漂移。
4. 常驻卷补**指向新节的索引**（顶部导览 + 末节「什么时候必须去读参考卷」）。
5. 跑 `node luacheck.js` + `node test_engine.js`：★`PACK LIST CHECK` 从**参考卷**读第 9 步打包清单 ⇒ 新节必须**追加在它之后**（本次追加在 §九、§十 之后，检查仍绿）。
6. **一次 commit**（别边改边提交，避免整卷被反复注入）。

## 十二、1.74.29 / 1.74.30 明细（射击计时 · UI 三处补完 · 条件与继承修复）

> 常驻卷只留一句铁律与索引；本节是**全部细节与数据**（探针实测量、跳过的坑、判据与变异编号）。

### 12.1 射击计时（探针真机定案）
- 探针：`/eh go 射击探针`（开/关/报告/清空），报告**同时落盘**（`[射击探针]` 进 SavedVariables ⇒ 事后直接读文件，不用截图）。
- **实测数据**（8 发干净样本）：`UnitRangedDamage(player)` → [1]=2.09（秒/击）· [2]=18.59 / [3]=21.59（伤害上下限，差 3.0 = 弹药）· [4][5][6]=0/0/1（噪声，比值表排除）；`UnitAttackSpeed` 主手 3.20 副手 2；`IsAutoRepeatAction(slot 9)` 可用。
- **锚点通道** = `CHAT_MSG_SPELL_SELF_DAMAGE`，原文「你的自动射击击中X造成17点伤害。」/**暴击**「你的自动射击对X造成30的致命一击伤害。」⇒ 判据只认「自动射击 / Auto Shot」子串。
- **Δt 样本**：2.22/2.13/2.04/2.33/2.03/2.13/2.23 → 均值 2.16 vs API 2.09 = 比值 **1.03** ⇒ 本轮**未观测到**急速差异（首个 1.82 的单样本假象被推翻，故未硬编系数）。
- **自校准**：留最近 6 次 (Δt÷API) 中位数；样本 ≥4 且中位数出 [0.9,1.1] 才修正，否则用 API 原值；离群样本（<0.5× 或 >1.5×）丢弃。
- **状态感知单入口**：`EVAL_SWING_KIND/SPEED/REMAIN_ACTIVE`（自动射击中 → 射击）；战斗UI 金色细条、状态UI 行、条件 `swingLeft` 全部自动跟随；文案分「下次射击 / 下次攻击」。
- **新条件 `shotLeft`**：文本 token「距射击」（也认「距下次射击」/`shotLeft`）、编辑窗名 `CT_SHOTLEFT`（三语）、时间型（0.1 步进 / 0~10）、初始值 **0**；与 `swingLeft` 成对但**显式**（不走状态感知）。
- **继承修复**：旧 `new.op, new.n = old.op, old.n` 无条件继承 ⇒ 从「能量>30」切到时间型会带进 30.0；改为纯函数 `seSwitchCond`：**同参数域才继承 n**（op 始终继承），并顺手把时间型清单变单一来源 `SE_TIME_K`/`seIsTimeKind` 且**上移到使用者之前**（原位置在使用者之后 = 闭包只看到全局 nil）。
- **坑记录**：`DECL ORDER CHECK` 当场抓到读值口 `EVAL_TEST_SE_TYPE_INIT` 写在 `SE_TYPES` 声明之前（真机上是全局 nil）→ 已挪到声明之后。

### 12.2 UI 三处补完
- 战斗UI 激活方案格：`uiProfBtnBorder` + BUILD 建 4 条 1px BORDER 纹理；只有激活格 Show；颜色与文字同源（品阶色，算不出暖金）。
- 弹窗候选（`tools/IconGrid.lua` 共用件）：悬停先 `SetBagItem(bag,slot)` 出原生 tooltip，再补「名称 ×数量 [包,格]」+ 提示 + 已选角标；拿不到 bag/slot 退回文本。
- 喂食助手快乐度边框：复用主图标**既有 4 条 1px 亮边**（`HH.edges`），颜色按 `GetPetHappiness()` 现算：3=亮绿 / 2=金 / 1=红 / 无宠物或接口不可用=默认金；只在建帧/刷新/CD tick/悬停时现算（不新开后台 tick）。
- 消耗品助手左键取消弹窗：面板入口收归右键（左键与「拖动图标」争用同一按键），三语 `CH_MAIN_HINT` 同步。

### 12.3 判据与变异（本轮）
- 组 188 ①~⑦（激活边框 · 物品详情 tooltip · 快乐度边框 · 射击计时 · 距下次射击条件 · 类型切换继承）· 组 177 左键反向哨兵。
- 变异：M1 边框着色 · M2 横排 SetBagItem · M3 候选格 SetBagItem · M4 开心→金色 · M5 探针开关 · M6 「自动射击」守卫 · M7 自校准 · M8 初始值 · M9 无数据守卫 · M10 跨域继承 · M11 左键弹窗 —— **11/11 全捕获**。

## 十三、1.74.31 载入审计（阶段 0 探针 + 阶段 1 零风险清理）与 OnUpdate 零参数事故

### 13.1 OnUpdate 零参数（真机炸点 · 用户截图定案）
- **现场**：`EvalHelp.lua:9495: attempt to index local 'f' (a nil value)`，栈顶 `function <...:9494>` ——
  载入报告帧写成 `frame:SetScript("OnUpdate", function(f) pcall(f.SetScript, f, "OnUpdate", nil) ... end)`。
- **根因**：**本客户端调 OnUpdate 时一个参数都不传**（f = nil）。全项目另外 13 处 OnUpdate 注册全是 `function()`，
  只有这一处抄了「`this` 作第一参」的老写法 ⇒ 每帧报错，**载入报告一行都打不出来**（阶段 0 的读数因此一直没拿到）。
- **修法**：帧引用用**外层 `local lf` 捕获**，回调写成 `function()`；摘钩子 `lf:SetScript("OnUpdate", nil)`。
- **判据**：源码检查 **`ONUPDATE ARG CHECK`**（扫 toc 列出的全部模块：匿名回调 `function(<非空参数>)`、
  具名回调 `function name(<非空参数>)` 一律 FAIL；注册点 < 10 处也 FAIL —— 正则失效时必须吵，不能静默放行）
  ＋ 组 190⑦（`GetScript("OnUpdate")` 取**真回调**、**零参数**调一次：不许报错 · 必须打出 `[载入]` · 报完即摘）。
- **变异**：M16（把 `function(f)` 放回去）→ 源码检查 FAIL ＋ 组 190⑦ `ASSERT FAIL`（err 原文正是真机那句，exit 1）；
  M17（给 HunterHelper 的 OnUpdate 加 `self` 参数）→ 源码检查抓到**另一个文件**的同类风险。
- ★**纪律**：`OnEvent` 的参数三态（第 1 参 / 第 2 参 / 全局 `event`）能兼容，`OnUpdate` **不能** —— 它就是零参数。

### 13.2 阶段 0：载入耗时探针（Core.lua）
- `EVAL_LOAD_T0`（`Locales/zhCN.lua` **第 1 行**）＝插件开始加载的时刻；`Core.lua` 尾部：`LOADM`（`t0/files/vars/init`）·
  `EVAL_LOAD_PROBE_KEYS()`（`iconDump/shProbe/shVariantProbe/probeEvents` 四键，唯一来源）· `EVAL_LOAD_MARK(what)`（`t0` 显式重读起点）·
  `EVAL_PROBE_STAMP`（`date("%Y-%m-%d")`）· `EVAL_LOAD_CLEANUP(force)` · `EVAL_LOAD_REPORT(sayFn)` **3 行**：
  源码加载 / SavedVariables 恢复 / 初始化 / 合计 ＋ 顶层键数与最大键 ＋ 本次清理量与下次对比。
- 打点位置：`tools/RareWatch.lua`（toc 最后一个模块）载入完 → `files`；`EvalHelp.lua` 的 `VARIABLES_LOADED` → `vars`；
  **一帧后** `OnUpdate` → `init` 再出报告（不新增事件注册）。
- **阶段 1 零风险清理**：`iconDump` 每次载入一律清；其余探针键**当天不算过期**要保留（非当天才清）；
  `cfg.log` 环形缓冲上限 `EH_LOG_MAX = 300 → 100`（存档体积）；手动入口 `/eh 存档清理`（强制全清）。
- 判据 = 组 190（①~⑦）＋变异 M14（去掉无条件清 iconDump）/ M15（环改回 300）／M16／M17 全捕获。
- ★**为什么先做这两阶段**：用户要求「先分析原因、出方案、待确认」⇒ 阶段 0/1 = **只观测 + 清残渣**，
  零行为风险；**阶段 2**（推迟建帧 / 大表懒建）等两轮 `/reload` 的读数到手再定。
- 存档现状（改造前实测）：`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua` 119 KB
  ＝ iconDump 62 KB ＋ log 25.6 KB ＋ war 18.7 KB ＋ 探针 ≈5.8 KB。

### 13.3 阶段 0 第一次真机读数 ⇒ 探针本身错了（1.74.31 第二版）
- **真机打出来的报告（用户两次 /reload）**：`源码加载 0ms ｜ SavedVariables 恢复 0ms ｜ 初始化 390444014ms ｜ 合计 390444014ms`，
  两次相差 25.5 秒（3904430014 − 3904404490 = 25524ms ≈ 两次 /reload 的真实间隔）。
- **定案**：**本客户端在插件加载阶段 `GetTime()` 恒 0**（进世界才开始走）——
  ① `t0/files/vars` 三点读数都是 0 ⇒ 前两段「0ms」是**假数**（不是"很快"，是量不到）；
  ② `init` 是进世界后的真实时钟 ⇒ 旧公式 `init − t0` 把**游戏运行时长**（39 万秒 ≈ 4.5 天）当成了「初始化耗时」。
- **本客户端只有这几个时间源**（api 索引 1343 条里过滤出来的全部）：`GetTime` · `GetGameTime` · `time`（epoch 秒）· `date`；
  **没有任何 tick/高精度计数器**（无 `GetTickCount`/`debugprofile`）⇒ 载入期的毫秒级计时**目前无解**，
  除非 `GetGameTime` 在载入期就走（第二版探针把三个读数并排打出来就是为了验证这一条）。
- **第二版探针（已实现）**：
  ① `EVAL_LOAD_MARK` 每个打点都记**原始读数**（GetTime / GetGameTime / time / 墙钟 `%H:%M:%S`），`EVAL_LOAD_STATE()` 读值口；
  ② 报告**先判时钟是否启动**（t0/files/vars 任一 GetTime 缺失或 0 ⇒ `dead`）：`dead` 时**如实写「载入期时钟未启动 ⇒ 测不出」**
     ＋ 追加**原始读数行** ＋ **墙钟秒级旁证**（两点同秒 ⇒ 整段载入 < 1 秒），**绝不再打假的 0ms / 39 万 ms**；
  ③ 报告**不再在载入期打**（那时全是 0）：报告帧的 OnUpdate **等 `GetTime() > 0` 的第一帧**才记 `init` 并出报告
     （等于「进世界 → 插件首帧」的真实毫秒），万一一直不可用（停在角色选择界面）最多等 **120 秒**（`time()` 做期限）再如实报告；
  ④ 新增 `PLAYER_ENTERING_WORLD` → `EVAL_LOAD_MARK("world")`（`player` 进世界打点，报告用它算「进世界→首帧」）；
  ⑤ 取证命令 **`/eh 载入报告`**（随时重打，不必 /reload）。
- **判据**：组 190 ⑧（时钟死掉时不许出现 `390444014`／必须写「时钟未启动」／「进世界→首帧」可测／原始读数含 GetGameTime／有墙钟旁证）
  ＋ ⑨（时钟未启动时调真回调**不许**提前报告且**不摘钩**，时钟起来后才报告并摘钩）＋ ⑩（`/eh 载入报告` 入口）。
  变异：**M18**（把 `dead` 分支短路成 `if false`）→ ⑧ 当场 ASSERT FAIL；**M19**（去掉「等时钟」那行）→ ⑨ 当场 ASSERT FAIL。
- ★**顺带确认阶段 1 已生效**：报告里 `iconDump` 已不在存档（62 KB 省掉），
  `SavedVariables 顶层键 28 个；最大键 log（估算 5.9 KB）`（环上限 300 → 100 后只剩 5.9 KB）。
- ★**未决**：载入期毫秒仍测不出（客户端限制）⇒ 阶段 2 的取舍要基于「存档体积 + 墙钟 + 进世界后首帧」这三条证据。

### 13.4 阶段 0 第二次真机读数（1.74.31 第三版）：载入期到底有没有可用时钟
- **用户第二次 /reload 的报告（原文关键行）**：
  `载入期时钟未启动（GetTime() 原始读数 = 0，实测）⇒ 源码/存档两段**测不出**；进世界→首帧 —` ·
  `原始读数 t0/f/v/w/i ｜ GetTime nil/0/0/nil/3904876.377` ·
  `　同序 ｜ GetGameTime nil/6/6/nil/6 ｜ time(秒) nil/1789996554/1789996555/nil/1789996555`
- **定案（三个时间源逐一验完）**：
  | 时间源 | 载入期（files / vars 两点） | 结论 |
  |---|---|---|
  | `GetTime` | `0 / 0` | **载入期恒 0** ⇒ 毫秒级不可测 |
  | `GetGameTime` | `6 / 6`（init 也是 6） | **恒定不动** ⇒ 也不能当时钟 |
  | `time()`（epoch 秒） | `1789996554 / 1789996555` | **载入期真的在走**，但只有 **1 秒分辨率** |
  | `date("%H:%M:%S")` | 同秒级 | 与 `time()` 等价 |
  ⇒ **本客户端载入期没有任何毫秒级时钟**（api 索引 1343 条里已确认没有 tick/高精度计数器）——这是**客户端限制**，不是我们写法问题。
- **第三版探针（已实现）**：
  ① 起点（`Locales/zhCN.lua` 第 1 行）把 `GetTime/GetGameTime/time/date` **四个读数一起采**（存全局），Core.lua 载入时桥接进 `LOAD_RAW.t0`
     —— **必须在第一个文件采**：Core.lua 比它晚载入，那时调不了函数；
  ② 报告加 **墙钟行** ＋ **秒级窗口行**：`time() 差 N 秒`（同秒 ⇒ 这一段 <1 秒；跨秒 ⇒ 至少 1 秒，要继续查），
     且三种读数组合逐一尝试 —— **不许因为缺一个读数就一行不打**（第一次真机就因为起点读数缺，墙钟行整行没打）；
  ③ `GetGameTime` 三处相等时，行尾如实标注 `（GetGameTime 恒 6，不随时间走 ⇒ 不能当时钟）`。
- **判据/变异**：组 190 ①b（起点读数**在第一个文件**就采好）+ ⑧（秒级窗口 / 同秒文案 / GetGameTime 恒定标注 / `time(秒)` 必留）。
  变异 **M20** 去掉 Core 桥接、**M21** 短路秒级窗口行 —— 都当场捕获。
- ★★★**本轮教训（弱判据）**：①b 最初写在 ⑧ 里，而 ⑧ 之前 `②` 已经调过 `EVAL_LOAD_MARK("t0")` **覆写**了 t0 的原始读数
  ⇒ 那条断言**恒为真**、M20 存活（自证式假判据）。**断言必须放在「被测状态尚未被后续步骤覆写」的位置**；
  判据的写法纪律（相对量验相对量）在时间轴上也一样成立。
- ★**下一次要问的问题**：`t0 → vars` 的秒级窗口是 0 秒还是 ≥1 秒 —— 0 秒 ⇒ 插件自己的「编译+恢复」全程 <1 秒，
  「载入慢」不在我们的 Lua 里（阶段 2 拆分/懒建是白费）；≥1 秒 ⇒ 再用同一把尺子做 A/B（临时摘模块看窗口是否变小）。

### 13.5 阶段 0 第三次真机读数（1.74.31 第四版）：把 1 秒分辨率的钟变成可用尺子
- **用户第三次 /reload 的报告（关键行）**：
  `墙钟（秒级旁证）：21:35:50 → 21:35:51` · `秒级窗口：time() 差 1 秒` ·
  `原始读数 t0/f/v/w/i ｜ GetTime 0/0/0/nil/3906072.349` ·
  `　同序 ｜ GetGameTime 6/6/6/nil/6 ｜ time(秒) 1789997750/1789997750/1789997751/nil/1789997751`
- **定案**：
  | 段 | 读数 | 结论 |
  |---|---|---|
  | `t0 → files`（30 模块源码编译+执行） | time 同秒（750 → 750） | **< 1 秒**（上界可用）—— 与离线实测 ≈180 ms 一致 ⇒ **源码编译不是「载入慢」的原因** |
  | `files → vars`（最后模块 → SavedVariables 恢复完） | 750 → 751（跨秒） | **单次定不了量**；两次重载都是跨秒（2/2） |
- ★★★**我犯的措辞错误（已修）**：旧文案写「跨秒 ⇒ 这一段至少 1 秒」——**错**。
  跨秒只说明两点落在不同秒格，**不构成下界**（在边界前 1ms 采样同样跨秒）。
  正确说法 = 「同秒 ⇒ <1 秒（上界）」/「跨秒 ⇒ 单次定不了量」。
- ★★★**正解：抽样平均**（本客户端载入期只有秒级时钟，这是唯一能拿到真值的手段）：
  随机相位下 `E[floor(T2) − floor(T1)] = 真实时长` ⇒ **多次重载求平均秒差就是该段时长的无偏估计**（1 秒分辨率的钟 → 秒级精度的尺子）。
  实现：报告里把 `t0→files`（源码段）与 `files→vars`（存档段）的秒差**累计进 `cfg.loadStat`（写存档）**，并打一行
  `[载入] 秒级抽样 n=N：源码段均 x 秒（跨秒 a）｜ 存档段均 y 秒（跨秒 b）`。
  ⇒ 用户正常玩（每次 /reload 自动记一笔）即可累积样本；**样本够了我可以直接读存档文件**（`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`）取统计，不必让用户手工复现。
- **存档现状（实测）**：`EvalHelp.lua` = **51.6 KB**（改造前 119 KB）；`iconDump` 已清、`log` 5.9 KB。
- **判据/变异**：组 190 ⑧b（抽样写进存档 / 报告有抽样行 / 跨秒文案 = 「单次定不了量」/ **禁止**「至少 1 秒」）。
  变异 **M22**（短路抽样块）、**M23**（把措辞改回「至少 1 秒」）—— M23 第一次**存活**，原因：夹具当时 `time()` 两点同秒 ⇒ 报告只走「同秒」分支，
  **那条反向哨兵永远照不到**。修法 = 夹具**必须把被测分支真的走一遍**（让 `files→vars` 跨秒），并加正面断言（必须含「单次定不了量」）；
  重跑 M23 ⇒ 当场捕获。★这是本会话第二次「弱判据」教训（第一次是断言放在被覆写之后）。
- ★**下一版收尾**：取证结束（阶段 2 定案）后，报告要从 6~8 行**精简回 3 行**（原始读数/抽样只在需要时打）。

### 13.6 收尾（1.74.31 定案）：报告精简 + 调试残渣一键清
- **用户定案语**：「优化完成，可以清理调试残留了」⇒ 两件事：**把取证噪音收起来** + **把残渣清干净**（能力保留，噪音清除）。
- **报告分两层**（`EVAL_LOAD_REPORT(sayFn, full)`）：
  · **登录 = 1 行摘要**：`[载入] 源码段均 x 秒 ｜ 存档段均 y 秒（样本 n） ｜ 存档 N 键 / 最大 X ｜ 本次清残渣 k 个`；
  · **`/eh 载入报告`（full=true）= 完整取证**（毫秒段/墙钟/秒级窗口/抽样/原始读数/时间源 dump）；
  · ★**完整取证始终写进调试日志**（聊天只给摘要）⇒ 需要深挖时 `/eh logdump` 也拿得到，不必重载。
- **调试残渣清单一处真源**：`LOAD_RESIDUE_KEYS`（Core.lua）= `probeLog` · `shColorProbe` · `shTitleColorProbe` · `shareIconProbe` ·
  `shareProbe` · `shareProbeHover` · `shareProbeRaw` · `shareProbeVerdicts` · `shareSealDemo` · `shareCreatorOpen` · `loadStat` · `guideSeen`（废弃键）。
  ★判据：**只有 `force`（`/eh 存档清理`）才清**——它们是若干判据的「落盘证人」（自动清掉 = 「事后读回来」的能力无声消失）；
  ★★**真状态键绝不进这个清单**（`ds/tb/war/ui/title/share/log/st/…` 删了就是丢用户配置）。
  ★`LOAD_PROBE_KEYS`（4 个探针数据键）维持原规则：`iconDump` 一律清、其余非当天才清。
- **判据/变异**：组 190 ⑪（默认只 1 行；`full=true` 仍给完整取证）、⑫（非强制**不碰**残渣键、force 一次清干净、清单 ≥8 项）；
  ③ 的期望值从「恰好 4」放宽为「≥4 且 4 个探针键确实消失」（force 现在连残渣一起清）。
  变异 **M24**（force 不清残渣）→ ⑫ 当场捕获；**M25**（非 force 也清残渣）→ **更早的组**（「秘籍样例」以落盘字段为证）当场捕获 ——
  正好证明「残渣键是判据的证人」这条设计理由。
- **工作区清理**：仓库根目录的 `dbg_*.lua`（10 个，历史遗留的一次性调试脚本）与 `CLAUDE.md.bak` 已**搬进 `.dsh/debug-residue-20260922/`**
  （`.dsh/` 在 `.gitignore` 里）——游戏 AddOns 目录因此干净，且随时可翻回来。
- **用户机上还需执行一次**：`/eh 存档清理`（清掉当前存档里已存在的残渣键；`loadStat` 会随之清零，下次登录继续累计）。

## 十四、任务线数据来源（1.75.1）与物品类型过滤明细（1.74.28 原文照存）

### 14.1 ★任务线检索依据 = `https://database.emberveil.org/quests`（用户 1.75.1 明确「记住任务线的检索依据…数据为准」）

- **唯一真值来源**：EmberVeil 官方数据库 `https://database.emberveil.org/quests`。任务线、任务节点、等级、阵营、奖励物品**全部以该站页面为准** —— 不凭记忆、不引别家数据库。
- `quest/QuestData.lua` 是**生成物**（纯数据、无函数）：`node quest/build.js` 用缓存生成、`--force` 全量重抓。★**手改会在下次生成时被覆盖** ⇒「改数据」＝改策展清单 `quest/chains.js`（任务 ID 序列 / 阵营 / 档位 / 等级 / 地区 / 点评）后重跑生成。
- 抓取器 `quest/fetch.js`：自带本地代理自举（`127.0.0.1:10809`，无第三方依赖）、限速 200ms、失败重试 3 次、缓存落 `quest/cache/`（已在 `.gitignore`）。站点要点：Next.js SSR，任务列表 GET 参数 `name/min_level/max_level/type/page`（50 条/页），详情页自带「本系列第 N/M 部分」链信息，`Cookie: lang=zhCN` 全站中文，物品品质取 RSC 的 `qualityColor`。
- **判据**：`QUEST TOC CHECK`（两文件在 toc 且在 DataSearch 之前 + 磁盘↔toc 双向一致 + 数据文件不许出现 function）· 组 191（22 条链**逐条**查字段齐 + 任务/物品都在表里 + 档位排序 + 武器优先 + 诚实失败）· 组 192（弹窗：装备优先 / 反查任务线 / 直连数据检索 / **阵营严格三分类** / **任务节点放大镜**）。
- **加新任务线**：往 `quest/chains.js` 加一条（key / 名称 / 阵营 A|H|B / 档位 S|A|B / 等级区间 / 地区 / `quests` 完整 ID 序列 / 一句 note）→ `node quest/build.js` → 跑 `node luacheck.js` + `node test_engine.js`（都要 exit 0）。
- 弹窗行为（1.75.0~1.75.8 五轮）：数据检索 ·「地图标注」右侧 [任务线推荐]；两视图（装备优先 / 任务线）+ 三个筛选（等级 / **类型（种类子类型多选）** / 阵营）+ **行数按窗高现算**（`EVAL_QP_ROWS_FOR`，铺满不留白）+ 滚轮 + 拖动柄；装备行带真实图标（`GetItemInfo` 第 9 返回）与品质色；详情里**每个任务节点左侧放大镜** → 按**任务名**走 `EVAL_DS_SEARCH_NAME` 直达数据检索（★**不关窗**）。

### 14.3 装备「种类细分 + 子类型多选」明细（1.75.8，用户「装备筛选种类细分,支持种类子类型.武器子类型支持.并且支持多选.」）

- **种类唯一来源 = 生成数据的 `k` 字段**（类型：剑/斧/锤/匕首/法杖/弓/盾牌/布甲/皮甲/锁甲/其它），部位在 `s`，**武器与否由 `EVAL_QC_IS_WEAPON`（dps>0）现判** —— 不另立种类表（写死＝与数据脱节，下一批数据就漂移）。
- **数据层**（`quest/QuestChains.lua`）：`EVAL_QC_ITEM_KIND(rec)`（取 `rec.k`）· `EVAL_QC_KIND_LIST()`（**现算**，只列数据里真有的种类；排序 = 武器子类型在前 → 件数降序 → 名字升序 → 首见序，`table.sort` 在 5.1 不稳定故末项兜底）· `EVAL_QC_KIND_GROUPS()`（返回 武器子类型名数组, 其它种类名数组 —— 界面**不自己分组**）· `qcKindPass(set, k)`（非表/空集 = 不过滤）· `EVAL_QC_ITEM_ROWS{..., kinds={[种类]=true}}`。
- **界面**（`DataSearch.lua` 弹窗）：类型筛选按钮 = **`EVAL_DD_OPEN` 的 multi 下拉**（`{ multi = true, selected = sel, locked = locked }`；`onPick(pi, on)` → **两步布尔** `if on == true then ... = true else ... = nil end`，禁用 `on and true or nil` 这种 and/or 写法）· 分组标题（武器/其它）走 `locked[序号]=true`（画纯文本、不画方框、点击无回调）· **末行 = 「全部」一键清空**（`map[末行] = { clear = true }`，与工具箱关键字菜单的 clear 行同范式）· 选项来自 `qpKindMenu()`（数据现算）· 按钮文字 `qpKindLabel()`（空 = 全部 · 1 = 名字 · 2 = 名字、名字 · 更多 = 首项…(N)）· `DS.qpKinds` 是**唯一**选中态（旧三态 token 只作入口：`qpApplyKindToken` 把 `ALL/WP/OT` 或种类名（可 `"剑,斧"`）翻成集合）。
- **读值口**：`EVAL_QP_KINDS()` · `EVAL_QP_SET_KINDS(set)` · `EVAL_QP_KIND_MENU()` · `EVAL_QP_KIND_LABEL()` · `EVAL_QP_F2_TEXT()`（按钮上**真 FontString** 的文字 —— 按钮本体没有文字）。
- **判据**：`QUEST WIRING CHECK`（kinds 判定只准有一处 + 显式布尔 + 空集放行）· `QUEST PANEL CHECK`（无 QP_KIND 三态表 + 传 `kinds=DS.qpKinds` + multi/locked/两步布尔/空集文案/两个 locked 分组标题/走 `EVAL_QC_KIND_GROUPS`）· 组 192 ⑧j（每个武器子类型单独筛只出该子类型 · 多选并集 · 空集=全部 · 真实按钮→真实 multi 下拉→分组标题不可点→真实点行→列表按子类型过滤→按钮文字同步）。
- **变异（全部 CAPTURED）**：M20 数据层忽略 kinds · M21 退回单选 · M22 空集当「什么都不显示」· M23 未勾选时按钮留空 · M24 分组标题可点 · M25 回调写成 and/or 单行。

### 14.4 全量采集（10-60+ 全部任务奖励）+ 审计 + 输入框修复（1.75.9）

**用户原话**：「1. 现在验证可行想.开始进行数据抓取.将任务奖励:只要有装备/武器的都可以进行数据采集.单任务也可以加入采集. 2. 经典任务线衍生到30-60范围.包含大型任务线.各种开门任务线等. 3. 图片内的输入框无法输入 … 任务完成之后要审计装备链接是否正确.任务链接是否正确,任务线是否完整.以上所有数据来源都以 https://database.emberveil.org/quests 为准.装备链接都游戏内信息为准.」

- **可行性实证（先探规模，再动手）**：`/quests?min_level=..&max_level=..&page=N` 每页 50 条、页内有「第 N / M 页」可读总页数；**列表页本身就带奖励物品** —— 每条 `<img src="/icons/small/<图标名>.png" style="border-color:#<品质色>" data-tooltip-entry="<物品id>">` ⇒ 任务→装备的对应关系**不必逐条拉详情页**。10-60 共 **81 页 / 4008 条**任务；有奖励 470、带绿装+ 422、奖励物品 923（绿 637 / 蓝 148 / 紫 49 / 白 89）。
- ★★★**三个必须记住的站点事实（1.75.9 全部实测踩过，每条都对应一次返工）**：
  1. **列表页的奖励图标是「截断显示」**：一行的奖励区只画前几枚（实测 #451 列表只有 `2458`，任务详情页的「选择一件/直接给予」还有 `2459`）⇒ **奖励的权威来源 = 任务详情页**；生成器取「列表 ∪ 详情」并集。★只看列表页时审计 C 检查报了 88 条「仅详情页有」——那就是漏掉的奖励。
  2. **站点搜索 `?name=<词>` 是「任务标题（英文原文）子串」匹配**：`name=Onyxia` → 3 条 ✓；`name=安其拉` → **0 条**（中文只是 `lang=zhCN` 的显示层，不参与检索）；多词短语（`Scepter of the Shifting Sands`）→ 0 条（不是全文检索）⇒ 名人任务线种子必须用**英文单词**（Naxxramas / Onyxia / Quel'Serrar / Thunderfury / Linker / Eranikus…）。
  3. **「本系列第 N/M 部分」必须用结构性解析**：整条系列除「你在这里」那一步外每步都是 `<a href="/quest/ID">名字</a>` ⇒ 按**文档顺序**取块内任务链接、当前页那一步按 `part` 号插回。★旧实现按可见行「数字 / 名字」对齐，在部分页面整块错位（实测 #8949 把 24 步全读成同一个名字、只解出 1 个 id；#1170 奥妮克希亚同样）⇒ 生成出一堆**假任务线**。修好后 id 覆盖率 100%。
- **可抓取规模修正**（修好列表解析后重扫）：有奖励 **1683** 条任务、奖励物品 **1882**（绿装+ 1509）· 装备（部位或 DPS）**994** 件；**发货口径**（进 `QuestBulk.lua`）= 奖励里有装备的 **751** 条任务 + 它们引用到的 **1262** 件物品 + **688** 条自动任务线（≥8 步 36 条 · 开门/史诗 19 条 · 含 30-60 与 55-60 的大线）· 文件 **186 KB**。
  ★30-60 的线是**补抓**出来的：先按「有装备奖励」抓只能拿到 10-31 的小线 ⇒ `sweep_quests.js 1 70`（**全部 4008 条**任务详情，1888 条带系列）+ `refetch_series.js`（解析器每改一次都必须重抓：缓存里存的是**解析结果**）才把整库的线补全。
- ★★★**系列解析第三次返工（1.75.9 收尾）**：站点的「本系列第 N/M 部分」块有三种形态 —— ① 全是链接 ② **全是纯文本（没有链接）** ③ 混合。只按链接解析时，形态②的页面会退化成「只剩你在这里那一步」（实测：迪菲亚兄弟会 1/5、莱恩的净化 1/9、大地之冠 0/7）⇒ 经典线整条消失。**正解 = 链接 + 可见文本「数字→名字」双来源**：名字从可见文本取、id 从链接取（名字与链接对齐），再用 `quest/resolve.js` 的「任务名 → id」补缺（候选要过候选自己那页的 `part/total` 交叉验证）。修好后这些线全部拿到 5/5、9/9、7/7。
- **审计结论（`node quest/audit.js`，现 0 硬错误）**：A 装备 994 件全部有名字且品质合法 · B 任务 751 条（奖励 id 全在物品表、无孤立装备）· C 列表页↔详情页 **93 条不一致（全部是「仅详情页有」= 列表页截断，属于站点显示行为，数据已取并集）** · **E 策展 22 条链全部「与站点一致」**（本轮按站点把 10 条链补全：维里甘之拳 +1650、尖牙德鲁伊 +880、莱恩的净化 +1023、健忘的勘察员 +729、奥萨拉克斯之塔 +965/966/967、与血色十字军的战争 +383、大地之冠 +917、死亡矿井散件 +2041、诺莫瑞根 +2931、主动式负载平衡器 +3922）· **F 装备↔任务链接不一致 0 条** · D/G 任务线 **769 条**（≥10 步 21 条 · 开门/史诗 19 条：斯塔文的传说、埃提耶什之杖、奥妮克希亚的血脉、基尔卡克的钥匙、安斯雷姆的钥匙、圣光节杖、梦魇的缠绕…）。
- **经典覆盖清点（审计 G 段）**：按区域自动清点 —— 黑石塔 27 条线 · 东瘟疫之地 27 · 希利苏斯 20 · 黑石深渊 19 · 斯坦索姆 17 · 奥达曼 13 · 通灵学院 13 · 厄运之槌 13 · 诺莫瑞根 10 · 沉没的神庙 8 · 祖尔法拉克 6 · 黑暗深渊 4 · 死亡矿井 3 · 哀嚎洞穴 2 · 剃刀高地/沼泽/血色/熔火之心/纳克萨玛斯/奥妮克希亚/安其拉各 1-2 条。★唯一「未命中关键词」= **灰烬使者**，原因如实写进报告：1.12 灰烬使者只有纳克萨玛斯掉落、**没有任务线**（黑翼/祖尔格拉布同理：前者进本靠 UBRS 流程、后者只有硬币与声望重复任务）。

- **数据质量三道补丁（都写进生成器，不许回退）**：① 奖励 = 列表 ∪ 详情；② 系列 `trusted`（id 覆盖 <50% 不采信）+ 步骤数与站点自报 `total` 不等的不采信；③ 物品名两份来源兜底（白/灰物品无「拾取后绑定」行 ⇒ 物品页拿不到名字，用任务页奖励链接文本补）。


- **抓取三层**：`sweep.js`（列表页 → `cache/sweep_10_60.json`，行含 等级/名称/地区/阵营标签/类型/经验/奖励物品）→ `sweep_details.js`（物品页：名称/品质/物品等级/DPS/速度/部位/类型/属性/图标 + 装备判定；任务详情页：`rec.series` = 站点自报「本系列第 N/M 部分」+ 步骤 id/名）→ `build_bulk.js`（→ `quest/QuestBulk.lua`）。
- **`QuestBulk.lua` 记法（紧凑串，分隔符 `|`；生成器**先证明**任何名字都不含它，否则拒绝写出）**：
  `q[id]="名|等级|地区|阵营A/H/空|奖励id,id"` · `i[id]="名|品质|ilvl|dps|speed|部位|类型|属性|图标名|是否装备"` · `s[n]="系列名|lo|hi|地区|档位(长度≥10=S,≥6=A,否则B)|是否开门/史诗|步骤id,id"` · `sn[id]="步骤名"`（步骤任务本身没装备奖励、不在 q 表时用）。
- **自动任务线**：按详情页的 series 步骤 id 集合去重 → 排序 → 等级区间取已知步骤的 min/max → 阵营由成员任务的 A/H 标签推（拿不准按「共有」）→ 开门/史诗靠关键词（之门/节杖/流沙/纳克萨玛斯/黑翼/熔火/安其拉/奥妮克希亚/克尔苏加德/泰坦/奎尔塞拉/雷霆之怒…）。
- **逻辑层**（`QuestChains.lua`）：`EVAL_QC_BULK_READY/META/QUEST/ITEM/ITEM_ROWS/SOURCES` + `EVAL_QC_SERIES_LIST/COUNT/DETAIL/FACTION`；★`EVAL_QC_ITEM_ROWS` = **全量优先、策展兜底**（`qcChainItemRows` 保留旧实现，全量缺席时界面照常可用）；★`EVAL_QC_ITEM/ITEM_NAME` 策展表查不到 → 退回全量；★`EVAL_QC_ITEM_CHAINS` 走**反向索引**（禁借道 `EVAL_QC_ITEM_ROWS`：全量行与策展行形状不同，借道＝静默 nil）；★`EVAL_QC_SEARCH` 追加一遍 **series**（`kind="series"`、键 `"s:<位次>"`），`EVAL_QC_DETAIL("s:n")` 走 `EVAL_QC_SERIES_DETAIL`（详情形状与策展链**完全一致** ⇒ 文案行/界面不分叉）。
- **审计双层**：① **离线** `node quest/audit.js [--online]` —— A 装备（id↔名/品质/部位自洽；列表页 vs 物品页品质交叉验）· B 任务（id↔名/等级；奖励 id 必须在物品表；**装备不许孤立**）· C **双向一致**（列表页奖励 vs 任务详情页「选择一件/直接给予」，站点自己不一致也抓）· D 任务线完整性（步骤 1..M 连续、成员任务自报 total 与系列自洽）；有硬错误 `exit 1`，报告落 `cache/audit_report.json`。② **游戏内** `/eh ds 任务线 审计`（`EVAL_DS_QC_AUDIT`）——逐件对账**游戏内名字/图标**（★以游戏内为准），未缓存的按 `QP_REQ_RATE/QP_REQ_MAX` **排队补缓存**（跑第二次看自愈）。
- **输入框无法输入（用户截图）＝ 真凶是 `EnableMouse`**：主搜索框 `eb` 有 `pcall(eb.EnableMouse, eb, true)`，弹窗 `qpEb` 当初漏了 —— 本客户端 EditBox **不显式开鼠标就收不到点击 ⇒ 拿不到焦点 ⇒ 一个字都打不进**。修法 = 照主框那条已验证配方补齐四件：`EnableMouse` + **点击即聚焦兜底按钮**（`qpEbFocus`，`OnClick → SetFocus`）+ `SetJustifyH("LEFT")`（本客户端默认居中偏右）+ 字体链三级兜底（全失败才启用回声行）+ `OnEnterPressed`/`OnEscapePressed`。判据 = `QUEST PANEL CHECK` 五条 + 组 192 ⑧k（真实点输入区 → `HasFocus` 为真 → 敲字进查询词 → 占位消失）。
- **等级档扩到 10-60**：`QP_LV` = ALL / 10-19 / 20-29 / 30-39 / 40-49 / **50+（hi=999，因为站点在 60-69 还有带装备奖励的团本/开门任务）**；★下拉标签**由 `QP_LV` 现算**（写死四项＝加档必漏一处）；三语言新增 `DS_QP_LV_L4/L5`。
- **判据**：`QUEST TOC CHECK`（三文件顺序 QuestData→QuestBulk→QuestChains、磁盘↔toc 双向、生成物纯数据、**任务行≥200/物品行≥300/系列≥20**、任务行恰好 4 个分隔符）· `QUEST WIRING CHECK`（全量八个接口 + 统一入口「全量优先/策展兜底」+ 反向索引 + 不借道 + plain 查找 + 物品兜底）· `QUEST PANEL CHECK`（等级档 ≥5 档且含 50+、下拉现算、来源=任务名、来源任务可搜、详情来源行挂放大镜、审计函数与命令接线）· 组 192 ⑧l/⑧m/⑧n。
- **变异（1.75.9 新增）**：M27 审计名字对账写反 · M28 `EVAL_QC_ITEM_ROWS` 去掉全量分派 · M29 搜索丢掉 series · M30 审计图标对账不跑。

### 14.2 两个助手的弹窗候选「按物品类型过滤」明细（1.74.28 · 常驻卷瘦身移出，原文照存）

- ★★★**两个助手的弹窗候选按物品类型过滤**（1.74.28，用户「弹窗选的物品项目要过滤一下.不要显示武器,装备.灰色物品,草药,矿物,任务物品,材料等等非可使用的物品,验证可行性.」）：判定收在**共用件 `EVAL_IG_ITEM_KIND`**（tools/IconGrid.lua），**三级**按「便宜→贵」早停 ——
  ① **品质**（`GetContainerItemInfo` 第 5 返回，**完全不依赖缓存**）⇒ 灰色一律剔；② **`GetItemInfo`**：★传参**先用物品链接**（`GetContainerItemLink` 给的 `|Hitem:…|h[名]|h` = 客户端的**缓存键**），nil 再退回名字；读第 5/6/8 返回 = 主类型/子类型/**装备槽**（装备槽非空 ⇒ 算护甲，比类型词更硬）；③ 缓存为 nil ⇒ **自建隐形 tooltip** `EVAL_HELP_WTT` + 读守卫 `EVAL_WTT_MAY_READ` + **`SetBagItem`**（已核在官方 API 索引里）读**类型行** —— ★★这一步会**把物品写进客户端缓存** ⇒ 下次 `GetItemInfo` 直接命中 = **自愈**（`probed` 计数会掉下来）。
  ★**剔除表** `IG_KIND_DROP`：武器 · 护甲(装备) · 灰色 · **材料（草药/矿物/布料/皮革/附魔材料）** · 任务物品 · 容器 · 箭矢弹药 · 钥匙 · 配方图纸；★**判不出就不剔**（铁律「查不到 ≠ 没有」：宁可多显示一件，也不把真食物藏起来）+ 计入 `EVAL_IG_KIND_STATS().unknown` 如实报。
  ★★**过滤只在「弹窗候选」这条路径开**（`EVAL_IG_SCAN_BAGS(bags, { classify = true })`）——按名字解析包格那条路（`EVAL_CH_FIND` / `EVAL_HH_FIND_FOOD`）**绝不过滤**：判错一类 → 用户已配置的物品会**静默找不到**（本项目最恨的失败型）。
  ★★**tooltip 只读 TextLeft2 起**（**跳过 TextLeft1 = 物品名**）：名字里可能含类型词（「草药烤鱼」含「草药」）会污染判定；词表 `IG_KIND_WORDS` 按**真机实测文案**维护（本客户端 zhCN）。
  ★**验证入口**（「验证可行性」= 一条命令）：`/eh go 消耗品探针 过滤` ｜ `/eh go 喂食探针 过滤` → 逐件打出**判定依据**（品质 / 缓存主类型·子类型·装备槽 / tooltip 读到的真实类型行 / 最终判定）+ 统计行（剔除/保留/判不出/缓存命中/未缓存/tooltip 探了几次），上限 30 行并如实报「还有 N 条未显示」；★它同时是**补词表的依据**。
  ★**新增文件/新代码要同步的清单**（本轮 `DECL ORDER` 当场抓到）：报告函数被插到 `IG_KIND_*` **local 声明之前** → 真机上读到**全局 nil**；★凡是新函数引用文件内 local，一律确认声明在前（`DECL ORDER CHECK` 扫全部 14 个生产 .lua）。
  判据 = 组 187（旧档 ①~⑥ + 新档 ⑦~⑩：白色**材料**/任务/容器/箭矢/钥匙/配方逐项剔、tooltip 兜底真的收到 `SetBagItem(bag,slot)`、**缓存自愈后不再探**、判不出不剔但记账、关掉 `classify` 行为不变）。
