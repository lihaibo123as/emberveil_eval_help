EHMailTM = EHMailTM or {}
L = EHMailTM.L

local m = EHMailTM

-- ★★★0.3.17（用户定 = **子插件开发规范**）：「**子插件命名统一采用 EH_xxx 方式**」——
--   面向玩家的**播报前缀一律 = 插件目录名**（这里 = `[EH_Mail]`）。
--   ★本文件是从第三方插件（TurtleMail）整份搬来的 ⇒ `EHMailTM` 是**内部表名/文件名**，
--   只许出现在代码里（函数名、帧名、存档键前缀），**绝不许当聊天前缀** ——
--   用户截图里那行 `EHMailTM: Loaded (v0.3.16)` 就是反面例子。
--   ★唯一来源 = 这一个常量：聊天出口（`m.info` / `m.debug` / 帮助头一行 / `MailTo.lua` 的错误行）
--   全部读它 ⇒ 以后要改名只改这一处。
--   ★同目录的**探针部分**（`EH_Mail.lua`）本来就播 `[EH_Mail]` ⇒ 两部分现在同名同前缀。
m.ADDON_NAME = "EH_Mail"

local function get_realm_faction_key()
  local realm = "UnknownRealm"
  if m.api and m.api.GetCVar then
    local ok, r = pcall(m.api.GetCVar, "realmName")
    if ok and r and r ~= "" then realm = r end
  end

  local faction = "Unknown"
  if m.api and m.api.UnitFactionGroup then
    local ok2, f = pcall(m.api.UnitFactionGroup, "player")
    if ok2 and f and f ~= "" then faction = f end
  end

  return realm .. "|" .. faction
end

-- Optional: expose via m for convenience
m.get_realm_faction_key = get_realm_faction_key

local getn = table.getn 
local function pack( ... ) return arg end

local ATTACHMENTS_MAX = 21
local ATTACHMENTS_PER_ROW_SEND = 7
local ATTACHMENTS_MAX_ROWS_SEND = 3

local EHMailTM_SelectedItems = {} 
local INBOX_AUCTIONHOUSES = {
  [ "Stormwind Auction House" ] = true,
  [ "Alliance Auction House" ] = true,
  [ "Darnassus Auction House" ] = true,
  [ "Undercity Auction House" ] = true,
  [ "Thunder Bluff  Auction House" ] = true,
  [ "Horde Auction House" ] = true,
  [ "Blackwater Auction House" ] = true,
}

local FILTER_DEFS = {
  [ "Sold" ]     = { label = "拍卖成功", kind = "ah", value = "Sold" },
  [ "Won" ]      = { label = "一口价",   kind = "ah", value = "Won" },
  [ "Outbid" ]   = { label = "竞拍",     kind = "ah", value = "Outbid" },
  [ "Expired" ]  = { label = "已到期",   kind = "ah", value = "Expired" },
  [ "Removed" ]  = { label = "已取消",   kind = "ah", value = "Removed" },
  [ "Money" ]    = { label = "带钱",     kind = "money" },
  [ "Item" ]     = { label = "带附件",   kind = "item" },
  [ "COD" ]      = { label = "到付",     kind = "cod" },
  [ "Returned" ] = { label = "退信",     kind = "returned" },
  [ "Unread" ]   = { label = "未读",     kind = "unread" },
}

local function classify_ah_mail( subject )
  if not subject then return nil end
  local subj = string.gsub( subject, "|%s", "" )
  if string.find( subj, string.gsub( m.api.AUCTION_SOLD_MAIL_SUBJECT, "%%s", "" ) ) then
    return "Sold"
  elseif string.find( subj, string.gsub( m.api.AUCTION_REMOVED_MAIL_SUBJECT, "%%s", "" ) ) then
    return "Removed"
  elseif string.find( subj, string.gsub( m.api.AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", "" ) ) then
    return "Expired"
  elseif string.find( subj, string.gsub( m.api.AUCTION_WON_MAIL_SUBJECT, "%%s", "" ) ) then
    return "Won"
  elseif string.find( subj, string.gsub( m.api.AUCTION_OUTBID_MAIL_SUBJECT, "%%s", "" ) ) then
    return "Outbid"
  end
end

-- 竞得(Won)邮件的花费只在正文货币文本里（N金N银N铜），邮件头 money 恒为 0。
-- 单位可缺省（如只有银铜）；取正文第一处金额。5.0 无 string.match，用 string.find 捕获。
function EHMailTM.parse_body_money( body )
  if not body or body == "" then return nil end
  local pats = {
    "(%d+)金%s*(%d+)银%s*(%d+)铜",
    "(%d+)金%s*(%d+)银",
    "(%d+)银%s*(%d+)铜",
    "(%d+)金",
    "(%d+)银",
    "(%d+)铜",
  }
  for k = 1, getn( pats ) do
    local _, _, a, b, c = string.find( body, pats[ k ] )
    if a then
      local g = tonumber( a ) or 0
      local s = b and tonumber( b ) or 0
      local cp = c and tonumber( c ) or 0
      return ( g * 100 + s ) * 100 + cp
    end
  end
end

-- ★移植适配：改用「存档代理」而不是裸 getfenv() —— 本客户端 `## SavedVariables` 一行只认一个名字，
-- 所以那几个独立存档全局（EHMailTM_Log / _To / _PanelOffset …）必须作为 EH_MAIL_CFG / EH_MAIL_CHAR
-- 的字段存在；代理把它们的读写转发过去（见 EHMailTM_Saved.lua，它在本文件**之前**载入）。
-- ★代理只拦存档键，其余全局照旧走 _G ⇒ 拿不到代理时退回原写法（fail-open，绝不让插件因它挂掉）。
EHMailTM.api = EHMailTM_SAVED_PROXY or getfenv()
EHMailTM.timer = 0
EHMailTM.log = {}
EHMailTM.orig = {}
EHMailTM.hooks = {}
EHMailTM.hook = setmetatable( {}, { __newindex = function( _, k, v ) m.hooks[ k ] = v end } )
EHMailTM.debug_enabled = false
EHMailTM.mailable = {}

-- ★移植适配：本版**不含 pfUI 皮肤**（pfui-skin.lua 已整体剔除）⇒ 这个开关恒为 false，
-- 于是全文件所有「m.pfui_skin_enabled and <pfUI 值> or <原版值>」都自动走**原版 UI** 那一支。
-- ★刻意保留那些三元、而不逐处重写：它们另一半就是我们要的「原版保底值」。
m.pfui_skin_enabled = false

-- 1.12 无 GetItemLink，且 GetItemInfo 未回包时返回 nil，失败也要缓存空标记
EHMailTM.item_name_cache = {}

---@type Calendar
EHMailTM.calendar = m.Calendar.new()

function EHMailTM:init()
  self.debug( "EHMailTM.init" )
  self.update_frame = m.api.CreateFrame( "Frame", "EHMailTMFrame", m.api.MailFrame )
  self.update_frame:SetScript( "OnUpdate", self.on_update )

  -- Register events
  self.update_frame:SetScript( "OnEvent", function() self[ event ]() end )
  for _, event in { "ADDON_LOADED", "PLAYER_LOGIN", "UI_ERROR_MESSAGE", "CURSOR_UPDATE", "BAG_UPDATE", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_INBOX_UPDATE" } do
    self.update_frame:RegisterEvent( event )
  end

  -- ★移植适配（2026-10-10）：原版这里把 EHMailTM_Log **无条件整体覆盖**成默认值，
  -- 而它自己的注释写的是「仅对没有存档的新角色生效」⇒ **代码与注释不符**：
  -- 客户端是先把存档恢复成全局、再执行本文件 ⇒ 这次覆盖会把上一次的日志历史（Sent/Received）当场清掉。
  -- 改成「缺什么补什么」——没有存档才建默认值，有存档只补缺失的段。
  -- ★两种 SavedVariables 时机下都正确（先恢复 ⇒ 保住历史；后恢复 ⇒ 与原来等价）。
  local function tm_default_settings()
    return {
      -- 日志默认启用（新角色；已有存档沿用其保存的设置，可用 /tm log 切换）
      Enabled = true,
      SentFilters = { Money = 1, COD = 1, Other = 1 },
      ReceivedFilters = { Money = 1, COD = 1, Other = 1, Returned = 1, AH = 1, AHSold = 1, AHOutbid = 1, AHWon = 1, AHCancelled = 1, AHExpired = 1 }
    }
  end
  if m.api.EHMailTM_Log == nil then
    m.api.EHMailTM_Log = { Sent = {}, Received = {}, Settings = tm_default_settings() }
  else
    if m.api.EHMailTM_Log.Sent == nil then m.api.EHMailTM_Log.Sent = {} end
    if m.api.EHMailTM_Log.Received == nil then m.api.EHMailTM_Log.Received = {} end
    if m.api.EHMailTM_Log.Settings == nil then m.api.EHMailTM_Log.Settings = tm_default_settings() end
  end
  -- ★移植适配：同样不许无条件清掉自动补全的名字历史
  m.api.EHMailTM_AutoCompleteNames = m.api.EHMailTM_AutoCompleteNames or {}

  -- hack to prevent beancounter from deleting mail
  self.TakeInboxMoney, self.TakeInboxItem, self.DeleteInboxItem = m.api.TakeInboxMoney, m.api.TakeInboxItem, m.api.DeleteInboxItem

  self.tooltip_frame = m.api.CreateFrame( "GameTooltip", "EHMailTMTooltipFrame", nil, "GameTooltipTemplate" )
  self.tooltip_frame:SetOwner( m.api.WorldFrame, "ANCHOR_NONE" );
end

-- 1.12 无 UIDropDownMenu，筛选条件只能用按钮排
local CHECK_BOX = 16
-- 单元格：方框 16 + 间隙 4 + 文字 72（4 个汉字约 53px，加宽留出字体被放大的余量）
local CELL_W = 92
local PAD = 6
local ROW_H = 20
local ROW_GAP = 3
local FILTER_ROWS = 5
-- 面板左缘与邮箱外框右缘的间距
local PANEL_GAP = 4
-- 原版皮肤下 MailFrame 本体比可见装饰边框宽出一截（实测 MailFrame.R 467 而
-- 邮件列表 MailItem7.R 只有 411），拿 GetRight() 当锚点会留可见空隙。
-- pfUI 有 backdrop 能算出内缩，原版没有，用捞哥实测校准值（/tm paneloff 调出来的）。
-- /tm paneloff <dx> [dy] 可临时覆盖；/tm paneloff reset 回到下面这组默认值。
local PANEL_OFFSET_X = -38
local PANEL_OFFSET_Y = -12
-- pfUI 皮肤的默认校准值（捞哥实测），/tm paneloff 可临时覆盖
local PANEL_OFFSET_PF_X = 1
local PANEL_OFFSET_PF_Y = -5
-- pfUI 给整窗画的可见外框内缩量（pfUI/skins/blizzard/mail.lua:178-179：
-- TOPLEFT 12,-12 / BOTTOMRIGHT -30,72）。面板要贴的是这个可见边框，
-- 所以锚 MailFrame 本体时必须把这截内缩让掉。
local MAIL_INSET_TOP = -12
local MAIL_INSET_RIGHT = -30
-- 宽：PAD*2 + CELL_W*2 = 196，正好两列
local SIDE_PANEL_W = PAD * 2 + CELL_W * 2
-- 高：PAD + 4 行按钮(20+3) + 间隔 + 本页全选行 + FILTER_ROWS 行条件 + PAD
-- ★0.3.3：勾选框已还原到面板上（本页全选 + 两列筛选条件）⇒ 高度照原样算回来
local SIDE_PANEL_H = PAD * 2 + 4 * ( ROW_H + ROW_GAP ) + 8 + ( CHECK_BOX + 6 )
  + FILTER_ROWS * ( CHECK_BOX + ROW_GAP )

-- ★0.3.16（用户定）：「触发批量面板」那颗按钮要带**图标**。
--   ★★**占地保持原来的 22×26**（0.3.16 第一版加宽到 34 ⇒ 真机报障「超过界限」：按钮顶到邮箱可见边框外面）。
--   ★★**图标 = 自绘**（纯色纹理 `Interface\Buttons\WHITE8X8` + `SetVertexColor`）—— 本项目**唯一可靠**的贴图；
--     **不依赖任何图标路径**（第一版用宏图标 454 的路径 ⇒ 真机「图标未显示」，还画出一块占满按钮的红，
--     即「贴图加载失败」，本项目在案 = 「配好了却看不见 / 一次都没贴上过」那一族）。
--   ★这几个常量一律挂 `m` 表（本文件主 chunk 局部量有上限 ⇒ 不新增文件级 local）。
m.PANEL_TOGGLE_W = 22               -- 与加图标**之前**一模一样的占地（不许再加宽）
m.PANEL_TOGGLE_H = 26
m.PANEL_TOGGLE_ICON = 10            -- 自绘图标的外框边长（竖向居中）
m.PANEL_TOGGLE_TEX = "Interface\\Buttons\\WHITE8X8"
m.PANEL_TOGGLE_GOLD = { 1, 0.82, 0.25 }
-- 图标 = 6 条纯色纹理：**外框四条**（上下左右各 1px）+ **里面两条短横线** ⇒ 一眼是「面板 / 列表」。
-- 每条 = { 相对图标外框左上角的 dx, dy, 宽, 高 }；外框边长见 m.PANEL_TOGGLE_ICON。
m.PANEL_TOGGLE_BARS = {
  { 0, 0, 10, 1 }, { 0, 9, 10, 1 }, { 0, 0, 1, 10 }, { 9, 0, 1, 10 },
  { 2, 3, 6, 1 }, { 2, 6, 6, 1 },
}

---@param args string
function EHMailTM.slash_command( args )
  if args == "" or args == "help" then
    -- ★0.3.17：帮助头一行也用**统一前缀**（目录名），不再是内部表名
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cff66ccff[" .. m.ADDON_NAME .. "]|r " .. L[ "Help" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm log|r " .. L[ "Toggle logging on/off" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear sent|r " .. L[ "Clear sent log" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear received|r " .. L[ "Clear received log" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear names|r " .. L[ "Clear saved recipient names from autocomplete" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm take|r " .. L[ "Batch take all filtered mails" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm drop|r " .. L[ "Batch delete all filtered mails" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm return|r " .. L[ "Batch return all filtered mails to sender" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm filter <keys>|clear|r " .. L[ "Batch usage" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm paneloff <dx> [dy]|reset|r " .. L[ "Panel offset usage" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm panel|r " .. L[ "Panel layout diag" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm save|r " .. L[ "Panel offset saved" ] )
    -- ★0.3.10 起的测试指令（0.3.11 改成「附件选择列表」语义；见文件末尾那一节）
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100—— 附件选择列表 / 测试指令 ——|r" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm 发送背包 <N> [包]|r 背包第 1..N 格直接挂上并寄给当前收件人（不碰光标/客户端寄件栏）" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm 附件 …|r 附件选择列表（展示位置 = 发件页那排附件格）：状态|默认|加 <包> <格>|删 <包> <格>|设 …|清|显示|发|自动|偏移 <dx> <dy>" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffa0a0a0　· 右键背包物品 = 只加进列表 ｜ 右键附件格 = 只从列表删掉（都不碰光标、不动物品）|r" )
    return
  end

  -- 必须排在 ^panel 之前：这两条不吃 panel 前缀，但放前面读起来与帮助同序
  if string.find( args, "^发送背包" ) then
    m.cmd_sendbag( string.gsub( args, "^发送背包%s*", "" ) )
    return
  end

  -- `/tm 附件 …` 与 `/tm 多选 …` 是同一个命令体（0.3.11 起主名改成「附件」——它的语义已经是附件选择列表）
  if string.find( args, "^附件" ) then
    m.cmd_multi( string.gsub( args, "^附件%s*", "" ) )
    return
  end

  if string.find( args, "^多选" ) then
    m.cmd_multi( string.gsub( args, "^多选%s*", "" ) )
    return
  end

  -- 必须排在 ^panel 之前：paneloff 以 panel 开头，被它截胡就永远进不来
  if string.find( args, "^paneloff" ) then
    local rest = string.gsub( args, "^paneloff%s*", "" )
    -- 原皮肤 / pfUI 各用各的存档键，校准互不影响
    local dflt_x = m.pfui_skin_enabled and PANEL_OFFSET_PF_X or PANEL_OFFSET_X
    local dflt_y = m.pfui_skin_enabled and PANEL_OFFSET_PF_Y or PANEL_OFFSET_Y
    local store = m.pfui_skin_enabled and "EHMailTM_PanelOffsetPF" or "EHMailTM_PanelOffset"
    local cur = m.api[ store ] or { x = dflt_x, y = dflt_y }
    if rest == "reset" or rest == "复位" then
      -- 回落到当前皮肤源码默认值，清掉对应存档覆盖
      m.api[ store ] = nil
      cur = { x = dflt_x, y = dflt_y }
    elseif rest ~= "" then
      -- 1.12 只有 string.gmatch，string.gfind 根本不存在（pfUI 自己也写 gmatch or gfind 兜底）。
      -- 这里只用 string.find 手撸切词，不碰 gmatch/gfind，跨版本最稳。
      local parts, pos = {}, 1
      while true do
        local s, e = string.find( rest, "%S+", pos )
        if not s then break end
        tinsert( parts, string.sub( rest, s, e ) )
        pos = e + 1
      end
      cur.x = tonumber( parts[ 1 ] ) or cur.x
      cur.y = tonumber( parts[ 2 ] ) or cur.y
      m.api[ store ] = cur
    end
    if m.batch_panel then
      if m.batch_reanchor then m.batch_reanchor() end
      -- batch_settle 的 OnUpdate 会连帧 reanchor 30 次，命令后必须留够帧数才生效
      m.batch_settle = 30
      if m.batch_reanchor then m.batch_reanchor() end
    end
    m.info( string.format( "面板偏移 X=%d Y=%d", cur.x, cur.y ) )
    m.info( string.format( "|cffffd100pfui皮肤=%s 面板L=%s 邮箱R=%s|r",
      m.pfui_skin_enabled and "开" or "关",
      m.batch_panel and tostring( math.floor( m.batch_panel:GetLeft() or -1 ) ) or "?",
      m.api.MailFrame and tostring( math.floor( m.api.MailFrame:GetRight() or -1 ) ) or "?" ) )
    if rest ~= "reset" and rest ~= "复位" then
      m.info( "满意后敲 /tm save 确认；/tm paneloff reset 复位" )
    end
    return
  end

  if string.find( args, "^panel" ) then
    -- 布局诊断：直接读屏幕坐标，避免靠截图猜像素
    local function r( f )
      if not f then return "nil" end
      if not f.GetLeft then return "no-Geometry" end
      -- 用 GetRight/GetTop 而不是 L+W：backdrop 类 frame 的 GetWidth 会跟锚点不一致
      local l, b, rt, tp = f:GetLeft(), f:GetBottom(), f:GetRight(), f:GetTop()
      if not l then return "no-left(未显示)" end
      return string.format( "L=%.0f R=%.0f T=%.0f W=%.0f H=%.0f", l, rt, tp, rt - l, tp - b )
    end
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473-- 面板布局诊断 --|r" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100pfui皮肤=|r" ..
      ( m.pfui_skin_enabled and "|cff20ff20开（皮肤回调已跑）|r" or "|cffff6060关（当前原版皮肤）|r" ) )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100MailFrame|r      " .. r( m.api.MailFrame ) )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100MailFrame.bd|r   " .. r( m.api.MailFrame.backdrop ) )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100InboxFrame|r     " .. r( m.api.InboxFrame ) )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100InboxFrame.bd|r  " .. r( m.api.InboxFrame.backdrop ) )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100MailItem1|r      " .. r( m.api.MailItem1 ) )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100MailItem7|r      " .. r( m.api.MailItem7 ) )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100BatchPanel|r     " .. r( m.batch_panel ) )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100筛选按钮|r        " .. r( m.filterButton ) )
    -- 拍卖行/退信标记：XML 挂在 MailItemNExpireTime 下，用来核对它们有没有跑到窗外
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100AH图标1|r        " .. r( m.api.EHMailTMAuctionIcon1 ) )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100退信箭头1|r      " .. r( m.api.EHMailTMReturnedArrow1 ) )
    local mf = m.api.MailFrame
    local mfRight = mf and mf.GetRight and mf:GetRight()
    if mfRight then
      local inset = m.pfui_skin_enabled and MAIL_INSET_RIGHT or 0
      local ox, oy = 0, 0
      if m.pfui_skin_enabled then
        local off = m.api.EHMailTM_PanelOffsetPF
        if off then
          ox = off.x or 0
          oy = off.y or 0
        end
      else
        local off = m.api.EHMailTM_PanelOffset
        if off then
          ox = off.x or 0
          oy = off.y or 0
        else
          ox = PANEL_OFFSET_X
          oy = PANEL_OFFSET_Y
        end
      end
      m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cff20ff20BatchPanel.L 应≈" .. string.format( "%.0f", mfRight + inset + PANEL_GAP + ox )
        .. "（MailFrame.R " .. string.format( "%.0f", mfRight )
        .. " 内缩 " .. tostring( inset ) .. " + 间距 " .. tostring( PANEL_GAP )
        .. " + 校准X " .. tostring( ox ) .. " 校准Y " .. tostring( oy ) .. "）|r" )
    end
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cff808080backdrop 的 W/H 不可信，只看 L/B|r" )
    return
  end


  if string.find( args, "^save" ) then
    local off = m.api[ m.pfui_skin_enabled and "EHMailTM_PanelOffsetPF" or "EHMailTM_PanelOffset" ]
    if not off then
      m.info( string.format( "当前用源码默认值 X=%d Y=%d（无存档覆盖）|r",
        m.pfui_skin_enabled and PANEL_OFFSET_PF_X or PANEL_OFFSET_X,
        m.pfui_skin_enabled and PANEL_OFFSET_PF_Y or PANEL_OFFSET_Y ) )
    else
      m.info( string.format( "当前偏移 X=%d Y=%d 已在内存中。|r", off.x or 0, off.y or 0 ) )
      m.info( "|cffffd100要写入硬盘必须完全退出游戏（不是 /reload），否则会丢|r" )
    end
    return
  end

  if string.find( args, "^filter" ) then
    local rest = string.gsub( args, "^filter%s*", "" )
    m.batch_filters = m.batch_filters or {}
    if rest == "clear" or rest == "" then
      m.batch_filters = {}
      for key, btn in pairs( m.batch_filter_buttons or {} ) do
        pcall( btn.SetChecked, btn, false )
      end
      m.batch_preview_dirty = true
      m.batch_refresh_label()
      m.info( L[ "Batch filter cleared" ] )
      return
    end
    local set, invalid = {}, {}
    local gmatch = string.gmatch or string.gfind
    local defs = {}
    for k2, v2 in pairs( FILTER_DEFS ) do defs[ string.lower( k2 ) ] = k2 end
    for word in gmatch( rest, "%S+" ) do
      local lower = string.lower( word )
      local key = defs[ lower ]
      if key then
        m.batch_filters[ key ] = true
        tinsert( set, key )
        local btn = m.batch_filter_buttons and m.batch_filter_buttons[ key ]
        if btn then pcall( btn.SetChecked, btn, true ) end
      else
        tinsert( invalid, word )
      end
    end
    m.batch_preview_dirty = true
    m.batch_refresh_label()
    if getn( set ) > 0 then
      m.info( L[ "Batch filter set" ] .. " " .. table.concat( set, ", " ) )
    end
    if getn( invalid ) > 0 then
      m.info( "|cffff6060" .. table.concat( invalid, ", " ) .. "|r" )
    end
    return
  end

  if args == "take" then
    m.batch_start( "take" )
    return
  end

  if args == "drop" then
    m.batch_start( "delete" )
    return
  end

  if args == "return" then
    m.batch_start( "return" )
    return
  end

  if args == "log" then
    m.api.EHMailTM_Log[ "Settings" ][ "Enabled" ] = not m.api.EHMailTM_Log[ "Settings" ][ "Enabled" ]
    if m.api.EHMailTM_Log[ "Settings" ][ "Enabled" ] then
      m.info( L[ "Logging is enabled." ] )
      if m.api.MailFrame:IsVisible() then
        m.api.MailFrameTab3:Show()
      end
    else
      m.info( L[ "Logging is disabled." ] )
      if m.api.MailFrame:IsVisible() then
        m.api.MailFrameTab3:Hide()
      end
    end
    m.log_enabled = m.api.EHMailTM_Log[ "Settings" ][ "Enabled" ]
  end

  if string.find( args, "^clear" ) then
    if args == "clear sent" then
      m.info( L[ "Sent log cleared." ] )
      m.api.EHMailTM_Log[ "Sent" ] = {}
    elseif args == "clear received" then
      m.info( L[ "Received log cleared." ] )
      m.api.EHMailTM_Log[ "Received" ] = {}
    elseif args == "clear names" then
      m.info( L[ "Recipient autocomplete names have been cleared." ] )
      local key = get_realm_faction_key()
      m.api.EHMailTM_AutoCompleteNames[ key ] = {}
    end
  end

  if args == "debug" then
    m.debug_enabled = not m.debug_enabled
    if m.debug_enabled then
      m.info( L[ "Debug is enabled." ] )
    else
      m.info( L[ "Debug is disabled." ] )
    end
  end
end

function EHMailTM_selected_time() 
  m.selected_time = m.selected_time - 1
  m.inbox_update = true
end

