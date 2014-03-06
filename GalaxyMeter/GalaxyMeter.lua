-----------------------------------------------------------------------------------------------
-- Client Lua Script for GalaxyMeter
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Apollo"
require "ChatSystemLib"
require "GameLib"
require "Window"
require "Unit"
require "Spell"
require "GroupLib"
require "ICCommLib"


-----------------------------------------------------------------------------------------------
-- GalaxyMeter Module Definition
-----------------------------------------------------------------------------------------------
local GalaxyMeter = {}

local gLog
local Queue
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
local GalMet_Version = 14


local kcrSelectedText = CColor.new(1,1,1,1)
local kcrNormalText = CColor.new(1,1,0.7,0.7)

-- Damage Type Colors (Get Proper Colors)
local kDamageStrToColor = {
	["Self"] 					= CColor.new(1, .75, 0, 1),
	["DamageType_Physical"] 	= CColor.new(1, .5, 0, 1),
	["DamageType_Tech"]			= CColor.new(.6, 0, 1, 1),
	["DamageType_Magic"]		= CColor.new(0, 0, 1, 1),
	["DamageType_Healing"]		= CColor.new(0, 1, 0, 1),
	["DamageType_Fall"]			= CColor.new(.5, .5, .5, 1),
	["DamageType_Suffocate"]	= CColor.new(.3, 0, 1, 1),
	["DamageType_Unknown"]		= CColor.new(.5, .5, .5, 1),
}

local kDamageTypeToColor = {
	[0]	= kDamageStrToColor["DamageType_Physical"],
	[1]	= kDamageStrToColor["DamageType_Tech"],
	[2]	= kDamageStrToColor["DamageType_Magic"],
	[3]	= kDamageStrToColor["DamageType_Healing"],
	[4] = kDamageStrToColor["DamageType_Healing"],
	[5]	= kDamageStrToColor["DamageType_Fall"],
	[6]	= kDamageStrToColor["DamageType_Suffocate"],
}

local kDamageTypeToString = {
	[0]	= "Physical",
	[1]	= "Tech",
	[2]	= "Magic",
	[3]	= "Heal",
	[4] = "Heal Shield",
	[5]	= "Falling",
	[6]	= "Suffocate",
}


local kClass = {
	"Warrior", "Engineer", "Esper", "Medic", "Stalker", "Unknown" , "Spellslinger", 
}

local kHostilityToColor = {
	[0] = CColor.new(1, .75, 0, 1),		-- Player
	CColor.new(1, 0, 0, 1),				-- Hostile
	CColor.new(0.5, 0.5, 0.5, 1),		-- Neutral
	CColor.new(0, 1, 1, 1),				-- Friendly
}

local eTypeDamageOrHealing = {
    PlayerDamageInOut = 1,
    PlayerDamageIn = 2,
    PlayerDamageOut = 3,
    PlayerHealingInOut = 4,
    PlayerHealingIn = 5,
    PlayerHealingOut = 6,
}


-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function GalaxyMeter:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end


function GalaxyMeter:Init()
    Apollo.RegisterAddon(self, false, "", {"GeminiLogging-1.1", "drafto_Queue-1.1"})
end


function GalaxyMeter:OnLoad()

	-- Setup GeminiLogging
	local GeminiLogging = Apollo.GetPackage("GeminiLogging-1.1").tPackage

	gLog = GeminiLogging:GetLogger({
		level = GeminiLogging.FATAL,
		pattern = "[%d] %n [%c:%l] - %m",
		appender = "GeminiConsole"
	})

	Queue = Apollo.GetPackage("drafto_Queue-1.1").tPackage
	
	-- Slash Commands
	Apollo.RegisterSlashCommand("galaxy", 							"OnGalaxyMeterOn", self)
	Apollo.RegisterSlashCommand("lkm", 								"OnGalaxyMeterOn", self)

	-- Player Updates
	Apollo.RegisterEventHandler("ChangeWorld", 						"OnChangeWorld", self)

	-- Self Combat Logging
	Apollo.RegisterEventHandler("UnitEnteredCombat", 				"OnEnteredCombat", self)
	--Apollo.RegisterEventHandler("SpellCastFailed", 				"OnSpellCastFailed", self)
	--Apollo.RegisterEventHandler("SpellEffectCast", 				"OnSpellEffectCast", self)
	--Apollo.RegisterEventHandler("CombatLogString", 				"OnCombatLogString", self)
	--Apollo.RegisterEventHandler("GenericEvent_CombatLogString", 	"OnCombatLogString", self)
	Apollo.RegisterEventHandler("CombatLogAbsorption",				"OnCombatLogAbsorption", self)
	Apollo.RegisterEventHandler("CombatLogCCStateBreak",			"OnCombatLogCCStateBreak", self)
	Apollo.RegisterEventHandler("CombatLogDamage",					"OnCombatLogDamage", self)
	Apollo.RegisterEventHandler("CombatLogDeath",					"OnCombatLogDeath", self)
	Apollo.RegisterEventHandler("CombatLogDelayDeath",				"OnCombatLogDelayDeath", self)
	Apollo.RegisterEventHandler("CombatLogDispel",					"OnCombatLogDispel", self)
	Apollo.RegisterEventHandler("CombatLogHeal",					"OnCombatLogHeal", self)
	Apollo.RegisterEventHandler("CombatLogInterrupted",				"OnCombatLogInterrupted", self)
	Apollo.RegisterEventHandler("CombatLogDeflect", 				"OnCombatLogDeflect", self)
	Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor",	"OnCombatLogModifyInterruptArmor", self)
	Apollo.RegisterEventHandler("CombatLogResurrect",				"OnCombatLogResurrect", self)
	Apollo.RegisterEventHandler("CombatLogTransference",			"OnCombatLogTransference", self)

	-- Combat Log
	Apollo.RegisterEventHandler("ChatMessage",						"OnChatMessage", self)

	-- Chat: Shared Logging
	Apollo.RegisterEventHandler("Group_Join",						"OnGroupJoin", self)
	Apollo.RegisterEventHandler("Group_Left",						"OnGroupLeft", self)
	Apollo.RegisterEventHandler("Group_Updated",					"OnGroupUpdated", self)

	Apollo.SetConsoleVariable("cmbtlog.disableOtherPlayers", false)

	-- Load Forms
	self.xmlMainDoc = XmlDoc.CreateFromFile("GalaxyMeter.xml")

	self.wndMain = Apollo.LoadForm(self.xmlMainDoc, "GalaxyMeterForm", nil, self)
	self.wndMain:Show(false)
	self.wndEncList = self.wndMain:FindChild("EncounterList")
	self.wndEncList:Show(false)

	-- Store Child Widgets
	self.Children = {}
	self.Children.TimeText = self.wndMain:FindChild("Time_Text")
	self.Children.DisplayText = self.wndMain:FindChild("Display_Text")
	self.Children.EncounterText = self.wndMain:FindChild("EncounterText")
	self.Children.ModeButton_Left = self.wndMain:FindChild("ModeButton_Left")
	self.Children.ModeButton_Right = self.wndMain:FindChild("ModeButton_Right")
	self.Children.ConfigButton = self.wndMain:FindChild("ConfigButton")
	self.Children.ClearButton = self.wndMain:FindChild("ClearButton")
	self.Children.CloseButton = self.wndMain:FindChild("CloseButton")
	self.Children.EncItemList = self.wndEncList:FindChild("ItemList")

	self.Children.EncounterText:SetText("")
	self.Children.TimeText:SetText("")
	self.Children.DisplayText:SetText("")

	-- Item List
	self.wndItemList = self.wndMain:FindChild("ItemList")

	self.tItems = {}
	self.tEncItems = {}

	-- Display Order (For Reducing On Screen Drawing)
	self.DisplayOrder = {}

	-- Display Timer
	self.timerDisplay = ApolloTimer.Create(0.1, true, "OnDisplayTimer", self)
	self.timerDisplay:Stop()

	-- Player Check Timer
	self.timerPulse = ApolloTimer.Create(1, true, "OnPulse", self)
	self.timerPulse:Stop()

	self.ClassToColor = {
		self:HexToCColor("855513"),	-- Warrior
		self:HexToCColor("cf1518"),	-- Engineer
		self:HexToCColor("c875c4"),	-- Esper
		self:HexToCColor("2cc93f"),	-- Medic
		self:HexToCColor("d7de1f"),	-- Stalker
		self:HexToCColor("ffffff"),	-- Corrupted
		self:HexToCColor("5491e8"),	-- Spellslinger
	}

	-- Handled by Configure
	self.settings = {
		bDebug = false,
		strReportChannel = "g",
	}


	-- Comm Channel
	self.CommChannel = nil
	self.ChannelName = ""


	-- Display Modes, list of mode names, callbacks for display and report, and log subtype indices
	-- TODO Move these into the individual menu builders
	self.tModes = {
		["Main Menu"] = {
			name = "Main Menu",
			display = self.DisplayMainMenu,
			report = nil,
			prev = nil,
			next = self.MenuMainSelection,
			sort = function(a,b) return a.n < b.n end,	-- Aplhabetic sort by mode name
		},
		["Player Damage Done"] = {
			name = "Overall Damage Done",       		-- Display name
			pattern = "Damage done on %s",           	--
			display = self.GetOverallList,
			report = self.ReportGenericList,
			type = "damageDone",
			segType = "players",
			prev = self.MenuPrevious,						-- Right Click, previous menu
			next = self.MenuPlayerSelection,			-- Left Click, next menu
			sort = function(a,b) return a.t > b.t end,
		},
		["Player Damage Taken"] = {
			name = "Overall Damage Taken",
			pattern = "Damage taken from %s",
			display = self.GetOverallList,
			report = self.ReportGenericList,
			type = "damageTaken",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuPlayerSelection,
			sort = function(a,b) return a.t > b.t end,
		},
		["Player Healing Done"] = {
			name = "Overall Healing Done",
			pattern = "Healing Done on %s",
			display = self.GetOverallList,
			report = self.ReportGenericList,
			type = "healingDone",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuPlayerSelection,
			sort = function(a,b) return a.t > b.t end,
		},
		["Player Healing Received"] = {
			name = "Overall Healing Taken",
			pattern = "Healing Taken on %s",
			display = self.GetOverallList,
			report = self.ReportGenericList,
			type = "healingTaken",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuPlayerSelection,
			sort = function(a,b) return a.t > b.t end,
		},
		["Player Damage Done Breakdown"] = {
			name = "%s's Damage Done",
			pattern = "%s's Damage to %s",
			display = self.GetPlayerList,
			report = self.ReportGenericList,
			type = "damageOut",
			prev = self.MenuPrevious,
			next = self.MenuPlayerSpell,
			nextTotal = self.MenuPlayerSpellTotal,
			sort = function(a,b) return a.t > b.t end,
		},
		["Player Damage Taken Breakdown"] = {
			name = "%s's Damage Taken",
			pattern = "%s's Damage Taken from %s",
			display = self.GetPlayerList,
			report = self.ReportGenericList,
			type = "damageIn",
			prev = self.MenuPrevious,
			next = self.MenuPlayerSpell,
			sort = function(a,b) return a.t > b.t end,
		},
		["Player Healing Done Breakdown"] = {
			name = "%s's Healing Done",
			pattern = "%s's Healing Done on %s",
			display = self.GetPlayerList,
			report = self.ReportGenericList,
			type = "healingOut",
			prev = self.MenuPrevious,
			next = self.MenuPlayerSpell,
			sort = function(a,b) return a.t > b.t end,
		},
		["Player Healing Received Breakdown"] = {
			name = "%s's Healing Received",
			pattern = "%s's Healing Received on %s",
			display = self.GetPlayerList,
			report = self.ReportGenericList,
			type = "healingIn",
			prev = self.MenuPrevious,
			next = self.MenuPlayerSpell,
			sort = function(a,b) return a.t > b.t end,
		},
		["Spell Breakdown"] = {
			name = "",
			pattern = "",
			display = self.GetSpellList,
			report = self.ReportGenericList,
			prev = self.MenuPrevious,
			next = nil,
			sort = nil,
		},
		["Player Interrupts"] = {
			name = "Player Interrupts",
			pattern = "Interrupts on %s",
			type = "interrupts",
			segType = "players",
			display = self.GetOverallList,
			report = self.ReportGenericList,
			prev = self.MenuPrevious,
			next = self.MenuPlayerSelection,
			sort = function(a,b) return a.t > b.t end,
		},
		["Interrupt Breakdown"] = {
			name = "%s's Interrupts",
			pattern = "",
			display = self.GetScalarList,
			report = self.ReportGenericList,
			type = "interruptOut",
			prev = self.MenuPrevious,
			next = self.MenuScalarSelection,
			sort = function(a,b) return a.t > b.t end,
		},
		["Deaths"] = {
			name = "Deaths",
			display = nil,
			report = nil,
			--display = self.GetDeathList,
			sort = function(a,b) return a.t > b.t end,
		},
		["Threat"] = {
			name = "Threat",
			display = nil,
			report = nil,
			--display = self.GetThreatList,
			sort = function(a,b) return a.t > b.t end,
		},
		["Dispels"] = {
			name = "Dispels",
			display = nil,
			report = nil,
			--display = self.GetDispelList,
			sort = function(a,b) return a.t > b.t end,
		},
		["Overhealing"] = {
			name = "Overhealing",
			pattern = "%s's Overhealing",
			display = self.GetOverallList,
			report = self.ReportGenericList,
			type = "overheal",
			prev = self.MenuPrevious,
			next = nil,
			sort = function(a,b) return a.t > b.t end,
		},
	}

	self.tMainMenu = {
		["Player Damage Done"] = self.tModes["Player Damage Done"],
		["Player Damage Taken"] = self.tModes["Player Damage Taken"],
		["Player Healing Done"] = self.tModes["Player Healing Done"],
		["Player Healing Received"] = self.tModes["Player Healing Received"],
		["Player Interrupts"] = self.tModes["Player Interrupts"],
		["Deaths"] = self.tModes["Deaths"],
		["Threat"] = self.tModes["Threat"],
		["Dispels"] = self.tModes["Dispels"],
		["Overhealing"] = self.tModes["Overhealing"],
	}

	self.tModeFromSubType = {
		["damageDone"] = self.tModes["Player Damage Done Breakdown"],
		["damageTaken"] = self.tModes["Player Damage Taken Breakdown"],
		["healingDone"] = self.tModes["Player Healing Done Breakdown"],
		["healingTaken"] = self.tModes["Player Healing Received Breakdown"],
		["interrupts"] = self.tModes["Interrupt Breakdown"],
	}

	self.tListFromSubType = {
		["damageDone"] = "damageOut",
		["damageTaken"] = "damageIn",
		["healingDone"] = "healingOut",
		["healingTaken"] = "healingIn",
		["interrupts"] = "interruptOut",
		["interrupted"] = "interruptIn",
	}

	-- Reverse table
	self.tSubTypeFromList = {}
	for k, v in pairs(self.tListFromSubType) do
		self.tSubTypeFromList[v] = k
	end


	-- Quick check if our spell target is a dummy
	self.tIsDummy = {}
	self.tIsDummy["Target Dummy"] = true
	self.tIsDummy["Formidable Target Dummy"] = true
	self.tIsDummy["Weak Target Dummy"] = true


	self.vars = {
		-- modes
		tMode = self.tModes["Main Menu"],   -- Default to Main Menu
		nLogIndex = 0,
		bGrouped = false,
	}

	self.timerPulse:Start()

	self.bNeedNewLog = true
	self:NewLogSegment()

	self.vars.tLogDisplay = self.log[1]

	gLog:info("OnLoad()")

