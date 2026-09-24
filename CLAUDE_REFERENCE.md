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
★**装完必须核对条目数**（1.74.34 基准 = **72 个**（+`tools/LayerFix.lua` 图层特殊处理独立模块）；1.74.30 时是 71（+`tools/DragFrames.lua`）；1.74.29 时是 70；1.74.27 时是 69；1.74.12 时是 68、1.74.6 时是 66、1.73.5 时是 63；1.74.5 陆续加了 `tools/IconGrid.lua` / `tools/HunterHelper.lua` / `tools/ConsumableHelper.lua`，1.74.7 加 `tools/DismountHelper.lua`，1.74.27 加 `tools/RareWatch.lua`，1.74.30 加 `tools/DragFrames.lua`（框拖拽从子插件搬进主插件工具模块），1.74.34 加 `tools/LayerFix.lua`（图层特殊处理从 DragFrames 抽成独立模块））：
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
- **当前版本（源码唯一真值）**：`EvalHelp.lua` 的 `local VERSION` == `EvalHelp.toc` 的 `## Version` = **1.74.28**（v1.74.27 已发布）
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
1. **1.74.30** — 🧲 框拖拽**抽成独立工具模块** `tools/DragFrames.lua`（自包含 + 自有存档 `EVAL_HELP_CONFIG.dragFrames` + 老存档一次性迁移；子插件只留瘦转发）：修①拖拽结束不掉（本客户端**没有 `IsMouseButtonDown`** → 旧兜底是死代码；新增「全屏接盘 + 自校准兜底 + 超时无位移自动结束」六层）②配置窗贴左下角（`ClearAllPoints` 后位置=(0,0)；改成相对父级居中 + **读回自证** + 兜底）③**拖拽期间整体跳过 2 秒复查**（与手动拖拽抢锚点）；打包基准 71。
2. **1.74.28** — 🧺 两个助手弹窗候选**按物品类型过滤**（品质 → `GetItemInfo(链接)` → **自建 tooltip 兜底并自愈客户端缓存**；药草矿物材料等全剔，判不出不剔）+ 验证命令。
3. **1.74.27** — 🧹 稀有提醒转播**提取为独立模块** `tools/RareWatch.lua`（主程序只留两个接线点）+ **工具箱开关**（打包基准 69）。
4. **1.74.26** — 🧹 点名字**只做一件事**：`TargetByName(名字)` 选中它，选不中**就报错**；删掉所有与任务插件机制的耦合。
5. **1.74.25** — 📏 切目标文案纠错（真因 = 客户端只认附近单位）+ 目标探针。
6. **1.74.24** — 🎨 稀有提醒名字按**品阶染色** + 可点链接。
7. **1.74.23** — 🔔 **稀有提醒转播**：包住 UnrealQuest 弹窗唯一出口 `RareAlert:Show`。
8. **1.74.22** — 🧩 模版收录「神圣风暴」+ 模版按品阶重命名 + 作者/备注 + 神级改亮蓝。
9. **1.74.21** — 🎯 神级门槛 120 → **50**（封顶与示例全部现算）。
10. **1.74.20** — 👤 **配置分角色存**（三个助手 15 个键，`tbCfg()` 路由代理）。

---

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

### R15. 真机窗口帧名实测清单 + 客户端取证踩坑全案（1.74.32）

> 这一批全是**真机一次探针跑出来的事实**（`/eh go 框体探针` → 落存档 `EVAL_HELP_CONFIG.dragBars` → 外部读），
> 不是查文档也不是猜的。**下次要动「别人的窗口」，先看这里，别重新探一遍。**

**① 被动打开窗口的真名（探针实测，全部存在）**
- 尺寸统一 **384×512 / lv=1**（打开着的窗口 lv 会变高，实测 `CharacterFrame` 打开时 lv=8）：
  `GuildFrame`(公会) · `CharacterFrame`(属性) · `MailFrame`+`InboxFrame`+`OpenMailFrame`(邮箱) ·
  `QuestFrame`(任务对话) · `SpellBookFrame`(技能树) · `TradeFrame`(交易技能) · `MerchantFrame`(商人) ·
  `FriendsFrame`+`FriendsListFrame`(好友) · `BankFrame` · `BattlefieldFrame` · `DressUpFrame` · `GossipFrame` ·
  `GuildRegistrarFrame` · `ItemTextFrame` · `LFTFrame` · `PetStableFrame` · `PetitionFrame` · `TabardFrame` ·
  `TaxiFrame` · **`ClassTrainerFrame`(训练师 —— `TrainerFrame` 这个名字**不存在**，靠候选表第二个名字才探到)**。
- 其它规格：`QuestLogFrame` 704×512 · `HelpFrame` 640×512 · `ShopFrame` 700×460 · `SoundOptionsFrame` 400×570 ·
  `WorldStateScoreFrame` 640×512 · `LootFrame`/`ContainerFrame1..12` 256×256（背包） · `OneBankFrame` 400×400（OneBank）。
- 子弹窗（**不是**主窗口，别当目标）：`GuildControlPopupFrame` 297×298 · `LFTGroupReadyFrame` 308×220 ·
  `StationeryPopupFrame` 220×298 · `LFTGroupReadyStatusFrame` 360×152 · `LFTRoleCheckFrame` 250×200。
- **队伍没有整队容器**：`PartyFrame`/`PartyMemberFrameContainer`/`PartyFrameContainer`/`PartyContainer` **全不在**，
  只有 `PartyMemberFrame1~4` 四个独立帧 ⇒ 目标表拆成「队伍成员1~4」（用户 1.74.32 定）。
- 满屏（`1228.8×768` = UIParent 尺寸）的全是**事件帧/遮罩**，不是窗口：`EVAL_*`、`UnrealQuest*`、
  `AceEvent20Frame`、`CinematicFrame`、`WorldMapBlackout`、`UIOptionsFrame`、`SoundOptionsFrame`、`StatsFrame`。
- **仍未探到：拍卖行**（`AuctionFrame`/`AuctionHouseFrame`/`AuctionFrameContainer` 全不在、`auction` 关键词命中 0、
  兜底清单里也没有）—— 客户端**确实在跑** `Blizzard_AuctionUI`（它自己在写 SavedVariables），
  所以最可能是**匿名窗口**（`CreateFrame("Frame", nil, UIParent)`）⇒ 只能靠父子链取证（见下）。

**② 客户端取证踩坑全案（每条都真金白银踩过）**
1. **真机 SavedVariables 带 UTF-8 BOM**（`EF BB BF`）：直接丢给 Lua 报 `unexpected symbol near '<\239>'`
   ⇒ 读之前**先剥 BOM**（与当初 PowerShell 写文件那次是同一个符号）。
2. **全 `_G` 扫描是本模块第一处索引「任意全局」的代码**：`_G` 里有些对象是**不可索引的 userdata**
   ⇒ 一句 `f.GetParent` 就抛 `attempt to index local 'f' (a userdata value)`，**把整个探针打断**，
   而报错行看起来跟"帧名"毫无关系。修法 = `dfFrameUsable`（pcall 探测 + 只放 table/userdata）。
3. **`_G` 里同名子件成千上万**：光 `ActionButton*` 的贴图/文字/冷却圈就有 2900+ 个
   ⇒ 必须按 `GetObjectType()=="Frame"` 过滤，否则把 SavedVariables 灌成几百 KB；★判不出类型时**不许丢**。
4. **匿名窗口 `_G` 扫描永远看不到**（只认挂在 `_G` 上的具名帧）⇒ 只能走 `GetChildren()` 父子链两层，
   并**用「具名子件」当身份指纹**（匿名父 + `AuctionFrame*`/`BrowseButton` 这类子件名 = 认得出是谁）。
5. **`GetChildren()` 返回多值不是表** ⇒ 必须 `{ pcall(fr.GetChildren, fr) }` 再遍历；
   写成 `local kids = fr:GetChildren()` 只会拿到**第一个**子件（静默少数据）。
6. **父级「名字」不可靠**：`GetName()` 可能返回 nil（测试桩里 `UIParent` 就是匿名帧）
   ⇒ 判「宿主是谁」一律**比对象身份**（`p == rawget(_G,"UIParent")`），按名字判会一条都匹配不上。
7. **桩不保真三连**：桩原本**没有 `GetChildren`**（宽容兜底给一个返回 nil 的函数 ⇒ 父子链永远空）、
   fengari 是 Lua 5.3 **没有全局 `unpack`**（`unpack(children)` 直接报错、又被 pcall 兜住 ⇒ 表现成"什么都取不到"）、
   `UIParent` 在桩里无名。★都按「桩保真」补上了（补 `GetChildren` + 垫 `unpack`）。
8. **Lua 的 `a and f()` 只保留第一个返回值**：写成 `local p, _, rel = btn and btn:GetPoint(1)` ⇒ 后两个恒 nil，
   断言读到 nil 还以为锚点没设上（本轮 组212⑤ 就是这么误报的）。多值必须**先判后取**。
9. **`/eh go` 别名撞车是静默的**：新命令写了 `go icons` 当英文别名 —— 而 `go icons` 早就被**组 116 的图标路径采集**占了，
   分派是 elseif 链 ⇒ 先命中的赢，那条命令被**静默顶掉**（症状：用户跑 `/eh go icons` 得到完全不相干的行为）。
   现在有 `GO ALIAS UNIQUE CHECK` 守（按**缩进**识别分派链，同分支内的嵌套 `if` 不算新分支）。
10. **取证命令绝不许静默**：子插件那句裸 `pcall(EVAL_DF_PROBE_BARS)` 会把错误吞掉 ⇒ 真机上表现为
    「跑了命令、聊天框空的、存档里连键都没有」，**无法区分**「没跑到」与「跑了一半死了」。修法 = 三态阶段标记
    （`start`/`done`/`error` + 错误原文落档）+ 统一安全入口 + 命令先打一行「命令已收到」即时回显。
11. **拖拽机制会吃掉点击**：`dfDragBegin` 一 Show 全屏接盘（level 800，高于任何窗口图标）⇒ 图标自己的 `OnClick`
    **永远收不到**松手事件。修法 = 在 `dfDragEnd` 里判「按下了但没移动」（`st.moved` 是拖拽机制**自己算的**阈值，
    唯一真值），由它开属性弹窗。
12. **「像窗口」的判据要宽高都够大**：只用一个维度（`w>=200 or h>=200`）会被 400×120 这类条状件占满，
    真窗口反被清单上限挤掉（测试环境当场暴露，真机同样会）。

**③ 从常驻卷迁入的「名字着色族」原文（1.74.32 迁入）**
- 名字着色族（1.73.18~51）：名字在 `arg2`；名字槽不吃富文本 → 吞行自拼；色码必须 8 位 → `COLOR CODE LEN CHECK`；
  缓存唯一 = 名字→职业 token（`tbNameClassPut`）；四来源 = 白拿/`EVAL_TB_NAMECLASS_HARVEST(kind)`//who/事件；
  名册懒加载（`GetNumGuildMembers()` 恒 0）→ 自愈 `EVAL_TB_NAMECLASS_HEAL()` + 一发 `GuildRoster()`；
  `TB_NAMECOLOR_WRITE=false`；组 129b/161 + `NAME CACHE PROBE WIRING CHECK`。