function EHMailTM.on_update()
  if not m.api.MailFrame or not m.api.MailFrame:IsVisible() then return end

  -- 一次右键会连抛好几次 BAG_UPDATE/ITEM_LOCK_CHANGED，合并成每帧只重排一次附件区
  if m.sendmail_need_update then
    m.debug( "on_update: sendmail_frame_update" )
    m.sendmail_need_update = nil
    m.api.SendMailFrame_Update()
  end

  if m._cursorItem then
    m.debug( "on_update: cursorItem" )
    m.cursorItem = m._cursorItem
    m._cursorItem = nil
  end

  if m.sendmail_update then
    m.debug( "on_update: sendmail" )
    m.sendmail_update = nil
    if m.sendmail_sending then
      m.debug( "m.sendmail_sending" )
      m.sendmail_send()
    end
  end

  -- 右键收取的延迟队列：等发票就绪再开信（每封上限 150 帧兜底）
  if m.delayed_opens and getn( m.delayed_opens ) > 0 then
    local item = m.delayed_opens[ 1 ]
    item.frames = item.frames - 1
    if item.frames <= 0 then
      local _, _, _, subject = m.api.GetInboxHeaderInfo( item.i )
      local inv_ready = true
      if classify_ah_mail( subject ) == "Won" then
        local okI, _, _, _, invMoney = pcall( m.api.GetInboxInvoiceInfo, item.i )
        inv_ready = okI and invMoney and invMoney > 0
      end
      if not inv_ready and ( item.waits or 0 ) < 150 then
        item.waits = ( item.waits or 0 ) + 1
        m.api.GetInboxText( item.i )
        m.api.GetInboxInvoiceInfo( item.i )
      else
        tremove( m.delayed_opens, 1 )
        m.inbox_open( item.i, true )
      end
    end
  end

  if m.inbox_update then
    m.debug( "on_update: inbox_update" )
    m.inbox_update = false
    if m.batch_opening then
      m.batch_step()
    elseif not m.Mail_open_Selected then
      local  _, _, _, _, _, COD, _, _, _, _, _, _, isGM = m.api.GetInboxHeaderInfo( m.inbox_index )
      if m.inbox_index > m.api.GetInboxNumItems() then
        if m.money_received > 0 then
          m.info( string.format( "%s%s.", m.format_money( m.money_received ), L[ "collected" ] ) )
        end
        m.inbox_abort()
      elseif m.inbox_skip or isGM  or (m.api.EHMailTM_AutoCOD ~= 1 and COD > 0) then
        m.inbox_skip = false
        m.inbox_index = m.inbox_index + 1
        m.inbox_update = true
      else
        -- ★限频：接收所有邮件同样是逐封写动作（跳过/越界那些分支不算，不占闸）
        if not m.batch_rate_ok() then
          m.inbox_update = true
          return
        end
        m.inbox_open( m.inbox_index )
      end
    else
      -- 选择取件（批量取件/接收选择邮件共用）：
      -- 按邮件身份（发件人+主题）匹配而不是索引——取件会让列表索引漂移，
      -- 邮件一多索引必错（重复记录/读错邮件/金额错乱的根源），身份永远不漂。
      if not m.take_idents or getn( m.take_idents ) == 0 then
        if m.money_received > 0 then
          m.info( string.format( "%s%s.", m.format_money( m.money_received ), L[ "collected" ] ) )
        end
        if m.take_total and m.take_total > 0 then
          m.info( string.format( L[ "Batch done: %d" ], m.take_total ) )
        end
        m.take_total = nil
        m.money_received = 0
        m.inbox_opening = false
        m.Mail_open_Selected = false
        return
      end
      -- 上一封还没从列表消失就先等（150 帧等不到则跳过，防卡死）
      if m.take_wait_count and m.api.GetInboxNumItems() == m.take_wait_count and ( m.take_waits or 0 ) < 150 then
        m.take_waits = ( m.take_waits or 0 ) + 1
        m.inbox_update = true
        return
      end
      m.take_wait_count = nil
      m.take_waits = 0

      local ident = m.take_idents[ 1 ]
      local found, cod_amount = nil, nil
      local total = m.api.GetInboxNumItems()
      for i = 1, total do
        local _, _, sender2, subject2, _, cod2, _, _, _, _, _, _, isGM2 = m.api.GetInboxHeaderInfo( i )
        if not isGM2 and sender2 == ident.from and subject2 == ident.subject then
          found = i
          cod_amount = cod2
          break
        end
      end
      if not found then
        -- 这封已不在邮箱里（被其它操作收走/删除）：跳过
        tremove( m.take_idents, 1 )
        m.inbox_update = true
        return
      end
      if m.api.EHMailTM_AutoCOD ~= 1 and cod_amount and cod_amount > 0 then
        tremove( m.take_idents, 1 )
        m.inbox_update = true
        return
      end
      -- 竞得邮件的发票金额要等服务器回包：没就绪就继续预取再等（150 帧兜底），
      -- 否则落档时读到的还是 0 → "花费:?"
      local inv_ready = true
      if classify_ah_mail( ident.subject ) == "Won" then
        local okI, _, _, _, invMoney = pcall( m.api.GetInboxInvoiceInfo, found )
        inv_ready = okI and invMoney and invMoney > 0
      end
      if not inv_ready and ( m.inv_waits or 0 ) < 150 then
        m.inv_waits = ( m.inv_waits or 0 ) + 1
        m.api.GetInboxText( found )
        m.api.GetInboxInvoiceInfo( found )
        m.inbox_update = true
        return
      end
      m.inv_waits = 0
      -- ★限频：这条路径（接收选择邮件 / 批量取件）也发写动作，与上面共用同一个闸
      if not m.batch_rate_ok() then
        m.inbox_update = true
        return
      end
      -- manual=true：用户明确勾选要取的邮件一律记日志，未读也落档
      m.inbox_open( found, true )
      tremove( m.take_idents, 1 )
      -- 等这封真的消失再找下一封：防止身份扫描撞上还没消失的同一封
      m.take_wait_count = m.api.GetInboxNumItems()
      m.inbox_update = true
    end
  end

  if m.timer > 0 then
    m.timer = m.timer - 1
  elseif not m.inbox_opening then
    m.timer = 200
    m.api.CheckInbox()
  end
end

function EHMailTM.CURSOR_UPDATE()
  m.cursorItem = nil
end

function EHMailTM.get_cursor_item()
  return m.cursorItem
end

---@param item table
function EHMailTM.set_cursor_item( item )
  m._cursorItem = item
end

function EHMailTM.sendmail_queue_update()
  m.sendmail_need_update = true
end

function EHMailTM.BAG_UPDATE()
  if m.api.MailFrame:IsVisible() then
    m.sendmail_queue_update()
  end
end

function EHMailTM.MAIL_SHOW()
  -- ★0.3.3：不再恢复窗口位置（位置完全交给客户端与宿主工具，本插件不记也不写）

  if not m.first_show then
    m.first_show = true
    -- ★移植适配：本客户端这些控件的 region 数量**会随状态变**
    -- ⇒ 一律「够了才用」；另外**只调一次 GetRegions**（原写法调两次，两次之间数量可能不同）
    local pkgRs = { m.api.SendMailPackageButton:GetRegions() }
    local background = pkgRs[ 1 ]
    if background and type(background.Hide) == "function" then background:Hide() end
    local count = pkgRs[ 3 ]
    if count and type(count.Hide) == "function" then count:Hide() end
    m.api.SendMailPackageButton:Disable()
    m.api.SendMailPackageButton:SetScript( "OnReceiveDrag", nil )
    m.api.SendMailPackageButton:SetScript( "OnDragStart", nil )
  end

  if m.log_enabled then
    m.api.MailFrameTab3:Show()
  else
    m.api.MailFrameTab3:Hide()
  end

  m.timer = 0
  m.money_received = 0
  m.update_money( 0 )

  -- ★0.3.16：邮箱窗显示之后重申一次开关按钮的自绘视觉（「隐藏态写属性不落地」——
  --   建的时候窗还没显示，那时写的尺寸/锚点不生效；详见 `m.panel_toggle_apply_icon` 的说明）。
  if m.panel_toggle_apply_icon then m.panel_toggle_apply_icon() end
end

function EHMailTM.MAIL_CLOSED()
  m.inbox_abort()
  m.sendmail_sending = false
  m.sendmail_clear()
  -- ★★★0.3.15：**关邮箱 = 附件选择整体作废**（用户 2026-10-10 定：「在邮箱关闭之后.
  --   要做好背包内附件锁定清理的流程.」）—— 唯一清理口，见文件末尾那一节。
  --   ★必须在这里做：背包格上的「附件」遮盖（背包整合画的）与客户端自己那层「锁定/灰化」
  --     **都由这份选择列表派生**，而它们**谁都不会自己复位** ⇒ 不清就是「关了邮箱背包还锁着」。
  m.multi_release( "邮箱已关闭" )
end

function EHMailTM.UI_ERROR_MESSAGE()
  if m.inbox_opening then
    if arg1 == m.api.ERR_INV_FULL then
      m.inbox_abort()
    elseif arg1 == m.api.ERR_ITEM_MAX_COUNT then
      m.inbox_skip = true
    end
  elseif m.sendmail_sending and (arg1 == m.api.ERR_MAIL_TO_SELF or arg1 == m.api.ERR_PLAYER_WRONG_FACTION or arg1 == m.api.ERR_MAIL_TARGET_NOT_FOUND or arg1 == m.api.ERR_MAIL_REACHED_CAP) then
    m.sendmail_sending = false
    m.sendmail_state = nil
    m.api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
  end
end

function EHMailTM.ADDON_LOADED()
  -- ★移植适配：本插件现叫 EH_Mail，客户端发的 arg1 就是它
  -- （不改这一句 ⇒ 初始化一个字节都不执行：插件看着载入了却什么都没做）
  if arg1 ~= "EH_Mail" then return end

  local version = m.api.GetAddOnMetadata( "EH_Mail", "Version" )
  m.info( string.format( "Loaded (|cffeda55fv%s|r).", version ) )

  -- 日志一次性迁移：老角色存档里存的是关，本版本起强制开一次；之后 /tm log 的手动开关照旧尊重
  local log_settings = m.api.EHMailTM_Log[ "Settings" ]
  if log_settings.log_on_version ~= version then
    log_settings.log_on_version = version
    log_settings.Enabled = true
    m.info( "日志已默认启用，可用 /tm log 关闭。" )
  end

  if not m.api.EHMailTM_Log[ "Settings" ].first_run then
    m.api.EHMailTM_Log[ "Settings" ].first_run = version
    m.info( "New in |cffeda55fv1.4|r: Enable logging with |cffabd473/tm log|r" )
  end

  if m.api.UIPanelWindows[ "MailFrame" ] then
    m.api.UIPanelWindows[ "MailFrame" ].pushable = 1
  else
    m.api.UIPanelWindows[ "MailFrame" ] = { area = "left", pushable = 1 }
  end

  if m.api.UIPanelWindows[ "FriendsFrame" ] then
    m.api.UIPanelWindows[ "FriendsFrame" ].pushable = 2
  else
    m.api.UIPanelWindows[ "FriendsFrame" ] = { area = "left", pushable = 2 }
  end

  -- ★★★0.3.3 真机定案（用户）：**本插件不再提供任何窗口拖拽**。
  --   收件箱/写信页的空白处曾整片是拖拽热区（上游为了「背景处也能拖」把两个页面的鼠标全关掉，
  --   而本客户端只要按下有位移就起拖 ⇒ 用户报障「任意地方都会开始拖拽」）。
  --   ⇒ 拖窗口请用**宿主工具箱 → 拖拽图层**；本插件连标题栏柄也一并撤掉，位置也不再自己记。
  --   ★ 注册与处理体必须**一起**撤 —— 只撤处理体，空白处照旧起拖；只撤注册，处理体留着等别人触发它。
  m.api.MailFrame:SetMovable( true )
  pcall( m.api.MailFrame.RegisterForDrag, m.api.MailFrame )
  m.api.MailFrame:SetScript( "OnDragStart", nil )
  m.api.MailFrame:SetScript( "OnDragStop", nil )
  m.api.MailFrame:SetClampedToScreen( true )
  m.api.PanelTemplates_SetNumTabs( m.api.MailFrame, 3 )

  m.inbox_load()
  m.sendmail_load()
  m.log.load()
  m.batch_load()
end

function EHMailTM.PLAYER_LOGIN()
  m.debug( "PLAYER_LOGIN" )
  for k, v in m.hooks do
    m.orig[ k ] = m.api[ k ]
    m.api[ k ] = v
  end
	local key = get_realm_faction_key()
	m.api.EHMailTM_AutoCompleteNames[ key ] = m.api.EHMailTM_AutoCompleteNames[ key ] or {}

	for char, last_seen in pairs( m.api.EHMailTM_AutoCompleteNames[ key ] or {} ) do
	  -- 用 time()（Unix 时间戳）而非 GetTime()（会话秒数，重载即归零，跨会话比较无意义）
	  if time() - last_seen > 60 * 60 * 24 * 30 then
		m.api.EHMailTM_AutoCompleteNames[ key ][ char ] = nil
	  end
	end

  m.add_auto_complete_name( m.api.UnitName( "player" ) )
  m.log_enabled = m.api.EHMailTM_Log[ "Settings" ][ "Enabled" ]

  SLASH_TURTLEMAIL1 = "/ehmail"
  SLASH_TURTLEMAIL2 = "/tm"
  m.api.SlashCmdList[ "TURTLEMAIL" ] = m.slash_command
end

function EHMailTM.MAIL_SEND_SUCCESS()
  m.debug( "MAIL_SEND_SUCCESS" )
  if m.sendmail_state and not m.sendmail_state.sent then
    m.sendmail_state.sent = true
    m.log.add( 'Sent', m.sendmail_state )
    m.add_auto_complete_name( m.sendmail_state.to )
  end
  if m.sendmail_sending then
    m.sendmail_update = true
  end
end

function EHMailTM.MAIL_INBOX_UPDATE()
  if m.inbox_opening then
    m.inbox_update = true
  end

  for i = 1, 7 do
    local index = (i + (m.api.InboxFrame.pageNum - 1) * 7)
    if index <= m.api.GetInboxNumItems() then
      local _, _, sender, _, _, _, _, _, _, was_returned = m.api.GetInboxHeaderInfo( index )
      if INBOX_AUCTIONHOUSES[ sender ] then
        m.api[ "EHMailTMAuctionIcon" .. i ]:Show()
      else
        m.api[ "EHMailTMAuctionIcon" .. i ]:Hide()
      end
      if was_returned then
        m.api[ "EHMailTMReturnedArrow" .. i ]:Show()
      else
        m.api[ "EHMailTMReturnedArrow" .. i ]:Hide()
      end
    end
  end

--新增选择取件
  -- 预览必须在刷勾选框之前算，否则勾选状态会落后一帧
  if not m.inbox_opening then
    local page = m.api.InboxFrame.pageNum or 1
    local total = m.api.GetInboxNumItems()
    if m.batch_preview_dirty or m.batch_preview_page ~= page or m.batch_preview_total ~= total then
      m.batch_preview_dirty = nil
      m.batch_preview_update()
    end
  end

  m.inbox_refresh_checkboxes()

end

---@param name string
function EHMailTM.add_auto_complete_name( name )
  local key = get_realm_faction_key()
  m.api.EHMailTM_AutoCompleteNames[ key ] = m.api.EHMailTM_AutoCompleteNames[ key ] or {}
  m.api.EHMailTM_AutoCompleteNames[ key ][ name ] = time()
end

function EHMailTM.inbox_load()

--新增选择取件
  m.api.InboxFrame:EnableMouse( false )
  local btnAll = m.api.CreateFrame( "Button", "EHMailTMOpenAllMailButton", m.api.InboxFrame, "UIPanelButtonTemplate" )
  btnAll:SetPoint( "LEFT",m.api.InboxFrame, "TOP", 15, -53 )
  btnAll:SetText("接收所有邮件")
  btnAll:SetWidth(120)
  btnAll:SetHeight( 25 )
  btnAll:SetScript( "OnClick", m.inbox_open_all )

  local btnSelected = m.api.CreateFrame( "Button", "EHMailTMOpenSelectedMailButton", m.api.InboxFrame, "UIPanelButtonTemplate" )
  btnSelected:SetPoint( "RIGHT",m.api.InboxFrame, "TOP", 5, -53 )
  btnSelected:SetText("接收选择邮件")
  btnSelected:SetWidth(120)
  btnSelected:SetHeight( 25 )
  btnSelected:SetScript( "OnClick", m.inbox_open_selected )

  -- 小窗开关（方案A）：钉在"接收所有邮件"右侧，**占地保持 22×26**（加宽会顶到邮箱可见边框外面）。
  -- ★0.3.16（用户定）：按钮带**图标** —— 自绘（纯色纹理，见常量那一段的说明），不用任何图标路径。
  -- ★★本客户端有「**隐藏态写属性不落地**」这条老雷（EH_Bag 0.3.21/0.3.25 在案）：这个按钮是在
  --   `ADDON_LOADED` 里建的，那一刻邮箱窗还没显示 ⇒ 那时写的尺寸/锚点**不生效**
  --   （真机症状 = 图标看不见 / 控件跑到框外）。⇒ 全部几何收在 `m.panel_toggle_apply_icon()` **一处**，
  --   除建时调一次，另外**三条腿**各再重申一次：按钮自己的 `OnShow` · `MAIL_SHOW` ·
  --   `hook.InboxFrame_Update`（自终止）。
  local btnToggle = m.api.CreateFrame( "Button", "EHMailTMPanelToggleButton", m.api.InboxFrame, "UIPanelButtonTemplate" )
  btnToggle:SetPoint( "LEFT", btnAll, "RIGHT", 0, 0 )
  btnToggle:SetWidth( m.PANEL_TOGGLE_W )
  btnToggle:SetHeight( m.PANEL_TOGGLE_H )
  m.panel_toggle_btn = btnToggle
  local bars = {}
  for i = 1, getn( m.PANEL_TOGGLE_BARS ) do
    bars[ i ] = btnToggle:CreateTexture( nil, "ARTWORK" )
  end
  m.panel_toggle_bars = bars
  -- 开合指示（» / «）挂**我们自建**的那条 FontString：按钮模板自带的文字是**居中**的，会压住图标
  local toggleArrow = btnToggle:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
  m.panel_toggle_arrow = toggleArrow
  if type( btnToggle.SetScript ) == "function" then
    pcall( btnToggle.SetScript, btnToggle, "OnShow", function() m.panel_toggle_apply_icon() end )
  end
  m.panel_toggle_apply_icon()
  btnToggle:SetScript( "OnClick", function()
    if not m.batch_panel then return end
    if m.batch_panel:IsVisible() then
      m.batch_panel:Hide()
      m.api.EHMailTM_PanelHidden = 1
    else
      m.batch_panel:Show()
      -- ★0.3.16：**显式 false = 「打开过」**（默认档 / 缺键 / 别的值一律按「关」处理 —— 见 batch_panel_want_open）
      m.api.EHMailTM_PanelHidden = false
      if m.batch_reanchor then m.batch_reanchor() end
      m.batch_settle = 30
    end
    m.update_panel_toggle_btn()
  end )
  btnToggle:SetScript( "OnEnter", function()
    m.api.GameTooltip:ClearLines()
    m.api.GameTooltip:SetOwner( this, "ANCHOR_LEFT" )
    -- ★按**面板现在的显隐**说要做的那件事（旧写法读 `PanelHidden` 的真值性 ⇒ 默认档改成「关」以后会反着说）
    local open = m.batch_panel and m.batch_panel:IsVisible()
    m.api.GameTooltip:AddLine( open and "收起批量面板" or "展开批量面板", "", 1, 1, 0 )
    m.api.GameTooltip:Show()
  end )
  btnToggle:SetScript( "OnLeave", function() m.api.GameTooltip:Hide() end )
  m.update_panel_toggle_btn()

  -- batch_load 内部自建自守，只在第一次真正建控件；
  -- inbox_load 每次开邮箱都会跑，不能在这里无条件调用重建。

