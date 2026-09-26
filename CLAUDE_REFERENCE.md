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
★**装完必须核对条目数**（1.75.1 基准 = **75 个**：+`quest/QuestData.lua`、`quest/QuestBulk.lua`、`quest/QuestChains.lua`（1.75.9 新增 QuestBulk = 全量任务/装备数据）；1.74.34 时是 72（+`tools/LayerFix.lua` 图层特殊处理独立模块）；1.74.30 时是 71（+`tools/DragFrames.lua` 框拖拽从子插件搬进工具模块）；1.74.29 时是 70；1.74.27 时是 69（+`tools/RareWatch.lua`）；1.74.12 时是 68、1.74.6 时是 66、1.73.5 时是 63；1.74.5 陆续加了 `tools/IconGrid.lua` / `tools/HunterHelper.lua` / `tools/ConsumableHelper.lua`，1.74.7 加 `tools/DismountHelper.lua`）：
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
- ★★★1.74.30 **不许把「不确定存在」的 API 当兜底**：先查索引/参考实现，没有就整条别写（`type(X)=="function"` 守卫在**不存在**时是死代码、在**存在但说假话**时更坏——一次误判就把功能掐断）。真要用 → **自校准**：在「状态确定的那一刻」（如 OnMouseDown 时左键必然按着）探一次，返回值不成立就**永久弃用这一层**并如实记录（框拖拽的 `IsMouseButtonDown`/`GetMouseFocus` 两层都这么做，组 202 ⑥a~⑥d 钉住）。
- ★★★1.74.30 **`ClearAllPoints` 之后位置就是 (0,0) = 父级左下角**（官方 wiki Region:ClearAllPoints 明文；SetPoint 条目又写明「新建帧有一个默认 BOTTOMLEFT 种子」）⇒ 看到「窗口/控件贴屏幕左下角」= **清锚点成功、SetPoint 没生效**。纪律：① 别把 SetPoint 包在 `pcall` 里**静默吞掉**结果；② 设完**读回自证**（`GetNumPoints` ≥ 1 + `GetPoint(1)` 的点名/偏移对得上）；③ 要有兜底路径（改用**父级相对**锚点，别跨父级指 UIParent）。

### F. 本客户端 API / 素材的真伪清单（用前必查，别按命名习惯猜）
- **`WorldMapFrame:IsShown()` 两个方向都会撒谎**（可能恒 false，关图后也可能恒 true）→ **绝不进分支**；判「有没有可标注视图」只用 `MapContext:GetViewedZone()` 的 `zoneIndex==0 → continentView`；开图一律 `ShowUIPanel`，**绝不 Toggle**。
- **`UnitBuff`/`UnitDebuff` 只有图标+层数、没有时长**；只有自身光环能查 `GetPlayerBuffTimeLeft`，**它返回 0 = 无限/无数据（不是 0 秒）**。
- **`UnitCreatureType` 返回带后缀的本地化名**（「人型生物」）→ 匹配要剥掉「生物」再比。
- **无 CombatLog API、无免疫查询函数、无 `UnitCastingInfo`、无 SuperWoW**（精确距离/挥击计时做不了）。
- ★★★1.74.30 **没有 `IsMouseButtonDown`**（API 索引 1328 条唯一函数名里查无；整个游戏 AddOns 目录除本插件自己的引用外**零出现**）→ 鼠标按键兜底只能靠 `OnMouseUp` / `OnDragStop`(**真机未证实收得到**：拖动配方要 SetMovable+StartMoving)/ `GetMouseFocus()`(**有**，但要自校准) / 自制**全屏接盘**（拖拽期间 Show 一个吃鼠标的 Button，松手无论指针在哪都收得到 —— UnrealQuest 的筛选菜单同款）/ 超时无位移自动结束。
- ★★1.74.30 **`GetPoint` 的第 2 个返回值是相对帧的「名字字符串」（不是帧对象；父级锚点无名时给 `"auto"`），且它与 `SetPoint` 传参的 y 偏移符号口径有歧义**（wiki 说内部存储取反；UnrealQuest 2026-09-17 定点探针在 UIParent 同名锚点上量到 18/18 同号）⇒ **绝不把 `GetPoint` 的偏移回灌给 `SetPoint`**（回读→加增量→回写会累积成镜像/漂移）。正解 = 用**测量边**（`GetLeft/GetBottom/GetWidth/GetHeight`，UI 像素、原点左下、Y 向上）构造偏移，`GetPoint` 只用来读**点名与相对帧名字**。

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
- **当前版本（源码唯一真值）**：`EvalHelp.lua` 的 `local VERSION` == `EvalHelp.toc` 的 `## Version` = **1.75.4**（v1.75.3 已发布）
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
1. **1.75.4** — 🔔 **稀有转播=通知（不受总闸门）+ 探索层原值带地图身份**：稀有提醒转播改走**不门控的强制出口** `EVAL_SAY_FORCE` —— 它是**通知**不是调试日志（真因：`cfg.log.on=false` 把 `say`/`logLine` 一起静音 ⇒ 用户报「检测不到稀有通知」，**日志环里也查不到任何证据**，两个证据同时消失）；受**自己的**开关 `cfg.rareWatch` 管，★总闸门语义一个字不改（组 252① 有反向哨兵）。
  ★配套：**专属取证环** `cfg.rareProbe`（有界 30、不门控，AI 读存档即可判「有没有转 / 走的哪个出口 / 回调有没有抛错」）· **接线自检**（状态命令里比对 `EVAL_RW.showRef`，包装被人重载或又被别人包一层 ⇒ **当场重装**并如实播报）· 兼容对方测试入口**改名**（`Test` 优先、旧名 `TestNearest` 也认 —— 原来只认旧名 ⇒ 自证命令**静默失效**、排障时误导用户）· 回调**异常如实计数 + 落盘**（原来 `pcall` 静默吞掉 = 排查盲区）。判据 = 组 252 + `RARE WATCH WIRING CHECK`。
  ★★★**修「某些地图打开之后会将探索层的坐标丢失、全部图层都集中在左下区域重叠」**（用户报障 → 真机存档取证 → 定案）：`WorldMapOverlay1..N` 是客户端**按序号逐图复用**的纹理（每图重摆、用不到的 `:Hide()` 且**不清几何**）⇒ **同一个纹理名在不同地图上是完全不同的矩形**；旧 schema 把原值**只按名字**记一份且永不过期（真机存档 8 条里 **6 条完全相同** = 把「还没布局 / 本图不用」的残留几何记了下来）⇒ 开别的图时无条件把那套矩形写回去。修法五条 + 存档自愈：**按地图身份分桶**（`GetMapInfo` 文件名 + 尺寸）· 换图**当场作废**内存记录并重抓（`smFitNewMap`）· 只碰**本图在用**的层（`IsShown`/`GetTexture`，★读不到就放行）· 抓原值**等版式稳定**（`SMFIT_SETTLE = 0.4s`）· 还原**只还本图写过的层**（`wroteKeys` 逐层记账）· `mapFitVer` **2→3** 丢弃脏原值。取证 = **只读清单 `/ehm mapfit dump`**。判据 = 组 253 + `SM MAP KEY CHECK`（变异 4/4，其中 M1/M2 两条**当场漏网 → 补判据**）。全案 **R20c**。
2. **1.75.3** — 🎯 **选取目标一族 + 修「自动攻击抢目标」+ 围攻·交战人数 + 任务线数据补完**：「选取目标 → **玩家的目标**」= `AssistByName`（与「指定名称」同族：同一份 `TARGET_SEL`/同名下拉/同输入弹窗，**只差客户端函数**；官方只承诺「附近」⇒ 用 `UnitExists` 兜底**如实失败**）+ 条件「**目标玩家:X**」「**目标死亡**」（★五处注册各有判据：类型表/分组/三语/求值/文本往返）。
  ★★★**修「没按键目标也在尸体与活怪之间来回跳」**（用户真机复现 → 插桩取证定案）：根因 = `EVAL_GO` 的「补自动攻击」① **不看目标能不能打**（尸体也照按）② 排在**规则之前**，而本客户端的「攻击」= `AttackTarget()` **会顺带切目标**（文档只写 Toggles）⇒ 顺序成了「先被它切走 → 再被 选取目标 切回来」。修法 = **目标守卫**（实时 `UnitExists` + 非 `UnitIsDeadOrGhost` + `UnitCanAttack`，**不用过期 `st.canAttack`**）+ **挪到规则之后**（`if acted then return end` 之前）；守卫不过**不消耗** 2 秒节流。判据 = **组 251**。
  ★**新增调用点取证**：唯一调用口 `tselInvoke`（源码检查 `SEL TRACE WIRING CHECK` 禁掉裸 `pcall(fn…)`）+ 读值口 `EVAL_TSEL_PROBE()` + 命令 `/eh go tsel log|clear` + 落盘 `cfg.selProbe`（有界 40）；每条 =「谁调的 + 前 ⇒ 后 目标快照 + 按键轮 `p<N>`」+「接受发/被去抖丢弃」两条腿。★★由此查明：**「没按键却在跳」= `/run` 宏的 RunScript 队列余震**（真机实测 13.6 秒 51 发 ≈ 3.75 次/秒），**去抖窗小于冲刷节奏 ⇒ 每一发都放行**。判据 = 组 250。
  ★新条件「**围攻自身数量**」「**10s 交战人数**」（口径 = 聊天正文「X 击中你/你击中 X」· **只统计战斗**、非战斗恒 0 · 计算只在 `EVAL_MW_ACTIVE_INFO` 一处 → `UPDATE_STATE` 写 `st`，条件与两个 UI **只读** · 估算与名字数**取最大**、封顶 8）+ 近战探针 `/eh go melee 开始|停|报告|周围|通道|截获|全事件`。
  ★任务线/装备**全量数据**（`quest/QuestBulk.lua` 生成物）· 列表上限 **0 = 不限** · 任务线视图加**等级过滤**（两视图共用档位）· **种类筛选**与装备视图同源 · 缺图**占位（宏 961）+ 置灰 + 点击优先刷新** · 请求泵**常驻开启**（★帧一 Hide，OnUpdate 就不触发）。工具箱两行改名「**图层拖拽**」「**图层隐藏**」（只动显示值，键名/模块名/存档键不动）。
3. **1.75.2** — 🎯 **追踪类型条件 + 「调试日志」= 聊天输出总闸门 + 缩放大地图探索层折算收口**：条件「自身状态 → **追踪类型**」（下拉单选 · `TRK.hint` **13 条实证**候选表 · 纹理→种类**全等比对** · 贵调用只在追踪变化时做一次 · 导出走稳定 id、界面走本地化标签），由 `TRACK ICON CHECK` 钉在本机图标清单上。
  ★「**调试日志**」升级为**整个插件往聊天框说话的总闸门**（关掉 ⇒ `say`/`EVAL_SAY` 与日志环**一起静默**；常开例外只留**开关自身确认行** + 「引擎未加载完整」兜底 —— 否则关掉后看不到怎么开回来）；`cfg.wdebug` 改名「方案技能日志」，与总闸门不再撞名。判据 = 组 231 + `CHAT GATE CHECK`。
  ★缩放大地图**探索层折算收口**：关掉零动作 · 折算前**先探测客户端自己会不会级联** · 原值**只在自然档抓一次** · 关→开不连乘 · 关闭收钩子 + 开启再武装 · 折算取证环 `mapFitTrace` · 配置改**懒代理**（载入期缓存空表 = 设置与记录一个都不落盘）。判据 = 组 232 + `SM FIT CASCADE CHECK`。
4. **1.75.1** — 🔀 **两支合流 + 图层拖拽宽高只给聊天窗 + 宠物动作条**：`probe/map-scale`（框拖拽 / 图层工具 / 缩放大地图）与任务线两支**合流到 master**（5 处冲突逐条审过、3 个合并副作用修净：OnUpdate 真零形参 · `EVAL_HH_PETDECOR` 补 `hhHasPet()` 门 · 参考卷打包脚本补回 quest/ 三行），并立新铁律 **`TEST LOAD ORDER CHECK`**（harness 里 `test_assert.lua` 必须排在所有 `tools/*.lua` 之后 —— 工具模块在**载入期**自登记 `EVAL_TB_MOD_ROWS`，顺序反了组 200 会「模块完全正常却 got=false」）。
  ★★★**图层拖拽：宽/高只对「聊天窗」开放 + 持久化**（用户第三次改口径，1.74.33 的「所有窗口都不给」收窄）：唯一真值 `dfSizeOK`（`^ChatFrame%d+$`，**全项目只许出现一次**）⇒ 目标表项 `noSize` 现算；属性弹窗对聊天窗**建并显示**宽/高两行 + 窗高 224→280，其余窗口 **Hide** 两行并收回窗高（**不是灰掉**）；保存**先抓原值 → 再写新值**（反了等于没还原），落存档 `w/h/ow/oh` ⇒ 重登/应用存档写回；启动清理**只清 `noSize == true`** 的目标，聊天窗的 w/h 一个字段都不动。
  ★**常驻层补「宠物动作条」**：`DF_TARGETS` 新增 `PetActionBarFrame`（候选名解析，同动作条1~4）；★按需出现（没宠物时不在）⇒ 进 `DF_ROSTER_EVENTS` 的**有界跟随**，事件 `UNIT_PET`（有本地证据），★`PET_BAR_UPDATE` 零证据 **不注册**；跟满 `DF_ROSTER_TRIES` 即停。
  ★**口径更名**：「全职业**施法**工具」→「**全职业工具**」（Core / EvalHelp.toc(Title+Notes) / 三语言包 `CFG_TITLE`·`MB_TIP_TITLE` / 三语 README / DEVELOPMENT 一起改），Tab4「数据检索」→「**任务线 & 装备**」（`TAB_DS` + 页内六处文案；Tab 宽 74/78 → **84/88**，7 个 Tab 仍在一行 624 ≤ 660）。
  ★猎人助手提示行收成唯一来源 `EVAL_HH_TIP_LINES()`：没选喂养技能由「未识别」改成**明确提示 + 警示色**（与「食物：未设置」同形）。判据 = 组 207/208 + **新增组 227** + `DF OPEN HOOK CHECK` 四道哨兵。
5. **1.75.0** — 🧭 **数据检索新增「任务线」+ 地图标注右侧的「任务线推荐」弹窗**（`quest/` 独立目录）：**最终口径（数字一律从数据现算）** —— 策展经典链 **62** 条 + 自动任务线 **611** 条（**界面合计 673** 条 · ≥10 步 18 · 开门/史诗 17 · 最长 24 步）+ 全量 **751** 条带装备奖励任务 / **1262** 件物品（装备视图列出 **990** 件），覆盖 **4-60 级**，逐条抓自 `database.emberveil.org`（★首版 22 链 / 88 任务 / 62 奖励已被 1.75.9 全量采集取代）；**奖励优先**（精良武器排最前）+ **完整上下级步骤**；奖励行悬停出原生物品详情、步骤行点击进任务详情；抓取脚本（`fetch.js`/`chains.js`/`build.js`）**与插件零耦合**；数据自带 ⇒ **UnrealQuest 缺席照样能查**；★**弹窗 v2**（数据检索 · 地图标注右侧）：**装备优先**（按可获得等级列装备 + 真实物品图标 → 点装备**反查来源任务线**与完整步骤 → **[在数据检索中查询]** 直连 `EVAL_DS_SEARCH_NAME`）+ 两个视图 Tab（装备/任务线）+ 9 行分页列表 + ▲▼/滚轮 + 四档筛选（等级/类型/档位/阵营）+ 拖动柄；默认关、OnHide 收下拉。
  ★1.75.7 调（用户要求「将返回放置在下一页右边 · 整体按钮左对齐」）：底部按钮顺序改为 **[上页] [下页] [← 返回]** —— 按钮组起点 `QP_NAV_X = QP_PAD`（整体左对齐），返回按钮 x = `QP_NAV_X + (QP_BTN_W + QP_BTN_GAP) * 2`（第三位）。判据 = CHECK（按钮组起点 = 内边距 + 返回必须在第三位）+ 组 192 ⑧h（读真控件 `GetLeft` 验 x 递增；桩不返回几何就如实降级由 CHECK 守）。变异 M14 捕获。
