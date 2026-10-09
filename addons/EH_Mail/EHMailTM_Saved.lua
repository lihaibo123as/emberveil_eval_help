-- EHMailTM_Saved.lua —— 把邮箱增强的存档收进两个真正的存档根
-- ============================================================================
-- ★★★为什么需要这个文件（真机红框换来的教训）：
--   本客户端的 `## SavedVariables:` **一行只认一个变量名**。写成
--       ## SavedVariables: A B C
--   时，客户端会把「A B C」整串当成**一个**超长名字写进存档文件，读回来就是
--       '=' expected near 'B'        ← 语法错，每次进游戏弹一个红框
--   ⇒ 所以 toc 里只能声明**两个**名字：账号级一个（EH_MAIL_CFG）+ 角色级一个（EH_MAIL_CHAR），
--     其余那些「原来各自独立的存档全局」只能作为它们的**字段**存在。
--
-- ★★★两个根各放什么（2026-10-10 用户定：「收件人设置账号级别存储. 同个账号都可直接复用」）：
--   `EH_MAIL_CFG`（账号级）= `tm_log` 邮件日志 · `tm_autoNames` 收件人自动补全 · **`tm_mailToList` 收件人历史**
--                              · `tm_panelOffset` / `tm_panelOffsetPF` 面板校准
--   `EH_MAIL_CHAR`（角色级）= `tm_to` 上次收件人 · `tm_point` 窗口位置（已不再写）·
--                              `tm_autoCOD` 自动到付 · `tm_panelHidden` 小窗收起
--   ★收件人历史为什么是账号级：那是「我常寄给谁」的通讯录，**同账号换角色照样用**；
--     日志同理（`tm_log` 一直就在账号级）。
--
-- ★★★怎么做到「零改动收容器」：
--   邮箱增强访问存档**几乎全走 `m.api.X`**，而 `m.api = getfenv()`（= 全局环境）⇒
--   把一个**代理表**交给 `m.api`（改动只有 EHMailTM.lua 里那一行），
--   代理的 `__index` / `__newindex` 把下面 MAP 里的名字转发到 CFG / CHR 的字段上。
--   ⇒ 那 20+ 处 `m.api.EHMailTM_Log` / `m.api.EHMailTM_To = …` **一个字都不用改**，
--     读写都落在两个存档根里，客户端自然会保存。
--
-- ★裸访问的那几个：`MailTo.lua` 里 11 处 `EHMailTM_MailToList` 不走 `m.api` ⇒
--   对**表类**直接做别名绑定（表是引用 ⇒ 别名与容器字段共享同一张表）。
--   简单值类**没有**裸访问（已用 `tmp/tm_saved_scan.js` 逐个核过）⇒ 不需要别名。
--
-- ★代理只拦 MAP 里的名字，其余全局（CreateFrame / SlashCmdList / 客户端帧 …）照旧走 `_G`，
--   所以「按名顶掉客户端全局」那类写法（如 `m.api.SendMailMailButton = …`）行为不变。
--
-- ★★★2026-10-10 真机报障（收件人历史「添加成功、/reload 后没了」）—— 本文件改了两处：
--   ① **容器根一律「用的时候现读全局」**（`_G[ "EH_MAIL_CFG" ]`），不再在文件执行期抓住引用：
--      本项目有老雷 —— 文件执行期读存档可能拿到**空表**，客户端**随后**才把真表换到那两个全局上，
--      抓住的引用就成了**孤儿表**（写进去永远不落盘）。
--   ② **裸别名在 `VARIABLES_LOADED` 再确认一次**（幂等 + 把旧表已有数据并进新表），
--      这样无论客户端在哪一刻换表，别名最终都指向**真正的存档表**。
--
-- ★★★2026-10-10 第二个要求（收件人历史改账号级）—— 本文件再加一段：
--   **从角色级一次性迁移**（`migrateMailToList`）：老存档的历史在 `EH_MAIL_CHAR.tm_mailToList`，
--   搬到账号级之后旧位置会**清空**（避免数据分家、也避免下次重复搬）。
--   迁移只补不覆盖、跳过非字符串垃圾、同服去重、搬完排序；在**两个时机**各跑一次（文件执行期 +
--   `VARIABLES_LOADED`）且**幂等** ⇒ 无论客户端哪一刻换表都能搬到。
-- ============================================================================

local function root(key)
  local t = _G[key]
  if type(t) ~= "table" then
    t = {}
    _G[key] = t
  end
  return t
end

