# Emberveil 官方插件平台 · 发布与编辑流程

> 独立记忆体（与 `kook/CLAUDE.md` 同一档：**子系统自身管理的记忆**，宿主 `CLAUDE.md` 只留指针）。
> 实测时间 **2026-10-10**，操作人账号 `lihaiboas1`（平台显示名 `LIHAIBOAS1`）。
> 站点 = Laravel + Livewire 渲染（按钮全是 `wire:click`，**不是普通表单提交**）。

## 一、入口 URL

| 用途 | URL |
| --- | --- |
| 插件市场（公开） | `https://emberveil.org/wiki/addons` |
| **我的插件**（自己发布的清单） | `https://emberveil.org/wiki/addons/mine` |
| 提交插件（新建，空表单） | `https://emberveil.org/wiki/addons/submit` |
| 打包指南 | `https://emberveil.org/wiki/addons/guide` |
| 某个插件详情页 | `https://emberveil.org/wiki/addons/<slug>` |
| **编辑某个插件** | `https://emberveil.org/wiki/addons/<slug>/edit` |

★ 登录后导航栏「资料」下拉里才会出现 **My Addons / My Profile**（未登录看不到）。

## 二、登录与「免登录」凭据

- 凭据文件（**全部在 `token/`，该目录已被 `.gitignore` 忽略，绝不入库**）：
  - `token/emberveil_login.json` —— 账号 / 密码 / 登录步骤 / 判据（本文件是操作手册）
  - `token/emberveil_cookies.json` —— 登录 Cookie 备份（`browser_auth restore` 可直接吃这个数组）
- **登录三步**（实测约 10 秒，全程无需人工）：
  1. 打开 `https://emberveil.org/login`
  2. `browser_fill` 填 `input[placeholder="Enter your username"]` / `input[placeholder="Enter your password"]`
  3. 等 1~2 秒 ⇒ `input[name="cf-turnstile-response"]` 的 `value` 长度变成 **~816** ⇒ 点文本为 `LOG IN` 的按钮
- **登录成功判据**：导航栏出现 `LIHAIBOAS1` + 出现 `捐助/Donate`，并且不再有 `Login / Register`。
- ★ **Cloudflare Turnstile 是隐形自动过**：本机会卡在「正在验证…」几秒，**不要**当成人工验证去叫人点；轮询令牌长度即可（首次约 8 秒、第二次 1 秒）。
- ★★ **登录态本身会落盘在浏览器 profile**：`%APPDATA%\dsh-builtin-browser-host\Network\Cookies`，
  实测**关掉标签页 + `Stop-Process electron` 之后重启浏览器仍保持登录**（3 条 Cookie 都是 `is_persistent=1`）。
  所以「免登录」的第一层保障 = **别删这个 profile**；第二层 = `token/emberveil_cookies.json` 兜底 restore。
- Cookie 三条（2026-10-10 导出）：`emberveil-session`（httpOnly，**约 2 小时过期**）· `remember_account_<hash>`（**约 1 年**，免登录主力）· `XSRF-TOKEN`。
- ★ **导出 Cookie 的复算方法**（profile 被清空时重建）：
  1. 关掉浏览器（`Stop-Process -Name electron -Force`）⇒ `Cookies` 数据库才不锁
  2. 复制 `%APPDATA%\dsh-builtin-browser-host\Network\Cookies`
  3. DPAPI 取密钥（`Local State` 的 `os_crypt.encrypted_key`，剥掉 5 字节 `DPAPI` 前缀 → `ProtectedData::Unprotect`）—— ★**要用 `powershell.exe`（5.1）**，`pwsh`(7) 里没有 `System.Security.Cryptography.ProtectedData` 类型
  4. `node:sqlite` 读库 + `aes-256-gcm`（`v10` 前缀：nonce 3~15、tag 末 16 字节）解密
  5. 脚本 = `tmp/emberveil_cookie_export.js`（★**SQL 里大整数列必须 `CAST(... AS TEXT)`**：`expires_utc`/`creation_utc` 超出 JS 安全整数，直选会抛 `ERR_OUT_OF_RANGE`）

