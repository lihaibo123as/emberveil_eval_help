EHMailTM = EHMailTM or {}

local L= {}
EHMailTM.L = L
setmetatable( L, { __index = function( _, key) return key end } );

L[ "collected" ] = nil
L[ "1st mail" ] = nil
L[ "each mail" ] = nil
L[ "Money received" ] = nil
L[ "All mails" ] = nil
L[ "This mail was returned to you." ] = nil
L[ "This mail was sent by an auctionhouse." ] = nil
L[ "Log" ] = nil
L[ "Received" ] = nil
L[ "Sent" ] = nil
L[ "Auction House" ] = nil
L[ "Returned" ] = nil
L[ "Help" ] = nil
L[ "Toggle logging on/off" ] = nil
L[ "Clear sent log" ] = nil
L[ "Clear received log" ] = nil
L[ "Clear saved recipient names from autocomplete" ] = nil
L[ "Could not attach %s (it is still on your cursor) - this mail was not sent" ] = nil
L[ "Could not attach %s - this mail was not sent" ] = nil
L[ "Unselect all" ] = nil
L[ "Select all tip" ] = nil
L[ "Filter menu unavailable" ] = nil
L[ "Logging is enabled." ] = nil
L[ "Logging is disabled." ] = nil
L[ "Logging is now off by default. Use /tm log to enable it." ] = nil
L[ "Sent log cleared." ] = nil
L[ "Received log cleared." ] = nil
L[ "AH" ] = "Auction House"
L[ "COD" ] = "C.O.D."
L[ "Money" ] = "Money Attached"
L[ "Players" ] = nil
L[ "date_format" ] = "%d.%m.%Y"
L[ "time_format" ] = "%H:%M"

-- ★0.3.13 附件框的信息引导 + 快速删除（用户定：「附件框内做好信息引导提示. 推荐直接在背包内完成邮件快速选择.
--   操作. 邮件附件快速删除操作.」）★这些是**短键**（不是「键 = 整句英文」那一族）⇒ 两种语言都必须给值，
--   否则 `__index` 兜底会把键名（`ATT_TIP_TITLE` 这种）画到屏幕上。
L[ "ATT_TIP_TITLE" ] = "Quick attachments"
L[ "ATT_TIP_BAG" ] = "Recommended: do it right in your bags - right-click an item to add it, right-click again to remove it, Alt+left-click adds every item of the same kind"
L[ "ATT_TIP_DRAG" ] = "You can also drag an item onto this row of slots and release: it is added to the list and that drag is cancelled automatically (the item goes back where it was)"
L[ "ATT_TIP_DEL" ] = "Remove one: click its slot below (left or right button both work) - only the list entry is removed, the item itself is never touched"
L[ "ATT_CLEAR_TIP" ] = "Clear the whole list: right-click the counter box"
L[ "ATT_TIP_SEND" ] = "When done, press [Send]: the items are attached and mailed one by one"
L[ "ATT_TIP_THIS" ] = "Click this slot = remove it from the list (the bag item is untouched)"
L[ "ATT_CLEARED" ] = "Attachment list cleared (%d entries) - nothing in your bags was touched"
L[ "ATT_CLEAR_EMPTY" ] = "The attachment list is already empty"

-- ★0.3.14 日志页 = **小图标方格聚合展示**（用户定：「已发送和已收到进行小图标方格聚合展示. 参考图标库的布局形式,
--   tooltip 信息提示是这个邮件的发件人.附件信息.金币等等, 然后点击这个日志图标可以快速切换到发件箱.
--   填充这个日志邮件的发件人操作.」）
L[ "LOG_STATUS" ] = "%d mails  |  showing %d-%d"
L[ "LOG_TIP_SENT" ] = "Sent to"
L[ "LOG_TIP_RECEIVED" ] = "Received from"
L[ "LOG_TIP_SUBJECT" ] = "Subject"
L[ "LOG_TIP_ITEM" ] = "Attachment"
L[ "LOG_TIP_MONEY" ] = "Money"
L[ "LOG_TIP_COD" ] = "C.O.D."
L[ "LOG_TIP_TIME" ] = "Time"
L[ "LOG_TIP_NONE" ] = "(none)"
L[ "LOG_TIP_LABEL_AH" ] = "Auction House"
L[ "LOG_TIP_LABEL_RETURNED" ] = "Returned"
L[ "LOG_TIP_LABEL_GM" ] = "GM"
L[ "LOG_TIP_EARNED" ] = "Money received"
L[ "LOG_TIP_PAID" ] = "Paid"
L[ "LOG_TIP_CLICK" ] = "Click = open the send page and fill \"%s\" in as the recipient"
L[ "LOG_TIP_CLICK_NONE" ] = "Click = open the send page (this one has no counterpart to fill in)"
L[ "LOG_FILL_OK" ] = "Switched to the send page; recipient filled as \"%s\" (that mail was %s)"
L[ "LOG_FILL_NONE" ] = "Switched to the send page - this mail has no counterpart to fill in"
L[ "LOG_FILL_FAIL" ] = "Could not fill \"%s\" into the recipient box"
L[ "LOG_TIP_HINT" ] = "Hover an icon for that mail's details"

-- ★0.3.15 关邮箱 = 附件选择整体作废（用户定：「在邮箱关闭之后. 要做好背包内附件锁定清理的流程.」）
L[ "REL_CLOSED" ] = "Mailbox closed: cleared %d selected attachment(s), nothing in your bags was touched"