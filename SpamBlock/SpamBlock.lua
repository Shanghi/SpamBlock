----------------------------------------------------------------------------------------------------
-- variables / references
----------------------------------------------------------------------------------------------------
SpamBlockSave = nil -- saved settings/statistics - set up in ADDON_LOADED
local eventFrame = CreateFrame("frame") -- anonymous frame for OnEvent/OnUpdate scripts

-- local references/copies of some saved settings that are used a lot
local spamSettings            = nil -- reference to SpamBlockSave
local filterNumbers           = nil -- copy of SpamBlockSave.filterNumbers
local filterShattrathLanguage = nil -- copy of SpamBlockSave.filterShattrathLanguage
local filterClinkFix          = nil -- copy of SpamBlockSave.filterClinkFix
local filterRaidIcons         = nil -- copy of SpamBlockSave.filterRaidIcons
local filterTranslateLinks    = nil -- copy of SpamBlockSave.filterTranslateLinks
local filterExtraSecond       = nil -- copy of SpamBlockSave.filterExtraSecond
local allChatInfo             = nil -- spamSettings.channel["ALL"]
local nameInfo                = nil -- spamSettings.channel["NAMES"]
local playerName              = UnitName("player")
local GetTime                 = GetTime
local find                    = string.find
local upper                   = string.upper
local format                  = string.format

-- statistics for this session
local amountAllowed = 0
local amountBlocked = 0

-- message handling
local recentMessages   = {}  -- table of recently seen messages: [message] = GetTime() when expires
local extraSecondList  = {}  -- table for filterExtraSecond: {["name"] = {"channel", GetTime()}, ...}
local onMessageId      = nil -- current message ID being processed
local onMessageBlocked = nil -- if the current message has been blocked - true or false

-- for fast testing when using unknown Shattrath language filtering - languages set up when loading
local languagesKnown = {}

----------------------------------------------------------------------------------------------------
-- helper functions
----------------------------------------------------------------------------------------------------
--------------------------------------------------
-- return a modified message to use for matching other messages
--------------------------------------------------
local drunkSlur = SLURRED_SPEECH:gsub("%s*%%s%s*", "") -- get the client's "...hic!" string

-- Convert and return a message suitable to match against - remove {skull}-like icons, spaces,
-- capitalization, punctuation, drunk text, and numbers (if wanted)
local function GetMatchMessage(message, normalize)
	if message then
		if normalize then
			message = message:gsub("{.-}",""):gsub(drunkSlur,""):gsub("[%s%p%c]+",""):lower():gsub("sh","s")
		else
			message = message:lower()
		end
		if filterNumbers then
			message = message:gsub("%d+","")
		end
	end
	return message or ""
end

--------------------------------------------------
-- convert raw text from an option edit box into a list of proper filters
--------------------------------------------------
local function SetFilterList(filter_table, raw_text, normalize)
	for i=1,#filter_table do
		filter_table[i] = nil
	end
	local text
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
-- convert raw text from an option edit box into an dictionary table, not list, of lowercase names
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
	for _,settings in pairs(spamSettings.channel) do
		SetFilterList(settings[4], settings[2], settings[6]) -- allow filters
	SetFilterList(settings[5], settings[3], settings[6]) -- block filters
	end
end

--------------------------------------------------
-- return true if a player is not a friend, guild member, or group member
--------------------------------------------------
local function IsStranger(name)
	for i=1,GetNumFriends() do
		if name == GetFriendInfo(i) then
			return
		end
	end
	if GetNumRaidMembers() > 0 then
		for i=1,MAX_RAID_MEMBERS do
			if name == (GetRaidRosterInfo(i)) then
				return
			end
		end
	elseif GetNumPartyMembers() > 0 then
		for i=1,GetNumPartyMembers() do
			if name == UnitName("party"..i) then
				return
			end
		end
	end
	if IsInGuild() then
		for i=1,GetNumGuildMembers() do
			if name == GetGuildRosterInfo(i) then
				return
			end
		end
	end
	return true
end

----------------------------------------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------------------------------------
local guiFrame = CreateFrame("Frame", "SpamBlockGui", UIParent)

local function CreateCheckbox(name, text, tooltip)
	local frame = CreateFrame("CheckButton", "SSSB_CB"..name, guiFrame, "OptionsCheckButtonTemplate")
	_G[frame:GetName().."Text"]:SetText(text)
	local width = _G[frame:GetName().."Text"]:GetStringWidth()
	frame:SetHitRectInsets(0, -width, 4, 4)
	frame.tooltipText = tooltip
	return frame
end

-- for showing tooltips
function WidgetTooltip_OnEnter()
	GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
	GameTooltip:SetText(this.tooltipText, nil, nil, nil, nil, 1)
	GameTooltip:Show()
end
function WidgetTooltip_OnLeave()
	GameTooltip:Hide()
end

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
checkboxGeneral:SetScript("OnClick", function() spamSettings.channel["GENERAL"][1] = this:GetChecked() or false end)