★1.75.6 修（用户截图「样式有点重叠」）：详情**标题压住副标题** —— 根因 = 标题用 `SetPoint("LEFT", qpDetIcon, "RIGHT")` 锚在 **36 高**的大图标上 = **垂直居中**（≈ y −74），而副标题正好也在 −74 ⇒ 必然压字。正解 = 两者都以**图标右上角**为锚、**垂直依次排**（标题 −2 · 副标题 −20），字号/语言变化都不会再压。判据 = `QUEST PANEL CHECK`（钉锚点写法 + **禁**旧的 `LEFT` 写法）+ 组 192 ⑧i（读 `GetTop` 验几何；**桩不支持就如实降级**，绝不假红）。
★1.75.5 修（用户截图「底部按钮不见了」）：翻页按钮**同时进了 listWidgets 与 detWidgets 两份互斥清单** ⇒ `qpShowView` 先 Show（list）后 Hide（det），列表视图下**整个消失**。正解 = **不进任何互斥清单**，由 `qpShowView` **末尾显式 Show**（两视图都常显、位置不跳）。★★可见性契约的又一实例：**同一控件只能属于一份显隐清单**；判据补 CHECK（禁进互斥清单 + 必须显式 Show）与组 192 ⑧h（**两视图下翻页按钮都必须可见** —— 这正是漏过的那条：只验了「详情控件在列表视图要隐藏」，没验「列表自己的按钮要显示」）。变异 M13 捕获。
★1.75.4 追加（用户要求，三条）：① 翻页**不用图标**，改**文字按钮 [上一页][下一页]**（复用图标库 `IB_PREV`/`IB_NEXT` 键），放**底部 [返回] 旁边左对齐**（位置由 `QP_NAV_X = QP_PAD + 64 + QP_BTN_GAP` 单一来源算）；② **焦点离开必须隐藏装备信息**（旧实现 `OnLeave` 只复原底色 ⇒ 原生 tooltip 残留）；③ **详情大图标可获取焦点并显示装备信息**（Texture 收不到鼠标 ⇒ 加了 36×36 的覆盖 Button）。★顺带修：`EVAL_QP_SHOW` 从不调 `qpShowView` ⇒ **首次打开**时详情专用控件（返回/大图标/数据检索钮）在列表视图里露着（用户截图里正是这个）。变异 M12（翻页改回图标式）被 CHECK 捕获。
★1.75.3 追加（用户要求，三条）：① **滚动区铺满窗口** —— 行数**按窗口高度现算**（纯函数 `EVAL_QP_ROWS_FOR(h, top, rowH, tail)`，17 行/页），**禁写死**（图标库那种 `IB_ROWS = 9` 照搬会留白，用户在图 3 圈出）；② 装备详情 **36×36 大图标 + 12 号大标题（品质色）+ 副标题（属性）**，图标仍只取 `GetItemInfo`；③ 放大镜素材换成**本插件自带** `Interface\AddOns\EvalHelp\media\icons\database`（与图标库同款），点击后**不关窗**，只回执一行「已送数据检索：<任务名>」（★旧判据「点完应收起」已按要求**反转**成「必须仍在显示」）。变异 M10（又关窗）/M11（行数写死）均捕获。
★1.75.1 追加（用户要求）：**阵营严格三分类**（联盟/部落/共有 —— 旧写法把「共有」并进联盟/部落，`c.f ~= "B"` 那半句已删）；**每个任务节点左侧放大镜**（素材 `INV_Misc_Spyglass_01_TEX`，与 PetHelper 同源；点了按**任务名**（不是链名）走 `EVAL_DS_SEARCH_NAME` 直达数据检索）；装备视图三个筛选（等级/类型/阵营）⇒ 读值口 `EVAL_QP_SET_FILTER(a,b,c)` 三参。
  ★v1 事故（务必记住）：`local b = dsBtn(..., function() b.btn ... end)` 里的 b 是**全局 nil**（local 作用域从声明之后开始）→ 点按钮当场红字；另有「label 传空串 = 空白按钮」「详情行压住底部按钮」两处 UI 事故 —— 判据分别落在 `QUEST PANEL CHECK`（自引用检测/空白按钮检测/**布局重叠独立验算**）与组 192。变异 M3/M4/M5/M7 全捕获。
6. **1.74.30** — ⏱️ **射击计时 + 条件「距下次射击」**：探针真机定案（法术频道含「自动射击」的原文 = 锚点、`UnitRangedDamage[1]` = 射速 2.09s，与近战**双锚点互不干扰**）；数值条件 `shotLeft`（文本 `距射击<0.5`、初始值 0）；修「切换条件类型把 30.0 带进时间型」；消耗品助手左键不再弹窗。
7. **1.74.29** — 🖼️ 战斗UI **激活方案格品阶色边框** + 两个助手弹窗候选**原生物品详情** + 喂食助手 `GetPetHappiness()` **快乐度边框**（开心亮绿 / 一般金 / 不开心红 / 无宠物默认金）。
8. **1.74.28** — 🧺 两个助手弹窗候选**按物品类型过滤**（品质 → `GetItemInfo(链接)` → **自建 tooltip 兜底并自愈客户端缓存**；药草矿物材料等全剔，判不出不剔）+ 验证命令。
9. **1.74.27** — 🧹 稀有提醒转播**提取为独立模块** `tools/RareWatch.lua`（主程序只留两个接线点）+ **工具箱开关**（打包基准 69）。
10. **1.74.26** — 🧹 点名字**只做一件事**：`TargetByName(名字)` 选中它，选不中**就报错**；删掉所有与任务插件机制的耦合。
## 十、常驻卷瘦身移出（**已废止的 1.74.9 快照**）

> ★**本节原样保留的历史快照已删除**（2026-09-25 记忆体压缩）：那些「原文照存」的内容要么已回到常驻卷（铁律 3 的 Heart/C 读法、§5.4 UI 判据、§5.5 API 事实），要么在**附录 R9~R16** 里按 1.74.32+ 口径重新整编过；任务线明细已迁到 **§十四**。
> 仍需要「当时的逐字原文」时，去 **git log / `CHANGELOG.md`** 查（本文件里不再重复一份）。
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

### 11.4 ★★★2026-09-25 大压缩（用户：「先压缩下记忆体.整理流水账的版本记录.提取关键的最终有价值的记忆保存」）
- **成果**：常驻卷 `CLAUDE.md` **103,414 → 57,658 B**（476 → 219 行）；参考卷 `CLAUDE_REFERENCE.md` **354,750 → 166,034 B**（2,180 → 877 行，−53%）。
- **常驻卷做法（手写重排，不靠脚本）**：保持原有章节骨架（顶栏铁律 / §一~§五），把每条判据压成「一句规则 + 追溯锚点（组号 / CHECK / 标识符）」，删掉「为什么」叙事与重复解释，把长篇踩坑留给参考卷；★**锚点一个都不许丢**（组号、CHECK 名、标识符、`Rxx` 引用）。
- **参考卷做法（node 脚本按段替换，见 `tmp/ref_splice.js` / `ref_bulk.js` / `ref_fix.js`）**：① 逐版本流水账（§十二/§十三/§十四）**手写重排**成「最终口径」清单；② 案例长文（R15 的 ⑥a~⑥q、R17~R22）先用**机械规则**（段首 2 行 + 前 5 行非空 + 最多 8 行含 判据/变异/★/铁律）压一遍，再把「引用最频繁、片段最碎」的几节**手写重写**干净；③ §十 那批「1.74.9 原文照存」（与常驻卷/R9~R16 重复）**整节删掉换成指针**。
- ★★★**压缩后必须跑完整性自检**（`tmp/ref_verify.js`）：把常驻卷里引用到的 **所有 `Rxx` 编号 + R15 子标签（④⑤⑥d⑥f⑥h⑥i⑥j⑥k⑥l⑦⑧）+ 章节标题**逐个回查参考卷，**断链即报**（本轮就靠它抓到「R20b 被机械压缩吃掉」并补回）。★绝不能只看「文件变小了」就收工。
- ★★**steering：机械压缩会留下断句碎片**（如 ⑥c 的「真因」只剩第 2 条）⇒ 对「常驻卷点名说『全案见 Rx』」的那几节，必须**手写**保证自洽，机械压缩只用于纯历史流水。
- ★**已知工具故障（待修）**：`node dsh_memory_budget.js check` 现在直接抛 `TypeError: Cannot read properties of undefined (reading 'version')`（`dsh_memory_budget.js:232`，安装布局/版本探测那一段）⇒ 该闸门暂时**不可信**；当前常驻卷 57.6 KB，远低于旧 65,536 与新的 1 MiB，暂不影响使用。

## 十二、1.74.29~1.74.36-2 明细（压缩版：只留**最终口径**；逐版本流水见 CHANGELOG.md 与 git log）

### 12.1 射击计时（`/eh go 射击探针` 真机定案）
- 数据源 = `UnitRangedDamage(player)`：**[1] = 秒/击**、[3]−[2] = 弹药伤害；`UnitAttackSpeed` 主/副手；`IsAutoRepeatAction(slot)` 可用。
- **锚点通道 = `CHAT_MSG_SPELL_SELF_DAMAGE`**，判据只认原文里的「自动射击 / Auto Shot」子串（普攻与暴击两种句式都覆盖）。
- **自校准**：留最近 6 次 `Δt÷API` 取中位数；样本 ≥4 且中位数落 `[0.9,1.1]` 才修正，否则用 API 原值；离群（<0.5× 或 >1.5×）丢弃。实测 Δt 均值 2.16 vs API 2.09（比 1.03）⇒ **未观测到急速差异，不硬编系数**。
- **状态感知单入口** `EVAL_SWING_KIND/SPEED/REMAIN_ACTIVE`（自动射击中 = 射击）⇒ 战斗UI 金条 / 状态UI 行 / 条件 `swingLeft` 全部自动跟随；文案分「下次射击 / 下次攻击」。
- 新条件 `shotLeft`（文本「距射击」/`shotLeft`、编辑窗 `CT_SHOTLEFT` 三语、时间型 0.1 步进 0~10、初始 0），与 `swingLeft` **显式区分**。
- **继承修复**：旧 `new.op,new.n = old.op,old.n` 无条件继承 ⇒「能量>30」切到时间型会带进 30.0；改纯函数 `seSwitchCond`（**同参数域才继承 n**，op 始终继承）；时间型清单单一来源 `SE_TIME_K`/`seIsTimeKind` 上移到使用者之前。
- 判据 = 组 188 ①~⑦ + 变异 11/11。★坑：读值口 `EVAL_TEST_SE_TYPE_INIT` 曾写在 `SE_TYPES` 声明之前（`DECL ORDER CHECK` 当场抓到）。

### 12.2 UI 三处补完（1.74.29）
- 战斗UI 激活方案格：`uiProfBtnBorder` 4 条 1px BORDER 纹理，只有激活格 Show，颜色与文字同源（品阶色，算不出用暖金）。
- 弹窗候选（`tools/IconGrid.lua` 共用件）：悬停先 `SetBagItem(bag,slot)` 出原生 tooltip 再补「名称 ×数量 [包,格]」+ 提示 + 已选角标；拿不到 bag/slot 退回文本。
- 喂食助手快乐度边框：复用主图标既有 4 条 1px 亮边，颜色 `GetPetHappiness()` 现算（3=亮绿 / 2=金 / 1=红 / 无宠物或接口不可用=默认金），**不新开后台 tick**。
- 消耗品助手：面板入口收归**右键**（左键与拖动图标争用同一按键），三语 `CH_MAIN_HINT` 同步。

### 12.3 1.74.31 载入审计（最终结论）
- ★★★**OnUpdate 零参数**（真机炸点）：本客户端调 OnUpdate **一个参数都不传** ⇒ 帧引用必须用外层 local 捕获，回调写 `function()`；判据 = `ONUPDATE ARG CHECK` + 组 190⑦；`OnEvent` 参数三态能兼容、**OnUpdate 不能**。
- ★★★**载入期没有任何毫秒级时钟**（三个时间源逐一实测）：`GetTime()` **载入期恒 0**（进世界才走）、`GetGameTime` **恒定 6 不随时间动**、`time()`/`date()` **只有 1 秒分辨率**；api 索引 1343 条里确认**无 tick/高精度计数器** ⇒ 这是客户端限制。
- ★★★**唯一手段 = 秒级抽样平均**：随机相位下 `E[floor(T2)−floor(T1)] = 真实时长` ⇒ 多次 /reload 求平均秒差即无偏估计；实现 = 报告把 `t0→files`（源码段）与 `files→vars`（存档段）秒差累计进 `cfg.loadStat`（写存档）。★措辞铁律：**「同秒 ⇒ <1 秒（上界）」/「跨秒 ⇒ 单次定不了量」**，**禁止**写「至少 1 秒」（跨秒不构成下界 —— 边界前 1ms 采样同样跨秒）。实测源码段 <1 秒（与离线 ≈180ms 一致）⇒ **源码编译不是载入慢的原因**；存档段两次重载都跨秒。
- **报告分两层**：登录 = 1 行摘要（源码段均/存档段均/样本数/存档键数/本次清残渣数）；`/eh 载入报告`（full=true）= 完整取证（毫秒段/墙钟/秒级窗口/抽样/原始读数/时间源 dump）⇒ **完整取证始终写进调试日志**（聊天只给摘要），深挖时 `/eh logdump` 也拿得到。
- **`LOAD_RESIDUE_KEYS` 一处真源**（Core.lua）：**只有 `force`（`/eh 存档清理`）才清** —— 它们是若干判据的「落盘证人」，自动清掉 = 「事后读回来」的能力无声消失；★★**真状态键绝不进清单**（`ds/tb/war/ui/title/share/log/st` 删了就是丢用户配置）。`LOAD_PROBE_KEYS`（4 个探针键）规则不变：`iconDump` 一律清、其余非当天才清。
- 存档体积：**119 KB → 51.6 KB**（`iconDump` 62 KB 清掉、`log` 环 `EH_LOG_MAX` 300 → 100 ⇒ 25.6 KB → 5.9 KB）。
- 判据 = 组 190 ①~⑫ + 变异 M14~M25 全捕获。★★**两条弱判据教训**（都要记住）：① 断言**不能放在「被测状态已被后续步骤覆写」之后**（否则恒真、变异存活）；② 夹具**必须真的把被测分支走一遍**（M23 因夹具两点同秒 = 只走同秒分支 ⇒ 反向哨兵永远照不到，改夹具后当场捕获）。
- 收尾：仓库根 `dbg_*.lua`（10 个一次性脚本）与 `CLAUDE.md.bak` 搬进 `.dsh/debug-residue-20260922/`（`.dsh/` 在 `.gitignore`）。
## 十四、任务线 & 装备（1.75.0~1.75.21）· 压缩版：只留**最终口径**（逐版本流水见 CHANGELOG.md / git log）

### 14.1 数据来源与生成链（**唯一真值**）
- **唯一真值 = `https://database.emberveil.org/quests`**（用户 1.75.1 明确「数据为准」）：任务线/节点/等级/阵营/奖励物品全部以该站为准，不凭记忆、不引别家库。
- `quest/QuestData.lua` 与 `quest/QuestBulk.lua` 都是**生成物**（纯数据、无函数）：`node quest/build.js`（用缓存）· `--force` 全量重抓。★**手改必被下次生成覆盖** ⇒ 「改数据」＝改策展清单 `quest/chains.js`（任务 ID 序列/阵营/档位/等级/地区/点评）后重跑生成。
- 抓取链：`sweep.js`（列表页 → 50 条/页，行内含等级/名称/地区/阵营/类型/经验/**奖励物品**）→ `sweep_details.js`（物品页 + 任务详情页的系列块）→ `build_bulk.js` → `QuestBulk.lua`。抓取器 `fetch.js` 自带本地代理自举（`127.0.0.1:10809`）、限速 200ms、重试 3 次、缓存 `quest/cache/`（`.gitignore`）。站点 = Next.js SSR，`Cookie: lang=zhCN` 全站中文，品质取 RSC 的 `qualityColor`。
- **加新任务线**：往 `quest/chains.js` 加一条 → `node quest/build.js` → 跑两道闸门。
- `QuestBulk.lua` 记法（紧凑串，分隔符 `|`，生成器**先证明**名字不含它）：`q[id]="名|等级|地区|阵营|奖励id,id"` · `i[id]="名|品质|ilvl|dps|speed|部位|类型|属性|图标|是否装备"` · `s[n]="系列名|lo|hi|地区|档位|是否开门史诗|步骤id,id"` · `sn[id]="步骤名"`。
- 逻辑层 `QuestChains.lua` 读值口：`EVAL_QC_BULK_READY/META/QUEST/ITEM/ITEM_ROWS/SOURCES` + `EVAL_QC_LIST/SERIES_LIST/COUNT/DETAIL/FACTION`。★`EVAL_QC_ITEM_ROWS` = **全量优先、策展兜底**；★`EVAL_QC_ITEM_CHAINS` 走**反向索引**（**禁借道** `EVAL_QC_ITEM_ROWS`：两种行形状不同，借道 = 静默 nil）；★`EVAL_QC_SEARCH` 追加一遍 series（`kind="series"`、键 `"s:<位次>"`），详情形状与策展链**完全一致**（界面不分叉）。

### 14.2 ★★★站点三大事实（全部实测踩过，每条对应一次返工）
1. **列表页的奖励图标是「截断显示」**（只画前几枚）⇒ **奖励权威来源 = 任务详情页**；生成器取「列表 ∪ 详情」并集（只吃列表会漏 93 条「仅详情页有」）。
2. **`?name=<词>` 只匹配任务标题的英文原文子串**：`name=Onyxia` ✓ / `name=安其拉` **0 条**（中文只是显示层）；多词短语（`Scepter of the Shifting Sands`）也是 0 条 ⇒ 名人线种子必须用**英文单词**。
3. **「本系列第 N/M 部分」必须结构性解析**，且块有**三种形态**：① 全链接 ② **全纯文本（无链接）** ③ 混合。只按链接解析时形态② 退化成「只剩你在这里那一步」（经典线整条消失）⇒ 正解 = **链接 + 可见文本「数字→名字」双来源**，再用 `quest/resolve.js` 的「任务名→id」补缺（候选要过 `part/total` 交叉验证）。★旧实现按可见行「数字/名字」对齐 ⇒ 部分页面整块错位、生成一堆**假任务线**。
- 数据质量三道补丁（写进生成器，不许回退）：奖励 = 列表 ∪ 详情 · 系列 `trusted`（id 覆盖 <50% 或步骤数与站点 `total` 不符不采信）· 物品名双来源兜底（白/灰物品无「拾取后绑定」行 ⇒ 用任务页奖励链接文本补）。

### 14.3 ★★★步骤名事故（两层，**修一处不算修好**）
- 现象（1.75.1 用户）：「60 级经典任务线**爱与家庭**怎么没有」——它在包里（自动线「救赎」第 4/5 步）却**搜不到**。
- **第一层（生成期）**：全量只装「带装备奖励」的任务（省 1.12 内存）⇒ 该链 7 个任务 `rewards=[]` 全被排除；而收集判据写成「连**列表页**都没有才存名字」⇒ 这 7 个都在列表页、只是没奖励 ⇒ 名字没人接 ⇒ 显示 `#5742`。**修法** = 判据改成「**不在进包任务表**里」（`shippedIds`）⇒ `sn` 25 → **1575**、1834 步里无名步骤 **1585 → 0**。
- **第二层（运行期）**：① `EVAL_QC_SERIES_DETAIL` 把站点抄来的名字 `n` **覆盖成序号**；② 行模型只认 `q` 表（没奖励的步骤在 q 表里根本没有）⇒ 即使 `sn` 有名字也读不到。**修法** = 详情加 `nm`（序号留 `n`）+ 行模型**四级来源**（`nm` → `s.q.n` → `EVAL_QC_STEP_NAME(id)` 读 `sn` → 如实 `#id`）+ 放大镜改用行模型真名 + 「装备→来源任务线」也补 `sn` 兜底。
- **闸门** = `quest/audit.js` **H 段（生成物体检）**：任何系列步骤既不在 q 表也不在 sn 表 ⇒ **硬错误**（阈值 0）；变异 = 换回旧生成物 ⇒ 1950 无名步骤、exit 1。
- ★★**自查假绿**：`s` 表是**序列**（`s={ "名|…" }`）**没有 `[n]=` 键**，首版按键值行解析 ⇒ 解析 **0 条**、闸门恒绿 —— **解析前先确认表的形态**。
- ★★**判据必须打在用户真正看到的输出**（行模型/渲染数据）上，不是中间层：判据 = **组 228**；变异 = 名字解析改回只认 q 表 ⇒ 「实测带 # **7** 行」exit 1（正是用户截图那 7 行）。

### 14.4 最终数据规模与口径（**别混用两种口径**）
- 发货口径（`QuestBulk.lua`）：有装备奖励的 **751** 条任务 + 引用到的 **1262** 件物品 + **611** 条自动任务线（原始 688 条里 77 条因同名或步骤重合 ≥60% 让位给策展链）+ **62** 条人工策展链 ⇒ **界面任务线视图实际列出 673 条**（= 62 + 611）。
- 审计口径 = 缓存里 `total≥2` 的站点系列 **769** 条。★★**文案写数字前先问「这是谁的口径」**。
- 装备 **990~994 件**（部位或 DPS 判定，`EVAL_QC_IS_WEAPON` 按 `dps>0` 现判）。
- 审计（`node quest/audit.js [--online]`，现 **0 硬错误**）：A 装备 id↔名/品质/部位自洽 · B 任务奖励 id 全在物品表、**装备不许孤立** · C 列表页↔详情页双向一致（93 条不一致全是「仅详情页有」= 列表截断，数据已取并集）· D 任务线完整性 · E 策展链核对（如实列「站点更长 12 条 / 站点未给系列块 29 条」）· F 装备↔任务链接不一致 0 条 · **G 区域经典覆盖清点**（黑石塔 27 · 东瘟疫 27 · 希利苏斯 20…；唯一未命中关键词 = **灰烬使者**，1.12 它只有纳克萨玛斯掉落、**没有任务线**）。游戏内审计 = `/eh ds 任务线 审计`（**以游戏内名字/图标为准**，未缓存按限频排队补，跑第二次看自愈）。

### 14.5 界面最终口径
- **排序 = 等级 → 稀有度 → 原序**（旧的「开门/史诗优先 → 档位 → 等级」已被 1.75.10 明确推翻）；两个来源**先全收 → 统一排序 → 最后按 cap 截断**（★只过滤不 sort = 顺序原样，判据 ⑧aa 当场抓到）。5.1 的 `table.sort` 不稳定 ⇒ 必须带原下标装饰。
- **稀有度 6 档 = 魔兽品质色**，单一来源 `EVAL_QC_RARITY(rec)`（token + RGB）：LEG `ff8000`（传说关键词：雷霆之怒/逐风者/风剑/埃提耶什/萨弗拉斯/灰烬使者/流沙/甲虫之墙/安其拉）· EPIC `a335ee`（开门/钥匙/团本关键词或 `open` 标记或 ≥10 步）· RARE `0070dd`（策展 S 或 ≥6 步）· UNCOMMON `1eff00`（策展 A 或 ≥4 步）· COMMON `ffffff`（≥1 步）· POOR `9d9d9d`（拿不到步骤 ⇒ 如实降级）。★关键词一律 `qcHasAny()` **plain 逐词**（Lua 模式里 `|` 不是交替）。
- **列表行** = `[档位·稀有度] 名字 · 地区 · lo-hi`；**行尾奖励图标**紧跟标题**左对齐**（6 槽位池，起点 `x0 = 22 + qpTextWidth(文本) + 8`，逐槽 `ClearAllPoints` + `SetPoint`；装不下用 `+N` 如实提示）；图标走与武器列表**同一套** `qpItemTex`，悬停出物品链接 tooltip、点击进装备详情。★**宽度单一来源 `qpTextWidth`**：优先 `GetStringWidth()`（本机**没有**该 API ⇒ 兜底逐字节判 UTF-8 估算），**绝不用 `string.len` 当宽度**。★**行池复用**每轮必须逐槽 `Hide` + 清 `rwIds`（否则翻页残留）。
- **筛选布局**：任务线视图 **F1 等级 · F2 类型 · F3 阵营**（等级**两视图都在最左**）；装备/任务线**共用同一份种类菜单**（`DS.qpKinds` 唯一选中态）。等级 **7 档**：ALL / 10-19 / 20-29 / 30-39 / 40-49 / **50-59** / **60+（hi=999）**；标签**由 `QP_LV` 现算**（写死 = 加档必漏）。★`DS.qpTier`/`QP_TIER` **整块删除**（死代码必漂移）。
- **种类**：唯一来源 = 生成数据的 `k` 字段；`EVAL_QC_KIND_LIST()` **现算**（只列数据里真有的，排序 = 武器子类型在前 → 件数降序 → 名字升序 → 首见序）；`EVAL_QC_KIND_GROUPS()` 返回分组（界面不自己分组）；多选用 `EVAL_DD_OPEN{multi=true}` + `onPick(pi,on)` **两步布尔**（禁 `on and true or nil`）+ 分组标题 `locked` + 末行「全部」清空。★站点把**戒指/项链/饰品**的类型全写成「其它」，**只有部位分得开** ⇒ `QC_SLOT_KIND = { 手指→戒指, 颈部→项链, 饰品→饰品 }` 在「类型=其它或空」时按部位补。
- **等级过滤口径 = 区间重叠**：`(hi >= lvLo) and (lo <= (lvHi or 999))`。写「lo 落在档内」会让**跨档长线**整条消失（判据 ⑧u 是它的反向哨兵）。装备视图仍用「来源任务等级落档」。
- **列表全量**：`EVAL_QC_SEARCH` 认 **`cap ≤ 0 = 不限`**，DataSearch 侧单一来源常量 **`QP_CHAIN_MAX = 0`**（旧写死 200 + 等级升序 ⇒ 列表停在 30 级，用户报的「最高只有 30 级」就是这个，**不是数据没收集齐**）。
- **未扫描出的装备** = **宏图标 961** 占位（`GetMacroIconInfo(961)`，拿不到才退回问号）+ **置灰 0.55** + 悬停「数据更新中…（点击优先刷新）」+ **点击 → `qpReqPriority(id)`**（插到队首 + 清 `st.at` 与 `tried[id]`）。
- **滚动 = 抓宠帮手范式**：滚轮 **1 行/格**、`[上页][下页]` 按页；像素滑动动画（**每帧 ×0.55 缓动**、`|anim| < 0.6px` 归零并**摘掉 OnUpdate**，整页起步夹到最多 3 行）；`qpLayoutRows` **必须先 `ClearAllPoints`**（每帧追加锚点 = 布局漂移）；`qpFillList` **绝不能再把 `qpOff` 拍回页边界**（只夹 `[0, total-ROWS]`）。★OnUpdate 零参数 ⇒ tick 写 `local function qpAnimTick()` 无参 + 外层 local 捕获帧。
- **请求泵（1.75.16 定案）**：泵 **挂 UIParent + 常驻开启**（`EVAL_QP_HIDE` **故意不 Hide** —— OnUpdate 只在帧可见时触发，挂弹窗子级 ⇒ 弹窗管线漏一处泵就永远不跑；「只在当前看得见时检索」由**内部**判「弹窗显示 + 队列非空」把关）；工具柄走**正式读值口** `EVAL_WTT_HANDLE()`（**不许读全局名** —— 自建 tooltip 失败退化时那个全局名恒 nil ⇒ 静默不请求）；★**取柄/授权通过之后才 `table.remove`**（先消费再取柄 = 拿不到柄时那件**白丢**且毫无痕迹；拿不到就记 `blocked` 且队列原样留着）。队列**每次重绘重建**（`qpReqBegin()` 在 `qpFillList`/`qpDrawDetailBody` 开头各一次 ⇒ 只装这一屏；994 件里没上屏的一件都不请求）；限频 **2.0s/件**、上限 **QP_REQ_MAX=24**（1.75.20 起「入队不截断 + 收尾 `qpReqTrim()`：先全收 → 按列排序 → 再截 24」—— 入队时截断 = 行序先到先得，后面的行连排队资格都没有）。★**可观测性**：`EVAL_QP_REQ_STATE()` 给 `req/blocked/tried/pumpShown`，探针 `/eh ds 任务线` 打 `[请求泵] 已请求 N 件 · 因拿不到工具柄挡下 M 次 · 泵帧=开/关` —— **光看「队列几条」分不清「在抽」还是「死了」**。
- **首屏「空着」是数据事实**（`quest/probe_chainlist.js`）：任务线一行最多 6 个奖励图标（装备视图每行 1 个）⇒ 同屏待抓件数最多 4 倍；10-19 档 17 行只有 2 行有奖励。★量「第几轮才轮到」**必须逐轮模拟**（拿「行序位次 × 2s」当等待时间是错的）。
- **顺滑/交互杂项**：`EnableMouse` 是 EditBox 能聚焦的前提（**漏了 ⇒ 一个字都打不进**，用户报的「输入框无法输入」就是这个）；修法四件套 = `EnableMouse` + 点击聚焦兜底按钮 + `SetJustifyH("LEFT")` + 字体链三级兜底；渲染层双 nil 守卫（`EVAL_DD_OPEN`/`DD_FILTER` 收到非表不许报错）；放大镜 = `EVAL_DS_SEARCH_NAME(词)` → `pcall(EVAL_HELP_CFG_SETTAB, 4)` → 回执行（**先送词再切 tab**，照抄 `EVAL_PH_JUMP`）；任务行左侧贴**黄色感叹号**（与数据检索列表同一张图）+ 拼 `LvNN`（`EVAL_QC_QUEST_LEVEL(id)`，查不到如实 nil）。
- ★★★**`local function` 的声明位置即契约**：`EVAL_QP_SCROLL` 用了声明在其后的 `qpFillList` ⇒ 真机 `attempt to call global 'qpFillList' (a nil value)`。**结构性修法** = 前向声明 `local qpFillList` + 定义写 `qpFillList = function()`；★配套新闸门 **`LOCAL ORDER CHECK`**（`probe_localorder.js` 做真词法分析：块栈收支平衡 · 字段名/方法名不算引用 · `--selftest` 7 条夹具 · 扫 toc 全部 .lua）。★**扫描判据前必须先摘注释**（首轮就是被自己注释里的 `` `local function qpFillList()` `` 字面量误报）。
- **闸门**：`QUEST TOC CHECK`（三文件顺序 QuestData→QuestBulk→QuestChains · 磁盘↔toc 双向 · 生成物纯数据 · 行数/系列数下限 · 任务行分隔符个数）+ `QUEST WIRING CHECK` + `QUEST PANEL CHECK` + 组 191/192/228；**省时闸门** `node check.js`（luacheck + test_engine 并行 28s / `--quick` 6.5s 跳过组 192 并**如实打 SKIPPED** / `--full` 追加 audit / `--selftest`）—— ★实测**组 192 独占 22s**（1300 行断言 × 每次刷新跑 673 条全量检索 + 17 行重绘）。`mutate.js` 默认不再全量且**中断自动还原**。
- **变异编号**（全部 CAPTURED）：M20~M81（数据层 kinds / 单选 / 截断位置 / 排队顺序 / 排序键 / 前向声明 / 审计对账 / 泵挂载与限频…）。
- ★★**工具坑**：`node xx.js > log.txt` 在 PowerShell 里写出 **UTF-16LE**（node 读回中文全乱码）⇒ 写日志用 `| Out-File -Encoding utf8`；★`Get-Content`/`Set-Content` 往返改含中文源码**不可逆写坏**（103 处 U+FFFD）⇒ 只用 edit/write 工具或 node 脚本。
## 附录 R：从常驻卷（CLAUDE.md）清理迁入的判据详案（不自动载入）

> ★**来源**：常驻卷超工作区指令预算（65,536 字节）被截断，清理时把「判据还在、但踩坑经过/版本流水属于叙事」的块整体迁到这里。
> 常驻卷里对应条目末尾的「全案见参考卷附录 Rx」即指本节。**这些信息没有删，只是不再每会话自动加载**。

### R1. 分享「回声忽略」误判 + 「分片到了却不弹」取证全案（1.74.4~1.74.5）

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

### R2. local 声明顺序连踩三次的实例（1.74.29）

- 本轮在 `addons/` 独立插件上**连踩三次**：`pb8Start`→`autoEnsureLabel`、`pb9SetAll`→`featWm`、`uiRefresh`→`hlApplySelected`。
- 盲区实例：行 OnEnter 里 `add(...)` 用了 21 次、而 `local L = {}`/`local function add` 写在 40 行之后 → 运行期 `attempt to call global 'add'`，闸门静默通过。
  （检查按**名字**比对，文件内还有**缩进的**同名 local 就整名跳过（防误报）⇒ 顶层「先用后声明」漏网。）
- 旧检查只扫 15 个生产文件，独立插件目录曾是盲区（1.70.46 的老教训重演）；1.74.29 补 `ADDON DECL ORDER CHECK`（扫 `addons/**/*.lua`，与主仓同算法）。

### R3. 品阶配色史与评分/头衔旧口径（1.74.19~1.74.22）

- 神级配色史：暗金 b87333 → 亮蓝 00bfff → 深红 c00000 → 亮金 ffcc00（试色）→ **亮蓝 00bfff**（1.74.22 用户定案）。
- 评分旧口径：**空技能白送 1 分** ⇒ 25 条空技能就神级（实测复现过）；1.74.19 重做为「空技能 0 分 + 条件按类加权」。
- 头衔旧口径：2~5 档全是「≥1 个」⇒ 头衔满档只要 1 个方案，连带彩蛋闸门形同虚设；1.74.19 改为 `SH_TITLE_REQ = { 1, 2, 3, 3, 2 }`＋逐级满足。
- 旧写死值（已废，一律现算）：25 / {3,9,15,21,26} / {1,4,7,10,13}。

### R4. 稀有提醒转播全案（1.74.23~1.74.27）

- ★★★**跨插件：捕获 UnrealQuest 的稀有提醒**（1.74.23，用户「只要知道他发现稀有的那一时刻，在对话框内输出一段文字」）：
  弹窗唯一出口 = `World/RareAlert.lua` 的 `RareAlert:Show(entry, distance, dx, dy, others)`（内部 `SetAlertWindowText → UpdateArrow → Client.ShowObject → shownUntil → 音 → 聊天 → 计数`）
  ⇒ **包住它、在返回后回调 = 卡片已经在屏幕上的那一刻**。模块注册表是**公开**的：全局 `UnrealQuest`（`Core/Namespace.lua:17`）+ `UnrealQuest:GetModule("RareAlert")`（就是 `UQ.modules[name]` 那张**普通表**，`NewModule` 只塞 name/enabled、无元表保护）；
  ★**安装必须等 VARIABLES_LOADED**（AddOns 按目录名排序，**EvalHelp(E) 先于 UnrealQuest(U)**，载入期拿不到对方 —— 与 DataSearch 的 `dsUQModule` 同因；那个是文件内 local，本处提成全局 `EVAL_UQ_MODULE`）；
  ★包装纪律 = **返回值逐个透传 + 原函数抛错照原样 `error(a,0)` 抛出**（吞掉别人的错 = 把别人的 bug 藏起来），只在抛错时如实计数；
  兜底 = `Show` 不可包时轮询对方**公开读值口** `RareAlert:GetStatus().alerts`（单调累计计数；**首读只立基准**，否则会把本次登录前的历史计数当成刚弹过）；兜底 tick 父级必须是 **WorldFrame**（挂 UIParent 开全屏地图会停摆，见 1.70.39）；
  载荷：名字走 `Database:GetUnitName(entry.unitId)`、品阶 `entry.rank`（1 精英/2 稀有精英/3 首领/4 稀有）、`distance` 已是整码、`others` = 同刻另有几只；频率上对方自带「同怪 180s 冷却 + inRange 抖动带」，不会刷屏；
  命令 `/eh go 稀有`（状态/开/关/试；`试` 直接调对方 `TestNearest` 走完整链路自证）；判据 = 组 199 + 源码检查 `RARE WATCH WIRING CHECK`（安装点 / 命令前缀字节数 / 包装透传与照抛 / 兜底 tick 父级）。
- 染色（**1.74.24** 用户「对稀有精英染色」）：名字按品阶上色（精英 银 c0c0c0 · 稀有 蓝 0070dd · 稀有精英 紫 a335ee · 首领 橙 ff8000 —— 物品品质那套玩家一眼就懂；与「方案品阶」五色是**两个维度**，项目纪律要求错开，故最低档用银不用白）；★**整条消息只许一段 8 位色码**（一条多段会整条不画）⇒ 色码由调用方按品阶给，语言包里不再写死金。
- 可点（**1.74.24 → 1.74.26** 用户「点击他可以定位目标」＋「点击头像相当于目标切换到稀有精英目标」＋定案原话「点击名字逻辑很简单.不要和那边插件的机制管理.需求只要是调用类似目标函数选中目标就可以了.如果目标不存在就报错.」）：名字做成链接 `|c..|HEHRW:<名字>|h[名]|h|r`（形态照抄分享封皮那条真机配方：色码在外、链接在里）⇒ **点名字 = 一次 `TargetByName(名字)`**，选中报「已选中目标：X」、选不中报「选不中目标：X」—— **就这一个动作，没有第二动作、没有退路**。★1.74.26 按用户定案**删掉**了所有与那边插件机制的耦合：不再有坐标 / 最近刷新点 / 地图投影 / `EVAL_DS_SHOWMAP` 开图；token 从 `EHRW:areaId:x:y:unitId` 收成 `EHRW:<名字>`（名字是唯一需要的东西）—— 源码检查现在**反向守**：稀有转播里出现 `EVAL_DS_SHOWMAP`/`EVAL_RW_NEAREST_LOC`/`GetCurrentZoneView` 即 FAIL。
- ★★★**1.74.27 提取为独立模块 + 工具箱开关**（用户：「将以上功能提取到独立文件内 ./tools 然后再工具箱内设置开关.」）：整块搬到 `tools/RareWatch.lua`（**主文件只留两个接线点**：VARIABLES_LOADED 的 `pcall(EVAL_RW_INSTALL)`、命令分支 `/eh go 稀有`）；新模块只走**全局桥**（`EVAL_SAY`/`EVAL_LOGLINE`/`EVAL_L`/`rawget(_G,"EVAL_HELP_CONFIG")`），绝不引用主程序文件内 local；工具箱新增「稀有提醒」组 + 开关（Toolbox 的 `t="rw"` 行型）——★**读写走实现自己的单一来源** `EVAL_RW_ENABLED`/`EVAL_RW_SET`，不另存 `tb.rareWatch`（两处真值必然打架）；★工具箱模型 28 条 > 每页容量 26 ⇒ **第 2 页**，判据必须翻页后取控件（`EVAL_TB_TEST_SCROLL_CLICK("dn")` + 新读值口 `EVAL_TEST_TB_CHK_FOR`）；★**新增文件要同步 7 处清单**：toc / 测试载入清单 / DECL ORDER / LANG KEY / COMMENT SWALLOW / WHEEL / COLOR CODE LEN / FRAME NAME CLASH（漏一处就是「新文件永远不被检查」的静默盲区），打包基准 68 → 69；`RARE WATCH WIRING CHECK` 改成**分两段扫**（接线点看主文件、实现模式看两份并集）。判据 = 组 120⑥ + 组 199。
- ★`TargetByName`：**官方 API 索引里有**（category=Targetting），且**不是 Protected**（参考卷 §F3:138 逐条核过）；但它在「附近没有这只」时**静默失败**（官方文档明文「只认附近单位」，`Engine.lua:735-736` 早已记过）⇒ **必须核对结果**：调用后读一次 `UnitName("target")`（否则「点了没反应」会被报成成功）。★对方 RareAlert **明确不做**这件事（自动扫描会抢玩家目标，RareAlert.lua:23-27 有明文），我们只在**玩家主动点一下**时做。
- ★★★**1.74.25 实锤（用户截图，这是本条最重要的事实）**：截图上任务插件导航箭头显示那只稀有在 **556 码**外，而我们写的文案是「它没刷 / 它不在这儿」→ **真因是客户端限制**：`TargetByName` **只认客户端附近的单位**，远处**静默失败**（官方文档 `Targetting#targetbyname` 明文；本项目 `Engine.lua:735-736`、参考卷 §F3 早已记过；参考卷 §F3:138 还确认它**不是** Protected —— 所以「切不到」≠「调用非法」）。
- ★★教训 = **「把自己的限制说成对方/世界的状态」是造谣**：`选不到「X」` 必须**同时报出距离**（`约 N 码`，取转播时对方给的那个数）+ 给出下一步（走近再点 / 右键地图定位），并且**一句话说完**（上一版太长，被聊天框折成两行 —— 截图可见）。反向哨兵：文案里绝不许再出现「它没刷」。
- ★取证命令 `/eh go 稀有 目标探针`：拿**当前目标自己的名字**（必然存在且必然在附近）——先 `ClearTarget()` 再按名字选回来，报 4 步判定。**这是唯一能区分**「客户端只认附近」与「TargetByName 对本插件是空操作」的实验（两者从结果上长得一模一样）；顺带打印库里那份名字与**字节数**，排掉「库名 ≠ 客户端名」这第三种可能。判据 = 组 199⑫（含「它没刷」反向哨兵 + 距离必须出现）与 ⑯。
- ★链接的失败模式是「**整条不画**」⇒ 留了 `稀有 链接` 开关，一键退回**已验证的「只有色码」形态**；命令 `/eh go 稀有 目标|链接|目标探针`；判据 = 组 199⑩~⑯ + `RARE WATCH WIRING CHECK`（4 色逐项 8 位 · 链接**只带名字** · Toolbox 的 `EHRW:` 分派**必须以该语句开头** —— 只查「文件里出现过这串」会被 `if false and …` 骗过，本轮变异测当场撞到 · **反向守**不许再耦合地图机制）。

