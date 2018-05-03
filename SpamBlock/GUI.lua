local guiFrame = CreateFrame("frame", "SpamBlockGUI", UIParent)

----------------------------------------------------------------------------------------------------
-- helper functions
----------------------------------------------------------------------------------------------------
--------------------------------------------------
-- convert edit box text into a proper filter list
--------------------------------------------------
local find = string.find
local function SetFilterList(filter_table, raw_text, normalize)
	for i=1,#filter_table do
		filter_table[i] = nil
	end
	local text
	local GetMatchMessage = _G["SpamBlockFrame"].GetMatchMessage
	for line in string.gmatch(raw_text, "[^\r\n]+") do
		if not find(line, "^:") then
			text = GetMatchMessage(line, normalize)
			if not normalize then
				text = text:gsub("[%(%)%.%%%+%-%*%?%[%^%$]", "%%%1") -- escape special characters
			end
			if text ~= "" then
				filter_table[#filter_table+1] = text
			end
		else
			filter_table[#filter_table+1] = line:sub(2):gsub("||","|"):gsub("\\(%d+)", function(value) return string.char(value) end)
		end
	end
end

--------------------------------------------------
-- convert edit box text into a table of names
--------------------------------------------------
local function SetFilterNameList(filter_table, raw_text)
	for n in pairs(filter_table) do
		filter_table[n] = nil
	end
	for line in string.gmatch(raw_text, "[^\r\n]+") do
		filter_table[line:lower()] = true
	end
end

-- convert all block and allow raw text in every chat setting into a list of proper filters
local function SetAllFilterLists()
	for _,settings in pairs(SpamBlockSave.channel) do
		SetFilterList(settings[4], settings[2], settings[6]) -- allow filters
		SetFilterList(settings[5], settings[3], settings[6]) -- block filters
	end
end

--------------------------------------------------
-- for showing tooltips
--------------------------------------------------
function WidgetTooltip_OnEnter()
	GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
	GameTooltip:SetText(this.tooltipText, nil, nil, nil, nil, 1)
	GameTooltip:Show()
end
function WidgetTooltip_OnLeave()
	GameTooltip:Hide()
end

--------------------------------------------------
-- return a checkbox widget
--------------------------------------------------
local function CreateCheckbox(name, text, tooltip)
	local frame = CreateFrame("CheckButton", "SpamBlock_Checkbox_"..name, guiFrame, "OptionsCheckButtonTemplate")
	_G[frame:GetName().."Text"]:SetText(text)
	local width = _G[frame:GetName().."Text"]:GetStringWidth()
	frame:SetHitRectInsets(0, -width, 4, 4)
	frame.tooltipText = tooltip
	return frame
end

----------------------------------------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------------------------------------
--------------------------------------------------
-- main window
--------------------------------------------------
table.insert(UISpecialFrames, guiFrame:GetName()) -- make it closable with escape key
guiFrame:SetFrameStrata("HIGH")
guiFrame:SetBackdrop({
	bgFile="Interface/Tooltips/UI-Tooltip-Background",
	edgeFile="Interface/DialogFrame/UI-DialogBox-Border",
	tile=1, tileSize=32, edgeSize=32,
	insets={left=11, right=12, top=12, bottom=11}
})
guiFrame:SetBackdropColor(0,0,0,1)
guiFrame:SetPoint("CENTER")
guiFrame:SetWidth(680)
guiFrame:SetHeight(600)
guiFrame:SetMovable(true)
guiFrame:EnableMouse(true)
guiFrame:RegisterForDrag("LeftButton")
guiFrame:SetScript("OnDragStart", guiFrame.StartMoving)
guiFrame:SetScript("OnDragStop", guiFrame.StopMovingOrSizing)
guiFrame:SetScript("OnMouseDown", function(self, button)
	if button == "LeftButton" and not self.isMoving then
		self:StartMoving()
		self.isMoving = true
	end
end)
guiFrame:SetScript("OnMouseUp", function(self, button)
	if button == "LeftButton" and self.isMoving then
		self:StopMovingOrSizing()
		self.isMoving = false
	end
end)
guiFrame:SetScript("OnHide", function(self)
	if self.isMoving then
		self:StopMovingOrSizing()
		self.isMoving = false
	end
end)

--------------------------------------------------
-- header title
--------------------------------------------------
local textureHeader = guiFrame:CreateTexture(nil, "ARTWORK")
textureHeader:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
textureHeader:SetWidth(315)
textureHeader:SetHeight(64)
textureHeader:SetPoint("TOP", 0, 12)
local textHeader = guiFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
textHeader:SetPoint("TOP", textureHeader, "TOP", 0, -14)
textHeader:SetText("SpamBlock 2.6")

--------------------------------------------------
-- duplicate filter checkboxes - left
--------------------------------------------------
-- Header
local textDuplicateHeader = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
textDuplicateHeader:SetPoint("TOP", guiFrame, "TOP", 0, -32) -- horizontally aligned after editbox
textDuplicateHeader:SetText("Blocking Duplicates")

-- General channel
local checkboxGeneral = CreateCheckbox("General", "|cffff0000General|r")
checkboxGeneral:SetPoint("TOP", guiFrame, "TOP", 0, -36 - textDuplicateHeader:GetHeight())
checkboxGeneral:SetScript("OnClick", function() SpamBlockSave.channel["GENERAL"][1] = this:GetChecked() or false end)

-- Defense
local checkboxDefense = CreateCheckbox("Defense", "|cffff0000Defense|r")
checkboxDefense:SetPoint("TOPLEFT", checkboxGeneral, "BOTTOMLEFT", 0, 8)
checkboxDefense:SetScript("OnClick", function() SpamBlockSave.channel["DEFENSE"][1] = this:GetChecked() or false end)

-- Recruitment
local checkboxRecruitment = CreateCheckbox("Recruitment", "|cffff0000Recruitment|r")
checkboxRecruitment:SetPoint("TOPLEFT", checkboxDefense, "BOTTOMLEFT", 0, 8)
checkboxRecruitment:SetScript("OnClick", function() SpamBlockSave.channel["GUILDRECRUITMENT"][1] = this:GetChecked() or false end)

-- Tradeskills
local checkboxTradeskills = CreateCheckbox("Tradeskills", "|cffff0000Tradeskills|r")
checkboxTradeskills:SetPoint("TOPLEFT", checkboxRecruitment, "BOTTOMLEFT", 0, 8)
checkboxTradeskills:SetScript("OnClick", function() SpamBlockSave.channel["CHAT_MSG_TRADESKILLS"][1] = this:GetChecked() or false end)

-- edit time
local textDuplicateNoisy = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
textDuplicateNoisy:SetPoint("TOPLEFT", checkboxTradeskills, "BOTTOMLEFT", 4, 0)
textDuplicateNoisy:SetText("|cffff0000Block time for these:|r")

local editboxDuplicateNoisy = CreateFrame("EditBox", "SSSB_EditDuplicatePrivate", guiFrame, "InputBoxTemplate")
editboxDuplicateNoisy:SetWidth(32)
editboxDuplicateNoisy:SetHeight(12)
editboxDuplicateNoisy:SetPoint("LEFT", textDuplicateNoisy, "RIGHT", 10, 0)
editboxDuplicateNoisy:SetNumeric(true)
editboxDuplicateNoisy:SetMaxLetters(4)
editboxDuplicateNoisy:SetAutoFocus(false)
editboxDuplicateNoisy:SetScript("OnEnterPressed", function() this:ClearFocus() end)
editboxDuplicateNoisy:SetScript("OnEditFocusLost", function()
	local time = tonumber(editboxDuplicateNoisy:GetText())
	if not time or time < 1 then
		time = 60
		editboxDuplicateNoisy:SetText("60")
	end
	SpamBlockSave.blockTime[1] = time
end)
editboxDuplicateNoisy.tooltipText = "Block duplicate messages from these red channels for this many seconds."
editboxDuplicateNoisy:SetScript("OnEnter", WidgetTooltip_OnEnter)
editboxDuplicateNoisy:SetScript("OnLeave", WidgetTooltip_OnLeave)

-- position widgets and center header above it
local duplicatesWidth = (editboxDuplicateNoisy:GetRight()-textDuplicateNoisy:GetLeft())
checkboxGeneral:SetPoint("RIGHT", guiFrame, "RIGHT", -duplicatesWidth, 0)
textDuplicateHeader:SetPoint("LEFT", textDuplicateNoisy, "LEFT", (duplicatesWidth/2) - (textDuplicateHeader:GetWidth()/2), 0)

-- Guild
local checkboxGuild = CreateCheckbox("Guild", "|cff00ff00Guild|r")
checkboxGuild:SetPoint("TOP", textDuplicateNoisy, "BOTTOM", 0, -10)
checkboxGuild:SetPoint("LEFT", checkboxGeneral, "LEFT", 0, 0)
checkboxGuild:SetScript("OnClick", function() SpamBlockSave.channel["CHAT_MSG_GUILD"][1] = this:GetChecked() or false end)

-- Battleground
local checkboxBattleground = CreateCheckbox("Battleground", "|cff00ff00Battleground|r")
checkboxBattleground:SetPoint("TOPLEFT", checkboxGuild, "BOTTOMLEFT", 0, 8)
checkboxBattleground:SetScript("OnClick", function() SpamBlockSave.channel["CHAT_MSG_BATTLEGROUND"][1] = this:GetChecked() or false end)

-- Whispered
local checkboxWhisper = CreateCheckbox("Whispered", "|cff00ff00Whispered|r")
checkboxWhisper:SetPoint("TOPLEFT", checkboxBattleground, "BOTTOMLEFT", 0, 8)
checkboxWhisper:SetScript("OnClick", function() SpamBlockSave.channel["CHAT_MSG_WHISPER"][1] = this:GetChecked() or false end)

-- Whisper Inform
local checkboxWhisperInform = CreateCheckbox("Whispering", "|cff00ff00Whispering|r")
checkboxWhisperInform:SetPoint("TOPLEFT", checkboxWhisper, "BOTTOMLEFT", 0, 8)
checkboxWhisperInform:SetScript("OnClick", function() SpamBlockSave.channel["CHAT_MSG_WHISPER_INFORM"][1] = this:GetChecked() or false end)

-- edit time
local textDuplicateOther = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
textDuplicateOther:SetPoint("TOPLEFT", checkboxWhisperInform, "BOTTOMLEFT", 4, 0)
textDuplicateOther:SetText("|cff00ff00Block time for these:|r")

local editboxDuplicateOther = CreateFrame("EditBox", "SSSB_EditDuplicatePublic", guiFrame, "InputBoxTemplate")
editboxDuplicateOther:SetWidth(32)
editboxDuplicateOther:SetHeight(12)
editboxDuplicateOther:SetPoint("LEFT", textDuplicateOther, "RIGHT", 10, 0)
editboxDuplicateOther:SetNumeric(true)
editboxDuplicateOther:SetMaxLetters(4)
editboxDuplicateOther:SetAutoFocus(false)
editboxDuplicateOther:SetScript("OnEnterPressed", function() this:ClearFocus() end)
editboxDuplicateOther:SetScript("OnEditFocusLost", function()
	local time = tonumber(editboxDuplicateOther:GetText())
	if not time or time < 1 then
		time = 2
		editboxDuplicateOther:SetText("2")
	end
	SpamBlockSave.blockTime[2] = time
end)
editboxDuplicateOther.tooltipText = "Block duplicate messages from these green channels for this many seconds."
editboxDuplicateOther:SetScript("OnEnter", WidgetTooltip_OnEnter)
editboxDuplicateOther:SetScript("OnLeave", WidgetTooltip_OnLeave)

--------------------------------------------------
-- duplicate filter checkboxes - right
--------------------------------------------------
-- Trade
local checkboxTrade = CreateCheckbox("Trade", "|cffff0000Trade|r")
checkboxTrade:SetPoint("TOPLEFT", checkboxGeneral, "TOPRIGHT", 70, 0)
checkboxTrade:SetScript("OnClick", function() SpamBlockSave.channel["TRADE"][1] = this:GetChecked() or false end)

-- LFG
local checkboxLFG = CreateCheckbox("LFG", "|cffff0000LFG|r")
checkboxLFG:SetPoint("TOPLEFT", checkboxTrade, "BOTTOMLEFT", 0, 8)
checkboxLFG:SetScript("OnClick", function() SpamBlockSave.channel["LOOKINGFORGROUP"][1] = this:GetChecked() or false end)

-- Custom
local checkboxCustom = CreateCheckbox("Custom", "|cffff0000Custom|r")
checkboxCustom:SetPoint("TOPLEFT", checkboxLFG, "BOTTOMLEFT", 0, 8)
checkboxCustom:SetScript("OnClick", function() SpamBlockSave.channel["CUSTOM"][1] = this:GetChecked() or false end)

-- Yell
local checkboxYell = CreateCheckbox("Yell", "|cffff0000Yell|r")
checkboxYell:SetPoint("TOPLEFT", checkboxCustom, "BOTTOMLEFT", 0, 8)
checkboxYell:SetScript("OnClick", function() SpamBlockSave.channel["CHAT_MSG_YELL"][1] = this:GetChecked() or false end)

-- Say
local checkboxSay = CreateCheckbox("Say", "|cff00ff00Say|r")
checkboxSay:SetPoint("TOPLEFT", checkboxGuild, "TOPRIGHT", 70, 0)
checkboxSay:SetScript("OnClick", function() SpamBlockSave.channel["CHAT_MSG_SAY"][1] = this:GetChecked() or false end)

-- Party
local checkboxParty = CreateCheckbox("Party", "|cff00ff00Party|r")
checkboxParty:SetPoint("TOPLEFT", checkboxSay, "BOTTOMLEFT", 0, 8)
checkboxParty:SetScript("OnClick", function() SpamBlockSave.channel["CHAT_MSG_PARTY"][1] = this:GetChecked() or false end)

-- Raid
local checkboxRaid = CreateCheckbox("Raid", "|cff00ff00Raid|r")
checkboxRaid:SetPoint("TOPLEFT", checkboxParty, "BOTTOMLEFT", 0, 8)
checkboxRaid:SetScript("OnClick", function() SpamBlockSave.channel["CHAT_MSG_RAID"][1] = this:GetChecked() or false end)

-- Emote
local checkboxEmote = CreateCheckbox("Emote", "|cff00ff00Emote|r")
checkboxEmote:SetPoint("TOPLEFT", checkboxRaid, "BOTTOMLEFT", 0, 8)
checkboxEmote:SetScript("OnClick", function()
	SpamBlockSave.channel["CHAT_MSG_EMOTE"][1] = this:GetChecked() or false
	SpamBlockSave.channel["CHAT_MSG_TEXT_EMOTE"][1] = SpamBlockSave.channel["CHAT_MSG_EMOTE"][1]
end)

--------------------------------------------------
-- special filter options
--------------------------------------------------
-- Header
local textFilterOptions = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
textFilterOptions:SetPoint("TOP", guiFrame, "TOP", 0, -32) -- horizontally aligned at the end
textFilterOptions:SetText("Filtering Options")

-- Test Mode
local checkboxTestMode = CreateCheckbox("TestMode", "|cffffffffTest mode - show blocks|r",
	"Messages that would normally be hidden will have |cffff0000[Spam]|r in front of them.")
checkboxTestMode:SetPoint("TOP", checkboxTrade, "TOP", 0, 0)
checkboxTestMode:SetPoint("LEFT", guiFrame, "LEFT", 16, 0)
checkboxTestMode:SetScript("OnClick", function() SpamBlockSave.filterTestMode = this:GetChecked() or false end)

-- Yourself
local checkboxYourself = CreateCheckbox("Yourself", "|cffffffffFilter your messages too|r",
	"Normally your own messages are never blocked, but if you're a spammer then you can enable this so that they are.")
checkboxYourself:SetPoint("TOPLEFT", checkboxTestMode, "BOTTOMLEFT", 0, 8)
checkboxYourself:SetScript("OnClick", function() SpamBlockSave.filterSelf = this:GetChecked() or false end)

-- Numbers
local checkboxNumbers = CreateCheckbox("Numbers", "|cffffffffIgnore number differences|r",
	'"LFM 3 DPS" and "LFM 2 DPS" would count as the same message.')
checkboxNumbers:SetPoint("TOPLEFT", checkboxYourself, "BOTTOMLEFT", 0, 8)
checkboxNumbers:SetScript("OnClick", function()
	SpamBlockSave.filterNumbers = this:GetChecked() or false
	_G["SpamBlockFrame"].UpdateLocalCopies()
	SetAllFilterLists()
end)

-- Shattrath Language
local checkboxShattrathLanguage = CreateCheckbox("Languages", "|cffffffffBlock unknown languages|r",
	"Block messages using game languages you can't understand, but only while in sanctuary areas like Shattrath.")
checkboxShattrathLanguage:SetPoint("TOPLEFT", checkboxNumbers, "BOTTOMLEFT", 0, 8)
checkboxShattrathLanguage:SetScript("OnClick", function()
	SpamBlockSave.filterShattrathLanguage = this:GetChecked() or false
	_G["SpamBlockFrame"].UpdateLocalCopies()
end)

-- CLINK fix
local checkboxClinkFix = CreateCheckbox("Clink", "|cffffffffFix CLINK links|r",
	"Some people use addons that change item/spell links to be like {CLINK:something} because links were blocked on retail. This changes those back to normal links.")
checkboxClinkFix:SetPoint("TOPLEFT", checkboxShattrathLanguage, "BOTTOMLEFT", 0, 8)
checkboxClinkFix:SetScript("OnClick", function()
	SpamBlockSave.filterClinkFix = this:GetChecked() or false
	_G["SpamBlockFrame"].UpdateLocalCopies()
end)

-- Raid target icons
local checkboxRaidIcons = CreateCheckbox("Icons", "|cffffffffRemove icons in channels|r",
	"They're only removed in numbered channels, so you'll still see them in raid/yell/etc.")
checkboxRaidIcons:SetPoint("TOPLEFT", checkboxClinkFix, "BOTTOMLEFT", 0, 8)
checkboxRaidIcons:SetScript("OnClick", function()
	SpamBlockSave.filterRaidIcons = this:GetChecked() or false
	_G["SpamBlockFrame"].UpdateLocalCopies()
end)

-- Translate links
local checkboxTranslateLinks = CreateCheckbox("Translate", "|cffffffffTranslate spell/craft links|r",
	"Prefixes (like \"Alchemy:\") won't be translated.")
checkboxTranslateLinks:SetPoint("TOPLEFT", checkboxRaidIcons, "BOTTOMLEFT", 0, 8)
checkboxTranslateLinks:SetScript("OnClick", function()
	SpamBlockSave.filterTranslateLinks = this:GetChecked() or false
	_G["SpamBlockFrame"].UpdateLocalCopies()
end)

-- Continue blocking for a second
local checkboxExtraSecond = CreateCheckbox("ExtraSecond", "|cffffffffBlock for an extra second|r",
	"This continues blocking someone for a second after their message matches something on a block list. This is for cases where they send multiple messages about the same thing at once (like a 3 message long guild ad) causing only the first to get blocked. Duplicate messages and emote actions don't trigger it.")
checkboxExtraSecond:SetPoint("TOPLEFT", checkboxTranslateLinks, "BOTTOMLEFT", 0, 8)
checkboxExtraSecond:SetScript("OnClick", function()
	SpamBlockSave.filterExtraSecond = this:GetChecked() or false
	_G["SpamBlockFrame"].UpdateLocalCopies()
end)

-- Block channel invites
local checkboxChannelInvites = CreateCheckbox("ChannelInvites", "|cffffffffBlock channel invites from strangers|r",
	"This will block channel invitations from people that aren't friends, guild members, or in your group.")
checkboxChannelInvites:SetPoint("TOPLEFT", checkboxExtraSecond, "BOTTOMLEFT", 0, 8)
checkboxChannelInvites:SetScript("OnClick", function() SpamBlockSave.filterChannelInvites = this:GetChecked() or false end)

textFilterOptions:SetPoint("LEFT", checkboxNumbers, "LEFT",
	((checkboxNumbers:GetWidth() + _G[checkboxNumbers:GetName().."Text"]:GetWidth())/2) - (textFilterOptions:GetWidth()/2) + 4, 0)

--------------------------------------------------
-- Stats
--------------------------------------------------
-- Total Header
local textTotalHeader = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
textTotalHeader:SetPoint("TOP", guiFrame, "TOP", 0, -32)
textTotalHeader:SetText("Total Statistics")

-- Total stats left
local textTotalStatsLeft = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
textTotalStatsLeft:SetTextColor(.9, .9, .9)
textTotalStatsLeft:SetPoint("TOP", textTotalHeader, "BOTTOM", -45, -8)
textTotalStatsLeft:SetJustifyH("LEFT")
textTotalStatsLeft:SetText("Allowed:\nBlocked:\nSpam:")

-- Total stats right
local textTotalStatsRight = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
textTotalStatsRight:SetTextColor(.9, .9, .9)
textTotalStatsRight:SetPoint("TOP", textTotalHeader, "BOTTOM", 45, -8)
textTotalStatsRight:SetJustifyH("RIGHT")
textTotalStatsRight:SetText("2910\n329\n19.281%")

-- Session Header
local textSessionHeader = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
textSessionHeader:SetPoint("TOP", textTotalHeader, "TOP", 0, -90)
textSessionHeader:SetText("Session Statistics")

-- Session stats left
local textSessionStatsLeft = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
textSessionStatsLeft:SetTextColor(.9, .9, .9)
textSessionStatsLeft:SetPoint("TOP", textSessionHeader, "BOTTOM", -45, -8)
textSessionStatsLeft:SetJustifyH("LEFT")
textSessionStatsLeft:SetText("Allowed:\nBlocked:\nSpam:")

-- Session stats right
local textSessionStatsRight = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
textSessionStatsRight:SetTextColor(.9, .9, .9)
textSessionStatsRight:SetPoint("TOP", textSessionHeader, "BOTTOM", 45, -8)
textSessionStatsRight:SetJustifyH("RIGHT")
textSessionStatsRight:SetText("355\n71\n5.184%")

--------------------------------------------------
-- separator line
--------------------------------------------------
local separatorLine = guiFrame:CreateTexture()
separatorLine:SetTexture(.4, .4, .4)
separatorLine:SetWidth(guiFrame:GetWidth()-32)
separatorLine:SetHeight(2)
separatorLine:SetPoint("TOP", guiFrame, "TOP", 0, 0-(guiFrame:GetTop()-textDuplicateOther:GetBottom())-12)

--------------------------------------------------
-- dropdown menu - its functions are set up below edit boxes
--------------------------------------------------
local dropdownMenu = CreateFrame("Frame", "SSSB_dropdownMenu", guiFrame, "UIDropDownMenuTemplate")
dropdownMenu:SetPoint("TOPLEFT", separatorLine, "BOTTOMLEFT", -16, -8)
UIDropDownMenu_SetWidth(180, dropdownMenu)

local checkboxNormalization = CreateCheckbox("Normalization", "|cffffffffNormalize these messages|r",
	'If checked, messages here will have spaces, punctuation, target icons like {skull}, and "...hic!" removed, and "sh" changed to "s" to remove drunk slurs. Normal lines that you add to the block and allow lists will be automatically converted, so you don\'t have to remove spaces or anything yourself.')
checkboxNormalization:SetPoint("LEFT", dropdownMenu, "RIGHT", -12, 1)

local dropdownMenuInfo = {
--  Dropdown name                 name in SpamBlockSave.channel[name]
	{"All",                        "ALL"},
	{"Special: Names",             "NAMES"},
	{"Channels: All",              "CHAT_MSG_CHANNEL"},
	{"Channels: Custom",           "CUSTOM"},
	{"Channels: Defense",          "DEFENSE"},
	{"Channels: General",          "GENERAL"},
	{"Channels: GuildRecruitment", "GUILDRECRUITMENT"},
	{"Channels: LookingForGroup",  "LOOKINGFORGROUP"},
	{"Channels: Trade",            "TRADE"},
	{"Battleground",               "CHAT_MSG_BATTLEGROUND"},
	{"Emote",                      "CHAT_MSG_EMOTE"},
	{"Emote Action (like /bow)",   "CHAT_MSG_TEXT_EMOTE"},
	{"Guild",                      "CHAT_MSG_GUILD"},
	{"NPCs",                       "CHAT_MSG_MONSTER_SAY"},
	{"Party",                      "CHAT_MSG_PARTY"},
	{"Raid",                       "CHAT_MSG_RAID"},
	{"Say",                        "CHAT_MSG_SAY"},
	{"System",                     "CHAT_MSG_SYSTEM"},
	{"Tradeskills",                "CHAT_MSG_TRADESKILLS"},
	{"Whisper (incoming)",         "CHAT_MSG_WHISPER"},
	{"Whisper (outgoing)",         "CHAT_MSG_WHISPER_INFORM"},
	{"Yell",                       "CHAT_MSG_YELL"},
}

--------------------------------------------------
-- edit box - block messages
--------------------------------------------------
local editboxBlock = CreateFrame("Frame", "SSSB_EditBlock", guiFrame)
local editboxBlockInput = CreateFrame("EditBox", "SSSB_EditBlockInput", editboxBlock)
local editboxBlockScroll = CreateFrame("ScrollFrame", "SSSB_EditBlockScroll", editboxBlock, "UIPanelScrollFrameTemplate")

-- header
local textBlockContaining = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
textBlockContaining:SetPoint("LEFT", guiFrame, "LEFT", 16, 0)
textBlockContaining:SetPoint("TOP", dropdownMenu, "BOTTOM", 0, -6)

-- editboxBlock - main container
editboxBlock:SetPoint("TOPLEFT", textBlockContaining, "BOTTOMLEFT", 0, -3)
editboxBlock:SetPoint("BOTTOM", guiFrame, "BOTTOM", 0, 12)
editboxBlock:SetWidth((guiFrame:GetWidth() / 2) - 42)
editboxBlock:SetBackdrop({
	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
	tile=1, tileSize=32, edgeSize=16,
	insets={left=5, right=5, top=5, bottom=5}})
editboxBlock:SetBackdropColor(0,0,0,1)

-- editboxBlockInput
editboxBlockInput:SetMultiLine(true)
editboxBlockInput:SetAutoFocus(false)
editboxBlockInput:EnableMouse(true)
editboxBlockInput:SetFont("Fonts/ARIALN.ttf", 14)
editboxBlockInput:SetWidth(editboxBlock:GetWidth()-20)
editboxBlockInput:SetHeight(editboxBlock:GetHeight()-8)
editboxBlockInput:SetScript("OnEscapePressed", function() editboxBlockInput:ClearFocus() end)
editboxBlockInput:SetScript("OnEditFocusLost", function()
	local channel = dropdownMenuInfo[UIDropDownMenu_GetSelectedValue(dropdownMenu)][2]
	local channel_settings = SpamBlockSave.channel[channel]
	channel_settings[3] = this:GetText()
	if channel == "NAMES" then
		SetFilterNameList(channel_settings[5], channel_settings[3])
	else
		SetFilterList(channel_settings[5], channel_settings[3], channel_settings[6])
	end
end)

-- editboxBlockScroll
editboxBlockScroll:SetPoint("TOPLEFT", editboxBlock, "TOPLEFT", 8, -8)
editboxBlockScroll:SetPoint("BOTTOMRIGHT", editboxBlock, "BOTTOMRIGHT", -6, 8)
editboxBlockScroll:EnableMouse(true)
editboxBlockScroll:SetScript("OnMouseDown", function() editboxBlockInput:SetFocus() end)
editboxBlockScroll:SetScrollChild(editboxBlockInput)

-- taken from Blizzard's macro UI XML to handle scrolling
editboxBlockInput:SetScript("OnTextChanged", function()
	local scrollbar = _G[editboxBlockScroll:GetName() .. "ScrollBar"]
	local min, max = scrollbar:GetMinMaxValues()
	if max > 0 and this.max ~= max then
		this.max = max
		scrollbar:SetValue(max)
	end
end)
editboxBlockInput:SetScript("OnUpdate", function(this)
	ScrollingEdit_OnUpdate(editboxBlockScroll)
end)
editboxBlockInput:SetScript("OnCursorChanged", function()
	ScrollingEdit_OnCursorChanged(arg1, arg2, arg3, arg4)
end)

--------------------------------------------------
-- edit box - allow messages
--------------------------------------------------
local editboxAllow = CreateFrame("Frame", "SSSB_EditAllow", guiFrame)
local editboxAllowInput = CreateFrame("EditBox", "SSSB_EditAllowInput", editboxAllow)
local editboxAllowScroll = CreateFrame("ScrollFrame", "SSSB_EditAllowScroll", editboxAllow, "UIPanelScrollFrameTemplate")

-- header
local textAllowContaining = guiFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
textAllowContaining:SetPoint("TOP", textBlockContaining, "TOP", 0, 0)

-- editboxAllow - main container
editboxAllow:SetPoint("TOP", editboxBlock, "TOP", 0, 0)
editboxAllow:SetPoint("BOTTOMRIGHT", guiFrame, "BOTTOMRIGHT", -32, 12)
editboxAllow:SetWidth(editboxBlock:GetWidth())
editboxAllow:SetBackdrop({
	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
	tile=1, tileSize=32, edgeSize=16,
	insets={left=5, right=5, top=5, bottom=5}})
editboxAllow:SetBackdropColor(0,0,0,1)

textAllowContaining:SetPoint("LEFT", editboxAllow, "LEFT", 0, 0)

-- editboxAllowInput
editboxAllowInput:SetMultiLine(true)
editboxAllowInput:SetAutoFocus(false)
editboxAllowInput:EnableMouse(true)
editboxAllowInput:SetFont("Fonts/ARIALN.ttf", 14)
editboxAllowInput:SetWidth(editboxAllow:GetWidth()-20)
editboxAllowInput:SetHeight(editboxAllow:GetHeight()-8)
editboxAllowInput:SetScript("OnEscapePressed", function() editboxAllowInput:ClearFocus() end)
editboxAllowInput:SetScript("OnEditFocusLost", function()
	local channel = dropdownMenuInfo[UIDropDownMenu_GetSelectedValue(dropdownMenu)][2]
	local channel_settings = SpamBlockSave.channel[channel]
	channel_settings[2] = this:GetText()
	if channel == "NAMES" then
		SetFilterNameList(channel_settings[4], channel_settings[2])
	else
		SetFilterList(channel_settings[4], channel_settings[2], channel_settings[6])
	end
end)

-- editboxAllowScroll
editboxAllowScroll:SetPoint("TOPLEFT", editboxAllow, "TOPLEFT", 8, -8)
editboxAllowScroll:SetPoint("BOTTOMRIGHT", editboxAllow, "BOTTOMRIGHT", -6, 8)
editboxAllowScroll:EnableMouse(true)
editboxAllowScroll:SetScript("OnMouseDown", function() editboxAllowInput:SetFocus() end)
editboxAllowScroll:SetScrollChild(editboxAllowInput)

-- taken from Blizzard's macro UI XML to handle scrolling
editboxAllowInput:SetScript("OnTextChanged", function()
	local scrollbar = _G[editboxAllowScroll:GetName() .. "ScrollBar"]
	local min, max = scrollbar:GetMinMaxValues()
	if max > 0 and this.max ~= max then
		this.max = max
		scrollbar:SetValue(max)
	end
end)
editboxAllowInput:SetScript("OnUpdate", function(this)
	ScrollingEdit_OnUpdate(editboxAllowScroll)
end)
editboxAllowInput:SetScript("OnCursorChanged", function()
	ScrollingEdit_OnCursorChanged(arg1, arg2, arg3, arg4)
end)

--------------------------------------------------
-- dropdown menu functions
--------------------------------------------------
-- set the block and allow editbox texts
local function UpdateEditBoxes()
	local value = UIDropDownMenu_GetSelectedValue(dropdownMenu)
	local channel = dropdownMenuInfo[value][2]
	local channel_settings = SpamBlockSave.channel[channel]
	editboxAllowInput:SetText(channel_settings[2])
	editboxBlockInput:SetText(channel_settings[3])
	if channel == "NAMES" then
		checkboxNormalization:Hide()
		textBlockContaining:SetText("Block messages from:")
		textAllowContaining:SetText("Allow messages from:")
	else
		checkboxNormalization:Show()
		checkboxNormalization:SetChecked(channel_settings[6])
		textBlockContaining:SetText("Block messages containing:")
		textAllowContaining:SetText("Allow messages containing:")
	end
end

-- a dropdown menu item was selected, so change the edit boxes to whatever was picked
local function DropdownMenu_OnClick()
	if GetCurrentKeyBoardFocus() then GetCurrentKeyBoardFocus():ClearFocus() end
	UIDropDownMenu_SetSelectedValue(dropdownMenu, this.value)
	UpdateEditBoxes()
end

-- set up the dropdown choices
local dropdownMenuItem = {}
local function DropdownMenu_Initialize()
	for i=1,#dropdownMenuInfo do
		dropdownMenuItem.func = DropdownMenu_OnClick
		dropdownMenuItem.checked = nil
		dropdownMenuItem.value = i
		dropdownMenuItem.text = dropdownMenuInfo[i][1]
		UIDropDownMenu_AddButton(dropdownMenuItem)
	end
end
UIDropDownMenu_Initialize(dropdownMenu, DropdownMenu_Initialize)
UIDropDownMenu_SetSelectedValue(dropdownMenu, 1)

-- normalization checkbox
checkboxNormalization:SetScript("OnClick", function()
	local channel = dropdownMenuInfo[UIDropDownMenu_GetSelectedValue(dropdownMenu)][2]
	if channel ~= "NAMES" then
		local channel_settings = SpamBlockSave.channel[channel]
		channel_settings[6] = this:GetChecked() or false
		-- reparse the filter lines
		SetFilterList(channel_settings[4], channel_settings[2], channel_settings[6])
		SetFilterList(channel_settings[5], channel_settings[3], channel_settings[6])
	end
end)

--------------------------------------------------
-- close button
--------------------------------------------------
local buttonClose = CreateFrame("Button", "SSSB_ButtonClose", guiFrame, "UIPanelCloseButton")
buttonClose:SetPoint("TOPRIGHT", guiFrame, "TOPRIGHT", -8, -8)
buttonClose:SetScript("OnClick", function()
	editboxDuplicateNoisy:ClearFocus()
	editboxDuplicateOther:ClearFocus()
	editboxBlockInput:ClearFocus()
	editboxAllowInput:ClearFocus()
	guiFrame:Hide()
end)

--------------------------------------------------
-- showing the window
--------------------------------------------------
-- update the statistics display
function guiFrame.UpdateStatistics()
	local allowed, blocked = SpamBlockSave.amountAllowed, SpamBlockSave.amountBlocked
	textTotalStatsRight:SetFormattedText("%d\n%d\n%.2f%%", allowed, blocked,
		(allowed<=0 and blocked<=0 and 0 or blocked*100/(allowed+blocked)) )

	allowed, blocked = SpamBlockSave.sessionAllowed, SpamBlockSave.sessionBlocked
	textSessionStatsRight:SetFormattedText("%d\n%d\n%.2f%%", allowed, blocked,
		(allowed<=0 and blocked<=0 and 0 or blocked*100/(allowed+blocked)) )
end

guiFrame:SetScript("OnShow", function()
	local settings = SpamBlockSave
	checkboxCustom:SetChecked(settings.channel["CUSTOM"][1])
	checkboxGeneral:SetChecked(settings.channel["GENERAL"][1])
	checkboxRecruitment:SetChecked(settings.channel["GUILDRECRUITMENT"][1])
	checkboxDefense:SetChecked(settings.channel["DEFENSE"][1])
	checkboxLFG:SetChecked(settings.channel["LOOKINGFORGROUP"][1])
	checkboxTrade:SetChecked(settings.channel["TRADE"][1])
	checkboxYell:SetChecked(settings.channel["CHAT_MSG_YELL"][1])
	checkboxTradeskills:SetChecked(settings.channel["CHAT_MSG_TRADESKILLS"][1])
	editboxDuplicateNoisy:SetText(tonumber(settings.blockTime[1]) or 60)

	checkboxBattleground:SetChecked(settings.channel["CHAT_MSG_BATTLEGROUND"][1])
	checkboxEmote:SetChecked(settings.channel["CHAT_MSG_EMOTE"][1])
	checkboxGuild:SetChecked(settings.channel["CHAT_MSG_GUILD"][1])
	checkboxParty:SetChecked(settings.channel["CHAT_MSG_PARTY"][1])
	checkboxRaid:SetChecked(settings.channel["CHAT_MSG_RAID"][1])
	checkboxSay:SetChecked(settings.channel["CHAT_MSG_SAY"][1])
	checkboxWhisper:SetChecked(settings.channel["CHAT_MSG_WHISPER"][1])
	checkboxWhisperInform:SetChecked(settings.channel["CHAT_MSG_WHISPER_INFORM"][1])
	editboxDuplicateOther:SetText(tonumber(settings.blockTime[2]) or 2)

	checkboxTestMode:SetChecked(settings.filterTestMode)
	checkboxYourself:SetChecked(settings.filterSelf)
	checkboxNumbers:SetChecked(settings.filterNumbers)
	checkboxShattrathLanguage:SetChecked(settings.filterShattrathLanguage)
	checkboxClinkFix:SetChecked(settings.filterClinkFix)
	checkboxRaidIcons:SetChecked(settings.filterRaidIcons)
	checkboxTranslateLinks:SetChecked(settings.filterTranslateLinks)
	checkboxExtraSecond:SetChecked(settings.filterExtraSecond)
	checkboxChannelInvites:SetChecked(settings.filterChannelInvites)

	UpdateEditBoxes()
	guiFrame.UpdateStatistics()
end)

-- only hide after everything is set up and placed
guiFrame:Hide()