--新增自动到付选项
  local CODCheckButton = m.api.CreateFrame( "CheckButton", "EHMailTMCODCheckButton", m.api.InboxFrame, "OptionsCheckButtonTemplate" )
  CODCheckButton:SetPoint( "TOP",m.api.InboxFrame, "BOTTOM", -25, 115)
  EHMailTMCODCheckButtonText:SetText("自动到付")
  CODCheckButton:SetWidth(24)
  CODCheckButton:SetHeight( 24 )
  CODCheckButton:SetScript( "OnUpdate", function()
    if m.api.EHMailTM_AutoCOD == 1 then
      CODCheckButton:SetChecked(1)
    else
      CODCheckButton:SetChecked(0)
    end
  end)
  CODCheckButton:SetScript( "OnClick", function()
    if m.api.EHMailTM_AutoCOD == 1 then
      m.api.EHMailTM_AutoCOD = 0
    else
      m.api.EHMailTM_AutoCOD = 1
    end
  end)
  CODCheckButton:SetScript( "OnEnter", function()
    GameTooltip:ClearLines();
    GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("警告！！！")
    GameTooltip:AddLine("请仔核对认邮件，否则遭受损失概不负责！")
    GameTooltip:Show()
  end)
  CODCheckButton:SetScript( "OnLeave", function() GameTooltip:Hide() end )

  MailItem1:SetPoint("TOPLEFT", m.api.InboxFrame, "TOPLEFT", 48, -80)
  for i=1,7 do
    -- 到期时间左移 15px，给右侧新增的邮件勾选框腾位
    getglobal("MailItem" .. i .. "ExpireTime"):SetPoint("TOPRIGHT", "MailItem" .. i, "TOPRIGHT", -15, -4)
    getglobal("MailItem" .. i):SetWidth(280)
  end

  for i = 1, 7 do
    m.api[ "EHMailTMAuctionIcon" .. i .. "Texture" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    m.api[ "EHMailTMReturnedArrow" .. i .. "Texture" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
  end
end

--新增选择取件
function EHMailTM.inbox_open_all()
  m.inbox_opening = true
  m.inbox_update_lock()
  m.inbox_skip = false
  m.inbox_index = 1
  m.inbox_update = true
  m.Mail_open_Selected = false
end

function EHMailTM_Inbox_SetSelected()
  local id = this:GetID() + (m.api.InboxFrame.pageNum - 1) * 7
    if not this:GetChecked() then
		for k, v in ipairs(EHMailTM_SelectedItems) do
		  if v == id then
			tremove(EHMailTM_SelectedItems, k)
			break
		  end
		end
    else
      tinsert(EHMailTM_SelectedItems, id)
    end
end

function EHMailTM.inbox_open_selected()
	if getn(EHMailTM_SelectedItems) == 0 then
	  return
	end

	-- 按邮件身份（发件人+主题）排队，索引在取件过程中会漂移
	m.take_idents = {}
	local seen = {}
	local total = m.api.GetInboxNumItems()
	for _, i in ipairs(EHMailTM_SelectedItems) do
	  if type(i) == "number" and i >= 1 and i <= total and not seen[i] then
		local _, _, sender2, subject2 = m.api.GetInboxHeaderInfo( i )
		seen[i] = true
		tinsert( m.take_idents, { from = sender2, subject = subject2 } )
	  end
	end

	EHMailTM_SelectedItems = {}

	m.Mail_open_Selected = true
	m.inbox_opening = true
	m.inbox_update_lock()
	m.inbox_skip = false
	m.inbox_update = true
	m.take_total = getn( m.take_idents )
	m.take_wait_count = nil
	m.take_waits = 0
	m.inv_waits = 0
end

function EHMailTM.inbox_abort()
  m.inbox_opening = false
  m.inbox_update_lock()
  m.inbox_update = false
end

-- 本页全选：把当前页 7 个勾选框一次性切到同一状态。
-- 直接改 EHMailTM_SelectedItems 而不是逐个模拟点击，保证不重复入表。
function EHMailTM.inbox_select_page( checked )
  local page = m.api.InboxFrame.pageNum or 1
  local total = m.api.GetInboxNumItems()

  for i = 1, 7 do
    local index = i + ( page - 1 ) * 7
    if index > total then break end
    local cb = getglobal( "EHMailTMBoxItem" .. i .. "CB" )
    -- 1.12 只有 IsVisible/IsShown，没有 IsHidden（2.0 才加）
    if cb and cb:IsVisible() then
      cb:SetChecked( checked and 1 or nil )
      local at = nil
      for k, v in ipairs( EHMailTM_SelectedItems ) do
        if v == index then at = k break end
      end
      if checked and not at then
        tinsert( EHMailTM_SelectedItems, index )
      elseif not checked and at then
        tremove( EHMailTM_SelectedItems, at )
      end
    end
  end
end

-- 把 EHMailTM_SelectedItems 同步到当前页 7 个勾选框，并回推"本页全选"状态。
function EHMailTM.inbox_refresh_checkboxes()
  local page = m.api.InboxFrame.pageNum or 1
  local total = m.api.GetInboxNumItems()
  local page_checked, page_total = 0, 0

  for i = 1, 7 do
    local index = i + ( page - 1 ) * 7
    local cb = getglobal( "EHMailTMBoxItem" .. i .. "CB" )
    if cb then
      if index > total then
        cb:Hide()
      else
        cb:Show()
        cb:SetChecked( nil )
        page_total = page_total + 1
        for k = 1, getn( EHMailTM_SelectedItems ) do
          if EHMailTM_SelectedItems[ k ] == index then
            cb:SetChecked( 1 )
            page_checked = page_checked + 1
            break
          end
        end
      end
    end
  end

  -- ★0.3.3：全选又是**勾选框**了（客户端原生 CheckButton）⇒ 恢复用 SetChecked 回推状态；
  --   m.pageAllState 仍然留着（点击回调与自检都读它）。
  m.pageAllState = ( page_total > 0 and page_checked == page_total ) and true or false
  if m.select_all_button and type( m.select_all_button.SetChecked ) == "function" then
    pcall( m.select_all_button.SetChecked, m.select_all_button, m.pageAllState )
  end
end

-- 筛选预览：把当前页里命中筛选条件的邮件勾上，一眼看清批量操作会动哪几封。
-- 预览勾的索引单独记在 m.batch_preview：条件/页码/邮件数变化时先撤回再重算，
-- 所以条件不变期间手动取消勾选是有效的，不会被预览立刻盖回去。
function EHMailTM.batch_preview_update()
  local page = m.api.InboxFrame.pageNum or 1
  local total = m.api.GetInboxNumItems()
  m.batch_preview = m.batch_preview or {}
  m.batch_preview_page = page
  m.batch_preview_total = total

  for k = getn( m.batch_preview ), 1, -1 do
    local idx = m.batch_preview[ k ]
    for j = getn( EHMailTM_SelectedItems ), 1, -1 do
      if EHMailTM_SelectedItems[ j ] == idx then tremove( EHMailTM_SelectedItems, j ) end
    end
    tremove( m.batch_preview, k )
  end

  local filters = m.batch_filters or {}
  if next( filters ) then
    for i = 1, 7 do
      local index = i + ( page - 1 ) * 7
      if index <= total then
        local _, _, sender, subject, money, cod, _, has_item, read, returned, _, _, isGM =
          m.api.GetInboxHeaderInfo( index )
        if not isGM and m.batch_match( filters, sender, subject, money, cod, has_item, read, returned ) then
          tinsert( m.batch_preview, index )
          local at = false
          for k = 1, getn( EHMailTM_SelectedItems ) do
            if EHMailTM_SelectedItems[ k ] == index then at = true break end
          end
          if not at then tinsert( EHMailTM_SelectedItems, index ) end
        end
      end
    end
  end

  m.batch_refresh_label()
end

function EHMailTM.batch_refresh_label()
  if not m.filterButton then return end
  local n = 0
  for _ in pairs( m.batch_filters or {} ) do n = n + 1 end
  if n == 0 then
    m.filterButton:SetText( L[ "Filter" ] )
    return
  end
  -- 命中数每次现算：跨页总数，让"本页只看到 2 封、其实一共 12 封"不至于误判
  local matched = getn( m.batch_scan( m.batch_filters ) )
  m.filterButton:SetText( string.format( L[ "Filter (%d)" ], n ) ..
    " · " .. string.format( L[ "Matched (%d)" ], matched ) )
end

-- ★★★0.3.3（用户定：「如果是UI有问题就换成当前插件的常规弹窗多选正方形形式」）：
--   筛选条件不再用自绘勾选框，改用**本插件常规的弹窗多选**（宿主 `EVAL_DD_OPEN` 的 multi 模式，
--   每行一个正方形勾）—— 与其继续修一个在这台客户端上点不动的自绘控件，不如用已经验证过的组件。
--   ★口径 = **按目标态设置**（不是切换）：宿主 multi 下拉点一行时它自己已经翻过一次勾，
--     我们再"切换"一次就会双翻转（勾点不上/点了反）。
function EHMailTM.batch_set_filter( key, on )
  if not key then return end
  if on then
    m.batch_filters[ key ] = true
  else
    m.batch_filters[ key ] = nil
  end
  -- ★两个入口共用一个写口：面板上那颗勾选框也要跟着走（否则面板与弹窗会各显示一套）
  local cb = m.batch_filter_buttons and m.batch_filter_buttons[ key ]
  if cb and type( cb.SetChecked ) == "function" then pcall( cb.SetChecked, cb, on and true or false ) end
  m.batch_refresh_label()
  m.batch_preview_update()
  if m.batch_panel then m.inbox_refresh_checkboxes() end
end

-- 「筛选」按钮弹出的多选窗（唯一入口）。★拿不到那个口就**如实报一声**（绝不静默、也绝不假装打开了）。
function EHMailTM.batch_filter_menu()
  if type( EVAL_DD_OPEN ) ~= "function" then
    m.info( L[ "Filter menu unavailable" ] )
    return
  end
  local keys = {}
  for key in pairs( FILTER_DEFS ) do tinsert( keys, key ) end
  sort( keys )
  local labels, sel = {}, {}
  for i = 1, getn( keys ) do
    labels[ i ] = FILTER_DEFS[ keys[ i ] ].label
    if m.batch_filters[ keys[ i ] ] then sel[ i ] = true end
  end
  EVAL_DD_OPEN( m.filterButton, labels, function( pi, on )
    if keys[ pi ] then m.batch_set_filter( keys[ pi ], on ) end
  end, { multi = true, selected = sel } )
end

-- ★0.3.16：开关按钮的**自绘视觉**唯一重设口（图标 6 条纯色纹理 + 开合箭头的锚点）。
--   ★★为什么必须能**重复调用**：本客户端「**隐藏态写属性不落地**」（EH_Bag 0.3.21/0.3.25 在案）——
--   这个按钮在 `ADDON_LOADED` 里建，那一刻邮箱窗还没显示 ⇒ 建的时候写的尺寸/锚点**不生效**
--   （真机症状 = 图标看不见 / 控件跑到框外）。⇒ 建时一次 + 按钮 `OnShow` 一次 +
--   `hook.InboxFrame_Update` 里每个 tick 重申一次，直到**按钮真的可见**（那时置 `m.toggle_visual_ok`
--   ⇒ **自终止**，不会一直写）。
--   ★图标 = 纯色纹理自绘（`m.PANEL_TOGGLE_TEX` + `SetVertexColor`）：本项目**唯一可靠**的贴图，
--   不依赖任何图标路径 ⇒ 不会再出现「贴图加载失败画成一块红 / 空白」。
--   ★对象守卫一律按 `type` 判 table/userdata（宽容桩对没设过的字段会返回函数，写 `~= nil` 会炸）。
function EHMailTM.panel_toggle_apply_icon()
  local btn = m.panel_toggle_btn
  local bt = btn and type( btn )
  if not btn or ( bt ~= "table" and bt ~= "userdata" ) then return false end

  local defs = m.PANEL_TOGGLE_BARS
  local bars = m.panel_toggle_bars
  if type( defs ) ~= "table" or type( bars ) ~= "table" then return false end

  local icon = tonumber( m.PANEL_TOGGLE_ICON ) or 10
  local iy = math.floor( ( ( tonumber( m.PANEL_TOGGLE_H ) or 26 ) - icon ) / 2 )
  local gold = m.PANEL_TOGGLE_GOLD
  local n = 0
  for i = 1, getn( defs ) do
    local bar, d = bars[ i ], defs[ i ]
    local t = bar and type( bar )
    if bar and ( t == "table" or t == "userdata" )
      and type( bar.SetTexture ) == "function" and type( bar.SetPoint ) == "function" then
      pcall( bar.SetTexture, bar, m.PANEL_TOGGLE_TEX )
      pcall( bar.SetWidth, bar, d[ 3 ] )
      pcall( bar.SetHeight, bar, d[ 4 ] )
      if type( bar.ClearAllPoints ) == "function" then pcall( bar.ClearAllPoints, bar ) end
      pcall( bar.SetPoint, bar, "TOPLEFT", btn, "TOPLEFT", 1 + d[ 1 ], -( iy + d[ 2 ] ) )
      pcall( bar.SetVertexColor, bar, gold[ 1 ], gold[ 2 ], gold[ 3 ] )
      pcall( bar.Show, bar )
      n = n + 1
    end
  end

  -- 箭头：**锚点也在这一处重设**（它同样是「隐藏态写进去就不生效」的受害者 —— 没有锚点的 FontString
  -- 什么都不画，这正是第一版真机「连 » 都看不见」的成因）。
  local fs = m.panel_toggle_arrow
  local ft = fs and type( fs )
  if fs and ( ft == "table" or ft == "userdata" ) and type( fs.SetPoint ) == "function" then
    if type( fs.ClearAllPoints ) == "function" then pcall( fs.ClearAllPoints, fs ) end
    pcall( fs.SetPoint, fs, "RIGHT", btn, "RIGHT", -2, 0 )
  end

  -- 自终止门：**按钮真的可见**了才算这趟视觉落地（在那之前每个 tick 再来一遍）
  if type( btn.IsVisible ) == "function" then
    local okv, vis = pcall( btn.IsVisible, btn )
    if okv and vis then m.toggle_visual_ok = true end
  end
  return n > 0
end

-- ★★★0.3.16（用户定）：**批量面板默认关**。
--   判据只此一处：**显式 false = 「打开过」**；缺键 / nil / 任何别的值 ⇒ 收起。
--   （旧版是 nil = 展开 ⇒ 老存档升级后第一次开邮箱即为收起状态，这正是用户要的默认档；
--     用户手动点开过一次就会记住，写的是显式 false。）
function EHMailTM.batch_panel_want_open()
  return m.api.EHMailTM_PanelHidden == false
end

-- 小窗开关按钮的两态文案：» / « 恒为金色（捞哥要求不做变灰），靠符号方向区分开合
-- ★0.3.16：箭头改画在**我们自建的那条 FontString** 上（按钮模板自带的居中文字会压住新增的图标）；
--   拿不到它 ⇒ 退回按钮自己的文字（fail-open：宁可压一点图标，也不能丢掉开合指示）。
function EHMailTM.update_panel_toggle_btn()
  local btn = m.api.EHMailTMPanelToggleButton
  if not btn then return end
  local txt
  if m.batch_panel_want_open() then
    txt = "|cffffd100»|r"
  else
    txt = "|cffffd100«|r"
  end
  local fs = m.panel_toggle_arrow
  local ft = fs and type( fs )
  if fs and ( ft == "table" or ft == "userdata" ) and type( fs.SetText ) == "function" then
    pcall( btn.SetText, btn, "" )
    pcall( fs.SetText, fs, txt )
  else
    pcall( btn.SetText, btn, txt )
  end
end

function EHMailTM.batch_load()
  -- 只建一次。inbox_load 每次开邮箱都会调用这里，重复 CreateFrame 同名控件
  -- 会返回新 frame 而旧的仍留在屏幕上，叠成一堆错位的面板。
  if m.batch_panel then
    -- 尊重小窗开关的状态（★0.3.16 起**默认关**）：不能每次开邮箱都强制弹出来
    if m.batch_panel_want_open() then
      m.batch_panel:Show()
    end
    if m.batch_reanchor then m.batch_reanchor() end
    return
  end

  m.batch_filters = m.batch_filters or {}
  m.batch_filter_buttons = m.batch_filter_buttons or {}

  local keys = {}
  for key in pairs( FILTER_DEFS ) do tinsert( keys, key ) end
  sort( keys )

  -- 旧版本遗留的同名 frame 先清掉，避免和这次的叠在一起
  local stale = getglobal( "EHMailTMBatchPanel" )
  if stale then pcall( function() stale:Hide() end ) end

  local panel = m.api.CreateFrame( "Frame", "EHMailTMBatchPanel", m.api.InboxFrame )
  panel:SetWidth( SIDE_PANEL_W )
  panel:SetHeight( SIDE_PANEL_H )
  -- ★★★0.3.3 真机报障「筛选条件勾选框点不动」：面板只是一块背景板（没有任何鼠标处理体），
  --   却开了 `EnableMouse( true )` —— 本项目在案「**层级同时决定点击命中**、透明/无贴图的帧照样吃点击」
  --   ⇒ 面板只要在子件之上就会把整片点击全吃掉（而批量按钮因为自带模板贴图/层次看着"好使"）。
  --   ⇒ 关掉它的鼠标：它本来就不需要 —— 点击要么落到子件、要么穿到底下同样不吃鼠标的 InboxFrame。
  panel:EnableMouse( false )

  -- 锚 MailFrame 本体 + 已知内缩，不要锚 backdrop：pfUI 的 backdrop 会被重建/重排，
  -- 实测它的 L/B 与锚点一致但 W/H 会凭空缩掉 64/80（MailFrame.bd R 报 620，
  -- 而按 mail.lua:179 应为 684）。锚它等于把位置交给一个会漂的对象。
  -- 不开放拖动：StartMoving 存下的偏移会让面板永久脱离邮箱。
  local function right_inset()
    if m.pfui_skin_enabled then return MAIL_INSET_RIGHT end
    return 0
  end
  -- 内缩量是 pfUI 外框的，没皮肤时可见边缘就是本体边缘，不该跟着让
  local function top_inset()
    if m.pfui_skin_enabled then return MAIL_INSET_TOP end
    return 0
  end
  local function reanchor()
    panel:ClearAllPoints()
    local mf = m.api.MailFrame
    -- 两套皮肤各存各的校准值：原皮肤用 EHMailTM_PanelOffset（默认 -38/-12），
    -- pfUI 用 EHMailTM_PanelOffsetPF（默认 0/0），互不串扰。
    local dx, dy = 0, 0
    if m.pfui_skin_enabled then
      local off = m.api.EHMailTM_PanelOffsetPF
      if off then
        dx = off.x or 0
        dy = off.y or 0
      else
        dx = PANEL_OFFSET_PF_X
        dy = PANEL_OFFSET_PF_Y
      end
    else
      local off = m.api.EHMailTM_PanelOffset
      if off then
        dx = off.x or 0
        dy = off.y or 0
      else
        dx = PANEL_OFFSET_X
        dy = PANEL_OFFSET_Y
      end
    end
    if mf then
      panel:SetPoint( "TOPLEFT", mf, "TOPRIGHT", PANEL_GAP + right_inset() + dx, top_inset() + dy )
    else
      panel:SetPoint( "TOPLEFT", m.api.InboxFrame, "TOPRIGHT", PANEL_GAP + dx, dy )
    end
  end

  -- pfUI 皮肤在本插件之后才撑开 MailFrame.backdrop，锚点会停在旧位置。
  -- 开面板后连续重锚到布局稳定（30 帧足够跨过皮肤重排）。
  m.batch_settle = 30
  reanchor()
  panel:SetScript( "OnUpdate", function( self )
    if m.batch_settle and m.batch_settle > 0 then
      m.batch_settle = m.batch_settle - 1
      reanchor()
    end
  end )

  panel:SetScript( "OnShow", function()
    m.batch_settle = 30
    m.batch_preview_dirty = true
    reanchor()
  end )
  panel:RegisterEvent( "MAIL_INBOX_UPDATE" )
  panel:SetScript( "OnEvent", function() m.batch_settle = 30; reanchor() end )

  if m.api.pfUI and m.api.pfUI.api and m.api.pfUI.api.CreateBackdrop then
    pcall( m.api.pfUI.api.CreateBackdrop, panel, 4 )
  else
    -- 没装 pfUI：面板得自己画背景，否则只剩一圈裸按钮飘在游戏画面上。
    -- 1.12 的 Frame 原生支持 SetBackdrop（XML 里 MailAutoCompleteBox 就是这种写法）。
    panel:SetBackdrop( {
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    } )
    panel:SetBackdropColor( 0, 0, 0, 0.75 )
  end
  m.batch_panel = panel
  m.batch_reanchor = reanchor

  local y = -PAD

  local btnMenu = m.api.CreateFrame( "Button", "EHMailTMFilterMenuButton", panel, "UIPanelButtonTemplate" )
  btnMenu:SetPoint( "TOPLEFT", panel, "TOPLEFT", PAD, y )
  btnMenu:SetWidth( SIDE_PANEL_W - PAD * 2 )
  btnMenu:SetHeight( ROW_H )
  -- ★0.3.3：这个按钮本来就是空的（设计上就是给筛选菜单用的）⇒ 接上宿主的多选窗
  btnMenu:SetScript( "OnClick", function() m.batch_filter_menu() end )
  m.filterButton = btnMenu
  m.batch_refresh_label()
  y = y - ( ROW_H + ROW_GAP )

  local function action_button( name, text, tip, r, g, b, onclick )
    local btn = m.api.CreateFrame( "Button", name, panel, "UIPanelButtonTemplate" )
    btn:SetPoint( "TOPLEFT", panel, "TOPLEFT", PAD, y )
    btn:SetWidth( SIDE_PANEL_W - PAD * 2 )
    btn:SetHeight( ROW_H )
    btn:SetText( text )
    btn:SetScript( "OnClick", onclick )
    btn:SetScript( "OnEnter", function()
      m.api.GameTooltip:ClearLines()
      m.api.GameTooltip:SetOwner( this, "ANCHOR_LEFT" )
      m.api.GameTooltip:AddLine( tip, "", r, g, b )
      m.api.GameTooltip:Show()
    end )
    btn:SetScript( "OnLeave", function() m.api.GameTooltip:Hide() end )
    y = y - ( ROW_H + ROW_GAP )
    return btn
  end

  local btnTake = action_button( "EHMailTMBatchTakeButton", L[ "Batch take" ],
    L[ "Batch take tip" ], 0, 1, 0, function() m.batch_start( "take" ) end )

  local btnReturn = action_button( "EHMailTMBatchReturnButton", L[ "Batch return" ],
    L[ "Batch return tip" ], 1, 1, 0, function() m.batch_start( "return" ) end )
  m.batch_return_button = btnReturn

  local btnDelete = action_button( "EHMailTMBatchDeleteButton", L[ "Batch delete" ],
    L[ "Batch delete tip" ], 1, 0, 0, function() m.batch_start( "delete" ) end )
  m.batch_delete_button = btnDelete

  y = y - 8

  -- ★★★0.3.3（用户定）：「我更想在面板上直接看到勾选框」⇒ 平铺勾选框**还原**，
  --   但控件换成**客户端原生 `CheckButton`**（不再是自绘的普通 `Button`）—— 两处关键差异：
  --   ① checked 状态由客户端管（不用自己实现 SetChecked/GetChecked、也不用自己显示那个勾）；
  --   ② **命中区由客户端算**，而我们把按钮宽度设成**整格**（CELL_W）⇒ 点方框、点文字**都是点它**。
  --      （原来「16x16 方框 + 独立标签按钮」那种拼法，正是「点方框没反应／点文字点不到」的根源。）
  --   ★上游注释说 OptionsCheckButtonTemplate「在不同客户端会错位」—— 那是**模板自带尺寸/锚点**造成的；
  --     我们**建完读回自证**：拿不到贴图就自己贴一套（尺寸与锚点全由我们定 ⇒ 无从错位）。
  local function checkbox( name, label, x, yy, onclick )
    -- ★★★0.3.3 勾选框样式（真机第三轮）——**贴图全部自绘**，不再用客户端的勾选框贴图：
    --   ① 客户端那批 `UI-CheckBox-*` **不是正方形**（多为横向图集）⇒ 按 16x16 取左上角只会截到框的一角
    --      （真机表现就是「方框只剩左边一条竖线」）；图集怎么切**不能靠猜**，所以不用它。
    --   ② 本项目在案的纯色纹理只有 `Interface\Buttons\WHITE8X8`（配 `SetVertexColor`）可靠 ——
    --      方框 = 暗底 + 四条 1px 亮边，选中 = 内部一块亮绿，全部由我们画 ⇒ 尺寸与样式完全可控。
    --   ★控件仍然是**客户端原生 `CheckButton`**：checked 态与**命中区**由客户端管（「点得着」的关键），
    --     我们只接「画」这一层。
    local cb = m.api.CreateFrame( "CheckButton", name, panel )
    cb:SetWidth( CELL_W )      -- ★整格宽 ⇒ 点方框、点文字都是点它
    cb:SetHeight( CHECK_BOX )
    cb:SetPoint( "TOPLEFT", panel, "TOPLEFT", x, yy )
    -- 子件逐个抬层（本项目铁律：抬高父帧不带动子件）
    cb:SetFrameLevel( panel:GetFrameLevel() + 2 )

    local box = cb:CreateTexture( name .. "Box", "BACKGROUND" )
    box:SetTexture( "Interface\\Buttons\\WHITE8X8" )
    box:SetWidth( CHECK_BOX )
    box:SetHeight( CHECK_BOX )
    box:SetPoint( "LEFT", cb, "LEFT", 0, 0 )
    box:SetVertexColor( 0.06, 0.06, 0.06, 0.85 )   -- 暗底（与面板底色区分）

    -- 四条 1px 亮边（像标准勾选框的框线）：上/下各拉满宽，左/右各拉满高
    local EDGES = {
      { "TOPLEFT",     "TOPRIGHT",     1, 0 },
      { "BOTTOMLEFT",  "BOTTOMRIGHT",  1, 0 },
      { "TOPLEFT",     "BOTTOMLEFT",   0, 1 },
      { "TOPRIGHT",    "BOTTOMRIGHT",  0, 1 },
    }
    for ei = 1, 4 do
      local e = EDGES[ ei ]
      local t = cb:CreateTexture( name .. "Edge" .. ei, "ARTWORK" )
      t:SetTexture( "Interface\\Buttons\\WHITE8X8" )
      t:SetPoint( e[ 1 ], box, e[ 1 ], 0, 0 )
      t:SetPoint( e[ 2 ], box, e[ 2 ], 0, 0 )
      if e[ 3 ] == 1 then t:SetHeight( 1 ) else t:SetWidth( 1 ) end
      t:SetVertexColor( 0.62, 0.62, 0.62, 1 )
    end

    -- 选中态：内部一块亮绿（用实心块而不是「勾字符」—— 无字形/编码风险）
    local mark = cb:CreateTexture( name .. "Mark", "OVERLAY" )
    mark:SetTexture( "Interface\\Buttons\\WHITE8X8" )
    mark:SetPoint( "TOPLEFT", box, "TOPLEFT", 3, -3 )
    mark:SetPoint( "BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3 )
    mark:SetVertexColor( 0.25, 0.85, 0.35, 1 )
    mark:Hide()

    -- ★checked 态只有一个来源：**读客户端的**（不自己存变量）⇒ 选中块显隐只在这一处同步
    local function syncMark()
      if type( cb.GetChecked ) ~= "function" then return end
      if cb:GetChecked() then mark:Show() else mark:Hide() end
    end
    -- 包一层 SetChecked：外面（inbox_refresh_checkboxes / `/tm filter`）改状态时也跟上
    local origSetChecked = cb.SetChecked
    if type( origSetChecked ) == "function" then
      cb.SetChecked = function( self, v )
        pcall( origSetChecked, self, v )
        syncMark()
      end
    end

    -- 文字：自己建，紧贴方框右侧
    local fs = cb:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
    fs:SetPoint( "LEFT", cb, "LEFT", CHECK_BOX + 4, 0 )
    fs:SetText( label )
    if type( m.log.fontSet ) == "function" then pcall( m.log.fontSet, fs, 11 ) end

    cb:SetScript( "OnClick", function()
      syncMark()   -- ★客户端已经翻过 checked，这里只把选中块画对
      onclick( cb:GetChecked() and true or false )
    end )
    -- 悬停反馈：方框底色提亮（纯显示，不改状态）
    cb:SetScript( "OnEnter", function() pcall( box.SetVertexColor, box, 0.22, 0.22, 0.22, 0.95 ) end )
    cb:SetScript( "OnLeave", function() pcall( box.SetVertexColor, box, 0.06, 0.06, 0.06, 0.85 ) end )
    return cb
  end

  local cbAll
  cbAll = checkbox( "EHMailTMSelectAllCB", L[ "Select all" ], PAD + 2, y, function( on )
    m.inbox_select_page( on )
  end )
  m.select_all_button = cbAll
  y = y - ( CHECK_BOX + 6 )

  for idx = 1, getn( keys ) do
    local key = keys[ idx ]
    local row = math.ceil( idx / 2 )
    -- 奇偶不能用 % 或 math.fmod：两者都是 Lua 5.1 才有的，1.12 的 5.0 会报语法错/字段 nil
    local col = idx - ( row - 1 ) * 2

    local cb
    cb = checkbox( "EHMailTMBatchFilter" .. idx, FILTER_DEFS[ key ].label,
      PAD + ( col - 1 ) * CELL_W, y - ( row - 1 ) * ( CHECK_BOX + ROW_GAP ),
      function( on ) m.batch_set_filter( key, on ) end )

    m.batch_filter_buttons[ key ] = cb
  end

  -- ★0.3.16：**默认关** —— 没设过 / 缺键 / 任何非 false 的值都保持隐藏；
  --   只有显式打开过（写 false）才在首次建好后立刻展开。判据只在 `batch_panel_want_open()` 一处。
  if not m.batch_panel_want_open() then
    panel:Hide()
  end
end

-- 倒序队列：删掉第 N 封后只有 >N 的索引左移，而那些都已处理完，剩余索引不受影响
function EHMailTM.batch_scan( filters )
  local total = m.api.GetInboxNumItems()
  local list = {}
  for i = 1, total do
    local _, _, sender, subject, money, cod, _, has_item, read, returned, _, _, isGM = m.api.GetInboxHeaderInfo( i )
    if not isGM and m.batch_match( filters, sender, subject, money, cod, has_item, read, returned ) then
      tinsert( list, i )
    end
  end

  local sorted = {}
  for k = getn( list ), 1, -1 do
    tinsert( sorted, list[ k ] )
  end
  return sorted
end

--- 多条件之间是 OR：命中任意一个已勾选条件即入选
function EHMailTM.batch_match( filters, sender, subject, money, cod, has_item, read, returned )
  local ah = classify_ah_mail( subject )
  local has_any = false

  for key in pairs( filters ) do
    local def = FILTER_DEFS[ key ]
    if not def then return false end
    has_any = true
    if def.kind == "ah" then
      if ah == def.value then return true end
    elseif def.kind == "money" then
      if money and money > 0 then return true end
    elseif def.kind == "item" then
      if has_item then return true end
    elseif def.kind == "cod" then
      if cod and cod > 0 then return true end
    elseif def.kind == "returned" then
      if returned then return true end
    elseif def.kind == "unread" then
      if not read then return true end
    end
  end

  return false
end

--- 没勾筛选条件时的队列：直接用收件箱里手动打勾的邮件。
--- 与 batch_scan 同为倒序，且要剔掉越界与 GM 邮件，否则 batch_step 会空转。
function EHMailTM.batch_scan_selected()
  local total = m.api.GetInboxNumItems()
  local seen = {}
  local list = {}
  for k = 1, getn( EHMailTM_SelectedItems ) do
    local i = EHMailTM_SelectedItems[ k ]
    if type( i ) == "number" and i >= 1 and i <= total and not seen[ i ] then
      local _, _, _, _, _, _, _, _, _, _, _, _, isGM = m.api.GetInboxHeaderInfo( i )
      if not isGM then
        seen[ i ] = true
        tinsert( list, i )
      end
    end
  end

  local sorted = {}
  for k = getn( list ), 1, -1 do
    tinsert( sorted, list[ k ] )
  end
  return sorted
end

--- mode: "take" 取件 / "return" 退信 / "delete" 删除
-- ★★★0.3.3（用户要求）：批量操作限频 —— **默认生效，不需要任何配置**。
--   现状：批量推进挂在 on_update 上（每帧最多一步），唯一的刹车是「等 GetInboxNumItems 掉下来」
--   ⇒ **节奏只受服务器确认速度限制**：服务器回得快时一帧就能连发多件写动作。
--   本项目铁律 = 「服务器写动作 > ~1-2 次/s 必限频」（1.75.x 实测：一帧 24 次 UseContainerItem 被反滥用踢线）。
--   ⇒ 四处写动作（批量取件/退信/删除 · 接收所有邮件 · 选择取件 · 批量寄送）**共用这一个闸**；
--     没到点就**原样排队、下一帧再来**（绝不丢队列、绝不吞掉用户的操作）。
--   ★ 用 GetTime()（会话秒）+ 批量开始时复位（见 batch_start）⇒ **每一批的第一件永远立刻执行**，
--     不会因为上一轮的 last_at 而「点了没反应」。
m.batch_rate = 0.5
function EHMailTM.batch_rate_ok()
  local now = GetTime()
  if now - ( m.batch_last_at or 0 ) < m.batch_rate then
    return false
  end
  m.batch_last_at = now
  return true
end

function EHMailTM.batch_start( mode )
  -- ★限频账在每一批开始时复位：第一件立刻做，不带上一次的尾巴
  m.batch_last_at = 0
  local filters = m.batch_filters or {}

  -- 队列 = 筛选命中 ∪ 手动勾选，去重；两边都是倒序，合并后仍倒序，
  -- 删信时只会影响已处理完的高索引，剩余索引不漂移。
  local filter_hits = {}
  if next( filters ) then
    filter_hits = m.batch_scan( filters )
  end
  local picked = m.batch_scan_selected()

  local queue, seen = {}, {}
  for k = 1, getn( picked ) do
    local i = picked[ k ]
    if not seen[ i ] then
      seen[ i ] = true
      tinsert( queue, i )
    end
  end
  for k = 1, getn( filter_hits ) do
    local i = filter_hits[ k ]
    if not seen[ i ] then
      seen[ i ] = true
      tinsert( queue, i )
    end
  end

  -- 合并后必须整体重排成倒序：两段各自倒序，拼接后不保证。
  -- 取走一封邮件它会从列表消失、比它大的索引全部左移，乱序队列会拿旧索引取空/取错。
  table.sort( queue, function( a, b ) return a > b end )

  -- 有手动勾选参与本次批量，跑完才清空勾选
  if getn( picked ) > 0 then
    m.batch_used_selection = true
  end

  if getn( queue ) == 0 then
    if next( filters ) then
      m.info( L[ "No mail matched" ] )
    else
      m.info( L[ "No filter selected" ] )
    end
    return
  end

  if mode == "take" then
    -- 取件按邮件身份（发件人+主题）排队：索引会随邮件消失漂移，身份不会。
    -- 处理流程在 on_update 的 Mail_open_Selected 分支（与"接收选择邮件"共用）。
    m.take_idents = {}
    for k = 1, getn( queue ) do
      local _, _, sender2, subject2 = m.api.GetInboxHeaderInfo( queue[ k ] )
      tinsert( m.take_idents, { from = sender2, subject = subject2 } )
    end
    EHMailTM_SelectedItems = {}
    if m.batch_panel then m.inbox_refresh_checkboxes() end
    m.Mail_open_Selected = true
    m.inbox_opening = true
    m.inbox_update_lock()
    m.inbox_skip = false
    m.inbox_update = true
    m.take_total = getn( m.take_idents )
    m.take_wait_count = nil
    m.take_waits = 0
    m.inv_waits = 0
    m.batch_queue = nil
    m.batch_opening = false
    m.batch_used_selection = nil
    return
  end

  if mode == "delete" and m.batch_pending_delete ~= getn( queue ) then
    m.batch_pending_delete = getn( queue )
    local tip = m.api.GameTooltip
    tip:Hide()
    tip:ClearLines()
    tip:SetOwner( m.batch_delete_button or m.batch_panel or m.api.InboxFrame, "ANCHOR_LEFT" )
    tip:AddLine( string.format( L[ "Really delete %d mails?" ], getn( queue ) ), "", 1, 0, 0 )
    tip:AddLine( L[ "Click again to confirm" ], "", 1, 0, 0 )
    tip:Show()
    return
  end
  m.batch_pending_delete = nil

  m.batch_mode = mode
  m.batch_queue = queue
  m.batch_total = getn( queue )
  m.batch_done = 0
  m.batch_returned = 0
  m.batch_opening = true

  m.inbox_opening = true
  m.inbox_update_lock()
  m.inbox_skip = false
  m.inbox_update = true
end

function EHMailTM.batch_abort()
  m.batch_opening = false
  m.batch_queue = nil
  m.batch_wait_count = nil
  m.batch_wait_frames = nil
  m.inbox_opening = false
  m.inbox_update_lock()
  m.inbox_update = false
  -- 手动勾选只对本次批量有效，跑完就清空，否则残留索引会指向别的邮件
  if m.batch_used_selection then
    m.batch_used_selection = nil
    EHMailTM_SelectedItems = {}
    if m.batch_panel then
      m.inbox_refresh_checkboxes()
    end
  end
  if m.batch_mode == "return" then
    local returned = m.batch_returned or 0
    if returned > 0 then
      m.info( string.format( L[ "Batch returned: %d" ], returned ) )
    end
  end
  local gained = m.money_received or 0
  if gained > 0 then
    m.info( string.format( "%s%s.", m.format_money( gained ), L[ "collected" ] ) )
    m.money_received = 0
  end
end

function EHMailTM.batch_step()
  if not m.batch_queue or getn( m.batch_queue ) == 0 then
    m.batch_abort()
    if m.batch_done > 0 then
      m.info( string.format( L[ "Batch done: %d" ], m.batch_done ) )
    end
    return false
  end

  -- 1.12 邮箱同一时刻只受理一个取件：上一封还没从列表消失就开下一封会静默失败。
  -- 等 GetInboxNumItems 掉下来（邮件真被取走）才放行下一封，超时 100 帧兜底防卡死。
  -- 与"接收选择邮件"按钮的同步方式（MAIL_INBOX_UPDATE 里等 cur < last_inbox_count）一致。
  if m.batch_wait_count then
    if m.api.GetInboxNumItems() == m.batch_wait_count and ( m.batch_wait_frames or 0 ) < 100 then
      m.batch_wait_frames = ( m.batch_wait_frames or 0 ) + 1
      m.inbox_update = true
      return true
    end
    m.batch_wait_count = nil
    m.batch_wait_frames = nil
  end

  -- ★限频：到点才做下一件（没到点就保持排队，下一帧再来）
  if not m.batch_rate_ok() then
    m.inbox_update = true
    return true
  end

  local index = tremove( m.batch_queue, 1 )
  if index > m.api.GetInboxNumItems() then
    m.inbox_update = true
    return true
  end

  local hdr_icon, _, _, _, _, COD, _, _, _, _, _, _, isGM = m.api.GetInboxHeaderInfo( index )
  -- 槽位已空（邮件被取走后列表左移，队里残留的是旧索引）→ 跳过且不计入完成数
  -- GM 邮件与未开启自动到付时的 COD 邮件一律跳过
  if not hdr_icon or isGM or (m.api.EHMailTM_AutoCOD ~= 1 and COD and COD > 0) then
    m.inbox_update = true
    return true
  end

  if m.batch_mode == "delete" then
    m.api.DeleteInboxItem( index )
  elseif m.batch_mode == "return" then
    -- 不要用 InboxItemCanDelete 预判：它在 1.12 存在，但对普通邮件也返回 falsy，
    -- 会把每封都算成"kept"导致退信永远不成功。直接调 ReturnInboxItem，
    -- 退不掉的（已退回过、GM 邮件等）会在下一轮按索引越界自然跳过。
    m.api.ReturnInboxItem( index )
    m.batch_returned = (m.batch_returned or 0 ) + 1
    m.batch_done = m.batch_done + 1
    m.batch_wait_count = m.api.GetInboxNumItems()
    m.batch_wait_frames = 0
    m.inbox_update = true
    return true
  else
    m.inbox_open( index )
  end
  m.batch_done = m.batch_done + 1
  m.batch_wait_count = m.api.GetInboxNumItems()
  m.batch_wait_frames = 0
  m.inbox_update = true
  return true
end

---Sunelegy修复付款取信报错
function EHMailTM.set_cod_text()
    local text = m.api.COD_AMOUNT or ""

  if not m.pfui_skin_enabled then
    -- Lua 5.0 没有 string.match，用 string.find 取捕获
    local _, _, matched = string.find(text, "^(.-)%s+%S+$")
    if matched then
      text = matched
    end
  end

  text = text or ""

  if m.api.SendMailCODAllButton:GetChecked() then
    m.api.SendMailMoneyText:SetText(L["each mail"] .. " " .. text)-- .. " " .. L["each mail"] .. ":")
  else
    m.api.SendMailMoneyText:SetText(L["1st mail"] .. " " .. text)-- .. " " .. L["1st mail"] .. ":")
  end
end

-- 把时间戳格式化为 "2026.8.29 5:23"（月/日/时不补零，24 小时制，分补零）
---@param timestamp number
function EHMailTM.format_datetime( timestamp )
  local _, _, y, mo, d, h, mi = string.find( date( "%Y %m %d %H %M", timestamp ), "^(%d+) (%d+) (%d+) (%d+) (%d+)$" )
  return string.format( "%d.%d.%d %d:%02d", y, mo, d, h, mi )
end

-- 把时间戳格式化为 "2026.8.29"（月/日不补零）
---@param timestamp number
function EHMailTM.format_date( timestamp )
  local _, _, y, mo, d = string.find( date( "%Y %m %d", timestamp ), "^(%d+) (%d+) (%d+)$" )
  return string.format( "%d.%d.%d", y, mo, d )
end

---@param copper number
function EHMailTM.format_money( copper )
  if type( copper ) ~= "number" then return "-" end

  local gold = math.floor( copper / 10000 )
  local silver = math.floor( (copper - gold * 10000) / 100 )
  local copper_remain = copper - (gold * 10000) - (silver * 100)

  local result = ""
  if gold > 0 then
    result = result .. string.format( "|cffffffff%d|cffffd700金|r ", gold )
  end
  if silver > 0 then
    result = result .. string.format( "|cffffffff%d|cffc7c7cf银|r ", silver )
  end
  if copper_remain > 0 or result == "" then
    result = result .. string.format( "|cffffffff%d|cffeda55f铜|r ", copper_remain )
  end

  return result
end

---@param money number
function EHMailTM.update_money( money )
  m.money_received = (m.money_received or 0) + money
  m.api.MoneyReceived:SetText( L[ "Money received" ] .. ": " .. m.format_money( m.money_received ) )

  -- 调整到自动到付底部中央
  m.api.MoneyReceived:ClearAllPoints()
  m.api.MoneyReceived:SetPoint("BOTTOM", m.api.EHMailTMCODCheckButton, "BOTTOM", 11, -13)
  
  if m.money_received > 0 then
    m.api.MoneyReceived:Show()
  else
    m.api.MoneyReceived:Hide()
  end
end

--- GetItemInfo 未回包时返回 nil，解析结果需缓存
function EHMailTM.get_item_name( link )
  if not link or link == "" then return nil end
  local cached = m.item_name_cache[ link ]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end

  local ok, name = pcall( m.api.GetItemInfo, link )
  if ok and name and name ~= "" then
    m.item_name_cache[ link ] = name
    return name
  end
  m.item_name_cache[ link ] = false
  return nil
end

---@param i number
---@param manual boolean?
function EHMailTM.inbox_open( i, manual )
  m.debug( "inbox_open" )
  local package_icon, _, sender, subject, money, cod, _, has_item, read, returned, _, _, gm = m.api.GetInboxHeaderInfo( i )

  -- 竞得邮件的花费只在正文里，邮件头 money 恒为 0
  local body = m.api.GetInboxText( i )

  if has_item then
    if not m.received_icon then
      m.received_item = m.api.GetInboxItem( i )
      m.received_icon = package_icon
      -- COD 会在取件付款后被清掉、附件会在 TakeInboxItem 后清空，都得提前取
      m.received_cod = (cod and cod > 0) and cod or nil
      m.received_item_name = m.get_item_name( m.received_item )
    end
  end

  -- ★0.3.3（用户定）：未读邮件也要记 —— 原条件 `read or manual` 让「批量取件」时未读邮件**一条都不记**
  --   （真机证据：存档 tm_log.Received/Sent 两个族全空，而收件箱里明明有邮件）。
  --   ★ 顺带堵上游的老毛病：同一封邮件反复打开会**重复入账** ⇒ 内容键 + 2 秒窗去重
  --   （不用 GetTime 差值判会漏掉「点开-关闭-再点开」那一串，也会把同一批里的不同邮件误并）。
  local log_key = tostring( sender ) .. "|" .. tostring( subject ) .. "|" .. tostring( money )
    .. "|" .. tostring( m.received_item_name or "" )
  local now = GetTime()
  local dup = ( log_key == m.log_last_key ) and ( now - ( m.log_last_at or 0 ) ) < 2
  if not dup then
    m.log_last_key = log_key
    m.log_last_at = now
  end
  if not dup then
    if money > 0 then
      m.update_money( money )
      m.received_money = money
    end
    if money == 0 or manual then
      local money_logged = manual and money or m.received_money
      -- 竞得邮件的花费是发票式排版（付费金额用钱币图标渲染），正文文本里没有数字可解析，
      -- 走 GetInboxInvoiceInfo（已在 WoW.exe 字符串里验证存在）：返回第 4 值 = 金额
      if ( not money_logged or money_logged == 0 ) and classify_ah_mail( subject ) == "Won" then
        local ok, _, _, _, inv_money = pcall( m.api.GetInboxInvoiceInfo, i )
        if ok and inv_money and inv_money > 0 then
          money_logged = inv_money
        else
          -- 兜底：万一某些客户端把金额写进正文文本
          local bid = m.parse_body_money( body )
          if bid then money_logged = bid end
        end
      end
      m.log.add( "Received", {
        from = sender,
        subject = subject,
        money = money_logged,
        cod = m.received_cod or cod,
        returned = returned,
        gm = gm,
        icon = m.received_icon,
        item = m.received_item,
        item_name = m.received_item_name,
        body = body
      } )
      m.received_money = 0
      m.received_icon = nil
      m.received_item = nil
      m.received_item_name = nil
      m.received_cod = nil
    end
  end

  m.TakeInboxMoney( i )
  m.TakeInboxItem( i )
  m.DeleteInboxItem( i )

end

function EHMailTM.inbox_update_lock()
  for i = 1, 7 do
    m.api[ "MailItem" .. i .. "ButtonIcon" ]:SetDesaturated( m.inbox_opening )
    if m.inbox_opening then
      m.api[ "MailItem" .. i .. "Button" ]:SetChecked( nil )
    end
  end
end

-- ★0.3.3：不再接管 UpdateUIPanelPositions —— 原先在这个钩子里恢复我们记的位置，
-- 而宿主「拖拽图层」也在管 MailFrame 的位置（真机存档里就有它的 dx/dy 记录）⇒ 两边必然互抢。
-- 现在位置完全归客户端与宿主，本插件一个字节都不写。

function EHMailTM.hook.GetInboxHeaderInfo( ... )
  local sender, canReply = arg[ 3 ], arg[ 12 ]
  if sender and canReply then
    m.add_auto_complete_name( sender )
  end

  return m.orig.GetInboxHeaderInfo( unpack( arg ) )
end

function EHMailTM.hook.OpenMail_Reply( ... )
  m.api.EHMailTM_To = nil
  return m.orig.OpenMail_Reply( unpack( arg ) )
end

function EHMailTM.hook.InboxFrame_Update()
  m.orig.InboxFrame_Update()
  for i = 1, 7 do
    -- hack for tooltip update
    m.api[ "MailItem" .. i ]:Hide()
    m.api[ "MailItem" .. i ]:Show()
  end

  local currentPage = m.api.InboxFrame.pageNum
  local totalPages = math.ceil( m.api.GetInboxNumItems() / m.api.INBOXITEMS_TO_DISPLAY )
  local text = totalPages > 0 and (currentPage .. "/" .. totalPages) or m.api.EMPTY
  m.api.InboxTitleText:SetText( m.api.INBOX .. " [" .. text .. "]" )

  -- ★0.3.16：开关按钮的自绘视觉要等「窗真的显示出来」再重申（本客户端「隐藏态写属性不落地」）。
  --   这一腿**自终止**：`panel_toggle_apply_icon` 在按钮可见时置 `m.toggle_visual_ok`。
  if not m.toggle_visual_ok and m.panel_toggle_apply_icon then
    m.panel_toggle_apply_icon()
  end

  m.inbox_update_lock()
end

---@param i number
function EHMailTM.hook.InboxFrame_OnClick( i )
  if m.inbox_opening or arg1 == "RightButton" and (m.api.EHMailTM_AutoCOD ~= 1) and ({ m.api.GetInboxHeaderInfo( i ) })[ 6 ] > 0 then --新增自动到付选项
    this:SetChecked( nil )
  elseif arg1 == "RightButton" then
    -- 预取正文/发票并排队延迟开信：竞得邮件的发票金额要等服务器回包，
    -- 右键当场读是 0（邮件随后就删了，再没机会补），日志里就成了"花费:?"
    m.api.GetInboxText( i )
    m.api.GetInboxInvoiceInfo( i )
    m.delayed_opens = m.delayed_opens or {}
    tinsert( m.delayed_opens, { i = i, frames = 10 } )
  else
    return m.orig.InboxFrame_OnClick( i )
  end
end

function EHMailTM.hook.InboxFrameItem_OnEnter()
  m.orig.InboxFrameItem_OnEnter()
  if m.api.GetInboxItem( this.index ) then
    m.api.GameTooltip:AddLine( m.api.ITEM_OPENABLE, "", 0, 1, 0 )
    m.api.GameTooltip:Show()
  end
end

function EHMailTM.hook.SendMailFrame_Update()
  local gap
  local last = m.sendmail_num_attachments()

  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]

    local texture, count
    if btn.item then
      texture, count = m.api.GetContainerItemInfo( btn.item[ 1 ], btn.item[ 2 ] )
    end
    if not texture then
      btn:SetNormalTexture( nil )
      m.api[ btn:GetName() .. "Count" ]:Hide()
      btn.item = nil
    else
      btn:SetNormalTexture( texture )
      if count > 1 then
        m.api[ btn:GetName() .. "Count" ]:Show()
        m.api[ btn:GetName() .. "Count" ]:SetText( count )
      else
        m.api[ btn:GetName() .. "Count" ]:Hide()
      end
    end
  end

  if m.sendmail_num_attachments() > 0 then
    m.api.SendMailCODButton:Enable()
    m.api.SendMailCODButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    if m.sendmail_num_attachments() > 1 and m.api.SendMailCODButton:GetChecked() then
      m.api.SendMailCODAllButton:Enable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    else
      m.api.SendMailCODAllButton:Disable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
      m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND )
    end
  else
    m.api.SendMailSendMoneyButton:SetChecked( 1 )
    m.api.SendMailCODButton:SetChecked( nil )
    m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND )
    m.api.SendMailCODButton:Disable()
    m.api.SendMailCODButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
    m.api.SendMailCODAllButton:Disable()
    m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
  end

  m.api.MoneyFrame_Update( "SendMailCostMoneyFrame", m.api.GetSendMailPrice() * math.max( 1, m.sendmail_num_attachments() ) )

  -- Determine how many rows of attachments to show
  local itemRowCount = 1
  local temp = last
  while temp > ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND do
    itemRowCount = itemRowCount + 1
    temp = temp - ATTACHMENTS_PER_ROW_SEND
  end

  if not gap and temp == ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND then
    itemRowCount = itemRowCount + 1
  end
  if m.api.SendMailFrame.maxRowsShown and last > 0 and itemRowCount < m.api.SendMailFrame.maxRowsShown then
    itemRowCount = m.api.SendMailFrame.maxRowsShown
  else
    m.api.SendMailFrame.maxRowsShown = itemRowCount
  end

  -- Compute sizes
  local cursorx = 0
  local cursory = itemRowCount - 1
  local marginxl = 8 + 6
  local marginxr = 40 + 6
  local areax = m.api.SendMailFrame:GetWidth() - marginxl - marginxr
  local iconx = m.api.MailAttachment1:GetWidth() + 2
  local icony = m.api.MailAttachment1:GetHeight() + 2
  local gapx1 = m.api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND)) / (ATTACHMENTS_PER_ROW_SEND - 1) )
  local gapx2 = m.api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND) - (gapx1 * (ATTACHMENTS_PER_ROW_SEND - 1))) / 2 )
  local gapy1 = 5
  local gapy2 = 6
  local areay = (gapy2 * 2) + (gapy1 * (itemRowCount - 1)) + (icony * itemRowCount)
  local indentx = marginxl + gapx2 + 17
  local indenty = 170 + gapy2 + icony - 13
  local tabx = (iconx + gapx1) - 3 --this magic number changes the attachment spacing
  local taby = (icony + gapy1)
  local scrollHeight = 249 - areay

  m.api.MailHorizontalBarLeft:SetPoint( "TOPLEFT", m.api.SendMailFrame, "BOTTOMLEFT", 2 + 15, 184 + areay - 14 )

  m.api.SendMailScrollFrame:SetHeight( scrollHeight )
  m.api.SendMailScrollChildFrame:SetHeight( scrollHeight )

  -- ★移植适配（**真机报错换来的**）：这一条 region 在本客户端**可能不存在**
  -- （真机 `EHMailTM.lua:1871 attempt to call method 'SetTexCoord' (a nil value)`，而探针那一刻量到的是 3 个
  --   ⇒ **数量会随状态变，读数只能当参考**）⇒ 「够了才设」，拿不到就跳过
  -- （皮肤线画不出来，界面照旧可用）。
  local scrollRs = { m.api.SendMailScrollFrame:GetRegions() }
  local SendMailScrollFrameTop = scrollRs[ 3 ]
  if SendMailScrollFrameTop and type(SendMailScrollFrameTop.SetTexCoord) == "function" then
    SendMailScrollFrameTop:SetHeight( scrollHeight )
    SendMailScrollFrameTop:SetTexCoord( 0, .484375, 0, scrollHeight / 256 )
  end

  m.api.StationeryBackgroundLeft:SetHeight( scrollHeight )
  m.api.StationeryBackgroundLeft:SetTexCoord( 0, 1, 0, scrollHeight / 256 )


  m.api.StationeryBackgroundRight:SetHeight( scrollHeight )
  m.api.StationeryBackgroundRight:SetTexCoord( 0, 1, 0, scrollHeight / 256 )

  -- Set Items
  for i = 1, ATTACHMENTS_MAX do
    if cursory >= 0 then
      m.api[ "MailAttachment" .. i ]:Enable()
      m.api[ "MailAttachment" .. i ]:Show()
      m.api[ "MailAttachment" .. i ]:SetPoint( "TOPLEFT", "SendMailFrame", "BOTTOMLEFT", indentx + (tabx * cursorx),
        indenty + (taby * cursory) )

      cursorx = cursorx + 1
      if cursorx >= ATTACHMENTS_PER_ROW_SEND then
        cursory = cursory - 1
        cursorx = 0
      end
    else
      m.api[ "MailAttachment" .. i ]:Hide()
    end
  end

  m.api.SendMailFrame_CanSend()