### R5. 队伍菜单三条条件定案经过（1.74.1 / 1.74.4）

- ★★★队伍菜单三条条件（1.74.1，审计定案）：**邀请队伍** = 不在队伍 或 我是队长（修「队长反而邀不了人」的旧 bug）；
- ★1.74.4 邀请队伍再补一刀（用户截图：对方已入队却仍显示邀请队伍）：条件只看「我」的状态是 bug → 改为「**对方不在我队伍/团队里 且 （不在队伍 或 我是队长）**」；队友已入队 → 邀请藏掉（踢出/离开照常）。组 130⑥e2 反转；变异 M568。
  **踢出队伍** = 我是队长 且 被右键的是队友（非队长根本不出现这条，不再是「点了才说不是队长」）；**离开队伍** = 在队伍内显示
  （退队不需权限，与右键的人无关，动作 `LeaveParty()`）。判队长 = `IsPartyLeader()` 或 `IsRaidLeader()`；★助理踢人没有
  `IsRaidAssistant` 接口可判 → 如实接受边界（助理看不到这条，动作里仍有「不是队长」兜底）。成员判定 = `EVAL_TB_NAME_INMYGROUP`
  （UnitInParty/UnitInRaid 反查，party 只扫 1..4）。组 130⑥e/⑥e2/⑥e3 + 组 173 + ⑤b；变异 M564~M567 捕获。