end



function GalaxyMeter:OnConfigure()
	self:ConfigOn()
end


function GalaxyMeter:OnPulseTimer()
	
	local unitPlayer = GameLib.GetPlayerUnit()
	if unitPlayer then
		self.unitPlayer = GameLib.GetPlayerUnit()
		self.unitPlayerId = self.unitPlayer:GetId()
		self.PlayerId = tostring(self.unitPlayerId)
		self.PlayerName = self.unitPlayer:GetName()
		self.PlayerClassId = self.unitPlayer:GetClassId()
	end

	-- Stupid hack to properly set class ids instead of thru unit objects from combat log events
	if self.vars.tLogDisplay then

		local nMemberCount = GroupLib.GetMemberCount()
		if nMemberCount == 0 and unitPlayer and self.vars.tLogDisplay.players[self.PlayerName] then
			self.vars.tLogDisplay.players[self.PlayerName].classId = self.PlayerClassId
		else

			for i = 1, nMemberCount do
				local tMemberInfo = GroupLib.GetGroupMember(i)
				local unitMember = GroupLib.GetUnitForGroupMember(i)

				local strCharName = tMemberInfo.strCharacterName

				if unitMember and self.vars.tLogDisplay.players[strCharName] then
					self.vars.tLogDisplay.players[strCharName].classId = unitMember:GetClassId()
				end

			end
		end
	end


	-- Check if the rest of the group is out of combat
	if self.tCurrentLog.start > 0 then
		if not self:GroupInCombat() and not self.bInCombat then
			gLog:info("OnPlayerCheckTimer pushing combat segment")
			self:PushLogSegment()
		else
			--gLog:info("OnPlayerCheckTimer - Not pushing segment, group in combat")
		end
	else
		--gLog:warn("no log checking timer")
	end

end



-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnTimer
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnDisplayTimer()
	
	self.tCurrentLog.combat_length = os.clock() - self.tCurrentLog.start

	if self.wndMain:IsVisible() and self.vars.tLogDisplay == self.tCurrentLog then

		self.Children.TimeText:SetText(self:SecondsToString(self.vars.tLogDisplay.combat_length))

		--if self.bDirty then
			self:RefreshDisplay()
			self.bDirty = false
		--end
	end
end


-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnChangeWorld
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnChangeWorld()
	-- Restarts Player Check Timer to update Player Id based on New Zone
	self.timerPulse:Start()
end


-- Set self.bInCombat true if any group members are in combat
function GalaxyMeter:GroupInCombat()

	if self.tGroupMembers ~= nil then

        for k, v in pairs(self.tGroupMembers) do
			if v.combat == true and v.name ~= self.PlayerName then
				return true
			end
		end
	end
	
	return false
end

	
function GalaxyMeter:StartLogSegment()

	gLog:info("StartLogSegment()")

	self.tCurrentLog.start = os.clock()

	-- Switch to the newly started segment if logindex is still 0 (which means we're looking at 'current' logs)
	if self.vars.nLogIndex == 0 then
		self.vars.tLogDisplay = self.tCurrentLog
		--self:Rover("StartLogSegment", self.vars)
	end


	self.bDirty = true
	self.bNeedNewLog = false

	self.timerDisplay:Start()
end


function GalaxyMeter:NewLogSegment()
    -- Push a new log entry to the top of the history stack
    local log = {
        start = 0,
        combat_length = 0,
        name = "Current",	-- Segment name
        ["players"] = {},	-- Array containing players involved in this segment
        ["mobs"] = {},		-- Array containing mobs involved in this segment
    }

    if self.log then
        table.insert(self.log, 1, log)
    else
        self.log = {}
        table.insert(self.log, log)
    end

	-- tCurrentLog always points to the segment in progress, even if it hasnt started yet
    self.tCurrentLog = self.log[1]


    if self.vars.nLogIndex == 0 then
        -- If we were looking at the previous current log, set logdisplay to that one because the new blank log hasnt been displayed yet
		-- If logindex is still 0 when starting a new log segment, switch to it
		if self.log[2] then
        	self.vars.tLogDisplay = self.log[2]
		else
			self.vars.tLogDisplay = self.log[1]
		end
    else
        self.vars.nLogIndex = self.vars.nLogIndex + 1
        self.vars.tLogDisplay = self.log[self.vars.nLogIndex]
    end


	self:Rover("NewLogSegment: vars", self.vars)
	self:Rover("log", self.log)
end


-- TODO rename this, the actual 'push' occurs in NewLogSegment
function GalaxyMeter:PushLogSegment()
	gLog:info("Pushing log segment")

    -- Pop off oldest, TODO Add config option to keep N old logs
    if #self.log >= 30 then
        table.remove(self.log)
    end

	self.timerDisplay:Stop()

    self:NewLogSegment()
end


-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnEnteredCombat
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnEnteredCombat(unit, bInCombat)

    -- TODO: Keep track of group members combat status solely using this event?
	
	if unit:GetId() == GameLib.GetPlayerUnit():GetId() then
	
		-- We weren't in combat before, so start new segment
		if not self.bInCombat then
			-- Hm, we shouldnt set this flag if the spell was a heal...
			self.bNeedNewLog = true
            gLog:info("Setting bNeedNewLog = true")
        end
	
		self.bInCombat = bInCombat
	else
		if unit:IsInYourGroup() then
			local playerName = unit:GetName()

			self.tGroupMembers = self.tGroupMembers or {}

			if self.tGroupMembers[playerName] == nil then
				self.tGroupMembers[playerName] = {}
			end

			--gLog:info(string.format("OnEnteredCombat, group member %s combat %s", playerName, tostring(bInCombat)))

			self.tGroupMembers[playerName] = {
				name = playerName,
				id = unit:GetId(),
				class = unit:GetClassId(),
				combat = bInCombat,
			}
		end
	end

	--[[
	self:Rover("UnitEnteredCombat " .. unit:GetName() .. " " .. tostring(bInCombat), {
		self = GameLib.GetPlayerUnit(),
		unit = unit,
	})
	--]]
end


-----------------------------------------------------------------------------------------------
-- GalaxyMeter Functions
-----------------------------------------------------------------------------------------------

function GalaxyMeter:RestoreWindowPosition()
	if self.wndMain and self.settings.anchor ~= nil then
		self.wndMain:SetAnchorOffsets(unpack(self.settings.anchor))
	end
end

-- on SlashCommand "/lkm"
function GalaxyMeter:OnGalaxyMeterOn(strCmd, strArg)

	if strArg == "log" then
		self:PrintPlayerLog()

	elseif strArg == "debug" then
		self.settings.bDebug = not self.settings.bDebug
		gLog:info("bDebug = " .. tostring(self.settings.bDebug))
	elseif strArg == "spellSync" then
		self.settings.bSyncSpells = not self.settings.bSyncSpells
		gLog:info("bSyncSpells = " .. tostring(self.settings.bSyncSpells))
	elseif strArg == "" then

		if self.wndMain:IsVisible() then
			self.settings.anchor = self:Pack(self.wndMain:GetAnchorOffsets())
			self.wndMain:Show(false)
		else
			self:RestoreWindowPosition()

			self.wndMain:Show(true)

			self:RefreshDisplay()
		end
	else
		-- multiple args
		local args = {}
		for arg in strArg:gmatch("%S+") do table.insert(args, arg) end

		if args[1] == "nSyncFreq" and args[2] then
			self.settings.nSyncFrequency = tonumber(args[2])
			gLog:info("nSyncFrequency = " .. self.settings.nSyncFrequency)
		elseif args[1] == "channel" and args[2] then
			self.settings.strReportChannel = args[2]
			gLog:info("Reporting to channel: " .. args[2])
		end

	end
end



-----------------------------------------------------------------------------------------------
-- Group Functions
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnGroupJoin()

	local MemberCount = GroupLib.GetMemberCount()
	if MemberCount == 1 then return nil end
	
	local tTempMembers = {}

    -- What we think is the current list of group members
	self.tGroupMembers = self.tGroupMembers or {}
	
	local GroupLeader = nil
	for i=1, MemberCount do
		local MemberInfo = GroupLib.GetGroupMember(i)

		local charName = MemberInfo.strCharacterName
		
		if MemberInfo.bIsLeader then
			GroupLeader = charName
		end

		if self.tGroupMembers[charName] == nil then
			self.tGroupMembers[charName] = {
				name = charName,
				id = i,	-- What do we use this for?
				combat = false,	-- May cause confusion if someone joins the group while in combat
            }
        end

        table.insert(tTempMembers, charName)
	end
	
	-- Maintain list of current group members
    -- Now remove items in tGroupMembers that don't exist in the temp table
	for p in pairs(self.tGroupMembers) do
		-- If not in temp members, remove
		if tTempMembers[p] ~= nil then

            self.tGroupMembers[p] = nil
		end
	end
	
	self.vars.bGrouped = true
end


function GalaxyMeter:OnGroupLeft()
	self.vars.bGrouped = false
end

function GalaxyMeter:OnGroupUpdated()
	-- They're going to do the exact same thing
	self:OnGroupJoin()
end

-----------------------------------------------------------------------------------------------
-- CombatLogging Functions
-----------------------------------------------------------------------------------------------

function GalaxyMeter:GetTarget()
	-- Safe Target String
	local unitTarget = GameLib.GetTargetUnit()
	if unitTarget then
		return unitTarget:GetName()
	end
	return "Unknown"
end


-- @return Current log, or nil
function GalaxyMeter:GetLog()
	return self.tCurrentLog
end


-- Return log indexed by logdisplay, current segment if logdisplay is 0, or nil
function GalaxyMeter:GetLogDisplay()
	return self.vars.tLogDisplay
end


-- @return LogDisplayPlayerId, or nil
function GalaxyMeter:GetLogDisplayPlayerId()
	return self.vars.tLogDisplay.playerid
end


-- @return LogDisplayTimer, or nil
function GalaxyMeter:GetLogDisplayTimer()
	return self.vars.tLogDisplay.combat_length
end


function GalaxyMeter:SetLogTitle(title)
	if self.tCurrentLog.name == "" then
		self.tCurrentLog.name = title
		if self.tCurrentLog == self.vars.tLogDisplay then
			self.Children.EncounterText:SetText(title)
		end
	end
end


function GalaxyMeter:GetUnitId(unit)
	if unit then
		return tostring(unit:GetId())
	else
		return "0"
	end
end


function GalaxyMeter:GetUnitName(unit)
    if unit then
        return unit:GetName()
    else
        return "Unknown"
    end
end


function GalaxyMeter:OnCombatLogDispel(tEventArgs)
	if self.bDebug then
		gLog:info("OnCombatLogDispel()")
		gLog:info(tEventArgs)
	end
	--[[
	local tCastInfo = self:HelperCasterTargetSpell(tEventArgs, true, true, true)
	tCastInfo.strSpellName = string.format("<T Font=\"%s\">%s</T>", kstrFontBold, tCastInfo.strSpellName)
	local strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.strCaster, tCastInfo.strSpellName, tCastInfo.strTarget)

	local strAppend = Apollo.GetString("CombatLog_DispelSingle")
	if tEventArgs.bRemovesSingleInstance then
		strAppend = Apollo.GetString("CombatLog_DispelMultiple")
	end

	local tSpellCount =
	{
		["name"] = Apollo.GetString("CombatLog_SpellUnknown"),
		["count"] = tEventArgs.nInstancesRemoved
	}

	local strArgRemovedSpellName = tEventArgs.splRemovedSpell:GetName()
	if strArgRemovedSpellName and strArgRemovedSpellName~= "" then
		tSpellCount["name"] = strArgRemovedSpellName
	end

	strResult = String_GetWeaselString(strAppend, strResult, tSpellCount)
	self:PostOnChannel(string.format("<T TextColor=\"%s\">%s</T>", tCastInfo.strColor, strResult))
	--]]