end

function EHMailTM.hook.SendMailRadioButton_OnClick( index )
  if (index == 1) then
    m.api.SendMailSendMoneyButton:SetChecked( 1 );
    m.api.SendMailCODButton:SetChecked( nil );
    m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND );
    m.api.SendMailCODAllButton:Disable()
    m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
  else
    m.api.SendMailSendMoneyButton:SetChecked( nil );
    m.api.SendMailCODButton:SetChecked( 1 );
    m.api.SendMailMoneyText:SetText( m.api.COD_AMOUNT );

    if m.sendmail_num_attachments() > 1 then
      m.api.SendMailCODAllButton:Enable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    end
  end
  m.api.PlaySound( "igMainMenuOptionCheckBoxOn" );
end

function EHMailTM.hook.ClickSendMailItemButton()
  -- ★0.3.11：这条 hook **原样透传**（保留 hook 只是为了 PLAYER_LOGIN 仍然填好 `m.orig.ClickSendMailItemButton`，
  --   发送那一步要用它）。本插件**不再从客户端寄件栏抓附件** —— 附件改由「选择列表」纯数据驱动；
  --   玩家若自己往客户端寄件栏里塞了东西，那属于残留，开批前的硬停会如实拦下（不替他清）。
  return m.orig.ClickSendMailItemButton()
end

function EHMailTM.hook.GetContainerItemInfo( bag, slot )
  local ret = pack( m.orig.GetContainerItemInfo( bag, slot ) )
  ret[ 3 ] = ret[ 3 ] or m.sendmail_attached( bag, slot ) and 1 or nil
  return unpack( ret )
end

function EHMailTM.hook.PickupContainerItem( bag, slot )
  -- ★★★0.3.11 起：**挂附件 = 纯数据**（用户 2026-10-10 定：「右键某个物品**只是**将该物品添加这个变量列表内」+
  --   「绝不碰鼠标拿起放下的行为.容易卡住物品」）⇒ 这条分支**一个物品操作都不做**：
  --   不 ClearCursor、不 PickupContainerItem、不碰客户端寄件栏。
  --   ★旧写法（走到 `sendmail_pickup_mailable` 那套「ClearCursor → 塞进邮寄槽 → 读回 → 取出」）
  --     正是「拿不起来 / 光标忙 / 发送 7 件只出去 3 件」那一族的源头 ⇒ 整条已删。
  if not ( m.api.MailFrame and m.api.MailFrame:IsVisible() ) then
    return m.orig.PickupContainerItem( bag, slot )
  end

  -- Alt+左键：一键把背包里所有**同 id** 的物品加进选择列表（同样是纯数据批量，一件都不拿）
  if arg1 == "LeftButton" and m.api.IsAltKeyDown() then
    local link = m.multi_link( bag, slot )
    local _, _, itemId = string.find( link or "", "item:(%d+)" )
    if not itemId then
      m.info( "Alt+左键：这一格没有可识别的物品 ⇒ 什么都没做" )
      return
    end
    itemId = tonumber( itemId )
    local added, dup, full = 0, 0, 0
    for b = 0, 4 do
      local slots = m.api.GetContainerNumSlots( b )
      for s = 1, slots do
        local l = m.multi_link( b, s )
        if l then
          local _, _, id = string.find( l, "item:(%d+)" )
          if id and tonumber( id ) == itemId then
            local r = m.multi_add( b, s, true )
            if r == "ok" then added = added + 1
            elseif r == "dup" then dup = dup + 1
            elseif r == "full" then full = full + 1 end
          end
        end
      end
    end
    m.multi_project()
    m.info( string.format( "Alt+左键：同种物品加进选择列表 %d 件（已有 %d ｜ 因满未加 %d）⇒ 列表共 %d 条",
      added, dup, full, getn( m.multi_list ) ) )
    return
  end

  if m.multi_has( bag, slot ) then
    if arg1 == "RightButton" then
      -- ★右键 = **只从列表删掉这一条**（用户定：「附件内的右键也只是删除某个物品在这个列表内的数据」）
      --   注意：**不**执行原始取件（否则物品会被真的拿起来 = 又回到「卡住物品」那条路）
      m.multi_del( bag, slot )
      m.multi_project()
      return
    end
    -- ★左键 = **完全交回客户端**（拿起/放下，用户定「保持客户端原样…不动」）：
    --   列表这一条**留着** —— 物品若放回原处，链接对得上，这一条照样有效；
    --   若挪走/换成别的东西，投影不会再显示它，发送那一步也会如实「跳过 + 点名」。
    return m.orig.PickupContainerItem( bag, slot )
  end

  if m.api.GetContainerItemInfo( bag, slot ) then
    if arg1 == "RightButton" then
      -- ★右键 = **只把这一件加进选择列表**（不真拿、不真放；附件格随后从列表重排）
      m.sendmail_show_send_tab()
      if m.multi_add( bag, slot ) == "ok" then m.multi_project() end
      return
    end
    m.set_cursor_item( { bag, slot } )
  end
  return m.orig.PickupContainerItem( bag, slot )
end

function EHMailTM.hook.SplitContainerItem( bag, slot, amount )
  if m.sendmail_attached( bag, slot ) then return end
  return m.orig.SplitContainerItem( bag, slot, amount )
end

function EHMailTM.hook.UseContainerItem( bag, slot, onself )
  if m.sendmail_attached( bag, slot ) then return end
  if m.api.IsShiftKeyDown() or m.api.IsControlKeyDown() or m.api.IsAltKeyDown() then
    return m.orig.UseContainerItem( bag, slot, onself )
  elseif m.api.MailFrame:IsVisible() then
    -- 邮箱开着时「使用」= 加进选择列表（上游就是这个交互；0.3.11 起同样是**纯数据**：不动物品）
    m.sendmail_show_send_tab()
    if m.multi_add( bag, slot ) == "ok" then m.multi_project() end
  elseif m.api.TradeFrame:IsVisible() then
    for i = 1, 6 do
      if not m.api.GetTradePlayerItemLink( i ) then
        m.orig.PickupContainerItem( bag, slot )
        m.api.ClickTradeButton( i )
        return
      end
    end
  else
    return m.orig.UseContainerItem( bag, slot, onself )
  end
end

function EHMailTM.hook.SendMailFrame_CanSend()
  if not m.sendmail_sending and string.len( m.api.SendMailNameEditBox:GetText() ) > 0 and (m.api.SendMailSendMoneyButton:GetChecked() and m.api.MoneyInputFrame_GetCopper( m.api.SendMailMoney ) or 0) + m.api.GetSendMailPrice() * math.max( 1, m.sendmail_num_attachments() ) <= m.api.GetMoney() then
    MailMailButton:Enable()
  else
    MailMailButton:Disable()
  end
end

function EHMailTM.hook.MailFrameTab_OnClick( tab )
  if not tab then
    tab = this:GetID()
  end

  if tab == 3 then
    m.api.PanelTemplates_SetTab( m.api.MailFrame, 3 )
    m.api.InboxFrame:Hide()
    m.api.SendMailFrame:Hide()
    m.api.EHMailTMLogFrame:Show()
    m.api.MailFrameTopLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopLeft" )
    m.api.MailFrameTopRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopRight" )
    m.api.MailFrameBotLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotLeft" )
    m.api.MailFrameBotRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotRight" )
    m.api.MailFrameTopLeft:SetPoint( "TOPLEFT", "MailFrame", "TOPLEFT", 2, -1 )
    m.log.populate( "Received" )
    return
  else
    m.api.EHMailTMLogFrame:Hide()
  end

  m.orig.MailFrameTab_OnClick( tab )

  -- ★0.3.10 测试档：切到发件页时把「多选列表」自动渲染进附件格（= 记账，等同已挂载）。
  --   默认开（用户指定「现在测试默认显示背包格1-4 的物品」）；`/tm 多选 自动` 可关。
  --   ★先出声再动手：这是**会改变寄出内容**的行为，绝不静默。
  if tab == 2 and m.multi_auto and not m.multi_quiet and type( m.multi_project ) == "function" and getn( m.multi_list ) > 0 then
    local shown = m.multi_project()
    m.info( string.format( "附件选择列表 %d 条已投影到附件格（挂上 %d 格）—— 按【发送】就会把这些格上的物品寄出去；不想要就 /tm 附件 清 或 /tm 附件 自动",
      getn( m.multi_list ), shown ) )
  end
end

function EHMailTM.hook.OpenMailFrame_OnHide()
  if m.api.InboxFrame.openMailID then
    local package_icon, _, sender, subject, money, cod, _, itemID, _, returned, text_created, _, gm = m.api.GetInboxHeaderInfo( m.api.InboxFrame.openMailID )
    if (money == 0 and not itemID and text_created) then
      local received_item = m.api.GetInboxItem( m.api.InboxFrame.openMailID )
      m.log.add( "Received", {
        from = sender,
        subject = subject,
        money = money,
        cod = cod,
        returned = returned,
        gm = gm,
        icon = package_icon,
        item = received_item
      } )
    end
  else
    m.debug( "returning mail" )
  end

  m.orig.OpenMailFrame_OnHide()
end