### R6. 铁律 1 / 铁律 2 的代价全案

- **1.9.0 语法事故**：两处 `local function` 误用 `end)` 收尾（多一个右括号），导致 **1.9.0~1.11.0 全部功能实际未生效**；旧的 balance 脚本（数 function/end 配对）**拦不住多余符号**，只能当辅助。
- **铁律 2 的两次代价（都是绕了远路）**：**1.70.17** 自己发明用 `IsShown` 判地图可见性，而对方 `ClientAPI.lua:8664` 早写明这 API 在本客户端**不可靠** → 引入回归；**1.70.39** tick 挂 `UIParent` 导致开图时 OnUpdate 停摆，而对方 `Driver.lua:467-482` 把机理和正确做法全写在注释里——用日志推断**五轮**没找到，**用户一句「可以查看任务插件…」当场破案**。

### R7. 铁律 5 首案（频道进出屏蔽返工三次）

- 频道进出屏蔽返工三次（文本判据 → 官方消息组 → 事件名判据），最后靠核 API 调用 + 探针才定案；而那次「Channel is missing!」报错，核完 API 后确认**插件根本没拿 CHANNEL 发过消息**、错在客户端的频道成员状态 —— 不是插件把 API 调用写错。

### R8. 分享分片限频根因全案（1.72.3）

- ★★★1.72.3 **分享分片必须限频发送**（用户实测：「长方案对方有时候接收不到」，短方案 1 片从不出问题）。
  【根因】`Share.lua` 原实现在一个 for 循环里**连着 `RunScript('SendChatMessage(...)')`** 把 N 片一次发完
  （同一帧 N 条聊天）→ 撞反刷屏限流被吞一片 → 接收端**永远收不齐**（而收不齐当时还是静默丢弃，见常驻卷 §5.2）。
  ★这正是频率防护总则早就写明的铁律的又一次违反：「**RunScript 本身也是队列，连发聊天同样会被反滥用踢线**，通知类输出也要入限频队列」。
  【修法】第 1 片立即发（手感不变），其余进 FIFO 由 OnUpdate 每 `SH_SEND_RATE=0.5s` 滴一片（**2 条/秒**，给服务器留余量），
  队列上限 `SH_MAX_QUEUE=200`（超出如实取消）；★**绝不在瞬间倾泻大量文字**（用户明确：不然服务器被触发预警）。
  ★判据 = 断言组 106（只准立即发 1 片 + 同刻 tick 也抽不干 + 分时发完）；变异 M7（退回一帧全发）→ 当场 got=9 want=1。

### R9. §5.2 被合并条目的原文（1.73.39~1.73.40 族）

- 1.73.39「加个边框」也要读顶点色：四条 1px 纹理（BORDER 层）`tbSolid(1,1,1,0.75)`；判据 = 四条 + 顶点色 ≥0.9 + 跨满窗宽高。
- 1.73.39「A ↔ B 对调位置」= 改数据顺序不是改坐标；判据直接读渲染出的条目文字，别比 x/y。
- 1.73.40「圆角」只能来自原生边贴图：`SetBackdrop` + `edgeFile = UI-Tooltip-Border`（`edgeSize 16` 整数、`insets 4`）；判据 `MENU ROUND CHROME CHECK` + 两条路都验。
- 1.73.40「末行按钮吊在框外」= 高度公式漏算末行自身高度；正解 `h = -TOP + rows*行距 + PAD`；判据别用同一公式自证 → 独立包含性断言：每条按钮落在 `[0,W]×[-H,0]` 内。
- 1.73.40 悬停高亮走 `OnEnter`/`OnLeave` 改颜色（禁用 `SetHighlightTexture`）：底色/文字两处都改、离开逐值复原；判据读真控件 + 每条都挂了两个脚本。
- 1.73.40 计数必须由闸门守：「案例模版 11 组 N 条」散在 4 处（`.toc` + 三语 README）；判据 `TEMPLATE COUNT CHECK`。
- 1.73.40 样式需求会被下一轮推翻 → 断言跟着改方向：新判据 = ①悬停背景逐值没变 ②文字真变白；桩要能读回文字色。
- 1.73.40「框增加 padding」= 宽高/标题/条目位置全由同一组常量算：`TB_MENU_PAD`/`TB_MENU_TOP`；判据用独立阈值，不用生产常量自证。

### R10. 其它被精简表述的原文（4.1 / 4.2 / 5.4 等）

- 4.1 `seBtn` 条原文尾巴：「——1.21.4 修复 SE 技能名按钮把包裹表当按钮用（`uiText` 炸 CreateFontString、SE_BUILD 半成品窗口）」。
- 4.1 local 作用域条原文尾巴：「——1.21.4 修复激活方案下拉（`DD_OPEN` anchorBtn nil）」。
- 4.1 EditBox 条原文：「（1.15.1 用户报告 IO 窗口空白：`pcall` 全「成功」但什么都不可见）→ IO 窗加 FontString 保底预览区（`EVAL_HELP_IO_REFRESH`）；EditBox 字体链先试 `SetFontObject(GameFontHighlightSmall/ChatFontNormal/GameFontNormal)`；**文本类 UI 一律给 FontString 保底**；单行输入弹窗用**回声行**保底（`OnTextChanged` 镜像到 FontString，1.17.0 重命名弹窗 `EVAL_HELP_RP_*` 范式）。」
- 4.2 手写转义全案（1.73.28）：想写「引号 + 反斜杠」时手写 `"` / `\\` 极易写坏（实测把 `string.gsub(name, "[\"\\\\]", "")` 写成了 `"["\]"`）→ 而且 **luacheck 当时只查主文件、照样报 SYNTAX OK**，直到运行时 load 才炸（LOAD ERROR ... expected ')' near backslash）。正解 = 用 `string.char(34)` / `string.char(92)` 构造这类字符，抽成一个小函数（`tbSafeName`）复用；★同时把 `luacheck.js` 改成**逐个文件**检查（当时 27 个 .lua），语法错误再也漏不过去。
- 4.3 配置窗 Tab② 原文：「1.20.0 起底部的图标选择器/条件输入框/`EVAL_WAR_ADD_FROM_UI` 已删除，**新增技能走编辑窗**」。
- 5.4 分享弹窗坐标原文：「坐标 `SH_SEAL_ROW_Y` -50→-46·`SH_DETAIL_Y1` -74→-66·dPanel 顶 -46→-42」。
- 5.4 可点品阶色链接原文补充：「（`|HEHPF:<id>` 形态，封皮 B 行与场景描述头衔同款）；超 `SH_MSG_MAX`/缺 id ⇒ 退回纯文本」。
- 5.4 品阶显示条原文：「★纯黑＝`EVAL_SHARE_SEAL_ICON` 两返回值内联进 `pcall(t.SetTexture,…)`⇒多返回值禁内联进可变参数调用」。

### R11. §5.2 的 1.73.24~1.73.41 弹窗/菜单细则条目（整批迁入）

> 这些条目判据仍然有效，只是年代较早、引用频率低；常驻卷只留高频条目。

- 右键菜单（1.73.24）：有 `GuildInviteByName`/`CanGuildInvite`；无剪贴板接口、无 `UIDropDownMenu`；`SetItemRef` 可写 → 包它 + 读回确认 + 幂等，只认 `player:` 右键；`/s` 走 `RunScript` + 0.5s 去抖；组 130。
- 资源名必须显示时现算（1.73.27）：`UnitPowerType` 0 法力/1 怒气/2 集中值/3 能量、随形态变 → 写死在表（`COND_NUMNAME.powerPct`）即错；显示名一律 `EVAL_POWERLABEL()`、四处同源；改显示名＝改导出文本 → 解析侧同时认新写法；组 132。
- 「填进输入框」≠「替用户发送」（1.73.29）：只预填不回车、不碰 `SendChatMessage`/`RunScript`；判据双向：内容对 + 一个字都没发；共用 `tbMenuPrefill`。
- 标题栏宽度自适应（1.73.30）= 纯函数拼分隔条：`EVAL_TB_HDR_TEXT(标题,列宽)` 剥装饰后按列宽补破折号；读值口 `EVAL_TEST_TB_HDR_TEXT` 读真控件、逐字相同；「—」三字节 → 绝不写 `[—]`。
- 弹窗规程（1.73.31~36）：层级全 `DIALOG`（10~250 八级，`EVAL_TN` 220、`EVAL_DD_OPEN` 250 最高）；①子弹窗层级必须高于父弹窗；②只设 strata 没设 frame level = 点击不到 → `SetFrameLevel(root,200)` + `EnableMouse(true)`；③可拖拽 = Button 柄 + 三件套 + level=窗口+1 + warm-up；④布局跟窗宽走、不写死 x、文案由调用方给；⑤位置按字面拆 = 左下角贴光标 + 坐标除缩放。
- 布局异常（1.73.33）：①锚点偏移算错（距右边误填距左边的数 → 列头叠画）→ 列几何单一来源（全用「距左边」、列头宽度 = 本列宽度）；判据 = 列头右边缘 == 该列数据右边缘 + 列头互不重叠；②能不能拖先问「有没有柄」。
- 滚动条规范（1.73.34）：①滚轮要显式 `EnableMouseWheel(true)` + `SetScript("OnMouseWheel")`，方向单一来源 `EVAL_WHEEL_DIR(a,b)`；②`off` 双侧夹；③到顶/底、空列表藏箭头；④▲▼不许压数据列 → 专用滚动槽；⑤页码必须整数、末页特判；⑥箭头与指示同一口径。★1.74.30 起升级为「连续窗口」（页码/末页改为行偏移/窗口，见常驻卷 §5.4 滚动模式唯一标准）。
- 右键菜单条件门 + 名字→unit（1.73.35）：①条目出不出现由 `CanGuildRemove()`/`CanGuildInvite()`/`GetNumPartyMembers()>0` 在建菜单时决定；②名字→unit 只扫本机看得到的单位，解析不到如实退回；③查询不许直调 `SendWho` → 走 `EVAL_TB_WHO_ENQUEUE`；④两列 + 宽高由条目数算（`EVAL_TB_MENU_LAYOUT`）。
- 聊天提示搬进弹窗 = 判据跟着落点走（1.73.35）：判据改到弹窗正文 + 「知道了 → `cfg.loadMsgSeen=true` → `EVAL_LOADPOP_SHOW()` 返 false」；按钮判据走真实 `GetScript("OnClick")`。
- 「点了没反应」两根因（1.73.37）：①闭包捕获建菜单那一刻的名字快照（首次右键 nil）→ 名字先写再建 + 闭包改点击时才读；②「关闭」传空函数。判据必须走真实 `OnClick` → `EVAL_TEST_TB_MENU_CLICK(标签)`；测试先用 `EVAL_TEST_TB_MENU_DROP()`；冗余守卫要整组拆。
- 「接收方要支持私聊」（1.73.38）：接收帧本来就注册 `CHAT_MSG_WHISPER`；`IsEventRegistered("CHAT_MSG_WHISPER")` + 用真实路径 `EVAL_SHARE_ONMSG(msg,sender,"CHAT_MSG_WHISPER")` 喂密语分片。
- tooltip 也要列全 + 分层（1.73.38）：金色标题 + 每功能一行 + 灰色注意行，用 `\n` 在一条 `AddLine` 里分行；判据 = 逐个功能名都出现 + 含颜色码 + 含换行。
- 同一内容不要两处各写（1.73.41）：入口全走 `EVAL_HELP_GUIDE`，内部优先 `EVAL_LOADPOP_SHOW`、弹窗不可用才退回聊天打印；判据让 force 承重：`cfg.loadMsgSeen=true` 再点「使用引导」仍必须弹。

### R12. §5.4 的布局细则条目（整批迁入）

> 同样是「判据有效但引用频率低」的一批；常驻卷 §5.4 只留 ★★★ 级与用户点名的判据。

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

### R13. 关键源码检查在守什么（1.74.32 从常驻卷 §5.10 迁入）

> 从常驻卷迁出的原因：这份「一句话清单」与 `test_engine.js` 里的实现**同源**，真正要查全清单时直接看 `test_engine.js` 更快；
> 常驻卷只留一行指针。★判据本身仍然有效（每道检查都做过变异验证）。

- `FRAME NAME CLASH`（具名帧撞全局函数）· `WTT ISOLATION`（禁借 GameTooltip，★扫描前摘注释）· `CHAT COLOR WIRING`（读回确认 + 幂等守卫）· `COLOR CODE LEN`（色码 8 位 + 禁 `"|c"..string.sub(`）· `SHARE MSG SHAPE` / `SHARE PALETTE`（分享形态 / 色表）· `MENU ROUND CHROME`（圆角边贴图）· `TEMPLATE COUNT` · `WHEEL DIRECTION` · `SHARE RECV EVENTS`（接收帧七事件全注册）· `UI CELL MOUSE`（左右键分派）· `DF BARS WIRING CHECK`（候选名解析接线，1.74.31）· `DF ROSTER WIRING CHECK`（队伍/团队「按需出现」的事件跟随接线，1.74.32）。
- 其余：`EXAMPLES TOC` · `STOP ATTACK WIRING` · `PET ICON` · `LANG KEY` · `DECL ORDER` · `PAINT WIRING` · `DEBUFF DISPLAY` · `CREATOR GATE` · `SH FUN` · `PROF ICON PROBE WIRING` · `UI TITLE BADGES`/`UI TIER BADGE`/`UI TITLEBAR`/`UI TITLE NAME`。

### R14. §5.4 的分享弹窗与彩蛋条目（1.74.32 迁入）

> 迁出原因：这 4 条判据**仍然有效**，但引用频率低（彩蛋两条自 1.74.5 起就没接线）；
> 常驻卷只留一行指针，需要时回到这里读原文。

- ★分享弹窗：摘要行⇒「X 分享的 [品阶秘籍·名]」带品阶色；品阶行只留图标、删重复文字（`EVAL_SHARE_SEAL_ROW` 被组 145 等用）；组 145；★改 UI 文案要同步反转旧判据。
- ★可点品阶色链接（`|HEHPF:<id>` 形态）：点它靠 `EVAL_SHARE_CLICK_OPEN("EHPF:<id>")` 在 `SH.recent` 找（用 `SH.pending.idh`）⇒ 重填 `SH.pending` 弹出接收页；超 `SH_MSG_MAX`/缺 id ⇒ 退回纯文本；`shReactionNameLink(p)` **保留但未接线**（彩蛋取消）；判据组 180②。
- ★彩蛋角色扮演反应（1.73.64 建 · **1.74.5 起未接线**）：机制与三语言 50 格文案**全部保留**、只是 [导入]/[忽略] 不再发（改发「场景描述」）；`SH FUN CHECK` 钉「机制都在 **且** 调用点未接」＋组 82④⑤ 反向哨兵。
- ★彩蛋创世者亲临闸门：手动方案有**神级**（封顶后 ≥50，`EVAL_SEAL_GOD_SCORE()` 现算）· 手动 **≥3 个** · 头衔满档 5；`src`：手工 `"manual"` / 文本解析唯一出口 `EVAL_PROFILE_FROM_TEXT` 盖 `"text"` / 老存档无 `src`⇒按手动；堵 `EVAL_TITLE_CREATOR_OPEN`/`EVAL_TITLE_CREATOR_TRY` 两条路；`EVAL_TITLE_EGG_CHECK()` 挂 `EVAL_WAR_TAB_REFRESH`＋登录、只播一次；组 169/150＋`CREATOR GATE CHECK`。

### R15. 真机窗口帧名实测清单 + 客户端取证踩坑全案（1.74.32~1.75.7 · 压缩版）

> ★这批**真机一次探针跑出来的事实**（`/eh go 框体探针` → 落存档 `EVAL_HELP_CONFIG.dragBars` → 外部读），不是查文档也不是猜。**下次要动「别人的窗口」，先看这里，别重新探一遍。** ⑥* 各块的完整叙事见 `CHANGELOG.md` 与 git log。