## 三、我的插件清单（2026-10-10 · 5 个，全部 `已通过` + `已公开`）

| 显示名 | slug | 分类 | 下载 | 点赞 | 仓库点击 |
| --- | --- | --- | ---: | ---: | ---: |
| **EvalHelp 全职业一键宏,全任务装备检索,工具箱,宠物资料** | `addon` | 战斗 | 733 | 15 | 49 |
| EvalHelp -> EH_Damage · 增强伤害显示（浮动战斗信息） | `evalhelp-eh-damage` | 战斗 | 19 | 3 | 1 |
| EvalHelp -> EH_Bag · 整合背包 | `evalhelp-eh-bag` | 背包与物品栏 | 12 | 2 | 3 |
| EvalHelp -> EH_DPS · 队伍伤害统计（自娱自乐版） | `evalhelp-eh-dps` | 战斗 | 9 | 2 | 1 |
| EvalHelp -> EH_DebugBox · 图层调试 | `evalhelp-eh-debugbox` | 其他 | 7 | 3 | 2 |

（列表按下载量排序；各行"浏览量"均为 0。）

★ 主插件 slug 是 **`addon`**（平台默认 slug，历史遗留），不是 `evalhelp`。

## 四、编辑页表单字段（全量，`.../<slug>/edit`）

| 区块 | 控件 | 说明 / 约束 |
| --- | --- | --- |
| 顶部 | 文案 | 「可随时保存草稿；准备好后再**申请发布** ⇒ 由管理员审核，**当前公开版本一直保留**直到新版本通过」 |
| 预览 | 只读 | 实时渲染 markdown + 名称/描述长度计数（名称 `34/60`、描述按字符） |
| 分类 | `<select>` | 13 类：单位框体 / 动作条 / 战斗 / 地图与小地图 / 背包与物品栏 / 聊天 / 提示信息 / 专业技能 / 任务 / PvP / 界面与框体 / 其他 / 数据包 |
| 版本 | text | 占位 `例如 1.2.0 · 适用于 1.12.1`；★ 由下载链接**自动填入** |
| Git / 仓库链接 | url | **域名白名单**：`github.com` · `gitlab.com` · `bitbucket.org` · `codeberg.org` · `git.sr.ht` |
| **下载链接（必填）** | url | `https://…/Addon-1.2.0.zip`；**必须带版本号**（打了 tag 的发行版或文件名带版本），**严禁 `…/archive/HEAD.zip`** |
| 图标（推荐） | file | 不填则条目显示名称首字母 |
| 封面图（可选） | file | |
| 截图 | file ×最多 10 | 新图追加进列表，每张图角上有 `✕` 可移除 |
| 内容（多语言） | tab | `English` / `Español` / `Русский` / **`简体中文 • (主要)`** —— 先填主要语言再加翻译 |
| 插件名称 | text | **上限 60 字** |
| 描述 | textarea + Markdown 工具条 | `**加粗**` `*斜体*` `` `代码` `` `- 列表` `> 引用` `[文字](链接)`；前 ~160 字进 SEO/分享摘要 |
| 常见问题（可选） | 可重复行 | `wire:click="addFaq"` |
| 更新日志（可选） | 可重复行 | `wire:click="addChangelog"` |

## 五、动作（Livewire action 名 = 自动化锚点）

| 按钮 | `wire:click` | 语义 |
| --- | --- | --- |
| 保存草稿 | `saveDraft` | 存草稿，**不改公开版本** |
| 申请发布 | `requestPublish` | 提交管理员审核，旧公开版本继续生效直到通过 |
| 切换语言 | `switchLocale('en'\|'es'\|'ru'\|'zh_CN')` | |
| 删除（在我的插件页） | `deleteAddon(<id>)` + `wire:confirm` | ★**不可撤销**（连同全部版本/图片/点赞），弹确认框 |

## 六、我的插件页布局