function EHMailTM.send_mail_button_onclick()
  m.api.MailAutoCompleteBox:Hide()

  -- ★★★0.3.12（用户需求②）：**发件前先把「光标上还拖着东西」处理掉** ——
  --   有拖拽 ⇒ 认源格 ⇒ `PickupContainerItem` 放回原处（**绝不 ClearCursor**）⇒ 读回自证；
  --   认不出源格 / 放不回去 ⇒ 如实说一句并**停下**（一件都不寄）—— 与下面那条「寄件栏有残留就硬停」
  --   同一把尺子：拿不到证据就一个字节都不碰，让玩家自己处理。
  --   ★为什么值得停下：光标上挂着东西时，我们那串 `ClearCursor` → `ClickSendMailItemButton` →
  --     `PickupContainerItem` 的挂件序列正好会与「手里那件东西」抢同一个光标（历史上就是「光标忙 /
  --     之后什么都拿不起来」那一族）⇒ 先把手清干净，再走那条已验证的序列。
  if m.cursor_clear( "发件前清理光标上的拖拽" ) ~= true then
    m.info( "  已停下、没有寄出：请把光标上那件东西放下（或放回背包）后再点【发送】" )
    m.sendmail_sending = false
    return
  end

  -- ★★★【发送】的**唯一入口**（0.3.11 起）：点客户端那个【发送】按钮 → 这里。
  --   客户端 XML 的 OnClick 是按名字调全局 `SendMailMailButton_OnClick()`（本插件已把它指向本函数），
  --   另外 `sendmail_load` 还把**真按钮的 OnClick 脚本**也直接指到本函数（双保险，见那里的注释）。
  --
  --   数据来源 = **选择列表**（`m.multi_list`）的投影：`m.multi_project()` 先按列表把附件格重排一次，
  --   随后照旧读 `sendmail_attachments()`（= 投影）当队列 ⇒ 「列表 = 寄什么」这条链只有一处真值。
  m.multi_project()

  -- ★★★开批前先看**客户端附件栏**：有东西（= 我们没放过的残留，玩家以前用拖放塞进去的）
  --   ⇒ **本批直接停下，一个字节都不碰**。
  --   ★真机实证（0.3.3 第三轮）为什么必须硬停而不是「提示一句照旧往下跑」：
  --     上游清空附件栏的三步（ClearCursor → ClickSendMailItemButton → ClearCursor）会把**玩家的残留物
  --     从附件栏拿到光标上又清掉**，此后客户端进入「光标忙」状态 —— `CursorHasItem()` 报**空**
  --     （我们的光标守卫完全看不见它），但**之后每一次 `PickupContainerItem` 都被客户端拒绝**
  --     ⇒ 全批「拿不起来」（真机读数：`该格现在= [清凉的泉水] ｜ 光标上=空 ｜ 寄件栏=空 ｜ 连试 4 次`，
  --     即物品**从未离开背包**）；子插件 `EH_Bag` 的「右键直投 → 邮件附件栏」同时报同款失败也是它。
  --   ⇒ 附件栏里的东西不是我们放的 ⇒ 依「拿不到证据就一个字节都不碰」，**不替他清、也不发这一批**。
  if m.api.GetSendMailItem() then
    m.info( "  寄件栏里已经有一件东西（不是本插件放的）—— 已停下，没有寄出" )
    m.info( "  请先点一下寄件栏把那件东西取出（或重启客户端），然后再发一次" )
    m.sendmail_sending = false
    return
  end
  m.api.EHMailTM_To = m.api.SendMailNameEditBox:GetText()
  m.api.SendMailNameEditBox:HighlightText()

  m.sendmail_state = {
    to = m.api.EHMailTM_To,
    subject = MailSubjectEditBox:GetText(),
    body = m.api.SendMailBodyEditBox:GetText(),
    money = m.api.MoneyInputFrame_GetCopper( m.api.SendMailMoney ),
    cod = m.api.SendMailCODButton:GetChecked(),
    attachments = m.sendmail_attachments(),
    numMessages = math.max( 1, m.sendmail_num_attachments() ),
  }

  -- ★每批开始复位三个会话计数（与 m.batch_last_at 同一口径）：
  --   不复位 ⇒ 上一批硬停（光标留件那条路）时攒下的「跳过 / 拿不起来」会算进这一批的汇总，
  --   而 sendmail_retry 会带着上一批的连续失败数起跑 ⇒ **这一批的第一件一失败就被判超限**。
  m.sendmail_skipped = nil
  m.sendmail_failed = nil
  m.sendmail_retry = 0
  -- 这一批真正寄出去的 {包,格}（批末据此把它们从选择列表里摘掉；见 sendmail_send 收尾）
  m.multi_sent = {}

  m.sendmail_clear()
  m.sendmail_sending = true
  m.sendmail_send()
end

function EHMailTM.sendmail_load()
  m.api.SendMailFrame:EnableMouse( false )

  m.api.SendMailFrame:CreateTexture( "MailHorizontalBarLeft", "BACKGROUND" )
  m.api.MailHorizontalBarLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar" )
  m.api.MailHorizontalBarLeft:SetWidth( 256 )
  m.api.MailHorizontalBarLeft:SetHeight( 16 )
  m.api.MailHorizontalBarLeft:SetTexCoord( 0, 1, 0, .25 )

  m.api.SendMailFrame:CreateTexture( "MailHorizontalBarRight", "BACKGROUND" )
  m.api.MailHorizontalBarRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar" )
  m.api.MailHorizontalBarRight:SetWidth( 75 )
  m.api.MailHorizontalBarRight:SetHeight( 16 )
  m.api.MailHorizontalBarRight:SetTexCoord( 0, .29296875, .25, .5 )
  m.api.MailHorizontalBarRight:SetPoint( "LEFT", m.api.MailHorizontalBarLeft, "RIGHT" )

  m.api.SendMailMoneyText:SetJustifyH( "LEFT" )
  m.api.SendMailMoneyText:SetPoint( "TOPLEFT", 0, 0 )
  m.api.SendMailMoney:ClearAllPoints()
  m.api.SendMailMoney:SetPoint( "TOPLEFT", m.api.SendMailMoneyText, "BOTTOMLEFT", 5, -5 )
  m.api.SendMailMoneyGoldRight:SetPoint( "RIGHT", 20, 0 )
  do
    -- ★移植适配（R11）：本客户端这个 EditBox 实测只有 4 个 region，
    -- 原版直接取 [ 9 ] 会 nil 索引（而且无 pcall、跑在载入期）⇒ 改成「够才设」，语义不变。
    local rs = { m.api.SendMailMoneyGold:GetRegions() }
    if rs[ 9 ] and type(rs[ 9 ].SetDrawLayer) == "function" then rs[ 9 ]:SetDrawLayer( "BORDER" ) end
  end
  m.api.SendMailMoneyGold:SetMaxLetters( 7 )
  m.api.SendMailMoneyGold:SetWidth( 50 )
  m.api.SendMailMoneySilverRight:SetPoint( "RIGHT", 10, 0 )
  do
    -- ★移植适配（R11）：本客户端这个 EditBox 实测只有 4 个 region，
    -- 原版直接取 [ 9 ] 会 nil 索引（而且无 pcall、跑在载入期）⇒ 改成「够才设」，语义不变。
    local rs = { m.api.SendMailMoneySilver:GetRegions() }
    if rs[ 9 ] and type(rs[ 9 ].SetDrawLayer) == "function" then rs[ 9 ]:SetDrawLayer( "BORDER" ) end
  end
  m.api.SendMailMoneySilver:SetWidth( 28 )
  m.api.SendMailMoneySilver:SetPoint( "LEFT", m.api.SendMailMoneyGold, "RIGHT", 30, 0 )
  m.api.SendMailMoneyCopperRight:SetPoint( "RIGHT", 10, 0 )
  do
    -- ★移植适配（R11）：本客户端这个 EditBox 实测只有 4 个 region，
    -- 原版直接取 [ 9 ] 会 nil 索引（而且无 pcall、跑在载入期）⇒ 改成「够才设」，语义不变。
    local rs = { m.api.SendMailMoneyCopper:GetRegions() }
    if rs[ 9 ] and type(rs[ 9 ].SetDrawLayer) == "function" then rs[ 9 ]:SetDrawLayer( "BORDER" ) end
  end
  m.api.SendMailMoneyCopper:SetWidth( 28 )
  m.api.SendMailMoneyCopper:SetPoint( "LEFT", m.api.SendMailMoneySilver, "RIGHT", 20, 0 )
  m.api.SendMailSendMoneyButton:SetPoint( "TOPLEFT", m.api.SendMailMoney, "TOPRIGHT", 20, 25 )

  -- hack to avoid automatic subject setting and button disabling from weird blizzard code
  MailMailButton = m.api.SendMailMailButton
  m.api.SendMailMailButton = setmetatable( {}, { __index = function() return function() end end } )
  m.api.SendMailMailButton_OnClick = m.send_mail_button_onclick
  -- ★★★【发送】按钮拦截（0.3.11 补的第二条腿，用户 2026-10-10 定「拦截」）：
  --   客户端 `MailFrame.xml` 里那个按钮的 OnClick 就是一句 `SendMailMailButton_OnClick();`（按**名字**调全局）
  --   ⇒ 覆盖那个全局已经等于拦截（上面一行）。这里再把**真按钮自己的 OnClick 脚本**直接指到本函数：
  --   · 别的插件若把全局改回原版，按钮仍然走我们这条路（单次调用，不重复）；
  --   · ★真按钮句柄 = 全局 `MailMailButton` —— `SendMailMailButton` 这个全局**已被上一行换成空壳**，
  --     拿 `m.api.SendMailMailButton` 是拿不到真对象的（这是本移植版刻意的 hack）。
  --   ★拿不到/设不上 ⇒ 一个字节都不动，全局那一条腿照旧生效（fail-open）。
  if MailMailButton and type( MailMailButton.SetScript ) == "function" then
    pcall( MailMailButton.SetScript, MailMailButton, "OnClick", function() m.send_mail_button_onclick() end )
  end
  MailSubjectEditBox = m.api.SendMailSubjectEditBox
  m.api.SendMailSubjectEditBox = setmetatable( {}, {
    __index = function( _, key )
      return function( _, ... )
        return MailSubjectEditBox[ key ]( MailSubjectEditBox, unpack( arg ) )
      end
    end,
  } )

  m.api.SendMailNameEditBox._SetText = m.api.SendMailNameEditBox.SetText
  function m.api.SendMailNameEditBox:SetText( ... )
  -- 确保在选择新收件人时能正常更新输入框内容
    local text = unpack(arg)
	 self:_SetText(text)
  end

  m.api.SendMailNameEditBox:SetScript( "OnShow", function()
    if m.api.EHMailTM_To then
      m.api.this:_SetText( m.api.EHMailTM_To )
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnChar", function()
    m.api.EHMailTM_To = nil
    GetSuggestions()
  end )
  m.api.SendMailNameEditBox:SetScript( "OnTabPressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      if m.api.IsShiftKeyDown() then
        m.previous_match()
      else
        m.next_match()
      end
    else
      MailSubjectEditBox:SetFocus()
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnEnterPressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      m.api.MailAutoCompleteBox:Hide()
      this:HighlightText( 0, 0 )
    else
      MailSubjectEditBox:SetFocus()
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnEscapePressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      m.api.MailAutoCompleteBox:Hide()
    else
      this:ClearFocus()
    end
  end )
  function m.api.SendMailNameEditBox.focusLoss()
    m.api.MailAutoCompleteBox:Hide()
  end

  m.api.SendMailCODAllButtonText:SetText( L[ "All mails" ] )
  m.api.SendMailCODAllButton:SetScript( "OnClick", m.set_cod_text )

  do

  end

  for _, editBox in { m.api.SendMailNameEditBox, m.api.SendMailSubjectEditBox } do
    editBox:SetScript( "OnEditFocusGained", function()
      this:HighlightText()
    end )
    editBox:SetScript( "OnEditFocusLost", function()
      (this.focusLoss or function() end)()
      this:HighlightText( 0, 0 )
    end )
    do
      local lastClick
      editBox:SetScript( "OnMouseDown", function()
        local x, y = m.api.GetCursorPosition()
        if lastClick and m.api.GetTime() - lastClick.t < .5 and x == lastClick.x and y == lastClick.y then
          this:SetScript( "OnUpdate", function()
            this:HighlightText()
            this:SetScript( "OnUpdate", nil )
          end )
        end
        lastClick = { t = m.api.GetTime(), x = x, y = y }
      end )
    end
  end

  -- ★★★附件格的鼠标完全由我们接管（0.3.3 起；0.3.11 起处理体的语义改成「只删列表数据」）：
  --   上游写好了 attachment_button_on_click 却**从来没有挂到任何控件上**（全文件零引用）⇒
  --   附件格的点击与拖放仍是客户端自己的行为：拖着物品放到附件格 ⇒ 客户端**真的**把它放进客户端附件栏
  --   （界面/记账/背包三份状态各说各话）⇒ 之后 `PickupContainerItem` 拿不起来（真机「连试 4 次」）。
  --   ⇒ 现在：点击 = `m.attachment_button_on_click`（**只从选择列表删这一条**，不动物品、不碰光标）·
  --     **拖放 = 由我们接管**（0.3.12）：拖着物品松手落在附件格上 ⇒ `m.attachment_receive_drag`
  --     **只把那一件加进选择列表、再把这次拖拽取消掉**（认源格 ⇒ `PickupContainerItem` 放回原处 ⇒ 读回自证），
  --     客户端寄件栏**一个字节都不会被塞进去**（这正是 0.3.3 那条「拖放会被客户端真塞进附件栏、
  --     此后整条取件通道被堵死」的病根）⇒ 撤掉拖拽注册那条照旧保留。
  --   ★加进列表的另一条入口 = 「右键背包里的物品」（`hook.PickupContainerItem` ⇒ `m.multi_add`，纯数据）。
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn then
      btn:SetScript( "OnClick", m.attachment_button_on_click )
      btn:RegisterForClicks( "LeftButtonUp", "RightButtonUp" )
      btn:SetScript( "OnReceiveDrag", m.attachment_receive_drag )
      -- ★0.3.13：悬停改成**我们的信息引导**（占用格 = 客户端物品信息 + 追加两行；空格 = 只出引导）
      btn:SetScript( "OnEnter", m.attachment_button_on_enter )
      btn:SetScript( "OnLeave", m.attachment_button_on_leave )
      btn:SetScript( "OnDragStart", nil )
      pcall( btn.RegisterForDrag, btn )
    end
  end
end

--@param bag number
--@param slot number
function EHMailTM.sendmail_attached( bag, slot )
  if not m.api.MailFrame:IsVisible() then return false end
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn.item and btn.item[ 1 ] == bag and btn.item[ 2 ] == slot then
      return true
    end
  end
  if m.sendmail_state then
    for _, attachment in m.sendmail_state.attachments do
      if attachment[ 1 ] == bag and attachment[ 2 ] == slot then
        return true
      end
    end
  end
end

-- 已经在发信页就别再切一次：MailFrameTab_OnClick 会连带 Hide/Show 一整套 + 一次完整 Update
function EHMailTM.sendmail_show_send_tab()
  if not m.api.SendMailFrame:IsVisible() then
    m.api.MailFrameTab_OnClick( 2 )
  end
end

-- ★★★附件格的点击（0.3.11 起）= **只从选择列表里删掉这一条数据**（用户 2026-10-10 定：
--   「附件内的右键也只是删除某个物品在这个列表内的数据」；左键同样只删、不再与光标换物品）：
--   · 不 PickupContainerItem、不 ClearCursor、不动物品 —— 这一支以前会「拿起 → 放回 → 清光标」，
--     正是「附件格里的东西被拿走 / 内部数据不更新 / 客户端此后拒绝取件」那一族的老路，整条去掉。
--   · 删完由 `m.multi_project()` 从列表重排展示 ⇒ 列表 = 显示的**唯一真值**。
function EHMailTM.attachment_button_on_click()
  local it = this and this.item
  if not ( it and it[ 1 ] and it[ 2 ] ) then
    m.info( "这一格是空的（选择列表里没有这一条）" )
    return
  end
  m.multi_del( it[ 1 ], it[ 2 ] )
  m.multi_project()
end

-- ★★★下面这两个函数**已按用户指令整条删除**（0.3.11；别再往回加）：
--   `sendmail_set_attachment` / `sendmail_pickup_mailable` —— 它们是「挂附件时真的去拿放物品」那条老路
--   （ClearCursor → PickupContainerItem → ClickSendMailItemButton → 读回 → ClickSendMailItemButton），
--   真机多轮报障（拿不起来 / 光标忙 / 发送 7 件只出去 3 件）全部源于它。
--   用户 2026-10-10 定：「**绝不碰鼠标拿起放下的行为.容易卡住物品**」⇒ 选择改走纯数据：
--   加 = `m.multi_add` · 删 = `m.multi_del` · 显示 = `m.multi_project` · 发送 = `send_mail_button_onclick`。
--   `sendmail_forget` / `sendmail_remove_attachment` 同批删除（它们的活由列表与投影接管）。

function EHMailTM.sendmail_num_attachments()
  local x = 0
  for i = 1, ATTACHMENTS_MAX do
    if m.api[ "MailAttachment" .. i ].item then
      x = x + 1
    end
  end
  return x
end

function EHMailTM.sendmail_attachments()
  local t = {}
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn.item then
      table.insert( t, btn.item )
    end
  end
  return t
end

function EHMailTM.sendmail_clear()
  -- ★★★0.3.11：**不再**「把附件格里的东西拿出来再清光标」。
  --   用户 2026-10-10 定：「绝不碰鼠标拿起放下的行为.容易卡住物品」；而且附件格现在只是
  --   **选择列表的投影**（客户端寄件栏全程是空的）⇒ 清显示 = 把投影抹掉，**一个物品操作都不做**。
  --   ★旧写法在这里 `PickupContainerItem(anyItem)` + `ClearCursor()`（上游那三步的翻版），
  --     正是「光标忙 / 之后什么都拿不起来」的入口之一 ⇒ 一并去掉。
  for i = 1, ATTACHMENTS_MAX do
    m.api[ "MailAttachment" .. i ].item = nil
  end
  MailMailButton:Disable()
  m.api.SendMailNameEditBox:SetText ""
  m.api.SendMailNameEditBox:SetFocus()
  MailSubjectEditBox:SetText ""
  m.api.SendMailBodyEditBox:SetText ""
  m.api.MoneyInputFrame_ResetMoney( m.api.SendMailMoney )
  m.api.SendMailRadioButton_OnClick( 1 )

  m.sendmail_queue_update()
end

-- 批量寄送：同一件挂不上寄件栏时**连续**重试几次（有界；超限才停下并如实报）
m.sendmail_retry_max = 3

function EHMailTM.sendmail_send()
  -- ★★★0.3.3 真机报障「发送多封偶尔报一次错」定案（**逐行对照过参考插件**）：
  --   参考插件（宿主 tmp/ 下那份原版源码的 sendmail_send）的挂件序列与本函数**逐字一致**
  --   （ClearCursor → ClickSendMailItemButton → ClearCursor → PickupContainerItem →
  --    ClickSendMailItemButton → not GetSendMailItem() 判定）⇒ **移植没有抄错**，报错不是移植引入的。
  --   参考插件的缺陷在**失败之后**：只往聊天框打一行 ERROR_CAPS（客户端本地化的「错误」）就 return，
  --   而 m.sendmail_sending 仍是 true、sendmail_update 再没人设 ⇒ **这一批静默卡死**
  --   （后面的件永远不再发，界面上却像还在发）—— 用户最初看到的 EHMailTM：错误 就是它。
  -- ⇒ 本文件只在**失败之后**加三件事（挂件序列与成功路径**一字未改**）：
  --   ① 光标上还拿着东西 ⇒ **绝不清光标**（清掉就是丢件 —— 与子插件 EH_Bag 的 DROP_CURSOR 同一口径），
  --      如实报一声停下，让玩家自己放；
  --   ② 挂不上寄件栏 ⇒ **放回队首 + 延迟一帧重试**（同一帧里紧挨着的 ClearCursor/Pickup 会撞
  --      客户端的物品锁，下一帧锁就松了）⇒ 一次抖动不再让整批中断；
  --   ③ 连续失败到 m.sendmail_retry_max 才停，并**如实报出物品名 + 现场诊断**（绝不静默漏寄）。
  if m.api.CursorHasItem and m.api.CursorHasItem() then
    m.info( string.format( L[ "Could not attach %s (it is still on your cursor) - this mail was not sent" ], "" ) )
    m.sendmail_sending = false
    return
  end

  -- ★限频：批量寄送与批量取件/退信/删除共用同一个闸（没到点就下一帧再来）
  if not m.batch_rate_ok() then
    m.sendmail_update = true
    return
  end

  local item = table.remove( m.sendmail_state.attachments, 1 )
  if item then
    -- ★★★挂件前先核对「那一格现在还是不是当初选的那一件」：
    --   条目 = `{ 包号, 格号, 选择时的链接 }`（0.3.11 起带身份）⇒ 读到空、或读到**别的链接**，
    --   都如实**跳过这一件并继续**（绝不拿「现在那一格里的东西」冒名寄出去）。
    --   ★为什么不在这里做「能不能邮寄」预检：用户 2026-10-10 定「不预警，让邮件发送自身函数报错/提示，
    --     **绝不碰鼠标拿起放下的行为，容易卡住物品**」⇒ 能不能寄只由真正的挂件序列回答。
    local nowLink = m.api.GetContainerItemLink( item[ 1 ], item[ 2 ] )
    if ( not nowLink ) or ( item[ 3 ] and nowLink ~= item[ 3 ] ) then
      m.sendmail_skipped = ( m.sendmail_skipped or 0 ) + 1
      m.info( string.format( "  附件（包 %d / 格 %d）%s —— 跳过这一件",
        item[ 1 ], item[ 2 ], nowLink and "那一格已经换成别的东西了" or "已不在原处" ) )
      m.sendmail_retry = 0
      m.sendmail_update = true
      return
    end
    m.api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
    -- ★条目现在是 `{ 包号, 格号, 链接 }` ⇒ 只把前两个交给客户端（多传一个链接没有意义）
    m.orig.PickupContainerItem( item[ 1 ], item[ 2 ] )
    -- ★决定性取证：**拿起之后立刻**读一次光标 —— 用来区分两种根因（下一轮真机一眼可判）：
    --   「拿起后=空」= 客户端**拒绝了这次 PickupContainerItem**（物品从未离开背包，
    --                  与我们的放置序列无关；`寄件栏=空` 也是此时的状态）；
    --   「拿起后=有」= 拿起来了，是**放置**那一步失败（附件栏被占 / 客户端拒收）。
    local pickedUp = "空"
    if m.api.CursorHasItem and m.api.CursorHasItem() then pickedUp = "有" end
    m.orig.ClickSendMailItemButton()

    if not m.api.GetSendMailItem() then
      -- ★挂不上：先放回队首、延迟一帧重试几次（同帧物品锁这类瞬时问题下一拍就好）
      local tries = ( m.sendmail_retry or 0 ) + 1
      m.sendmail_retry = tries
      if tries <= m.sendmail_retry_max then
        table.insert( m.sendmail_state.attachments, 1, item )
        m.sendmail_update = true
        return
      end
      -- ① 光标上还留着东西 ⇒ **硬停**（后面必然连锁失败；绝不清光标 —— 清掉就是丢件）
      if m.api.CursorHasItem and m.api.CursorHasItem() then
        table.insert( m.sendmail_state.attachments, 1, item )
        local nm = m.get_item_name( m.api.GetContainerItemLink( item[ 1 ], item[ 2 ] ) )
        m.info( string.format( L[ "Could not attach %s (it is still on your cursor) - this mail was not sent" ], nm or "?" ) )
        m.sendmail_sending = false
        return
      end
      -- ② 光标干净、那一格又有东西却拿不起来 ⇒ **跳过这一件、继续发后面的**；
      --    ★这一支**绝不执行 SendMail** ⇒ 不会寄出空邮件。
      --    ★根因不猜：靠 `拿起后=` 那一格判（「空」= 客户端拒绝取件 / 「有」= 取件成功、是放置那一步失败）。
      m.sendmail_failed = ( m.sendmail_failed or 0 ) + 1
      m.sendmail_retry = 0
      m.info( string.format( "  附件（包 %d / 格 %d）拿不起来（连试 %d 次）—— 跳过这一件，继续发后面的",
        item[ 1 ], item[ 2 ], tries ) )
      -- ★必须留一行可截图的现场诊断（这一族「拿不起来」的问题一律先取证再改）：
      --   格子 bag/slot ｜ 该格现在是什么 ｜ **拿起之后**光标上有没有东西 ｜ 现在光标 / 寄件栏 ｜ 连试几次
      --   判读：`拿起后=空` ⇒ 客户端**拒绝这次取件**（物品从未离开背包，与放置序列无关）；
      --         `拿起后=有` ⇒ 取起来了，是放置那一步失败。
      local diagLink = m.api.GetContainerItemLink( item[ 1 ], item[ 2 ] )
      local diagCur = "空"
      if m.api.CursorHasItem and m.api.CursorHasItem() then diagCur = "有" end
      local diagSlot = "空"
      if m.api.GetSendMailItem() then diagSlot = "有" end
      m.info( string.format( "  诊断：格子 %d/%d ｜ 该格现在= %s ｜ 拿起后=%s ｜ 现在光标=%s ｜ 寄件栏=%s ｜ 连试 %d 次",
        item[ 1 ], item[ 2 ], diagLink or "空", pickedUp, diagCur, diagSlot, tries ) )
      m.sendmail_update = true
      return
    end
    -- 这一件挂上了 ⇒ 连续失败计数清零（成功一件就重新开始数）
    m.sendmail_retry = 0
  end

  local amount = m.sendmail_state.money
  m.sendmail_state.sent_money = m.sendmail_state.money
  m.sendmail_state.sent = false

  if amount > 0 then
    if not m.api.SendMailCODAllButton:GetChecked() then
      m.sendmail_state.money = 0
    end
    if m.sendmail_state.cod then
      m.sendmail_state.cod = amount
      m.api.SetSendMailCOD( amount )
    else
      m.sendmail_state.money = 0
      m.api.SetSendMailMoney( amount )
    end
  end

  local subject = m.sendmail_state.subject
  if subject == "" then
    if item then
      local item_name, texture, stack_count = m.api.GetSendMailItem()
      subject = item_name .. (stack_count > 1 and " (" .. stack_count .. ")" or "")
      m.sendmail_state.item = item_name
      m.sendmail_state.icon = texture
    else
      subject = "<" .. m.api.NO_ATTACHMENTS .. ">"
    end
  elseif m.sendmail_state.numMessages > 1 then
    subject = subject .. string.format( " [%d/%d]", m.sendmail_state.numMessages - getn( m.sendmail_state.attachments ),
      m.sendmail_state.numMessages )
  end

  m.sendmail_state.sent_subject = subject

  m.debug( "SendMail" )
  m.api.SendMail( m.sendmail_state.to, subject, m.sendmail_state.body )
  -- 记下这一件**真的寄出去了**（批末据此把它从选择列表里摘掉 ⇒ 列表 = 还没寄出去的那些）
  if item then
    m.multi_sent = m.multi_sent or {}
    m.multi_sent[ item[ 1 ] .. ":" .. item[ 2 ] ] = true
  end

  if getn( m.sendmail_state.attachments ) == 0 then
    m.sendmail_sending = false
    if ( m.sendmail_skipped or 0 ) + ( m.sendmail_failed or 0 ) > 0 then
      m.info( string.format( "  本次共跳过 %d 件（拿不起来 %d ｜ 已不在原处 %d）",
        ( m.sendmail_skipped or 0 ) + ( m.sendmail_failed or 0 ),
        m.sendmail_failed or 0, m.sendmail_skipped or 0 ) )
      m.sendmail_skipped = nil
      m.sendmail_failed = nil
    end
    -- ★批末收口：把**已经寄出去**的条目从选择列表里摘掉；跳过的那些留着（还在背包里，可再点发送重试）
    local sentSet = m.multi_sent or {}
    local kept, gone = {}, 0
    for i = 1, getn( m.multi_list ) do
      local it = m.multi_list[ i ]
      if sentSet[ it[ 1 ] .. ":" .. it[ 2 ] ] then
        gone = gone + 1
      else
        tinsert( kept, it )
      end
    end
    if gone > 0 then
      m.multi_list = kept
      m.info( string.format( "  已寄出 %d 件已从选择列表移除（列表还剩 %d 条）", gone, getn( m.multi_list ) ) )
      -- ★0.3.12：寄出去的条目离开列表 ⇒ 背包格上那层「附件」遮盖也要跟着收掉
      m.multi_tell_bag()
    end
    m.multi_sent = nil
  end
end