**① 被动打开窗口的真名（探针实测，全部存在）**
- 尺寸统一 **384×512 / lv=1**（打开的窗口 lv 会变高，实测 `CharacterFrame` 打开时 lv=8）：
  `GuildFrame`(公会) · `CharacterFrame`(属性) · `MailFrame`+`InboxFrame`+`OpenMailFrame`(邮箱) · `QuestFrame`(任务对话) · `SpellBookFrame`(技能树) · `TradeFrame`(交易技能) · `MerchantFrame`(商人) · `FriendsFrame`+`FriendsListFrame`(好友) · `BankFrame` · `BattlefieldFrame` · `DressUpFrame` · `GossipFrame` · `GuildRegistrarFrame` · `ItemTextFrame` · `LFTFrame` · `PetStableFrame` · `PetitionFrame` · `TabardFrame` · `TaxiFrame` · **`ClassTrainerFrame`（训练师 —— `TrainerFrame` 这个名字**不存在**，靠候选表第二个名字才探到）**。
- 其它规格：`QuestLogFrame` 704×512 · `HelpFrame` 640×512 · `ShopFrame` 700×460 · `SoundOptionsFrame` 400×570 · `WorldStateScoreFrame` 640×512 · `LootFrame`/`ContainerFrame1..12` 256×256 · `OneBankFrame` 400×400。
- 子弹窗（**不是**主窗口，别当目标）：`GuildControlPopupFrame` 297×298 · `LFTGroupReadyFrame` 308×220 · `StationeryPopupFrame` 220×298 · `LFTGroupReadyStatusFrame` 360×152 · `LFTRoleCheckFrame` 250×200。
- ★**队伍没有整队容器**：`PartyFrame`/`PartyMemberFrameContainer`/`PartyFrameContainer`/`PartyContainer` **全不在**，只有 `PartyMemberFrame1~4` ⇒ 目标表拆成「队伍成员1~4」（用户 1.74.32 定）。
- 满屏（`1228.8×768` = UIParent 尺寸）的全是**事件帧/遮罩**不是窗口：`EVAL_*`、`UnrealQuest*`、`AceEvent20Frame`、`CinematicFrame`、`WorldMapBlackout`、`UIOptionsFrame`、`SoundOptionsFrame`、`StatsFrame`。
- ★**仍未探到：拍卖行**（`AuctionFrame`/`AuctionHouseFrame`/`AuctionFrameContainer` 全不在、关键词命中 0），但客户端确实在跑 `Blizzard_AuctionUI` ⇒ 最可能是**匿名窗口** ⇒ 只能靠父子链 + 具名子件指纹取证。

**② 客户端取证踩坑全案（每条都真金白银踩过）**
1. **真机 SavedVariables 带 UTF-8 BOM**（`EF BB BF`）⇒ 直接丢给 Lua 报 `unexpected symbol near '<\239>'` ⇒ **读之前先剥 BOM**。
2. **`_G` 里有不可索引的 userdata** ⇒ 一句 `f.GetParent` 就抛错并**打断整个探针**（报错行看起来与帧名无关）⇒ 索引前先 `dfFrameUsable`（pcall 探测 + 只放 table/userdata）。
3. **`_G` 里同名子件成千上万**（光 `ActionButton*` 的贴图/文字/冷却圈就 2900+）⇒ 必须按 `GetObjectType()=="Frame"` 过滤；★判不出类型时**不许丢**。
4. **匿名窗口 `_G` 扫描永远看不到** ⇒ 走 `GetChildren()` 父子链两层 + **具名子件当身份指纹**。
5. **`GetChildren()` 返回多值不是表** ⇒ 必须 `{ pcall(fr.GetChildren, fr) }`；写成 `local kids = fr:GetChildren()` 只拿到**第一个**子件（静默少数据）。
6. **父级「名字」不可靠**（`GetName()` 可能 nil）⇒ 判「宿主是谁」一律**比对象身份**（`p == rawget(_G,"UIParent")`）。
7. **桩不保真三连**：桩原本没有 `GetChildren`（宽容兜底 ⇒ 父子链永远空）· fengari 是 Lua 5.3 **没有全局 `unpack`** · `UIParent` 在桩里无名 ⇒ 全按「桩保真」补齐。
8. **Lua 的 `a and f()` 只保留第一个返回值** ⇒ `local p, _, rel = btn and btn:GetPoint(1)` 后两个恒 nil（组 212⑤ 误报过）；多值必须**先判后取**。
9. **`/eh go` 别名撞车是静默的**（`go icons` 曾被 elseif 链先命中的旧命令顶掉）⇒ `GO ALIAS UNIQUE CHECK`（按**缩进**识别分派链）。
10. **取证命令绝不许静默**：裸 `pcall(探针)` 会把错误吞掉 ⇒ 真机表现「跑了命令、聊天框空的、存档连键都没有」，无法区分「没跑到」与「跑一半死了」⇒ 三态阶段标记（`start`/`done`/`error` + 错误原文落档）+ 命令先回显「命令已收到」。
11. **拖拽机制会吃掉点击**：`dfDragBegin` 一 Show 全屏接盘（level 800）⇒ 图标的 `OnClick` **永远收不到**松手 ⇒ 在 `dfDragEnd` 里判「按下了但没移动」（`st.moved` 是拖拽机制自己算的阈值，唯一真值）来决定是否开属性弹窗。
12. **「像窗口」的判据要宽高都够大**：只用一维（`w>=200 or h>=200`）会被 400×120 条状件占满，真窗口反被上限挤掉。

**③ 名字着色族（1.73.18~51 · 原文照存）**
- 名字在 `arg2`；名字槽不吃富文本 ⇒ 吞行自拼；色码必须 8 位 ⇒ `COLOR CODE LEN CHECK`；缓存唯一 = 名字→职业 token（`tbNameClassPut`）；四来源 = 白拿/`EVAL_TB_NAMECLASS_HARVEST(kind)`//who/事件；名册懒加载（`GetNumGuildMembers()` 恒 0）→ 自愈 `EVAL_TB_NAMECLASS_HEAL()` + 一发 `GuildRoster()`；`TB_NAMECOLOR_WRITE=false`；组 129b/161 + `NAME CACHE PROBE WIRING CHECK`。

**④ 图层树折叠 / 层深（1.74.33 · 原文照存）**
- ★★★**层级只能来自「扫描时写下的层号」，不许数路径里的 `/`**：`scanTree` 递归写 `d = depth + 1` 进节点、`uiBuildEntries` 带进条目 ⇒ 缩进与「层深」过滤**同一口径**（理由：路径形态不一 · 同帧多区域同名不唯一 · 过滤藏中间层会让父子漂移）。
- 【父子】`uiTreePass`：DFS 前序 + 未闭合祖先栈，层号 ≤ 栈顶就弹；`uiFiltered` 懒补算；折叠 `ui.treeCollapsed[路径]` 落存档（读回只收「值为真 + 键是字符串」）。
- 【三态别混】行上 `▶/▼` 三来源：① 折叠 ② 层深上限卡住本层 ③ 子层被别的过滤藏了（`e.visKid` 记账）⇒ 只有 `(e.kids or 0) > 0` 且（已折叠/被卡住/有可见子层）才画开关，叶子不画。
- 【层深 = 展开到第 N 层】唯一写入点 `uiDepthApply`；`0`（全部）**一个标记都不清**；点 ▶ 在「被卡住」时 = 上限抬到本层+1。判据 = `DBX TREE WIRING CHECK` + **组 205**；字形 `UI_TREE_OPEN=▼`/`UI_TREE_SHUT=▶`（`▸` 未验证）。

**⑤ 只读取证要用哨兵钉住（1.74.33 · 原文照存）**
- ★★**声明「本次只取证 / 只搬代码 / 只接线，行为零变化」时，必须用哨兵把它钉住**（例：被动窗口候选挂成独立清单 `DF_WIN_CANDS` 喂探针、**不进** `DF_TARGETS`，源码检查加「候选与 `DF_TARGETS` 零交集 + 目标数 == 12」两条哨兵）。理由：不小心接进去**不报错**，只是这些窗口突然被贴上整条透明柄；这类改动的错法恰恰是「悄悄多做了」。

**⑥a 「图层选择」多选下拉全案（1.74.33 用户：「拖拽图层右侧添加设置弹窗支持这么多种类的支持多选的下拉选择，选中的才开启配置和支持拖拽」）**
- **需求**：工具箱 → 拖拽图层行右侧 `[设置]` 弹一个**多选下拉**（38 个目标分三组：① 框体柄 1~10 ② 队伍/团队 11~15 ③ 图标形态窗口 16~38），**勾上的才贴柄/挂图标/应用存档属性/可拖**。
- **真值**：`EVAL_HELP_CONFIG.dragFrames.pick[目标名] = true`；★**表不存在 = 全选**（老存档升级后行为必须与升级前一致）；唯一写入口 `EVAL_DF_PICK_SET(name, on)`。
- ★★**第一次写必须先把「全选」快照物化进表**：老存档里 `pick` 不存在 ⇒ 用户取消勾一个，如果只写 `pick[name]=false`，其余几十层因「表里没键」全部变成未选中（**静默关掉几十个拖拽**，用户以为插件坏了）。物化 = 写之前先按 `DF_TARGETS` 把全部目标填成 true，再改这一项。
- **七条路径都要过 `dfPicked(name)`**：贴柄 `dfRefresh` · 挂图标 `dfIconsRefresh` · 应用存档 `dfApplyAll`/`dfKeepTick`/`dfApplyOne` · 事件结算 `dfRosterPass` · 清理 `EVAL_DF_RESET`。★未勾选的层**记录与属性都不动**（不重锚、不改宽高、不重置），并在播报里**如实报数**（不许假装全都处理了）。
- **判据**：组 214（名单/分组/物化快照/七条路径逐条）+ `DF PICK WIRING CHECK`（真值 + 物化 + 七处 `dfPicked` 门 + 工具箱槽位几何 + 无重复目标表）；变异 M1~M17（含「摘掉图标那道门」「换回 chv 槽」）全捕获。

**⑥ 同一条带上的两个控件 = 遮挡（1.74.33 真机 + 源码双重踩坑全案）**
- **真机侧**：被动窗口的「配」图标原本锚 `TOPRIGHT`、偏移 `-34`（注释写着「要大于关闭按钮宽度」）⇒ 用户截图：**法术书的关闭按钮被「配」压住**（红圈里两个控件叠在一起）。修法 = 右边距抬到 **58**（按关闭按钮 40px 带宽 + 18px 间隙算），图标横跨 `[W−78, W−58]`。判据 = 组 212⑤b（**验性质**：图标右边距 ≥40px，不写死 58）。
- **工具箱侧**：图层拖拽行要放**两个**按钮 ⇒ `[设置]` 用 `r.add`（cRight−96 宽 44）、`[重置]` 原本还在 `r.chv`（**同起点、宽 88**）⇒ 后建的 chv 压在上面，`[设置]` **永远点不到**；而「按钮存在 + OnClick 已挂上」的断言**全绿**（第一版就是这样漏过去的）。修法 = `[重置]` 改挂 `r.clr`（cRight−48 宽 40），两块并排留 4px 缝。
- **两类判据都要有**：① 行为侧 = `EVAL_TB_TEST_ROW_BTNS(key)` 读两个控件的几何，断言 `[设置]右边界 ≤ [重置]左边`；② 源码侧 = `DF PICK WIRING CHECK` 的几何哨兵（lddrag 分支必须 `r.clr.btn:Show()` 且**不许出现 `r.chv.btn`**）。变异 M16/M17（各自换回 chv 槽）都被断言捕获。
- ★**教训一般化**：**「控件建出来了」不等于「用户点得到」** —— 凡是同一行/同一角落放多个控件，或往别人的窗口上贴东西，都要问「它盖住谁 / 谁盖住它」，并把这条写成几何断言。真机截图是唯一能发现「压住原生按钮」的手段（`GetNumPoints`/`IsShown` 都看不出来）。

**⑥b 「头部拖拽带」（1.74.33 用户：「窗口拖拽的区域能否定位到 窗体头部红色部分?」）全案**
- **需求**：图标形态的窗口原来只有右上角 20×20 的小图标能拖；用户截图（任务窗口顶部红线）要求**整条标题栏都能抓**。
- **实现**：再建一条**透明 Button** 贴顶部（`dfHeadBuild`）——`TOPLEFT` 锚在 `(DF_HEAD_LEFT=4, -DF_HEAD_TOP=3)`、宽 = `窗口宽 − DF_HEAD_LEFT − DF_ICON_RIGHT − DF_ICON_SIZE`、**高 `DF_HEAD_H`（1.74.33 用户追加「向下再延伸 15px」⇒ 18 → 33，上沿不动只向下长）**；鼠标分工与图标**共用** `dfBindDragButton`（左键拖窗口 / 右键开属性窗 / 悬停出说明）。
  ★**高度改数字不会卡判据**：组 215① 只验**性质**（控件真实高度落在 10~48 这一档），不钉死 18/33；要按窗口单独调矮时改这一处即可。
- ★★**两项都要减**（这是本轮第二次同类事故）：只减「关闭按钮留空区」时，带的右端正好落在**图标右边界**上 ⇒ 带把图标整块盖住、**右键点不到图标**；组 215③ 的几何断言当场抓到（带右端 326 > 图标左边界 306）。
- ★★**读值口必须现读控件几何**：组 215 第一版的 `h` 直接回常量 `DF_HEAD_H` ⇒ 变异 M28（`SetHeight` 改成 200、带盖住整窗）**照样绿**——这是「写死布局常量＝测自己」的又一例。改成现读 `GetHeight()` 并**验性质**（≥10 且 ≤40：只许盖标题条那一带）后，M28 被捕获。

**⑥c 拖拽「位移叠加漂移」全案（1.74.33 用户：「窗口拖拽有些会有位移叠加漂移，比如角色等其他测试。你拍下什么问题」）**
- **现象**：缩放 ≠ 1 的窗口（角色/法术书……）**每拖一次就多漂一个固定量**（越拖越偏），而且**第一次拖拽就比光标跑得远**；缩放 = 1 的窗口完全正常 —— 所以只有「有些窗口」。
- **真因（三层，缺一层都修不对）**：
  2. 那个偏移是**从几何反算**的（不是 `GetPoint` 原值），与 `SetPoint` 要的偏移差一个**常数**（单位口径 + 锚点系数叠加）⇒ 「按实测系数 k 反解」（`偏移 = 位移 / k`）**解不掉**：它假设响应过原点，实际是 `屏幕 = 常数 + 折算 × 偏移`。★第一版就栽在这里：单次拖拽对（40→40）、**连续三次仍叠加**（90→118.9）。
- **修法（口径与单位无关，不猜文档）**：
- **判据**：组 217（①单次 40px 1:1 ②k ≈ 0.8 ③播报 ④**连续三次各 30px 总位移 = 90**（旧口径 ~118+）⑤纵向 1:1 ⑥「应用存档」回同一屏幕位置 ⑦拖到一半改尺寸仍记 20px 而不是 68）；桩里按真机语义造 1024×768 屏 + 缩放 0.8 的窗口（**UIParent 左下角故意不在 0**，否则单位错会被抹平）；变异 `tmp/mut_drift.js` **6/6**（M35 去掉量回自证→④ · M36 结算退回锚点相减→⑦ · M37 不记屏幕基准→② · M38 去掉修正循环→④ · M39 播报不报系数→③ · M40 `dfIsAt` 永远 true→组204）。

**⑥d 开窗探针：被动窗口「打开时重设属性」的可行性取证（1.74.33，用户提问待确认）**
- **用户问题（原话）**：「图层拖拽->被动类窗口能否在打开的时候进行自定义属性重设.或者定时重设? 验证可行性 待我确认」
- **为什么这不是「顺手加个 tick」**：被动窗口（公会/属性/技能树/任务…共 23 个 `icon = true` 目标）的**自定义属性**
- ★**先取证再动代码**（铁律 4/5）：判断「要不要做」需要真机证据，而不是猜；`/eh go 开窗探针` 就是那件取证工具。
     （判据 = 组 218①：把夹具的 `SetWidth/SetHeight/SetScale/SetAlpha/Show/Hide` 全包计数 ⇒ 必须为 **0**；
     变异 M41「偷偷写一次 SetWidth」当场报红）。

**⑥e 被动窗口「不许改宽高」+ 开窗重设 A/C 全案（1.74.33 用户拍板）**
- **用户的硬约束（原话 + 截图）**：「被动类型窗口不能设置宽度.会破坏内部布局.不能同时设置缩放和宽度.UI 会撕裂」
  —— 截图是**法术书**：左边技能列表被撑成一大块、右边那条页签被挤成一条细缝，两边各画各的。
  ① **属性弹窗**：五行改成**带 key** 的行（`p.rowBy`；★不再按下标读值 —— 藏了行之后下标必然错位，那是「静默改错属性」的经典入口），
  ★★**踩过的坑**：`dfCommitPop(target, ...)` 传进来的 `target` 是**帧**（`dfDragEnd`/图标点击都传 `b.dfTarget`），
     而 `noSize` 挂在**目标表项**上 ⇒ 第一版判不出来（组 220② 当场报红）。修法 = 新增 `dfTgtOfName(name)` 按名字回查目标表，弹窗与保存两侧都复用。

**⑥f 从常驻卷迁入的「物品类型过滤」细则全文（1.74.33 迁入，为被动窗口约束腾预算）**
- ★★★**两个助手的弹窗候选按物品类型过滤**（1.74.28）：判定收在**共用件 `EVAL_IG_ITEM_KIND`**（tools/IconGrid.lua），**三级**按「便宜→贵」早停 ——
  ① **品质**（`GetContainerItemInfo` 第 5 返回，不依赖缓存）⇒ 灰色一律剔；② **`GetItemInfo`**：传参**先用物品链接**（客户端缓存键），nil 再退名字；读第 5/6/8 返回 = 主/子类型/**装备槽**（装备槽非空 ⇒ 算护甲）；③ 缓存为 nil ⇒ **自建隐形 tooltip** `EVAL_HELP_WTT` + 守卫 `EVAL_WTT_MAY_READ` + **`SetBagItem`** 读类型行 —— 这步会**把物品写进客户端缓存** = **自愈**。
  ★**剔除表** `IG_KIND_DROP`：武器/护甲/灰色/**材料**/任务/容器/箭矢弹药/钥匙/配方；★**判不出就不剔**（查不到 ≠ 没有）+ 计入 `EVAL_IG_KIND_STATS().unknown` 如实报。
  ★★**过滤只在「弹窗候选」路径开**（`EVAL_IG_SCAN_BAGS(bags,{classify=true})`）——按名字解析包格那条路（`EVAL_CH_FIND`/`EVAL_HH_FIND_FOOD`）**绝不过滤**（判错一类 = 用户已配置的物品静默找不到）。
  ★★**tooltip 只读 TextLeft2 起**（跳过 TextLeft1 = 物品名，名字可能含类型词会污染判定）；词表 `IG_KIND_WORDS` 按真机实测文案维护。