**④ 从常驻卷迁入的「图层树折叠 / 层深」原文（1.74.33 迁入，为图层选择腾预算）**
- ★★★**图层树的层级只能来自「扫描时写下的层号」，不许数路径里的 `/`**（1.74.31）：`scanTree` 递归写 `d = depth + 1` 进节点、`uiBuildEntries` 带进条目 ⇒ 缩进与「层深」过滤**同一口径**。理由：① 根/子条目路径形态不一（前缀源多一层），按路径切父级对不上；② 同帧多区域路径**同名**不唯一；③ 过滤藏掉中间层 ⇒ 按过滤后列表算父子会漂移。
  【父子】`uiTreePass`：DFS 前序 + 未闭合祖先栈，层号 ≤ 栈顶就弹；`uiFiltered` 懒补算；折叠 `ui.treeCollapsed[路径]` 落存档（读回只收「值为真 + 键是字符串」）。
  【三态别混】行上 `▶/▼` 三来源：① 折叠 ② 层深上限卡住本层 ③ 子层被别的过滤藏了（`e.visKid` 记账）⇒ 只有 `(e.kids or 0) > 0` 且（已折叠/被卡住/有可见子层）才画开关，叶子不画。
  【层深 = 展开到第 N 层】唯一写入点 `uiDepthApply`；`0`（全部）**一个标记都不清**；点 ▶ 在「被卡住」时 = 上限抬到本层+1。判据：`DBX TREE WIRING CHECK` ＋ **组 205**；字形 `UI_TREE_OPEN=▼`/`UI_TREE_SHUT=▶`（`▸` 未验证）。

**⑤ 从常驻卷迁入的「只读取证要用哨兵钉住」原文（1.74.33 迁入，为图层选择腾预算）**
- ★★**声明「本次只取证、行为零变化」时，要用哨兵把它钉住**（1.74.32 第 1 步）：被动打开层候选挂成独立清单 `DF_WIN_CANDS` 喂探针（**不进** `DF_TARGETS`）⇒ 源码检查加「候选与 `DF_TARGETS` 零交集 + 目标数 == 12」两条哨兵（★第 2 步实现图标时要一起改掉，代码里有注释提醒）。理由：不小心接进去**不报错**，只是这些窗口突然被贴上整条透明柄。
  ★**通用形态**：凡是「本轮只取证 / 只搬代码 / 只接线，行为不变」的承诺，都要能**用源码检查或断言把它钉死**，否则它只是一句口头承诺 —— 而这类改动的错法恰恰是「悄悄多做了」。

**⑥a 「图层选择」多选下拉全案（1.74.33 用户：「拖拽图层右侧添加设置弹窗支持这么多种类的支持多选的下拉选择，选中的才开启配置和支持拖拽」）**
- **需求**：工具箱 → 拖拽图层行右侧 `[设置]` 弹一个**多选下拉**（38 个目标分三组：① 框体柄 1~10 ② 队伍/团队 11~15 ③ 图标形态窗口 16~38），**勾上的才贴柄/挂图标/应用存档属性/可拖**。
- **真值**：`EVAL_HELP_CONFIG.dragFrames.pick[目标名] = true`；★**表不存在 = 全选**（老存档升级后行为必须与升级前一致）；唯一写入口 `EVAL_DF_PICK_SET(name, on)`。
- ★★**第一次写必须先把「全选」快照物化进表**：老存档里 `pick` 不存在 ⇒ 用户取消勾一个，如果只写 `pick[name]=false`，其余几十层因「表里没键」全部变成未选中（**静默关掉几十个拖拽**，用户以为插件坏了）。物化 = 写之前先按 `DF_TARGETS` 把全部目标填成 true，再改这一项。
- **七条路径都要过 `dfPicked(name)`**：贴柄 `dfRefresh` · 挂图标 `dfIconsRefresh` · 应用存档 `dfApplyAll`/`dfKeepTick`/`dfApplyOne` · 事件结算 `dfRosterPass` · 清理 `EVAL_DF_RESET`。★未勾选的层**记录与属性都不动**（不重锚、不改宽高、不重置），并在播报里**如实报数**（不许假装全都处理了）。
- **单一来源**：下拉内容 = `EVAL_DF_PICK_MENU()`（从 `DF_TARGETS` **现生成**；组标题行走 `locked[i]`（无勾选框、点了不响应）+ `names=nil`）⇒ **工具箱不许有第二份目标表**。
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
- ★★**「初始值」被刷新覆盖 ⇒ 打它的是行为等价变异**：`dfHeadBuild` 里的初始 `SetHeight` 每次 `dfIconEnsure` 都会被重设 ⇒ 只改初始值的变异（M30）**应该存活**，别当成漏检；要打得打**权威赋值点**（`dfIconEnsure` 里那道）。
- **随勾选/开关一起收**（`dfIconsRefresh` 的收尾循环里 `rc.head` 与 `rc.b` 必须同进同退）：只收一个会留下**一条看不见却吃点击的带子**，而且这种「透明控件没被收掉」在界面上完全看不出来。
- **判据**：组 215（①在位/层级+10/真实高度只盖标题条 ②右端 ≤ 宽−58 且够宽 ③与图标不重叠 ④左键拖头部落存档且不弹窗 ⑤右键开窗 ⑥取消勾选一并收起）+ `DF ICON ART CHECK`（带的宽度公式必须呈「宽 − 左让开 − 留空区 − 图标宽」形态）；变异 M24~M29 全捕获、M30 为等价变异。
- ★★**图标边距两处都是真机截图改出来的**（同一个「只能靠真机看」的量，改法只有一处）：
  · **右边距 34 → 58**（`DF_ICON_RIGHT`）：34 让「配」压在**窗口自带的关闭按钮**上（法术书截图，两个控件叠在一起）⇒ 组 212⑤b 验性质「右边距 ≥40px」。
  · **上边距 6 → 18**（`DF_ICON_TOP`，1.74.33 用户第二次微调：「窗口的属性打开图标可以再往下移动12像素」，截图 = **好友名单**窗口）：6 让 20×20 的图标**骑在窗口上边框上**（上半截落在标题栏外，像挂在窗口沿上）⇒ 下移 12 ⇒ 图标纵向跨 [18, 38]，整块落进标题栏；组 212⑤c 验性质「上边距 ≥12px」。
  · 变异验证：把 `DF_ICON_TOP` 改回 6 ⇒ 组 212⑤c **当场报红**（`tmp/mut_icontop.js`）—— 证明这条断言真的**现读控件几何**，不是回读常量（回读 = 测自己）。
- ★图标与头部拖拽带**横向相邻、不重叠**（带的右端 = `W − DF_ICON_RIGHT − DF_ICON_SIZE`，组 215③ 守它）⇒ 图标纵向挪多少都不会被那条带盖住；而且两份控件共用**同一套鼠标分工**（`dfBindDragButton`：左键拖窗口 / 右键开属性窗），所以哪怕真叠上，行为也一样（但断言仍按几何查，别依赖这个巧合）。

**⑥c 拖拽「位移叠加漂移」全案（1.74.33 用户：「窗口拖拽有些会有位移叠加漂移，比如角色等其他测试。你拍下什么问题」）**
- **现象**：缩放 ≠ 1 的窗口（角色/法术书……）**每拖一次就多漂一个固定量**（越拖越偏），而且**第一次拖拽就比光标跑得远**；缩放 = 1 的窗口完全正常 —— 所以只有「有些窗口」。
- **真因（三层，缺一层都修不对）**：
  1. `dfCapture` 算锚点偏移用的是 `x = GetLeft + GetWidth × 系数 − 相对帧锚点` —— `GetLeft/GetBottom` 是**屏幕**坐标、`GetWidth/GetHeight` 是**帧本地**尺寸（含缩放），只在缩放 = 1 时同口径 ⇒ 每次捕获都把 `w × 系数 × (1 − s)` 掺进偏移。
  2. 那个偏移是**从几何反算**的（不是 `GetPoint` 原值），与 `SetPoint` 要的偏移差一个**常数**（单位口径 + 锚点系数叠加）⇒ 「按实测系数 k 反解」（`偏移 = 位移 / k`）**解不掉**：它假设响应过原点，实际是 `屏幕 = 常数 + 折算 × 偏移`。★第一版就栽在这里：单次拖拽对（40→40）、**连续三次仍叠加**（90→118.9）。
  3. 尺寸在拖拽**中途**变化时（队伍框来人 ⇒ 行数变了），旧口径记的是 `Δ(屏幕底边 + 本地高度 − 相对锚点)`，会把 `Δh` 当位移记进存档（夹具实测：光标只动 20px，存档记成 68）。
- **修法（口径与单位无关，不猜文档）**：
  · `dfCapture` 除锚点四元组外再记**实测屏幕位置** `out.l/out.b`（命名键、不进数组部分）；老记录没有它们 → 退回旧的纯锚点平移（**不假装能修**）。
  · 位移/落锚唯一入口 `dfPlaceFrom(fr, cap, dx, dy)`（`dx/dy` = **屏幕**单位）：首猜「偏移增量 = 屏幕位移 ÷ `GetEffectiveScale`」→ 落锚 → **量回**（`dfMeasure`）→ 差值是那个**常数**（与位移大小无关，一步消掉）→ 还没到位就用**两次落点手量真实折算**（`Δ屏幕 / Δ偏移`）再修，≤3 轮。返回的 k = 本次折算（**量出来的**；1 表示偏移即屏幕单位）。
  · `dfDragUpdate` 用**光标累计位移**（`cx − st.cx0`，**不除缩放**）喂 `dfPlaceFrom`；`dfDragEnd` 对新式基准记**屏幕差** `rec.dx = fin.l − rec.base.l`；`dfIsAt` 也改按屏幕比；`EVAL_DF_RESET` 走 `dfPlaceFrom(fr, rec.base, 0, 0)`。
  · 实测折算 `|k − 1| > 0.02` 时**在聊天里如实播报**（用户能看到「这个窗口为什么要折算 · 不再叠加」）；读值口 `EVAL_DF_TEST_STATE().lastK`。
- **判据**：组 217（①单次 40px 1:1 ②k ≈ 0.8 ③播报 ④**连续三次各 30px 总位移 = 90**（旧口径 ~118+）⑤纵向 1:1 ⑥「应用存档」回同一屏幕位置 ⑦拖到一半改尺寸仍记 20px 而不是 68）；桩里按真机语义造 1024×768 屏 + 缩放 0.8 的窗口（**UIParent 左下角故意不在 0**，否则单位错会被抹平）；变异 `tmp/mut_drift.js` **6/6**（M35 去掉量回自证→④ · M36 结算退回锚点相减→⑦ · M37 不记屏幕基准→② · M38 去掉修正循环→④ · M39 播报不报系数→③ · M40 `dfIsAt` 永远 true→组204）。
- **测试教训**：① 夹具必须**自洽**（第一版把屏幕基准塞进帧、UIParent 却留在 0 ⇒ 量出来的系数毫无意义，单次断言当场就红）；② 「把窗口挪歪」不能靠替换 `SetPoint`（不调用就不发生），要**直接改夹具的位置状态**；③ 让夹具的**尺寸可中途变化**，否则「尺寸掺进位移」这条路径**测不出来**（M36 会漏）。

**⑥d 开窗探针：被动窗口「打开时重设属性」的可行性取证（1.74.33，用户提问待确认）**
- **用户问题（原话）**：「图层拖拽->被动类窗口能否在打开的时候进行自定义属性重设.或者定时重设? 验证可行性 待我确认」
- **为什么这不是「顺手加个 tick」**：被动窗口（公会/属性/技能树/任务…共 23 个 `icon = true` 目标）的**自定义属性**
  （显隐/缩放/透明度/宽/高）现在只在**四个时刻**写：登录恢复 `dfApplyAll`、拖拽结束保存、显式应用、
  `dfApplyOne`（队伍帧出现时）——`dfAttrsApply` 的注释原文就是「**不做周期性写入**」；
  而 `dfKeepTick` 那套有界复查**只重锚位置、不碰属性**。所以「客户端在开窗时把自己的尺寸摆回去」这件事，
  我们现在**既没侦测、也没补救**（若真发生，用户看到的就是「我配的缩放/宽高，开了窗口就没了」）。