end


function GalaxyMeter:OnCombatLogInterrupted(tEventArgs)
	--gLog:info("OnCombatLogInterrupted()")
	--gLog:info(tEventArgs)

	self:Rover("Interrupted", tEventArgs)

	local tInfo = self:HelperCasterTargetSpell(tEventArgs, true, true)

	local tEvent = {}
	tEvent.Caster = tInfo.strCaster	-- Caster of the interrupting spell
	tEvent.CasterId = tInfo.nCasterId
	tEvent.CasterType = tInfo.strCasterType
	tEvent.Target = tInfo.strTarget -- Target of the interrupting spell
	tEvent.CasterId = tInfo.nCasterId
	tEvent.TargetType = tInfo.strTargetType
	tEvent.CasterClassId = tInfo.nCasterClassId
	tEvent.TargetClassId = tInfo.nTargetClassId

	tEvent.Deflect = false
	tEvent.CastResult = tEventArgs.eCastResult
	tEvent.Result = tEventArgs.eCombatResult

	tEvent.PlayerName = self.PlayerName

	-- if bCaster then player class is caster class, otherwise its the target class
	tEvent.bCaster = (tInfo.strCasterType ~= "NonPlayer")

	-- Spell that was casting and got interrupted
	tEvent.SpellName = tInfo.strSpellName

	-- Spell that interrupted the casting spell
	tEvent.strInterruptingSpell = tEventArgs.splInterruptingSpell:GetName()

	self:UpdatePlayerInterrupt(tEvent)

end


function GalaxyMeter:OnCombatLogModifyInterruptArmor(tEventArgs)

	if self.bDebug then
		gLog:info("OnCombatLogModifyInterruptArmor()")
		gLog:info(tEventArgs)
	end

	--[[
	local tCastInfo = self:HelperCasterTargetSpell(tEventArgs, true, true, true)
	tCastInfo.strSpellName = string.format("<T Font=\"%s\">%s</T>", kstrFontBold, tCastInfo.strSpellName)
	local strArmorCount = string.format("<T TextColor=\"white\">%d</T>", tEventArgs.nAmount)

	local strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.strCaster, tCastInfo.strSpellName, tCastInfo.strTarget)
	strResult = String_GetWeaselString(Apollo.GetString("CombatLog_InterruptArmor"), strResult, strArmorCount)
	if tEventArgs.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), strResult)
	end
	self:PostOnChannel(string.format("<T TextColor=\"%s\">%s</T>", tCastInfo.strColor, strResult))
	--]]
end


function GalaxyMeter:OnCombatLogCCStateBreak(tEventArgs)
	if self.bDebug then
		gLog:info("OnCombatLogCCStateBreak()")
		gLog:info(tEventArgs)
	end
	--[[
	local strBreak = String_GetWeaselString(Apollo.GetString("CombatLog_CCBroken"), tEventArgs.strState)
	self:PostOnChannel(string.format("<P TextColor=\"%s\">%s</P>", kstrStateColor, strBreak))
	--]]
end


function GalaxyMeter:OnCombatLogDelayDeath(tEventArgs)
	if self.bDebug then
		gLog:info("OnCombatLogDelayDeath()")
		gLog:info(tEventArgs)
	end
	--[[
	local tCastInfo = self:HelperCasterTargetSpell(tEventArgs, false, true)
	local strSaved = String_GetWeaselString(Apollo.GetString("CombatLog_NotDeadYet"), tCastInfo.strCaster, tCastInfo.strSpellName)
	self:PostOnChannel(string.format("<P TextColor=\"%s\">%s</P>", kstrStateColor, strSaved))
	--]]
end


function GalaxyMeter:OnCombatLogDeath(tEventArgs)
	if self.bDebug then
		gLog:info("OnCombatLogDeath()")
		gLog:info(tEventArgs)
		self:Rover("CLDeath", tEventArgs)
	end

	if tEventArgs.unitCaster then
		if tEventArgs.unitCaster:GetId() == self.unitPlayer:GetId() then

		end
	end
end


function GalaxyMeter:OnCombatLogAbsorption(tEventArgs)
	if self.bDebug then
		gLog:info("OnCombatLogAbsorption()")
		gLog:info(tEventArgs)
	end
end


function GalaxyMeter:OnCombatLogResurrect(tEventArgs)
end


function GalaxyMeter:OnCombatLogTransference(tEventArgs)
	-- OnCombatLogDamage does exactly what we need so just pass along the tEventArgs
	self:OnCombatLogDamage(tEventArgs)

	if self.bDebug then
		gLog:info("OnCombatLogTransference()")
		gLog:info(tEventArgs)
	end

	--[[
	local tCastInfo = self:HelperCasterTargetSpell(tEventArgs, true, false)
	-- healing data is stored in a table where each subtable contains a different vital that was healed
	for _, tHeal in ipairs(tEventArgs.tHealData) do
		local strVital = Apollo.GetString("CombatLog_UnknownVital")
		if tHeal.eVitalType then
			strVital = Unit.GetVitalTable()[tHeal.eVitalType]["strName"]
		end

		local strAmount = string.format("<T TextColor=\"%s\">%s</T>", self.crVitalModifier, tHeal.nHealAmount)
		local strResult = String_GetWeaselString(Apollo.GetString("CombatLog_GainVital"), tCastInfo.strCaster, strAmount, strVital, tCastInfo.strTarget)

		if tHeal.nOverheal and tHeal.nOverheal > 0 then
			local strOverhealString = ""
			if tHeal.eVitalType == GameLib.CodeEnumVital.ShieldCapacity then
				strOverhealString = Apollo.GetString("CombatLog_Overshield")
			else
				strOverhealString = Apollo.GetString("CombatLog_Overheal")
			end
			strAmount = string.format("<T TextColor=\"white\">%s</T>", tHeal.nOverheal)
			strResult = String_GetWeaselString(strOverhealString, strResult, strAmount)
		end

		if tEventArgs.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
			strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), strResult)
		end

		if not self.unitPlayer then
			self.unitPlayer = GameLib.GetControlledUnit()
		end

		-- TODO: Analyze if we can refactor (this has no spell)
		local strColor = kstrColorCombatLogIncomingGood
		if tEventArgs.unitCaster ~= self.unitPlayer then
			strColor = kstrColorCombatLogOutgoing
		end
		self:PostOnChannel(string.format("<T TextColor=\"%s\">%s</T>", strColor, strResult))
	end
	--]]
end