**⑦ 从常驻卷迁入的「品阶显示」原文（1.74.33 迁入，为图层选择腾预算）**
- ★★品阶显示现算（不硬编品阶）：文字＝品阶色、底色×（激活 0.45/否则 0.22）；组 160/167。图标＝IconSem 真纹理 13px；★`EVAL_SHARE_SEAL_ICON` 两返回值**禁内联进可变参数调用**（先收局部再 pcall——内联会丢第二个返回值）；`PROF ICON PROBE WIRING CHECK`；组 160⑥⑦。★重锚前 `ClearAllPoints`；文字框留富余（`TPL_TEXT_PAD=4`·组 91）。

**⑧ 从常驻卷迁入的两条零碎判据（1.74.33 迁入，为窗口图标口径腾预算）**
- ★**COND WEIGHT CHECK 的实战价值**：它上线当场抓到 `target`（「选取目标」，hidden 存量类型）**不在任何分组**里 ⇒ 新口径下会被按 0 分算、也不计覆盖（静默少算）。★「新增条件类型必须进组」由它兜底。
- ★★**`/eh go` 别名不许两家共用**（1.74.32）：`go icons` 早被组 116 占用 ⇒ elseif 链先命中的赢、那条命令被**静默顶掉**；`GO ALIAS UNIQUE CHECK` 守。

**⑥g 图层隐藏（1.75.x 前的旧名 =「图层特殊处理」/ Layer Fixes；内部名仍 LayerFix）全案（1.74.34 用户三连问）**
- **用户原话**：①「能否对固定的某个层内的最后2个纹理做特殊处理.比如隐藏这2个纹理」（配 EH_DebugBox 图层树截图：
  `MainMenuBarArtFrame` 的 #21/#22 两条 `纹理:Texture` 被红框圈出 = 动作条两端那两张狮鹫贴图）；
  `key`（= 存档键，★绝不用序号/显示名）· `group`（下拉分组号）· `kind`（现在只有 `hideTex`）·
  （★键字面量要出现在源码里，否则 `LANG KEY CHECK` 看不见；★现取才不会绑死加载期语言）。
- **真值** = `EVAL_HELP_CONFIG.dragFrames.fix[key] = true`；★**表不存在 = 一条都不选**（与 `pick` 的「不存在 = 全选」**相反**）：

**⑥g-2 抽成独立模块（1.74.34 第二轮，用户：「能否将以上功能提取到./tools 独立文件脚本管理.尽量少的在ToolBox文件内修改.只要加入嵌入点进行函数调用?」）**
- **落地形态**：新文件 `tools/LayerFix.lua`（约 35 KB，自包含）；`tools/DragFrames.lua` 里那一整段（14.6 KB）
  被**整段删除**（含前向声明 `local dfFixSync, dfFixTick`、`DF` 表里的 `fixState/fixApplied/fixRehide`、
- **判据全量改名**：`DF FIX WIRING CHECK` → **`LAYER FIX WIRING CHECK`**（改查 `tools/LayerFix.lua`），
- **★本轮踩到的两个新坑（都已落进判据）**：
  ① **「名字还在」不等于「那行能执行」**：变异 M9 把载入期那句改成 `if false then pcall(EVAL_LF_INSTALL) end` ——

**⑥g-3 「图层拖拽」那一行的界面接线也搬进模块（1.74.34 第三轮，用户：「审查下 图层拖拽的功能.在Toolbox.lua 内的代码修改.参考以上也进行./tools 的代码文件归类」）**
- **审查结论（先审后动）**：Toolbox 里属于这个功能的代码只有 **3 处**：① 模型行（`t = "lddrag"` + `ldReset/ldSet` 两个开关字段）；
  ② `elseif it.t == "lddrag" then … end` 分支（约 **128 行**：`[重置]` 的 tooltip/清单/OnClick、`[设置]` 的多选下拉代理、
  ★顺带确认：勾选框的 OnClick（`tbBuild` 里那段）是**点击时**才读 `row.get/row.set`，且**没有** `dbgDrag` 专用副作用分支
  （★**不写 `noChk`** ⇒ 主开关勾选框照旧；`key` 必须留 —— 读值口按 key 找行，丢了 `key` 断言会**静默跳过**）；
- **判据跟着搬**（三处源码检查）：

**⑥h 工具类归属规范 + Toolbox 剩余功能审查（1.74.34 第四轮，用户：「以上工具类的整理要加入项目记忆。尽量单独文件进行管理，在 Toolbox.lua 内只做开启/配置入口的引入」）**
- **规范（已入常驻卷 §4.1）**：工具功能一律 `./tools/<模块>.lua` **自包含**（真值 + **自己的存档子树** + 界面控件 + 读值口 + **自己的有界计时器**）；
  `Toolbox.lua` 里**只允许**「模型行数据 `t = "mod", mod = "<名>", key = "<键>"`」与「入口按钮（点了就调模块函数）」；
  判据 = 通用 **`TB MOD ROW CHECK`**（模块行必须有 `key` + `mod` 名字在 `tools/*.lua` 里有**同名登记** + Toolbox 不许出现模块内部件）
  「工具箱自身框架」或「某工具功能」。**判据不是「写在哪个文件」，而是「这函数是谁的知识」**：
  ★**每搬一个都要**：加 `.toc` + 8 处源码检查名单 + 模块行/入口 + 删旧代码 + **反向哨兵** + 跑该功能的既有断言组 + 一条新变异。

**⑥i 从常驻卷迁入的「可驱散负面类型多选」原文（1.74.34 迁入，为工具类规范腾预算）**
- 可驱散「负面类型」多选（1.73.2；**1.74.6 扩到自身/目标 debuff**）：`cd.dt` = nil / 单串 / 集合（**空集 = 任意**）；
  **求值一律走 `dispelMatch` 按类型过滤**（名字对上但类型不符 = **没有**）；

**⑥j 工具模块自带的测试三件套归模块自己管（1.74.34 落地全案）**
- **用户原话**：「test 相关的搬迁到对应工具类子文件内自身管理。」（承接同一轮的「工具类功能独立文件」规范）
- **落地形态（三件套各归其位）**：
  ★**为什么必须对账**：这类失效**全是静默的** —— 文件存在但没被加载，整组断言消失，套件**照样打印 ALL TESTS PASS**（本项目最恨的形态）。
  ③ **反向哨兵**：`tests/` 不许出现在 `EvalHelp.toc`（会被当插件模块载入）与发布打包行里（测试代码不随包发给用户）。
- **变异验证**（`tmp/mut_tests.js`，6/6 全捕获）：M1 加载器 `modTests.slice(0,0)` 静默跳过（**只有握手对账能抓**）· M2 末行握手注释掉 · M3 自造 `local eq` · M4 `tests/checks/` 多出一个没人 require 的文件 · M5 harness 里那行 require 被注释 · M6 `tests\tools\LayerFix.lua` 被列进 `.toc`。

**⑥k 从常驻卷迁入的「索引任意全局 / 父子链扫描」原文（1.74.34 迁入，为测试规范腾预算）**
- ★★★**索引「任意全局」/ 走父子链的扫描，动手前先看参考卷附录 R15**（1.74.32 真机栽过一整轮）：① 索引前先过守卫（**不可索引的 userdata** 会抛错、**打断整个探针**；只收 `GetObjectType()=="Frame"`）；② **匿名窗口 `_G` 扫描永远看不到** ⇒ 只能靠 `GetChildren()` 父子链 + **具名子件当指纹**；③ 真机存档**带 BOM**、`a and f()` **只保留第一个返回值**、桩里 `unpack` 在 fengari **不存在** —— 都表现为「静默取不到值」。判据 = `DF GLOBAL SCAN GUARD CHECK` + 组 209/211/213。

**⑥l 从常驻卷迁入的「滚动/翻页/分页标准做法」原文（1.74.34 迁入，同上）**
- ★★★滚动/翻页/分页标准做法：三段 `[计数]`←8px→`[按钮组]`←10px→`[关闭]`；文字按钮（`IB_PREV/IB_NEXT`、`TB_UP/TB_DN`）、不用 ▲▼；几何唯一源 `EVAL_HELP_CFG_BOTTOM()`（`midY/closeLeft/closeW/rowY/rowH`；拿不到按 `-(H-10-11)`/`W-12-64` 回退）；判据＝中线==关闭中线、按钮组右端 ≤ 关闭左−4、真实 OnClick 能滚；读值口 `EVAL_IB_TEST_BOTTOM()`（组 92）/`EVAL_TB_TEST_SCROLL()`（组 118）。

**⑥m 拖拽模块（DragFrames）代码归属排查 + 测试整块归类（1.74.34 全案·压缩）**
- 把 `DragFrames` 的界面/状态整块搬进 `tools/DragFrames.lua`，Toolbox 只留「模块行数据 + 入口按钮」；`TB MOD ROW CHECK` **留在 `test_engine.js`**（它是工具箱模块行的**框架契约**，服务所有工具模块，不属于某一个模块）。
- ★★★**`DF GROUP ROSTER CHECK` 四条**：① 组号集合必须与期望**完全一致**（多/少都 FAIL）；② 必须**升序**（顺序本身是契约）；③ 每组区间里必须**真的有 `eq(`**（「整组被删」「被掏空成只剩注释」都会当场变红）；④ 每组必须有 `print("GROUP <n> …: PASS")` 收尾行。★写这类「按组切段」的检查不能用「到下一个标记为止」（**最后一组会一路吃到文件尾的 `print("ALL TESTS PASS")`**）。

**⑥n 「缩放大地图」行的 [设置] 下拉 = GUI重开（1.74.35-3 全案·压缩）**
- 用户原话：「工具箱->缩放大地图右侧添加个设置 设置点击下拉->GUI重开 然后提示这个功能会有导致地图切换到其他地图后自动刷新到当前地图,,默认关闭.」⇒ 模块行 + `[设置]` 多选下拉（**默认关** + 提示必须写清：中文提示里同时有「自动刷新」与「当前所在地图」两句，**源码检查钉住这两句不许被删**）；顺手删掉认不出来的死分支 `elseif it.t == "smap"`（模型里从没有这种行且它走已废弃的子插件注册表）。判据 = **组 224** + `tests/tools/SimpleMap.lua` 自查。

**⑥o 工具箱那几行的「配置项」移进 tooltip + 检查文件死代码（1.74.36 全案·压缩）**
- 用户原话：「工具箱->以上UI工具的配置项.不需要再外部显示,已经在tooltip设置内显示了」⇒ `tools/SimpleMap.lua` 的 `smRow` 与 `tools/LayerFix.lua` 的 `lfRow` 去掉 `r.extra:SetText(...)+Show()`、改成显式 `r.extra:Hide()`；配套：读值口 `EVAL_TB_TEST_ROW_TEXT` 增加 `extraShown`（否则「行上不显示了」断言不了）+ 组 223/224 按「行上不显示 / 悬停里有 / 走**真实 OnEnter** 读真 GameTooltip 记账」改。★★**顺手抓到的死代码**：`tests/checks/LayerFix.js` 的导出函数开头写成 `return (function () {…})();` ⇒ **后面追加的检查全是死代码**（文件里看得到、日志里从不打印）⇒ 判据 = `TOOL TEST FILES CHECK` 的「顶层 return」一条。

**⑥p 「缩放大地图」勾选框点不动 = 模块引用了宿主文件的 local（1.74.36-2 全案·压缩）**
- **用户报告**：工具箱 → 缩放大地图的勾选框**点了不会勾上**，聊天框却每次都打「[简易地图] 已启用」。
- **根因**：`tbCfg` 是 `Toolbox.lua` 的 `local function`；模块里写 `(type(tbCfg) == "function") and tbCfg() or nil` ⇒ 恒取 nil（**读永远 false、写一次不生效、播报静默消失**，而界面照样说成功）。★**为什么三个闸门全绿**：Lua 语法没问题；行为断言测的是模块自己的纯函数（`EVAL_SM_SUMMARY()` 之类照旧对）。
- **修法**：跨文件一律走**全局桥**（`EVAL_TB_CFG`/`EVAL_SAY`/`EVAL_LOGLINE`/`EVAL_L`），或模块**自带同名 local**。**新判据 `MODULE HOST LOCAL CHECK`**：收集宿主（Toolbox/EvalHelp/Core/Engine）全部 `local`/`local function` 名字（本轮 **367 个**）逐个比对模块里的调用。

**⑥q 「未开启缩放大地图时还在不在监听探索层缩放」（1.75.7 全案·压缩）**
- **结论：会，而且不只是监听**（实测关闭状态 + 点 10 拍 tick：读了 10 次 `IsShown` + 10 次 `GetEffectiveScale`，还把叠加层几何**折了 8 次**（355/-320/215×215 → ×0.7 的 248.5/-224/150.5×150.5）、记下 2 条原值）。
- **根因两条（这类事故的通式）**：① **tick 是载入期无条件建的**（`CreateFrame("Frame","EH_SM_FEAT", WorldFrame)`）⇒ 与开关无关地一直跑；② 子开关（`SM_CFG.mapFit`，**nil = 默认开**）被当成了判据，**真正的总开关压根没参与**。
- **修法**：闸门放在**第一次读/写之前**、闸门块要**清「已应用」标记 + `return`**；「关掉时把改过的几何还回去」**当场做**。**闸门** = **组 230**（关闭：读 0 次 / 几何 0 次 / 关闭即还原；开启：照常监听折算 —— **反向哨兵不许把功能关死**）+ 源码检查 **`SM OFF SILENT CHECK`**（闸门在探测之前 + 有 return + 清 applied + 关闭路径真的调 `pcall(smFitRestore…`）；变异 **5/5** 捕获。

### R16. 铁律 3「先读 Heart / C」的完整对照表（1.74.36-2 从常驻卷 §一.3 迁入）

> 常驻卷只留「一行一入口」的速查；**要动手改队伍/血量/buff 相关代码时回来看这张表**。

| 问题 | 先读 |
|---|---|
| 名字 → unit id（从聊天/战斗文字反查） | `C\C_GetUnitID.lua`（缓存 `C_player_map` + `UnitExists`/名字复核 + 慢查 raid/party/pet/target/mouseover） |
| `target`/`mouseover` → 具体成员 | `C\C_AKA.lua`（`UnitIsUnit` 逐个比对） |
| buff/debuff 全量采集结构 | `C\C_SetPlayerData.lua`（16+16 槽扫描 → `C_player_data[名字].Buff[纹理]`） |
| 采集驱动 + 多插件仲裁 | `C\C_UpdatePlayerData.lua`（★同一轮更新只允许一个调用者） |
| 「某单位有没有某 buff」 | `C\C_UnitGotBuff.lua`/`C\C_UnitGotDebuff.lua`（**要求 `Tick == CurrentTick`** 才算「有」） |
| **用 tooltip 读没暴露的信息** | `C\C.xml`（隐形 `C_Tooltip`）+ `C_GetBuffData`/`C_GetDebuffData`/`C_GetSpellData` |
| 团队主逻辑、血量优先级 | `Heart\Heart.lua`、`Heart\Heart_Helper.lua`（`hpDeficit`、`priority * (healvalue / UnitHealthMax)`） |
| 事件与跨插件通信 | `Heart\Heart_event.lua`、`Heart\Heart_Hooks.lua` + `Plugins\*_Clicks.lua` |
| 图腾 / tooltip 扫描跟踪 | `Heart\Heart_Totem.lua` |

**怎么读**：重点是**大段注释**——对方把踩过的坑、API 的真假、为什么这么写全留在注释里，这是整个仓库**信息密度最高**的内容。


### R17. 「记忆体指令预算」全案（2026-09-25）· 压缩版
- **背景**：常驻卷被 `dsh-agent-instructions` 的 `maxBytes` 限制（旧 65536，超了**从尾部截断** ⇒ 末尾铁律 AI 看不到）；DSH 升到 0.1.7-rc.2 后改好的补丁失效（限值搬家）。
- ★★★**唯一有效修法 = web profile 补丁层按 id 覆盖 preset 声明行**：`%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml` 里的 `- id: preset-standard / preset-ptc / preset-cordis` 覆盖块，**完整重述 `config`**（其 `plugins` 内 `agent-instructions.config.maxBytes: 1048576`）。
- ★★**两条死路**：① 改安装内 `dsh-web-app\presets\<id>.patch.yml`（升级 / 换 `_npx` hash 即回 65536）；② profile 补丁里只写**单层** `- id: agent-instructions`（宿主那行被 web-app bundle 补丁 `disabled: true` 关掉 ⇒ `dump-config` 实证**写了也不生效**）。
- ★**覆盖会替换整个 `config`** ⇒ **少写字段 = preset 激活失败**（2026-09-25 早上 GUI 崩过一次就是这个）⇒ **一律脚本生成**：仓库根 **`dsh_memory_budget.js`**（`apply` 从当前安装重生成 + 先备份 / `check` 闸门 / `status` 列候选安装；`check` 用「临时 `DSH_HOME` + `dsh --profile web --dump-config`」自证，纯读、不碰真实 profile）。
- ★**判定「跑的是哪份安装」别猜 `_npx` hash / 别查进程**（junction 会骗人、沙箱里 `Get-CimInstance`/`tasklist`/`wmic` 全被拒）：**指纹 = 自己有没有 `ralph` 工具**（0.1.5-rc.x 的 standard/ptc 开着 `tool-ralph`，0.1.7-rc.2 **关着**）⇒ 本轮判定 = 全局 `%APPDATA%\npm\node_modules\@deepseek-ai\dsh`。
- **生效时机** `patchReload = startup` ⇒ **必须重启 GUI**，且只对**新开会话**生效（旧会话保持原预算）。**验证** = 把常驻卷临时撑过上限，看下一次注入有没有 `Workspace instruction budget … truncated`、尾部标记是否还在（只看「没报错」不算）。