local function tbl(rootKey, key)
  local r = root(rootKey)
  if type(r[key]) ~= "table" then r[key] = {} end
  return r[key]
end

root("EH_MAIL_CFG")
root("EH_MAIL_CHAR")

-- ---- 表类：容器字段建好，并把**裸全局**指到同一张表（引用共享）----
-- ★哪些裸全局需要别名 = 只有走不到 `m.api` 的那几处（`MailTo.lua` 的收件人历史）
local ALIAS = {
  { "EHMailTM_Log",               "EH_MAIL_CFG",  "tm_log" },
  { "EHMailTM_AutoCompleteNames", "EH_MAIL_CFG",  "tm_autoNames" },
  { "EHMailTM_MailToList",        "EH_MAIL_CFG",  "tm_mailToList" },
}

-- 重绑时把旧表里已有的数据并进新表（只并第一层，够用；避免重绑丢掉会话内刚写的数据）
local function mergeInto(dst, src)
  if type(src) ~= "table" then return end
  for k, v in pairs(src) do
    if dst[k] == nil then dst[k] = v end
  end
end

-- ★★★收件人历史：角色级 → 账号级 的一次性迁移（幂等；搬完清旧位置）
local function migrateMailToList()
  local chr = root("EH_MAIL_CHAR")
  local old = chr.tm_mailToList
  if type(old) ~= "table" then return end
  local dst = tbl("EH_MAIL_CFG", "tm_mailToList")
  for srv, names in pairs(old) do
    if type(names) == "table" and type(srv) == "string" then
      if type(dst[srv]) ~= "table" then dst[srv] = {} end
      for i = 1, table.getn(names) do
        local nm = names[i]
        -- ★只搬「非空字符串」：老存档里混进过帧对象/数字之类的东西，搬过去只会把下拉弄脏
        if type(nm) == "string" and nm ~= "" then
          local dup = false
          for k = 1, table.getn(dst[srv]) do
            if dst[srv][k] == nm then dup = true end
          end
          if not dup then table.insert(dst[srv], nm) end
        end
      end
      table.sort(dst[srv])
    end
  end
  chr.tm_mailToList = nil
end

-- ★唯一绑定口（幂等）：文件执行期先绑一次，`VARIABLES_LOADED` 再确认一次
function EHMailTM_SavedBind()
  for i = 1, table.getn(ALIAS) do
    local name, rk, key = ALIAS[i][1], ALIAS[i][2], ALIAS[i][3]
    local dst = tbl(rk, key)
    local cur = _G[name]
    if cur ~= dst then
      if type(cur) == "table" then mergeInto(dst, cur) end
      _G[name] = dst
    end
  end
  migrateMailToList()
end

EHMailTM_SavedBind()

-- 客户端换表之后再确认一次（本项目老雷：文件执行期的存档表可能随后被替换）
local bindFrame = CreateFrame("Frame")
bindFrame:RegisterEvent("VARIABLES_LOADED")
bindFrame:SetScript("OnEvent", function() EHMailTM_SavedBind() end)

-- ---- 存档键 → 容器字段（代理按这张表转发；根名用**字符串**，取的时候现读全局）----
local MAP = {
  EHMailTM_Log               = { "EH_MAIL_CFG",  "tm_log" },
  EHMailTM_AutoCompleteNames = { "EH_MAIL_CFG",  "tm_autoNames" },
  EHMailTM_MailToList        = { "EH_MAIL_CFG",  "tm_mailToList" },
  EHMailTM_PanelOffset       = { "EH_MAIL_CFG",  "tm_panelOffset" },
  EHMailTM_PanelOffsetPF     = { "EH_MAIL_CFG",  "tm_panelOffsetPF" },
  EHMailTM_To                = { "EH_MAIL_CHAR", "tm_to" },
  EHMailTM_Point             = { "EH_MAIL_CHAR", "tm_point" },
  EHMailTM_AutoCOD           = { "EH_MAIL_CHAR", "tm_autoCOD" },
  EHMailTM_PanelHidden       = { "EH_MAIL_CHAR", "tm_panelHidden" },
}

-- ---- 代理：只拦上表里的名字，其余全局照旧 ----
EHMailTM_SAVED_PROXY = setmetatable({}, {
  __index = function(_, k)
    local e = MAP[k]
    if e then return root(e[1])[e[2]] end
    return _G[k]
  end,
  __newindex = function(_, k, v)
    local e = MAP[k]
    if e then root(e[1])[e[2]] = v else _G[k] = v end
  end,
})