- ★**先取证再动代码**（铁律 4/5）：判断「要不要做」需要真机证据，而不是猜；`/eh go 开窗探针` 就是那件取证工具。
- **探针的四条契约**（错一条，真机取证就会得出错结论 —— 比不做更糟）：
  ① **只读**：只 `IsShown/GetWidth/GetHeight/GetScale/GetAlpha/GetLeft/GetBottom`，一个写接口都不碰
     （判据 = 组 218①：把夹具的 `SetWidth/SetHeight/SetScale/SetAlpha/Show/Hide` 全包计数 ⇒ 必须为 **0**；
     变异 M41「偷偷写一次 SetWidth」当场报红）。
  ② **显隐跳变 = 开窗的唯一可靠证据**，且**前后属性都要记**（前 = 我们写进去的值、后 = 客户端改成的值）——
     这一对就是答案；变异 M44（不记开窗事件）被组 218③ 捕获。
  ③ **开着时被改另记 `attrChange`，位置变化记 `posChange`**（本项目自己的有界复查也会动位置，不许混算）。
  ④ **有界**：武装 60 秒（`DF_ATTR_PROBE_SECS`）× 采样 0.25 秒，到点自停**并摘掉脚本** ——
     本客户端隐藏帧的 `OnUpdate` 照样触发，「只 Hide 不摘」= 永远空转（变异 M42 捕获）。
- **采样策略**（省开销）：每轮只读 23 个目标的 `IsShown`（便宜）；**窗口开着**（或还没有基线）时才读几何 ⇒
  成本与「当前开着几个窗口」成正比，通常每轮只有几次 API 调用。
- **落档**：`EVAL_HELP_CONFIG.dragAttr`（三态 `phase = start/error/done` + `caps` 能力清单 + `rows` 逐目标
  「存档要的 vs 关着时 vs 打开后」+ `events` 事件表）；`/eh go 开窗探针 看` 可复读。
  能力清单要报的三件事：每个目标的 `GetScript("OnShow")` 真值（**链式接管**的必要性）、`type(fr.HookScript)`、
  `type(fr.Show)`、以及全局有没有 `hooksecurefunc`（本客户端**没有**）。
- **命令**：`/eh go 开窗探针`（武装 60 秒）· ` 停`（提前收工，原因记 `manual`）· ` 看`（复读上次落档）。
- **判据**：组 218（①只读哨兵 ②命令入口武装+心跳 ③开窗事件前后对照 ④attrChange ⑤posChange
  ⑥OnShow 三态如实 ⑦到点自停且摘脚本 ⑧三态落档+计数汇总 ⑨停/看两条路）+ `DF PROBE SAFE CHECK`
  （新探针也守三态与 pcall：心跳里 `pcall(dfAttrPStep)`、出错即停并落错误原文）；变异 M41~M45 **5/5 捕获**。
- **测试教训**：夹具要**自己建**（前面的组收尾会把 `_G["GuildFrame"] = nil`）且建完必须 `EVAL_DF_TEST_TARGETS_RESET()`
  清解析缓存，否则探针解析到别组留下的旧对象、夹具上做的一切都测不到；
  「只读」这类承诺必须用**写接口计数器**钉住，光靠「代码里没写 SetXxx」是口头承诺。
- **待用户确认的三个方案**（取证结果出来后再定）：**A** 链式接管 `OnShow`（零轮询，推荐）·
  **B** 只在既有有界复查窗口里顺手重设属性（不改侦测）· **C** 开窗后武装一个 1~2 秒的短复查窗口
  （对付「客户端在 OnShow 之后一两帧才摆好尺寸」）。**都不新增常驻轮询**。
- ★★★**第一轮真机取证结果（用户已跑完：60 秒 · 227 轮采样 · 23 个被动窗口 · 21 条事件）**：
  · **结论 1（属性没被覆盖）**：唯一配过自定义属性的目标（**属性窗口**，只配了缩放 0.7）开窗后实测仍是
    `w=268.8 h=358.4 sc=0.70`，与存档一致 ⇒ **没有被客户端改回去**（落档 `armOK=1/armMismatch=0`、
    `openOK=1/openMismatch=0`）⇒ 就这一条而言「打开即重设」**不是必需**的。
  · **结论 2（但客户端确实会重写尺寸）**：**任务窗口**开窗那一刻宽从 384 → **704**（它的原生规格就是
    704×512）⇒ 客户端在开窗时按**自己的规格**摆尺寸。这次因为它**没配自定义宽高**所以判不出「会不会盖掉我们的值」
    ⇒ 这正是第二轮要问的问题（见下）。
  · **结论 3（侦测手段）**：`hooksecurefunc` 没有，**`Frame:HookScript` 也没有**（23 个目标全 `nil` —— 本轮新量的
    客户端事实）；而 **21/23 个被动窗口原生都挂着 `OnShow` 脚本**（`MailFrame` 明确没有、训练师那层当时不在位读不到）
    ⇒ 将来若要做「打开即重设」，**只能链式接管 `OnShow`**（`GetScript` 存原脚本 → 自己的脚本里**先调原脚本**
    再干自己的事），**绝不能覆盖式接管**（与滚轮链式接管同一纪律）。
  · **结论 4（开窗后没有二次改动）**：`attrChange` 事件 **0 条** ⇒ 没有「开窗后一两帧又被改一次」的现象 ⇒
    方案 C（开窗后短复查）在本次证据里**没有必要性**。
  · **附带发现（位置 ≠ 属性）**：多个目标「关着」与「打开后」的 `left` 读数差很大（属性窗口关着读 655.15、
    打开后读 0），开窗后还有多串 `posChange` ⇒ **隐藏帧的位置读数不可信**（客户端开窗时才真正摆位）；
    而缩放/宽/高/透明度的读数稳定可信。→ 将来任何「按读数判断位置」的逻辑都要记住这条。
  · **口径修正（本轮当场抓到的判据 bug，已修）**：`GetWidth/GetHeight` 含缩放 ⇒「存档要 384×512 + 缩放 0.8、
    实测读回 307.2×409.6」直接比会**假报「被客户端覆盖」**。修法 = `dfAttrPMismatch` 先比原值、不等再比
    「存值 × 实测缩放」，两者都不等才算真不符；「折算后一致」单独落 `foldedArm/foldedOpen` + 计数 `foldedN`
    （**不计入**不符）+ 播报单独一行。判据 = 组 218⑩；变异 M46 捕获（本轮 6/6）。
- **第二轮取证方案（待用户再跑一轮，把结论 2 问到底）**：给**原生规格与自定义值明显不同**的三个窗口各配一眼能
  认出的宽/高（**任务** 原生 704×512 · **帮助** 640×512 · **商店** 700×460 ⇒ 都配「宽 500 / 缩放 0.80」），
  再跑一遍 `/eh go 开窗探针` 并打开这三个窗口各停 2 秒。判据：「打开后」那行若出现**真不符**（不带「折算」字样）
  ⇒ **确证需要「打开即重设」**（方案 A：链式 OnShow）；若仍全一致 ⇒ **这个功能可以不做**（用户配的属性本来就安全）。
**⑥e 被动窗口「不许改宽高」+ 开窗重设 A/C 全案（1.74.33 用户拍板）**
- **用户的硬约束（原话 + 截图）**：「被动类型窗口不能设置宽度.会破坏内部布局.不能同时设置缩放和宽度.UI 会撕裂」
  —— 截图是**法术书**：左边技能列表被撑成一大块、右边那条页签被挤成一条细缝，两边各画各的。
  ⇒ 结论：**宽度对被动窗口是危险能力**（缩放实测安全：属性窗口缩放 0.7 一直好用）⇒ 宁可少一个能力，也不要一个会把界面搞坏的能力。
- **实现（唯一真值 `noSize`）**：`DF_TARGETS` 载入期给所有 `icon = true` 目标打 `noSize = true`（一个循环、一处真值）；
  ① **属性弹窗**：五行改成**带 key** 的行（`p.rowBy`；★不再按下标读值 —— 藏了行之后下标必然错位，那是「静默改错属性」的经典入口），
     被动窗口**藏起宽/高两行**（按钮与标签**都要藏**：标签是 root 的子件，不跟着按钮走）+ 显示一行说明 `TB_LD_NOSIZE_TIP`；
  ② **`dfAttrsApply(fr, rec, quiet, tgt)`**：`allowSize` 门守在两处 SetWidth/SetHeight 上（一个写调用都不发，组 220③ 用写接口计数器钉住）；
  ③ **老记录清理 `EVAL_DF_SIZE_CLEAN`**（挂在 INSTALL、**独立于 `store.mig`** —— 老用户那道迁移早就打过标记，挂它下面等于永不执行）：
     有 `rec.ow/oh` 就**还原原尺寸**，然后清掉 `w/h/ow/oh`，并如实播报「清了几个目标、还原了几项、为什么」。
  ★★**踩过的坑**：`dfCommitPop(target, ...)` 传进来的 `target` 是**帧**（`dfDragEnd`/图标点击都传 `b.dfTarget`），
     而 `noSize` 挂在**目标表项**上 ⇒ 第一版判不出来（组 220② 当场报红）。修法 = 新增 `dfTgtOfName(name)` 按名字回查目标表，弹窗与保存两侧都复用。
- **A：链式接管 `OnShow`**（前提来自第一轮真机取证 ⑥d：21/23 原生有 OnShow、本客户端无 `Frame:HookScript`）：
  · `dfOpenHookEnsure(fr, tgt)`：`GetScript` 读当前 OnShow（nil 也照样存：「原本没有」也是事实）→ `DF.onShowOrig[fr]` → `SetScript` 装 `DF.onShowBoss`；
    ★**幂等**；★**被别人换掉后重新链**，链的是**最新那个**原生脚本（组 220⑥ 用「新原脚本被调用 1 次」验）；
  · `DF.onShowBoss(self)`：**第一件事永远 `pcall(orig, self)`** → 再 `dfApplyOne(tgt)`（属性 + 位置一次做完，复用唯一入口）→ 再 `dfOpenArm`（C）；
    ★**顺序可判**：夹具让原生把 scale 设成 1.0、我们的重设再设回 0.8 ⇒ 触发后读到 0.8 就证明「原生先跑」（组 220⑤）；
  · `dfOpenHookRemove(fr)`：把 OnShow **还回原生那一个**（`orig`，可以是 nil = 摘掉脚本）；关主开关/取消勾选即卸链（组 220⑦）；
  · `dfOpenHooksSync(on)` 在 `dfIconsRefresh` 末尾跑（`dfRefresh → dfIconsRefresh` ⇒ 每次刷新都同步），条件 = 主开关 + 该层被勾选，**与图标显隐开关无关**。
- **C：开窗后有界短复查**：`DF_OPEN_PERIOD=0.3` · `DF_OPEN_CHECKS=4` · `DF_OPEN_WALL=3.0`（绝对墙钟）· `DF_OPEN_MAX_T=12`（超了**如实记 `drop`**）；
  步进体 `dfOpenCheckStep` 只在「位置不在存档点 或 缩放/透明与存档不符」时才 `dfApplyOne`（**宽高不在复查范围** —— 那能力已经拿掉了）；
  **拖拽中/战斗中跳过并如实记 `skips`**；到点 `dfOpenStop` **摘掉 OnUpdate 脚本**。
  为什么还要 C：A 只在 `OnShow` 那一刻重设一次，而客户端有可能**在它自己的 OnShow 之后一两帧**才把尺寸摆好（第一轮证据里任务窗口是 384→704）。