### R18. 「玩家追踪效果（草药 / 采矿 / 野兽…）」全案（1.75.3）· 压缩版
- ★★★**只有三条 API，没有枚举接口**：① `GetTrackingTexture()`（Mapping）= 当前追踪的**图标纹理**，什么都没追踪 = `nil` ⇒ 判「在不在追踪」；② `GameTooltip:SetTrackingSpell()`（走**自建隐形 tooltip** `EVAL_HELP_WTT`）= **唯一**能拿到「是哪种追踪」**本地化名字**的入口；③ `CancelTrackingBuff()`（Buff）= 取消当前追踪。★三条官方页**都没有 Protected 行** ⇒ 插件可直接调；而 `CastSpell`/`CastSpellByName` 是 Protected ⇒ **开追踪只能走动作条 `UseAction(slot)`**。
- **不存在**：`GetNumTrackingTypes`/`GetTrackingInfo`/`SetTracking`（别照 1.12 抄）；**小地图圆点无法枚举**（Minimap 只有 `SetBlipTexture`/`SetIconTexture` 两个纯外观 setter）；**事件名官方未公开**（wiki `/wiki/lua/Events` = 404）⇒ 只能实测（别抄 pfUI 的 `PLAYER_AURAS_CHANGED`，那是 TurtleWoW 的值）。
- **官方另两条硬事实**：`GetPlayerBuff` **skip** hidden/tracking auras；Buff 页明文「Tracking auras are **not** listed here」⇒ **光环路线只能当旁证**。
- ★★★**真机实测形态**：`GetTrackingTexture()` 返 `/Game/Interface/Icons/<Base>_TEX.<Base>_TEX`（资产路径 + 「.」 + 对象名）⇒ `EVAL_TRACK_BASE` 取最后一段后**只认第一个「.」之前**（否则归一成 `x_tex.x` 永远命中不了）。真机三条路都通：① 纹理 ② 本地化名字（`SetTrackingSpell`：读到「追踪野兽」+ 第二行「正在追踪野兽。」）③ 默认 UI 追踪按钮 `MiniMapTrackingIcon`（Texture、纹理与①相同、`IsShown=true`）。★**追踪不占增益条** ⇒ 光环路线只能当旁证；★**事件名仍未实测出** ⇒ 实时刷新**不必依赖事件**：1s 轮询纹理、**变了才读名字**（贵调用只在变化时做）。
- ★**纹理 → 种类一律 `EVAL_TRACK_BASE`（剥目录/扩展名/`_TEX`、转小写）+ 全等比对 `TRK.hint`**（13 条实证表，**表在 `Engine.lua`**）：**不许子串匹配**（`INV_Misc_Flower_02` 会假命中 `..._02_Copy`）；表逐条由 **`TRACK ICON CHECK`** 钉在 `doc/图标路径清单.txt` 上（本机清单里没有的图标 = 真机永远匹配不上）；名字备用路 `EVAL_TRACK_KIND_BY_NAME`（zhCN/enUS，认不出就 nil，**不猜**）。
- ★**落成条件类型**：`{ id="tracking", kind="track", s="any" }`（**单选下拉**，值 = 候选表 id）归 **CTG_1 自身状态**；求值唯一入口 `EVAL_TRACK_MATCH(id)`（内部 `EVAL_TRACK_NOW()` **按纹理缓存** ⇒ 贵调用只在追踪变化时做一次）；分支在 `condOne`（`cd.v == false` = 反向「未追踪:X」）；导出走 id（`追踪:beast` / `未追踪:beast`）、界面走本地化标签；解析认 id / 基础名 / en / zh / 标签（认不出**整条丢弃**）。
- ★★**两个当场踩到的坑**：① **函数名以 `L` 结尾 + 字面量参数**（`EVAL_TRACK_LABEL("any")`）会被 `LANG KEY CHECK` 的正则当成语言键 `any` ⇒ 改走局部变量；② `EVAL_DD_OPEN` 的 `opts.selected` **只在 `multi = true` 时生效** ⇒ 单选下拉的「当前值」得自己加标记（金色圆点）。
- **判据/取证**：组 229（id/标签/清单 · 求值+缓存 · 文本往返 · 真实 condOne · 归组权重 · 真控件单选下拉）+ `TRACK ICON CHECK`（候选表 4 列 + **17 个 TRK 语言键三语齐全**；查键前**必须先剥注释**，否则注释掉一个键照样算有 —— 变异 M3 实测）+ **组 189**；取证命令 `/eh go 追踪探针`（读一次）·`监听`（事件实测，`RegisterAllEvents` 全量抓取、关掉时按次数升序列出）·`表`（13 条摊开）·`存档`（专属持久读数 `cfg.trkProbe`）。★**报告必须分三态**（① 类型 + **原文**：非字符串不许静默当「没追踪」；② 名字路独立于①，why = `ok`/`empty`/`noguard`/`noapi`；③ 增益条光环连名字一起读）。

### R19. 「聊天输出总闸门」全案（1.75.8）· 压缩版
- **用户原话**：「say 函数能否根据全局配置->调试日志状态开关要不要打印」+「记录调试日志重命名->调试日志」。
- ★★★**总闸门 = 配置项「调试日志」(`cfg.log.on`)**：关掉 ⇒ **整个插件一个字都不往聊天框刷**（模块自带的 say 全部委托 `EVAL_SAY` ⇒ 一处门控全生效）；★**同一判据也是数据层闸门**（`logLine` 一个字都不记）。★**闸门必须放在第一次输出之前**（与 §5.1「关掉零动作」同族）。
- ★**关掉时必须留一条看得见的回头路**：日志开关**自己**的确认行 + 「引擎未加载完整」兜底走 **`EVAL_SAY_FORCE`**（常开）—— 否则用户再也看不到「怎么开回来」。
- `cfg.wdebug`（配置项**「方案技能日志」**）＝更细的一层（Engine 里那批决策原因同步刷屏），**不是**总闸门；两条分工仍在，但总闸门**同时管「说不说话」**。★自建打印口的模块（`tools/SimpleMap.lua` 的 `P`）读 **`EVAL_CHAT_ON()`**；其余模块的 say 早已「优先 `EVAL_SAY`」⇒ 委托即门控（**有意例外**：子插件 `EH_DebugBox`——它有自己的开关）。
- **判据** = **组 231** + **`CHAT GATE CHECK`**（say 门控 `logEnabled→chatOut` · 两出口 FORCE/CHAT_ON · 声明顺序 · `/eh log` 常开 · 模块 P 读闸门 · 三语标签已改名；**变异 6/6**）。

### R20. 「探索层纹理被缩两遍」全案（1.75.9）· 压缩版
- **用户现象**（三轮递进）：「地图缩放 探索层纹理缩放是否操作了两遍?」→「关闭一次大地图缩放、再重新打开，就进行了 2 遍纹理缩放」→「我说的纹理缩放是 **WorldMapDetailFrame 下面 12 之后的纹理**…在开启/关闭大地图缩放要做好探索层纹理的事件清理」。
- ★★★**定案 = 本客户端自己会把父帧缩放级联到那批纹理上**（且**几何读回也含缩放**）⇒ 我们那套「按 es 折算」是**第二遍**。
- ★★★**判据（六条）**：① 动手前先**只读探测**（`smFitDetect`：外框缩放在 `1→0.7` 走一档，看屏幕几何跟不跟）；② 只有结论 `true` 才折算，**`nil`/`false` 一个几何都不碰**；③ 原值**只在自然档抓一次**（`smFitCapture` 临时 `SetScale 1`），`smFitApply` 里**绝不记原值**、`smFitRestore` **绝不清 `SMFIT.rec`**；④ 记录键用**纹理名**（枚举序号会随换区重建漂移）；⑤ `featApplyScale` **读回自证**（同档不重写）；⑥ **开启/关闭都要收钩子**（`featTeardown`：坐标行 OnUpdate / 拖拽柄 / `UISpecialFrames` 里我们插的那项；滚轮与坐标行各一道 enabled 门）。
- **闸门 + 策略三档**：`SM_CFG.mapFitMode` = `nil`/`"fold"`（**默认：照旧折算**）/ `"auto"`（听探测）/ `"nofold"`（一个几何都不碰），判定收在唯一入口 `smFitNeedFold()`；`smFitApply` 与 tick **各一道门**（★只放一道时变异 M1 当场漏网）。★★**别把默认改成「听探测」**（那一版上线后用户立刻报「现在正常开启都无法生效缩放修正」）。★**「真写过」标记 `SMFIT.wrote`**：本会话一次都没写过 ⇒ 关闭时**连还原都不写**。
- ★★**别把新结论外推到旧结论**：旧那条是「直接缩画布/尺寸」，不能外推到「缩外框 + 折算纹理」⇒ **旧结论要连条件一起继承**。
- ★同案附带修掉的一颗雷：模块在**文件执行期**缓存了 `EVAL_HELP_CONFIG.simpleMapCfg`（那时它还是**空表**）⇒ 设置与「原值记录」一个都没落盘 ⇒ 已改**懒代理**。
- 判据 = **组 232** + **`SM FIT CASCADE CHECK`**（变异 10/10，含「检查只匹配到一处门」那次当场漏网的补洞）+ 组 230（关掉零动作）+ `SM OFF SILENT CHECK`。

#### R20b. 「位置乱跳到左下角」全案（1.75.10）· 压缩版
- **用户原话**：「世界地图缩放开启之后，每次插件重载的初始位置能否居中。现在他有时候会乱跳到左下角位置」。
- ★★★**口径 = 每次载入后的第一次开图一律居中**（`FEAT.posArmed`，载入期就是 `true`），本会话内拖动之**后才**记位置。
- **判据五条**：① `featCenterOnce` 必须**先清掉存档里的 `SM_CFG.px/py`** 再摆正中 —— 那个值是「几何读回含缩放」下按折算公式写出的屏幕中心偏移，口径一旦对不上就**被永久继承**（每次开图都按它摆，还会累积）＝用户看到的「乱跳」；② 居中要配**有界窗口期**（`FEAT.recenter = SM_RECENTER_TICKS` ≈ 5s，`featKeep` 逐拍重申）—— 客户端自己的开图流程可能在我们 `featApply` **之后**才摆位置，只居中一次就是「有时候没居上」；③ 窗口期必须**可被拖拽打断**（`OnDragStart` 把 `recenter` 清 0），否则是跟用户抢位置；④ `featApply` 里「首次居中」**排在位置记忆之前**（顺序即判据）；⑤ `featCenterNow` **已居中就不写**（读回自证；读不到 `GetPoint` 才退回盲写），复位 `featReset` 同口径。
- 判据 = **组 237** + **`SM POS CENTER CHECK`**（变异 7/7；★其中「把窗口期那一段改成 `if false then`」**源码级抓不到**（字符串还在）⇒ 由组 237③ 行为断言抓住 —— 与 M24 同型：**互补不是漏**）。

#### R20c. 「探索层坐标丢失 / 全部图层挤在左下重叠」全案（1.75.13）· 压缩版
- **用户原话**：「排查工具箱->缩放大地图->探索层额外处理异常: 某些地图打开之后会将探索层的坐标丢失.全部图层都集中在左下区域重叠…**先别修改，分析问题**」（附 DebugBox 图层树 + 定位面板两张截图）。
- ★★★**功能定位**：用户说的「探索层额外处理」= `tools/SimpleMap.lua` 的**地图探索叠加层「跟随地图缩放」自动适配**（`smFit*`，真值 `simpleMapCfg.mapFit`，提示语写作「叠加层适配」，命令 `/ehm mapfit`）。DebugBox 里那批 `WorldMapOverlay1..8` + `WorldMapHighlight` 就是「探索层」。
- ★★★**客户端机制（本轮结论的地基）**：`WorldMapOverlayN` 是**按序号逐图复用**的纹理 —— 本机 TurtleWoW 同源实现 `S_WorldMap\Modules\MapOverlay.lua`（钩客户端 `WorldMapFrame_Update`）实证：`CreateTexture("WorldMapOverlay"..j)` → 每图按 `GetMapInfo()`/`GetNumMapOverlays()`/`GetMapOverlayInfo(i)` 的补丁列表**重新分配**，`SetPoint("TOPLEFT", WorldMapDetailFrame, "TOPLEFT", offsetX + 256*(k-1), -(offsetY + 256*(j-1)))`，**本图用不到的 `:Hide()` 且不清几何**（留着上一张图/初始默认的矩形）。⇒ **同一个纹理名在不同地图上代表完全不同的矩形**。
- **真机证据（`LIHAIBOAS2` 存档）**：① `cfg.log` 环里 `[mapfit] 折算：es=1.000 WorldMapOverlay1 原值(155.0,-403.0 240.0×185.0,来自saved) → 写入(…)` 连续多条 ⇒ 我们**在持续写**这批纹理，且 0.112s 后同一张纹理又被 `es=0.700` 写了一遍（240×185 ↔ 168×129.5，`折算口径：读回 es=1.000 ｜ 父链真有效缩放=0.700`）；② `mapFitOrig` 里 8 条原值 **6 条完全相同**（155,-403 240×185，正是某图某条补丁的矩形）+ 1 条 (295,-385 150×128) 属于别的图 ⇒ **不是任何真实版式**；③ `mapFitLast={es=0.7,changed=1,total=1}` 的 `total` 会随图变 ⇒ 目标集合本身在变，而记录只有一份。
- ★★★**根因五条（旧 schema）**：① 原值**只按纹理名**存一份（平表 `mapFitOrig[名]`）+ `mapFitVer=2` 永不失效 ⇒ 一图抓错、全图沿用；② **抓原值不看「本图用不用」**（无 `IsShown`/`GetTexture` 过滤）⇒ 记下的正是残留几何（6 条相同就是这么来的）；③ **写的时候对 `smFitTargets()` 全体写**（含隐藏/没贴图的）⇒ 本图不用的层全停在同一格 = 用户看到的「全部重叠」；④ **换图不作废** ⇒ 客户端刚摆好的坐标 0.3s 内被顶掉 = 「坐标丢失」；⑤ **还原用的是同一份脏原值**（且不看「我们写过没」）⇒ 关闭/还原也回不去（用户自己救不回来）。
- ★★★**修法五条 + 存档自愈**（全在 `tools/SimpleMap.lua`，判据 = **组 253**）：① **原值按地图身份分桶** `mapFitOrig[GetMapInfo 文件名+纹理尺寸][纹理名]`，换图**当场作废内存记录**（`smFitNewMap`，tick 里比 `smMapKey()`，开启路径 `smFitPrepare` 也对齐）；② **只碰本图在用的层**（`smFitInUse`：`IsShown()==false` / `GetTexture()==nil` 一律跳过；★**读不到就放行** —— 判不出不拦，别把功能判死，组 253⑤ 有反向哨兵）；③ 抓原值**等版式摆稳**（`SMFIT_SETTLE=0.4s`）；④ 客户端自报 `GetNumMapOverlays()==0` ⇒ 一个几何都不碰（apply/capture 各一道）；⑤ 折算**逐层记账** `wroteKeys[名]=地图身份` ⇒ 还原只还**本图写过的**层。★存档版本戳 `mapFitVer` **2→3**（旧污染整块丢弃 —— 只修代码不清存档 = 脏原值继续生效）。
- ★★**两个必须记住的接口事实**：① 读 `GetMapInfo()` **必须包一层函数再 pcall**（`pcall(function() return GetMapInfo() end)`）—— 本项目铁律「pcall 只保留第一个返回值」，直写 `pcall(GetMapInfo)` 拿不到 `height/width`，地图身份会退化成文件名（或 nil）；② 「本图在用」的判定一律**只读三态**，读不到不许当成「不用」。
- **取证口**：`/ehm mapfit dump`（只读清单 = 地图身份 / 客户端 `GetMapInfo`+`GetNumMapOverlays`+`GetMapOverlayInfo` 真值 / 每层「显示·贴图·本图在用·记录·本图已写」）· 既有 `/ehm mapfit trace|traceclear|diag|mode`。
- ★**判据** = **组 253**（换图重抓 · 折算用本图矩形 · 隐藏/没贴图层零几何 · 零叠加层零动作 · 还原只还写过的层 · 版本 2 自愈 · 只读清单）+ **`SM MAP KEY CHECK`**（9 条源码级：分桶、版本戳 3、换图作废、在用判定双侧、零叠加层闸门、版式稳定、逐层记账、清单/命令在位）；★模块的组号清单 `SM GROUP ROSTER CHECK` 的 `WANT` 要跟着加 **253**。
- ★★★**变异 4/4 被抓，其中两条是「当场漏网 → 补判据」**（这两条教训比代码本身值钱）：① **M1**（去掉 apply 的「本图在用」闸门）：第一版**漏网** —— 只断言「隐藏层的几何零调用」证明不了「有记录也不会写」（它们本来就没记录）；只查「调了 `smFitInUse`」也没用（`local use = smFitInUse(o)` 那行还在）⇒ 补两处：源码检查钉 **`if use and okp and p and okw and okh`**（判据必须**真的闸住读写块**，与 M8 同型）+ 组 253 **⑤b 先种一条脏记录**再验零调用（= 用户那台机器的真实状态）。② **M2**（`smFitNewMap` 不清 `SMFIT.rec`）：第一版**漏网** —— 换图前 `SMFIT.rec` 还是空的（它由 **apply 采纳**时才填，capture 只写存档桶）⇒ 组 253 补 **②b：先在本图折一轮（`EVAL_SM_TEST_MAPFIT_REC()==3` + 几何真的折过）再换图**。
- ⏳**仍未闭环的一条（需真机 A/B）**：R20 的定案是「本客户端**自己会**把父帧缩放级联到这批纹理上」⇒ 默认档 `fold` 就是**第二遍**；但 1.75.9 那次把默认改成「听探测」后用户立刻报「正常开启都不生效」。本轮**不动默认档**（只把折算做稳），真机上用 `/ehm mapfit dump` + `/ehm mapfit mode nofold|fold` 各看一次「探索层与底图对不对得齐」即可定案。