function GalaxyMeter:OnCombatLogDeflect(tEventArgs)

	-- An error may occur here where tEventArgs is nil??

	local tInfo = self:HelperCasterTargetSpell(tEventArgs, true, true)

	local tEvent = {}
	tEvent.Caster = tInfo.strCaster
	tEvent.CasterType = tInfo.strCasterType
	tEvent.Target = tInfo.strTarget
	tEvent.TargetType = tInfo.strTargetType
	tEvent.SpellName = tInfo.strSpellName
	tEvent.CasterClassId = tInfo.nCasterClassId
	tEvent.TargetClassId = tInfo.nTargetClassId

	tEvent.Damage = 0
	tEvent.Deflect = true
	tEvent.Result = tEventArgs.eCombatResult
	tEvent.PlayerName = self.PlayerName

	-- Guarantee that unitCaster and unitTarget exist
	if not tEventArgs.unitCaster or not tEventArgs.unitTarget then
		self:Rover("CLDeflect:error", tEventArgs)
		gLog:error("OnCLDeflect - nil caster or target")
		return
	end

	tEvent.TypeId = self:GetDamageEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	-- Should we trigger a new log segment?
	if self.bNeedNewLog then
		self:StartLogSegment()

		-- Figure out the name of this new log segment
		if tEventArgs.unitTarget:GetType() == "NonPlayer" then
			self.tCurrentLog.name = tEvent.Target
		else
			if tEventArgs.unitTarget:GetTarget() then
				self.tCurrentLog.name = tEventArgs.unitTarget:GetTarget():GetName()
			else
				-- Winter Beta Patch 3, unitTarget:GetTarget() started returning nil
				self.tCurrentLog.name = "Unknown"
			end
		end

		gLog:info(string.format("OnDeflect: Set activeLog.name to %s", self.tCurrentLog.name))
	end

	self:UpdatePlayerSpell(tEvent)
end


function GalaxyMeter:OnCombatLogDamage(tEventArgs)
	self:Rover("CombatLogDamage", tEventArgs)

	local tInfo = self:HelperCasterTargetSpell(tEventArgs, true, true)

	local tEvent = {}
	tEvent.Caster = tInfo.strCaster
	tEvent.CasterType = tInfo.strCasterType
	tEvent.Target = tInfo.strTarget
	tEvent.TargetType = tInfo.strTargetType
	tEvent.SpellName = tInfo.strSpellName
	tEvent.CasterClassId = tInfo.nCasterClassId
	tEvent.TargetClassId = tInfo.nTargetClassId

	tEvent.Deflect = false
	tEvent.DamageRaw = tEventArgs.nRawDamage
	tEvent.Shield = tEventArgs.nShield
	tEvent.Absorb = tEventArgs.nAbsorption
	tEvent.Periodic = tEventArgs.bPeriodic
	tEvent.Vulnerable = tEventArgs.bTargetVulnerable
	tEvent.Overkill = tEventArgs.nOverkill
	tEvent.Result = tEventArgs.eCombatResult
	tEvent.DamageType = tEventArgs.eDamageType
	tEvent.EffectType = tEventArgs.eEffectType

	tEvent.PlayerName = self.PlayerName

	-- if bCaster then player class is caster class, otherwise its the target class
	tEvent.bCaster = (tInfo.strCasterType ~= "NonPlayer")

	if self:ShouldThrowAwayDamageEvent(tEventArgs.unitCaster, tEventArgs.unitTarget) then
		return
	end

	-- Guarantee that unitCaster and unitTarget exist
	if not tEventArgs.unitCaster or not tEventArgs.unitTarget then
		self:Rover("CLDamage:error", tEventArgs)
		gLog:error("OnCLDamage - nil caster or target")
		return
	end

	-- Workaround for players dealing a severely reduced damage to target dummies
	if self.tIsDummy[tEvent.Target] then
		if not tEventArgs.nRawDamage then
			gLog:error(string.format("nRawDamage nil for %s", tEvent.SpellName or "Unknown"))
			tEvent.Damage = tEventArgs.nDamageAmount
		else
			tEvent.Damage = tEventArgs.nRawDamage
		end
	else
		tEvent.Damage = tEventArgs.nDamageAmount
	end

	tEvent.TypeId = self:GetDamageEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	-- Should we trigger a new log segment?
	if self.bNeedNewLog then
		self:StartLogSegment()

		if tEventArgs.unitTarget:GetType() == "NonPlayer" then
			self.tCurrentLog.name = tEvent.Target
		else
			-- So attacking plants sometimes returns not NonPlayer, with a nil targettarget
			if tEventArgs.unitTarget:GetTarget() then
				self.tCurrentLog.name = tEventArgs.unitTarget:GetTarget():GetName()
			else
				self.tCurrentLog.name = "Unknown"
			end
		end
		gLog:info(string.format("OnCLDamage: Set activeLog.name to %s", self.tCurrentLog.name))
	end

	if tEvent.TypeId > 0 and tEvent.Damage then
		self:UpdatePlayerSpell(tEvent)
	else
		gLog:error(string.format("OnCLDamage: Something went wrong!  Invalid type Id %d, dmg raw %d, dmg %d", tEvent.TypeId, tEventArgs.nRawDamage, tEventArgs.nDamageAmount))

	end

	-- Count pet actions as actions of the player, done after UpdateSpell because AddPlayer sets CasterClassId to CombatEvent.Caster
	if not tEventArgs.unitCaster then
		--gLog:info(string.format("Pet Damage, set CasterID to %s", CombatEvent.CasterId))
		event.CasterClassId = self.unitPlayer:GetClassId()
	end
end


function GalaxyMeter:OnCombatLogHeal(tEventArgs)
	self:Rover("CombatLogHeal", tEventArgs)

	local tInfo = self:HelperCasterTargetSpell(tEventArgs, true, true)

	local tEvent = {}
	tEvent.Caster = tInfo.strCaster
	tEvent.CasterType = tInfo.strCasterType
	tEvent.Target = tInfo.strTarget
	tEvent.TargetType = tInfo.strTargetType
	tEvent.SpellName = tInfo.strSpellName
	tEvent.CasterClassId = tInfo.nCasterClassId
	tEvent.targetClassId = tInfo.nTargetClassId

	tEvent.Deflect = false
	--tEvent.DamageRaw = tEventArgs.nRawDamage
	tEvent.Damage = tEventArgs.nHealAmount
	--tEvent.Shield = tEventArgs.nShield
	--tEvent.Absorb = tEventArgs.nAbsorption
	--tEvent.Periodic = tEventArgs.bPeriodic
	tEvent.Overheal = tEventArgs.nOverheal
	tEvent.Result = tEventArgs.eCombatResult

	tEvent.EffectType = tEventArgs.eEffectType

	-- Temporary hack until we switch to checking spell effect type instead of tEvent.DamageType
	if tEventArgs.eEffectType == Spell.CodeEnumSpellEffectType.Heal then
		tEvent.DamageType = GameLib.CodeEnumDamageType.Heal
	elseif tEventArgs.eEffectType == Spell.CodeEnumSpellEffectType.HealShields then
		tEvent.DamageType = GameLib.CodeEnumDamageType.HealShields
	end

	tEvent.PlayerName = self.PlayerName

	tEvent.TypeId = self:GetHealEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	if tEvent.TypeId > 0 and tEvent.Damage then
		self:UpdatePlayerSpell(tEvent)
	else
		gLog:error("OnCLHeal: Something went wrong!  Invalid type Id!")
		return
	end
end


function GalaxyMeter:HelperCasterTargetSpell(tEventArgs, bTarget, bSpell)
	local tInfo = {
		strCaster = nil,
		strTarget = nil,
		strSpellName = nil,
		strColor = nil,
		strCasterType = nil,
		strTargetType = nil,
		nCasterClassId = nil,
		nTargetClassId = nil,
		nCasterId = nil,
		nTargetId = nil,
	}

	if bSpell then
		tInfo.strSpellName = self:HelperGetNameElseUnknown(tEventArgs.splCallingSpell)
		if tEventArgs.bPeriodic then
			tInfo.strSpellName = tInfo.strSpellName .. " (Dot)"
		end
	end

	-- TODO It's probably better to detect pets by using unitCaster/TargetOwner
	if tEventArgs.unitCaster then
		tInfo.nCasterId = tEventArgs.unitCaster:GetId()
		tInfo.strCasterType = tEventArgs.unitCaster:GetType()

		-- Count pets as damage done by the player
		if tInfo.strCasterType == "Pet" then
			--gLog:info(string.format("Pet Damage, set CasterID to %s", nCasterId))

			-- Prepend pet name to the spell name
			tInfo.strSpellName = string.format("%s: %s", tEventArgs.unitCaster:GetName(), tInfo.strSpellName)

			tInfo.strCaster = self.PlayerName
			tInfo.nCasterClassId = GameLib:GetPlayerUnit():GetClassId()

		else

			tInfo.strCaster = self:HelperGetNameElseUnknown(tEventArgs.unitCaster)
			if tEventArgs.unitCasterOwner and tEventArgs.unitCasterOwner:GetName() then
				tInfo.strCaster = string.format("%s (%s)", tInfo.strCaster, tEventArgs.unitCasterOwner:GetName())
			end

			tInfo.nCasterClassId = tEventArgs.unitCaster:GetClassId()
		end

	else
		local nTargetId = self:GetUnitId(tEventArgs.unitTarget)
		local strTarget = self:GetUnitName(tEventArgs.unitTarget)

		-- Hack to fix Pets sometimes having no unitCaster
		gLog:warn(string.format("HelperCasterTargetSpell unitCaster nil(pet?): Caster[%d] %s, Target[%d] %s",
			0, "Unknown", nTargetId, strTarget))

		-- Set caster to our player name
		tInfo.strCaster = self.PlayerName

		-- Set class id to player class
		-- This is only needed if the caster doesn't exist yet in the log, to properly set the class if a pet
		-- initiates combat
		tInfo.nCasterClassId = GameLib:GetPlayerUnit():GetClassId()
	end

	if bTarget then
		tInfo.strTarget = self:HelperGetNameElseUnknown(tEventArgs.unitTarget)
		if tEventArgs.unitTargetOwner and tEventArgs.unitTargetOwner:GetName() then
			tInfo.strTarget = string.format("%s (%s)", tInfo.strTarget, tEventArgs.unitTargetOwner:GetName())
		end

		if tEventArgs.unitTarget then
			tInfo.nTargetId = tEventArgs.unitTarget:GetId()
			tInfo.strTargetType = tEventArgs.unitTarget:GetType()
			tInfo.nTargetClassId = tEventArgs.unitTarget:GetClassId()
		else
			tInfo.strTargetType = "Unknown"
			-- Uhh? no target, no idea what to set classid to
			gLog:warn(string.format("** nil unitTarget, caster '%s', strTarget '%s', spell '%s'", tInfo.strCaster, tInfo.strTarget, tInfo.strSpellName))
		end


		--if bColor then
		--	tInfo.strColor = self:HelperPickColor(tEventArgs)
		--end
	end

	return tInfo
end


function GalaxyMeter:HelperGetNameElseUnknown(nArg)
	if nArg and nArg:GetName() then
		return nArg:GetName()
	end
	return Apollo.GetString("CombatLog_SpellUnknown")
end


function GalaxyMeter:ShouldThrowAwayDamageEvent(unitCaster, unitTarget)
    if unitTarget then

        -- Don't display damage taken by pets (yet)
        if unitTarget:GetType() == "Pet" then
            --gLog:info(string.format("Ignore pet Dmg Taken, Caster: %s, Target: %s, Spell: %s", CombatEvent.Caster, CombatEvent.Target, nSpellId))

            return true

        -- Don't log damage taken (yet)
		--[[
        elseif unitTarget:GetName() == self.PlayerName then

            --gLog:info(string.format("Scrap DmgTaken event, Type: %d, Caster: %s, Target: %s, Spell: %s",
            --    CombatEvent.DamageType, CombatEvent.Caster, CombatEvent.Target, CombatEvent.SpellId))

            return true
		--]]
        else
            return false
        end

    else
        -- Keep events with no unitCaster for now because they may still be determined useful
        return false
    end
end


