-- 由Sunelegy基于乌龟魔兽版本定制
if(GetLocale()=="zhCN") then
	MAILTO_TOOLTIP =    "点击选择收件人";
	MAILTO_LISTFULL =   "警告:收件人列表已满";
	MAILTO_ADDED =      "添加到收件人列表";
	MAILTO_REMOVED =    "从收件人列表中移除";
	MAILTO_F_ADD =      "(添加 %s)";
	MAILTO_F_REMOVE =   "(移除 %s)";
else
	MAILTO_TOOLTIP =    "Click to select recipient."
	MAILTO_LISTFULL =   "Warning: List is full!"
	MAILTO_ADDED =      " added to MailTo list."
	MAILTO_REMOVED =    " removed from MailTo list."
	MAILTO_F_ADD =      "(Add %s)"
	MAILTO_F_REMOVE =   "(Remove %s)"
end

local MailTo_Selected, MailTo_Name, MailTo_SavedName, Server
-- ★移植适配：原版无条件清空 ⇒ 会把已恢复的存档（收件人历史）当场覆盖掉。
-- 改成「没存档才建」：两种 SavedVariables 时机下都正确。
EHMailTM_MailToList = EHMailTM_MailToList or {}

-- 选择收件人
function MailTo_ListSelect()
    local value = this.value
    if value then
      MailTo_SavedName = EHMailTM_MailToList[Server][value]
      _G.Mail_To = nil  -- 清空 Mail_To 变量
      SendMailNameEditBox:SetText(MailTo_SavedName)
      SendMailNameEditBox:HighlightText(0, -1)
      SendMailSubjectEditBox:SetFocus()
    end
end

-- 增加收件人
function MailTo_ListAdd(name)
    if not name then name = MailTo_Name end
    -- ★★★0.3.3 取证（收件人历史「添加成功、/reload 后没了」）：先把三件事打出来 ——
    --   ① 这张表**是不是存档表**（必须等于 `EH_MAIL_CHAR.tm_mailToList`；不是 ⇒ 写进了孤儿表，永远不落盘）
    --   ② 服务器桶键 ③ 桶里现有几项。用户截图即可定案。
    print( "|cff00FAFA[EH_Mail] 收件人表==存档表? " .. tostring( EHMailTM_MailToList == _G.EH_MAIL_CFG.tm_mailToList )
        .. " ｜ 服务器=" .. tostring( Server ) .. " ｜ 桶内=" .. tostring( EHMailTM_MailToList[ Server ] and table.getn( EHMailTM_MailToList[ Server ] ) ) )
    tinsert(EHMailTM_MailToList[Server], name)
    sort(EHMailTM_MailToList[Server])
    print("|cff00FAFA"..name..MAILTO_ADDED)
end

-- 移除收件人
function MailTo_ListRemove()
    tremove(EHMailTM_MailToList[Server], MailTo_Selected)
    print("|cff00FAFA"..MailTo_Name..MAILTO_REMOVED)
end

-- 获取收件人姓名
function MailTo_InList(MCname)
    local LCname = string.lower(MCname)
    for key, name in EHMailTM_MailToList[Server] do
      if LCname == string.lower(name) then return key end
    end
end

-- 下拉菜单
function MailTo_ToList_Init()
    -- ★0.3.3：桶缺失时自愈（OnEvent 万一没跑到，原来这里会直接索引 nil 报错、下拉里一项都没有）
    if Server and type( EHMailTM_MailToList[ Server ] ) ~= "table" then
      EHMailTM_MailToList[ Server ] = {}
    end
    local info = {value = 0, notCheckable = 1}
    MailTo_Name = SendMailNameEditBox:GetText()
    if MailTo_Name ~= "" then
		MailTo_Selected = MailTo_InList(MailTo_Name)
		if MailTo_Selected then
			info.text = string.format(MAILTO_F_REMOVE, MailTo_Name)
			info.func = MailTo_ListRemove
		elseif table.getn(EHMailTM_MailToList[Server]) < UIDROPDOWNMENU_MAXBUTTONS then
			info.text = string.format(MAILTO_F_ADD, MailTo_Name)
			info.func = MailTo_ListAdd
		else
			info = nil
			print("|cffff4040"..MAILTO_LISTFULL)
		end
		if info then UIDropDownMenu_AddButton(info) end
    end
    for key, name in EHMailTM_MailToList[Server] do
      info = {text = name, value = key, func = MailTo_ListSelect}
      if key == MailTo_Selected then info.checked = 1 end
      UIDropDownMenu_AddButton(info)
    end
