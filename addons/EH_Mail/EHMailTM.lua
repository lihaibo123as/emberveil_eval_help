EHMailTM = EHMailTM or {}
L = EHMailTM.L

local m = EHMailTM

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

---@param args string
function EHMailTM.slash_command( args )
  if args == "" or args == "help" then
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473EHMailTM " .. L[ "Help" ] .. "|r" )
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
end

function EHMailTM.MAIL_CLOSED()
  m.inbox_abort()
  m.sendmail_sending = false
  m.sendmail_clear()
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

  -- 小窗开关（方案A）：钉在"接收所有邮件"右侧，纯字体符号零贴图；
  -- pfUI 下由皮肤回调 SkinButton 换装，原版走按钮原生底
  local btnToggle = m.api.CreateFrame( "Button", "EHMailTMPanelToggleButton", m.api.InboxFrame, "UIPanelButtonTemplate" )
  btnToggle:SetPoint( "LEFT", btnAll, "RIGHT", 0, 0 )
  btnToggle:SetWidth( 22 )
  btnToggle:SetHeight( 26 )
  btnToggle:SetScript( "OnClick", function()
    if not m.batch_panel then return end
    if m.batch_panel:IsVisible() then
      m.batch_panel:Hide()
      m.api.EHMailTM_PanelHidden = 1
    else
      m.batch_panel:Show()
      m.api.EHMailTM_PanelHidden = nil
      if m.batch_reanchor then m.batch_reanchor() end
      m.batch_settle = 30
    end
    m.update_panel_toggle_btn()
  end )
  btnToggle:SetScript( "OnEnter", function()
    m.api.GameTooltip:ClearLines()
    m.api.GameTooltip:SetOwner( this, "ANCHOR_LEFT" )
    m.api.GameTooltip:AddLine( m.api.EHMailTM_PanelHidden and "展开批量面板" or "收起批量面板", "", 1, 1, 0 )
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

-- 小窗开关按钮的两态文案：» / « 恒为金色（捞哥要求不做变灰），靠符号方向区分开合
function EHMailTM.update_panel_toggle_btn()
  local btn = m.api.EHMailTMPanelToggleButton
  if not btn then return end
  if m.api.EHMailTM_PanelHidden then
    btn:SetText( "|cffffd100«|r" )
  else
    btn:SetText( "|cffffd100»|r" )
  end
end

function EHMailTM.batch_load()
  -- 只建一次。inbox_load 每次开邮箱都会调用这里，重复 CreateFrame 同名控件
  -- 会返回新 frame 而旧的仍留在屏幕上，叠成一堆错位的面板。
  if m.batch_panel then
    -- 尊重小窗开关的收起状态：不能每次开邮箱都强制弹出来
    if not m.api.EHMailTM_PanelHidden then
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

  -- 存档里是收起状态：首次建好后保持隐藏
  if m.api.EHMailTM_PanelHidden then
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
      texture, count = m.api.GetContainerItemInfo( unpack( btn.item ) )
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
  m.sendmail_set_attachment( m.get_cursor_item() )
end

function EHMailTM.hook.GetContainerItemInfo( bag, slot )
  local ret = pack( m.orig.GetContainerItemInfo( bag, slot ) )
  ret[ 3 ] = ret[ 3 ] or m.sendmail_attached( bag, slot ) and 1 or nil
  return unpack( ret )
end

function EHMailTM.hook.PickupContainerItem( bag, slot )
  -- Alt+Left: add all same items Alt+左键一键添加相同物品到发送框
  if arg1 == "LeftButton" and m.api.IsAltKeyDown() and m.api.MailFrame:IsVisible() then
    local link = m.api.GetContainerItemLink(bag, slot)
    if link then
      local _, _, itemId = string.find(link, "item:(%d+)")
      if itemId then
        itemId = tonumber(itemId)
        -- Iterate through all bags
        for b = 0, 4 do
          local slots = m.api.GetContainerNumSlots(b)
          for s = 1, slots do
            -- Check if attachment slots are full
            if m.sendmail_num_attachments() >= ATTACHMENTS_MAX then
              break
            end
            local l = m.api.GetContainerItemLink(b, s)
            if l then
              local _, _, id = string.find(l, "item:(%d+)")
              if id and tonumber(id) == itemId then
                if not m.sendmail_attached(b, s) then
                  m.sendmail_set_attachment({b, s})
                end
              end
            end
          end
          if m.sendmail_num_attachments() >= ATTACHMENTS_MAX then
            break
          end
        end
      end
    end
    return
  end

  if m.sendmail_attached( bag, slot ) then
    if arg1 == "RightButton" and m.api.MailFrame:IsVisible() then
      return m.sendmail_remove_attachment( { bag, slot } )
    end
    -- ★左键把已挂载的这件**真的拿起来** ⇒ 记账必须一起清：记账只记 {bag,slot}，物品一离开那格，
    --   这条记账就指向「空位或别的东西」（= 用户说的「内部的数据没有更新」）。
    --   ★代价如实：拿起后又放回原处 = 需要重新挂一次（宁可少挂，也不能拿旧记账去发错东西）。
    if m.api.MailFrame:IsVisible() then m.sendmail_forget( bag, slot ) end
    return m.orig.PickupContainerItem( bag, slot )
  end

  if m.api.GetContainerItemInfo( bag, slot ) then
    if arg1 == "RightButton" and m.api.MailFrame:IsVisible() then
      m.sendmail_show_send_tab()
      m.sendmail_set_attachment( { bag, slot } )
      return
    else
      m.set_cursor_item( { bag, slot } )
    end
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
    m.sendmail_show_send_tab()
    m.sendmail_set_attachment( { bag, slot } )
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

  -- ★★★0.3.3 真机报障「多邮件发送异常 / 内部数据没更新 / 放到第二件就失败」的**主根因**：
  --   上游写好了 attachment_button_on_click（点附件格 = 拿出 / 与光标上的物品交换），
  --   却**从来没有把它挂到任何控件上**（全文件零引用）⇒ 附件格的点击与拖放**仍是客户端自己的行为**：
  --   ① 拖着物品放到附件格 ⇒ 客户端**真的**把它放进附件栏，而我们的记账里没有这一条
  --      ⇒ 界面/记账/背包三份状态各说各话；
  --   ② 点附件格拿东西 ⇒ 走客户端逻辑，**我们的记账一个字都不动**
  --      ⇒ 用户看到的就是「拿出来了、内部数据没更新、发出去的还是第一次那件」；
  --   ③ 真进了附件栏的物品在客户端里是「已附加」状态 ⇒ 之后 PickupContainerItem 拿不起来
  --      （真机诊断：连试 4 次都是空手而归）。
  --   ⇒ 把附件格整条接管过来：点击走我们的处理体、**禁止接收拖放**、撤掉拖拽注册。
  --   ★挂载方式仍是「右键点背包里的物品」（hook.PickupContainerItem ⇒ sendmail_set_attachment），与这里无关。
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn then
      btn:SetScript( "OnClick", m.attachment_button_on_click )
      btn:RegisterForClicks( "LeftButtonUp", "RightButtonUp" )
      btn:SetScript( "OnReceiveDrag", nil )
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

function EHMailTM.attachment_button_on_click()
  local attachedItem = this.item
  local cursorItem = m.get_cursor_item()
  if m.sendmail_set_attachment( cursorItem, this ) then
    if attachedItem then
      if arg1 == "LeftButton" then m.set_cursor_item( attachedItem ) end
      m.orig.PickupContainerItem( unpack( attachedItem ) )
      if arg1 ~= "LeftButton" then m.api.ClearCursor() end -- for the lock changed event
    end
  end
end

-- ★把「记账里指向这一格」的条目全部清掉 —— **不动物品、不碰光标**。
--   用途（两处）：① 玩家左键把已挂载的物品拿走时同步记账（见 hook.PickupContainerItem）；
--   ② 附件格被点掉/物品被换走后的收尾。
function EHMailTM.sendmail_forget( bag, slot )
  local hit = false
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn.item and btn.item[ 1 ] == bag and btn.item[ 2 ] == slot then
      btn.item = nil
      hit = true
    end
  end
  if hit then m.sendmail_queue_update() end
end

function EHMailTM.sendmail_remove_attachment( item )
  if not item then return end
  if type( item ) == "table" and m.sendmail_attached( item[ 1 ], item[ 2 ] ) then
    for i = 1, ATTACHMENTS_MAX do
      local btn = m.api[ "MailAttachment" .. i ]
      if btn.item and btn.item[ 1 ] == item[ 1 ] and btn.item[ 2 ] == item[ 2 ] then
        m.api[ "MailAttachment" .. i ].item = nil
        m.orig.PickupContainerItem( unpack( item ) )
        m.api.ClearCursor()
        m.sendmail_queue_update()
        return
      end
    end
  end
end

-- requires an item lock changed event for a proper update
---@param item table
---@param slot number?
function EHMailTM.sendmail_set_attachment( item, slot )
  if item and not m.sendmail_pickup_mailable( item ) then
    m.api.ClearCursor()
    return
  elseif not slot then
    for i = 1, ATTACHMENTS_MAX do
      if not m.api[ "MailAttachment" .. i ].item then
        slot = m.api[ "MailAttachment" .. i ]
        break
      end
    end
  end
  if slot then
    if not (item or slot.item) then return true end
    slot.item = item
    m.api.ClearCursor()
    m.sendmail_queue_update()
    return true
  end
end

---@param item table
function EHMailTM.sendmail_pickup_mailable( item )
  -- 命中缓存直接放行：跳过"拿起→塞进邮寄槽→读回→取出"这串锁操作。
  -- 原写法每次右键都抛 4 次 ITEM_LOCK_CHANGED，pfUI/Guda 会跟着把全背包重扫 4 遍 = 卡顿来源
  local _, _, itemId = string.find( m.api.GetContainerItemLink( item[ 1 ], item[ 2 ] ) or "", "item:(%d+)" )
  if itemId and m.mailable[ itemId ] then return true end

  m.api.ClearCursor()
  -- 邮寄槽平时是空的，只有真有残留时才值得多花这一次锁操作
  if m.api.GetSendMailItem() then
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
  end
  m.orig.PickupContainerItem( unpack( item ) )
  m.orig.ClickSendMailItemButton()
  local mailable = m.api.GetSendMailItem() and true or false
  m.orig.ClickSendMailItemButton()
  -- 只缓存能邮的：绑定是实例级的，同 itemID 可能有的绑有的没绑
  if mailable and itemId then
    m.mailable[ itemId ] = true
  end
  return mailable
end

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
  local anyItem
  for i = 1, ATTACHMENTS_MAX do
    anyItem = anyItem or m.api[ "MailAttachment" .. i ].item
    m.api[ "MailAttachment" .. i ].item = nil
  end
  if anyItem then
    m.api.ClearCursor()
    -- 必须走原版：hook 版在 arg1 还是 "RightButton" 时会把物品重新挂回附件格
    m.orig.PickupContainerItem( unpack( anyItem ) )
    m.api.ClearCursor()
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
    -- ★★★挂件前先校验「那一格现在还有没有东西」：用户可能在批量进行中把物品拿走/换掉
    --   （记账只记 {bag,slot}、不记身份）⇒ 对着空位死重试毫无意义，还会把整批拖住
    --   （真机诊断「连试 4 次」）。校验不过 ⇒ **如实跳过这一件**、继续发后面的。
    if not m.api.GetContainerItemLink( item[ 1 ], item[ 2 ] ) then
      m.sendmail_skipped = ( m.sendmail_skipped or 0 ) + 1
      m.info( string.format( "  附件（包 %d / 格 %d）已不在原处 —— 跳过这一件", item[ 1 ], item[ 2 ] ) )
      m.sendmail_retry = 0
      m.sendmail_update = true
      return
    end
    m.api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
    m.orig.PickupContainerItem( unpack( item ) )
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

  if getn( m.sendmail_state.attachments ) == 0 then
    m.sendmail_sending = false
    if ( m.sendmail_skipped or 0 ) + ( m.sendmail_failed or 0 ) > 0 then
      m.info( string.format( "  本次共跳过 %d 件（拿不起来 %d ｜ 已不在原处 %d）",
        ( m.sendmail_skipped or 0 ) + ( m.sendmail_failed or 0 ),
        m.sendmail_failed or 0, m.sendmail_skipped or 0 ) )
      m.sendmail_skipped = nil
      m.sendmail_failed = nil
    end
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

function EHMailTM.log.load()
  m.api.EHMailTMLogTitleText:SetText( L[ "Log" ] )
  m.api.MailFrameTab3:SetText( L[ "Log" ] )

  local font_size = 11

  for i = 1, 10 do
    m.api[ "EHMailTMLogItem" .. i .. "Background" ]:SetVertexColor( .5, .5, .5, 0.6 )
    m.api[ "EHMailTMLogItem" .. i .. "TimeStamp" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "EHMailTMLogItem" .. i .. "TimeStamp" ]:SetJustifyH( "LEFT" )
    m.log.fontSet( m.api[ "EHMailTMLogItem" .. i .. "TimeStamp" ], font_size )
    m.api[ "EHMailTMLogItem" .. i .. "Participant" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "EHMailTMLogItem" .. i .. "Participant" ]:SetJustifyH( "RIGHT" )
    m.log.fontSet( m.api[ "EHMailTMLogItem" .. i .. "Participant" ], font_size )
    m.api[ "EHMailTMLogItem" .. i .. "Subject" ]:SetJustifyH( "LEFT" )
    m.log.fontSet( m.api[ "EHMailTMLogItem" .. i .. "Subject" ], font_size )
    m.api[ "EHMailTMLogItem" .. i .. "Money" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "EHMailTMLogItem" .. i .. "Money" ]:SetJustifyH( "LEFT" )
    m.log.fontSet( m.api[ "EHMailTMLogItem" .. i .. "Money" ], font_size )
    m.api[ "EHMailTMLogItem" .. i .. "Status" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    if i > 1 then
      m.api[ "EHMailTMLogItem" .. i ]:SetPoint( "TOPLEFT", m.api[ "EHMailTMLogItem" .. i - 1 ], "BOTTOMLEFT", 0, -1 )
    end
  end
  m.api.EHMailTMLogItem10Background:Hide()

  m.api.EHMailTMLogStatusText:SetTextColor( 1, 1, 1, 1 )
  m.api.EHMailTMLogStatusText:SetFont( "Fonts\\FRIZQT__.TTF", 10 )
  m.api.EHMailTMLogScrollFrameScrollBar:SetValueStep( 1 )
  m.api.EHMailTMLogScrollFrameScrollBar:SetScript( "OnValueChanged", m.log.on_scroll_value_changed )

  m.api.EHMailTMLogScrollFrame:SetScript( "OnMouseWheel", function()
    m.log.scroll( arg1 * 10 )
  end )
  m.api.EHMailTMLogScrollFrameScrollBarScrollUpButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( 10 )
  end )
  m.api.EHMailTMLogScrollFrameScrollBarScrollDownButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( -10 )
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

  m.api.EHMailTMLogScrollFrameScrollBar:SetMinMaxValues( 0, math.max( 0, log_count - 10 ) )

  if not index then
    m.api.EHMailTMLogScrollFrameScrollBar:SetValue( log_count - 10 )
    m.api.EHMailTMLogScrollFrameScrollBar:SetScript( "OnUpdate", function()
      m.api.EHMailTMLogScrollFrameScrollBar:SetValue( log_count - 10 )
      m.api.EHMailTMLogScrollFrameScrollBar:SetScript( "OnUpdate", nil )
    end )

    index = math.max( 0, log_count - 10 )
  end

  -- 标题显示当前日志类型（已收到/已发送）
  m.api.EHMailTMLogTitleText:SetText( string.format( "%s %s", L[ m.current_log_type ], L[ "Log" ] ) )
  m.api.EHMailTMLogStatusText:SetText( string.format( "显示%d-%d，总共%d", (index == 0 and log_count == 0) and index or index + 1,
  math.min( log_count, index + 10 ), log_count ) )

  for i = 1, 10 do
    if log[ index + i ] then
      local entry = log[ index + i ]

      m.api[ "EHMailTMLogItem" .. i .. "IconTexture" ]:SetTexture( entry.icon or "Interface/Icons/INV_Misc_Note_01" )
      m.api[ "EHMailTMLogItem" .. i .. "Icon" ].item = entry.item
      m.api[ "EHMailTMLogItem" .. i .. "TimeStamp" ]:SetText( m.format_datetime( entry.timestamp ) )

      local subj = entry.subject or ""
      if entry.item_name and entry.item_name ~= "" and not string.find( subj, entry.item_name, 1, true ) then
        subj = subj .. " - " .. entry.item_name
      end
      m.api[ "EHMailTMLogItem" .. i .. "Subject" ]:SetText( subj )

      -- 正文全文（含竞得邮件的花费金额）挂到整行 tooltip 上
      local row = m.api[ "EHMailTMLogItem" .. i ]
      row.entry = entry
      row:EnableMouse( true )
      row:SetScript( "OnEnter", function( self )
        local e = self.entry
        m.api.GameTooltip:ClearLines()
        m.api.GameTooltip:SetOwner( self, "ANCHOR_RIGHT" )
        if e.item_name and e.item_name ~= "" then
          m.api.GameTooltip:AddLine( e.item_name, "", 1, 1, 0 )
        end
        if e.subject and e.subject ~= "" then
          m.api.GameTooltip:AddLine( e.subject, "", 0.7, 0.7, 0.7 )
        end
        if e.money and e.money > 0 then
          m.api.GameTooltip:AddLine( L[ "Money received" ] .. ": " .. m.format_money( e.money ), "", 0, 1, 0 )
        end
        if e.cod and e.cod > 0 then
          m.api.GameTooltip:AddLine( L[ "COD" ] .. ": " .. m.format_money( e.cod ), "", 0, 1, 0 )
        end
        -- 正文里的物品链接/颜色码要剥掉，否则 tooltip 会显示成方块
        if e.body and e.body ~= "" then
          local body = string.gsub( e.body, "|c%x%x%x%x%x%x%x%x", "" )
          body = string.gsub( body, "|r", "" )
          body = string.gsub( body, "|H[^|]*|h", "" )
          body = string.gsub( body, "|h", "" )
          body = string.gsub( body, "%s+$", "" )
          if body ~= "" then
            m.api.GameTooltip:AddLine( "" )
            m.api.GameTooltip:AddLine( body, "", 1, 1, 1, true )
          end
        end
        m.api.GameTooltip:Show()
      end )
      row:SetScript( "OnLeave", function() m.api.GameTooltip:Hide() end )

      m.api[ "EHMailTMLogItem" .. i .. "Status" ]:SetTexture( "" )
      if entry.ah then
        m.api[ "EHMailTMLogItem" .. i .. "Participant" ]:SetText( "" )
        m.api[ "EHMailTMLogItem" .. i .. "Status" ]:SetTexture( "Interface\\AddOns\\EH_Mail\\EHMailTM-AH.blp" )
        m.api[ "EHMailTMLogItem" .. i .. "Status" ]:SetPoint( "TOPRIGHT", 4, -10 )
      else
        m.api[ "EHMailTMLogItem" .. i .. "Participant" ]:SetText( entry.participant )
      end
      if entry.returned then
        m.api[ "EHMailTMLogItem" .. i .. "Status" ]:SetTexture( "Interface\\AddOns\\EH_Mail\\EHMailTM-RetArrow.blp" )
        local w = m.api[ "EHMailTMLogItem" .. i .. "Participant" ]:GetStringWidth()
        m.api[ "EHMailTMLogItem" .. i .. "Status" ]:SetPoint( "TOPRIGHT", -w + 4, -9 )
      end

      if entry.money and entry.money > 0 then
        local cod = (entry.cod and entry.cod > 0) and "COD: " or " "
        m.api[ "EHMailTMLogItem" .. i .. "Money" ]:SetText( cod .. m.format_money( entry.money ) )
      elseif entry.cod then
        m.api[ "EHMailTMLogItem" .. i .. "Money" ]:SetText( "COD" .. (entry.cod > 1 and (": " .. m.format_money( entry.cod )) or "") )
      elseif entry.ah == "Won" then
        -- 竞得邮件：旧存档没存金额也解析不了（正文当时没落档），只能挂 tooltip 看原文
        m.api[ "EHMailTMLogItem" .. i .. "Money" ]:SetText( L[ "Pay" ] .. ": ?" )
      else
        m.api[ "EHMailTMLogItem" .. i .. "Money" ]:SetText( "" )
      end

      m.api[ "EHMailTMLogItem" .. i ]:Show();
    else
      m.api[ "EHMailTMLogItem" .. i ]:Hide();
    end
  end
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
  m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473EHMailTM|r: %s", message ) )
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

    m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473EHMailTM|r: %s", messages ) )
  end
end

EHMailTM:init()