-- Defense
local checkboxDefense = CreateCheckbox("Defense", "|cffff0000Defense|r")
checkboxDefense:SetPoint("TOPLEFT", checkboxGeneral, "BOTTOMLEFT", 0, 8)
checkboxDefense:SetScript("OnClick", function() spamSettings.channel["DEFENSE"][1] = this:GetChecked() or false end)

-- Recruitment
local checkboxRecruitment = CreateCheckbox("Recruitment", "|cffff0000Recruitment|r")
checkboxRecruitment:SetPoint("TOPLEFT", checkboxDefense, "BOTTOMLEFT", 0, 8)
checkboxRecruitment:SetScript("OnClick", function() spamSettings.channel["GUILDRECRUITMENT"][1] = this:GetChecked() or false end)

-- Tradeskills
local checkboxTradeskills = CreateCheckbox("Tradeskills", "|cffff0000Tradeskills|r")
checkboxTradeskills:SetPoint("TOPLEFT", checkboxRecruitment, "BOTTOMLEFT", 0, 8)
checkboxTradeskills:SetScript("OnClick", function() spamSettings.channel["CHAT_MSG_TRADESKILLS"][1] = this:GetChecked() or false end)

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
	spamSettings.blockTime[1] = time
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
checkboxGuild:SetScript("OnClick", function() spamSettings.channel["CHAT_MSG_GUILD"][1] = this:GetChecked() or false end)

-- Battleground
local checkboxBattleground = CreateCheckbox("Battleground", "|cff00ff00Battleground|r")
checkboxBattleground:SetPoint("TOPLEFT", checkboxGuild, "BOTTOMLEFT", 0, 8)
checkboxBattleground:SetScript("OnClick", function() spamSettings.channel["CHAT_MSG_BATTLEGROUND"][1] = this:GetChecked() or false end)

-- Whispered
local checkboxWhisper = CreateCheckbox("Whispered", "|cff00ff00Whispered|r")
checkboxWhisper:SetPoint("TOPLEFT", checkboxBattleground, "BOTTOMLEFT", 0, 8)
checkboxWhisper:SetScript("OnClick", function() spamSettings.channel["CHAT_MSG_WHISPER"][1] = this:GetChecked() or false end)

-- Whisper Inform
local checkboxWhisperInform = CreateCheckbox("Whispering", "|cff00ff00Whispering|r")
checkboxWhisperInform:SetPoint("TOPLEFT", checkboxWhisper, "BOTTOMLEFT", 0, 8)
checkboxWhisperInform:SetScript("OnClick", function() spamSettings.channel["CHAT_MSG_WHISPER_INFORM"][1] = this:GetChecked() or false end)

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
	spamSettings.blockTime[2] = time
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
checkboxTrade:SetScript("OnClick", function() spamSettings.channel["TRADE"][1] = this:GetChecked() or false end)

-- LFG
local checkboxLFG = CreateCheckbox("LFG", "|cffff0000LFG|r")
checkboxLFG:SetPoint("TOPLEFT", checkboxTrade, "BOTTOMLEFT", 0, 8)
checkboxLFG:SetScript("OnClick", function() spamSettings.channel["LOOKINGFORGROUP"][1] = this:GetChecked() or false end)

-- Custom
local checkboxCustom = CreateCheckbox("Custom", "|cffff0000Custom|r")
checkboxCustom:SetPoint("TOPLEFT", checkboxLFG, "BOTTOMLEFT", 0, 8)
checkboxCustom:SetScript("OnClick", function() spamSettings.channel["CUSTOM"][1] = this:GetChecked() or false end)

-- Yell
local checkboxYell = CreateCheckbox("Yell", "|cffff0000Yell|r")
checkboxYell:SetPoint("TOPLEFT", checkboxCustom, "BOTTOMLEFT", 0, 8)
checkboxYell:SetScript("OnClick", function() spamSettings.channel["CHAT_MSG_YELL"][1] = this:GetChecked() or false end)

-- Say
local checkboxSay = CreateCheckbox("Say", "|cff00ff00Say|r")
checkboxSay:SetPoint("TOPLEFT", checkboxGuild, "TOPRIGHT", 70, 0)
checkboxSay:SetScript("OnClick", function() spamSettings.channel["CHAT_MSG_SAY"][1] = this:GetChecked() or false end)

-- Party
local checkboxParty = CreateCheckbox("Party", "|cff00ff00Party|r")
checkboxParty:SetPoint("TOPLEFT", checkboxSay, "BOTTOMLEFT", 0, 8)
checkboxParty:SetScript("OnClick", function() spamSettings.channel["CHAT_MSG_PARTY"][1] = this:GetChecked() or false end)

-- Raid
local checkboxRaid = CreateCheckbox("Raid", "|cff00ff00Raid|r")
checkboxRaid:SetPoint("TOPLEFT", checkboxParty, "BOTTOMLEFT", 0, 8)
checkboxRaid:SetScript("OnClick", function() spamSettings.channel["CHAT_MSG_RAID"][1] = this:GetChecked() or false end)