do
  local inputLength
  local matches = {}
  local index

  local function complete()
    m.api.SendMailNameEditBox:SetText( matches[ index ] )
    m.api.SendMailNameEditBox:HighlightText( inputLength, -1 )
    for i = 1, m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS do
      local button = m.api[ "MailAutoCompleteButton" .. i ]
      if i == index then
        button:LockHighlight()
      else
        button:UnlockHighlight()
      end
    end
  end

  function EHMailTM.previous_match()
    if index then
      index = index > 1 and index - 1 or getn( matches )
      complete()
    end
  end

  function EHMailTM.next_match()
    if index then
      ---@diagnostic disable-next-line: undefined-global
      index = mod( index, getn( matches ) ) + 1
      complete()
    end
  end

  function EHMailTM.select_match( i )
    index = i
    complete()
    m.api.MailAutoCompleteBox:Hide()
    m.api.SendMailNameEditBox:HighlightText( 0, 0 )
  end

  function GetSuggestions()
    local input = m.api.SendMailNameEditBox:GetText()
    inputLength = string.len( input )

    ---@diagnostic disable-next-line: undefined-field
    table.setn( matches, 0 )
    index = nil

	local autoCompleteNames = {}
	local key = get_realm_faction_key()
	local names_table = m.api.EHMailTM_AutoCompleteNames[ key ] or {}
	for name, time in pairs( names_table ) do
	  table.insert( autoCompleteNames, { name = name, time = time } )
	end

    table.sort( autoCompleteNames, function( a, b ) return b.time < a.time end )

    local ignore = { [ m.api.UnitName "player" ] = true }
    local function process( name )
      if name then
        if not ignore[ name ] and string.find( string.upper( name ), string.upper( input ), nil, true ) == 1 then
          table.insert( matches, name )
        end
        ignore[ name ] = true
      end
    end
    for _, t in autoCompleteNames do
      process( t.name )
    end
    for i = 1, m.api.GetNumFriends() do
      process( m.api.GetFriendInfo( i ) )
    end
    for i = 1, m.api.GetNumGuildMembers( true ) do
      process( m.api.GetGuildRosterInfo( i ) )
    end

    ---@diagnostic disable-next-line: undefined-field
    table.setn( matches, math.min( getn( matches ), m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS ) )
    if getn( matches ) > 0 and (getn( matches ) > 1 or input ~= matches[ 1 ]) then
      for i = 1, m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS do
        local button = m.api[ "MailAutoCompleteButton" .. i ]
        if i <= getn( matches ) then
          button:SetText( matches[ i ] )
          button:GetFontString():SetPoint( "LEFT", button, "LEFT", 15, 0 )
          button:Show()
        else
          button:Hide()
        end
      end
      m.api.MailAutoCompleteBox:SetHeight( getn( matches ) * m.api.MailAutoCompleteButton1:GetHeight() + 35 )
      m.api.MailAutoCompleteBox:SetWidth( 120 )
      m.api.MailAutoCompleteBox:Show()
      index = 1
      complete()
    else
      m.api.MailAutoCompleteBox:Hide()
    end
  end
end

-- ============================================================================
-- 0.3.11 附件选择列表（**纯数据**）+ 发送指令（点【发送】走这一条）
--   ★形态（用户 2026-10-10 定案）：**列表 = 唯一真值**，附件格 = 列表的投影。
--     · 右键背包物品 ⇒ `m.multi_add`：**只是**把 {包号,格号,链接} 加进列表 —— 不碰光标、
--       不碰客户端寄件栏、不拿放物品（用户原话：「绝不碰鼠标拿起放下的行为.容易卡住物品」）。
--     · 右键/左键附件格 ⇒ `m.multi_del`：**只是**把这条数据删掉，同样一个物品操作都不做。
--     · 点【发送】⇒ `send_mail_button_onclick`：先把列表投影一遍，再按**已验证过的那条路**
--       （`sendmail_send`：ClearCursor → ClickSendMailItemButton → PickupContainerItem → 放置 → SendMail）
--       逐件真切进客户端寄件栏并寄出；寄成功的条目批末从列表摘除。
--     · 全程客户端寄件栏都是空的（只有发送那一刻短暂占用）⇒ 「拿不起来 / 光标忙 / 附件格锁住」
--       那一整族现象从根上不存在。
--   ★为什么要有旧的那条测试指令 `/tm 发送背包`：把**入口链**与**出口链**分开验（它不碰入口）。
-- ============================================================================

-- ★附件选择列表（**唯一真值**）：元素 = `{ 包号, 格号, 选择时的物品链接 }`，从 1 起连续。
--   附件格（MailAttachment1..21）只是它的**投影**；旁边的小计数框也读同一张表。
m.multi_list = {}
-- UI 容量 = 附件格总数（7 列 × 3 行 = 21）；超出的**既不显示、也不寄出**（tooltip 如实说）
m.multi_cap = ATTACHMENTS_PER_ROW_SEND * ATTACHMENTS_MAX_ROWS_SEND
-- 自动档：切到发件页就把列表投影进附件格
m.multi_auto = true
-- 小计数框（只做悬停提示、不做点击）：尺寸与位置（位置可用 /tm 附件 偏移 现场调）
m.MULTI_BOX_W = 150
m.MULTI_BOX_H = 30
m.multi_box_dx = 8
m.multi_box_dy = -34

-- 切词：1.12 只有 string.gmatch，而本文件既有写法是 string.find 手撸（paneloff 那段）⇒ 照抄
m.multi_split = function( s )
  local t, pos = {}, 1
  while true do
    local a, b = string.find( s, "%S+", pos )
    if not a then break end
    tinsert( t, string.sub( s, a, b ) )
    pos = b + 1
  end
  return t
end

-- 测试默认档 = 背包 0 的第 1..4 格（带链接：发送时按链接核对「那格还是不是这件东西」）
m.multi_default_list = function()
  local t = {}
  for i = 1, 4 do tinsert( t, { 0, i, m.multi_link( 0, i ) } ) end
  return t
end

-- 字体：走本文件既有那条链（链尾 ARIALN 真机验证可用），拿不到再退两参数 SetFont
m.multi_font = function( fs, size )
  if not fs then return end
  if type( m.log ) == "table" and type( m.log.fontSet ) == "function" then
    if pcall( m.log.fontSet, fs, size ) then return end
  end
  pcall( fs.SetFont, fs, "Fonts\\ARIALN.TTF", size )
end

m.multi_link = function( bag, slot )
  if type( m.api.GetContainerItemLink ) ~= "function" then return nil end
  return m.api.GetContainerItemLink( bag, slot )
end

-- ★★★附件列表的核心（0.3.11 起 = **唯一真值**）：条目 = `{ 包号, 格号, 加进来时的链接 }`。
--   **只动数据**：绝不碰光标、绝不碰客户端寄件栏、绝不拿放物品（用户 2026-10-10 定：「绝不碰鼠标拿起放下的行为.容易卡住物品」）。
--   ★为什么这样改：真机多轮报障（「拿不起来 / 光标忙 / 发送 7 件只出去 3 件」）的源头全是
--     「挂附件时真的去拿放物品」（上游 `sendmail_pickup_mailable` 那套 ClearCursor → 塞进邮寄槽 → 读回 → 取出）
--     ⇒ 现在**选择 = 纯数据**，只有点【发送】那一刻才真切进客户端寄件栏，那条故障链整条不存在了。
m.multi_index = function( bag, slot )
  for i = 1, getn( m.multi_list ) do
    local it = m.multi_list[ i ]
    if it[ 1 ] == bag and it[ 2 ] == slot then return i end
  end
  return nil
end

m.multi_has = function( bag, slot )
  return m.multi_index( bag, slot ) ~= nil
end

-- 这一条现在还算不算「那一格上就是它」：★读到空 ⇒ **保留**（可能只是这一刻读不到，绝不因为一次读不到就清列表），
-- 只有「读到**别的**链接」才判失效 —— 那才是真的会寄错东西的危险情形。
m.multi_alive = function( it )
  local now = m.multi_link( it[ 1 ], it[ 2 ] )
  if not now then return true end
  if it[ 3 ] and now ~= it[ 3 ] then return false end
  return true
end

-- 只摘「那一格已经换成别的东西」的条目（读到空的一律保留，交给发送时的「跳过 + 点名」如实处理）
m.multi_prune = function( quiet )
  local kept, dropped = {}, 0
  for i = 1, getn( m.multi_list ) do
    local it = m.multi_list[ i ]
    if m.multi_alive( it ) then
      tinsert( kept, it )
    else
      dropped = dropped + 1
      if not quiet then
        m.info( string.format( "  附件（包 %d / 格 %d）那一格已经换成别的东西 ⇒ 已从选择列表移除", it[ 1 ], it[ 2 ] ) )
      end
    end
  end
  if dropped > 0 then m.multi_list = kept end
  return dropped
end

-- 加一条：返回 "ok" / "dup" / "empty" / "full"（quiet = 一声不出，给 Alt+左键的批量路径用）
m.multi_add = function( bag, slot, quiet )
  if m.multi_has( bag, slot ) then
    if not quiet then m.info( string.format( "包 %d 格 %d 已经在选择列表里了（不重复记）", bag, slot ) ) end
    return "dup"
  end
  local link = m.multi_link( bag, slot )
  if not link then
    if not quiet then m.info( string.format( "包 %d 格 %d 是空的 ⇒ 没有加进选择列表", bag, slot ) ) end
    return "empty"
  end
  m.multi_prune( true )
  if getn( m.multi_list ) >= m.multi_cap then
    if not quiet then
      m.info( string.format( "选择列表已满 %d 条 ⇒ 没加进去（点【发送】寄出后可再加，或右键附件格删掉某条）", m.multi_cap ) )
    end
    return "full"
  end
  tinsert( m.multi_list, { bag, slot, link } )
  if not quiet then
    m.info( string.format( "已加入选择列表：包 %d 格 %d ｜ %s（共 %d 条）", bag, slot, link, getn( m.multi_list ) ) )
  end
  return "ok"
end

-- 删一条（**只删数据**：不动物品、不碰光标）
m.multi_del = function( bag, slot, quiet )
  local i = m.multi_index( bag, slot )
  if not i then
    if not quiet then m.info( string.format( "包 %d 格 %d 不在选择列表里 ⇒ 没删任何东西", bag, slot ) ) end
    return false
  end
  local it = table.remove( m.multi_list, i )
  if not quiet then
    m.info( string.format( "已从选择列表移除：包 %d 格 %d ｜ %s（还剩 %d 条）", bag, slot, it[ 3 ] or "?", getn( m.multi_list ) ) )
  end
  return true
end

-- 现场读数（只读）：每条命令开头都摊开 —— 免得「看着像没反应」时无从判读
m.multi_diag = function()
  local t = {}
  local sendSlot = "?"
  if type( m.api.GetSendMailItem ) == "function" then
    local ok, v = pcall( m.api.GetSendMailItem )
    sendSlot = ( ok and v ) and "|cffff6060有（残留 ⇒ 开批会硬停）|r" or "空"
  end
  local cursor = "?"
  if type( m.api.CursorHasItem ) == "function" then
    local ok2, v2 = pcall( m.api.CursorHasItem )
    cursor = ( ok2 and v2 ) and "有" or "空"
  end
  tinsert( t, string.format( "客户端寄件栏=%s ｜ 光标=%s ｜ 附件格记账=%d", sendSlot, cursor, m.sendmail_num_attachments() ) )
  -- ★0.3.12：光标那一行再摊开「锁着的格子」（取消拖拽的唯一判据 —— 认不出它的家就一个字节都不碰）
  do
    local homes, n = m.cursor_homes()
    if n < 0 then
      tinsert( t, "拖拽源格=|cffff6060判不出|r（缺 `CursorHasItem` 或原函数）" )
    elseif ( cursor ~= "有" ) then
      tinsert( t, "拖拽源格=—（光标上没有物品）" )
    elseif n == 0 then
      tinsert( t, "拖拽源格=|cffff6060没有锁着的格子|r（多半来自银行/装备栏/别的窗口）⇒ 认不出它的家" )
    else
      local parts = {}
      local i
      for i = 1, getn( homes ) do
        parts[ i ] = string.format( "%d/%d", homes[ i ][ 1 ], homes[ i ][ 2 ] )
      end
      tinsert( t, string.format( "拖拽源格=%s%s", table.concat( parts, " " ),
        ( n == 1 ) and "（唯一 ⇒ 可以放回）" or "|cffff6060（不止一个 ⇒ 分不清，不动手）|r" ) )
    end
  end
  local to = ""
  if m.api.SendMailNameEditBox and m.api.SendMailNameEditBox.GetText then
    to = m.api.SendMailNameEditBox:GetText() or ""
  end
  tinsert( t, string.format( "收件人=%s ｜ 发件页=%s", ( to ~= "" ) and to or "|cffff6060★空|r",
    ( m.api.SendMailFrame and m.api.SendMailFrame:IsVisible() ) and "已打开" or "未打开" ) )
  -- ★0.3.15：关邮箱那一趟清理的读数（纯读；没跑过就不打这一行）——
  --   真机上「背包还锁着」时，这一行直接给出「清了没 / 清了几条 / 重画了几个容器帧」。
  if m.release_n ~= nil then
    tinsert( t, string.format( "上次清理：清空 %d 条 ｜ 重画客户端背包帧 %d 个 ｜ 原因=%s",
      m.release_n, m.release_frames or 0, m.release_why or "" ) )
  end
  return t
end

-- 列表里「这一刻真的还挂得住」的条数（读到空 / 那一格换了别的东西都不算）
m.multi_live = function()
  local live = 0
  for i = 1, getn( m.multi_list ) do
    local it = m.multi_list[ i ]
    local now = m.multi_link( it[ 1 ], it[ 2 ] )
    if now and ( not it[ 3 ] or now == it[ 3 ] ) then live = live + 1 end
  end
  return live
end

m.multi_lines = function()
  local n = getn( m.multi_list )
  local t = {}
  local head = string.format( "选择列表 %d 条（当前真的还在那格 %d 条）｜ 附件格容量 %d 格", n, m.multi_live(), m.multi_cap )
  if n > m.multi_cap then
    head = head .. string.format( " ｜ |cffff6060超出 %d 条（只显示前 %d 条；超出的既不显示、也不寄出）|r", n - m.multi_cap, m.multi_cap )
  end
  tinsert( t, head )
  for i = 1, n do
    local it = m.multi_list[ i ]
    local now = m.multi_link( it[ 1 ], it[ 2 ] )
    local state
    if not now then
      state = "|cffff6060（那一格现在空的）|r"
    elseif it[ 3 ] and now ~= it[ 3 ] then
      state = "|cffff6060（那一格换成了别的东西）|r"
    else
      state = now
    end
    tinsert( t, string.format( "  [%d] 包 %d / 格 %d ｜ %s%s", i, it[ 1 ], it[ 2 ],
      state, ( i > m.multi_cap ) and " |cffff6060超容量|r" or "" ) )
  end
  if n == 0 then tinsert( t, "  （空）右键背包里的物品即可加进来；右键附件格 = 移除这一条" ) end
  return t
end

-- ★tooltip 全文：纯文本、不许出现 `**`（本客户端会把星号原样画在屏幕上）、不许有 nil 行
-- ★超出容量那一行（**唯一来源**）：附件格自己的悬停与计数框悬停共用同一句；没超出 ⇒ nil（一个字节都不加）
m.multi_overflow_line = function()
  local n = getn( m.multi_list )
  if n <= m.multi_cap then return nil end
  return string.format( "|cffff6060选择物品列表超出 %d 条|r：附件格只放得下前 %d 条，超出的既不显示、也不会寄出",
    n - m.multi_cap, m.multi_cap )
end

-- ★★★把附件格自己的悬停也接上同一条提示（用户 2026-10-10 点名：「展示选择物品列表就是**发件页那排附件格**这个位置」）
--   · 只在**超出容量**时补一行；没超出时原样保留客户端的 SetBagItem 提示（一个字节都不改）
--   · 包装纪律照项目既有做法：先把 XML 那份 OnEnter 取出来存成 upvalue，再挂我们的 —— 我们只**追加**一行
--   · 幂等（`btn.multiTipWrapped` 门）：重复调用不会包两层
m.multi_tip_wrap = function()
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn and not btn.multiTipWrapped
      and type( btn.GetScript ) == "function" and type( btn.SetScript ) == "function" then
      local origEnter = btn:GetScript( "OnEnter" )
      btn.multiTipWrapped = true
      btn:SetScript( "OnEnter", function()
        -- 原处理体用的是客户端的全局 this（不额外传参，保持与 XML 里 `GetScript('OnEnter')()` 同一姿势）
        if type( origEnter ) == "function" then origEnter() end
        local line = m.multi_overflow_line()
        if line and m.api.GameTooltip and type( m.api.GameTooltip.AddLine ) == "function" then
          m.api.GameTooltip:AddLine( line )
        end
      end )
    end
  end
end

m.multi_tip_lines = function()
  local n = getn( m.multi_list )
  local t = {}
  tinsert( t, "|cffffd100选择物品列表|r（就是发件页那排附件格）" )
  tinsert( t, string.format( "共 %d 条 ｜ 当前真有物品 %d 条 ｜ 附件格容量 %d 格", n, m.multi_live(), m.multi_cap ) )
  if n > m.multi_cap then
    tinsert( t, m.multi_overflow_line() )
  elseif n == 0 then
    tinsert( t, "|cffa0a0a0列表为空|r" )
  else
    local inTray = m.multi_in_tray()
    if inTray >= n then
      tinsert( t, string.format( "|cff20ff20%d 条都已在附件格里|r（等同已挂载）", n ) )
    else
      tinsert( t, string.format( "|cffffd100%d 条里已有 %d 条在附件格里|r（切到发件页会自动补齐）", n, inTray ) )
    end
  end
  tinsert( t, " " )
  tinsert( t, "|cff9fe0ff/tm 多选 默认|r 列表 = 背包 0 第 1-4 格（测试默认档）" )
  tinsert( t, "|cff9fe0ff/tm 多选 加 <包> <格>|r 追加一条" )
  tinsert( t, "|cff9fe0ff/tm 多选 清|r 清空列表与附件格" )
  tinsert( t, "|cff9fe0ff/tm 多选 显示|r 把列表重新渲染进附件格" )
  tinsert( t, "|cff9fe0ff/tm 多选 发|r 渲染后立刻寄给当前收件人" )
  tinsert( t, "|cff9fe0ff/tm 发送背包 <N> [包]|r 背包第 1..N 格直接挂上并寄出" )
  tinsert( t, "|cff9fe0ff拖到附件框上|r 松手 = 把那一件加进列表，并|cff20ff20取消这次拖拽|r（放回原处）" )
  tinsert( t, "|cff9fe0ff点【发送】前|r 若光标上还拖着东西，先放回原处再寄（认不出它的家就如实说一句并停下）" )
  tinsert( t, "|cff9fe0ff/tm 多选 光标|r 只读探针：光标上有没有东西 / 认不认得出它的家" )
  tinsert( t, "|cff9fe0ff/tm 多选 帮助|r 摊开附件框的信息引导（与悬停提示同一份）" )
  tinsert( t, "|cff9fe0ff快速删除|r 点某一格 = 删这一条；|cffffd100右键计数框|r = 一次清空整个列表" )
  tinsert( t, "|cffa0a0a0小框位置：/tm 多选 偏移 <dx> <dy>|r" )
  return t
end

-- 计数框刷新（唯一出口：显示与文案都只在这里改）
m.multi_box_refresh = function()
  local box = m.multi_box
  if not box then return end
  if not m.multi_auto then
    box:Hide()
    return
  end
  box:Show()
  if box.count then
    local n = getn( m.multi_list )
    if n > m.multi_cap then
      box.count:SetText( string.format( "|cffff6060%d / %d 超出 %d|r", n, m.multi_cap, n - m.multi_cap ) )
    elseif n == 0 then
      box.count:SetText( string.format( "|cffa0a0a0%d / %d（空）|r", n, m.multi_cap ) )
    else
      box.count:SetText( string.format( "|cff20ff20%d / %d|r", n, m.multi_cap ) )
    end
  end
end

-- 计数框：**父级 = SendMailFrame** ⇒ 只有发件页显示时才跟着显示（这里要的就是父子传播），
-- 位置默认贴在发件页右缘外侧（批量面板挂在 InboxFrame 上、发件页看不见它 ⇒ 这块空间是空的）。
m.multi_box_build = function()
  if m.multi_box then
    m.multi_box_refresh()
    return m.multi_box
  end
  if not m.api.SendMailFrame then return nil end
  local box = m.api.CreateFrame( "Frame", "EHMailTMMultiBox", m.api.SendMailFrame )
  box:SetWidth( m.MULTI_BOX_W )
  box:SetHeight( m.MULTI_BOX_H )
  box:SetPoint( "TOPLEFT", m.api.SendMailFrame, "TOPRIGHT", m.multi_box_dx, m.multi_box_dy )
  -- 子件要自己抬层级（抬高父帧不带动子件）；读不到层级也不许把建框整条打断
  pcall( function()
    box:SetFrameLevel( ( m.api.SendMailFrame:GetFrameLevel() or 1 ) + 6 )
  end )
  -- 只是悬停热区：本客户端透明帧照样吃鼠标 ⇒ 这里只开悬停、不接任何点击
  box:EnableMouse( true )

  local title = box:CreateFontString( "EHMailTMMultiBoxTitle", "ARTWORK" )
  title:SetPoint( "TOPLEFT", box, "TOPLEFT", 2, -2 )
  title:SetText( "|cffffd100选择物品列表|r" )
  m.multi_font( title, 11 )

  local count = box:CreateFontString( "EHMailTMMultiBoxCount", "ARTWORK" )
  count:SetPoint( "TOPLEFT", title, "BOTTOMLEFT", 0, -2 )
  m.multi_font( count, 11 )

  box:SetScript( "OnEnter", function()
    if not ( m.api.GameTooltip and m.api.GameTooltip.SetOwner ) then return end
    m.api.GameTooltip:ClearLines()
    m.api.GameTooltip:SetOwner( box, "ANCHOR_RIGHT" )
    local lines = m.multi_tip_lines()
    for i = 1, getn( lines ) do m.api.GameTooltip:AddLine( lines[ i ] ) end
    -- ★0.3.13：列表内容之后**追加信息引导**（同一份引导行，与附件格悬停共用 —— 见 attach_tip_lines）
    m.api.GameTooltip:AddLine( " " )
    local guide = m.attach_tip_lines()
    for i = 1, getn( guide ) do m.api.GameTooltip:AddLine( guide[ i ] ) end
    m.api.GameTooltip:Show()
  end )
  box:SetScript( "OnLeave", function()
    if m.api.GameTooltip and m.api.GameTooltip.Hide then m.api.GameTooltip:Hide() end
  end )

  -- ★0.3.12：这个计数框也算**附件框的一部分**（用户点名的「展示选择物品列表就是发件页那排附件格」）
  --   ⇒ 拖着物品松手落在它上面，同样走「加进列表 + 取消拖拽」那一个处理体（与 MailAttachment 同一个口）。
  --   ★它照旧只是**悬停热区**（不接任何点击）—— 这里只加「接收拖放」这一条路。
  pcall( box.SetScript, box, "OnReceiveDrag", m.attachment_receive_drag )

  -- ★0.3.13 快速删除（整批）：**右键这个计数框 = 一次清空整个列表**（只动列表数据，物品一件不动）。
  --   ★鼠标键按本项目既有 idiom 取：先看处理体的第二个实参、再退回全局 `arg1`
  --     （本客户端把键名放全局 `arg1`；现代式客户端才是 (self, button) 两参）。
  box:SetScript( "OnMouseUp", function( a, b )
    local button = b
    if button == nil then button = arg1 end
    if button ~= "RightButton" then return end
    m.multi_box_clear()
  end )

  box.title = title
  box.count = count
  m.multi_box = box
  -- 附件格的悬停提示也接上（用户点名：选择物品列表的展示位置就是这排附件格）
  m.multi_tip_wrap()
  m.multi_box_refresh()
  return box
end

-- ★★★唯一投影口（列表 → 附件格）：**全量重建**。
--   ★为什么现在敢全量重建（0.3.10 时还写着「只加不删」）：**已经没有第二个写入者了** ——
--     右键背包不再物理附加、附件格点击只删数据、客户端寄件栏那条路也不再抓附件
--     ⇒ 附件格的显示 = 列表的投影，两者必然一致，不存在「把别人挂的弄丢」的风险。
--   ★只投影「这一刻真的还在那格」的条目（紧凑排列）；读到空 / 换了东西的条目**留在列表里**，
--     由发送那一步的「跳过 + 点名」如实处理（绝不在这里静默删掉用户的选择）。
m.multi_project = function()
  -- ★0.3.12：列表一变就通知背包整合（EH_Bag）重画背包格上的「附件」遮盖层 ——
  --   桥 = 它的全局表 `EH_BAG.mailMarkRefresh`；它不在场 / 没这个口 ⇒ 一个字节都不动（fail-open）。
  m.multi_tell_bag()
  if not m.api.MailAttachment1 then return 0 end
  -- 附件格只在邮箱窗口里才有意义：关着时写进去随后会被 MAIL_CLOSED 的 sendmail_clear 清掉
  -- ⇒ 与其「写了又没」，不如当场不写，由调用方如实说明「等打开邮箱会自动渲染」
  if not ( m.api.MailFrame and m.api.MailFrame:IsVisible() ) then return 0 end
  local n = 0
  for i = 1, getn( m.multi_list ) do
    local it = m.multi_list[ i ]
    local now = m.multi_link( it[ 1 ], it[ 2 ] )
    if now and ( not it[ 3 ] or now == it[ 3 ] ) then
      n = n + 1
      if n <= ATTACHMENTS_MAX then
        local btn = m.api[ "MailAttachment" .. n ]
        if btn then btn.item = { it[ 1 ], it[ 2 ], it[ 3 ] } end
      end
    end
  end
  for i = n + 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn then btn.item = nil end
  end
  m.multi_shown = n
  m.multi_tip_wrap()
  m.multi_box_build()
  m.multi_box_refresh()
  m.sendmail_queue_update()
  return n
end

-- 列表里「此刻真的在附件格里」的条数（诚实计数：格子被背包更新剔掉后会自己变少）
m.multi_in_tray = function()
  local c = 0
  for k = 1, getn( m.multi_list ) do
    local it = m.multi_list[ k ]
    if m.sendmail_attached( it[ 1 ], it[ 2 ] ) then c = c + 1 end
  end
  return c
end

-- 清空：列表清空（keep_list = true 只重投影、保留列表内容）
m.multi_clear = function( keep_list )
  if not keep_list then m.multi_list = {} end
  return m.multi_project()
end

-- 渲染 + 寄出（三条命令共用；收件人/邮箱/列表三道门都在这里，缺一道就如实说、一件都不寄）
m.multi_send_now = function( tag )
  if not ( m.api.MailFrame and m.api.MailFrame:IsVisible() ) then
    m.info( "|cffff6060邮箱没开|r：先打开邮箱再敲这条命令" )
    return false
  end
  local to = ""
  if m.api.SendMailNameEditBox and m.api.SendMailNameEditBox.GetText then
    to = m.api.SendMailNameEditBox:GetText() or ""
  end
  if to == "" then
    m.info( "|cffff6060收件人为空|r ⇒ 一件都没挂、也没寄出（先在『收件人』里填名字，或点右边的下拉选一个）" )
    return false
  end
  if getn( m.multi_list ) == 0 then
    m.info( "多选列表是空的 ⇒ 用 /tm 多选 默认 或 /tm 多选 加 <包> <格>" )
    return false
  end
  m.multi_quiet = true
  m.sendmail_show_send_tab()
  m.multi_quiet = nil
  local shown = m.multi_project()
  m.info( string.format( "%s：选择列表 %d 条 ⇒ 附件格挂上 %d 格（这一刻还在那格的；纯数据、没碰光标/客户端寄件栏）⇒ 交给发送 → %s",
    tag or "发送", getn( m.multi_list ), shown, to ) )
  m.send_mail_button_onclick()
  return true
end

-- 附件格只在邮箱窗口里 ⇒ 没开邮箱时如实说「列表更新了、格子没渲染」，绝不假装渲染过
m.multi_note_closed = function()
  return "｜ |cffffd100邮箱没开|r：列表已更新，附件格等打开邮箱切到发件页时自动渲染"
end