每行 = 名称 + `已通过` / `已公开` 徽章 + 三个动作 **查看 / 编辑 / 删除** + 统计 `浏览量 · 仓库点击 · 下载 · 点赞`。
页面右上 = `插件`（回市场）· `提交插件`。顶部 = `我的插件` 标题。

## 七、用共享浏览器操作时的注意事项

1. **只读优先**：`保存草稿` / `申请发布` / `删除` 都会改线上数据 ⇒ 排查/查看阶段**一次都别点**。
2. 打开 `/edit` 时会**再报一次 Turnstile**（隐形，等几秒即可），页面元素在 `browser_open` 返回时可能还没渲染 ⇒ **等 4~6 秒**再 `browser_snapshot`。
3. 文件上传（图标/封面/截图）走 `<input type=file>`，共享浏览器**没有文件选择器接口** ⇒ 需要上传图片时让用户手动拖，或先确认工具是否支持。
4. `browser_fill` 对 Livewire（受控输入）有效；但 **Livewire 的 wire:model 需要 `input` 事件**（`browser_fill` 已发），改完值**不必手动触发**、直接点按钮即可。
5. 平台没有公开写 API（未验证）⇒ 自动化一律走 UI；**发布/编辑的自动化脚本若要长期用，锚点用上面那批 `wire:click` 名**（比中文按钮文本稳）。

## 八、与本地 release 流程的关系（未定，待用户拍板）

目前 release 只有到 **第 10 步 = 发 KOOK**。本平台是**第二条对外分发口**（下载量最大的一条：主插件 733 次）。
若用户要把它并入 release，口径应是：**版本变了的插件**才在 `/edit` 更新「版本 + 下载链接 + 更新日志」⇒ `保存草稿` ⇒ `申请发布`（等管理员审核，不是即时生效）。

---

## 九、已发布条目的实际形态（2026-10-10 实测）

★ 下载/仓库按钮都是**站内跳转**（`…/go/download`、`…/go/git`，点击计数就记在这里），真实地址要读 302 的 `Location`。
★ 复算脚本 = `tmp/emberveil_go_probe.js`（`fetch(..., {redirect:'manual'})`，**不下文件**）。

| 条目 | slug | 版本 | 分类 | 包大小 | 真实下载直链（`/go/download` →） |
| --- | --- | --- | --- | ---: | --- |
| EvalHelp 全职业一键宏,全任务装备检索,工具箱,宠物资料 | `addon` | `v1.75.110` | 战斗 | 63.81 MB | `…/releases/download/v1.75.110/EvalHelp.zip` |
| EvalHelp -> EH_Damage · 增强伤害显示（浮动战斗信息） | `evalhelp-eh-damage` | `v1.75.110` | 战斗 | 464.3 KB | `…/releases/download/v1.75.110/EH_Damage.zip` |
| EvalHelp -> EH_Bag · 整合背包 | `evalhelp-eh-bag` | **`v1.75.110_0.3.42`** | 背包与物品栏 | 224.0 KB | `…/releases/download/v1.75.110/EH_Bag.zip` |
| EvalHelp -> EH_DPS · 队伍伤害统计（自娱自乐版） | `evalhelp-eh-dps` | `v1.75.110` | 战斗 | 25.9 KB | `…/releases/download/v1.75.110/EH_DPS.zip` |
| EvalHelp -> EH_DebugBox · 图层调试 | `evalhelp-eh-debugbox` | **`v1.75.106`** | 其他 | 127.6 KB | `…/releases/download/`**`v1.75.106`**`/EH_DebugBox.zip` |

仓库直链（`/go/git` →）：主插件 = `https://github.com/lihaibo123as/emberveil_eval_help.git`；
子插件 = `…/tree/<审批时冻结的 commit>/addons/<名>`（EH_Bag `3b19ae01…` · EH_DPS `7ecf17a3…` · EH_DebugBox `1515fbe7…` · EH_Damage `d930b713…`）。