end

-- ★★★0.3.3：把「建菜单」抽成幂等的 ensure —— OnClick 与 OnShow 都先过它。
--   ① parent 明确给箭头按钮自己（不再用 this：本客户端处理体参数走全局 arg1，this 不保证）；
--   ② 拿不到就返回 nil，调用方如实报一声（绝不静默）。
function MailTo_MenuEnsure()
	if S_MailTo_Menu then return S_MailTo_Menu end
	S_MailTo_Menu = CreateFrame("Button", "S_MailTo_Menu", MailToDropDownMenu, "UIDropDownMenuTemplate")
	if not S_MailTo_Menu then return nil end
	S_MailTo_Menu:Hide()
	UIDropDownMenu_Initialize(S_MailTo_Menu, MailTo_ToList_Init, "MENU")
	return S_MailTo_Menu
end

--创建下拉按钮
local MailToDropDownMenu = CreateFrame("Button", "MailToDropDownMenu", SendMailNameEditBox)
    local xOffset
    -- ★移植适配：原本这里按有无 pfUI 取不同偏移；本版无 pfUI ⇒ 只保留原版值
    xOffset = -10
MailToDropDownMenu:Show()
MailToDropDownMenu:SetWidth(24)
MailToDropDownMenu:SetHeight(24)
MailToDropDownMenu:SetPoint("RIGHT", SendMailNameEditBox, "RIGHT", xOffset, 0)
MailToDropDownMenu:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
MailToDropDownMenu:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
MailToDropDownMenu:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

MailToDropDownMenu:SetScript("OnShow", function()
	MailTo_MenuEnsure()
end)

MailToDropDownMenu:SetScript("OnHide", function()
	CloseDropDownMenus()
end)

MailToDropDownMenu:SetScript("OnClick", function()
	-- ★★★0.3.3 真机报障「下拉没放在收件人名称下方」：
	--   本客户端 UIDropDownMenu.lua **只在「不传 anchorName」时**才读 dropDownFrame 的
	--   point / relativeTo / relativePoint（该文件 555~573 行），而那一支里 relativeTo 用的是
	--   **帧名字符串**（569 行自己拼 UIDROPDOWNMENU_OPEN_MENU.."Left"）—— 我们原先塞的是帧对象，位置自然不对。
	--   ⇒ 改走 anchorName 那一支（588~589 行）：relativeTo = anchorName，位置取默认
	--   TOPLEFT 贴 BOTTOMLEFT ⇒ **正好落在收件人输入框正下方、左对齐**（用户要的位置）。
	--   ★ 那 5 个位置字段已删：传了 anchorName 时它们一个都不生效，留着只会误导。
	local menu = MailTo_MenuEnsure()
	if not menu then
		print("|cffff4040EHMailTM: 收件人下拉建不出来（UIDropDownMenuTemplate 拿不到）|r")
		return
	end
	if SendMailNameEditBox then
		ToggleDropDownMenu(nil, nil, menu, "SendMailNameEditBox", 0, 0)
	else
		ToggleDropDownMenu(nil, nil, menu)
	end
	PlaySound("igMainMenuOptionCheckBoxOn")
end)

MailToDropDownMenu:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this,"ANCHOR_TOPRIGHT")
	GameTooltip:SetText(MAILTO_TOOLTIP)
	GameTooltip:Show()
end)

MailToDropDownMenu:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

MailToDropDownMenu:RegisterEvent("VARIABLES_LOADED");
MailToDropDownMenu:SetScript("OnEvent", function()
    Server = GetRealmName()

    if not EHMailTM_MailToList[Server] then
		EHMailTM_MailToList[Server]={}
	end

    MailToDropDownMenu.displayMode = "MENU"
end)