-- ============================================================================
-- 0.3.12 光标拖拽：**认得出源格就放回去**（绝不 ClearCursor）+ 附件框接收拖放 + 发件前清理
--   ★用户 2026-10-10 两条需求：
--     ①「子插件邮箱发件附件框检测. 如果有用户拖拽物品点击到这个窗则进行添加对应物品到列表的行为.
--        并且取消掉物品的拖拽物品操作」
--     ②「发件前检测用户是否有拖拽物品在鼠标上的行为. 也清理掉拖拽物品的行为. 查看API是否支持」
--   ★★★API 事实（查的是本机 `api_cursor.html` 的客户端索引，**不许猜**）：
--     · `CursorHasItem()` —— **有**：唯一的「光标上有没有物品」判定口
--       （官方口径：只认背包物品/拆分堆/弹药，**不认**钱/法术/宏/商人物品）。
--     · `ClearCursor()` —— **有**，但**这一族一律不用它**：它是「把光标上的东西丢下」，
--       而本项目在案的事故里「清光标 = 丢件」（EH_Bag 整理引擎实测丢过两件）⇒ 绝不用它当兜底。
--     · `GetCursorInfo()` —— **本客户端索引里没有**（`api_cursor.html` 全表无此名）⇒
--       「光标上是哪一件」**读不出来**，只能靠**源格**反推。
--     · 源格怎么认：客户端把被拖走的那一格**锁上** —— `GetContainerItemInfo` 的第 3 个返回 = `locked`
--       （`api_container.html` 的官方口径）；被拖走的那件东西的家就是**锁着的那个格子**。
--   ★★★三条口径（改动这一族必看）：
--     ① **只认「恰好一个锁住的格子」**：0 个（判不出它从哪来）或 ≥2 个（分不清是哪一格）⇒
--        **一个字节都不碰**，如实说一句就收工（绝不猜、绝不拿别的格子当它的家）。
--     ② **放回 = `PickupContainerItem(源包, 源格)`** —— 与「玩家再点一次同一格」是同一条路：
--        客户端认得的**普通移动**，永远不可能销毁物品；放完**读回自证** `CursorHasItem()`：
--        空了 = 取消成功；**还拿着** ⇒ 如实说「请你手动放一下」，**绝不改走 ClearCursor**。
--     ③ **一律走 `m.orig.*`（未经 hook 的原函数）**：本插件的 `hook.PickupContainerItem` 会拦右键，
--        而这里是在我们自己的处理体里调它 —— 走 hook 就会被自己拦一次（物品一点没动）。
--   ★这一族**只在这三个入口**动手：附件框接收拖放（①②）/ 点【发送】前（②）/ 只读探针（不动物品）。
--     选择列表的加/删/投影照旧**纯数据**（0.3.11 的口径一个字节没改）。
-- ============================================================================

-- 光标上那件东西**可能**的源格（只读）：返回 列表, 计数。
--   计数语义：0 = 光标上没有物品（或没在拖）· `-1` = 判不出（缺 API / 缺原函数）· ≥1 = 锁着的格子数。
--
-- ★唯一读口：这一版客户端到底有没有 `CursorHasItem`（拿不到 ⇒ nil；**判不出 ≠ 没有**）。
--   全部调用点只走它 —— 少一处 `type(...) == "function"` 就多一个「同一条口径两处写」的漏改点。
m.cursor_api = function()
  local f = m.api.CursorHasItem
  if type( f ) == "function" then return f end
  return nil
end

m.cursor_homes = function()
  local list = {}
  local hasItem = m.cursor_api()
  if hasItem == nil then return list, -1 end
  local ok, has = pcall( hasItem )
  if not ok then return list, -1 end
  if not has then return list, 0 end
  -- ★必须用**原函数**：hook 版会给「已在选择列表里的格子」伪报 locked（那是附件格子的选中反馈）
  local getinfo = m.orig.GetContainerItemInfo
  local numslots = m.api.GetContainerNumSlots
  if type( getinfo ) ~= "function" or type( numslots ) ~= "function" then return list, -1 end
  local bags = { 0, 1, 2, 3, 4 }
  if type( m.api.KEYRING_CONTAINER ) == "number" then tinsert( bags, m.api.KEYRING_CONTAINER ) end
  if type( m.api.BANK_CONTAINER ) == "number" then
    tinsert( bags, m.api.BANK_CONTAINER )
    local b
    for b = 5, 10 do tinsert( bags, b ) end
  end
  local i
  for i = 1, getn( bags ) do
    local bag = bags[ i ]
    local okN, n = pcall( numslots, bag )
    n = ( okN and tonumber( n ) ) or 0
    local s
    for s = 1, n do
      -- ★多返回值的调用**不许**直接 pcall 接（`pcall` 只交回 ok + 第一个返回值；
      --   本项目在案：多返回值套 tostring/pcall 再当参数用会静默少值）⇒ 包一层闭包收成一个表
      local okR, ret = pcall( function() return { getinfo( bag, s ) } end )
      local locked = nil
      if okR and type( ret ) == "table" then locked = ret[ 3 ] end
      if locked then
        tinsert( list, { bag, s, m.multi_link( bag, s ) } )
      end
    end
  end
  return list, getn( list )
end

-- 恰好一个源格才认；返回 home, 计数（nil + 计数 = 认不出）
m.cursor_home = function()
  local list, n = m.cursor_homes()
  if n == 1 then return list[ 1 ], 1 end
  return nil, n
end

-- 把光标上那件东西放回它的源格（**唯一的「取消拖拽」口**）；返回 成功?, 原因
m.cursor_putback = function( home )
  local hasItem = m.cursor_api()
  if hasItem == nil then return false, "noapi" end
  if not hasItem() then return true, "empty" end
  if type( home ) ~= "table" then return false, "nohome" end
  local raw = m.orig.PickupContainerItem
  if type( raw ) ~= "function" then return false, "noapi" end
  raw( home[ 1 ], home[ 2 ] )
  if hasItem() then return false, "still" end
  return true, "ok"
end

-- 「认不出源格」时统一那句话（三处共用一份措辞，避免同一现象三种说法）
m.cursor_why = function( n )
  if n == -1 then
    return "|cffff6060判不出|r：这一版客户端没有 `CursorHasItem`（或原函数还没装上）⇒ 一个字节都没碰"
  end
  if n == 0 then
    return "光标上拿着东西，但**没有任何一格是锁着的**（多半是从银行/装备栏/别的窗口拖出来的）⇒ 认不出它的家"
  end
  return string.format( "光标上那件东西对应 |cffff6060%d 个锁住的格子|r（分不清是哪一格）⇒ 认不出它的家", n )
end

-- 发件前清理（用户需求②）：返回 true = 光标干净（本来就没拿东西，或已经放回去了）
m.cursor_clear = function( tag )
  local hasItem = m.cursor_api()
  if hasItem == nil then return true end
  if not hasItem() then return true end
  local home, n = m.cursor_home()
  if home == nil then
    m.info( "  " .. m.cursor_why( n ) .. "（绝不清光标 —— 清掉就等于把东西弄丢）" )
    return false
  end
  local okP, why = m.cursor_putback( home )
  if okP then
    m.info( string.format( "  光标上原本拿着东西 ⇒ 已放回原处（包 %d 格 %d）%s",
      home[ 1 ], home[ 2 ], ( tag and ( "｜" .. tag ) ) or "" ) )
    return true
  end
  m.info( string.format( "  |cffff6060没能放回去|r（包 %d 格 %d）：%s ⇒ 请你手动放一下（本插件绝不清光标 —— 清掉就等于把东西弄丢）",
    home[ 1 ], home[ 2 ], ( why == "noapi" ) and "取件口拿不到" or "放回之后光标上还有东西" ) )
  return false
end

-- ★★附件框接收拖放（用户需求①）：拖着物品松手落在附件格 / 计数框上
--   （挂在 `MailAttachment1..N` 的 `OnReceiveDrag` 与选择列表计数框上 —— 见 sendmail_load 与 multi_box_build）
function EHMailTM.attachment_receive_drag()
  local hasItem = m.cursor_api()
  if hasItem == nil then
    m.info( "附件框：这一版客户端没有 `CursorHasItem` ⇒ 判不出光标上有没有东西，一个字节都没碰" )
    return
  end
  if not hasItem() then
    m.info( "附件框：光标上没有物品（空手点一下 = 什么都不做）" )
    return
  end
  local home, n = m.cursor_home()
  if home == nil then
    m.info( "附件框：" .. m.cursor_why( n ) .. " ⇒ 这一件没加进选择列表，光标也一个字节都没碰" )
    return
  end
  -- 加进列表（纯数据）+ 投影（m.multi_add 自己会播报「已加入…/ 已在列表里 / 满了」）
  m.sendmail_show_send_tab()
  m.multi_add( home[ 1 ], home[ 2 ] )
  m.multi_project()
  -- 再取消这次拖拽
  local okP, why = m.cursor_putback( home )
  if okP then
    m.info( string.format( "  已取消这次拖拽：把那件东西放回了原处（包 %d 格 %d）｜ 列表里没有的东西一件都不会被拿走",
      home[ 1 ], home[ 2 ] ) )
    return
  end
  m.info( string.format( "  |cffff6060这次拖拽没取消掉|r：包 %d 格 %d 那件东西还挂在光标上（%s）⇒ 请你手动放一下",
    home[ 1 ], home[ 2 ], ( why == "noapi" ) and "取件口拿不到" or "放回后光标上还有东西" ) )
end

-- ★★通知背包整合（EH_Bag）重画「附件」标记（用户需求③的另一半：背包格上的遮盖层由它画）。
--   桥 = 它的全局表 `EH_BAG` 上的 `mailMarkRefresh`（它不在场 / 没这个口 ⇒ 一个字节都不动）。
--   ★纯通知：不传任何数据（背包侧只读本插件自己的 `multi_has`）⇒ 两边不会互相写对方的状态。
m.multi_tell_bag = function()
  local t = rawget( _G, "EH_BAG" )
  if type( t ) ~= "table" then return false end
  local f = t.mailMarkRefresh
  if type( f ) ~= "function" then return false end
  pcall( f )
  return true
end

-- ============================================================================
-- 0.3.13 附件框的**信息引导**（tooltip）+ **快速删除**
--   用户 2026-10-10 定：「附件框内做好信息引导提示. 推荐直接在背包内完成邮件快速选择. 操作.
--   邮件附件快速删除操作.」
--   ★三条口径（改这一族必看）：
--     ① **引导只有一份**：`m.attach_tip_lines()` 产出全部引导行，**附件格悬停与计数框悬停共用同一份**
--        （两处各写一份 = 下一个漏改点：文案一改就只改了一边）。
--     ② **占用格的气泡 = 客户端的物品信息 + 只追加**（`SetBagItem` 照旧先出那一件的完整信息，
--        我们只在后面补一行「点这一格 = 从列表移除」+ 一行「推荐在背包里选」；
--        **绝不 ClearLines** —— 那会把客户端的属性/商人价全抹掉，是 0.3.4~0.3.8 那一族的老雷）。
--        空格则相反：**只出我们的引导**（客户端模板那句 `ATTACHMENT_TEXT` 是句没有信息量的大白话，
--        既不告诉玩家怎么用、更不会说「推荐在背包里选」）。
--     ③ **删除两档，都不碰物品**：单格 = **点附件格**（左键/右键都行，纯数据）；整批 = **右键计数框**
--        （一次清空整个列表，唯一动作口 `m.multi_clear()`，退出时如实报清掉几条）。
-- ============================================================================

-- ★引导行（**唯一一份**）：标题 + 背包流推荐 + 拖放 + 单格删 + 整批清空 + 发送
m.attach_tip_lines = function()
  return {
    "|cffffd100" .. L[ "ATT_TIP_TITLE" ] .. "|r",
    L[ "ATT_TIP_BAG" ],
    L[ "ATT_TIP_DRAG" ],
    L[ "ATT_TIP_DEL" ],
    L[ "ATT_CLEAR_TIP" ],
    L[ "ATT_TIP_SEND" ],
  }
end

-- 附件格悬停：占用 ⇒ 客户端物品信息 + 追加两行；空格 ⇒ 只出我们的引导
function EHMailTM.attachment_button_on_enter()
  local it = this and this.item
  local tip = m.api.GameTooltip
  if not ( tip and tip.SetOwner ) then return end
  pcall( tip.SetOwner, tip, this, "ANCHOR_RIGHT" )
  if it and it[ 1 ] and it[ 2 ] then
    pcall( tip.SetBagItem, tip, it[ 1 ], it[ 2 ] )
    -- ★每个方法都要把 `tip` 自己当第一个实参传（`pcall(f, …)` **不会**自动带 self ——
    --   漏了就变成 `AddLine(self=" ")`，真机上是「该方法拿不到对象/什么都不显示」）
    pcall( tip.AddLine, tip, " " )
    pcall( tip.AddLine, tip, "|cffffd100" .. L[ "ATT_TIP_THIS" ] .. "|r" )
    pcall( tip.AddLine, tip, L[ "ATT_TIP_BAG" ] )
    pcall( tip.Show, tip )
    return
  end
  pcall( tip.ClearLines, tip )
  local lines = m.attach_tip_lines()
  local i
  for i = 1, getn( lines ) do pcall( tip.AddLine, tip, lines[ i ] ) end
  pcall( tip.Show, tip )
end

function EHMailTM.attachment_button_on_leave()
  local tip = m.api.GameTooltip
  if tip and tip.Hide then pcall( tip.Hide, tip ) end
end

-- ★快速删除（整批）：**唯一动作口**是 `m.multi_clear()` —— 只抹列表数据 + 重投影，一个物品操作都不做。
--   返回清掉的条数（0 = 本来就是空的 ⇒ 如实说一句，不假装做了什么）。
function EHMailTM.multi_box_clear()
  local n = getn( m.multi_list )
  if n == 0 then
    m.info( L[ "ATT_CLEAR_EMPTY" ] )
    return 0
  end
  m.multi_clear()
  m.info( string.format( L[ "ATT_CLEARED" ], n ) )
  return n
end

-- 命令体：/tm 附件 …（`/tm 多选 …` 是等价别名；两个词都认）
m.cmd_multi = function( rest )
  local p = m.multi_split( rest or "" )
  local sub = p[ 1 ] or ""

  if sub == "" or sub == "状态" then
    local lines = m.multi_lines()
    for i = 1, getn( lines ) do m.info( lines[ i ] ) end
    local diag = m.multi_diag()
    for i = 1, getn( diag ) do m.info( "  " .. diag[ i ] ) end
    m.info( "用法：/tm 附件 默认|加 <包> <格>|设 <包> <格>…|清|显示|发|自动|偏移 <dx> <dy>|光标|帮助（右键背包物品 = 加，右键附件格 = 删，拖到附件框 = 加并取消拖拽，右键计数框 = 一次清空）" )
    return
  end

  if sub == "默认" or sub == "重设" then
    m.multi_list = m.multi_default_list()
    m.multi_auto = true
    local shown = m.multi_project()
    m.info( string.format( "选择列表已重设为背包 0 的第 1..4 格（列表 %d 条 ⇒ 附件格挂上 %d 格%s）",
      getn( m.multi_list ), shown, ( shown == 0 ) and m.multi_note_closed() or "" ) )
    return
  end

  if sub == "加" or sub == "add" then
    local bag, slot = tonumber( p[ 2 ] ), tonumber( p[ 3 ] )
    if not bag or not slot then
      m.info( "用法：/tm 附件 加 <包号> <格号>（包号 0 = 主背包）" )
      return
    end
    local r = m.multi_add( bag, slot )
    if r == "ok" then
      local shown = m.multi_project()
      m.info( string.format( "  附件格挂上 %d 格%s", shown, ( shown == 0 ) and m.multi_note_closed() or "" ) )
    end
    return
  end

  if sub == "删" or sub == "del" then
    local bag, slot = tonumber( p[ 2 ] ), tonumber( p[ 3 ] )
    if not bag or not slot then
      m.info( "用法：/tm 附件 删 <包号> <格号>" )
      return
    end
    m.multi_del( bag, slot )
    m.multi_project()
    return
  end

  if sub == "设" then
    local t, i, bad = {}, 2, 0
    while p[ i ] and p[ i + 1 ] do
      local bag, slot = tonumber( p[ i ] ), tonumber( p[ i + 1 ] )
      if bag and slot then tinsert( t, { bag, slot, m.multi_link( bag, slot ) } ) else bad = bad + 1 end
      i = i + 2
    end
    if getn( t ) == 0 then
      m.info( "用法：/tm 附件 设 <包> <格> <包> <格> …（至少一对）" )
      return
    end
    m.multi_list = t
    local shown = m.multi_project()
    m.info( string.format( "选择列表已设为 %d 条（解析失败 %d 对）⇒ 附件格挂上 %d 格%s",
      getn( t ), bad, shown, ( shown == 0 ) and m.multi_note_closed() or "" ) )
    return
  end

  if sub == "清" then
    m.multi_list = {}
    local shown = m.multi_project()
    m.info( string.format( "选择列表已清空、附件格已收干净（现在 %d 格；没碰光标、没碰客户端寄件栏、也没动物品）", shown ) )
    return
  end

  if sub == "显示" or sub == "刷" then
    if not ( m.api.MailFrame and m.api.MailFrame:IsVisible() ) then
      m.info( "|cffff6060邮箱没开|r：附件格只在邮箱窗口里，先打开邮箱（列表数据不受影响）" )
      return
    end
    m.multi_quiet = true
    m.sendmail_show_send_tab()
    m.multi_quiet = nil
    local shown = m.multi_project()
    m.info( string.format( "选择列表 %d 条 ｜ 附件格挂上 %d 格 ｜ 列表里此刻真的还在那格 %d 条",
      getn( m.multi_list ), shown, m.multi_live() ) )
    return
  end

  if sub == "发" then
    m.multi_send_now( "附件发送" )
    return
  end

  if sub == "自动" then
    m.multi_auto = not m.multi_auto
    m.multi_box_refresh()
    if m.multi_auto then
      m.info( "附件自动档 = |cff20ff20开|r：切到发件页时自动把选择列表投影进附件格" )
    else
      m.info( "附件自动档 = |cffff6060关|r：不再自动投影（列表数据保留，/tm 附件 显示 可手动刷）" )
    end
    return
  end

  if sub == "偏移" then
    local dx, dy = tonumber( p[ 2 ] ), tonumber( p[ 3 ] )
    if not dx or not dy then
      m.info( string.format( "用法：/tm 附件 偏移 <dx> <dy>（当前 dx=%d dy=%d）", m.multi_box_dx, m.multi_box_dy ) )
      return
    end
    m.multi_box_dx, m.multi_box_dy = dx, dy
    if m.multi_box then
      m.multi_box:ClearAllPoints()
      m.multi_box:SetPoint( "TOPLEFT", m.api.SendMailFrame, "TOPRIGHT", dx, dy )
    end
    m.info( string.format( "附件小框偏移 = %d, %d", dx, dy ) )
    return
  end

  -- ★0.3.12 只读探针（用户需求②的「查看API是否支持」）：把「光标上有没有东西 / 认不认得出它的家」
  --   一条命令摊开 —— **零副作用**（一个物品操作都不做、连 Show/Hide 都没有）。
  if sub == "光标" or sub == "拖拽" then
    local homes, n = m.cursor_homes()
    if n < 0 then
      m.info( "光标探针：|cffff6060判不出|r ｜ 这一版客户端没有 `CursorHasItem`（或原函数还没装上）" )
      m.info( "  ⇒ 本插件**不会**去动光标（判不出就一个字节都不碰）" )
      return
    end
    if n == 0 then
      m.info( "光标探针：光标上**没有**物品（官方口径：只认背包物品/拆分堆/弹药，不认钱/法术/宏/商人物品）" )
      return
    end
    m.info( string.format( "光标探针：光标上**有**物品 ｜ 锁着的格子 %d 个", n ) )
    local i
    for i = 1, getn( homes ) do
      m.info( string.format( "  源格候选 包 %d 格 %d ｜ %s ｜ 已在选择列表=%s", homes[ i ][ 1 ], homes[ i ][ 2 ],
        homes[ i ][ 3 ] or "（读不到链接）", m.multi_has( homes[ i ][ 1 ], homes[ i ][ 2 ] ) and "是" or "否" ) )
    end
    if n == 1 then
      m.info( "  ⇒ |cff20ff20认得出它的家|r：点【发送】会先把它放回原处；拖到附件框上则「加进列表 + 取消这次拖拽」" )
    else
      m.info( "  ⇒ |cffff6060认不出它的家|r：两处都会如实说一句、一个字节都不碰（绝不清光标）" )
    end
    return
  end

  -- ★0.3.13 信息引导（与附件格/计数框悬停**同一份行**）：`/tm 附件 帮助`
  if sub == "帮助" or sub == "提示" or sub == "guide" then
    local lines = m.attach_tip_lines()
    local i
    for i = 1, getn( lines ) do m.info( lines[ i ] ) end
    m.info( "用法：/tm 附件 默认|加 <包> <格>|删 <包> <格>|清|显示|发|自动|偏移 <dx> <dy>|光标|帮助" )
    return
  end

  m.info( "未知子命令：" .. sub .. " ｜ 可用：状态 默认 加 <包> <格> 删 <包> <格> 设 … 清 显示 发 自动 偏移 光标 帮助" )
end

-- 命令体：/tm 发送背包 <N> [包号]
m.cmd_sendbag = function( rest )
  local p = m.multi_split( rest or "" )
  if p[ 1 ] and not tonumber( p[ 1 ] ) then
    m.info( "用法：/tm 发送背包 <N> [包号]（默认 N=4、包号 0 = 主背包）；例：/tm 发送背包 7" )
    return
  end
  local n = tonumber( p[ 1 ] ) or 4
  local bag = tonumber( p[ 2 ] ) or 0
  if n < 1 then
    m.info( "N 至少是 1" )
    return
  end
  if n > m.multi_cap then
    m.info( string.format( "|cffffd100N=%d 超过附件格容量 %d|r ⇒ 只处理前 %d 件（超出的不挂、也不寄）", n, m.multi_cap, m.multi_cap ) )
    n = m.multi_cap
  end

  -- 先摊现场（只读），再动手 —— 「看着像没反应」时这几行就是唯一判读依据
  local diag = m.multi_diag()
  for i = 1, getn( diag ) do m.info( "  " .. diag[ i ] ) end

  local list, empty = {}, {}
  for i = 1, n do
    local link = m.multi_link( bag, i )
    if link then
      tinsert( list, { bag, i, link } )
    else
      tinsert( empty, i )
    end
  end
  m.info( string.format( "发送背包：包 %d ｜ 取第 1..%d 格 ⇒ 有物品 %d 件 ｜ 空格 %d 格%s", bag, n, getn( list ), getn( empty ),
    ( getn( empty ) > 0 ) and ( "（空格：" .. table.concat( empty, "," ) .. "）" ) or "" ) )
  if getn( list ) == 0 then
    m.info( string.format( "|cffff6060包 %d 的第 1..%d 格全是空的|r ⇒ 中止，没挂也没寄", bag, n ) )
    return
  end

  m.multi_list = list
  m.multi_send_now( "发送背包" )
end