-- Determine the type of heal based on the caster and target
-- TODO This is only called from OnDamageOrHealingDone, refactor this
function GalaxyMeter:GetHealEventType(unitCaster, unitTarget)

    --local playerUnit = GameLib.GetPlayerUnit()


	if not self.unitPlayer then
		gLog:error("GetHealEventType: self.unitPlayer is nil!")
		return 0
	end


	if not unitTarget or not unitCaster then
		gLog:error(string.format("GetHealEventType() nil unitTarget or caster, caster[%d] %s",
			self:GetUnitId(unitCaster), self:GetUnitName(unitCaster)))
		return 0
	end

	local selfId = self.unitPlayer:GetId()

    if unitCaster:GetId() == selfId then

        if unitTarget:GetId() == selfId then
            return eTypeDamageOrHealing.PlayerHealingInOut
        end

        return eTypeDamageOrHealing.PlayerHealingOut

    elseif unitTarget:GetId() == selfId then
        return eTypeDamageOrHealing.PlayerHealingIn

    else
        -- It's possible for your pet to heal other people?!

        gLog:warn(string.format("Unknown Heal - Caster: %s, Target: %s", self:GetUnitName(unitCaster), self:GetUnitName(unitTarget)))

        return eTypeDamageOrHealing.PlayerHealingOut
    end
end


function GalaxyMeter:GetDamageEventType(unitCaster, unitTarget)
    --local playerUnit = GameLib.GetPlayerUnit()

    if self.settings.bDebug then
        if not self.unitPlayer then
            gLog:warn("GetDamageEventType: self.unitPlayer is nil!")
			return 0
        end
	end

	local selfId = self.unitPlayer:GetId()

	self:Rover("GetDmgType", {selfId = selfId, casterId = unitCaster:GetId(), targetId = unitTarget:GetId()})

    if unitTarget:GetId() == selfId then

        if unitCaster:GetId() == selfId then
            return eTypeDamageOrHealing.PlayerDamageInOut
        end

        return eTypeDamageOrHealing.PlayerDamageIn
	else


		-- Ok so the dmg might be from a pet
		if unitCaster:GetId() == selfId or (unitCaster:GetUnitOwner() and unitCaster:GetUnitOwner():GetId() == selfId) then
		-- This is being set when the caster is not yourself

       		return eTypeDamageOrHealing.PlayerDamageOut
		else

			gLog:error("Unknown dmg type")
		end
    end
end


-- Look up player by name
function GalaxyMeter:FindMob(tLog, strMobName)
    return tLog[strMobName]
end


-- Find or create player data table
-- @return Player data table
function GalaxyMeter:GetMob(tLog, tEvent)

    local strMobName = tEvent.Caster

    local mob = self:FindMob(tLog, strMobName)

    if not mob then
        mob = {
            -- Info
            name = strMobName,                      -- Name
            id = tEvent.PlayerId,                   -- GUID?
            classId = tEvent.CasterClassId,         -- Class Id

            -- Totals
            damageDone = 0,                         -- Total Damage Done
            damageTaken = 0,                        -- Total Damage Taken
            healingDone = 0,                        -- Total Healing Done
            healingTaken = 0,                       -- Total Healing Taken

            -- Spells
            damageIn = {},                          -- Damage Taken
            damageOut = {},                         -- Damage Done
            healingIn = {},                         -- Healing Taken
            healingOut = {},                        -- Healing Done

            -- Targets
            damaged = {},
            healed = {},
        }

        tLog[strMobName] = mob
    end

	--[[
    self:Rover("tCurrentLog: GetMob", tLog)
    self:Rover("tEvent: GetMob", tEvent)
	--]]

    return mob
end

-- Look up player by name
function GalaxyMeter:FindPlayer(tLog, playerName)
    return tLog[playerName]
end


-- Find or create player data table
-- @return Player data table
function GalaxyMeter:GetPlayer(tLog, tEvent)

	-- This is the only place where tEvent.PlayerName is used, refactor!
    local playerName = tEvent.PlayerName

    local player = tLog[playerName]

    if not player then
        player = {
            -- Info
            playerName = playerName,                -- Player name
            playerId = tEvent.PlayerId,             -- Player GUID?

			-- How do we tell if the player is the caster or target?
            --classId = tEvent.CasterClassId,         -- Player Class Id

            -- Totals
            damageDone = 0,                         -- Total Damage Done
            damageTaken = 0,                        -- Total Damage Taken
            healingDone = 0,                        -- Total Healing Done
            healingTaken = 0,                       -- Total Healing Taken

            -- Spells
            damageIn = {},                          -- Damage Taken
            damageOut = {},                         -- Damage Done
            healingIn = {},                         -- Healing Taken
            healingOut = {},                        -- Healing Done

			-- Targets
			damaged = {},
			healed = {},
		}

		--[[
		if tEvent.bCaster then
			player.classId = tEvent.CasterClassId
		else
			player.classId = tEvent.TargetClassId
		end

		if not player.classId then
			gLog:error("nil classId in GetPlayer")
		end
		--]]

        tLog[playerName] = player
    end

    return player
end


-- Find and return spell from spell type table, will create the spell entry if it doesn't exist
-- @param tSpellTypeLog reference to specific spell type table, ie log.players["guy"].damageOut
-- @return Spell data table
function GalaxyMeter:GetSpell(tSpellTypeLog, spellName)

    --gLog:info(string.format("GetSpell(tSpellTypeLog, %s)", spellName))

    if not tSpellTypeLog[spellName] then
        tSpellTypeLog[spellName] = {

            -- Info
            name = spellName,

            -- Counters
            castCount = 0,              -- total number of hits, includes crits
            critCount = 0,              -- total number of crits
            deflectCount = 0,

            -- Totals
            total = 0,                  -- total damage, totalNormal + totalCrit
            totalCrit = 0,              -- total damage from crits
            totalShield = 0,            -- damage or healing done to shields
            totalAbsorption = 0,        --
            avg = 0, avgCrit = 0,
        }
    end

    return tSpellTypeLog[spellName]
end


--
function GalaxyMeter:TallySpellAmount(tEvent, tSpell)

	-- Spell total casts, all hits crits and misses
	tSpell.castCount = tSpell.castCount + 1

	if tEvent.Deflect then
		tSpell.deflectCount = tSpell.deflectCount + 1
		-- We're done here, move along
		return
	end

	if tEvent.Overheal then
		tSpell.overheal = (tSpell.overheal or 0) + tEvent.Overheal
	end

	if not tSpell.dmgType then tSpell.dmgType = tEvent.DamageType end

    -- Shield Absorption - Total damage includes dmg done to shields while spell breakdowns dont
    if tEvent.ShieldAbsorbed and tEvent.ShieldAbsorbed > 0 then
        tSpell.totalShield = tSpell.totalShield + tEvent.ShieldAbsorbed

        -- TODO Option to record shield damage into the total accumulation, or seperate totalShields
		tSpell.total = tSpell.total + tEvent.ShieldAbsorbed
    end

    -- Absorption
    if tEvent.AbsorptionAmount and tEvent.AbsorptionAmount > 0 then
        tSpell.totalAbsorption = tSpell.totalAbsorption + tEvent.AbsorptionAmount

        tSpell.total = tSpell.total + tEvent.AbsorptionAmount
	end

	local nAmount = tEvent.Damage or 0

	if nAmount > 0 then

		-- Spell Total
		tSpell.total = tSpell.total + nAmount

		-- Crits
		if tEvent.Result == GameLib.CodeEnumCombatResult.Critical then
			tSpell.critCount = tSpell.critCount + 1
			tSpell.totalCrit = tSpell.totalCrit + nAmount
			tSpell.avgCrit = tSpell.totalCrit / tSpell.critCount
		end

		-- Dmg while vulnerable
		if tEvent.Vulnerable then
			tSpell.vulnCount = (tSpell.vulnCount or 0) + 1
			tSpell.totalVuln = (tSpell.totalVuln or 0) + nAmount
			tSpell.avgVuln = tSpell.totalVuln / tSpell.vulnCount
		end

		-- Average of ALL non deflected damage
		tSpell.avg = tSpell.total / (tSpell.castCount - tSpell.deflectCount)

		if not tSpell.max or nAmount > tSpell.max then
			tSpell.max = nAmount
		end

		if not tSpell.min or nAmount < tSpell.min then
			tSpell.min = nAmount
		end

	end
end



function GalaxyMeter:UpdatePlayerInterrupt(tEvent)

	-- Do we care about the interrupting spell?
	-- If it was a spell that did damage then it would be logged by the damage handler
	local strSpellName = tEvent.strInterruptingSpell
	local activeLog = self.tCurrentLog.players

	local player = self:GetPlayer(activeLog, tEvent)

	local playerId = GameLib.GetPlayerUnit():GetId()

	local spell = nil

	if tEvent.CasterId == playerId and tEvent.TargetId == playerId then
		gLog:info("Self interrupt?")

		--player.interrupts = (player.interrupts or 0) + 1
		--player.interrupted = (player.interrupted or 0) + 1

	elseif tEvent.CasterId == playerId then
		--gLog:info("Player interrupted " .. tEvent.Target)
		player.interrupts = (player.interrupts or 0) + 1
		player.interruptOut = player.interruptOut or {}

		player.interruptOut[tEvent.Target] = player.interruptOut[tEvent.Target] or {}

		local target = player.interruptOut[tEvent.Target]

		if not target[tEvent.SpellName] then
			target[tEvent.SpellName] = 1
		else
			target[tEvent.SpellName] = target[tEvent.SpellName] + 1
		end

	elseif tEvent.TargetId == playerId then
		gLog:info("Target interrupted")

		player.interrupted = (player.interrupted or 0) + 1
		player.interruptIn = player.interruptIn or {}

		player.interruptIn[tEvent.Caster] = player.interruptIn[tEvent.Caster] or {}

		local target = player.interruptIn[tEvent.Caster]

		if not target[tEvent.SpellName] then
			target[tEvent.SpellName] = 1
		else
			target[tEvent.SpellName] = target[tEvent.SpellName] + 1
		end

	end

	player.lastAction = os.clock()

	--[[
	if spell then
		self:TallySpellAmount(tEvent, spell)	-- only used for castCount
		self.bDirty = true
	end
	--]]

end