### R21. 猎人宠物「家族属性表 + 真机探针」全案（1.75.3）· 压缩版
- ★★★**`PetData.lua` 是 `gen_petdata.js` 的生成物**（技能/家族/图标三处数据都在生成器里，**手改必被下次生成冲掉**）；家族卡 = `families[id]`（`label/icon/cname/dmg/armor/hp/foods/sk`）+ `famOrder`（= **图片行序**，界面与探针唯一顺序来源）；源数据 = `doc/猎人宠物属性和技能图.jpg` → 转录 `doc/猎人宠物家族属性.md`。
- ★`other` **故意不带三加成**（未收录 ≠ 0）；`cname` 是客户端 `UnitCreatureFamily` 的匹配候选，**精确匹配 + 禁子串**（「猫头」不是「猫科」；认不出 → nil，不猜）。
- ★★★**技能图标 = 宏图标号**（用户指定 6 个）：撕咬 139 · 爪击 255 · 嚎叫 695 · 冲锋 700 · 甲壳护盾 710 · 暗影抗性 133。**号进 `PetData.skills[].iconIdx`、纹理运行期解析**（唯一合法入口 `GetMacroIconInfo(号)`，收在 `EVAL_PH_SKILL_ICON(sk)`：**按号缓存** + 取不到**退回 `skills[].icon` 语义路径**，绝不编路径/留空白）；号来自**图标库 Tab5 悬停的「宏图标序号：%d」**。★★**绝不能离线把号翻成路径**（`doc/图标路径清单.txt` 是**按字母排序**的白名单 ⇒ **行号 ≠ 宏图标号**；先例：DF 的 346 号在客户端是 `INV_Misc_Fish_20`）。已拿到的号→纹理真机读数（用户配合跑 `/eh go 图标号`）：139 `Ability_Racial_Cannibalize` · 255 `Ability_Druid_Rake` · 695 `Ability_Hunter_Pet_Wolf` · 700 `Ability_Hunter_Pet_Boar` · 710 `Ability_Hunter_Pet_Turtle` · 133 `Spell_Shadow_SealOfKings`（已写进生成器当**兜底**；★兜底写错的表现是「界面上显示的是别的图」且不报错 ⇒ 夹具走**绝对值**）。
- ★**`fam`（野兽→家族）定案优先级**（全在 `gen_petdata.js`）：⓪ **用户点名定案**（`FAM_USER`，最高）① **技能交集唯一** ⇒ 图片直接定案 ② 名字关键字**只在①的候选内**找 + **最长匹配优先**（修「`狼` 抢走 `狼蛛`」的老 bug）③ 显式覆写表（每条写理由）④ 名字**硬证据** ⑤ 其余**如实留 `other`**。实测 **重标 44 处、冲突 64→3、237 只全部定案**；`畏缩` 列为**非判据技能** `EVAL_PET_DB.skNoJudge`（例外只有一处来源）。
- ★**闸门口径 `PET FAMILY CHECK`**：具体家族的冲突必须**精确等于**例外表 `[爪击←尘泥钳嘴鳄鱼、爪击←猎蛛、爪击←癞爪]`（多/少都 FAIL）· **`other` 不算冲突**、**冻结 0** 条 · `skNoJudge` 必须恰为 `{ 畏缩 }` · **11 只抽查夹具**；变异 **16/16**。
- ★★**技能详情页宠物行的「家族图标 tooltip」= 最终形态**（内容唯一来源 `EVAL_PH_FAM_TIP_LINES`）：**纹理不吃鼠标事件** ⇒ 必须用**覆盖图标的透明 Button**；★图标按钮与其它六个控件**成对 Hide/Show**（第一版只进隐藏清单 ⇒ 被**组 234 当场抓到**）；★空行必须清 `row.beast`（否则 tooltip 报的是上一屏那只宠物的家族）；`other` 如实说「未收录」，**绝不显示成 0 加成**。
- **取证**：`/eh go 宠物家族`（别名 `/eh pet fam`）｜`表`｜`存档`｜`清`：读 `UnitCreatureFamily`/`GetPetFoodTypes` 与本表对账，读数落**有界环** `cfg.petProbe`（上限 40，已进残渣键清单）；读不到分四态如实报（`noapi`/`empty`/`error`/`notstr`），单位不存在**不对账**。判据 = **组 235/236** + `PET FAMILY CHECK ⑦c/⑦d`。
- ✅**用户二次确认**：家族显示名 6 处按图名改 · 7 条「名字被图片判掉」（含冬泉鸣枭→食腐鸟、雷鹰/山谷尖啸者→风蛇、异种爬行者→蝎子）· 两条名字硬证据例外维持 · 16 条覆写（含命名怪 7 条）确定 · **G1/G2 ❌ 不用** ⇒ **家族视图 UI 不做**、「宠物家族」**不进一键宏条件**（后人别再自行加）。
- ⏳**押后（用户「现在没测试环境.没法测试」）**：**A1/A2** 真机 `/eh go 宠物家族` 的 API 真值（`UnitCreatureFamily`/`GetPetFoodTypes` 形态 + `cname` 校准）· **B1** 家族属性表逐格复核 —— 恢复环境后只需 **跑一次探针 + 对图扫一眼**；★在那之前别当 bug 反复改。
- 判据 = **组 235/236** + `PET FAMILY CHECK`；变异 **28/28 + 31/31**（两条教训：**M29 变异只改第一处**而写回路还在 ⇒ 必须**全局替换**才算真拆掉；**M30/M31 检查被注释里的名字顶住** ⇒ 改为「先剥注释再剥字符串、只盯目标语句」）。

### R22. 「插件配置的图标是黑方块」全案（1.75.10）· 压缩版
- **用户报障**：「插件配置的图标初始使用：现在是黑色的没有图标」。
- ★**症状定案手法 = 截图取色**：那块方块 `#1D180E` ≈ 按钮创建时的 `WHITE8X8 × (0.12,0.10,0.06)`、一色占 95% 像素、无字无框 ⇒ 那是「**一次都没贴上过图标**」的暗底，**不是**「贴了一张黑图」——先分清这两种再谈修法。
- ★**三处修法**：① 贴图口（`mbApplyIcon`）必须**读回自证**（`GetTexture()` → `mbBack`）+ **alpha 还原**（兜底会把暗底 `SetAlpha(0)`，切回图标不还原 = 换个花样的透明）；② 兜底样式必须**真的看得见**（金框画在 BACKGROUND、暗底是不透明同尺寸 ARTWORK ⇒ **不透明掉暗底**；且**每次**进兜底都要把「EH」字**写回**）；③ **一次性载入接线不可靠**（贴图只在 `VARIABLES_LOADED` 打一次，那一刻宏图标表/存档未必就绪）⇒ 自愈口 `EVAL_HELP_MB_RETRY`（**已贴上就早退** = 正常路径零动作）+ 两个时机（`PLAYER_ENTERING_WORLD` / **鼠标悬停**）。
- ★**探针** `/eh go mbicon`（读数摊开：存档 / 已贴 / **读回** / 判定原因 / 自动挑；`<宏序号>` 按号设、`reset`、`重贴`）+ **专属有界落盘** `cfg.mbProbe`（12 行，进残渣键清单）——「贴上没贴上」在聊天框是读不到的（`say` 不落日志环）。
- ★★★**默认图标 = 头龙**（用户定稿原话「头龙 配置为插件默认图标」）：`EVAL_HELP_MB_PICKICON` 第一条 = **`^INV_MISC_HEAD_DRAGON_01`**（= 宏图标 **670**，`/Game/Interface/Icons/INV_Misc_Head_Dragon_01_TEX`），**力量祝福退居第二顺位**（某客户端没头龙那枚时不许掉到扳手）。★★**`_01` 尾号是判据的一部分**（`..._BLACK/BLUE/Bronze/Green` **不算命中**，组 95 有反向哨兵）。★**旧自定义一次性清掉**（账号级 `cfg.mbIcon` 只清 `INV_Misc_ShadowEgg_TEX` 那一个确切值 + **如实播报**）⇒ 否则用户永远看不到头龙。
- **判据** = **组 238** + **`MB ICON WIRING CHECK`**（变异 12/12；★教训：**M8/M8b 栽在「只查标签字样」** ⇒ 一律「标签 + **紧跟的取值表达式**」一起匹配；**M9 栽在「只建了空箱子」** ⇒ append 那一行也要钉）。判据 = `MB ICON WIRING CHECK ⑨`（顺序 + `_01` + 次位 + 迁移都在源码级钉住）。

## 十五、速查：分享消息模板 / 取证命令 / 关键 CHECK 明细（1.75.1 从常驻卷 §5.10 整段迁入）

> ★常驻卷超工作区指令预算会被**从尾部截断**，故把本节整体搬来（**原文未改一字**，只把标题降为 15.1）。
> 常驻卷 §5.10 现在只剩一行索引指向本节。

### 15.1 速查：分享消息模板 / 取证命令 / 关键 CHECK 明细

**分享消息（三段：色码打头 + 带链接 + 每条一段 8 位色码，间隔 ≥1s；身份只在 A 行）**
- 分片 `|cff9ad4ff|HEHPF:<id> <i>/<n>:<hex>|h[传输中...p%]|h|r`（走 `SH_CHUNK_LABEL` 三语言）
- A 行 `|c<身份色>|HEHPF:<id> 0/1:0|h[<头衔>]|h|r <名字> 分享了` · B 行（末条）`|c<品阶色>|HEHPF:<id> 0/1:1|h[<符号><品阶>秘籍·<名>]|h|r  <评语>`（★B 不带头衔尾巴）

**取证命令（本项目纪律：能做成命令就别让用户手工复现）**
- 光环：`/eh go tex`（看学习表）· `texdel 名字` · `texclear` · `texscan`；名字着色：`名字缓存`、`聊天 色测`。
- 分享：`/eh go 封皮测`（编号 A/B 变异测）· `分享探针`（发送留痕）· `色码测`（在用色码逐条实发；★跑完等 ≥30 秒再跑第二次）· `名号色 [<n>]`（预览/选用）。
- 其它：`/eh ds hud|trace|rnd` · `/eh go probe|bind|diag` · `/eh logdump` · `/eh guide`；稀有 `/eh go 稀有 目标|链接|目标探针`；框体/开窗 `框体探针`、`开窗探针 [停|看]`（只读）

**关键源码检查在守什么**（逐条清单已迁参考卷**附录 R13**，全清单见 `test_engine.js`）。


---

## 十六、§5.4「框拖拽 / 图层工具」判据原文（1.75.1 从常驻卷整批迁入）

> ★★**口径已于 1.75.1 变更**：宽/高从「所有窗口都不给」收窄为「**只给聊天窗**（并持久化）」——
>   下面是**迁移当时（1.75.1 合并）的原文快照**，作为历史保留；**现行判据以常驻卷 §5.4 ④ 为准**。

> ★常驻卷超工作区指令预算会被**从尾部截断**（§5.10 与 §六 导航行就这么丢过一次），故把这一整块**原文照存**在这里。
> 常驻卷 §5.4 现在只剩 7 行要点总表；要查**逐条判据的完整表述与踩坑经过**看本节（另见 R15 ⑥a~⑥n）。

- ★★★**「图层选择」名单（[设置] 多选下拉）**：真值 `dragFrames.pick[名]=true`，**表不存在 = 全选**；唯一写入口 `EVAL_DF_PICK_SET`（★第一次写先**物化全选快照**，否则一次取消勾选 = 其余几十层静默全关）；**七条路径全过 `dfPicked`**；菜单唯一来源 `EVAL_DF_PICK_MENU`。判据 = 组 214 + `DF PICK WIRING CHECK`；细则见 R15 ⑥a。
  ★**窗口图标与头部拖拽带**：图标 = **346 号宏图标**（按号现取、取不到退回「配」）；**左键只拖窗口、属性窗挂右键**；整条标题栏再挂透明「头部拖拽带」；分工收在 `dfBindDragButton`。判据 = 组 212/215 + `DF ICON ART CHECK`；细则见 R15 ⑥b。
  ★★★**拖拽位移一律「按屏幕算 + 量回自证」**（1.74.33）：`base.l/base.b` = 拖前**实测屏幕位置**；落锚唯一入口 `dfPlaceFrom`（首猜按 `GetEffectiveScale` 折算 →**量回**→**手量折算**修正）；`dfDragEnd` 新式基准记**屏幕差**。★必须**解仿射**（反算偏移与真偏移差一个**常数**，除系数救不了）。判据 = 组 217①~⑦ + `tmp/mut_drift.js` 6/6；全案见 R15 ⑥c。
- ★★★**所有窗口都不许改宽/高**（1.74.33 用户**第二次澄清**：「属性配置需要支持调整的是窗口的 x,y 坐标值」）：唯一真值 = **`DF_NO_SIZE`**（载入期给**每个**目标挂 `noSize`），读它三处 = 属性弹窗（**不建**宽/高行 + 常显说明）· `dfAttrsApply` 的 **`allowSize` 门**（**一个宽高写调用都不发**）· 老记录清理（清 w/h 并**还原 `ow/oh`**，没有原始值就**不去猜**）。★★**开窗重设 = A + C**：A＝**链式接管 `OnShow`**（先 `pcall` 调原生再跑 `dfApplyOne`；可重链、关掉即卸链）；C＝开窗后**有界**短复查（0.3s×4 / 墙钟 3s，**拖拽与战斗跳过**，到点摘脚本）。★★**位置调整 = 属性弹窗 X/Y 两行**（**绝对屏幕坐标** + 下拉预设 + `[−][+]` 微调；一律换算成屏幕位移走 **`dfPlaceFrom`** 量回自证，**绝不许**当本地偏移）。判据 = **组 206** + 组 208④⑥ + 组 220①③④ + **组 222** + `DF OPEN HOOK CHECK`；变异 `mut_nosize_all.js` 7/7 · `mut_xy.js` 4/4；全案见 R15 ⑥e。
- ★★★**1.75.1 追加：常驻层补「宠物动作条」**（用户：「工具→图层拖拽→设置. 常驻层缺少宠物动作条」）：`DF_TARGETS` 新增 `PetActionBarFrame`（`cands` 候选名解析，同动作条1~4 —— 本客户端 UI 编译在 pak 里，帧名只能现场探；一个都没命中就**如实缺席**、不画柄）；★**不带 roster/icon 标记 ⇒ 自然归第 1 组「常驻层（拖拽柄）」**（分组由 `EVAL_DF_PICK_MENU` 现算，标签不写死）。★★它是**按需出现**的（没宠物时不显示）⇒ 与队伍/团队同族，进 `DF_ROSTER_EVENTS` 的**有界跟随**：事件 **`UNIT_PET`** 有本地证据（本项目 `addons/EH_DebugBox/EH_DebugBox.lua` 正在注册它）、★**`PET_BAR_UPDATE` 本地零证据 ⇒ 不注册**（铁律 5④：探测名单不算注册依据）；跟满 `DF_ROSTER_TRIES` 即停、**不做常驻轮询**。判据 = 组 207/208。
- ★★★**1.75.1 起宽/高口径 = 只给聊天窗（并持久化）** —— 本节上面那条「所有窗口都不许改宽/高」是 **1.74.33 的原文快照**，仅作历史；现行以常驻卷 §5.4 ④ 为准（`dfSizeOK` / 弹窗显隐+窗高 / `allowSize` 门 / 清理只清 `noSize==true`；顺序铁律「先抓原值 → 再写新值」）。
- ★★★**「图层隐藏」（1.75.x 前叫「图层特殊处理」）= 独立模块 `tools/LayerFix.lua`；「图层拖拽」（1.75.x 前叫「图层拖拽柄」）那一行的界面接线也在自己的模块里**（1.74.34）：处理收在**规范表 `LF_FIXES`**（key/kind/`layer.cands`/`pick{last|path}`/label·tip 取词函数）；真值 = 本模块子树 `layerFix.fix[key]`，★**表不存在 = 一条都不选**（与 pick「不存在=全选」**相反**）；三处执行（勾选当场 / 载入期 / 有界复查到点摘脚本）；**层不在或对象数不够 ⇒ 一个都不动 + 如实播报**；还原三态（nil=读不到 ⇒ 按显示还原）。
  ★★**1.75.x 改名只动「显示值」**：三语 `TB_DFFIX`（图层隐藏 / Layer hiding / Скрытие элементов слоёв）· `TB_DBGDRAG`（图层拖拽 / Layer dragging / Перетаскивание слоёв）· 两者配套的 `*_TIP` 抬头 + `TB_DFFIX_NONE` + `tools/LayerFix.lua` 的 say 前缀 + `README.md` 两处清单；★**键名 `TB_DFFIX`/`TB_DBGDRAG`、文件名 `LayerFix.lua`、存档键 `layerFix.fix`、组 223、`LAYER FIX WIRING CHECK` 一个都没动**（断言全走 `EVAL_L(...)` ⇒ 改名不碰任何判据）。顺手修掉 tip 里的过期归属（原写「定义在 tools/DragFrames.lua 的 DF_FIXES 表」→ 实际 `LF_FIXES` / `tools/LayerFix.lua`）。
  ★★**界面侧只两处嵌入点**（用户：「尽量少的在 ToolBox 里改，只要加入嵌入点进行函数调用」）：① 载入期 `EVAL_LF_INSTALL`/`EVAL_DF_INSTALL`；② 工具箱**模块行**（一行数据 `t = "mod"` + 一个**通用**分支按 `EVAL_TB_MOD_ROWS[mod]` 取渲染函数）—— 工具箱里**不许**出现 `EVAL_DF_*`/`EVAL_LF_*` 这类模块内部件。判据 = **组 223** + `LAYER FIX WIRING CHECK` / **`TB MOD ROW CHECK`**；变异 `mut_lfix.js` 10/10 · `mut_dfrow.js` 6/6；全案见 R15 ⑥g。
- ★★★**工具箱那几行的「配置项」只在 `[设置]` 的悬停说明里显示，行上不再重复**（用户 1.74.36：「工具箱->以上UI工具的配置项.不需要再外部显示,已经在tooltip设置内显示了」）：模块行必须 `r.extra:Hide()`（那一格是工具箱自己的列表行在用），状态一律由 `tip.AddLine` 现读（含副作用提示）。判据 = **`TB MOD ROW CHECK ④`**（`tools/*.lua` 里出现 `extra:SetText` 即 FAIL）+ 各模块自查的 `LF/SM ROW SUMMARY CHECK`（行上不写 + 悬停里必须有）；读值口 `EVAL_TB_TEST_ROW_TEXT` 返回 `extraShown` 才断言得了这件事。
- ★★**「柄」按池位号复用** ⇒ 验「某目标有没有柄」要按**目标名**查当前**显示中**的那条（`dfName` 会被后面的目标改写，拿旧对象读 `IsShown` **误报**）。★**同一带上的两个控件 = 遮挡（断言盲区）**：[设置]/[重置] 同锚 ⇒ 后建者压住前者、按钮**永远点不到**而断言全绿（全案 R15 ⑤/⑥）。

---

## 十七、§5.9 关键标识符索引（1.75.1 从常驻卷整段迁入）

> ★常驻卷超工作区指令预算会被**从尾部截断**，故把索引表整段搬来这里（**原文未改一字**）。
> 完整清单（含全部测试读值口）见 `test_engine.js` 与 `test_assert.lua`；逐文件清单见 `tests/`。


- 配置/语言 `EVAL_HELP_CONFIG` · `EVAL_HELP_CFGWIN`（配置窗根）· `EVAL_HELP_CFG_TOGGLE` · `EVAL_RESOLVE_LANG` · `EVAL_IO_TEMPLATES`；解析/算分 `EVAL_PARSE_CONDS` · `EVAL_PROFILE_SCORE` · `EVAL_CLASS_LIST`。
- 分享/封皮 `EVAL_SHARE_SEAL_INFO` · `EVAL_SHARE_SEAL_TIER_RGB` · `EVAL_SHARE_DISPATCH` · `SH_POP_GOT_NAME`；头衔 `EVAL_TITLE_STATE` · `EVAL_TITLE_REFRESH` · `EVAL_TITLE_SET_CUSTOM`（只认第一次）。
- 聊天名字缓存 `tbNcHarvest` · `tbNcAt` · `tbNameClassEnsureRoster` · `EVAL_TB_NAMECLASS_PROBE`；工具箱 `tbBtn` · `tbMenuBuild` · `tbMigrateQuest` · `EVAL_TB_PAINT_ROW`。
- 图标库/下拉/调试 `EVAL_IB_SET_QUERY` · `EVAL_DD_SYNC` · `EVAL_DS_HUD`；测试读值口全清单见 `tests/`。