- **判据**：**组 220**（①noSize 唯一真值 ②弹窗藏行+说明 ③应用存档不写宽高&缩放照写 ④清理并还原 ⑤链式顺序 ⑥幂等+重链 ⑦卸链还原 ⑧C 能修回+有界自停摘脚本 ⑨战斗中跳过并记数）
  + 源码检查 **`DF OPEN HOOK CHECK`**（链式顺序/装链存原脚本/卸链还原/`allowSize` 门/`noSize` 标记/清理入口/C 墙钟与摘脚本）；变异 `tmp/mut_openafter.js` **6/6** 捕获。
- **测试教训**：① 夹具要**自己建**且建完 `EVAL_DF_TEST_TARGETS_RESET()` 清解析缓存；② 播报里的数字要**在断言那一刻取**（弹窗会为别的目标重开、清理会再调一次 SetWidth/SetHeight ⇒ 取晚了打出误导数字）；
  ③ 组号**先查有没有被占用**（本轮新组与既有组 219 撞号，改名 220）；④ 源码检查里「取函数体」必须认**列 0 的 end**（缩进的 end 是内层 if 的，用它截断会切半函数体 ⇒ 一串假 FAIL）。

**⑥f 从常驻卷迁入的「物品类型过滤」细则全文（1.74.33 迁入，为被动窗口约束腾预算）**
- ★★★**两个助手的弹窗候选按物品类型过滤**（1.74.28）：判定收在**共用件 `EVAL_IG_ITEM_KIND`**（tools/IconGrid.lua），**三级**按「便宜→贵」早停 ——
  ① **品质**（`GetContainerItemInfo` 第 5 返回，不依赖缓存）⇒ 灰色一律剔；② **`GetItemInfo`**：传参**先用物品链接**（客户端缓存键），nil 再退名字；读第 5/6/8 返回 = 主/子类型/**装备槽**（装备槽非空 ⇒ 算护甲）；③ 缓存为 nil ⇒ **自建隐形 tooltip** `EVAL_HELP_WTT` + 守卫 `EVAL_WTT_MAY_READ` + **`SetBagItem`** 读类型行 —— 这步会**把物品写进客户端缓存** = **自愈**。
  ★**剔除表** `IG_KIND_DROP`：武器/护甲/灰色/**材料**/任务/容器/箭矢弹药/钥匙/配方；★**判不出就不剔**（查不到 ≠ 没有）+ 计入 `EVAL_IG_KIND_STATS().unknown` 如实报。
  ★★**过滤只在「弹窗候选」路径开**（`EVAL_IG_SCAN_BAGS(bags,{classify=true})`）——按名字解析包格那条路（`EVAL_CH_FIND`/`EVAL_HH_FIND_FOOD`）**绝不过滤**（判错一类 = 用户已配置的物品静默找不到）。
  ★★**tooltip 只读 TextLeft2 起**（跳过 TextLeft1 = 物品名，名字可能含类型词会污染判定）；词表 `IG_KIND_WORDS` 按真机实测文案维护。
  ★验证命令：`/eh go 消耗品探针 过滤` ｜ `喂食探针 过滤`（逐件打判定依据 + 统计行，同时是补词表的依据）。判据 = 组 187（剔除逐项 / tooltip 兜底 / 缓存自愈后不再探 / 关掉 `classify` 行为不变）。
- ★★★**第二轮口径收窄（1.74.33 同一天，用户澄清）**：「图层拖拽功能.是所有窗口都不能调整宽高.会把内部原始撕裂.
  是我之前的需求说错了　属性配置需要支持调整的是窗口的 x,y 坐标值」
  —— 第一轮我把范围理解成「被动窗口（icon 目标）」，实际是**所有窗口**（拖拽柄层/动作条也不例外）。
  · **实现改法**：加 `local DF_NO_SIZE = true` 作**唯一真值**；目标表改为 `DF_TARGETS[i].noSize = DF_NO_SIZE`（每项都挂，读值口/判据直接读它）；
    `dfAttrsApply` 的 `allowSize = (not DF_NO_SIZE) and ...`（**不看 tgt 也判定得出来**）；属性弹窗**整体删除**两行 `addRow(-118/-146)`；
    保存处理器里「读原值 → 写宽高 → 读回自证」整段删除（连读都不读）；`EVAL_DF_SIZE_CLEAN` 去掉 `noSize` 过滤 ⇒ **所有**留宽高的记录都清。
  · **判据翻转**：旧组 206（1.74.31 那套「弹窗 5 行 / 选 500×200 / 还原」）**整体重写**成验「宽高改不了」
    （①弹窗不建宽/高行且说明常显 ②真实下拉+保存：缩放照写、**宽高写调用 0 次**、存档不留 w/h/ow/oh、播报不出现「宽 N」
     ③老记录清理并还原 300×60 ④只有 w/h 无原始值 ⇒ 清记录但**不猜尺寸** ⑤应用存档也不写宽高）；
    ★组 208④⑥ 原来用**宽**验「参数立刻生效 / 关掉开关不动目标」⇒ 停用宽高后这两条会变成**恒真的空断言**（弱判据），
      已把载体换成**缩放**（性质不变、载体换成还支持的那一项）——「判据照需求改」而不是删掉了事。
  · **变异**：`tmp/mut_nosize_all.js` **7/7**（摘宽高门→组206⑤ · 弹窗又建宽高行→组206① · 不先调原生→组220⑤ · C 不摘脚本→组220⑧ · 清理不还原→组206③ ·
    不标 noSize→组220① · 清理只挑被动窗口→组206③）。
  · **待用户确认（下一轮做）**：「属性配置需要支持调整的是窗口的 x,y 坐标值」—— x/y 的**语义**要定：
    (a) **绝对屏幕坐标**（X=左边缘、Y=下边缘，如 100 / -50）还是 (b) **相对位移**（相对记录基准的 dx/dy，与拖拽记录同一口径）？
    控件形式也随之定：本客户端 **EditBox 疑似不渲染**（老账）⇒ 只能用**下拉预设**（配合 `EVAL_DD_OPEN` 多列）或**微调按钮 [−][+]**；
    落地时注意：x/y 必须走 `dfPlaceFrom`（量回自证 + 手量折算）这条唯一落锚入口，绝不能再出现「把屏幕量当本地偏移用」。
- ★★★**X/Y 坐标行（用户第二次澄清真正要的那一项）实现全案**：
  · **语义 = 绝对屏幕坐标**（用户选定）：X = 窗口左边缘、Y = 窗口下边缘。实测值域 X 0~1228 / Y 0~768
    （屏幕坐标原点在左下角 —— 第一轮开窗探针的数据：各窗口 `left` 0~655、`bottom` 152~287 ✓）。
  · **控件 = 下拉预设 + [−][+] 微调按钮**（用户选定）：本客户端 EditBox 疑似不渲染（老账）⇒ 不做打字输入；
    ★预设**最多 10 项**（共用下拉列表只有 10 行、没有滚动）⇒ 预设给粗档（`DF_X_PRESETS`/`DF_Y_PRESETS`），
    精调靠按钮（`DF_XY_NUDGE=10`；按住 Shift 走 `DF_XY_NUDGE_FINE=1`，用 `IsShiftKeyDown` 且 pcall 兜住）。
  · **落锚**：X/Y → `dx = nx - base.l`、`dy = ny - base.b` → **`dfPlaceFrom(fr, base, dx, dy)`**（唯一落锚入口，量回自证）；
    ★**绝不许**算完坐标直接 `SetPoint`：那就是「把屏幕量当本地偏移用」的老坑（缩放≠1 必偏，组 222② 专门用「缩放 0.5 的窗口」
    区分：直接 SetPoint 会落在 150 而不是 300）。落完**读回自证**，没到位如实播报（不改口径、不假装成功）。
  · **老记录**：`base.l/base.b` 缺失时先 `dfScreenBaseOf` **反推**基准；反推不出来（尺寸读不到）⇒
    如实说「读不到基准位置 ⇒ 本次没设（不猜位置）」并且**一个写调用都不发**（组 222⑥）。
  · **回填只改显示、不写 `row.value`**：写了就等于「用户没动过也会被保存」，会把「客户端刚把窗口摆回去的错误位置」
    静默固化下来（变异 M60b 捕获）。微调按钮**必须写 `row.value`**（只改显示不写值 = 保存时丢改动，M61b 捕获）。
  · **判据**：组 222（①两行+两按钮+回填不写值 ②下拉 X=300 精确落点 + 老记录反推基准 ③微调 +20 精确生效
    ④Shift 步长 ±1 ⑤Y=400 精确且不动 X ⑥读不到基准不改目标且如实说明）+ `DF OPEN HOOK CHECK` 的 X/Y 三条哨兵；
    变异 `tmp/mut_xy.js`/`mut_xy2.js` **4/4**（绕过 dfPlaceFrom→组222② · Shift 档写反→组222④ · 回填写值→组222① · 微调不写值→组222①）。
**⑦ 从常驻卷迁入的「品阶显示」原文（1.74.33 迁入，为图层选择腾预算）**
- ★★品阶显示现算（不硬编品阶）：文字＝品阶色、底色×（激活 0.45/否则 0.22）；组 160/167。图标＝IconSem 真纹理 13px；★`EVAL_SHARE_SEAL_ICON` 两返回值**禁内联进可变参数调用**（先收局部再 pcall——内联会丢第二个返回值）；`PROF ICON PROBE WIRING CHECK`；组 160⑥⑦。★重锚前 `ClearAllPoints`；文字框留富余（`TPL_TEXT_PAD=4`·组 91）。

**⑧ 从常驻卷迁入的两条零碎判据（1.74.33 迁入，为窗口图标口径腾预算）**
- ★**COND WEIGHT CHECK 的实战价值**：它上线当场抓到 `target`（「选取目标」，hidden 存量类型）**不在任何分组**里 ⇒ 新口径下会被按 0 分算、也不计覆盖（静默少算）。★「新增条件类型必须进组」由它兜底。
- ★★**`/eh go` 别名不许两家共用**（1.74.32）：`go icons` 早被组 116 占用 ⇒ elseif 链先命中的赢、那条命令被**静默顶掉**；`GO ALIAS UNIQUE CHECK` 守。

**⑥g 图层特殊处理（Layer Fixes）全案（1.74.34 用户三连问）**
- **用户原话**：①「能否对固定的某个层内的最后2个纹理做特殊处理.比如隐藏这2个纹理」（配 EH_DebugBox 图层树截图：
  `MainMenuBarArtFrame` 的 #21/#22 两条 `纹理:Texture` 被红框圈出 = 动作条两端那两张狮鹫贴图）；
  ②「以上如果可行.可以在工具箱->UI 工具->添加个图层特处理->设置/重置 ,设置功能支持下拉,目前里面添加个动作条狮鹫 ,支持多选.切换显示选中的特殊处理.」；
  ③「以上特殊处理定义规范配置.以后可能还有其他特殊处理, 弹窗下拉UI参考图层拖拽->设置」。
- **可行性结论 = 可行**，且有本地证据：① 层真名来自用户截图（容器 `MainMenuBar` 的子帧 `MainMenuBarArtFrame` 717×37，
  它 `GetRegions()` 前 6 条是 `纹理:Texture`、第 7 条是 `字体串`）；② `Texture:Hide()` 是普通 Region 方法（非 Protected）；
  ③ 枚举区域本客户端实测可用（EH_DebugBox 整棵图层树就靠 `GetRegions`/`GetChildren` 走）。
