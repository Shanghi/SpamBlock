----------------------------------------------------------------------------------------------------
-- variables / references
----------------------------------------------------------------------------------------------------
SpamBlockSave = nil -- saved settings/statistics - set up in ADDON_LOADED
local spamBlockFrame = CreateFrame("frame", "SpamBlockFrame")

-- local references/copies of some saved settings that are used a lot
local spamSettings            = nil -- reference to SpamBlockSave
local filterNumbers           = nil -- copy of SpamBlockSave.filterNumbers
local filterShattrathLanguage = nil -- copy of SpamBlockSave.filterShattrathLanguage
local filterClinkFix          = nil -- copy of SpamBlockSave.filterClinkFix
local filterRaidIcons         = nil -- copy of SpamBlockSave.filterRaidIcons
local filterTranslateLinks    = nil -- copy of SpamBlockSave.filterTranslateLinks
local filterExtraSecond       = nil -- copy of SpamBlockSave.filterExtraSecond
local allChatInfo             = nil -- SpamBlockSave.channel["ALL"]
local nameInfo                = nil -- SpamBlockSave.channel["NAMES"]
local playerName              = UnitName("player")
local GetTime                 = GetTime
local find                    = string.find
local upper                   = string.upper
local lower                   = string.lower
local format                  = string.format

-- message handling
local recentMessages   = {}  -- table of recently seen messages: [message] = GetTime() when expires
local extraSecondList  = {}  -- table for filterExtraSecond: {["name"] = {"channel", GetTime()}, ...}
local onMessageId      = nil -- current message ID being processed
local onMessageBlocked = nil -- if the current message has been blocked - true or false
local onMessageChanged = nil -- the edited current message, so it doesn't have to keep modifying it

-- table of known langauges for fast testing when using unknown Shattrath language filtering
local knownLanguages = nil

----------------------------------------------------------------------------------------------------
-- helper functions
----------------------------------------------------------------------------------------------------
--------------------------------------------------
-- return a modified message to use for matching
--------------------------------------------------
local drunkSlur = SLURRED_SPEECH:gsub("%s*%%s%s*", "") -- get the client's "...hic!" string

-- Convert and return a message suitable to match against - remove {skull}-like icons, spaces,
-- capitalization, punctuation, drunk text, and numbers (if wanted)
function spamBlockFrame.GetMatchMessage(message, normalize)
	if message then
		if normalize then
			message = lower(message:gsub("{.-}", ""):gsub(drunkSlur, ""):gsub("[%s%p%c]+", "")):gsub("sh", "s")
		else
			message = lower(message)
		end
		if filterNumbers then
			message = message:gsub("%d+", "")
		end
	end
	return message or ""
end
local GetMatchMessage = spamBlockFrame.GetMatchMessage

--------------------------------------------------
-- if a name is not a friend or guild/group member
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

--------------------------------------------------
-- update the often used copies of settings
--------------------------------------------------
function spamBlockFrame.UpdateLocalCopies()
	filterNumbers           = spamSettings.filterNumbers
	filterShattrathLanguage = spamSettings.filterShattrathLanguage
	filterClinkFix          = spamSettings.filterClinkFix
	filterRaidIcons         = spamSettings.filterRaidIcons
	filterTranslateLinks    = spamSettings.filterTranslateLinks
	filterExtraSecond       = spamSettings.filterExtraSecond
end

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
		spamSettings.sessionAllowed = spamSettings.sessionAllowed + 1
		spamSettings.amountAllowed = spamSettings.amountAllowed + 1
	else
		spamSettings.sessionBlocked = spamSettings.sessionBlocked + 1
		spamSettings.amountBlocked = spamSettings.amountBlocked + 1
	end
	if _G["SpamBlockGUI"]:IsVisible() then
		_G["SpamBlockGUI"].UpdateStatistics()
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

	onMessageChanged = nil

	-- allow your own messages
	local arg2 = arg2
	if arg2 == playerName and not spamSettings.filterSelf then
		CountMessage(true)
		return
	end

	-- check language filtering
	local arg3 = arg3
	if filterShattrathLanguage and arg3 ~= "" and (GetZonePVPInfo()) == "sanctuary" then
		-- the language table is built here the first time it's needed instead of when loading because
		-- it's possible for GetNumLanguages() to not work even when waiting for the very last event
		-- that happens after logging in. It will return nil when not ready - I'm not sure if it would
		-- ever return 0, but better to be safe than sorry!
		if not knownLanguages and GetNumLanguages() ~= nil and GetNumLanguages() ~= 0 then
			knownLanguages = {}
			for i=1,GetNumLanguages() do
				knownLanguages[GetLanguageByIndex(i)] = true
			end
		end
		if knownLanguages and not knownLanguages[arg3] then
			CountMessage(false)
			return
		end
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
	local name = arg2 and arg2 ~= "" and lower(arg2) or nil
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