-- Emote
local checkboxEmote = CreateCheckbox("Emote", "|cff00ff00Emote|r")
checkboxEmote:SetPoint("TOPLEFT", checkboxRaid, "BOTTOMLEFT", 0, 8)
checkboxEmote:SetScript("OnClick", function()
	spamSettings.channel["CHAT_MSG_EMOTE"][1] = this:GetChecked() or false
	spamSettings.channel["CHAT_MSG_TEXT_EMOTE"][1] = spamSettings.channel["CHAT_MSG_EMOTE"][1]
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
checkboxTestMode:SetScript("OnClick", function() spamSettings.filterTestMode = this:GetChecked() or false end)

-- Yourself
local checkboxYourself = CreateCheckbox("Yourself", "|cffffffffFilter your messages too|r",
	"Normally your own messages are never blocked, but if you're a spammer then you can enable this so that they are.")
checkboxYourself:SetPoint("TOPLEFT", checkboxTestMode, "BOTTOMLEFT", 0, 8)
checkboxYourself:SetScript("OnClick", function() spamSettings.filterSelf = this:GetChecked() or false end)

-- Numbers
local checkboxNumbers = CreateCheckbox("Numbers", "|cffffffffIgnore number differences|r",
	'"LFM 3 DPS" and "LFM 2 DPS" would count as the same message.')
checkboxNumbers:SetPoint("TOPLEFT", checkboxYourself, "BOTTOMLEFT", 0, 8)
checkboxNumbers:SetScript("OnClick", function()
	filterNumbers = this:GetChecked() or false
	spamSettings.filterNumbers = filterNumbers
	SetAllFilterLists()
end)

-- Shattrath Language
local checkboxShattrathLanguage = CreateCheckbox("Languages", "|cffffffffBlock unknown languages|r",
	"Block messages using game languages you can't understand, but only while in sanctuary areas like Shattrath.")
checkboxShattrathLanguage:SetPoint("TOPLEFT", checkboxNumbers, "BOTTOMLEFT", 0, 8)
checkboxShattrathLanguage:SetScript("OnClick", function()
	filterShattrathLanguage = this:GetChecked() or false
	spamSettings.filterShattrathLanguage = filterShattrathLanguage
end)

-- CLINK fix
local checkboxClinkFix = CreateCheckbox("Clink", "|cffffffffFix CLINK links|r",
	"Some people use addons that change item/spell links to be like {CLINK:something} because links were blocked on retail. This changes those back to normal links.")
checkboxClinkFix:SetPoint("TOPLEFT", checkboxShattrathLanguage, "BOTTOMLEFT", 0, 8)
checkboxClinkFix:SetScript("OnClick", function()
	filterClinkFix = this:GetChecked() or false
	spamSettings.filterClinkFix = filterClinkFix
end)

-- Raid target icons
local checkboxRaidIcons = CreateCheckbox("Icons", "|cffffffffRemove icons in channels|r",
	"They're only removed in numbered channels, so you'll still see them in raid/yell/etc.")
checkboxRaidIcons:SetPoint("TOPLEFT", checkboxClinkFix, "BOTTOMLEFT", 0, 8)
checkboxRaidIcons:SetScript("OnClick", function()
	filterRaidIcons = this:GetChecked() or false
	spamSettings.filterRaidIcons = filterRaidIcons
end)

-- Translate links
local checkboxTranslateLinks = CreateCheckbox("Translate", "|cffffffffTranslate spell/craft links|r",
	"Prefixes (like \"Alchemy:\") won't be translated.")
checkboxTranslateLinks:SetPoint("TOPLEFT", checkboxRaidIcons, "BOTTOMLEFT", 0, 8)
checkboxTranslateLinks:SetScript("OnClick", function()
	filterTranslateLinks = this:GetChecked() or false
	spamSettings.filterTranslateLinks = filterTranslateLinks
end)

-- Continue blocking for a second
local checkboxExtraSecond = CreateCheckbox("ExtraSecond", "|cffffffffBlock for an extra second|r",
	"This continues blocking someone for a second after their message matches something on a block list. This is for cases where they send multiple messages about the same thing at once (like a 3 message long guild ad) causing only the first to get blocked. Duplicate messages and emote actions don't trigger it.")
checkboxExtraSecond:SetPoint("TOPLEFT", checkboxTranslateLinks, "BOTTOMLEFT", 0, 8)
checkboxExtraSecond:SetScript("OnClick", function()
	filterExtraSecond = this:GetChecked() or false
	spamSettings.filterExtraSecond = filterExtraSecond
end)

-- Block channel invites
local checkboxChannelInvites = CreateCheckbox("ChannelInvites", "|cffffffffBlock channel invites from strangers|r",
	"This will block channel invitations from people that aren't friends, guild members, or in your group.")
checkboxChannelInvites:SetPoint("TOPLEFT", checkboxExtraSecond, "BOTTOMLEFT", 0, 8)
checkboxChannelInvites:SetScript("OnClick", function() spamSettings.filterChannelInvites = this:GetChecked() or false end)

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
--  Dropdown name                 name in spamSettings.channel[name]
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
	local channel_settings = spamSettings.channel[channel]
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
	local channel_settings = spamSettings.channel[channel]
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
	local channel_settings = spamSettings.channel[channel]
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
		local channel_settings = spamSettings.channel[channel]
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
local function UpdateGuiStatistics()
	local allowed, blocked = spamSettings.amountAllowed, spamSettings.amountBlocked
	textTotalStatsRight:SetFormattedText("%d\n%d\n%.2f%%", allowed, blocked,
		(allowed<=0 and blocked<=0 and 0 or blocked*100/(allowed+blocked)) )

	allowed, blocked = amountAllowed, amountBlocked
	textSessionStatsRight:SetFormattedText("%d\n%d\n%.2f%%", allowed, blocked,
		(allowed<=0 and blocked<=0 and 0 or blocked*100/(allowed+blocked)) )
end

guiFrame:SetScript("OnShow", function()
	checkboxCustom:SetChecked(spamSettings.channel["CUSTOM"][1])
	checkboxGeneral:SetChecked(spamSettings.channel["GENERAL"][1])
	checkboxRecruitment:SetChecked(spamSettings.channel["GUILDRECRUITMENT"][1])
	checkboxDefense:SetChecked(spamSettings.channel["DEFENSE"][1])
	checkboxLFG:SetChecked(spamSettings.channel["LOOKINGFORGROUP"][1])
	checkboxTrade:SetChecked(spamSettings.channel["TRADE"][1])
	checkboxYell:SetChecked(spamSettings.channel["CHAT_MSG_YELL"][1])
	checkboxTradeskills:SetChecked(spamSettings.channel["CHAT_MSG_TRADESKILLS"][1])
	editboxDuplicateNoisy:SetText(tonumber(spamSettings.blockTime[1]) or 60)

	checkboxBattleground:SetChecked(spamSettings.channel["CHAT_MSG_BATTLEGROUND"][1])
	checkboxEmote:SetChecked(spamSettings.channel["CHAT_MSG_EMOTE"][1])
	checkboxGuild:SetChecked(spamSettings.channel["CHAT_MSG_GUILD"][1])
	checkboxParty:SetChecked(spamSettings.channel["CHAT_MSG_PARTY"][1])
	checkboxRaid:SetChecked(spamSettings.channel["CHAT_MSG_RAID"][1])
	checkboxSay:SetChecked(spamSettings.channel["CHAT_MSG_SAY"][1])
	checkboxWhisper:SetChecked(spamSettings.channel["CHAT_MSG_WHISPER"][1])
	checkboxWhisperInform:SetChecked(spamSettings.channel["CHAT_MSG_WHISPER_INFORM"][1])
	editboxDuplicateOther:SetText(tonumber(spamSettings.blockTime[2]) or 2)

	checkboxTestMode:SetChecked(spamSettings.filterTestMode)
	checkboxYourself:SetChecked(spamSettings.filterSelf)
	checkboxNumbers:SetChecked(spamSettings.filterNumbers)
	checkboxShattrathLanguage:SetChecked(spamSettings.filterShattrathLanguage)
	checkboxClinkFix:SetChecked(spamSettings.filterClinkFix)
	checkboxRaidIcons:SetChecked(spamSettings.filterRaidIcons)
	checkboxTranslateLinks:SetChecked(spamSettings.filterTranslateLinks)
	checkboxExtraSecond:SetChecked(spamSettings.filterExtraSecond)
	checkboxChannelInvites:SetChecked(spamSettings.filterChannelInvites)

	UpdateEditBoxes()
	UpdateGuiStatistics()
end)

-- only hide after everything is set up and placed
guiFrame:Hide()

----------------------------------------------------------------------------------------------------
-- filtering
----------------------------------------------------------------------------------------------------
--------------------------------------------------
-- remove old messages from being blocked
--------------------------------------------------
local updateElapsed = 0
local function SpamBlock_OnUpdate(self, elapsed)
	updateElapsed = updateElapsed + elapsed
	if updateElapsed >= 5 then
		updateElapsed = 0

		local current_time = GetTime()
		for message,expire_time in pairs(recentMessages) do
			if current_time >= expire_time then
				recentMessages[message] = nil
			end
		end
	end
end

--------------------------------------------------
-- set and tally the current message as allowed or blocked
--------------------------------------------------
local function CountMessage(allowed)
	local arg11 = arg11
	if arg11 == onMessageId and arg11 ~= 0 then -- text_emote is always 0 and only filtered once
		return -- already counted this message
	end

	onMessageId = arg11
	onMessageBlocked = (allowed == false)

	if allowed then
		amountAllowed = amountAllowed + 1
		spamSettings.amountAllowed = spamSettings.amountAllowed + 1
	else
		amountBlocked = amountBlocked + 1
		spamSettings.amountBlocked = spamSettings.amountBlocked + 1
	end
	if guiFrame:IsVisible() then
		UpdateGuiStatistics()
	end
end

--------------------------------------------------
-- processing the current message
--------------------------------------------------
-- return if a message matches any line in a filter list
local function IsMessageFiltered(filter_table, message)
	for i=1,#filter_table do
		if find(message, filter_table[i]) then
			return true
		end
	end
	return false
end

-- table to set which chat settings a channel uses - if not on the list then it uses "CUSTOM"
local channelNameSettings = {
	["GENERAL"]          = "GENERAL",
	["TRADE"]            = "TRADE",
	["LOCALDEFENSE"]     = "DEFENSE",
	["WORLDDEFENSE"]     = "DEFENSE",
	["GUILDRECRUITMENT"] = "GUILDRECRUITMENT",
	["LOOKINGFORGROUP"]  = "LOOKINGFORGROUP",
}

-- table of chat types that are in the first duplicate timer group
local chatTypeDuplicateGroupOne = {
	["CHAT_MSG_CHANNEL"] = 1,
	["CHAT_MSG_TRADESKILLS"] = 1,
	["CHAT_MSG_YELL"] = 1,
}

-- table of raid target icon names
local raidIconList = {
	["{star}"]=1, ["{circle}"]=1, ["{diamond}"]=1, ["{triangle}"]=1, ["{moon}"]=1, ["{square}"]=1, ["{cross}"]=1, ["{skull}"]=1,
	["{rt1}"]=1, ["{rt2}"]=1, ["{rt3}"]=1, ["{rt4}"]=1, ["{rt5}"]=1, ["{rt6}"]=1, ["{rt7}"]=1, ["{rt8}"]=1,
	-- it's ok if these are just the English names again
	["{"..RAID_TARGET_1.."}"]=1, ["{"..RAID_TARGET_2.."}"]=1, ["{"..RAID_TARGET_3.."}"]=1, ["{"..RAID_TARGET_4.."}"]=1,
	["{"..RAID_TARGET_5.."}"]=1, ["{"..RAID_TARGET_6.."}"]=1, ["{"..RAID_TARGET_7.."}"]=1, ["{"..RAID_TARGET_8.."}"]=1,
}

local function CheckMessage(channel)
	-- check if the message has already been processed
	local arg11 = arg11
	if arg11 == onMessageId and arg11 ~= 0 then
		return
	end

	-- allow your own messages
	local arg2 = arg2
	if arg2 == playerName and not spamSettings.filterSelf then
		CountMessage(true)
		return
	end

	-- check channel invitations
	if channel == "CHAT_MSG_CHANNEL_NOTICE_USER" then
		if spamSettings.filterChannelInvites and arg1 == "INVITE" and IsStranger(arg2) then
			CountMessage(false)
		else
			CountMessage(true)
		end
		return
	end

	-- check language filtering
	local arg3 = arg3
	if filterShattrathLanguage and arg3 ~= "" and not languagesKnown[arg3] and (GetZonePVPInfo()) == "sanctuary" then
		CountMessage(false)
		return
	end

	-- get settings for the main chat type and channel type (if it's a CHAT_MSG_CHANNEL)
	local chat_info = spamSettings.channel[channel]
	local channel_info = nil
	local arg9 = arg9
	if arg9 ~= "" then
		local channel_name = channelNameSettings[upper(arg9:match("(%S+)") or "")] or "CUSTOM"
		channel_info = spamSettings.channel[channel_name]
	end

	-- strip and modify message/name so that minor changes like capitalization don't matter
	local arg1 = arg1
	local name = arg2 and arg2 ~= "" and arg2:lower() or nil
	local message = GetMatchMessage(arg1, chat_info[6])
	local channel_message -- only used if the normalization options are different
	if channel_info and channel_info[6] ~= chat_info[6] then
		channel_message = GetMatchMessage(arg1, channel_info[6])
	end

	-- check allow lists
	if IsMessageFiltered(allChatInfo[4], message)
		or IsMessageFiltered(chat_info[4], message)
		or (channel_info and IsMessageFiltered(channel_info[4], channel_message or message))
		or (name and nameInfo[4][name]) then
		CountMessage(true)
		return
	end

	-- check extra second block
	if filterExtraSecond and name and channel ~= "CHAT_MSG_TEXT_EMOTE" then
		local extra_second_info = extraSecondList[name]
		if extra_second_info then
			if GetTime() - extra_second_info[2] < 1 and extra_second_info[1] == channel then
				CountMessage(false)
			else
				extraSecondList[name] = nil
			end
		end
	end

	-- check block lists
	if IsMessageFiltered(allChatInfo[5], message)
		or IsMessageFiltered(chat_info[5], message)
		or (channel_info and IsMessageFiltered(channel_info[5], channel_message or message)) then
		CountMessage(false)
		if filterExtraSecond and name then
			extraSecondList[name] = {channel, GetTime()}
		end
		return
	end

	-- check blocked names - after lists so it doesn't use the extra second block
	if name and nameInfo[5][name] then
		CountMessage(false)
		return
	end

	-- check for message duplicates
	if (channel_info and not channel_info[1]) or (not channel_info and not chat_info[1]) then
		CountMessage(true)
	else
		local rm = recentMessages[channel_message or message]
		if not rm or GetTime() >= rm then
			recentMessages[channel_message or message] = GetTime() + spamSettings.blockTime[chatTypeDuplicateGroupOne[channel] and 1 or 2]
			CountMessage(true)
		else
			CountMessage(false)
		end
	end
end

-- chat filter - return true to block the message
local lastChannelInviteId = nil -- used when show test messages for blocked channel invitations
local function SpamBlockChatFilter(message)
	-- if a message is new, it must be a channel message because all others are handled with events
	if arg11 ~= onMessageId then
		CheckMessage("CHAT_MSG_CHANNEL")
		-- remove raid icons from the channel message if wanted
		if not onMessageBlocked and filterRaidIcons then
			message = message:gsub("({.-})(%s?)", function(tag, space) return raidIconList[tag:lower()] and "" or tag..space end)
		end
	end

	if not onMessageBlocked then
		-- fix CLINK links if wanted
		if filterClinkFix and message:find("{CLINK") then
			-- from Chatter
			message = message:gsub("{CLINK:item:(%x+):([%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-):([^}]-)}", "|c%1|Hitem:%2|h[%3]|h|r")
			message = message:gsub("{CLINK:enchant:(%x+):([%d-]-):([^}]-)}", "|c%1|Henchant:%2|h[%3]|h|r")
			message = message:gsub("{CLINK:spell:(%x+):([%d-]-):([^}]-)}", "|c%1|Hspell:%2|h[%3]|h|r")
			message = message:gsub("{CLINK:quest:(%x+):([%d-]-):([%d-]-):([^}]-)}", "|c%1|Hquest:%2:%3|h[%4]|h|r")
			message = message:gsub("{CLINK:(%x+):([%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-):([^}]-)}", "|c%1|Hitem:%2|h[%3]|h|r")
		end
		-- translate some links if wanted
		if filterTranslateLinks then
			message = message:gsub("|H(%l+):(%d+)|h%[(.-)]|h", function(link_type, id, name)
				id = tonumber(id)
				if link_type == "spell" then
					name = (GetSpellInfo(id)) or name
				elseif link_type == "enchant" then
					local craft_prefix, craft_name = name:match("^(.-): (.+)")
					if craft_name then
						if craft_name ~= (GetSpellInfo(id)) then
							name = craft_prefix .. ": " .. ((GetSpellInfo(id)) or craft_name)
						end
					else
						name = (GetSpellInfo(id)) or name
					end
				end
				return format("|H%s:%s|h[%s]|h", link_type, id, name)
			end)
		end
	elseif spamSettings.filterTestMode then
		if arg1 == "INVITE" then
			-- a channel invitation - can't simply modify it like normal messages so go through each
			-- chat tab and add it manually if needed
			if arg11 == lastChannelInviteId then
				return true -- already added
			end
			lastChannelInviteId = arg11
			local info = ChatTypeInfo["CHANNEL"] or {} -- for the text color
			local spam = "|cffff0000[Spam]|r " .. CHAT_INVITE_NOTICE:gsub("%%2$s", (arg2 or "Unknown")):gsub("%%1$s", (arg4 or "Unknown"))
			for i=1,NUM_CHAT_WINDOWS do
				if i ~= 2 then
					for _,v in ipairs{GetChatWindowMessages(i)} do
						if v == "CHANNEL" then
							_G["ChatFrame"..i]:AddMessage(spam, info.r or 1, info.g or 1, info.b or 1, info.id)
							break
						end
					end
				end
			end
			return true
		else
			return false, "|cffff0000[Spam]|r "..message
		end
	end
	return onMessageBlocked, message
end

----------------------------------------------------------------------------------------------------
-- event handling
----------------------------------------------------------------------------------------------------
-- table to convert certain channels to use other channel settings
local channelSubstituteSettings = {
	["CHAT_MSG_BATTLEGROUND_LEADER"] = "CHAT_MSG_BATTLEGROUND",
	["CHAT_MSG_RAID_LEADER"]         = "CHAT_MSG_RAID",
	["CHAT_MSG_RAID_WARNING"]        = "CHAT_MSG_RAID",
	["CHAT_MSG_MONSTER_EMOTE"]       = "CHAT_MSG_MONSTER_SAY",
	["CHAT_MSG_MONSTER_YELL"]        = "CHAT_MSG_MONSTER_SAY",
}

local function SpamBlock_OnEvent(self, event, arg1, arg2)
	--------------------------------------------------
	-- Check new chat messages for spam
	--------------------------------------------------
	if event:sub(1, 4) == "CHAT" then
		event = channelSubstituteSettings[event] or event
		CheckMessage(event)
		return
	end

	--------------------------------------------------
	-- remove old data during loading screen
	--------------------------------------------------
	if event == "PLAYER_LEAVING_WORLD" then
		extraSecondList = {}
		return
	end

	--------------------------------------------------
	-- channel invitation popup
	--------------------------------------------------
	if event == "CHANNEL_INVITE_REQUEST" then
		if spamSettings.filterChannelInvites and IsStranger(arg2) then
			StaticPopup_Hide("CHAT_CHANNEL_INVITE")
		end
		return
	end

	--------------------------------------------------
	-- logged in enough to get known languages
	--------------------------------------------------
	if event == "QUEST_LOG_UPDATE" then
		if GetNumLanguages() ~= nil and GetNumLanguages() ~= 0 then
			eventFrame:UnregisterEvent(event)
			for i=1,GetNumLanguages() do
				languagesKnown[GetLanguageByIndex(i)] = true
			end
		end
		return
	end

	--------------------------------------------------
	-- loading settings and setting up filters/events
	--------------------------------------------------
	if event == "ADDON_LOADED" and arg1 == "SpamBlock" then
		eventFrame:UnregisterEvent(event)

		-- build any missing settings
		if SpamBlockSave == nil then
			SpamBlockSave = {}
		end
		spamSettings = SpamBlockSave
		if spamSettings.amountAllowed           == nil then spamSettings.amountAllowed           = 0      end -- total amount of allowed messages
		if spamSettings.amountBlocked           == nil then spamSettings.amountBlocked           = 0      end -- total amount of blocked messages
		if spamSettings.blockTime               == nil then spamSettings.blockTime               = {60,2} end -- how many seconds to block a message before allowing it again [1]=noisy channels, [2]=other channels
		if spamSettings.filterTestMode          == nil then spamSettings.filterTestMode          = false  end -- if messages that are blocked should be shown
		if spamSettings.filterSelf              == nil then spamSettings.filterSelf              = false  end -- if your own messages will be filtered
		if spamSettings.filterNumbers           == nil then spamSettings.filterNumbers           = false  end -- ignore numbers, so "need 4 dps" and "need 2 dps" count as the same
		if spamSettings.filterShattrathLanguage == nil then spamSettings.filterShattrathLanguage = false  end -- if unknown languages are blocked while in Shattrath
		if spamSettings.filterClinkFix          == nil then spamSettings.filterClinkFix          = true   end -- if CLINK links should be changed into proper links
		if spamSettings.filterRaidIcons         == nil then spamSettings.filterRaidIcons         = false  end -- if raid target icons are filtered from channels
		if spamSettings.filterTranslateLinks    == nil then spamSettings.filterTranslateLinks    = false  end -- if spells/crafts are translated to the client's language
		if spamSettings.filterExtraSecond       == nil then spamSettings.filterExtraSecond       = false  end -- if a player is blocked for an extra second after their message gets blocked
		if spamSettings.filterChannelInvites    == nil then spamSettings.filterChannelInvites    = false  end -- if channel invites are blocked from non-guild/friend/group people
		if spamSettings.channel                 == nil then spamSettings.channel                 = {}     end
		--                                                                                                       format: {check duplicates, plain text allow, plain text block, formatted allow lines, formatted block lines, is normalized}
		if spamSettings.channel["ALL"]                     == nil then spamSettings.channel["ALL"]                     = {false, "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_CHANNEL"]        == nil then spamSettings.channel["CHAT_MSG_CHANNEL"]        = {false, "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_BATTLEGROUND"]   == nil then spamSettings.channel["CHAT_MSG_BATTLEGROUND"]   = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_EMOTE"]          == nil then spamSettings.channel["CHAT_MSG_EMOTE"]          = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_TEXT_EMOTE"]     == nil then spamSettings.channel["CHAT_MSG_TEXT_EMOTE"]     = {spamSettings.channel["CHAT_MSG_EMOTE"][1],  "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_GUILD"]          == nil then spamSettings.channel["CHAT_MSG_GUILD"]          = {false, "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_MONSTER_SAY"]    == nil then spamSettings.channel["CHAT_MSG_MONSTER_SAY"]    = {false, "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_PARTY"]          == nil then spamSettings.channel["CHAT_MSG_PARTY"]          = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_RAID"]           == nil then spamSettings.channel["CHAT_MSG_RAID"]           = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_SAY"]            == nil then spamSettings.channel["CHAT_MSG_SAY"]            = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_SYSTEM"]         == nil then spamSettings.channel["CHAT_MSG_SYSTEM"]         = {false, "rolls", "", {"rolls"}, {}, true} end
		if spamSettings.channel["CHAT_MSG_TRADESKILLS"]    == nil then spamSettings.channel["CHAT_MSG_TRADESKILLS"]    = {false, "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_WHISPER"]        == nil then spamSettings.channel["CHAT_MSG_WHISPER"]        = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_WHISPER_INFORM"] == nil then spamSettings.channel["CHAT_MSG_WHISPER_INFORM"] = {false, "", "", {}, {}, true} end
		if spamSettings.channel["CHAT_MSG_YELL"]           == nil then spamSettings.channel["CHAT_MSG_YELL"]           = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["CUSTOM"]                  == nil then spamSettings.channel["CUSTOM"]                  = {false, "", "", {}, {}, true} end
		if spamSettings.channel["GENERAL"]                 == nil then spamSettings.channel["GENERAL"]                 = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["GUILDRECRUITMENT"]        == nil then spamSettings.channel["GUILDRECRUITMENT"]        = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["DEFENSE"]                 == nil then spamSettings.channel["DEFENSE"]                 = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["LOOKINGFORGROUP"]         == nil then spamSettings.channel["LOOKINGFORGROUP"]         = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["TRADE"]                   == nil then spamSettings.channel["TRADE"]                   = {true,  "", "", {}, {}, true} end
		if spamSettings.channel["NAMES"]                   == nil then spamSettings.channel["NAMES"]                   = {false, "", "", {}, {}, false} end

		-- set local copies for settings that are used a lot
		filterNumbers           = spamSettings.filterNumbers
		filterShattrathLanguage = spamSettings.filterShattrathLanguage
		filterClinkFix          = spamSettings.filterClinkFix
		filterRaidIcons         = spamSettings.filterRaidIcons
		filterTranslateLinks    = spamSettings.filterTranslateLinks
		filterExtraSecond       = spamSettings.filterExtraSecond
		allChatInfo             = spamSettings.channel["ALL"]
		nameInfo                = spamSettings.channel["NAMES"]

		-- set up events and filters
		local chat_channels = {
			"CHAT_MSG_BATTLEGROUND",
			"CHAT_MSG_BATTLEGROUND_LEADER",
			"CHAT_MSG_CHANNEL",
			"CHAT_MSG_CHANNEL_NOTICE_USER", -- for channel invitations
			"CHAT_MSG_EMOTE",
			"CHAT_MSG_GUILD",
			"CHAT_MSG_MONSTER_EMOTE",
			"CHAT_MSG_MONSTER_SAY",
			"CHAT_MSG_MONSTER_YELL",
			"CHAT_MSG_PARTY",
			"CHAT_MSG_RAID",
			"CHAT_MSG_RAID_LEADER",
			"CHAT_MSG_RAID_WARNING",
			"CHAT_MSG_SAY",
			"CHAT_MSG_SYSTEM",
			"CHAT_MSG_TEXT_EMOTE",
			"CHAT_MSG_TRADESKILLS",
			"CHAT_MSG_WHISPER",
			"CHAT_MSG_WHISPER_INFORM",
			"CHAT_MSG_YELL"
		}
		for i=1,#chat_channels do
			-- CHANNEL event not used because it comes after the filtering function so would be useless
			if chat_channels[i] ~= "CHAT_MSG_CHANNEL" then
				eventFrame:RegisterEvent(chat_channels[i])
			end
			ChatFrame_AddMessageEventFilter(chat_channels[i], SpamBlockChatFilter)
		end
		eventFrame:SetScript("OnUpdate", SpamBlock_OnUpdate)
		eventFrame:SetScript("OnEvent", SpamBlock_OnEvent)
	end
