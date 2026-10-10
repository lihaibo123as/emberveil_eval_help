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