--------------------------------------------------
-- chat frame filter - for channel invitations
-- block: return true / allow: return false, message
--------------------------------------------------
local function SpamBlockInviteFilter(message)
	-- not an invitation so allow
	if arg1 ~= "INVITE" then
		CountMessage(true)
		return false, message
	end

	-- if not already checked, count the message ar blocked or allowed
	local arg11 = arg11
	if arg11 ~= onMessageId then
		if spamSettings.filterChannelInvites and IsStranger(arg2) then
			CountMessage(false)
			-- can't just edit this message, so each tab chat will be checked to add it there if wanted
			if spamSettings.filterTestMode then
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
			end
			return true, message
		else
			CountMessage(true)
		end
	end
	return onMessageBlocked, message
end

--------------------------------------------------
-- chat frame filter - for normal messages
-- block: return true / allow: return false, message
--------------------------------------------------
local function SpamBlockChatFilter(event, message)
	CheckMessage(event)

	-- the filter is called for each chat tab, so the results are saved to be used quickly here
	if onMessageChanged then
		return onMessageBlocked, onMessageChanged
	end

	if not onMessageBlocked then
		-- remove raid icons from the channel message if wanted
		if filterRaidIcons and event == "CHAT_MSG_CHANNEL" then
			message = message:gsub("({.-})(%s?)", function(tag, space) return raidIconList[lower(tag)] and "" or tag..space end)
		end

		-- fix CLINK links if wanted
		if filterClinkFix and message:find("{CLINK") then
			-- copied from Chatter
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
		onMessageChanged = "|cffff0000[Spam]|r " .. message
		return false, onMessageChanged
	end
	onMessageChanged = message
	return onMessageBlocked, message
end