end

eventFrame:SetScript("OnEvent", SpamBlock_OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")           -- temporary - to load settings and initiate things
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")       -- temporary - to load languages
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")   -- remove old data during loading screens
eventFrame:RegisterEvent("CHANNEL_INVITE_REQUEST") -- for hiding channel invitation popups

----------------------------------------------------------------------------------------------------
-- slash command
----------------------------------------------------------------------------------------------------
_G.SLASH_SPAMBLOCK1 = "/spamblock"
function SlashCmdList.SPAMBLOCK(input)
	-- open the options window if there's no command
	if not input or input == "" then
		guiFrame:Show()
		return
	end

	local command, value = input:lower():match("(%w+)%s*(.*)")

	-- /spamblock stats
	if command:match("^stat[s]*$") then
		if value == "reset" then
			amountAllowed = 0
			amountBlocked = 0
			spamSettings.amountAllowed = 0
			spamSettings.amountBlocked = 0
			DEFAULT_CHAT_FRAME:AddMessage("Statistics have been reset.")
			if guiFrame:IsVisible() then
				UpdateGuiStatistics()
			end
		else
			local allowed, blocked
			allowed = amountAllowed
			blocked = amountBlocked
			DEFAULT_CHAT_FRAME:AddMessage(format("This session: Allowed:[%d] Blocked:[%d] Spam:[%.2f%%]",
				allowed, blocked, (allowed<=0 and blocked<=0 and 0 or blocked*100/(allowed+blocked)) ))

			allowed = spamSettings.amountAllowed
			blocked = spamSettings.amountBlocked
			DEFAULT_CHAT_FRAME:AddMessage(format("All sessions: Allowed:[%d] Blocked:[%d] Spam:[%.2f%%]",
				allowed, blocked, (allowed<=0 and blocked<=0 and 0 or blocked*100/(allowed+blocked)) ))
		end
		return
	end

	-- bod command - show syntax
	DEFAULT_CHAT_FRAME:AddMessage('SpamBlock commands:', 1, 1, 0)
	DEFAULT_CHAT_FRAME:AddMessage('/spamblock')
	DEFAULT_CHAT_FRAME:AddMessage('/spamblock stats ["reset"]')
end