function GalaxyMeter:UpdatePlayerSpell(tEvent)
    local CasterId = tEvent.CasterId
    local spellName = tEvent.SpellName
    local casterType = tEvent.CasterType
    local nAmount = tEvent.Damage
    local activeLog = nil

	if not nAmount and not tEvent.Deflect then
		gLog:error("UpdatePlayerSpell: nAmount is nil, spell: " .. spellName)
		self:Rover("nil nAmount Spell", tEvent)
		return
	end

	activeLog = self.tCurrentLog.players

    -- Finds existing or creates new player entry
    -- Make sure CombatEvent.classid is properly set to the player if their pet used a spell!!!
    local player = self:GetPlayer(activeLog, tEvent)

	--[[
	if not player.classId then
		gLog:error(string.format("nil classId for player %s, spell %s", player.playerName, spellName))
	end
	--]]

    local spell = nil

    -- Player tally and spell type
    -- TODO Generalize this comparison chain
	if tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingInOut then

        -- Special handling for self healing, we want to count this as both healing done and received
        -- Maybe add option to enable tracking for this

        player.healingDone = player.healingDone + nAmount
        player.healingTaken = player.healingTaken + nAmount
		player.healed[tEvent.Target] = (player.healed[tEvent.Target] or 0) + nAmount

		if tEvent.Overheal > 0 then
			player.overheal = (player.overheal or 0) + tEvent.Overheal
		end

        local spellOut = self:GetSpell(player.healingOut, spellName)
        local spellIn = self:GetSpell(player.healingIn, spellName)

        self:TallySpellAmount(tEvent, spellOut)
        self:TallySpellAmount(tEvent, spellIn)

		self.bDirty = true

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingOut then
        player.healingDone = player.healingDone + nAmount
		player.healed[tEvent.Target] = (player.healed[tEvent.Target] or 0) + nAmount

		if tEvent.Overheal > 0 then
			player.overheal = (player.overheal or 0) + tEvent.Overheal
		end

        spell = self:GetSpell(player.healingOut, spellName)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingIn then
        player.healingTaken = player.healingTaken + nAmount

        spell = self:GetSpell(player.healingIn, spellName)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageInOut then

        -- Another special case where the spell we cast also damaged ourself?
        player.damageDone = player.damageDone + nAmount
        player.damageTaken = player.damageTaken + nAmount
		player.damaged[tEvent.Target] = (player.damaged[tEvent.Target] or 0) + nAmount

        local spellOut = self:GetSpell(player.damageOut, spellName)
        local spellIn = self:GetSpell(player.damageIn, spellName)

        self:TallySpellAmount(tEvent, spellOut)
        self:TallySpellAmount(tEvent, spellIn)

		self.bDirty = true

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageOut then
		if not tEvent.Deflect then
        	player.damageDone = player.damageDone + nAmount
			player.damaged[tEvent.Target] = (player.damaged[tEvent.Target] or 0) + nAmount
		end

        spell = self:GetSpell(player.damageOut, spellName)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageIn then
		if not tEvent.Deflect then
        	player.damageTaken = player.damageTaken + nAmount
		end

        spell = self:GetSpell(player.damageIn, spellName)

	else
		self:Rover("UpdatePlayerSpell Error", tEvent)
        gLog:error("Unknown type in UpdatePlayerSpell!")
        gLog:error(string.format("Spell: %s, Caster: %s, Target: %s, Amount: %d",
            spellName, tEvent.Caster, tEvent.Target, nAmount or 0))

		-- spell should be null here, safe to continue on...
    end

    if spell then
		player.lastAction = os.clock()
        self:TallySpellAmount(tEvent, spell)
		self.bDirty = true
    end

end


-----------------------------------------------------------------------------------------------
-- Combat Logging
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnChatMessage(channelCurrent, bAutoResponse, bGM, bSelf, strSender, strRealmName, nPresenceState, arMessageSegments, unitSource, bShowChatBubble, bCrossFaction)
	local eChannelType = channelCurrent:GetType()

	if eChannelType ~= ChatSystemLib.ChatChannel_Combat then return end

	-- Concat all segments
	local tMessage = {}
	self:Rover("arMessage", arMessageSegments)
	for i = 1, #arMessageSegments do
		table.insert(tMessage, arMessageSegments[i].strText)
	end

	local strMessage = table.concat(tMessage)

	-- Ignore non combat crap that is polluting the *combat* log
	if string.find(strMessage, "Font") or string.find(strMessage, "XP") or string.find(strMessage, "reputation") then
		return
	end

	-- Create log entry
	-- Unfortunately we have no timestamp from when the event actually occurred, so this must suffice
	local tm = GameLib.GetLocalTime()
	local tNewLogEntry = {
		nClockTime = os.clock(),
		strTime = string.format("%d:%02d:%02d", tm.nHour, tm.nMinute, tm.nSecond),
		strMessage = strMessage,
	}

	-- Find player log
	-- TODO This only works now because the combat log only shows information pertinent to yourself
	local tLogSegment = self.vars.tLogDisplay
	local strPlayerName = self.vars.strCurrentPlayerName

	if strPlayerName == nil or strPlayerName == "" then
		return
	end

	local tPlayerLog = tLogSegment[self.vars.strCurrentLogType][strPlayerName]

	tPlayerLog.log = tPlayerLog.log or Queue.new()

	local log = tPlayerLog.log

	-- Append latest
	Queue.PushRight(log, tNewLogEntry)

	-- Remove non-recent events (10 second window for now)
	local nTimeThreshold = tNewLogEntry.nClockTime - 10
	
	while log[log.first].nClockTime < nTimeThreshold do
		Queue.PopLeft(log)
	end

end


function GalaxyMeter:PrintPlayerLog()
	-- Find player log
	local tLogSegment = self.vars.tLogDisplay
	local strPlayerName = self.vars.strCurrentPlayerName

	if strPlayerName == nil or strPlayerName == "" then
		return
	end

	local tPlayerLog = tLogSegment[self.vars.strCurrentLogType][strPlayerName]

	tPlayerLog.log = tPlayerLog.log or Queue.new()

	local log = tPlayerLog.log

	if log.last < log.first then return end

	for i = log.first, log.last do
		gLog:info(string.format("%s> %s", log[i].strTime, log[i].strMessage))
	end
end



-----------------------------------------------------------------------------------------------
-- List Generators
--
-- TODO These are pretty similar... Consider refactoring them into a more generic method
-----------------------------------------------------------------------------------------------

function GalaxyMeter:GetScalarList()
	local tList = {}

	-- These should have already been set
	local tLogSegment = self.vars.tLogDisplay
	local strPlayerName = self.vars.strCurrentPlayerName
	local tPlayerLog = tLogSegment[self.vars.strCurrentLogType][strPlayerName]
	local mode = self.vars.tMode

	-- convert to interruptIn/Out
	local strListTypeTotal = self.tSubTypeFromList[mode.type]

	-- count of all totals from all sublists
	local tTotal = {
		n = string.format("%s's %s", strPlayerName, mode.type),
		--t = tPlayerLog[dmgTypeTotal],
		t = 0,
		c = kDamageStrToColor.Self
	}

	for name, list in pairs(tPlayerLog[mode.type]) do
		local total = 0

		for spell, count in pairs(list) do
			tTotal.t = tTotal.t + count
			total = total + count
		end

		table.insert(tList, {
			n = name,
			t = total,
			c = kDamageTypeToColor[2],	-- TODO change this to something related to the type of mob/player that was interrupted
			--c = kDamageTypeToColor[v.dmgType],
			tStr = nil,
			click = function(_, btn)
				if btn == 0 and mode.next then
					mode.next(self, name)
				elseif btn == 1 then
					mode.prev(self)
				end
			end
		})
	end

	local strDisplayText = string.format("%s's %s", strPlayerName, mode.type)

	-- "%s's Damage to %s"
	local strModePatternTemp = string.format(mode.pattern, strPlayerName, tLogSegment.name)

	local strTotalText = string.format("%s - %d (%.2f) - %s",
		--"%s's blah on %s"
		strModePatternTemp,
		tTotal.t,
		tTotal.t / tLogSegment.combat_length,
		self:SecondsToString(tLogSegment.combat_length))

	return tList, tTotal, strDisplayText, strTotalText
end


-- TODO similar to GetPlayerList
function GalaxyMeter:GetScalarSubList()
	local tList = {}

	local tLogSegment = self.vars.tLogDisplay
	local strPlayerName = self.vars.strCurrentPlayerName
	local strModeType = self.vars.strModeType	-- interrupt/dispel/etc Out/In/etc
	local mode = self.vars.tMode

	-- log.players.PlayerName.ListType.Mob
	-- If it were passed in as a parameter we could possibly refactor this to a generic list generator
	-- Might need to create the tTotal list beforehand, other lists can add up the total
	--   in the pairs loop like this one instead of using the precalculated...
	-- GetPlayerList uses v.dmgType to generate a color
	-- strModeType is the same as mode.type but persists thru sub menus so use that?
	local tScalarList = tLogSegment[self.vars.strCurrentLogType][strPlayerName][strModeType][mode.special]

	local tTotal = {
		n = "ScalarSubListTotal",
		t = 0,
		c = kDamageTypeToColor.Self,
	}

	for name, count in pairs(tScalarList) do

		tTotal.t = tTotal.t + count

		table.insert(tList, {
			n = name,
			t = count,
			c = kDamageTypeToColor[2],
			tStr = nil,
			click = function(m, btn)
				if btn == 0 and mode.next then
					mode.next(self)
				elseif btn == 1 and mode.prev then
					mode.prev(self)
				end
			end
		})
	end

	local strDisplayText = mode.name

	local strTotalText = "strTotalText"

	return tList, tTotal, strDisplayText, strTotalText
end


--
-- @return tList, tTotal Overall list entries, total
-- Do we need an option for players/mobs?
function GalaxyMeter:GetOverallList()

	local tLogSegment = self.vars.tLogDisplay
	local mode = self.vars.tMode

	-- Grab segment type from mode: players/mobs/etc
	local strSegmentType = mode.segType
	local tSegmentType = tLogSegment[strSegmentType]

	local tTotal = {t = 0}

	local tList = {}
    for k, v in pairs(tSegmentType) do

		local nAmount = v[mode.type] or 0

		tTotal.t = tTotal.t + nAmount

        table.insert(tList, {
            n = k,
            t = nAmount,
            c = self.ClassToColor[v.classId],
			click = function(m, btn)
				-- args are the specific player log table, subType
				if btn == 0 and mode.next then
					gLog:info("OverallList next")
					mode.next(self, k, strSegmentType)

				elseif btn == 1 and mode.prev then
					gLog:info("OverallList prev")
					mode.prev(self)
				end
			end
        })
	end

	-- TODO This is only used for generating a report, refactor
	local strTotalText = string.format("%s - %d (%.2f) - %s",
		string.format(mode.pattern, tLogSegment.name),
		tTotal.t,
		tTotal.t / tLogSegment.combat_length,
		self:SecondsToString(tLogSegment.combat_length))

	self:Rover("GetOverallList", {tList, tTotal})

    return tList, tTotal, mode.name, strTotalText
end


-- Get player listing for this segment
-- @return Tables containing player damage done
--    1) Ordered list of individual spells
--    2) Total
function GalaxyMeter:GetPlayerList()
    local tList = {}

	-- These should have already been set
	local tLogSegment = self.vars.tLogDisplay
	local strPlayerName = self.vars.strCurrentPlayerName
	local mode = self.vars.tMode

	local tPlayerLog = tLogSegment[self.vars.strCurrentLogType][strPlayerName]

	-- convert to damageDone/damageTaken
	local dmgTypeTotal = self.tSubTypeFromList[mode.type]

    local tTotal = {
        n = string.format("%s's %s", strPlayerName, mode.type),
        t = tPlayerLog[dmgTypeTotal], -- "Damage to XXX"
        c = kDamageStrToColor.Self,
		click = function(m, btn)
			if btn == 0 and mode.nextTotal then
				mode.nextTotal(self, tPlayerLog)
			elseif btn == 1 and mode.prev then
				mode.prev(self)
			end
		end
    }

    for k, v in pairs(tPlayerLog[mode.type]) do
        table.insert(tList, {
            n = k,
            t = v.total,
			c = kDamageTypeToColor[v.dmgType],
			tStr = nil,
			click = function(m, btn)
				if btn == 0 and mode.next then
					mode.next(self, v)
				elseif btn == 1 then
					mode.prev(self)
				end
			end
        })
	end

	local strDisplayText = string.format("%s's %s", strPlayerName, mode.type)

	-- "%s's Damage to %s"
	local strModePatternTemp = string.format(mode.pattern, strPlayerName, tLogSegment.name)

	local strTotalText = string.format("%s - %d (%.2f) - %s",
		--"%s's blah on %s"
		strModePatternTemp,
		tTotal.t,
		tTotal.t / tLogSegment.combat_length,
		self:SecondsToString(tLogSegment.combat_length))

    return tList, tTotal, strDisplayText, strTotalText
end