----------------------------------------------------------------------------------------------------
-- event handling
----------------------------------------------------------------------------------------------------
local function SpamBlock_OnEvent(self, event, arg1, arg2)
	-- remove old data during loading screen
	if event == "PLAYER_LEAVING_WORLD" then
		extraSecondList = {}
		return
	end

	-- channel invitation popup
	if event == "CHANNEL_INVITE_REQUEST" then
		if spamSettings.filterChannelInvites and IsStranger(arg2) then
			StaticPopup_Hide("CHAT_CHANNEL_INVITE")
		end
		return
	end

	-- loading settings and setting up filters/events
	if event == "ADDON_LOADED" and arg1 == "SpamBlock" then
		spamBlockFrame:UnregisterEvent(event)

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
		spamSettings.sessionAllowed = 0
		spamSettings.sessionBlocked = 0

		-- channel format: {check duplicates, plain text allow, plain text block, formatted allow lines, formatted block lines, is normalized}
		local channels = spamSettings.channel
		if channels["ALL"]                     == nil then channels["ALL"]                     = {false, "", "", {}, {}, true} end
		if channels["CHAT_MSG_CHANNEL"]        == nil then channels["CHAT_MSG_CHANNEL"]        = {false, "", "", {}, {}, true} end
		if channels["CHAT_MSG_BATTLEGROUND"]   == nil then channels["CHAT_MSG_BATTLEGROUND"]   = {true,  "", "", {}, {}, true} end
		if channels["CHAT_MSG_EMOTE"]          == nil then channels["CHAT_MSG_EMOTE"]          = {true,  "", "", {}, {}, true} end
		if channels["CHAT_MSG_TEXT_EMOTE"]     == nil then channels["CHAT_MSG_TEXT_EMOTE"]     = {channels["CHAT_MSG_EMOTE"][1],  "", "", {}, {}, true} end
		if channels["CHAT_MSG_GUILD"]          == nil then channels["CHAT_MSG_GUILD"]          = {false, "", "", {}, {}, true} end
		if channels["CHAT_MSG_MONSTER_SAY"]    == nil then channels["CHAT_MSG_MONSTER_SAY"]    = {false, "", "", {}, {}, true} end
		if channels["CHAT_MSG_PARTY"]          == nil then channels["CHAT_MSG_PARTY"]          = {true,  "", "", {}, {}, true} end
		if channels["CHAT_MSG_RAID"]           == nil then channels["CHAT_MSG_RAID"]           = {true,  "", "", {}, {}, true} end
		if channels["CHAT_MSG_SAY"]            == nil then channels["CHAT_MSG_SAY"]            = {true,  "", "", {}, {}, true} end
		if channels["CHAT_MSG_SYSTEM"]         == nil then channels["CHAT_MSG_SYSTEM"]         = {false, "rolls", "", {"rolls"}, {}, true} end
		if channels["CHAT_MSG_TRADESKILLS"]    == nil then channels["CHAT_MSG_TRADESKILLS"]    = {false, "", "", {}, {}, true} end
		if channels["CHAT_MSG_WHISPER"]        == nil then channels["CHAT_MSG_WHISPER"]        = {true,  "", "", {}, {}, true} end
		if channels["CHAT_MSG_WHISPER_INFORM"] == nil then channels["CHAT_MSG_WHISPER_INFORM"] = {false, "", "", {}, {}, true} end
		if channels["CHAT_MSG_YELL"]           == nil then channels["CHAT_MSG_YELL"]           = {true,  "", "", {}, {}, true} end
		if channels["CUSTOM"]                  == nil then channels["CUSTOM"]                  = {false, "", "", {}, {}, true} end
		if channels["GENERAL"]                 == nil then channels["GENERAL"]                 = {true,  "", "", {}, {}, true} end
		if channels["GUILDRECRUITMENT"]        == nil then channels["GUILDRECRUITMENT"]        = {true,  "", "", {}, {}, true} end
		if channels["DEFENSE"]                 == nil then channels["DEFENSE"]                 = {true,  "", "", {}, {}, true} end
		if channels["LOOKINGFORGROUP"]         == nil then channels["LOOKINGFORGROUP"]         = {true,  "", "", {}, {}, true} end
		if channels["TRADE"]                   == nil then channels["TRADE"]                   = {true,  "", "", {}, {}, true} end
		if channels["NAMES"]                   == nil then channels["NAMES"]                   = {false, "", "", {}, {}, false} end

		-- set copies for settings that are used a lot
		SpamBlockFrame.UpdateLocalCopies()
		allChatInfo = channels["ALL"]
		nameInfo = channels["NAMES"]

		-- set up filters
		local chat_events = {
			["CHAT_MSG_BATTLEGROUND"] = "CHAT_MSG_BATTLEGROUND",
			["CHAT_MSG_BATTLEGROUND_LEADER"] = "CHAT_MSG_BATTLEGROUND",
			["CHAT_MSG_CHANNEL"] = "CHAT_MSG_CHANNEL",
			["CHAT_MSG_EMOTE"] = "CHAT_MSG_EMOTE",
			["CHAT_MSG_GUILD"] = "CHAT_MSG_GUILD",
			["CHAT_MSG_MONSTER_EMOTE"] = "CHAT_MSG_MONSTER_SAY",
			["CHAT_MSG_MONSTER_SAY"] = "CHAT_MSG_MONSTER_SAY",
			["CHAT_MSG_MONSTER_YELL"] = "CHAT_MSG_MONSTER_SAY",
			["CHAT_MSG_PARTY"] = "CHAT_MSG_PARTY",
			["CHAT_MSG_RAID"] = "CHAT_MSG_RAID",
			["CHAT_MSG_RAID_LEADER"] = "CHAT_MSG_RAID",
			["CHAT_MSG_RAID_WARNING"] = "CHAT_MSG_RAID",
			["CHAT_MSG_SAY"] = "CHAT_MSG_SAY",
			["CHAT_MSG_SYSTEM"] = "CHAT_MSG_SYSTEM",
			["CHAT_MSG_TEXT_EMOTE"] = "CHAT_MSG_TEXT_EMOTE",
			["CHAT_MSG_TRADESKILLS"] = "CHAT_MSG_TRADESKILLS",
			["CHAT_MSG_WHISPER"] = "CHAT_MSG_WHISPER",
			["CHAT_MSG_WHISPER_INFORM"] = "CHAT_MSG_WHISPER_INFORM",
			["CHAT_MSG_YELL"] = "CHAT_MSG_YELL",
		}
		for event,substitute in pairs(chat_events) do
			ChatFrame_AddMessageEventFilter(event, function(message)
				return SpamBlockChatFilter(substitute, message)
			end)
		end
		ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", SpamBlockInviteFilter)

		spamBlockFrame:RegisterEvent("PLAYER_LEAVING_WORLD")   -- remove old data during loading screens
		spamBlockFrame:RegisterEvent("CHANNEL_INVITE_REQUEST") -- for hiding channel invitation popups
		spamBlockFrame:SetScript("OnUpdate", SpamBlock_OnUpdate)
	end
end

spamBlockFrame:SetScript("OnEvent", SpamBlock_OnEvent)
spamBlockFrame:RegisterEvent("ADDON_LOADED") -- temporary - to load settings and initiate things

----------------------------------------------------------------------------------------------------
-- slash command
----------------------------------------------------------------------------------------------------
_G.SLASH_SPAMBLOCK1 = "/spamblock"
function SlashCmdList.SPAMBLOCK(input)
	-- open the options window if there's no command
	if not input or input == "" then
		_G["SpamBlockGUI"]:Show()
		return
	end

	local command, value = input:lower():match("(%w+)%s*(.*)")

	-- /spamblock stats
	if command:match("^stat[s]?$") then
		if value == "reset" then
			spamSettings.sessionAllowed = 0
			spamSettings.sessionBlocked = 0
			spamSettings.amountAllowed = 0
			spamSettings.amountBlocked = 0
			DEFAULT_CHAT_FRAME:AddMessage("Statistics have been reset.")
			if _G["SpamBlockGUI"]:IsVisible() then
				_G["SpamBlockGUI"].UpdateStatistics()
			end
		else
			local allowed, blocked
			allowed = spamSettings.sessionAllowed
			blocked = spamSettings.sessionBlocked
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