- **定义规范（唯一来源 = `tools/DragFrames.lua` 的 `DF_FIXES`，加一条处理只加一项）**：
  `key`（= 存档键，★绝不用序号/显示名）· `group`（下拉分组号）· `kind`（现在只有 `hideTex`）·
  `layer = { cands = {...} }`（帧名候选，与 `DF_TARGETS` 同口径：命中名会如实播报）·
  `pick = { last = N }`（按 `GetRegions()` 顺序取**最后 N 个纹理**）或 `{ path = "子串" }`（按贴图路径小写包含匹配，**更稳**，
  留给拿到真机路径后启用）· `label`/`tip` **必须是取词函数** `function() return L("键") end`
  （★键字面量要出现在源码里，否则 `LANG KEY CHECK` 看不见；★现取才不会绑死加载期语言）。
- **真值** = `EVAL_HELP_CONFIG.dragFrames.fix[key] = true`；★**表不存在 = 一条都不选**（与 `pick` 的「不存在 = 全选」**相反**）：
  特殊处理会改客户端界面，绝不能因为升级/加条目就自动生效（变异 M6 专门验这条：写反 → 组223① 当场报红）。
- **执行三处（全都有界）**：① 勾上/取消**当场**生效或还原（工具箱多选下拉每点一下就调 `EVAL_DF_FIX_SYNC`）；
  ② 载入期 `EVAL_DF_INSTALL` 调一次（重进游戏照样生效）；③ 启动期**有界**复查窗口（`dfKeepTick`，1s×5 次）里补一次
  —— 覆盖「层还没建出来」与「客户端自己又把它显示回来」，窗口结束即停（**不另开常驻计时器**）。
- **三条诚实性硬规矩**：① 层不在 / 层里纹理数少于要处理的个数 ⇒ **一个对象都不动** + 如实播报「没做成 + 这次没动界面」
  （绝不猜一个「看起来像」的层动手）；② 原始状态是**三态**（true=显示 / false=隐藏 / **nil=读不到** ⇒ 还原时按「显示」还原）——
  读不到就当 false 的后果正是用户会看到的「重置了但贴图没回来」；③ 本来就隐藏的元素**绝不**用 `Show` 弄出来（组223⑤）。
- **幂等**：`DF.fixState[key]` 存在即短路（**不重新挑对象**）—— 重新挑会因为在往「更前面」数而藏错对象（组223③b 幂等哨兵）。
- **接线（易漏且不报错的部分）**：★★★ `local dfFixSync, dfFixTick` **前向声明**必须写在 `dfKeepTick` / `EVAL_DF_INSTALL`
  两处调用**之前**（本项目头号坑：写在后面 = 那两个名字绑成全局 nil，而调用点套着 `if ... then` 守卫 ⇒ 静默永不执行）；
  工具箱那一行 `t = "dfFix"` + **`noChk = true`**（真值就是多选里勾了哪几条，多挂一个总开关只会多一份真值）
  ⇒ 渲染段必须 `if not it.noChk then r.chk:Show() end`（否则长出点了没反应的死勾选框）。
- **判据**：**组 223**（①规范 ②菜单唯一来源+默认全不选 ③只藏最后 N 个且前面的一个不动+播报层名与贴图路径 ③b 幂等
  ④取消当场还原/再勾再生效 ⑤诚实还原（隐藏的不弄出来）⑤b 读不到原状按显示还原 ⑥层不在一个不动+如实播报
  ⑦[重置] 还原+清勾选 ⑧存档持久化+重开后守护 ⑨有界复查补晚出现的层+被显示回来再藏 ⑩工具箱端到端）
  + 源码检查 **`DF FIX WIRING CHECK`**（DF_FIXES 必填字段/默认不选/陌生键拒写/菜单现生成/**前向声明哨兵**/
  两处调用都在/工具箱几何与多选/noChk）；变异 **`tmp/mut_dfix.js` 7/7**（全部由**断言**捕获，不是靠源码检查兜）：
  取前 N 个→组223③ · 还原不 Show→组223④ · 写入口不落存档→组223③ · 摘掉有界复查调用→组223⑨ · noChk 失效→组223⑩ ·
  默认语义写反→组223① · 还原后不清记账→组223④。
- **读值口**：`EVAL_DF_TEST_FIXES_RAW()` · `EVAL_DF_TEST_FIX_STATE()`（含每个对象的 `shown`/`orig`/`paths`）·
  `EVAL_DF_TEST_FIX_STATE_CLEAR()` · `EVAL_DF_TEST_STATE().fixApplied/fixRehide` · 工具箱 `EVAL_TB_TEST_ROW_TEXT(key)`。
- **★待真机确认（还没做）**：`pick = { last = 2 }` 是按**用户自己的定义**（层内最后 2 个纹理）实现的；本次播报会打出
  层名 + 两条**真贴图路径** ⇒ 用户跑一次即可核对「藏的是不是那两个」。若顺序/命中不符（或客户端改版换了顺序），
  把该条改成 `pick = { path = "路径关键字" }` 即可（**代码已支持，只改规范表一项**，不需要动引擎）。
- **测试踩坑**：① 桩里 `Texture` 的 `IsShown` 默认 nil（真机 CreateTexture 出来就是显示的）⇒ 夹具要**显式建立**显隐状态；
  ② 夹具的区域顺序必须把**字体串放在纹理后面**（与真机截图一致），否则「不数错类型」这条判据是空的；
  ③ `EVAL_DF_TEST_STATE()` 原本没有 `fixRehide` ⇒ 新读值口要同步补（第一次运行就报了 `attempt to compare number with nil`）；
  ④ `test_assert.lua` 里 `print("ALL TESTS PASS")` 有 **8 处**（14891~14895 是历史遗留的连续 5 行）⇒ 追加新组必须用
  `lastIndexOf` 锚末尾那处，用 `indexOf` 会命中注释（第一版报了「锚点命中 8 次」）。

**⑥g-2 抽成独立模块（1.74.34 第二轮，用户：「能否将以上功能提取到./tools 独立文件脚本管理.尽量少的在ToolBox文件内修改.只要加入嵌入点进行函数调用?」）**
- **落地形态**：新文件 `tools/LayerFix.lua`（约 35 KB，自包含）；`tools/DragFrames.lua` 里那一整段（14.6 KB）
  被**整段删除**（含前向声明 `local dfFixSync, dfFixTick`、`DF` 表里的 `fixState/fixApplied/fixRehide`、
  `dfKeepTick` 与 `EVAL_DF_INSTALL` 里的两处调用、`EVAL_DF_TEST_STATE` 的两个字段、全部 `EVAL_DF_FIX_*` 读值口）。
- **只留两处嵌入点**（这就是用户要的「函数调用」）：
  ① `EvalHelp.lua` 的 VARIABLES_LOADED：`if type(EVAL_LF_INSTALL) == "function" then pcall(EVAL_LF_INSTALL) end`
     （与 `EVAL_RW_INSTALL` / `EVAL_DF_INSTALL` 同一排）；
  ② `Toolbox.lua` 的**模块行**：模型里**一行数据** `{ t = "mod", mod = "layerFix", key = "layerFix", label = L("TB_DFFIX"), tip = L("TB_DFFIX_TIP"), noChk = true }`
     + 渲染段**一个通用分支**：
     ```lua
     elseif it.t == "mod" then
       local reg = rawget(_G, "EVAL_TB_MOD_ROWS")
       local fn = (type(reg) == "table") and reg[it.mod] or nil
       if type(fn) == "function" then pcall(fn, r, it)
       elseif type(EVAL_SAY) == "function" then pcall(EVAL_SAY, "工具箱：这一行要的模块没载入（mod=…）…") end
     end
     ```
     ⇒ 控件、tooltip、下拉、结算**全在模块里**（`lfRow`），Toolbox **一行都不知道**模块内部长什么样。
- **注册表为什么不走「函数登记」而是走全局表**：`EVAL_TB_MOD_ROWS` 由**模块自己**在载入期「没有就现建」，
  Toolbox 只在渲染时 `rawget` 取一次 ⇒ **toc 里谁先谁后都成立**。只认「对方已经建好表」的写法会出现
  「模块先载入 ⇒ 登记无处可去 ⇒ 面板上那一行点不动」的**静默失效**（这类顺序依赖是本项目老坑）。
- **存档搬家 + 一次性迁移**：真值从 `dragFrames.fix` 搬到**本模块自己的子树** `EVAL_HELP_CONFIG.layerFix.fix`；
  `lfMigrate` 把老的 `dragFrames.fix[key]` 逐条搬过去并**把老键清掉**（绝不留两份真值）；存档没就位时**不写、不标记**，
  交给 INSTALL 的 `0.5s × 20` 有界重试。真机用户已勾选的那一条**不会丢**（组 223⑧ 专门验这段迁移）。
- **复查窗口自给自足**：不再蹭框拖拽的 `dfKeepTick`，模块自己开 `EVAL_LF_KEEP`（`1s × 5` 次、墙钟 15s，
  到点 `lfStop` **摘掉 OnUpdate 脚本**）；只在真的做事时播报（补生效 / 再藏回去），不刷屏。
- **与 DragFrames 零耦合**：源码检查**反向守** `tools/LayerFix.lua` 里出现 `DF_TARGETS` / `dfPicked` / `dfStore` /
  `dfTargetFrame` / `dfPlaceFrom` / `dfKeepTick` / `dfApplyOne` 任一即 FAIL；同时反向守 `tools/DragFrames.lua` 里
  出现 `DF_FIXES` / `dfFix` / `EVAL_DF_FIX` / 「图层特殊处理」任一即 FAIL（**搬走必须一份不剩**：两份真值会互相打架）。
- **判据全量改名**：`DF FIX WIRING CHECK` → **`LAYER FIX WIRING CHECK`**（改查 `tools/LayerFix.lua`），
  新增四条哨兵：① 工具箱**不许**认识模块内部件（`LF_FIXES`/`EVAL_LF_`/`EVAL_DF_FIX`/`gryphon`/`MainMenuBar` 出现即 FAIL）；
  ② 两组 `mod` **名字必须一致**（工具箱 `mod = "layerFix"` vs 模块 `LF_TB_ROWS["layerFix"] =`；对不上 = 那一行点不动且不报错）；
  ③ toc 必须列 `tools\LayerFix.lua`；④ `EvalHelp.lua` 里那行必须**可执行**（见下面的 M9 教训）。
  组 223 也全面改成新接口（`EVAL_LF_*` / `EVAL_LF_TEST_*` / 真值子树 `layerFix` / 自己的 tick 帧），并补了两条：
  「模块行的渲染函数**已登记**进 `EVAL_TB_MOD_ROWS`」与「旧位置迁移不丢勾选」。
- **所有 9 处文件清单都要补新文件**：`test_engine.js` 里 8 处 `"tools/DragFrames.lua"` 清单 + 1 处单引号的 fengari 载入清单
  （DECL ORDER / LANG KEY / COMMENT SWALLOW / SAVEDVARS SPLIT / EXAMPLES TOC / WHEEL / COLOR CODE LEN / FRAME NAME CLASH / 载入），
  以及 `EvalHelp.toc`；另外 **`PACK LIST CHECK` 的条目数基准 71 → 72**（参考卷里那句「基准 = **N 个**」）。