-- ★★★0.3.3 日志列表「一个字都没有」的两轮定案（真机 + 源码；别再走回头路）：
--   一轮：原字体路径写成 `"FONTS\\ARIALN.TTF"`（**目录名全大写**，全仓唯一一处）⇒ 先按「路径大小写敏感」
--        改掉了大小写，并改走项目字体链。
--   二轮（用户截图：已发送页有 3 条、底部计数器正常，而**行里仍然一个字都没有**）—— **真根因不在大小写**：
--        本客户端 `FontString` **没有 `GetFont`**，而当时的 `fontSet` 写着「读不回就当这一步成功」
--        ⇒ 它在**链首 FZLBJW 那一步就 return true**，链子一步没往下走 ⇒ **链尾（真正可用的那条）从未被设过**。
--        ★同页对照证据：底部计数行的 `SetFont( "Fonts\\FRIZQT__.TTF", 10 )` **显示正常**（中文也正常）
--        ⇒ `log.load` 确实跑到了、两参数可用、路径写法也对 ⇒ 剩下的变量只有「链走到哪一条」。
--   ⇒ 现在的口径见 `m.log.fontChain` 上方那两条；链尾 = `Fonts\\ARIALN.TTF`（宿主主插件全界面在用）。
--   ★两页（已收到 / 已发送）**共用同一批 10 个行控件与同一份字体设置**（`log.load` 只跑一次、
--     `log.populate` 两个类型走同一个渲染循环）⇒ 这一处修好，两个页签同时生效。
m.log = m.log or {}
-- ★★★字体链的两条口径（改这里必看）：
--   ① **链尾那条必须真机验证可用** —— 本客户端 FontString **没有 GetFont**（见下），读不回时链会
--      **全部设一遍**，于是**最后一条生效**；链尾 = Fonts\ARIALN.TTF，而宿主主插件 EvalHelp.lua:173
--      全界面用的就是它（那条链的判据恒假 ⇒ 实际恒落到 ARIALN）⇒ 真机验证可用。
--   ② **链首不是兜底** —— 别以为「第一条通常是好的」；0.3.3 二轮报障就是栽在这个假设上。
m.log.fontChain = { "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }
function EHMailTM.log.fontSet( fs, size )
  if not fs or type( fs.SetFont ) ~= "function" then return false end
  local canRead = ( type( fs.GetFont ) == "function" )
  for _, fp in ipairs( m.log.fontChain ) do
    pcall( fs.SetFont, fs, fp, size )
    if canRead then
      local got = fs.GetFont( fs )
      if got and string.lower( got ) == string.lower( fp ) then return true end
    end
  end
  if canRead then
    -- 读得回、但一条都对不上 ⇒ 退回客户端字体对象（至少不是「没有字体」）
    if type( fs.SetFontObject ) == "function" then pcall( fs.SetFontObject, fs, m.api.GameFontNormal ) end
    return false
  end
  -- ★读不回（本客户端没有 GetFont）：链已**全部设过** ⇒ **链尾那条生效**（= ARIALN，真机验证可用）。
  --   绝不再在这一支提前 return —— 那正是「一个字都没有」的成因。
  return true
end

-- ============================================================================
-- 0.3.14 日志页 = **小图标方格聚合展示**（照宿主「图标库」那种网格）
--   用户 2026-10-10 定：「已发送和已收到进行小图标方格聚合展示. 参考图标库的布局形式,
--   tooltip 信息提示是这个邮件的发件人.附件信息.金币等等, 然后点击这个日志图标可以快速切换到发件箱.
--   填充这个日志邮件的发件人操作.」
--   ★四条口径：
--     ① **一格 = 一封邮件**（同名不合并）：图标 = 那封邮件的物品贴图；没有物品时按「拍卖行 → 退回 → 通用便签」
--        顺位兜底；右上角小图章 = 拍卖行 / 退回；右下角小色块 = 有钱（金）/ 到付（橙）。
--     ② **池子建一次、脚本设一次**（照 `IconBrowser` 的写法）：数据走 `c.entry` 现读，
--        **绝不每页重设 `SetScript`**（本客户端 `SetScript` 是单槽位，反复重设容易把别的处理漏掉）。
--     ③ **tooltip = 这一封的全部信息**（对方 / 主题 / 附件 / 金币 / 到付 / 时间）+ **点一下会做什么**。
--     ④ **点一下 = 切到写邮件页 + 把收件人填成「对方」**（`m.log.tile_click` → `m.sendmail_show_send_tab()`）：
--        已发送那页的「对方」= 当年的收件人（再寄给他）；已收到那页 = 来信的发件人（回信给他）；
--        拍卖行 / 系统寄来的没有对方 ⇒ **只切页面 + 如实说一句**（绝不编一个名字填进去）。
-- ============================================================================

-- 池子几何（**唯一来源**）：一格 30、图形 28、图标 26、内边距 4 ⇒ 9 列 × 10 行 = 90 格
--   宽 = 4 + 9*30 - 2 = 272 ≤ 296（滚动框宽）· 高 = 4 + 10*30 - 2 = 302 ≤ 312（滚动框高）
m.LOG_COLS = 9
m.LOG_ROWS = 10
m.LOG_CELL = 30
m.LOG_TILE = 28
m.LOG_ICON = 26
m.LOG_PAD = 4
m.LOG_BG_RGB = { 0.10, 0.09, 0.06 }
m.LOG_BG_HOVER = { 0.38, 0.30, 0.10 }
m.LOG_NOTE_ICON = "Interface\\Icons\\INV_Misc_Note_01"
m.LOG_STAMP_AH = "Interface\\AddOns\\EH_Mail\\EHMailTM-AH.blp"
m.LOG_STAMP_RET = "Interface\\AddOns\\EH_Mail\\EHMailTM-RetArrow.blp"

-- 池子（**建一次**）：`m.log.tiles[i]` 顺序 = 行优先，与锚点一一对应
m.log.build_grid = function()
  if m.log.tiles then return end
  local host = m.api.EHMailTMLogEntriesFrame
  if host == nil then return end
  local cols, rows = m.LOG_COLS, m.LOG_ROWS
  local cell, tile, icon = m.LOG_CELL, m.LOG_TILE, m.LOG_ICON
  local bgR, bgG, bgB = m.LOG_BG_RGB[ 1 ], m.LOG_BG_RGB[ 2 ], m.LOG_BG_RGB[ 3 ]
  local tiles = {}
  local i
  for i = 1, cols * rows do
    local col = math.mod( i - 1, cols )
    local row = math.floor( ( i - 1 ) / cols )
    local b = m.api.CreateFrame( "Button", nil, host )
    b:SetWidth( tile )
    b:SetHeight( tile )
    b:SetPoint( "TOPLEFT", host, "TOPLEFT", m.LOG_PAD + col * cell, -( m.LOG_PAD + row * cell ) )
    pcall( b.EnableMouse, b, true )
    pcall( b.RegisterForClicks, b, "LeftButtonUp" )
    local bg = b:CreateTexture( nil, "BACKGROUND" )
    pcall( bg.SetTexture, bg, "Interface\\Buttons\\WHITE8x8" )
    pcall( bg.SetVertexColor, bg, bgR, bgG, bgB, 1 )
    bg:SetPoint( "TOPLEFT", b, "TOPLEFT", 0, 0 )
    bg:SetPoint( "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0 )
    local tex = b:CreateTexture( nil, "ARTWORK" )
    tex:SetWidth( icon )
    tex:SetHeight( icon )
    tex:SetPoint( "CENTER", b, "CENTER", 0, 0 )
    -- 图标自带留白收掉一点（与宿主图标库同款做法）
    pcall( tex.SetTexCoord, tex, 0.07, 0.93, 0.07, 0.93 )
    local stamp = b:CreateTexture( nil, "OVERLAY" )
    stamp:SetWidth( 12 )
    stamp:SetHeight( 12 )
    stamp:SetPoint( "TOPRIGHT", b, "TOPRIGHT", 1, -1 )
    pcall( stamp.Hide, stamp )
    local dot = b:CreateTexture( nil, "OVERLAY" )
    pcall( dot.SetTexture, dot, "Interface\\Buttons\\WHITE8x8" )
    dot:SetWidth( 7 )
    dot:SetHeight( 7 )
    dot:SetPoint( "BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1 )
    pcall( dot.Hide, dot )
    local c = { btn = b, bg = bg, tex = tex, stamp = stamp, dot = dot, entry = nil }
    -- ★脚本只在建池时设一次（数据靠 c.entry 现读）
    b:SetScript( "OnClick", function() m.log.tile_click( c ) end )
    b:SetScript( "OnEnter", function() m.log.tile_enter( c ) end )
    b:SetScript( "OnLeave", function() m.log.tile_leave( c ) end )
    tiles[ i ] = c
  end
  m.log.tiles = tiles
end

-- 画一格（`e == nil` = 这一格收起来；池子是复用的，**每一趟都要显式 Show/Hide**）
m.log.tile_paint = function( c, e )
  if e == nil then
    c.entry = nil
    pcall( c.btn.Hide, c.btn )
    return
  end
  c.entry = e
  local ic = e.icon
  if ic == nil or ic == "" then
    if e.ah then ic = m.LOG_STAMP_AH
    elseif e.returned then ic = m.LOG_STAMP_RET
    else ic = m.LOG_NOTE_ICON end
  end
  pcall( c.tex.SetTexture, c.tex, ic )
  if e.ah then
    pcall( c.stamp.SetTexture, c.stamp, m.LOG_STAMP_AH )
    pcall( c.stamp.Show, c.stamp )
  elseif e.returned then
    pcall( c.stamp.SetTexture, c.stamp, m.LOG_STAMP_RET )
    pcall( c.stamp.Show, c.stamp )
  else
    pcall( c.stamp.Hide, c.stamp )
  end
  -- 右下角色块：到付 = 橙 · 有钱 = 金 · 都没有 ⇒ 收起
  if e.cod and e.cod > 0 then
    pcall( c.dot.SetVertexColor, c.dot, 1.00, 0.55, 0.15, 1 )
    pcall( c.dot.Show, c.dot )
  elseif e.money and e.money > 0 then
    pcall( c.dot.SetVertexColor, c.dot, 1.00, 0.82, 0.10, 1 )
    pcall( c.dot.Show, c.dot )
  else
    pcall( c.dot.Hide, c.dot )
  end
  pcall( c.bg.SetVertexColor, c.bg, m.LOG_BG_RGB[ 1 ], m.LOG_BG_RGB[ 2 ], m.LOG_BG_RGB[ 3 ], 1 )
  pcall( c.btn.Show, c.btn )
end

m.log.tile_enter = function( c )
  pcall( c.bg.SetVertexColor, c.bg, m.LOG_BG_HOVER[ 1 ], m.LOG_BG_HOVER[ 2 ], m.LOG_BG_HOVER[ 3 ], 1 )
  local e = c.entry
  if e == nil then return end
  m.log.tile_tip( c.btn, e )
end

m.log.tile_leave = function( c )
  pcall( c.bg.SetVertexColor, c.bg, m.LOG_BG_RGB[ 1 ], m.LOG_BG_RGB[ 2 ], m.LOG_BG_RGB[ 3 ], 1 )
  local tip = m.api.GameTooltip
  if tip and tip.Hide then pcall( tip.Hide, tip ) end
end

-- tooltip = 这一封的全部信息 + 「点一下会做什么」（★每个方法都要把 tip 自己当第一个实参）
m.log.tile_tip = function( owner, e )
  local tip = m.api.GameTooltip
  if not ( tip and tip.SetOwner ) then return end
  pcall( tip.SetOwner, tip, owner, "ANCHOR_RIGHT" )
  pcall( tip.ClearLines, tip )
  local sent = ( m.current_log_type == "Sent" )
  local who = e.participant
  if who == nil or who == "" then who = L[ "LOG_TIP_NONE" ] end
  pcall( tip.AddLine, tip, "|cffffd100" .. L[ sent and "LOG_TIP_SENT" or "LOG_TIP_RECEIVED" ] .. "：" .. who .. "|r" )
  local tags = {}
  if e.ah then tinsert( tags, L[ "LOG_TIP_LABEL_AH" ] ) end
  if e.returned then tinsert( tags, L[ "LOG_TIP_LABEL_RETURNED" ] ) end
  if e.gm then tinsert( tags, L[ "LOG_TIP_LABEL_GM" ] ) end
  if getn( tags ) > 0 then
    pcall( tip.AddLine, tip, table.concat( tags, " ｜ " ), 0.75, 0.75, 0.75 )
  end
  if e.subject and e.subject ~= "" then
    pcall( tip.AddLine, tip, L[ "LOG_TIP_SUBJECT" ] .. "：" .. e.subject, 1, 1, 1 )
  end
  local item = e.item_name
  if item == nil or item == "" then item = L[ "LOG_TIP_NONE" ] end
  pcall( tip.AddLine, tip, L[ "LOG_TIP_ITEM" ] .. "：" .. item, 0.55, 0.85, 0.45 )
  if e.money and e.money > 0 then
    pcall( tip.AddLine, tip, L[ sent and "LOG_TIP_PAID" or "LOG_TIP_EARNED" ] .. "：" .. m.format_money( e.money ), 1, 0.82, 0.10 )
  end
  if e.cod and e.cod > 0 then
    pcall( tip.AddLine, tip, L[ "LOG_TIP_COD" ] .. "：" .. m.format_money( e.cod ), 1, 0.55, 0.15 )
  end
  pcall( tip.AddLine, tip, L[ "LOG_TIP_TIME" ] .. "：" .. m.format_datetime( e.timestamp ), 0.7, 0.7, 0.7 )
  pcall( tip.AddLine, tip, " " )
  if who ~= L[ "LOG_TIP_NONE" ] then
    pcall( tip.AddLine, tip, string.format( L[ "LOG_TIP_CLICK" ], who ), 0.55, 0.85, 0.45 )
  else
    pcall( tip.AddLine, tip, L[ "LOG_TIP_CLICK_NONE" ], 0.55, 0.85, 0.45 )
  end
  pcall( tip.Show, tip )
end

-- 点一格 = **切到写邮件页 + 把收件人填成对方**（对方为空 ⇒ 只切页 + 如实说一句）
m.log.tile_click = function( c )
  local e = c.entry
  if e == nil then return end
  local name = e.participant
  -- ★先切页、再填名字：切页会触发一次 SendMailFrame_Update，顺序反了会被它擦掉
  m.sendmail_show_send_tab()
  if name == nil or name == "" then
    m.info( L[ "LOG_FILL_NONE" ] )
    return
  end
  local box = m.api.SendMailNameEditBox
  if box == nil or type( box.SetText ) ~= "function" then
    m.info( string.format( L[ "LOG_FILL_FAIL" ], name ) )
    return
  end
  pcall( box.SetText, box, name )
  if type( box.SetFocus ) == "function" then pcall( box.SetFocus, box ) end
  m.info( string.format( L[ "LOG_FILL_OK" ], name, L[ m.current_log_type ] ) )
end

function EHMailTM.log.load()
  m.api.EHMailTMLogTitleText:SetText( L[ "Log" ] )
  m.api.MailFrameTab3:SetText( L[ "Log" ] )

  -- ★0.3.14：日志页改成**小图标方格聚合展示**（池子建一次、脚本设一次；不再有 10 行文字行控件）
  m.log.build_grid()

  m.api.EHMailTMLogStatusText:SetTextColor( 1, 1, 1, 1 )
  -- ★0.3.14：日志页只剩这一行文字（格子里的都是贴图）⇒ 它继续走 0.3.3 定案的那条**字体链 + 读回自证**
  --   （`m.log.fontSet` 因此仍是活的唯一写口；`SetFont(path, size)` 两参数可用那条证据照旧留在记忆体里）
  m.log.fontSet( m.api.EHMailTMLogStatusText, 10 )
  m.api.EHMailTMLogScrollFrameScrollBar:SetValueStep( 1 )
  m.api.EHMailTMLogScrollFrameScrollBar:SetScript( "OnValueChanged", m.log.on_scroll_value_changed )

  m.api.EHMailTMLogScrollFrame:SetScript( "OnMouseWheel", function()
    m.log.scroll( arg1 * 3 )
  end )
  m.api.EHMailTMLogScrollFrameScrollBarScrollUpButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( m.LOG_ROWS )
  end )
  m.api.EHMailTMLogScrollFrameScrollBarScrollDownButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( -m.LOG_ROWS )
  end )

  m.api.EHMailTMLogFiltersButton:SetText( L[ "Filters" ] )
  m.api.EHMailTMLogFiltersButton:GetFontString():SetPoint( "LEFT", m.api.EHMailTMLogFiltersButton, "LEFT", 10, 0 )

  m.api.EHMailTMLogFiltersButton:SetScript( "OnMouseDown", function()
    m.api.EHMailTMLogFiltersButtonArrow:SetPoint( "RIGHT", m.pfui_skin_enabled and -4 or -8, -3 )
  end )
  m.api.EHMailTMLogFiltersButton:SetScript( "OnMouseUp", function()
    m.api.EHMailTMLogFiltersButtonArrow:SetPoint( "RIGHT", m.pfui_skin_enabled and -4 or -8, -1 )
  end )

  m.api.EHMailTMLogStartTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.EHMailTMLogStartTimeButton:SetScale( 0.9 )
  m.api.EHMailTMLogEndTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.EHMailTMLogEndTimeButton:SetScale( 0.9 )

  m.api.EHMailTMLogStartTime:SetScript( "OnClick", function()
    m.api.EHMailTMLogStartTimeText:SetText( "" )
    m[ m.current_log_type .. "_start_time" ] = nil
    m.log.populate( m.current_log_type )
  end )
  m.api.EHMailTMLogEndTime:SetScript( "OnClick", function()
    m.api.EHMailTMLogEndTimeText:SetText( "" )
    m[ m.current_log_type .. "_end_time" ] = nil
    m.log.populate( m.current_log_type )
  end )

  m.api.EHMailTMLogPlayersDropDown:SetScale( 0.9 )
  m.api.UIDropDownMenu_SetText( L[ "All players"] , m.api.EHMailTMLogPlayersDropDown )

  m.dropdown_filters = m.api.CreateFrame( "Frame", "EHMailTMDropDownFilters" )
  m.dropdown_filters.displayMode = "MENU"
  m.dropdown_filters.info = {}
end

function EHMailTM.log.players_dropdown_on_load()
  m.api.UIDropDownMenu_Initialize( m.api.EHMailTMLogPlayersDropDown, function()
    local info = {}
    info.notCheckable = 1
    info.text = L[ "All players"]
    info.arg1 = info.text
    info.arg2 = "All"
    info.func = m.log.select_player
    m.api.UIDropDownMenu_AddButton( info )

    if not m.current_log_type then return end

    local players = {}
    for _, v in ipairs( m.api.EHMailTM_Log[ m.current_log_type ] ) do
      if v then
        players[ v.participant ] = players[ v.participant ] and players[ v.participant ] + 1 or 1
      end
    end

    for player, count in pairs( players ) do
      info.text = player .. " (" .. count .. ")"
      info.arg1 = player
      info.arg2 = nil
      m.api.UIDropDownMenu_AddButton( info )
    end
  end )
end

function EHMailTM.log.select_player( player, is_all )
  m.api.UIDropDownMenu_SetText( player, m.api.EHMailTMLogPlayersDropDown )
  if is_all then
    m.filter_player = nil
  else
    m.filter_player = player
  end
  m.log.populate( m.current_log_type )
end

function EHMailTM.log.filter_dropdown()
  if m.dropdown_filters.initialize ~= EHMailTM.log.filters_menu then
    m.api.CloseDropDownMenus()
    m.dropdown_filters.initialize = EHMailTM.log.filters_menu
  end
  m.api.ToggleDropDownMenu( 1, nil, m.dropdown_filters, this:GetName(), 0, 0 )
end

function EHMailTM.log.filters_menu( level )
  local filters = m.api.EHMailTM_Log[ "Settings" ][ m.current_log_type .. "Filters" ] or {}
  local info = {}
  info.keepShownOnClick = 1

  -- 键名必须与 EHMailTM_Log.Settings 各过滤表及 populate 使用的英文键一致
  local values = { "Money", "COD", "Other" }
  if m.current_log_type == "Received" then
    table.insert( values, "Returned" )
    table.insert( values, "AH" )
  end

  if level == 1 then
    for _, filter in values do
      info.text = L[ filter ]
      info.checked = filters[ filter ]
      info.arg1 = filter
      info.func = m.log.toggle_filter
      if filter == "AH" then info.hasArrow = 1 end

      m.api.UIDropDownMenu_AddButton( info, level )
    end
  elseif level == 2 then
    -- 一级菜单的 hasArrow 会残留在复用的 info 上，清掉
    info.hasArrow = nil
    for _, filter in { "Sold", "Removed", "Expired", "Outbid", "Won" } do
      info.text = L[ filter ]
      info.checked = filters[ "AH" .. filter ]
      info.arg1 = filter
      info.arg2 = "AH"
      info.func = m.log.toggle_filter
      m.api.UIDropDownMenu_AddButton( info, level )
    end
  end
end

function EHMailTM.log.toggle_filter( filter, parent_filter )
  if not parent_filter then parent_filter = "" end
  local filter_value = m.api.EHMailTM_Log[ "Settings" ][ m.current_log_type .. "Filters" ][ parent_filter .. filter ]

  m.api.EHMailTM_Log[ "Settings" ][ m.current_log_type .. "Filters" ][ parent_filter .. filter ] = not filter_value
  m.log.populate( m.current_log_type )
end

function EHMailTM.log.show_calendar()
  if m.calendar.is_visible() then
    m.calendar.hide()
  else
    local text = string.gsub( this:GetName(), "Button", "Text" )
    m.calendar.show( m.api.EHMailTM_Log[ m.current_log_type ], time(), this, function( selected_date )
      local date_str = m.format_date( selected_date )
      m.api[ text ]:SetText( date_str )

      local v = m.current_log_type .. (string.find( text, "Start" ) and "_start_time" or "_end_time")
      m[ v ] = selected_date
      m.log.populate( m.current_log_type )
    end )
  end
end

function EHMailTM.log.scroll( step )
  local scroll_bar = m.api.EHMailTMLogScrollFrameScrollBar
  local current = scroll_bar:GetValue()
  local min, max = scroll_bar:GetMinMaxValues()
  local new = current - step

  if new >= max then
    scroll_bar:SetValue( max )
  elseif new <= min then
    scroll_bar:SetValue( 0 )
  else
    scroll_bar:SetValue( new )
  end
end

function EHMailTM.log.on_scroll_value_changed()
  local function round( num )
    return num + (2 ^ 52 + 2 ^ 51) - (2 ^ 52 + 2 ^ 51)
  end

  local scrollBar = m.api.EHMailTMLogScrollFrameScrollBar
  local scrollUp = m.api.EHMailTMLogScrollFrameScrollBarScrollUpButton
  local scrollDown = m.api.EHMailTMLogScrollFrameScrollBarScrollDownButton

  local minVal, maxVal = scrollBar:GetMinMaxValues()
  local currentVal = round( scrollBar:GetValue() )

  if currentVal <= round( minVal ) then
    scrollUp:Disable()
  else
    scrollUp:Enable()
  end

  if currentVal >= round( maxVal ) then
    scrollDown:Disable()
  else
    scrollDown:Enable()
  end

  m.log.populate( m.current_log_type, currentVal )
end

---@alias LogType
---| "Sent"
---| "Received"

---@param log_type LogType
---@param state table
function EHMailTM.log.add( log_type, state )
  if not m.log_enabled then return end
  m.debug( "Logging " .. log_type .. " message" )

  local data = {
    timestamp = time(),
    icon = state.icon,
    item = state.item
  }

  if state.item_name then data.item_name = state.item_name end
  -- 留档邮件正文：竞得(Won)类邮件的花费金额只在正文里，邮件头没有该字段
  if state.body and state.body ~= "" then data.body = state.body end

  if state.cod and state.cod > 0 then data.cod = tonumber( state.cod ) end
  if log_type == "Sent" then
    data.participant = state.to
    data.subject = state.sent_subject
    if state.send_money and state.sent_money > 0 then data.money = tonumber( state.sent_money ) end
  else -- Received
    data.participant = state.from
    data.subject = state.subject
    data.returned = state.returned
    data.gm = state.gm

    if state.money and state.money > 0 then data.money = tonumber( state.money ) end

    if string.find( data.subject, string.gsub( m.api.AUCTION_SOLD_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Sold"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_REMOVED_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Removed"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Expired"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_WON_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Won"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_OUTBID_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Outbid"
    end
  end

  table.insert( m.api.EHMailTM_Log[ log_type ], data )
end

---@param log_type LogType
---@param index number?
function EHMailTM.log.populate( log_type, index )
  m.current_log_type = log_type
  local filters = m.api.EHMailTM_Log[ "Settings" ][ log_type .. "Filters" ] or {}
  local start_time = m[ log_type .. "_start_time" ]
  local end_time = m[ log_type .. "_end_time" ]
  if start_time then start_time = start_time - 43200 end
  if end_time then end_time = end_time + 43140 end

  local log = m.filter( m.api.EHMailTM_Log[ log_type ], function( item )
    local ret =
        (filters.Money and item.money and item.money > 0 and (not item.cod or item.cod == 0) and not item.ah)
        or
        (filters.COD and item.cod and item.cod > 0)
        or
        (filters.Other and (not item.cod or item.cod == 0) and not item.ah and not item.returned and (not item.money or item.money == 0))
        or
        (filters.Returned and item.returned)
        or
        (filters.AH and filters.AHWon and item.ah == "Won")
        or
        (filters.AH and filters.AHSold and item.ah == "Sold")
        or
        (filters.AH and filters.AHCancelled and item.ah == "Removed")
        or
        (filters.AH and filters.AHOutbid and item.ah == "Outbid")
        or
        (filters.AH and filters.AHExpired and item.ah == "Expired")

    if m.filter_player then
      ret = ret and item.participant == m.filter_player
    end
    if start_time then
      ret = ret and item.timestamp >= start_time
    end
    if end_time then
      ret = ret and item.timestamp <= end_time
    end

    return ret
  end )

  m.api.EHMailTMLogStartTimeText:SetText( start_time and m.format_date( start_time ) or "" )
  m.api.EHMailTMLogEndTimeText:SetText( end_time and m.format_date( end_time ) or "" )

  -- ★0.3.3：空日志也要走完下面的渲染 —— 原来这里直接 return，页面会**留着上一次的残留**
  --（计数器还停在上一次的数字、行还是上一次的行）。
  if not log then log = {} end
  local log_count = getn( log )

  -- ★0.3.14：**小图标方格**（聚合展示）—— 滚动/翻页单位从「10 行文字」改成「一格 = 一封、一页 = COLS*ROWS 封」
  local cols, rows = m.LOG_COLS, m.LOG_ROWS
  local row_count = math.ceil( log_count / cols )
  local max_row = math.max( 0, row_count - rows )
  local bar = m.api.EHMailTMLogScrollFrameScrollBar
  bar:SetMinMaxValues( 0, max_row )

  if not index then
    index = max_row
    bar:SetValue( index )
    -- ★客户端会在我们之后自己再摆一次滚动条 ⇒ 下一拍补一次（老写法原样保留）
    bar:SetScript( "OnUpdate", function()
      bar:SetValue( index )
      bar:SetScript( "OnUpdate", nil )
    end )
  end
  index = math.floor( tonumber( index ) or 0 )
  if index < 0 then index = 0 end
  if index > max_row then index = max_row end

  -- 标题显示当前日志类型（已收到/已发送）
  m.api.EHMailTMLogTitleText:SetText( string.format( "%s %s", L[ m.current_log_type ], L[ "Log" ] ) )
  local first = ( log_count == 0 ) and 0 or ( index * cols + 1 )
  local last = math.min( log_count, ( index + rows ) * cols )
  m.api.EHMailTMLogStatusText:SetText( string.format( L[ "LOG_STATUS" ], log_count, first, last ) )

  -- 铺格子：池子复用 ⇒ **每一趟都显式 Show/Hide**（`log[...]` 为 nil 就是这一格该收起）
  m.log.build_grid()
  local tiles = m.log.tiles
  if tiles then
    local per = cols * rows
    for i = 1, per do
      local c = tiles[ i ]
      if c then m.log.tile_paint( c, log[ index * cols + i ] ) end
    end
  end
end

-- ============================================================================
-- 0.3.15 关邮箱 = **附件选择整体作废**（背包里的「附件锁定」必须一起清干净）
--   用户 2026-10-10 定：「在邮箱关闭之后. 要做好背包内附件锁定清理的流程.」
--   ★★为什么关邮箱必须清理 —— 两处外观都由这份选择列表派生，而它们**谁都不会自己复位**：
--     ① **背包整合（EH_Bag）那层「附件」遮盖 + 备注文字**：它的判定口只问 `multi_has(包, 格)`
--        ⇒ 列表不空 ⇒ 关掉邮箱之后遮盖照旧画在背包格上（它的刷新要人来喊）；
--     ② **客户端自己的背包格**：`hook.GetContainerItemInfo` 给选中格伪报 `locked`（= 选中反馈），
--        而客户端是**画的那一拍**读它 —— `ContainerFrame_Update` 里
--        `SetItemButtonDesaturated( itemButton, locked, 0.5, 0.5, 0.5 )` 把图标压灰
--        ⇒ 关邮箱之后没有任何事件让它重画，最后一次画上去的灰化就留在屏上。
--   ⇒ 唯一清理口 `m.multi_release( why )`：**先清数据、再清外观**（★顺序即判据 ——
--     反过来的话，重画那一刻列表还在，遮盖会被照旧算出来并画上）；全程**纯数据**
--     （不碰光标 / 不碰客户端寄件栏 / 一件物品都不动 —— 0.3.11 的口径一个字节没改）。
--   ★口径 = **整体作废**（用户选定）：关掉邮箱 = 这次选附件的事就算了，重开邮箱从零开始选。
--     要「手动清但不关邮箱」照旧走 `/tm 附件 清` 与右键计数框（同一个 `m.multi_clear` 家族）。
-- ============================================================================

-- 让背包格子重画一次（清掉客户端最后一次画上去的「锁定 / 灰化」外观）。返回真调过的帧数。
--   ★两条腿各自 fail-open：
--     ① 背包整合在场 ⇒ 客户端那批原生容器帧被它藏了（它的 `ContainerFrame_Update` 包装只 Hide），
--        外观长在它自己那批按钮上 ⇒ 由它自己的刷新口管（`m.multi_tell_bag` 已经喊过它）；
--     ② 客户端自己的容器帧 ⇒ 调它的 FrameXML 更新口 `ContainerFrame_Update(帧)` 重读一遍
--        （这一刻 `locked` 已经不再伪报 ⇒ 灰化当场消失）。
--   ★拿不到那个口 / 某个帧不存在 ⇒ **一个字节都不碰**（绝不硬造全局、绝不写别人的帧）——
--     真机上「重画不了」只是外观留到下一次背包刷新，绝不是丢东西。
m.bag_repaint = function()
  local upd = m.api.ContainerFrame_Update
  if type( upd ) ~= "function" then return 0 end
  local n = 0
  for i = 1, 12 do
    local fr = rawget( _G, "ContainerFrame" .. i )
    if fr then
      if pcall( upd, fr ) then n = n + 1 end
    end
  end
  return n
end

-- ★唯一清理口（关邮箱走它；将来任何「整体作废」也必须走它，绝不另写一份）
--   返回清掉的条数；`why` 只进诊断读数（给人看「这一次是谁清的」）。
m.multi_release = function( why )
  local n = getn( m.multi_list )
  -- ① 数据：整体作废
  m.multi_list = {}
  -- ② 投影：抹掉附件格（邮箱已关时它只做开头那一步「通知背包侧」—— 那正是我们要的）
  m.multi_project()
  -- ③ 外观：让客户端自己的背包格重画一次
  local frames = m.bag_repaint()
  -- ④ 取证（`/tm 附件 状态` 打出来；纯读、不落存档）
  m.release_n = n
  m.release_why = why or ""
  m.release_frames = frames
  -- ⑤ 出声：只有真的清掉了东西才说（本来就是空的 ⇒ 一声不出，不刷屏）
  if n > 0 then
    m.info( string.format( L[ "REL_CLOSED" ], n ) )
  end
  return n
end

-- ★移植适配：pfUI 美化已整体剔除（原 pfui-skin.lua 文件已删），本版只保留原版 UI 分支
function EHMailTM.filter( t, f, extract_field )
  if not t then return nil end
  if type( f ) ~= "function" then return t end

  local result = {}

  for i = 1, getn( t ) do
    local v = t[ i ]
    local value = type( v ) == "table" and extract_field and v[ extract_field ] or v
    if f( value ) then table.insert( result, v ) end
  end

  return result
end

function EHMailTM.info( message )
  -- ★0.3.17：前缀 = 插件目录名（见文件头的 `m.ADDON_NAME`），不再是内部表名 `EHMailTM`
  m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cff66ccff[%s]|r %s", m.ADDON_NAME, message ) )
end

function EHMailTM.dump( o )
  if not o then return "nil" end
  if type( o ) ~= 'table' then return tostring( o ) end

  local entries = 0
  local s = "{"

  for k, v in pairs( o ) do
    if (entries == 0) then s = s .. " " end
    local key = type( k ) ~= "number" and '"' .. k .. '"' or k
    if (entries > 0) then s = s .. ", " end
    s = s .. "[" .. key .. "] = " .. m.dump( v )
    entries = entries + 1
  end

  if (entries > 0) then s = s .. " " end
  return s .. "}"
end

function EHMailTM.debug( ... )
  if m.debug_enabled then
    local messages = ""
    for i = 1, getn( arg ) do
      local message = arg[ i ]
      if message then
        messages = messages == "" and "" or messages .. ", "
        if type( message ) == 'table' then
          messages = messages .. EHMailTM.dump( message )
        else
          messages = messages .. message
        end
      end
    end

    -- ★0.3.17：调试行同样走统一前缀（内部表名只许出现在代码里）
    m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cff66ccff[%s]|r %s", m.ADDON_NAME, messages ) )
  end
end

EHMailTM:init()