function GalaxyMeter:GetSpellList()

	local strPlayerName = self.vars.strCurrentPlayerName
	local tPlayerLog = self.vars.tLogDisplay[self.vars.strCurrentLogType][strPlayerName]
	local tSpell = tPlayerLog[self.vars.strModeType][self.vars.strCurrentSpellName]

	if not tSpell then
		gLog:error("GetSpellList() nil tSpell")
		return
	end

	local cFunc = function(m, btn)
		if btn == 1 then
			self.vars.tMode.prev(self)
		end
	end

	local tList = {}

	-- Prevent buffs and debuffs without a dmg type from showing in the list
	if tSpell.dmgType and tSpell.dmgType ~= "" then
		table.insert(tList, {n = string.format("Total Damage (%s)", kDamageTypeToString[tSpell.dmgType]), tStr = tSpell.total, click = cFunc})
	end

	table.insert(tList, {n = "Cast Count/Avg", tStr = string.format("%d - %.2f", tSpell.castCount, tSpell.avg), click = cFunc})
	table.insert(tList, {n = "Crit Damage", tStr = string.format("%d (%.2f%%)", tSpell.totalCrit, tSpell.totalCrit / tSpell.total * 100), click = cFunc})
	table.insert(tList, {n = "Crit Count/Avg/Rate", tStr = string.format("%d - %.2f (%.2f%%)", tSpell.critCount, tSpell.avgCrit, tSpell.critCount / tSpell.castCount * 100), click = cFunc})

	if tSpell.totalVuln and tSpell.vulnCount then
		table.insert(tList, {n = "Vuln Damage", tStr = string.format("%d (%.2f%%)", tSpell.totalVuln, tSpell.totalVuln / tSpell.total * 100), click = cFunc})
		table.insert(tList, {n = "Vuln Count/Avg/Rate", tStr = string.format("%d - %.2f (%.2f%%)", tSpell.vulnCount, tSpell.avgVuln, tSpell.vulnCount / tSpell.castCount * 100), click = cFunc})
	end

	if tSpell.max and tSpell.min then
		table.insert(tList, {n = "Min/Max", tStr = string.format("%d / %d", tSpell.min, tSpell.max), click = cFunc})
	end

	table.insert(tList, {n = "Total Shields", tStr = tostring(tSpell.totalShield), click = cFunc})
	table.insert(tList, {n = "Total Absorbed", tStr = tostring(tSpell.totalAbsorption), click = cFunc})
	table.insert(tList, {n = "Deflects", tStr = string.format("%d (%.2f%%)", tSpell.deflectCount, tSpell.deflectCount / tSpell.castCount * 100), click = cFunc})


	local strDisplayText = string.format("%s's %s", self.vars.strCurrentPlayerName, tSpell.name)

	local strTotalText = strDisplayText .. " for " .. self.vars.tLogDisplay.name

	return tList, nil, strDisplayText, strTotalText
end


function GalaxyMeter:GetSpellTotalsList()
	local strPlayerName = self.vars.strCurrentPlayerName
	local tPlayerLog = self.vars.tLogDisplay[self.vars.strCurrentLogType][strPlayerName]

	local modeType = self.vars.tMode.type

	local tSpells = tPlayerLog[modeType]

	local cFunc = function(m, btn)
		if btn == 1 then
			gLog:info("spell totals previous")
			self.vars.tMode.prev(self)
		end
	end

	local totals = {
		total = 0,
		avg = 0,
		castCount = 0,
		totalCrit = 0,
		avgCrit = 0,
		critCount = 0,
		max = 0,
		totalShield = 0,
		totalAbsorption = 0,
		deflectCount = 0,
	}

	for k, spell in pairs(tSpells) do
		totals.total = totals.total + spell.total
		totals.castCount = totals.castCount + spell.castCount
		totals.totalCrit = totals.totalCrit + spell.totalCrit
		totals.critCount = totals.critCount + spell.critCount

		-- vulnCount isnt a pre-initialized field
		if spell.vulnCount then
			totals.vulnCount = (totals.vulnCount or 0) + spell.vulnCount
			totals.totalVuln = (totals.totalVuln or 0) + spell.totalVuln
		end

		totals.totalShield = totals.totalShield + spell.totalShield
		totals.totalAbsorption = totals.totalAbsorption + spell.totalAbsorption
		totals.deflectCount = totals.deflectCount + spell.deflectCount

		if spell.min and (not totals.min or spell.min < totals.min) then
			totals.min = (totals.min or 0) + spell.min
		end

		if spell.max and spell.max > totals.max then
			totals.max = spell.max
		end

	end

	totals.avg = totals.total / totals.castCount
	totals.avgCrit = totals.totalCrit / totals.critCount

	if totals.vulnCount then
		totals.avgVuln = totals.totalVuln / totals.vulnCount
	end

	local tList = {}

	table.insert(tList, {n = "Total ", tStr = totals.total, click = cFunc})

	table.insert(tList, {n = "Cast Count/Avg", tStr = string.format("%d - %.2f", totals.castCount, totals.avg), click = cFunc})
	table.insert(tList, {n = "Crit Damage", tStr = string.format("%d (%.2f%%)", totals.totalCrit, totals.totalCrit / totals.total * 100), click = cFunc})
	table.insert(tList, {n = "Crit Count/Avg/Rate", tStr = string.format("%d - %.2f (%.2f%%)", totals.critCount, totals.avgCrit, totals.critCount / totals.castCount * 100), click = cFunc})

	if totals.vulnCount then
		table.insert(tList, {n = "Vuln Damage", tStr = string.format("%d (%.2f%%)", totals.totalVuln, totals.totalVuln / totals.total * 100), click = cFunc})
		table.insert(tList, {n = "Vuln Count/Avg/Rate", tStr = string.format("%d - %.2f (%.2f%%)", totals.vulnCount, totals.avgVuln, totals.vulnCount / totals.castCount * 100), click = cFunc})
	end

	if totals.max and totals.min then
		table.insert(tList, {n = "Min/Max", tStr = string.format("%d / %d", totals.min, totals.max), click = cFunc})
	end

	table.insert(tList, {n = "Total Shields", tStr = tostring(totals.totalShield), click = cFunc})
	table.insert(tList, {n = "Total Absorbed", tStr = tostring(totals.totalAbsorption), click = cFunc})
	table.insert(tList, {n = "Deflects", tStr = string.format("%d (%.2f%%)", totals.deflectCount, totals.deflectCount / totals.castCount * 100), click = cFunc})


	local strDisplayText = string.format("%s's %s", self.vars.strCurrentPlayerName, "<Totals Placeholder>")

	local strTotalText = strDisplayText .. " for " .. self.vars.tLogDisplay.name

	return tList, nil, strDisplayText, strTotalText
end



-----------------------------------------------------------------------------------------------
-- Report Generators
-----------------------------------------------------------------------------------------------

-- Entry point from Report UI button
-- Report current log to X channel
function GalaxyMeter:OnReport( wndHandler, wndControl, eMouseButton )

	local mode = self.vars.tMode

	if not mode.display or not mode.report then
		return
	end

    local tReportStrings = mode.report(self, mode.display(self))

	local chan = self.settings.strReportChannel

    for i = 1, #tReportStrings do
        ChatSystemLib.Command("/" .. chan .. " " .. tReportStrings[i])
    end

end


-- @param tList List generated by Get*List
function GalaxyMeter:ReportGenericList(tList, tTotal, strDisplayText, strTotalText)

	local tLogSegment = self.vars.tLogDisplay
	local mode = self.vars.tMode
	local combatLength = tLogSegment.combat_length
	local tStrings = {}
	local total = 0

	if tTotal then
		total = tTotal.t
	end

	if mode.sort then
		table.sort(tList, mode.sort)
	end

	if strTotalText and strTotalText ~= "" then
		table.insert(tStrings, strTotalText)
	end

	self:Rover("Report tList", tList)

	for i = 1, #tList do
		local v = tList[i]
		if v.t then
			table.insert(tStrings, string.format("%d) %s - %s (%.2f)  %.2f%%",
				i, v.n, v.t, v.t / tLogSegment.combat_length, v.t / total * 100))
		else
			table.insert(tStrings, string.format("%d) %s - %s", i, v.n, v.tStr))
		end
	end

	return tStrings
end


function GalaxyMeter:CompareDisplay(Index, Text)
	if not self.DisplayOrder[Index] or ( self.DisplayOrder[Index] and self.DisplayOrder[Index] ~= Text ) then
		self.DisplayOrder[Index] = Text
		return true
	end
end


-- Main list display function, this will assemble list items and set their click handler
-- TODO Maybe combine this with Get*List or something to avoid so much looping?
function GalaxyMeter:DisplayList(Listing)

	local Arrange = false
	for k,v in ipairs(Listing) do
		if not self.tItems[k] then
			self:AddItem(k)
		end

		local wnd = self.tItems[k]

		if self:CompareDisplay(k, v.n) then
			--gLog:info(string.format("CompareDisplay true tItem[%s] n=%s", k, v.n))
			wnd.id = wnd.wnd:GetId()
			wnd.left_text:SetText(v.n)
			wnd.bar:SetBarColor(v.c)
			Arrange = true
		end

		wnd.OnClick = v.click

		if v.t then
			-- TODO move formatting into the list generator
			-- v.t is a total, format a string showing the total and total over time as dps
			wnd.right_text:SetText(string.format("%s (%.2f)", v.t, v.t / self:GetLogDisplayTimer()))

			wnd.bar:SetProgress(v.t / Listing[1].t)
		else
			-- v.tStr is a preformatted total string
			if v.tStr then
				wnd.right_text:SetText(v.tStr)
			else
				wnd.right_text:SetText("")
			end
			wnd.bar:SetProgress(1)
		end
	end
	
	-- Trim Remainder
	if #self.tItems > #Listing then
		for i=#Listing+1, #self.tItems do
			self.tItems[i].wnd:Destroy()
			self.tItems[i] = nil
		end
	end
	
	-- Rearrange if list order changed
	if Arrange then
		self.wndItemList:ArrangeChildrenVert()
	end
end


function GalaxyMeter:DisplayUpdate()

	local mode = self.vars.tMode

	if not mode.display then
		return
	end

	-- Self reference needed for calling object method, why isnt mode:display() working?
	local tList, tTotal, strDisplayText = mode.display(self)

    if mode.sort ~= nil then
        table.sort(tList, mode.sort)
    end

	-- if option to show totals
	if tTotal ~= nil then
		tTotal.n = strDisplayText
		if tTotal.click == nil then
			tTotal.click = function(m, btn)
				if btn == 1 and mode.prev then
					gLog:info("Totals prev")
					mode.prev(self)
				end
			end
		end

		table.insert(tList, 1, tTotal)
	end

	self:Rover("DisplayUpdate", {tList, tTotal})

	-- Text below the meter
	self.Children.DisplayText:SetText(strDisplayText)

    self:DisplayList(tList)
end



function GalaxyMeter:RefreshDisplay()
	self.DisplayOrder = {}
    self:DisplayUpdate()
end


-----------------------------------------------------------------------------------------------
-- GalaxyMeterForm Functions
-----------------------------------------------------------------------------------------------
-- when the OK button is clicked
function GalaxyMeter:OnOK()
	self.wndMain:Show(false) -- hide the window
end

-- when the Cancel button is clicked
function GalaxyMeter:OnCancel()
	self.wndMain:Show(false) -- hide the window
end