- **★本轮踩到的两个新坑（都已落进判据）**：
  ① **「名字还在」不等于「那行能执行」**：变异 M9 把载入期那句改成 `if false then pcall(EVAL_LF_INSTALL) end` ——
     名字与调用都还在 ⇒ 只查 `indexOf("EVAL_LF_INSTALL")` 的源码检查**当场漏过**（10 个变异里唯一一个漏的）。
     修法 = 判据钉**可执行的那一整句**（`if type(EVAL_LF_INSTALL) == "function" then pcall(EVAL_LF_INSTALL) end`）。
  ② **`String.replace` 会把内容里的 `$&`/`$'` 当展开语法吃掉**：早前那版「块文件 + `src.replace(锚点, 块 + 锚点)`」的插入脚本，
     把块里 regex 转义那句 `"\\$&"` 展开成了**锚点原文**（于是 `DF ICON ART CHECK` 的注释文字被注进了代码里，
     文件里出现两处同名注释）。本次改用 `slice` 拼接 + 「残留检查」，并把 `$&` 记进纪律：
     **凡是用 node 脚本改源码，一律 `slice`/`indexOf` 拼接，绝不用 `String.replace` 塞含 `$` 的内容**。
- **变异**：`tmp/mut_lfix.js` **10/10**（9 条由断言捕获、1 条由源码检查捕获——正是两类检查互补的样子）：
  取前 N 个 · 还原不 Show · 写入口不落存档 · 有界复查不补 · noChk 失效 · 默认语义写反 · 还原后不清记账 ·
  嵌入点不调模块 · 载入期不安装（源码检查） · 有界窗口不摘脚本。

**⑥g-3 「图层拖拽」那一行的界面接线也搬进模块（1.74.34 第三轮，用户：「审查下 图层拖拽的功能.在Toolbox.lua 内的代码修改.参考以上也进行./tools 的代码文件归类」）**
- **审查结论（先审后动）**：Toolbox 里属于这个功能的代码只有 **3 处**：① 模型行（`t = "lddrag"` + `ldReset/ldSet` 两个开关字段）；
  ② `elseif it.t == "lddrag" then … end` 分支（约 **128 行**：`[重置]` 的 tooltip/清单/OnClick、`[设置]` 的多选下拉代理、
  主开关的 `r.get/r.set`）；③ 常量 `TB_LD_TIP_W = 460`（只被那段用）。**其余判定/真值/公式本来就都在模块里**
  （`dfPicked`/`EVAL_DF_PICK_*`/`EVAL_DF_RESET`/`EVAL_DF_SET`），所以这次是**纯界面接线搬迁**，行为零变化。
  ★顺带确认：勾选框的 OnClick（`tbBuild` 里那段）是**点击时**才读 `row.get/row.set`，且**没有** `dbgDrag` 专用副作用分支
  ⇒ 模块在自己渲染函数里设 `r.get/r.set` 完全等价（组 202②「两向同源」仍在守它）。
- **搬法**：`dfRow(r, it)`（[重置]=`r.clr` / [设置]=`r.add` / 主开关 `r.get/r.set`）+ `DF_TB_ROWS["dragFrames"] = dfRow`；
  Toolbox 侧模型行改成 `{ t = "mod", mod = "dragFrames", key = "dbgDrag", label = …, tip = … }`
  （★**不写 `noChk`** ⇒ 主开关勾选框照旧；`key` 必须留 —— 读值口按 key 找行，丢了 `key` 断言会**静默跳过**）；
  整段分支与 `TB_LD_TIP_W` 删除，`Toolbox.lua` 里**再不许出现** `EVAL_DF_*`（反向哨兵）。
  净效果：Toolbox 少 128 行、多 1 行数据 + 已有的通用分支（−6.3 KB）。
- **判据跟着搬**（三处源码检查）：
  · `DF PICK WIRING CHECK` ⑤ 段：从「工具箱 [设置] 分支」改成「模块 `dfRow`」（菜单/写入口/结算/计数/重置清单/主开关 8 个接口 +
    多选三件套 + 几何哨兵 `r.clr`/禁 `r.chv`），并保留「工具箱里不许有目标帧名字面量」；
  · `DRAG FRAMES WIRING CHECK`：工具箱侧断言 → 模块侧（`dfRow` 存在 + 登记 + 四个接口）+ 反向哨兵（Toolbox 无 `EVAL_DF_*`）+ 模型行存在；
  · **新增通用检查 `TB MOD ROW CHECK`**：① 通用嵌入分支（注册表取值 + 真调用 + 未登记时如实上报）；
    ② 模型里每个 `t = "mod"` 行必须有 `key`，且 `mod` 名字必须在 `tools/*.lua` 里有**同名登记**（对不上 = 那一行点不动且不报错）；
    ③ Toolbox 不许出现模块内部件（`EVAL_DF_`/`LF_FIXES`/`EVAL_LF_`）。
    ★这条通用检查是这次审查的**产品**：以后再加模块行，名字/键/嵌入点三件事一次判到底，不必给每个模块再写一份。
- **变异**：`tmp/mut_dfrow.js` **6/6**（**全部由既有的行为断言捕获** —— 搬动没有削弱覆盖）：
  不登记（组 200）· [设置] 不结算（组 214⑧）· 换 `chv` 槽（组 200 tooltip/几何）· 工具箱 `mod` 名字写错（组 200）·
  主开关无读写代理（组 202②）· [重置] 不接还原（组 204⑤c）。
- **测试影响**：**零改动** —— 组 200/202/204/214 全部按 `key = "dbgDrag"` 走读值口（`EVAL_TEST_TB_ADD_BTN_FOR` / `CLR_FOR` / `CHK_FOR` / `ROW_BTNS`），
  搬动后按钮仍由模块建在同一套槽位上，断言原样通过（这正是「读值口按稳定键找行」这条纪律的红利）。

**⑥h 工具类归属规范 + Toolbox 剩余功能审查（1.74.34 第四轮，用户：「以上工具类的整理要加入项目记忆。尽量单独文件进行管理，在 Toolbox.lua 内只做开启/配置入口的引入」）**
- **规范（已入常驻卷 §4.1）**：工具功能一律 `./tools/<模块>.lua` **自包含**（真值 + **自己的存档子树** + 界面控件 + 读值口 + **自己的有界计时器**）；
  `Toolbox.lua` 里**只允许**「模型行数据 `t = "mod", mod = "<名>", key = "<键>"`」与「入口按钮（点了就调模块函数）」；
  **不许**出现整窗 UI / 事件帧 / OnUpdate / 解析与状态机 / 协议队列。
  机制 = 模块行注册表 `EVAL_TB_MOD_ROWS[mod]`（模块**载入期自建自登记**，两边谁先载入都成立）；渲染段只有一个通用分支；
  判据 = 通用 **`TB MOD ROW CHECK`**（模块行必须有 `key` + `mod` 名字在 `tools/*.lua` 里有**同名登记** + Toolbox 不许出现模块内部件）
  + 每个模块自己的 `* WIRING CHECK` 里那条**反向哨兵**（「Toolbox 里出现 `<模块内部件>` 即 FAIL」）。
- **审查口径（怎么量）**：`tmp/audit_toolbox.js` —— 按顶层函数块（顶格 `end` 收尾）统计体积，再用「归属判定表」把每个函数归到
  「工具箱自身框架」或「某工具功能」。**判据不是「写在哪个文件」，而是「这函数是谁的知识」**：
  行模型/两列/连续窗口滚动/存档路由/读值口 = 工具箱的**本职**（留在原地）；某个工具的窗/状态机/事件/协议 = 该工具的**知识**（应进 `./tools`）。
- **1.74.34 审查结果（Toolbox.lua 共 5927 行 / 250 个顶层函数）**：

  | 归属 | 体量 | 内容 |
  |---|---|---|
  | 工具箱自身框架（**留**） | ~3000 行 | `EVAL_TB_BUILD`(251) · `EVAL_TB_REFRESH`(234) · `tbModel` · 两列/切点/滚动/`EVAL_TEST_TB_*` 读值口 · `tbCfg`/`tbMakeRouter`/`tbCharStore` · `tbBtn`/`tbText`/`tbSolid` 等自绘助手 |
  | **应进 ./tools（待搬）** | ~1300 行 + 若干混在框架里的助手 | ① 商家助手·**自动购买设置窗** `buyUIBuild`(199)+`buyUIRefresh`(84)+`EVAL_BUY_UI_*` ≈ **334 行**（整窗 UI + 步进器 + 列表 + 滚动 + 自己的读值口）② **聊天名字按职业着色** `EVAL_TB_NAMECLASS_*`/`EVAL_TB_CHATCOLOR_*`/`EVAL_TB_WHO_*`/`tbNcHarvest` ≈ **384 行**（缓存 + who 查询 + 事件帧 + 收尾）③ **右键名字菜单** `tbMenuBuild`(76)+`tbMenuItems`(76)+`tbMenuChrome`(41)+`EVAL_TB_NAMEMENU_*` ≈ **270 行** ④ **子插件注册表与行** `EVAL_TEST_SUBADDONS`(73)+`EVAL_SUBADDONS_*`+`EVAL_PLUGIN_*` ≈ **172 行** ⑤ **频道/拦截关键字** `EVAL_TB_CHANKEYS_*`/`EVAL_TB_QCHAN_*` ≈ **115 行** ⑥ **频道进出屏蔽** `EVAL_TB_CHAN_OFFICIAL_*` ≈ **52 行** ⑦ **旧配置迁移** `tbMigrateBuy`/`tbMigrateQuest` ≈ **17 行** |
  | 混在框架里的同名助手 | — | `EVAL_TB_CHATEVENT_INSTALL`(159) · `EVAL_TB_CHAT_COLOR_LINE`(118) · `EVAL_TB_NAME_PARTY`(67) · `EVAL_TB_TICK`(91)/`EVAL_TB_ONEVENT`(85)（工具箱的事件帧被多个工具共用 ⇒ 搬迁时要么把帧也交给某个模块、要么保留一个**只做派发**的薄壳） |

- **搬迁次序建议（按「干净程度」排，不是按体量）**：
  ① **频道进出屏蔽**（52 行，纯 API 开关 + 一个已存在的 `EVAL_TB_CHAN_OFFSET` 同步点）→ `tools/ChatChan.lua`；
  ② **频道/拦截关键字**（115 行，自己的下拉+输入框）→ 并入同一个 `ChatChan.lua`；
  ③ **右键名字菜单**（270 行，自成一窗、只读缓存）→ `tools/NameMenu.lua`；
  ④ **子插件注册表**（172 行，与配置窗「子插件」Tab 同源）→ `tools/AddonReg.lua`；
  ⑤ **聊天名字着色**（384 行 + 与 who 查询/事件帧耦合最深）→ `tools/NameClass.lua`（**要先把事件帧归属定下来**）；
  ⑥ **自动购买设置窗**（334 行整窗，但依赖工具箱的 `tbCfg()` 与 `tbBtn/tbText` 助手）→ `tools/BuyUI.lua`（**先把自绘助手抽成共用件或让模块自带**）。
  ★**每搬一个都要**：加 `.toc` + 8 处源码检查名单 + 模块行/入口 + 删旧代码 + **反向哨兵** + 跑该功能的既有断言组 + 一条新变异。
- **本轮的边界**：这一轮**只做规范 + 审查**（用户说的是「整理要加入项目记忆」），**没**动上面那 1300 行 —— 搬迁按上表次序**逐个做**，一次一个、每次跑满两道闸门与变异。

**⑥i 从常驻卷迁入的「可驱散负面类型多选」原文（1.74.34 迁入，为工具类规范腾预算）**
- 可驱散「负面类型」多选（1.73.2；**1.74.6 扩到自身/目标 debuff**）：`cd.dt` = nil / 单串 / 集合（**空集 = 任意**）；
  **求值一律走 `dispelMatch` 按类型过滤**（名字对上但类型不符 = **没有**）；
  **名称留空 + 类型 = 「有任意该类型」**（层数取命中项**最大值**）；类型存**平行表** `st.{player,target}DebuffType`（层数表仍是数字）；
  格式化同一份 `dtSuffix()`（导出 token / 显示本地化名）；编辑窗类型格**四族都有**、**buff 行不许有**；组 114 ＋ 组 181。