★ **四条要点（下次发布前必看）**：
1. 平台用的是**固定名包**（`EvalHelp.zip` / `EH_Bag.zip` …，不带版本号）—— 与本地 release 上传的「两份」对得上；版本号由**链接里的 tag** 决定，不由文件名决定。
2. **EH_DebugBox 还停在 `v1.75.106`**（其余四条已到 `v1.75.110`）⇒ 该条目**自 1.75.106 起没再更新过**。
3. **EH_Bag 的版本字段是双版本** `v1.75.110_0.3.42`（宿主_子插件），其余四条是单版本 —— 两种写法平台都收。
4. **EH_Mail 从未在本平台发布**（「我的插件」只有 5 个，5 个子插件里缺 EH_Mail）。
5. 页面上的 **SHA-256 + 字节数由平台在审批时冻结**（GitHub Release 附件直接读 GitHub 记录的哈希）；「下载已在审批时冻结到该提交」—— 所以**审核通过后绝不能替换同 tag 的同名包**。

★ 页面里各段的有无（现状）：**只有主插件有「更新日志」**（当前列 `v1.75.110` / `v1.75.106` 两条里程碑）+ **评论 26 条**（作者可回复/编辑/删除）；**子插件页一律没有更新日志、也没有常见问题**；五条都有「简介」与截图区。

## 十、子插件发布的内容规范

### A. 平台硬规则（原文见 `https://emberveil.org/wiki/addons/guide`，启动器按这套装包）

- **两个必填链接**：① 受支持托管平台的仓库（`github.com` / `gitlab.com` / `bitbucket.org` / `codeberg.org` / `git.sr.ht`）；② **同一仓库里带版本号的 `.zip` 直链**。禁短链 / 记 IP 的链接。
- **严禁 `…/archive/HEAD.zip`**：HEAD 每次都变 ⇒ 哈希失配 ⇒ 启动器拒装。要 `…/releases/download/<tag>/x.zip` 或文件名带版本号。
- **启动器流程**：HTTPS 下载 → 与记录的 SHA-256 校验（不符即拒）→ 解压 → 按 `Folder/Folder.toc` 找插件夹（`.toc` 直接位于同名夹内、大小写不敏感）→ 复制到 `Interface/AddOns/`。**目标已存在非启动器安装的同名夹 ⇒ 不覆盖并中止**（要先手动删）。
- **结构四条**：① 每个夹是 `Folder/Folder.toc`（没有同名 `.toc` 的夹被忽略）；② **文件夹名就是最终名**（别用容器夹包裹、别改名）；③ git-archive 会套一层 `repo-<ref>/` ⇒ **插件必须是仓库的子目录**（我们的 `addons/EH_<名>/` 天然满足；`.toc` 在仓库根目录 = 识别不出）；④ 多夹插件各自放 zip 根。
- **zip 里不许有**：`WTF/`、`SavedVariables`、`Cache/`、`.git`、插件夹以外的任何东西。
- **禁止条目名**：绝对路径 / 以 `/` 开头 / 盘符或 `:` / `..`；Windows 保留名 `CON PRN AUX NUL COM1–9 LPT1–9`（带扩展名也不行，如 `CON.toc`）；文件名不得以点或空格结尾、不得含控制字符或 RTL 字符；**插件夹名不得以 `Blizzard_` 开头**。
- **格式**：仅 `.zip`（stored=0 / deflate=8），**不支持 ZIP64 / 加密 / 分卷**，条目名 UTF-8。
- **大小**：下载 ≤ **64 MB**（**作为 GitHub Release 附件时 ≤ 2 GB** —— 只有这种情况服务器不下载、直接读 GitHub 记录的哈希）；解压后 ≤ 4 GB；单文件 ≤ 256 MB。
  ★ 我们主插件 **63.81 MB** 已贴近 64 MB 的非 Release 上限 ⇒ **必须继续走 GitHub Release 附件**（2 GB 档），别改成源码压缩包 / 别投到别的平台。
