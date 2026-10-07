# EH_Damage 子插件记忆体（铁律 / 判据 / 锚点）

> ★本文件 = **EH_Damage 自己的记忆体**（与宿主 `CLAUDE.md` 分目录存储，用户定）。
> · 面向使用者 = 同目录 `README.md`；逐版本改动 = 同目录 `CHANGELOG.md`。
> · 宿主 `CLAUDE.md` 的通用铁律照旧适用（`node luacheck.js` 闸门 · 不许子代理 · 答复中文 · 改完同步 · 不自动提交…），本文件不重复。

## 本目录构成与同步

| 文件 | 作用 |
| :-- | :-- |
| `EH_Damage.lua` | 主实现（配置 / 动画槽池 / 事件解析 / 编辑模式模拟战斗 / 配置面板 / 命令） |
| `EH_Damage.toc` | 载入清单 + `## Version` + `## SavedVariables: EH_DAMAGE_CFG` |
| `README.md` / `CLAUDE.md` / `CHANGELOG.md` | 使用者说明 / 本文件 / 改动记录（`0.1.x` ↔ 宿主 `1.75.y`） |

★本子插件**没有 `media\`**（不需要素材）。★同步 = `node sync_game.js`（整目录拷到插件同级）+ `node tmp/verify_sync.js` 逐字节核对。

## 判据正文

- ★★★**事件源只能是 SCT 模式（CHAT_MSG_ 文本解析）**：本客户端无 Nampower 结构化战斗事件、无 GUID API、
  姓名板非 Lua widget（三轮调研定案，见宿主 CLAUDE.md 与 `tmp/DamageEx for Nampower 2026-04-16` 分析）。
  ⇒ ① 事件名与文本格式**不许猜**（铁律 5）：模式表是 zhCN 尽力而为，未识别的战斗文本走**捕获环**
  （`/edmg 捕获` 开 → 原文落 `EH_DAMAGE_CFG.ring` 有界 40 → `/edmg 事件` 查看）供真机逐条校准；
  ② **绝不引入** `GetUnitGUID`/姓名板附着/TargetLine 这类 Nampower 依赖（反向钉）。
- ★★★**动画 = 绝对时间驱动**（`t = now - t0`，与帧率无关）：smoothstep 淡入淡出 `t*t*(3-2*t)`（前 10% 入 / 后 50% 出）·
  暴击 = 0.35s 窗口内抬一档字号（0.2.0 起；旧「三段缩放」随字号机制一起作废）· 彩虹弧线 `y = y0 + 240t − 200t²`
  （0.2.1 加高：峰值 ~72px · 0.6s 到顶 · 落到锚点以下；旧 `140t − 240t²` 峰值仅 ~20px）+ 侧漂。
- ★**滚动方向 8 种**（0.2.2，`DIRS`/`DIR_ZH` 两表同步是判据）：up / down / arc / angleUp（斜上抛物）/
  angleDown（斜下抛物）/ horiz（水平散开）/ sprinkler（洒水散开，分段：0.3s 斜喷→缓升微摆）/ sine（正弦上升）；
  全部 `t` 绝对时间驱动（★别退回 DamageEx 的逐帧累加写法 —— 帧率一变手感就变）；新增方向必须进两表 + harness ④d 位移签名钉。
- ★★★**防重叠 = 新字恒从锚点出发**（0.1.2 重写；真机报障「技能伤害定位越来越高」换来的）：先到的字已漂走、天然不叠；
  只有「同一瞬间连发」（同车道最近一条**当前 y** 离锚点不足一个行距）才往上/下摞一格 —— 判据从活动槽的
  **`s.cy`（当前 y）** 现算，槽出生即写 `s.cy`（复用槽不吃上一条命的残值）。★**反向钉：绝不许再用「黏性游标
  只有车道全空才复位」那版**（连续战斗时车道永远不空 ⇒ 每条 +行距 ⇒ 无限爬高）。回归钉 = harness ④b 三条。
- ★★★**关断四件事**（宿主 §4.1 尺子）：关总开关 `D.setMaster(false)` = ① 槽全收（`slotReleaseAll`，1.12 无销毁 API ⇒ Hide+清账）
  ② 节拍真摘（唯一入口 `beatSync`，`SetScript(D.frame,"OnUpdate",nil)`；再开重挂同一 handler，不用 /reload）
  ③ 数据重置（游标/拖拽/低血武装复位）④ 图层清理（编辑锚点 Hide + 摘全部事件 `eventSync`）。
  判据 = `tmp/ehdmg_harness.js` ⑩ 组（关后 `addText` 被拒 / 节拍 nil / 事件摘除 / 再开全恢复）。
- ★★★**记忆体分离**（宿主契约 ②）：本插件**只**读写 `EH_DAMAGE_CFG`；文件里**一个字都不许提**
  `EVAL_HELP_CONFIG` / `EVAL_HELP_CHAR`（`tmp/ehdmg_wiring_check.js` 有钉）。
- ★★★**资源独立性（0.2.x 全仓审计定案）**：本插件**零外部插件资源依赖** —— 引用的全部是**客户端内建资源**
  （`Interface\Buttons\WHITE8X8` · 客户端 Fonts 目录 · Fonts.xml 分档字体对象 · `GetSpellTexture` 图标库 ·
  `GameFontNormalSmall` 模板），**对宿主插件路径与 `EVAL_HELP_*` 全局零引用**。★判据：客户端内建资源**不复制**
  （复制 = 冗余）；今后若新增对任何**插件侧**素材的依赖（含宿主 media），一律先复制进本目录 `media\` 再引用，
  并把依赖写进本节；`EVAL_EDMG_*` 全局口是本插件自定义，不是宿主桥。
- ★★★**Lua 模式的多字节陷阱**：`?`/`-` 等量词按字节作用 ⇒ 「了?」会切掉半个汉字（宿主老坑）⇒
  可选字一律**写两条模式分别试**（锚点 = `CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS` 处理器里的注释）。
- ★★★**字号终案 = 分档字体对象**（0.2.0，探针 A~K 真机定案）：「改字号」（SetFont 路径+号 / SetTextHeight /
  帧缩放 / Button:SetText / MessageFrame）在本客户端**全部无效**，但 Fonts.xml **分档字体对象**有效（I<J<K 梯度）
  ⇒ 档位制 `D.TIER` 小/中/大/特大：**特大档数字行（`KIND_NUMERIC`）走 `NumberFontNormalHuge`（最大、数字优化、
  可能缺中文字形）、中文行走 `GameFontNormalHuge`**，缺字体对象降档兜底；暴击 = 0.35s 窗口内抬一档（封顶特大）；
  行距 = `D.TIER_H[tier]`。★反向钉：不许再退回任何「改字号」写法当主机制；档位语义只经 `sizeApply(fs, tier, kind)`。
  探针 `/edmg 字号探针`（A~K 样本）保留作诊断，别删。
- ★**显示项真值** = `EH_DAMAGE_CFG["it_"..id]`（15 项 + incoming 附加项，默认照暴雪「浮动战斗信息」截图）；
  唯一写口 = 配置面板勾选 / 恢复默认按钮；kind→显示项的门 = `KIND_ITEM` 表（**新 kind 必须进表**，否则不受开关管）。

## 本子插件专属闸门（`tmp/`，只在统一推送时跑）

| 脚本 | 作用 |
| :-- | :-- |
| `tmp/ehdmg_harness.js` | 离线真跑（fengari）：载入零副作用 · VLA 武装 · 动画推进 · 事件解析 · 捕获环 · 编辑模式 · 关断四件事 |
| `tmp/ehdmg_wiring_check.js` | 接线结构钉（五处契约 + 记忆体分离 + 一个节拍帧） |

★功能修改过程中只跑 `node luacheck.js` + `node sync_game.js`；那一轮不得声称「过了全套闸门」。

## 发布打包

· 独立打包两份：`EH_Damage-v<子版本>.zip` + 固定名 `EH_Damage.zip`（子版本现读 toc `## Version`）；
进包 = toc 列的 `.lua` + `README.md` + `CHANGELOG.md`；不进包 = `CLAUDE.md`。规矩全文 = 宿主 `CLAUDE.md` §4.3。