**⑥j 工具模块自带的测试三件套归模块自己管（1.74.34 落地全案）**
- **用户原话**：「test 相关的搬迁到对应工具类子文件内自身管理。」（承接同一轮的「工具类功能独立文件」规范）
- **落地形态（三件套各归其位）**：
  ① **读值口**留在模块本体 `tools/<模块>.lua`（如 `EVAL_LF_TEST_*`，模块自查用）；
  ② **断言组**搬到 `tests/tools/<模块>.lua`（LayerFix 的组 223 逐字迁入，22.7 KB），文件头写死四条纪律：不进 toc/不随包 · **一律用共用的 `EVAL_TEST_EQ`** · **末行必须 `EVAL_TEST_MOD_DONE("<模块>")`** · 夹具自建自清；
  ③ **源码检查**搬到 `tests/checks/<模块>.js`（原来嵌在 `test_engine.js` 里的 `LAYER FIX WIRING CHECK` 整段抬进 `module.exports = function (root) {…}`），harness 里只留一行 `require("./tests/checks/LayerFix.js")(__dirname);`。
- **共用件**：`test_assert.lua` 头部暴露 `EVAL_TEST_EQ = eq` 与 `EVAL_TEST_MOD_N / EVAL_TEST_MOD_NAMES / EVAL_TEST_MOD_DONE(name)`；**兄弟文件写 `local eq = EVAL_TEST_EQ` 即可** ⇒ 失败格式与其它组逐字一致（自带一套判定 = 两套口径，早晚打架）。
- **harness 接线（`test_engine.js`）**：在 `test_assert.lua` **之后**自动加载 `tests/tools/*.lua`（排序后遍历），跑完打一行 `MODULE TESTS: <跑到底数>/<磁盘文件数>（名字）`，并**当场对账**：不相等 → `TOOL TEST FILES CHECK: FAIL` + `process.exit(1)`。
  ★**为什么必须对账**：这类失效**全是静默的** —— 文件存在但没被加载，整组断言消失，套件**照样打印 ALL TESTS PASS**（本项目最恨的形态）。
- **新源码检查 `TOOL TEST FILES CHECK`**：
  ① 每个 `tests/tools/*.lua` 必须用 `local eq = EVAL_TEST_EQ` + 有 `EVAL_TEST_MOD_DONE("…")` + 有 `GROUP …: PASS` 收尾行；
  ② 每个 `tests/checks/*.js` 必须 `module.exports = function`，且 `test_engine.js` 里**必须真的有一行 require+调用**（漏了 = 那条检查静默缺席）；
  ③ **反向哨兵**：`tests/` 不许出现在 `EvalHelp.toc`（会被当插件模块载入）与发布打包行里（测试代码不随包发给用户）。
- **变异验证**（`tmp/mut_tests.js`，6/6 全捕获）：M1 加载器 `modTests.slice(0,0)` 静默跳过（**只有握手对账能抓**）· M2 末行握手注释掉 · M3 自造 `local eq` · M4 `tests/checks/` 多出一个没人 require 的文件 · M5 harness 里那行 require 被注释 · M6 `tests\tools\LayerFix.lua` 被列进 `.toc`。
- **★第二个真实的插曲（更要记：源码检查自己也会假阳性）**：变异 M5「把 harness 里那行 `require(...)(__dirname)` 注释掉」
  **第一轮没被抓**（退出码 0）—— 原因是我那条检查写的是 `te.indexOf('require("./tests/checks/X.js")(__dirname)') < 0`：
  **注释掉的行文本里照样含这串子串**，`indexOf` 直接命中 ⇒ 检查以为「接线还在」。
  【修法】改成**按行精确匹配**：`te.split(/\r?\n/).map(l => l.trim())`，要求存在一行**以该调用串开头且不是注释**（`l.indexOf(need) === 0 && l.indexOf('//') !== 0`）。
  【通用教训】凡是「检查某段代码在不在」的源码检查，**一律锚到「可执行的那一行」**，不要用裸 `indexOf` 找子串 ——
  注释、字符串字面量、别处的同名调用都会让它**假阳性**（这与第五节的「锚点唯一定位」是同一条纪律，只是这次骗过检查的是**注释**）。
- **一个真实的插曲（值得记）**：变异脚本第一版被 120s 超时杀掉，**M3 的变异残留在工作树里没还原**；下一轮脚本的**基线检查当场把它抓出来**（`TOOL TEST FILES CHECK: FAIL - 没有用共用的 EVAL_TEST_EQ`）⇒ 说明这道源码检查真的在守。教训：变异脚本要给足时间（跑一次 test_engine 约 10s，13 次跑不完），并且**每轮先验基线**。

**⑥k 从常驻卷迁入的「索引任意全局 / 父子链扫描」原文（1.74.34 迁入，为测试规范腾预算）**
- ★★★**索引「任意全局」/ 走父子链的扫描，动手前先看参考卷附录 R15**（1.74.32 真机栽过一整轮）：① 索引前先过守卫（**不可索引的 userdata** 会抛错、**打断整个探针**；只收 `GetObjectType()=="Frame"`）；② **匿名窗口 `_G` 扫描永远看不到** ⇒ 只能靠 `GetChildren()` 父子链 + **具名子件当指纹**；③ 真机存档**带 BOM**、`a and f()` **只保留第一个返回值**、桩里 `unpack` 在 fengari **不存在** —— 都表现为「静默取不到值」。判据 = `DF GLOBAL SCAN GUARD CHECK` + 组 209/211/213。

**⑥l 从常驻卷迁入的「滚动/翻页/分页标准做法」原文（1.74.34 迁入，同上）**
- ★★★滚动/翻页/分页标准做法：三段 `[计数]`←8px→`[按钮组]`←10px→`[关闭]`；文字按钮（`IB_PREV/IB_NEXT`、`TB_UP/TB_DN`）、不用 ▲▼；几何唯一源 `EVAL_HELP_CFG_BOTTOM()`（`midY/closeLeft/closeW/rowY/rowH`；拿不到按 `-(H-10-11)`/`W-12-64` 回退）；判据＝中线==关闭中线、按钮组右端 ≤ 关闭左−4、真实 OnClick 能滚；读值口 `EVAL_IB_TEST_BOTTOM()`（组 92）/`EVAL_TB_TEST_SCROLL()`（组 118）。

**⑥m 拖拽模块（DragFrames）代码归属排查 + 测试整块归类（1.74.34 全案）**
- **用户原话**：「拖拽图层模块（DragFrames）代码也排查下归类到自身文件内。」
- **排查结论（代码侧：已经干净，不需要再搬）**：
  · `Toolbox.lua` 里与 DF 相关的**只剩 5 行**：4 行注释 + 1 行**模块行数据**
    `{ t = "mod", mod = "dragFrames", key = "dbgDrag", label = …, tip = … }`（上次已把 128 行界面接线搬进 `dfRow`）；
    `dragFrames.on` 主开关勾选框由**通用分支**渲染（该行不写 `noChk`）⇒ 工具箱里没有 `EVAL_DF_*` 这类模块内部件。
  · `EvalHelp.lua` 里 18 处 DF 引用**全是命令入口**（`/eh go 框体探针` · `开窗探针 [停|看]` · `框体图标`）：
    带 `type(EVAL_DF_*)=="function"` 守卫 + 模块没载入时**如实播报**，正是「入口只调模块函数」的合规形态，**不该搬**。
  · 结论：`tools/DragFrames.lua`（177 KB）已是自包含模块；工具箱/主插件各留**入口**，无实现残留。
- **测试侧：整块归类（这一轮真正做的事）**：
  · **断言组 18 个**（202/204/206~218/220~222，共 **161,424 字符 ≈ 158 KB**）从 `test_assert.lua` 逐字搬进 `tests/tools/DragFrames.lua`；
    搬迁用的切片口径 = 「`-- ===== 组 N` 标记 → 该组 `print("GROUP N …")` 之后那个独立成行的 `end`」
    （★不能用「到下一个标记为止」：**最后一组会一路吃到文件尾的 `print("ALL TESTS PASS")`**）。
  · **9 道 DF/DRAG 源码检查**（48 KB）搬进 `tests/checks/DragFrames.js`：ANCHOR ID · BARS WIRING · ROSTER WIRING · OPEN HOOK ·
    PROBE SAFE · GLOBAL SCAN GUARD · DRAG FRAMES WIRING · PICK WIRING · ICON ART；harness 里只留一行 `require(...)(__dirname)`。
    ★**TB MOD ROW CHECK 留在 test_engine.js**：它是「工具箱模块行」的**框架契约**（服务所有工具模块），不属于某一个模块。
  · 依赖核对（搬之前先静态查）：这 18 组对 `test_assert.lua` 的**顶层 local 依赖只有 `eq`** ⇒ 一行 `local eq = EVAL_TEST_EQ` 就够。
  · 搬迁代价（如实记）：**组 204 的前置夹具帧是组 202 造的**（全局 `pf`）⇒ 两组必须**保持原顺序**，这不是「搬完就自由排序」。
- **踩坑**：搬成独立文件后 `fs`/`path` 不在作用域里（原来是 `test_engine.js` 的模块级常量）⇒ `ReferenceError: path is not defined`。
  修法：在 `module.exports = function (root)` 里自己 `require("fs")`/`require("path")`（LayerFix.js 早就是这么写的，照抄即可）。
- **新判据 `DF GROUP ROSTER CHECK`（这一步的真正价值）**：把「拖拽模块的组号清单」钉在源码检查里——
  ① 组号集合必须与期望**完全一致**（多/少都 FAIL）；② 必须**升序**（顺序本身是契约，见上条依赖）；
  ③ 每组区间里必须**真的有 `eq(`**（「整组被删」「被掏空成只剩注释」都会当场变红）；④ 每组必须有 `print("GROUP <n> …: PASS")` 收尾行。
  ★为什么必须这样：行为断言与「跑到底握手」都只保证**文件被加载**，管不了「文件里的某一组没了」——那正是本项目最恨的静默失效；
  顺带把组 202 补上了原本缺失的 `GROUP 202 …: PASS` 行（它是唯一没有收尾行的组）。
- **变异验证（`tmp/mut_tests.js` 扩到 10 条，10/10 全捕获）**：新增 4 条针对拖拽模块——
  M7 整组删掉组 217（→ DF GROUP ROSTER CHECK）· M8 删掉组 217 的 PASS 收尾行（→ 同上）·
  M9 注释掉 harness 里 DragFrames 检查的 require（→ TOOL TEST FILES CHECK ②）· M10 注释掉 `EVAL_TEST_MOD_DONE("DragFrames")`（→ 跑到底对账 MODULE TESTS 1/2）。
- **闸门**：`luacheck.js` SYNTAX OK: **39** files（多出的正是新测试文件）· `test_engine.js` ALL TESTS PASS + `MODULE TESTS: 2/2（DragFrames, LayerFix）` + 3 道通用检查全绿，退出码 0。

**⑥n 「缩放大地图」行的 [设置] 下拉 = GUI重开（1.74.35-3 全案）**
- **用户原话**：「工具箱->缩放大地图右侧添加个设置 设置点击下拉->GUI重开 然后提示这个功能会有导致地图
  切换到其他地图后自动刷新到当前地图,,默认关闭.」