- **只安装游戏文件**：`.toc .lua .xml .blp .tga .wav .mp3 .ogg .ttf .m2`；README / LICENSE / 截图 / 构建脚本**不进 AddOns**；`.exe/.dll/.bat/.ps1/.py/.lnk/.url` 永不安装且会列给管理员。
- **媒体魔数校验**：`.blp` 以 `BLP` 开头、`.wav` 以 `RIFF`、`.ogg` 以 `OggS`，否则拒包。
- **审核比对**：GitHub 发行版会拿每个 `.lua/.xml/.toc` 与 **tag 处的仓库**比对，仓库里没有的文件会被标出 ⇒ **发行包必须从打了 tag 的提交构建**。
- **大数据包（>64 MB 语音/贴图/多语言）**：拆成**单独条目**，分类选 **「数据包」**；数据包**只许含 `.toc` + 媒体**（出现任何 `.lua`/`.xml` 直接不批）；数据包也要 `Folder/Folder.toc`，最简 `.toc` 写 `## LoadOnDemand: 1`；主插件描述里说明该装哪个数据包。**描述里的链接既不校验也不安装**。
- **提交后**：提交 → 人工审核 → 服务器校验下载（约 1 分钟，**期间不能编辑**）→ 启动器目录上线；之后任何改动 = 新修订版，**要重新审核**。

### B. 我们现有条目的文案约定（照抄这个模板，别自创）

★ **逐字原文案例集 = `doc/Emberveil插件平台-已发布内容存档.md`**（5 条发布原文 + 版本/大小/SHA-256/图片 URL；复算 `node tmp/emberveil_dump_published.js`，纯读）。写新条目时**先照案例集的句式抄**，再改成本插件的内容。

1. **标题** = `EvalHelp -> EH_<名> · <中文名>（<附注，可省>）`；主插件标题 = `EvalHelp 全职业一键宏,全任务装备检索,工具箱,宠物资料`。
2. **版本字段**：单版本写 `v<宿主版本>`（如 `v1.75.110`）；要带子插件版本就写 `v<宿主>_<子版本>`（EH_Bag 现为 `v1.75.110_0.3.42`）。
3. **分类**：战斗（EH_Damage / EH_DPS）· 背包与物品栏（EH_Bag）· 其他（EH_DebugBox）—— 按**子插件自身功能**选，不跟主插件。
4. **描述结构（子插件统一 5~6 段）**：
   - ① 首行 = `<EH_名> <中文名>子插件`（实测：`EH_Damage · 增强伤害显示（浮动战斗信息）` / `EH_Bag 整合背包子插件` / `EH_DPS · 队伍伤害统计（自娱自乐版）` / `EH_DebugBox 图层调试子插件`）
   - ② 📢 行（固定原文）：`📢 插件发布频道（KOOK）：emberveil 一键宏 · 插件发布 (www.kookapp.cn) —— 每次发布都在这里发帖（主插件与每个子插件各一条），帖内含更新概要、封面/截图与下载包链接。`
   - ③ 定位段：是什么 · 实现口径（如「事件解析走 SCT 模式，本客户端没有结构化战斗事件/GUID」）· 依赖与免责（如 EH_DPS 的「自娱自乐版：准确度不保证」）· 互斥说明（如 EH_Bag 与 OneBag/Bagnon 互斥、`/ebag force`）
   - ④ `打开方式`：宿主 EvalHelp → 配置窗 → **⑦ 子插件** → <组>勾选 → **重载界面**；命令入口（`/edmg` `/ebag` `/edps` `/edb`）
   - ⑤ `功能地图` / `界面构成` / `面板功能地图`：**逐项罗列**（勾选项数、参数档位、按钮、悬停、命令表用表格）
   - ⑥ （EH_Bag 那种自包含条目可加）「本插件是 EvalHelp 的独立子插件：自带 `.toc`、自带存档、自带三份文档（README / CLAUDE.md / CHANGELOG.md）」
5. **不做**：子插件页**不放更新日志、不放常见问题**（现状四条都没有；只有主插件放了 2 条里程碑）。
6. **图标 / 封面 / 截图**：页面有这三个上传位（现状五条都填了截图区）；截图最多 10 张。
7. ★ **描述是给人看的说明书，不是发布流水** —— 不写「本版改了什么」（那是更新日志/CHANGELOG 的事）。