-- when the Clear button is clicked
function GalaxyMeter:OnClearAll()


	gLog:info("OnClearAll()")

	self.log = {}
	self.bNeedNewLog = true
	self:NewLogSegment()
	self.vars = {
		nLogIndex = 0,
		tLogDisplay = self.tCurrentLog,
		strCurrentLogType = "",
		strCurrentPlayerName = "",
		strCurrentSpellName = "",
		strModeType = "",
		tMode = self.tModes["Main Menu"],
		tModeLast = {}
	}
	self.Children.EncounterText:SetText(self.vars.tLogDisplay.name)
	self.Children.TimeText:SetText(self:SecondsToString(self.vars.tLogDisplay.combat_length))
	self:RefreshDisplay()
end


function GalaxyMeter:OnEncounterDropDown( wndHandler, wndControl, eMouseButton )
	if not self.wndEncList:IsVisible() then
		self.wndEncList:Show(true)
		
		-- Newest Entry at the Top
		for i = 1, #self.log do
			local wnd = Apollo.LoadForm(self.xmlMainDoc, "EncounterItem", self.Children.EncItemList, self)
			table.insert(self.tEncItems, wnd)
			
			local TimeString = self:SecondsToString(self.log[i].combat_length)
			
			wnd:FindChild("Text"):SetText(self.log[i].name .. " - " .. TimeString)
			wnd:FindChild("Highlight"):Show(false)
			wnd:SetData(i)
		end
		self.Children.EncItemList:ArrangeChildrenVert()
	else
		self:HideEncounterDropDown()
	end
end


function GalaxyMeter:HideEncounterDropDown()
	self.tEncItems = {}
	self.Children.EncItemList:DestroyChildren()
	self.wndEncList:Show(false)
end


function GalaxyMeter:SecondsToString(time)
	local Min = math.floor(time / 60)
	local Sec = time % 60

	local Time_String = ""
	if time >= 60 then
		Time_String = string.format("%sm:%.0fs", Min , Sec )
	else
		Time_String = string.format("%.1fs", Sec )
	end
	return Time_String
end


-----------------------------------------------------------------------------------------------
-- Menu Functions
-----------------------------------------------------------------------------------------------

-- Pop last mode off of the stack
function GalaxyMeter:PopMode()
	gLog:info("PopMode()")
	gLog:info(self.vars.tModeLast)

	if self.vars.tModeLast and #self.vars.tModeLast > 0 then
		local mode = table.remove(self.vars.tModeLast)
		--gLog:info(self.vars.tModeLast)
		return mode
	end

	return nil
end


-- Push mode onto the stack
function GalaxyMeter:PushMode()
	self.vars.tModeLast = self.vars.tModeLast or {}

	table.insert(self.vars.tModeLast, self.vars.tMode)

	gLog:info("PushMode")
	gLog:info(self.vars.tModeLast)
end


-- TODO Generalize this into DisplayMenu or something
function GalaxyMeter:DisplayMainMenu()
    local tMenuList = {}

	--gLog:info("DisplayMainMenu()")

    for k, v in pairs(self.tMainMenu) do
        table.insert(tMenuList, {
            n = k,
            c = kDamageStrToColor["DamageType_Physical"],
			click = function(m, btn)

				if v and self.vars.tLogDisplay.start > 0 and btn == 0 then
					gLog:info("MainMenu, next mode =")
					gLog:info(v)

					-- Call next on CURRENT mode, v arg is next mode
					--m.vars.tMode.next(m, v)
					self:PushMode()
					self.vars.tMode = v

					self.bDirty = true
				end
			end
        })
	end

	--self:Rover("DisplayMainMenu: tMenuList", tMenuList)

    return tMenuList, nil, "Main Menu"
end


-- A player was clicked from an Overall menu, update the mode to the appropriate selection
-- @param strPlayerName Player name
-- @param strSegmentType String identifier for segment type, players/mobs etc
function GalaxyMeter:MenuPlayerSelection(strPlayerName, strSegmentType)

	local mode = self.vars.tMode

	self.vars.strCurrentPlayerName = strPlayerName
	self.vars.strCurrentLogType = strSegmentType

	gLog:info(string.format("MenuPlayerSelection: %s -> %s", self.vars.strCurrentPlayerName, self.vars.strCurrentLogType))

	self:PushMode()
	-- damageDone -> "Player Damage Done Breakdown", etc

	self.vars.tMode = self.tModeFromSubType[mode.type]
	self.vars.strModeType = self.tListFromSubType[mode.type]	-- Save this because as we delve deeper into menus the type isn't necessarily set

	self.bDirty = true
end


function GalaxyMeter:MenuPlayerSpell(tSpell)
	self:PushMode()

	--gLog:info("strCurrentSpellName = " .. tSpell.name)
	self.vars.strCurrentSpellName = tSpell.name

	self.vars.tMode = self.tModes["Spell Breakdown"]

	self.bDirty = true
end


function GalaxyMeter:MenuPlayerSpellTotal(tPlayerLog)

	local mode = self.vars.tMode

	local newMode = {
		--name = self.vars.strCurrentPlayerName .. "'s " .. strType .. " on " .. name,
		name = "<Name>",
		pattern = "%s's %s",
		display = self.GetSpellTotalsList,
		report = self.ReportGenericList,
		type = mode.type,
		--segType = strLogType,
		prev = self.MenuPrevious,
		next = nil,
		sort = nil,
		--special = name,
	}

	self:PushMode()

	self.bDirty = true

	self.vars.tMode = newMode

end


function GalaxyMeter:MenuPrevious()
	gLog:info("MenuPrevious()")


	local currentMode = self.vars.tMode

	local tMode = self:PopMode()
	if tMode then
		self.vars.tMode = tMode
		self.bDirty = true
	else
		gLog:error("popped nil mode")
		gLog:error(currentMode)
	end
end


-- Special case scalar list, we create a temporary mode tailored to the specific list we're interested in
function GalaxyMeter:MenuScalarSelection(name)

	self:Rover("ScalarSelection", {
		param_Name = name,
		vars = self.vars,
	})

	local strLogType = self.vars.strCurrentLogType	-- players/mobs
	local strPlayerName = self.vars.strCurrentPlayerName
	local strModeType = self.vars.strModeType	-- interrupt/dispel/etc Out/In/etc

	local tLog = self.vars.tLogDisplay

	-- log.players.Humera.interruptOut
	local tScalarList = tLog[strLogType][strPlayerName][strModeType]

	local strType = ""
	if strModeType == "interruptOut" or strModeType == "interruptIn" then
		strType = "interrupts"
	end

	local reportFunc = nil

	local newMode = {
		name = strPlayerName .. "'s " .. strType .. " on " .. name,
		pattern = "%s's %s",
		display = self.GetScalarSubList,
		report = reportFunc,
		type = strType,
		segType = strLogType,
		prev = self.MenuPrevious,
		next = nil,
		sort = nil,
		special = name,
	}

	self:PushMode()

	self.vars.tMode = newMode

	self.bDirty = true
end



-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------
-- clear the item list
function GalaxyMeter:DestroyItemList()
	-- destroy all the wnd inside the list
	for idx,wnd in pairs(self.tItems) do
		wnd:Destroy()
	end

	-- clear the list item array
	self.tItems = {}
end


-- add an item into the item list
function GalaxyMeter:AddItem(i)
	-- load the window item for the list item
	local wnd = Apollo.LoadForm(self.xmlMainDoc, "ListItem", self.wndItemList, self)
	
	-- keep track of the window item created
	self.tItems[i] = { wnd = wnd }

    local item = self.tItems[i]

	item.id = wnd:GetId()
    item.bar = wnd:FindChild("PercentBar")
    item.left_text = wnd:FindChild("LeftText")
    item.right_text = wnd:FindChild("RightText")

    item.bar:SetMax(1)
    item.bar:SetProgress(0)
    item.left_text:SetTextColor(kcrNormalText)

	wnd:FindChild("Highlight"):Show(false)

	wnd:SetData(i)
	
	return self.tItems[i]
end


function GalaxyMeter:OnListItemMouseEnter( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(true)
end


function GalaxyMeter:OnListItemMouseExit( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(false)
end


function GalaxyMeter:OnListItemButtonUp( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY )
    if self.tListItemClicked == wndControl then
		self.tListItemClicked = nil
        --gLog:info(string.format("control %s id %d, name '%s', button %d", tostring(wndControl), wndControl:GetId(), wndControl:GetName(), tostring(eMouseButton)))

        local id = wndControl:GetId()

        -- find menu item from id of clicked control
        for i, v in pairs(self.tItems) do

            if v.id == id and v.OnClick then
				if self.settings.bDebug then
					gLog:info("Calling OnClick()")
					gLog:info(v)
				end
                v.OnClick(self, eMouseButton)
				if self.bDirty then
					self.bDirty = false
					self:RefreshDisplay()
				end
            end

        end
	end
end


function GalaxyMeter:OnListItemButtonDown( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation )
    self.tListItemClicked = wndControl
end



-----------------------------------------------------------------------------------------------
-- GalaxyMeter Config
-----------------------------------------------------------------------------------------------
function GalaxyMeter:ConfigOn()
	-- Start up Config
end


function GalaxyMeter:OnSave(eType)
	local tSave = {}

	if eType == GameLib.CodeEnumAddonSaveLevel.General then

		tSave.version = GalMet_Version
		tSave.settings = self.settings

		--if self.wndMain then
			tSave.settings.anchor = {self.wndMain:GetAnchorOffsets()}
		--else
		--	tSave.settings.anchor = self.settings.anchor
		--end
		
	elseif eType == GameLib.CodeEnumAddonSaveLevel.Character then
	end
	
	return tSave
end


function GalaxyMeter:OnRestore(eType, t)

	if not t or not t.version or t.version < GalMet_Version then
		return
	end

	if eType == GameLib.CodeEnumAddonSaveLevel.General then

		if t.settings then
			self.settings = t.settings

			if t.settings.anchor then
				--self.settings.anchor = t.settings.anchor
				self.wndMain:SetAnchorOffsets(unpack(t.settings.anchor))
			end

		end

		gLog:info("OnRestore General")
		gLog:info(t)
	end
end


---------------------------------------------------------------------------------------------------
-- EncounterItem Functions
---------------------------------------------------------------------------------------------------

function GalaxyMeter:OnEncounterItemSelected( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY )
	local logIdx = wndHandler:GetData()

	self.vars.tLogDisplay = self.log[logIdx]
	-- Should we do a sanity check on the current mode? For now just force back to main menu
	self.vars.tMode = self.tModes["Main Menu"]
	self.vars.tModeLast = {}

	self.Children.EncounterText:SetText(self.vars.tLogDisplay.name)
	
	self:HideEncounterDropDown()

	-- Right now this only updates in OnTimer, should probably look at the bDirty logic and move it into RefreshDisplay
	self.Children.TimeText:SetText(self:SecondsToString(self.vars.tLogDisplay.combat_length))

	self.bDirty = true
	self:RefreshDisplay()
end


function GalaxyMeter:OnEncounterItemMouseEnter( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(true)
end


function GalaxyMeter:OnEncounterItemMouseExit( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(false)
end



function GalaxyMeter:Rover(varName, var)
	if self.settings.bDebug then
		Event_FireGenericEvent("SendVarToRover", varName, var)
	end
end


function GalaxyMeter:HexToCColor(color)
	local r = tonumber(string.sub(color,1,2), 16) / 255
	local g = tonumber(string.sub(color,3,4), 16) / 255
	local b = tonumber(string.sub(color,5,6), 16) / 255
	local a = tonumber(string.sub(color,5,6 or "FF"), 16) / 255
	return CColor.new(r,g,b,1)
end


-----------------------------------------------------------------------------------------------
-- GalaxyMeter Instance
-----------------------------------------------------------------------------------------------
local GalaxyMeterInst = GalaxyMeter:new()
GalaxyMeterInst:Init()