- **落地（按新规范：这一行的界面全在模块自己文件里）**：
  · `Toolbox.lua` 那一行由 `t = "c"` 改成 **模块行** `{ t = "mod", mod = "simpleMap", key = "simpleMap", … }`；
    ★顺手删掉两处旧特例：认不出来的死分支 `elseif it.t == "smap"`（模型里从没有这种行，且它走已废弃的子插件注册表）、
    以及勾选后的 `row.modelKey == "simpleMap"` 特例（模块行的 `r.set` 自己就做完「写配置 + 立刻应用/复位」）。
  · `tools/SimpleMap.lua` 交出 `smRow(r, it)`：**主开关勾选框**（真值 = `tbCfg().simpleMap`，读写 = `EVAL_SM_ENABLED/SET`）
    + **`[设置]` 多选下拉**（`EVAL_DD_OPEN(..., {multi=true, selected=sel, locked=locked, tips=tips})`，与 LayerFix/dfRow 同一套）；
    行内摘要 `缩放 0.70 · 透明 0.70 · GUI重开 关`（**现算**）+ tooltip 里把副作用原文摊开。
  · 菜单内容 = `EVAL_SM_MENU()`（`items/locked/tips/sel/keys`，唯一条目 **「GUI重开」**，`sel` 由真值现算 ⇒ 不留第二份状态）。
- **真值**：`SM_CFG.guiReopen`（nil/false = 关 = **默认关**；true = 开）；**一次性迁移**老键 `showGUI`（true/非空表 ⇒ 开，
  false/空表 ⇒ 关，nil ⇒ 什么都不写）后 **清掉老键**（与 1.74.29 清 keepUI 同一纪律）。
- **副作用为什么是真的（读 UnrealQuest 得到的机制，铁律 2）**：`Map/MapContext.lua` 的 `InspectPrimed()` 把
  `Client.IsGameUIHidden() == false` 当作「地图是关着的」信号，然后每 `RECENTER_SECONDS=2s` 调一次 `SetMapToCurrentZone()`，
  把大洲/世界层视图拉回当前地图（注释原文：「A player browsing a continent has the map open and is never overruled」）。
  我们在地图打开时重显 UIParent ⇒ 那条信号被打破 ⇒ 插件以为地图关着 ⇒ 浏览大洲时每 2 秒被拉回当前地图。
  ★所以：**默认关 + 提示必须写清**（中文提示里同时有「自动刷新」与「当前所在地图」两句，源码检查钉住这两句不许被删）。
- **测试三件套**：`tests/tools/SimpleMap.lua`（**组 224**：默认关/迁移四态/菜单 1 项与勾选态/**关掉时开图零动作、开着才发**/摘要现算/行登记同源/单一真值，
  夹具自建自清）＋ `tests/checks/SimpleMap.js`（**SM GUIREOPEN WIRING CHECK** + **SM GROUP ROSTER CHECK**）＋ 模块内读值口 `EVAL_SM_TEST_*`。
  ★「关掉时一个动作都不发」靠**计数器** `FEAT.guiCalls`（`featShowGUI` 内自增）——这才是行为断言照得到的事实。
- **顺手修掉的静默失效（本轮最有价值的发现）**：
  · **`tools/SimpleMap.lua` 从没被 harness 载入过**（`test_engine.js` 的 Lua 加载清单是**硬编码**的，只有 `tools/DragFrames/layerFix/…`）
    ⇒ 它的行为断言一直是盲区。★**新增模块文件必须同步这份清单**（与「9 处清单」同族）。
  · **四个工具模块裸调全局 `L(...)`**（LayerFix / DragFrames / RareWatch / SimpleMap）：项目里 `L` 一律是**文件局部**，
    全仓与游戏目录其它插件都没有全局 `L` ⇒ 调用要么报错、要么靠外部全局；在工具箱里还被 `pcall(fn, r, it)` **吞掉**，
    表现是「按钮文案没设上 / 点击处理器没挂」而那一行看着正常。修法 = 按 `ConsumableHelper/DismountHelper/HunterHelper` 的既有写法
    每个模块自带 `local function L(k, ...)`（走全局 `EVAL_L`）；判据 = 新增的 **`MODULE L SCOPE CHECK`**（`tools/*.lua` 只要调 `L(` 就必须自带）。
  · `TB MOD ROW CHECK` 的反向哨兵名单加了 **`EVAL_SM_`**（工具箱里不许再出现模块内部件）。
- **闸门**：`luacheck.js` SYNTAX OK: **40** files · `test_engine.js` ALL TESTS PASS + `MODULE TESTS: 3/3（DragFrames, LayerFix, SimpleMap）` +
  `SM GUIREOPEN WIRING CHECK` / `SM GROUP ROSTER CHECK` / `MODULE L SCOPE CHECK: 7 个模块` / `TB MOD ROW CHECK: 3 个模块行` 全绿，退出码 0；已同步进本机游戏目录（`SYNC OK: 67 + 4 个文件`）。

**⑥o 工具箱那几行的「配置项」移进 tooltip + 检查文件死代码（1.74.36 全案）**
- **用户原话**：「工具箱->以上UI工具的配置项.不需要再外部显示,已经在tooltip设置内显示了」（截图圈了「缩放大地图 缩放 0.70 · 透明 0.70 · GUI重开 关」与「图层特殊处理 已生效 1/1 项：动作条狮鹫」）。
- **改法**：`tools/SimpleMap.lua` 的 `smRow` 与 `tools/LayerFix.lua` 的 `lfRow` 去掉 `r.extra:SetText(...)+Show()`，改成显式 `r.extra:Hide()`；
  状态**不丢** —— 仍在 `tip.AddLine` 里现读（LayerFix 的 [设置]/[重置] 各一处、SimpleMap 的 [设置] 一处，含 GUI重开 副作用提示）；
  「图层拖拽柄」行本来就没写行上文本（只有 tooltip），无需改。
- **配套判据**：① 读值口 `EVAL_TB_TEST_ROW_TEXT` 增加 `extraShown`（否则「行上不显示了」断言不了）；
  ② 通用 **`TB MOD ROW CHECK ④`**：`tools/*.lua` 里出现 `extra:SetText` 即 FAIL（那一格是工具箱自己的 `t="l"` 列表行在用）；
  ③ 模块自查 `LF ROW SUMMARY CHECK` / `SM ROW SUMMARY CHECK`：行上不写 + 悬停里**必须**有当前配置（SM 还要有副作用提示）。
  ★断言跟着改：组 223 三条（行上不显示 / 悬停里有 / 重置后悬停跟着变）、组 224 新增两条（走**真实 OnEnter** 读真 GameTooltip 记账）。
- **★顺手抓到的死代码（值得单记）**：`tests/checks/LayerFix.js` 的导出函数开头是 `return (function () {…})();`
  ⇒ 后来追加在它**后面**的检查**永不执行**：文件里 grep 得到、日志里从不打印（新加的 `LF ROW SUMMARY CHECK` 就被吞了一整轮，是我另写一个 node 直跑该文件才发现的）。
  已去掉那个 `return`，并把判据加进 `TOOL TEST FILES CHECK`：「`tests/checks/*.js` 的导出函数体里不许有顶层 `return`」。
  【教训】「文件里有这行代码」≠「它会被跑到」—— 检查类代码同样要证明**它打印了**（本项目那条「少跑一个文件/一组 = 静默」的同族）。
- **并发写工作树的实况（记一笔，避免下次误判）**：本轮我编辑期间，`tools/SimpleMap.lua` 与 `tests/tools/SimpleMap.lua` 被**另一处同时写入**
  （新增 `1.74.35-4 叠加层「跟随地图缩放」自动适配`：`smFitApply` · `EVAL_SM_TEST_MAPFIT_TARGETS` · 跳过 12 张 `WorldMapDetailTile*` 底瓦片；组 225；默认开；节奏 0.1s 爆发 2s → 0.3s 稳态）。
  期间套件一度两处红（`SM GROUP ROSTER CHECK: 多了组 225` + 组 225 自断言失败），**都不是我这轮的改动**；
  ★我当时的处置：**不碰对方文件、不跑同步**（避免把半成品推进游戏目录），如实报告并请用户确认；用户回「那边修改完了」后复核 → 两闸门全绿、组 225 PASS、已同步。
  【教训】共享工作树里出现「我没写的符号/组号」时，先取证（mtime + 符号名 + 两个闸门输出）再动手，别急着「修好」别人未完成的中间态。

**⑥p 「缩放大地图」勾选框点不动 = 模块引用了宿主文件的 local（1.74.36-2 全案）**
- **用户报告**（截图）：工具箱 → 缩放大地图的勾选框**点了不会勾上**，聊天框却每次都打「[简易地图] 已启用（开图会自动应用…）」。
- **根因**：`tbCfg` 是 `Toolbox.lua` 的 **`local function`**；模块里写 `(type(tbCfg) == "function") and tbCfg() or nil` ⇒ 恒取 nil
  ⇒ `EVAL_SM_ENABLED()` 永远 false（勾选框读它）、`EVAL_SM_SET()` 的配置写入也永远不执行 ⇒ 每次点击都 set(true) 并播报「已启用」，**只有播报是真的**。
  ★为什么三个闸门全绿：① Lua 语法没问题（luacheck 绿）；② 行为断言测的是模块自己的纯函数，`EVAL_SM_SUMMARY()` 之类照旧对；
  ③ **组 224 里那条真值往返断言被自己的「跳过分支」吞了**（见下）。
- **顺带扫出的一整族**（同一根因，全都是「真机 nil、本地看不出来」）：`say`（Core.lua L77 与 Toolbox.lua L199 的 local）与 `logLine`（Core.lua L104 的 local）——
  DragFrames ~80 处、RareWatch ~30 处、LayerFix ~11 处、SimpleMap 2 处调它们 ⇒ **所有「如实播报」在真机上静默消失**（`pcall` 吞掉），
  这正是用户多次反馈「出错时什么提示都没有」的底层原因之一。注意 `P`（SimpleMap 自己的 local）与 `EVAL_SAY` 是好的，所以「有的行有输出、有的行全哑」。
- **修法**：
  · `Toolbox.lua` 在 `local function tbCfg()` 之后导出全局 `function EVAL_TB_CFG() return tbCfg() end`（配置真值只读出口）。
  · 四个模块各自补**文件局部** `say`/`logLine`，走 Core.lua 末尾的全局桥（`EVAL_SAY = say` / `EVAL_LOGLINE = logLine`，与 ConsumableHelper 的 chSay 同一写法）。
  · `SimpleMap` 的配置读写改走 `EVAL_TB_CFG()`；读不到时 `smTbCfg(false)` **如实播报一次**（把「开关不落存档」说出来，而不是继续假装成功）。
  · 组 224：`type(tbCfg)` 改成 `type(EVAL_TB_CFG)`，并**先把「跳过分支」删掉**（`（无 tbCfg，跳过）` 那个逃生口正是它让真机 bug 在套件里全绿）。
- **新判据 `MODULE HOST LOCAL CHECK`**：收集宿主（Toolbox/EvalHelp/Core/Engine）的全部 `local`/`local function` 名字（本轮 367 个），
  逐个比对 `tools/*.lua` 里的调用；模块**没自带同名 local** 却调用了 ⇒ FAIL（写明「跨文件只能是全局 nil」）。修完输出：`8 个模块都没有引用宿主文件的 local`。
- **测试纪律（用户同时定的，已进常驻卷）**：改完**默认只跑 `node luacheck.js`（<1s）**；`test_engine.js` **整轮实测 32 秒**，只在**碰到异常 / 改动接线**时跑。
  ★配套教训：语法闸门**照不到接线**——本轮就是 luacheck 全绿而勾选框点不动；所以「动了模块↔宿主接线 / UI 渲染 / 存档读写」时必须补跑一次测试台。

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
