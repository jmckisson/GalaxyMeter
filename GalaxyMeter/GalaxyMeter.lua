-----------------------------------------------------------------------------------------------
-- Client Lua Script for GalaxyMeter
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Apollo"
require "GameLib"
require "Window"
require "Unit"
require "Spell"
require "GroupLib"
require "ICCommLib"


local GeminiPackages = _G["GeminiPackages"]
local gLog

-----------------------------------------------------------------------------------------------
-- GalaxyMeter Module Definition
-----------------------------------------------------------------------------------------------
local GalaxyMeter = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
local GalMet_Version = "0.10"
local GalMet_LogVersion = 4
local bDebug = true

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

local tReportTypes = {
	"Overall Damage", "Overall Healing Done", "Damage Done", "Damage Taken", "Healing Done", "Healing Taken",
}


-- Message types for use in the ICCommLib channel
local eMsgType = {
	CombatEvent = 0,
	CombatStopEvent = 1,
}

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function GalaxyMeter:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	self.tItems = {} -- keep track of all the list items
	self.tEncItems = {}
	
	-- Handled by Configure
	self.settings = {}
	self.tSavedSettings = {}

	-- Display Order (For Reducing On Screen Drawing)
	self.DisplayOrder = {}
	
	-- Comm Channel
	self.CommChannel = nil
	self.ChannelName = ""

    self.vars = {}

    return o
end


function GalaxyMeter:Init()
    Apollo.RegisterAddon(self, false)
end


function GalaxyMeter:Rover(varName, var)
	if bDebug then
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
-- GalaxyMeter OnLoad
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnLoad()

	GeminiPackages:Require("GeminiLogging-1.0", function(GeminiLogging)
		gLog = GeminiLogging:GetLogger({
			level = GeminiLogging.INFO,
			pattern = "[%d] %n [%c:%l] - %m",
			appender = "GeminiConsole"
		})

	
		-- Slash Commands
	    Apollo.RegisterSlashCommand("lkm", 								"OnGalaxyMeterOn", self)
	
		-- Player Updates
		Apollo.RegisterEventHandler("ChangeWorld", 						"OnChangeWorld", self)
		
		-- Self Combat Logging
		Apollo.RegisterEventHandler("UnitEnteredCombat", 				"OnEnteredCombat", self)
		--Apollo.RegisterEventHandler("AttackMissed", 					"OnAttackMissed", self)
		--Apollo.RegisterEventHandler("SpellCastFailed", 				"OnSpellCastFailed", self)
		--Apollo.RegisterEventHandler("SpellEffectCast", 				"OnSpellEffectCast", self)
		Apollo.RegisterEventHandler("DamageOrHealingDone", 				"OnDamageOrHealingDone", self)
		--Apollo.RegisterEventHandler("TransferenceTaken", 				"OnTransferenceTaken", self)
		--Apollo.RegisterEventHandler("TransferenceDone", 				"OnTransferenceDone", self)
		--Apollo.RegisterEventHandler("CombatLogString", 				"OnCombatLogString", self)
		--Apollo.RegisterEventHandler("GenericEvent_CombatLogString", 	"OnCombatLogString", self)
		Apollo.RegisterEventHandler("CombatLogCCStateBreak",			"OnCombatLogCCStateBreak", self)
		Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor",	"OnCombatLogModifyInterruptArmor", self)
		Apollo.RegisterEventHandler("CombatLogInterrupted",				"OnCombatLogInterrupted", self)
		Apollo.RegisterEventHandler("CombatLogDeath",					"OnCombatLogDeath", self)
		Apollo.RegisterEventHandler("CombatLogDelayDeath",				"OnCombatLogDelayDeath", self)
		Apollo.RegisterEventHandler("CombatLogResurrect",				"OnCombatLogResurrect", self)
		Apollo.RegisterEventHandler("CombatLogDispel",					"OnCombatLogDispel", self)
		Apollo.RegisterEventHandler("CombatLogDamage",					"OnCombatLogDamage", self)
		Apollo.RegisterEventHandler("CombatLogHeal",					"OnCombatLogHeal", self)

		-- Chat: Shared Logging
		Apollo.RegisterEventHandler("Group_Join",						"OnGroupJoin", self)
		Apollo.RegisterEventHandler("Group_Left",						"OnGroupLeft", self)
		Apollo.RegisterEventHandler("Group_Updated",					"OnGroupUpdated", self)

		-- Combat Timer
	    Apollo.CreateTimer("CombatTimer", 0.05, true)
	    Apollo.RegisterTimerHandler("CombatTimer", 						"OnTimer", self)
		Apollo.StopTimer("CombatTimer")
		
		-- Player Check Timer
	    Apollo.CreateTimer("PlayerCheckTimer", 1, false)	-- Pulsing Timer
	    Apollo.RegisterTimerHandler("PlayerCheckTimer", 				"OnPlayerCheckTimer", self)

		
	    -- Load Forms
	    self.wndMain = Apollo.LoadForm("GalaxyMeter.xml", "GalaxyMeterForm", nil, self)
	    self.wndMain:Show(false)
		self.wndEncList = self.wndMain:FindChild("EncounterList")
	    self.wndEncList:Show(false)
	
		-- Store Child Widgets
		self.Children = {}
		self.Children.TimeText = self.wndMain:FindChild("Time_Text")
		self.Children.DisplayText = self.wndMain:FindChild("Display_Text")
		self.Children.EncounterButton = self.wndMain:FindChild("EncounterButton")	
		self.Children.ModeButton_Left = self.wndMain:FindChild("ModeButton_Left")		
		self.Children.ModeButton_Right = self.wndMain:FindChild("ModeButton_Right")
		self.Children.ConfigButton = self.wndMain:FindChild("ConfigButton")	
		self.Children.ClearButton = self.wndMain:FindChild("ClearButton")		
		self.Children.CloseButton = self.wndMain:FindChild("CloseButton")
		self.Children.EncItemList = self.wndEncList:FindChild("ItemList")
		
		self.Children.EncounterButton:SetText("")
		self.Children.TimeText:SetText("")
		self.Children.DisplayText:SetText("")
		
		-- Item List
		self.wndItemList = self.wndMain:FindChild("ItemList")
		
		self.ClassToColor = {
			self:HexToCColor("855513"),	-- Warrior
			self:HexToCColor("cf1518"),	-- Engineer
			self:HexToCColor("c875c4"),	-- Esper
			self:HexToCColor("2cc93f"),	-- Medic
			self:HexToCColor("d7de1f"),	-- Stalker
			self:HexToCColor("ffffff"),	-- Corrupted
			self:HexToCColor("5491e8"),	-- Spellslinger
		}


        -- Display Modes, list of mode names, callbacks for display and report, and log subtype indices
        self.tModes = {
            ["Main Menu"] = {
                name = "Main Menu",
                display = self.DisplayMainMenu,
                report = nil,
                prev = nil,
                next = self.MenuMainSelection,
				sort = function(a,b) return a.n < b.n end,	-- Aplhabetic sort by mode name
            },
            ["Damage Done"] = {
                name = "Overall Damage Done",       		-- Display name
                pattern = "Damage done on %s",           	--
                display = self.GetOverallList,
                report = self.ReportGenericList,
                type = "damageDone",
                prev = self.MenuMain,						-- Right Click, previous menu
                next = self.MenuPlayerSelection,			-- Left Click, next menu
                sort = function(a,b) return a.t > b.t end,
            },
            ["Damage Taken"] = {
                name = "Overall Damage Taken",
                pattern = "Damage taken from %s",
                display = self.GetOverallList,
                report = self.ReportGenericList,
                type = "damageTaken",
                prev = self.MenuMain,
                next = self.MenuPlayer,
                sort = function(a,b) return a.t > b.t end,
            },
            ["Healing Done"] = {
                name = "Overall Healing Done",
                pattern = "Healing Done on %s",
                display = self.GetOverallList,
                report = self.ReportGenericList,
                type = "healingDone",
                prev = self.MenuMain,
                next = self.MenuPlayer,
                sort = function(a,b) return a.t > b.t end,
            },
            ["Healing Received"] = {
                name = "Overall Healing Taken",
                pattern = "Healing Taken on %s",
                display = self.GetOverallList,
                report = self.ReportGenericList,
                type = "healingTaken",
                prev = self.MenuMain,
                next = self.MenuPlayer,
                sort = function(a,b) return a.t > b.t end,
            },
            ["Player Damage Done Breakdown"] = {
                name = "%s's Damage Done",
                pattern = "%s's Damage to %s",
                display = self.GetPlayerList,
                report = self.ReportGenericList,
                type = "damageOut",
                prev = self.MenuPlayer,
                next = self.MenuPlayerSpell,
                sort = function(a,b) return a.t > b.t end,
            },
            ["Player Damage Taken Breakdown"] = {
                name = "%s's Damage Taken",
                pattern = "%s's Damage Taken from %s",
                display = self.GetPlayerList,
                report = self.ReportGenericList,
                type = "damageIn",
                prev = self.MenuPlayer,
                next = self.MenuPlayerSpell,
                sort = function(a,b) return a.t > b.t end,
            },
            ["Player Healing Done Breakdown"] = {
                name = "%s's Healing Done",
                pattern = "%s's Healing Done on %s",
                display = self.GetPlayerList,
                report = self.ReportGenericList,
                type = "healingOut",
                prev = self.MenuPlayer,
                next = self.MenuPlayerSpell,
                sort = function(a,b) return a.t > b.t end,
            },
            ["Player Healing Received Breakdown"] = {
                name = "%s's Healing Received",
                pattern = "%s's Healing Received on %s",
                display = self.GetPlayerList,
                report = self.ReportGenericList,
                type = "healingIn",
                prev = self.MenuPlayer,
                next = self.MenuPlayerSpell,
                sort = function(a,b) return a.t > b.t end,
            },
			["Spell Breakdown"] = {
				name = "",
				pattern = "",
				display = self.GetSpellList,
				report = self.ReportGenericList,
				prev = self.MenuPlayer,
				next = nil,
				sort = nil,
			},
			["Interrupts"] = {
				name = "Interrupts",
				display = self.GetInterruptList,
				sort = function(a,b) return a.t > b.t end,
			},
			["Deaths"] = {
				name = "Deaths",
				display = self.GetDeathList,
				sort = function(a,b) return a.t > b.t end,
			},
			["Threat"] = {
				name = "Threat",
				display = self.GetThreatList,
				sort = function(a,b) return a.t > b.t end,
			},
			["Dispels"] = {
				name = "Dispels",
				display = self.GetDispelList,
				sort = function(a,b) return a.t > b.t end,
			},
        }

        self.tMainMenu = {
            ["Damage Done"] = self.tModes["Damage Done"],
            ["Damage Taken"] = self.tModes["Damage Taken"],
			["Healing Done"] = self.tModes["Healing Done"],
			["Healing Received"] = self.tModes["Healing Received"],
			["Interrupts"] = self.tModes["Interrupts"],
			["Deaths"] = self.tModes["Deaths"],
			["Threat"] = self.tModes["Threat"],
			["Dispels"] = self.tModes["Dispels"],
		}

		self.tModeFromSubType = {
			["damageDone"] = self.tModes["Player Damage Done Breakdown"],
			["damageTaken"] = self.tModes["Player Damage Taken Breakdown"],
			["healingDone"] = self.tModes["Player Healing Done Breakdown"],
			["healingTaken"] = self.tModes["Player Healing Received Breakdown"],
		}

		self.tListFromSubType = {
			["damageDone"] = "damageOut",
			["damageTaken"] = "damageIn",
			["healingDone"] = "healingOut",
			["healingTaken"] = "healingIn",
		}

		-- Reverse table
		self.tSubTypeFromList = {}
		for k, v in pairs(self.tListFromSubType) do
			self.tSubTypeFromList[v] = k
		end


        self.vars = {
            -- modes
            tMode = self.tModes["Main Menu"],   -- Default to Main Menu
            nLogIndex = 0,
            bGrouped = false,
        }


        Apollo.StartTimer("PlayerCheckTimer")

        self:NewLogSegment()

		self.vars.tLogDisplay = self.log[1]

	end)	-- End Gemini load function
end



function GalaxyMeter:OnConfigure()
	self:ConfigOn()
end

-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnPlayerCheckTimer
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnPlayerCheckTimer()
	
	local unitPlayer = GameLib.GetPlayerUnit()
	if unitPlayer then
		self.unitPlayer = GameLib.GetPlayerUnit()
		self.unitPlayerId = self.unitPlayer:GetId()
		self.PlayerId = tostring(self.unitPlayerId)
		self.PlayerName = self.unitPlayer:GetName()

		Apollo.StartTimer("PlayerCheckTimer")
	end

	-- Check if the rest of the group is out of combat
	if self.tCurrentLog.start > 0 then
		if not self:GroupInCombat() and not self.bInCombat then
			--gLog:info("pushing combat segment")
			self:PushLogSegment()
		else
			--gLog:info("Not pushing segment, group in combat")
		end
	else
		--gLog:warn("no log checking timer")
	end

end

-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnTimer
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnTimer()
	
	self.tCurrentLog.combat_length = os.clock() - self.tCurrentLog.start

	if self.vars.tLogDisplay == self.tCurrentLog then
		
		self:DisplayUpdate()
    else
        --gLog:info("logdisplay: " .. tostring(self.vars.tLogDisplay))
        --gLog:info("tCurrentLog: " .. tostring(self.tCurrentLog))
	end
end

-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnChangeWorld
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnChangeWorld()
	-- Restarts Player Check Timer to update Player Id based on New Zone
	Apollo.StartTimer("PlayerCheckTimer")
end


-- Set self.bInCombat true if any group members are in combat
function GalaxyMeter:GroupInCombat()

	if self.tGroupMembers ~= nil then

        for i=1,#self.tGroupMembers do
            local member = self.tGroupMembers[i]
            if member.combat == true and member.name ~= self.PlayerName then
                return true
            end
        end
	end
	
	return false
end

	
function GalaxyMeter:StartLogSegment()

	gLog:info("StartLogSegment()")

	self.tCurrentLog.start = os.clock()

	Apollo.StartTimer("CombatTimer")

	-- Switch to the newly started segment if logindex is still 0 (which means we're looking at 'current' logs)
	if self.vars.nLogIndex == 0 then
		self.vars.tLogDisplay = self.tCurrentLog
	end
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
end


-- TODO rename this, the actual 'push' occurs in NewLogSegment
function GalaxyMeter:PushLogSegment()
	gLog:info("Pushing log segment")

    --self:Rover("lastLog", self.tCurrentLog)
    --self:Rover("log", self.log)

    -- Pop off oldest, TODO Add config option to keep N old logs
    if #self.log >= 50 then
        table.remove(self.log)
    end

    Apollo.StopTimer("CombatTimer")

    self:NewLogSegment()

end


-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnEnteredCombat
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnEnteredCombat(unit, bInCombat)
	--if not self.wndMain or not self.wndMain:IsValid() then
	--	return
    --end

    -- TODO: Keep track of group members combat status solely using this event?
	
	if unit == GameLib.GetPlayerUnit() then
	
		-- We weren't in combat before, so start new segment
		if not self.bInCombat then
			self.bNeedNewLog = true
            gLog:info("Setting bNeedNewLog = true")
        end


        if self.bInCombat and not bInCombat then
            -- If we were in combat, and not anymore...
            gLog:info("Sending combat stop message")
            self:SendCombatMessage(eMsgType.CombatStopEvent, {})
        end
	
		self.bInCombat = bInCombat
		
	end
end

-----------------------------------------------------------------------------------------------
-- GalaxyMeter Functions
-----------------------------------------------------------------------------------------------

function GalaxyMeter:RestoreWindowPosition()
	if self.wndMain and self.tSavedSettings ~= nil and self.tSavedSettings.anchor ~= nil then
		self.wndMain:SetAnchorOffsets(unpack(self.tSavedSettings.anchor))
	end
end

-- on SlashCommand "/lkm or /galmet"
function GalaxyMeter:OnGalaxyMeterOn()
	self:RestoreWindowPosition()

	self.wndMain:Show(true) -- show the window

	self:DisplayUpdate()
end

-----------------------------------------------------------------------------------------------
-- Channel Manager Functions
-----------------------------------------------------------------------------------------------
function GalaxyMeter:SetGroupLogChannel(GroupLeader)
	--Simple preventation to keep users from 'bumping' into the channel
	local newChannel = string.format("GalMet_%s_%s_%d", GroupLeader, string.reverse(GroupLeader), GalMet_LogVersion)

	if self.ChannelName ~= newChannel then
		self.ChannelName = newChannel
		self.CommChannel = ICCommLib.JoinChannel(self.ChannelName, "OnCombatMessage", self)
	
		gLog.info("Joined Channel '" .. self.ChannelName .. "'")
	end
end


function GalaxyMeter:LeaveGroupLogChannel()
	self.vars.channel = nil
	self.ChannelName = ""
end


function GalaxyMeter:OnCombatMessage(channel, tMsg)
	
	-- Ignore messages sent by yourself
	if channel ~= self.CommChannel or tMsg.event.Caster == self.PlayerName then return nil end
	
	if tMsg.type == eMsgType.CombatEvent then
	
		-- Don't pay attention to heals unless we're already in combat
		if self:IsHealEvent(tMsg.event.CombatType) and not self.bInCombat then
			gLog:info("OnCombatMessage: Not initiating combat for healing event")
			return
		end
	
		-- Assume that this group member is in combat
		if self.tGroupMembers[tMsg.playerName] == nil then
			gLog:info(string.format("OnCombatMessage, added %s to group list", tMsg.playerName))
			self.tGroupMembers[tMsg.playerName] = {
				combat = true,
				name = tMsg.playerName,
			}
		end
		
		-- If the current segment hasnt started and a group member is in combat, flag for creation of a new log
		if self.tCurrentLog.start == 0 and not self.bNeedNewLog and self:GroupInCombat() then
			gLog:info("OnCombatMessage: NeedNewLog = true")
			self.bNeedNewLog = true
		end

        -- At this point, event.TypeId should already be set by the sender
        if tMsg.event.TypeId == 0 then
            gLog:fatal(string.format("Invalid typeId on incoming message, Sender: %s, typeId: %s",
                                    tMsg.playerName, tMsg.event.TypeId))
        end

        self:UpdatePlayerSpell(tMsg.event)

		
	elseif tMsg.type == eMsgType.CombatStopEvent then
		self.tGroupMembers[tMsg.event.Caster].combat = false
	end
end


function GalaxyMeter:SendCombatMessage(eType, CombatEvent)
	if self.CommChannel then
		--CombatEvent.LogVersion = GalMet_LogVersion
		
		local msg = {
			version = GalMet_LogVersion,
			type = eType,
            playerName = self.PlayerName,
			event = CombatEvent,
		}
		
		self.CommChannel:SendMessage(msg)
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
				id = i,
				combat = false,
            }
        end

        table.insert(tTempMembers, charName)
	end
	
	-- Maintain list of current group members
    -- Now remove items in tGroupMembers that don't exist in the temp table
	for p in pairs(self.tGroupMembers) do
		-- If not in temp members, remove
		if tTempMembers[p.name] ~= nil then

            tTempMembers[p] = nil
			--table.remove(self.tGroupMembers, p.name)
		end
	end
	
	self.vars.bGrouped = true
	self:SetGroupLogChannel(GroupLeader)
end


function GalaxyMeter:OnGroupLeft()
	self.vars.bGrouped = false
	self:LeaveGroupLogChannel()
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
			self.Children.EncounterButton:SetText(title)
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


function GalaxyMeter:IsHealEvent(eType)
    return (eType == GameLib.CodeEnumDamageType.Heal or eType == GameLib.CodeEnumDamageType.HealShields)
end


function GalaxyMeter:NewCombatEvent(unitCaster, unitTarget, eMissType, eDamageType, spellName, ...)

    local dmgType = "Damage"
    local nClassId
    local strCaster

    local event = {
        --Caster = "Unknown",
        CasterId = self:GetUnitId(unitCaster),
        CasterType = "Unknown",
        Target = "Unknown",
        TargetId = self:GetUnitId(unitTarget),
        TargetType = "Unknown",
        DamageType = eDamageType,
        SpellName = spellName,
        TypeId = 0,
    }

    if eMissType > 0 then
        local Block = ( eMissType == GameLib.CodeEnumMissType.Block )
        local Dodge = ( eMissType == GameLib.CodeEnumMissType.Dodge )

        event.Block = Block
        event.Dodge = Dodge
        event.Miss = ( not Block and not Dodge )

    elseif eDamageType > 0 then
        local nDamage, nShieldAbsorbed, nAbsorptionAmount, bCritical = ...

        event.Damage = nDamage
        event.ShieldAbsorbed = nShieldAbsorbed
        event.AbsorptionAmount = nAbsorptionAmount
        event.Critical = bCritical
        event.Miss = false
    end


    --
    -- Figure out the proper caster name and class id for the casting unit
    if unitCaster then
        event.CasterType = unitCaster:GetType()

        -- Count pets as damage done by the player
        if event.CasterType == "Pet" then
            --gLog:info(string.format("Pet Damage, set CasterID to %s", nCasterId))

            -- Prepend pet name to the spell name
            event.SpellName = string.format("%s: %s", unitCaster:GetName(), event.SpellName)

            strCaster = self.PlayerName
            nClassId = GameLib:GetPlayerUnit():GetClassId()

        else
            strCaster = unitCaster:GetName()
            nClassId = unitCaster:GetClassId()
        end

    else
        local nTargetId = self:GetUnitId(unitTarget)
        local strTarget = self:GetUnitName(unitTarget)

        -- Hack to fix Pets sometimes having no unitCaster
        gLog:info(string.format("NewCombatEvent unitCaster nil(pet?): Caster[%d] %s, Target[%d] %s",
            event.CasterId, "Unknown", nTargetId, strTarget))

        -- Set caster to our player name
        strCaster = self.PlayerName

        -- Set class id to player class
        -- This is only needed if the caster doesn't exist yet in the log, to properly set the class if a pet
        -- initiates combat
        nClassId = GameLib:GetPlayerUnit():GetClassId()
    end


	if unitTarget then
        event.TargetType = unitTarget:GetType()

        if unitTarget:GetName() then
		    event.Target = unitTarget:GetName()
		    gLog:info("unitTarget, set target to " .. event.Target)
        end

    else
        -- No spell target, how about what the player is targetting?
		event.Target = self:GetTarget()
		gLog:info("no unitTarget, set target to " .. event.Target)
    end

    event.PlayerName = self.PlayerName
    event.Caster = strCaster
	event.StrType = dmgType
	event.CasterClassId = nClassId

    self:Rover("NewCombatEvent, tEvent", event)

    return event
end


function GalaxyMeter:OnCombatLogDispel(tEventArgs)
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
	--[[
	local tCastInfo = self:HelperCasterTargetSpell(tEventArgs, true, true)
	tCastInfo.strSpellName = string.format("<T Font=\"%s\">%s</T>", kstrFontBold, tCastInfo.strSpellName)
	local strResult = String_GetWeaselString(Apollo.GetString("CombatLog_TargetInterrupted"), tCastInfo.strTarget, tCastInfo.strSpellName) -- NOTE: strTarget is first, usually strCaster is first

	if tEventArgs.unitCaster ~= tEventArgs.unitTarget then
		if tEventArgs.splInterruptingSpell and tEventArgs.splInterruptingSpell:GetName() then
			strResult = String_GetWeaselString(Apollo.GetString("CombatLog_InterruptSourceCaster"), strResult, tEventArgs.unitCaster:GetName(), tEventArgs.splInterruptingSpell:GetName())
		else
			strResult = String_GetWeaselString(Apollo.GetString("CombatLog_InterruptSource"), strResult, tEventArgs.unitCaster.GetName())
		end
	elseif tEventArgs.strCastResult then
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_InterruptSelf"), strResult, tEventArgs.strCastResult)
	end

	-- TODO: Analyze if we can refactor (this has a unique spell)
	local strColor = kstrColorCombatLogIncomingGood
	if tEventArgs.unitCaster == self.unitPlayer then
		strColor = kstrColorCombatLogOutgoing
	end
	self:PostOnChannel(string.format("<T TextColor=\"%s\">%s</T>", strColor, strResult))
	--]]
end


function GalaxyMeter:OnCombatLogModifyInterruptArmor(tEventArgs)
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
	--[[
	local strBreak = String_GetWeaselString(Apollo.GetString("CombatLog_CCBroken"), tEventArgs.strState)
	self:PostOnChannel(string.format("<P TextColor=\"%s\">%s</P>", kstrStateColor, strBreak))
	--]]
end


function GalaxyMeter:OnCombatLogDelayDeath(tEventArgs)
	--[[
	local tCastInfo = self:HelperCasterTargetSpell(tEventArgs, false, true)
	local strSaved = String_GetWeaselString(Apollo.GetString("CombatLog_NotDeadYet"), tCastInfo.strCaster, tCastInfo.strSpellName)
	self:PostOnChannel(string.format("<P TextColor=\"%s\">%s</P>", kstrStateColor, strSaved))
	--]]
end


function GalaxyMeter:OnCombatLogDeath(tEventArgs)
	--[[
	self:PostOnChannel(string.format("<P TextColor=\"%s\">%s</P>", kstrStateColor, Apollo.GetString("CombatLog_Death")))
	--]]
end


function GalaxyMeter:OnAttackMissed(unitCaster, unitTarget, eMissType, strArgSpellName)
	if not self.bInCombat then return nil end
	
	local strSpellName = "Unknown" if strArgSpellName and string.len(strArgSpellName) > 0 then strSpellName = strArgSpellName end

	local CombatEvent = self:NewCombatEvent(unitCaster, unitTarget, eMissType, 0, strSpellName)
	
	self:UpdateDamageSpell(CombatEvent)
end


function GalaxyMeter:OnCombatLogDamage(tEventArgs)
end


function GalaxyMeter:OnCombatLogHeal(tEventArgs)
end


function GalaxyMeter:ShouldThrowAwayDamageEvent(unitCaster, unitTarget)
    if unitTarget then

        -- Don't display damage taken by pets (yet)
        if unitTarget:GetType() == "Pet" then
            --gLog:info(string.format("Ignore pet Dmg Taken, Caster: %s, Target: %s, Spell: %s", CombatEvent.Caster, CombatEvent.Target, nSpellId))

            return true

        -- Don't log damage taken (yet)
        elseif unitTarget:GetName() == self.PlayerName then

            --gLog:info(string.format("Scrap DmgTaken event, Type: %d, Caster: %s, Target: %s, Spell: %s",
            --    CombatEvent.DamageType, CombatEvent.Caster, CombatEvent.Target, CombatEvent.SpellId))

            return true
        else
            return false
        end

    else
        -- Keep events with no unitCaster for now because they can still be determined useful
        return false
    end
end


-- Determine the type of heal based on the caster and target
-- TODO This is only called from OnDamageOrHealingDone, refactor this
function GalaxyMeter:GetHealEventType(unitCaster, unitTarget)

    --local playerUnit = GameLib.GetPlayerUnit()

	if bDebug then
		if not self.unitPlayer then
			gLog:warn("GetHealEventType: self.unitPlayer is nil!")
			return 0
		end
	end

    if unitCaster == self.unitPlayer then

        if unitTarget == self.unitPlayer then
            return eTypeDamageOrHealing.PlayerHealingInOut
        end

        return eTypeDamageOrHealing.PlayerHealingOut

    elseif unitTarget == self.unitPlayer then
        return eTypeDamageOrHealing.PlayerHealingIn
    else
        -- It's possible for your pet to heal other people?!

        gLog:info(string.format("Unknown Heal - Caster: %s, Target: %s", self:GetUnitName(unitCaster), self:GetUnitName(unitTarget)))

        return eTypeDamageOrHealing.PlayerHealingOut
    end
end


function GalaxyMeter:GetDamageEventType(unitCaster, unitTarget)
    --local playerUnit = GameLib.GetPlayerUnit()

    if bDebug then
        if not self.unitPlayer then
            gLog:warn("GetDamageEventType: self.unitPlayer is nil!")
			return 0
        end
    end

    if unitTarget == self.unitPlayer then

        if unitCaster == self.unitPlayer then
            return eTypeDamageOrHealing.PlayerDamageInOut
        end

        return eTypeDamageOrHealing.PlayerDamageIn
    else
        return eTypeDamageOrHealing.PlayerDamageOut
    end
end


-- Event handler for incoming and outgoing damage and healing
-- Currently this only receives events which the player unit initiates or is the target of
function GalaxyMeter:OnDamageOrHealingDone(unitCaster, unitTarget, eDamageType, nDamage, nShieldAbsorbed, nAbsorptionAmount, bCritical, strArgSpellName)

	self:Rover("unitCaster", unitCaster)
	self:Rover("unitTarget", unitTarget)
	self:Rover("eDamageType", eDamageType)
	self:Rover("strArgSpellName", strArgSpellName)


	if not self.bInCombat then return nil end

    -- TODO Move this into NewCombatEvent
    local strSpellName = "Unknown" if strArgSpellName and string.len(strArgSpellName) > 0 then strSpellName = strArgSpellName end

    local event = self:NewCombatEvent(unitCaster, unitTarget, 0, eDamageType, strSpellName, nDamage, nShieldAbsorbed, nAbsorptionAmount, bCritical)

    -- Determine the spell TypeId, still need unitTarget and unitCaster for that
    if self:IsHealEvent(event.DamageType) then

        event.TypeId = self:GetHealEventType(unitCaster, unitTarget)

    else

        -- Check if incoming dmg on pet or self for now, which we aren't tracking yet
        if self:ShouldThrowAwayDamageEvent(unitCaster, unitTarget) then
            return
        end

        event.TypeId = self:GetDamageEventType(unitCaster, unitTarget)

        -- Should we trigger a new log segment?
        if self.bNeedNewLog then
            self:StartLogSegment()
            self.bNeedNewLog = false
            self.tCurrentLog.name = event.Target
            gLog:info(string.format("OnDamage: Set activeLog.name to %s", event.Target))
        end

    end

    if event.TypeId > 0 then
        self:UpdatePlayerSpell(event)
    else
        gLog:warn("OnDamage: Something went wrong!  Invalid type Id!")
        return
    end

		
	-- Count pet actions as actions of the player, done after UpdateSpell because AddPlayer sets CasterClassId to CombatEvent.Caster
	if not unitCaster then
		--gLog:info(string.format("Pet Damage, set CasterID to %s", CombatEvent.CasterId))
		event.CasterClassId = self.unitPlayer:GetClassId()
	else
	
        -- Check unitCaster here to prevent nil caster events from being sent
        if event.Caster == self.PlayerName then
            self:SendCombatMessage(event)
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

    local strMobName = tEvent.PlayerName

    --gLog:info(string.format("GetPlayer(tLog, %s)", playerName))

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

    self:Rover("tCurrentLog: GetMob", tLog)
    self:Rover("tEvent: GetMob", tEvent)

    return player
end

-- Look up player by name
function GalaxyMeter:FindPlayer(tLog, playerName)
    return tLog[playerName]
end


-- Find or create player data table
-- @return Player data table
function GalaxyMeter:GetPlayer(tLog, tEvent)

    local playerName = tEvent.PlayerName

    --gLog:info(string.format("GetPlayer(tLog, %s)", playerName))

    local player = self:FindPlayer(tLog, playerName)

    if not player then
        player = {
            -- Info
            playerName = playerName,                -- Player name
            playerId = tEvent.PlayerId,             -- Player GUID?
            classId = tEvent.CasterClassId,         -- Player Class Id

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

        tLog[playerName] = player
    end

    self:Rover("tCurrentLog: GetPlayer", tLog)
    self:Rover("tEvent: GetPlayer", tEvent)

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
            missCount = 0,
            dodgeCount = 0,
            blockCount = 0,

            -- Totals
            total = 0,                  -- total damage, totalNormal + totalCrit
            --totalNormal = 0,          -- total damage from hits, excludes crit damage
            totalCrit = 0,              -- total damage from crits
            totalShield = 0,            -- damage or healing done to shields
            totalAbsorption = 0,        --
            avg = 0,
            avgCrit = 0,
            --min = 0, max = 0, minCrit = 0, maxCrit = 0,
        }
    end

    return tSpellTypeLog[spellName]
end


--
function GalaxyMeter:TallySpellAmount(tEvent, tSpell)

	if not tSpell.dmgType then tSpell.dmgType = tEvent.DamageType end

    local nAmount = tEvent.Damage

    -- Spell Total
    tSpell.total = tSpell.total + nAmount

    -- Spell total casts, all hits crits and misses
    tSpell.castCount = tSpell.castCount + 1

    if tEvent.Critical then
        tSpell.critCount = tSpell.critCount + 1
        tSpell.totalCrit = tSpell.totalCrit + nAmount

    elseif tEvent.Block then
        tSpell.blockCount = tSpell.blockCount + 1

    elseif tEvent.Dodge then
        tSpell.dodgeCount = tSpell.dodgeCount + 1

    elseif tEvent.Miss then
        tSpell.missCount = tSpell.missCount + 1
    end

    -- Shield Absorption - Total damage includes dmg done to shields while spell breakdowns dont
    if tEvent.ShieldAbsorbed and tEvent.ShieldAbsorbed > 0 then
        tSpell.totalShield = tSpell.totalShield + tEvent.ShieldAbsorbed

        tSpell.total = tSpell.total + tEvent.ShieldAbsorbed
    end

    -- Absorption
    if tEvent.AbsorptionAmount and tEvent.AbsorptionAmount > 0 then
        tSpell.totalAbsorption = tSpell.totalAbsorption + tEvent.AbsorptionAmount

        tSpell.total = tSpell.total + tEvent.AbsorptionAmount
    end

    -- Counts misses dodges and blocks as 0
    -- Also counts dot ticks with the same name such as Mind Burst dot =(
    tSpell.avg = tSpell.total / tSpell.castCount + tSpell.critCount

    tSpell.avgCrit = tSpell.totalCrit / tSpell.critCount

	if not tSpell.max or nAmount > tSpell.max then
		tSpell.max = nAmount
	end

	if (not tSpell.min or nAmount < tSpell.min) and nAmount > 0 then
		tSpell.min = nAmount
	end
end


function GalaxyMeter:UpdatePlayerSpell(tEvent)
    local CasterId = tEvent.CasterId
    local spellName = tEvent.SpellName
    local casterType = tEvent.CasterType
    local nAmount = tEvent.Damage
    local activeLog = nil

    if bDebug then
        if not nAmount then
            gLog:fatal("UpdatePlayerSpell: nAmount is nil, spell: " .. spellName)
            return
        end
    end

    if (casterType == "Player" or casterType == "Pet") then
        -- Caster is a player or pet
        activeLog = self.tCurrentLog["players"]
    elseif casterType == "NonPlayer" then
        activeLog = self.tCurrentLog["mobs"]
    else
        -- If we got here after already attempting to not pay attention to incoming damage, then I need to fix this
        --Log = self.tCurrentLog["mobs"]
        gLog:warn("Unknown caster type, going to fail... " .. casterType)
    end

    if not activeLog then
        gLog:fatal("Nil log after checking casterType: " .. casterType)
        return
    end

    -- Finds existing or creates new player entry
    -- Make sure CombatEvent.classid is properly set to the player if their pet used a spell!!!
    local player = self:GetPlayer(activeLog, tEvent)

    local spell = nil

    -- Player tally and spell type
    -- TODO Generalize this comparison chain
    if tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingInOut then

        -- Special handling for self healing, we want to count this as both healing done and received
        -- Maybe add option to enable tracking for this

        player.healingDone = player.healingDone + nAmount
        player.healingTaken = player.healingTaken + nAmount
		player.healed[tEvent.Target] = (player.healed[tEvent.Target] or 0) + nAmount

        local spellOut = self:GetSpell(player.healingOut, spellName)
        local spellIn = self:GetSpell(player.healingIn, spellName)

        self:TallySpellAmount(tEvent, spellOut)
        self:TallySpellAmount(tEvent, spellIn)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingOut then
        player.healingDone = player.healingDone + nAmount
		player.healed[tEvent.Target] = (player.healed[tEvent.Target] or 0) + nAmount

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

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageOut then
        player.damageDone = player.damageDone + nAmount
		player.damaged[tEvent.Target] = (player.damaged[tEvent.Target] or 0) + nAmount

        spell = self:GetSpell(player.damageOut, spellName)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageIn then
        player.damageTaken = player.damageTaken + nAmount

        spell = self:GetSpell(player.damageIn, spellName)

    else
        gLog:fatal(string.format("Unknown type %d in UpdatePlayerSpell!", tEvent.TypeId))
        gLog:fatal(string.format("Spell: %s, Caster: %s, Target: %s, Amount: %d",
            spellName, CasterId, tEvent.Target, nAmount))
    end

    if spell then
        self:TallySpellAmount(tEvent, spell)
    end

    --[[
    if tEvent.Target then
        -- Make sure destination exists in player
        if not player.damaged[tEvent.Target] then
            player.damaged[tEvent.Target] = nAmount
        else
            player.damaged[tEvent.Target] = player.damaged[tEvent.Target] + nAmount
        end
    end
    --]]

end



-----------------------------------------------------------------------------------------------
-- List Generators
--
-- TODO These are pretty similar... Consider consolidating them into a more generic method
-----------------------------------------------------------------------------------------------

--
-- @param tLogSegment Log entry currently being displayed
-- @param type Segment subtype, healingIn/Out etc
-- @return tList, tTotal Overall list entries, total
-- Do we need an option for players/mobs?
function GalaxyMeter:GetOverallList()

	local tLogSegment = self.vars.tLogDisplay
	local mode = self.vars.tMode

	-- What if its overall mob dmg? Grab segment type from mode
	local tSegmentType = tLogSegment.players

    local tList = {}
	local tTotal = {}

    for k, v in pairs(tSegmentType) do

		local nAmount = v[mode.type]

		tTotal.t = (tTotal.t or 0) + nAmount

        table.insert(tList, {
            n = k,
            t = nAmount,
            c = self.ClassToColor[v.classId],
			click = function(m, btn)
				gLog:info("OverallMenu, current mode =")
				gLog:info(mode)

				-- Call next/prev
				-- args are the specific player log table, subType
				if btn == 0 then
					gLog:info("Overall -> Next " .. k .. " " .. mode.type)

					--gLog:info(string.format("MenuPlayerSelection: %s -> %s", tLogPlayer.playerName, subType))

					self.vars.tCurrentPlayer = tSegmentType[k]

					self:PushMode()
					-- damageDone -> "Player Damage Done Breakdown", etc
					self.vars.tMode = self.tModeFromSubType[mode.type]

					self.vars.tCurrentPlayerSpells = tSegmentType[k][self.vars.tMode.type]

					self:Rover("tCurrentPlayer", self.vars.tCurrentPlayer)
					self:Rover("tCurrentPlayerSpells", self.vars.tCurrentPlayerSpells)

					self.bDirty = true

				elseif btn == 1 and mode.prev then
					gLog:info("Overall -> Prev")
					--m.Rover(m, "GetOverallList: tList", m.vars.tMode)

					self.vars.tMode.prev(m, v, mode.type)

					self.bDirty = true
				end

			end
        })
	end

	local strTotalText = string.format("%s - %d (%.2f) - %s",
		string.format(mode.pattern, tLogSegment.name),
		total,
		total / tLogSegment.combat_length,
		self:SecondsToString(tLogSegment.combat_length))

    return tList, tTotal, mode.name, strTotalText
end


-- Get player listing for this segment
-- @param tLogSegment Log segment of interest
-- @param subType Dmg/Healing In/Out etc
-- @param strModeName
-- @param playerName
-- @return Tables containing player damage done
--    1) Ordered list of individual spells
--    2) Total
function GalaxyMeter:GetPlayerList()
    local tList = {}

	-- These should have already been set
	local tLogSegment = self.vars.tLogDisplay
	local tPlayerLog = self.vars.tCurrentPlayer
	local mode = self.vars.tMode

	-- convert to damageDone/damageTaken
	local dmgTypeTotal = self.tSubTypeFromList[mode.type]

    local tTotal = {
        n = string.format("%s's %s", tPlayerLog.playerName, mode.type),
        t = tPlayerLog[dmgTypeTotal], -- "Damage to XXX"
        c = kDamageStrToColor.Self
    }

    for k, v in pairs(tPlayerLog[mode.type]) do
        table.insert(tList, {
            n = k,
            t = v.total,
            --c = kHostilityToColor[3],
			c = kDamageTypeToColor[v.dmgType],
			tStr = nil,
			click = function(m, btn)
				if btn == 0 then
					gLog:info("Player -> Next")

					self:PushMode()

					self.vars.tCurrentSpell = v

					self.vars.tMode = self.tModes["Spell Breakdown"]

					self.bDirty = true

				elseif btn == 1 then
					gLog:info("Player -> Prev")
					--m.Rover(m, "GetOverallList: tList", m.vars.tMode)

					local tMode = self:PopMode()
					if tMode then
						self.vars.tMode = tMode
						self.bDirty = true
					end

				end
			end
        })
	end

	local strDisplayText = string.format("%s's %s", tPlayerLog.playerName, mode.type)

	local strTotalText = string.format("%s on %s - %d (%.2f) - %s",
		--"%s's blah on %s"
		string.format(mode.pattern, strPlayerName, mode.name, tLogSegment.name),
		total,
		total / tLogSegment.combat_length,
		self:SecondsToString(tLogSegment.combat_length))

    return tList, tTotal, strDisplayText, strTotalText
end


function GalaxyMeter:GetSpellList()
	local tSpell = self.vars.tCurrentSpell

	if not tSpell then
		gLog:fatal("GetSpellList() nil tSpell")
		return
	end

	local cFunc = function(m, btn)
		if btn == 1 then
			local tMode = self:PopMode()
			if tMode then
				self.vars.tMode = tMode
				self.bDirty = true
			end
		end
	end

	local tList = {
		{n = string.format("Total Damage (%s)", kDamageTypeToString[tSpell.dmgType]), tStr = tSpell.total, click = cFunc},
		{n = "Cast Count/Avg", tStr = string.format("%d - %.2f", tSpell.castCount, tSpell.avg), click = cFunc},
		{n = "Crit Damage", tStr = string.format("%d (%.2f%%)", tSpell.totalCrit, tSpell.totalCrit / tSpell.total * 100), click = cFunc},
		{n = "Crit Count/Avg/Rate", tStr = string.format("%d - %.2f (%.2f%%)", tSpell.critCount, tSpell.avgCrit, tSpell.critCount / tSpell.castCount * 100), click = cFunc},
		{n = "Total Shields", tStr = tSpell.totalShield, click = cFunc},
		{n = "Total Absorb", tStr = tSpell.tottalAbsorption, click = cFunc},
		{n = "Blocks", tStr = tSpell.blocks, click = cFunc},
		{n = "Dodges", tStr = tSpell.dodges, click = cFunc},
		{n = "Misses", tStr = tSpell.misses, click = cFunc},
	}

	if tSpell.max and tSpell.min then
		table.insert(tList, 5, {n = "Min/Max", tStr = string.format("%d / %d", tSpell.min, tSpell.max), click = cFunc})
	end

	local strDisplayText = string.format("%s's %s", self.vars.tCurrentPlayer.playerName, tSpell.name)

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

    local tReportStrings = mode.report(mode.display())

	-- Report to guild, eventually this will be configurable
	local chan = "g"

    for i = 1, #tReportStrings do
        ChatSystemLib.Command("/" .. chan .. " " .. tReportStrings[i])
    end

end

--[[
function GalaxyMeter:ReportPlayerList()

    local tPlayerList, tTotal, strDisplayText = self:GetPlayerList()

	local tLogSegment = self.vars.tLogDisplay
	local mode = self.vars.tMode
	local combatLength = tLogSegment.combat_length
	local tStrings = {}
	local total = tTotal.t

	if mode.sort then
    	table.sort(tPlayerList, mode.sort)
	end

    table.insert(tStrings, string.format("%s on %s - %d (%.2f) - %s",
        --"%s's blah on %s"
        string.format(mode.pattern, strPlayerName, mode.name, tLogSegment.name),
        --strPlayerName,
        --tReportTypes[self.vars.mode],
        --tLogSegment.name,  --
        total,
        total / combatLength,
        self:SecondsToString(combatLength)))

	-- This is the same as in report overall list
    for i=1,#tPlayerList do
        local v = tPlayerList[i]
        table.insert(tStrings, string.format("%d) %s - %s (%.2f)  %.2f%%",
            i, v.n, v.t, v.t / combatLength, v.t / total * 100))
    end

    return tStrings
end


-- @param tList List generated by GetOverallList
function GalaxyMeter:ReportOverallList()

    local tPlayerList, tTotal, strDisplayText = self:GetOverallList()

	local tLogSegment = self.vars.tLogDisplay
	local mode = self.vars.tMode
	local combatLength = tLogSegment.combat_length
	local tStrings = {}
	local total = tTotal.t or 0

	if mode.sort then
    	table.sort(tPlayerList, mode.sort)
	end

    table.insert(tStrings, string.format("%s - %d (%.2f) - %s",
        string.format(mode.pattern, tLogSegment.name),
        total,
        total / combatLength,
        self:SecondsToString(combatLength)))

	-- This is the same as in report player list
    for i=1,#tPlayerList do
        local v = tPlayerList[i]
        table.insert(tStrings, string.format("%d) %s - %s (%.2f)  %.2f%%",
            i, v.n, v.t, v.t / combatLength, v.t / total * 100))
    end

    return tStrings
end
--]]

-- @param tList List generated by Get*List
function GalaxyMeter:ReportGenericList(tList, tTotal, strDisplayText, strTotalText)

	local tLogSegment = self.vars.tLogDisplay
	local mode = self.vars.tMode
	local combatLength = tLogSegment.combat_length
	local tStrings = {}
	local total = tTotal.t or 0

	if mode.sort then
		table.sort(tPlayerList, mode.sort)
	end

	if strTotalText and strTotalText ~= "" then
		table.insert(tStrings, strTotalText)
	end

	for i = 1, #tList do
		local v = tPList[i]
		table.insert(tStrings, string.format("%d) %s - %s (%.2f)  %.2f%%",
			i, v.n, v.t, v.t / tLogSegment.combat_length, v.t / total * 100))
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
-- TODO Maybe combine this with Get*List or something to avoid to much looping?
function GalaxyMeter:DisplayList(Listing)

	--self:Rover("DisplayList: List", Listing)

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

    if not self.wndMain:IsVisible() then
        return
	end


	local mode = self.vars.tMode

	--local tLogSegment, strPlayerName, strDisplayText = self:GetListData(mode)

    -- Calls:
    --
    -- GetOverallList(tLogSegment, subType)
	-- name = "Overall Damage Done"
	-- pattern = "Damage on %s"
	--
    -- GetPlayerList(tLogSegment, subType, strPlayerName)
	-- name = "%s's Damage Done"
	-- pattern = "%s's Damage to %s"

	--[[
    local tList, tTotal, strDisplayText = mode.display(self,			-- Self reference needed for calling object method
										tLogSegment,	--
										mode.type,		-- Subtable in this segment
										strPlayerName)	-- Unused for Overall Lists
	--]]

	local tList, tTotal, strDisplayText = mode.display(self)

    if mode.sort ~= nil then
        table.sort(tList, mode.sort)
    end

	-- if option to show totals
	if tTotal ~= nil then
		tTotal.n = strDisplayText
		tTotal.click = function(m, btn)
			if btn == 1 then
				local tMode = self:PopMode()
				if tMode then
					self.vars.tMode = tMode
					self.bDirty = true
				end
			end
		end

		table.insert(tList, 1, tTotal)
	end

	-- Text below the meter
	self.Children.DisplayText:SetText(strDisplayText)
	self.Children.TimeText:SetText("Timer: " .. self:SecondsToString(self.tCurrentLog.combat_length))

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

-- TODO
-- when the Cancel button is clicked
function GalaxyMeter:OnClearAll()
	--if not self.bInCombat then return nil end
	self.log = {}
	self.vars.nLogIndex = 0
	self.vars.tLogDisplay = 0
	self:RefreshDisplay()
end


function GalaxyMeter:OnEncounterDropDown( wndHandler, wndControl, eMouseButton )
	if not self.wndEncList:IsVisible() then
		self.wndEncList:Show(true)
		
		-- Newest Entry at the Top
		for i = 1, #self.log do
			local wnd = Apollo.LoadForm("GalaxyMeter.xml", "EncounterItem", self.Children.EncItemList, self)
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
	if time > 60 then
		Time_String = string.format("%sm:%.0fs", Min , Sec )
	else
		Time_String = string.format("%.2fs", Sec )
	end
	return Time_String
end


-----------------------------------------------------------------------------------------------
-- Menu Functions
-----------------------------------------------------------------------------------------------

-- Pop last mode off of the stack
function GalaxyMeter:PopMode()
	if self.vars.tModeLast and #self.vars.tModeLast > 0 then
		return table.remove(self.vars.tModeLast)
	end

	return nil
end


-- Push mode onto the stack
function GalaxyMeter:PushMode()
	self.vars.tModeLast = self.vars.tModeLast or {}

	table.insert(self.vars.tModeLast, self.vars.tMode)
end


-- TODO Generalize this into DisplayMenu or something
function GalaxyMeter:DisplayMainMenu()
    local tMenuList = {}

	--gLog:info("DisplayMainMenu()")

    for k,v in pairs(self.tMainMenu) do
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



-- Set current mode to the main menu
function GalaxyMeter:MenuMain()

	self.vars.tMode = self.tModes["Main Menu"]

	self:Rover("MenuMain: tItems", self.tItems)
end


-- A player was clicked from an Overall menu, update the mode to the appropriate selection
-- @param tLogPlayer Selected player
-- @param subType log subtype damageIn/Out etc
--[[
function GalaxyMeter:MenuPlayerSelection(tLogPlayer, subType)

	gLog:info("MenuPlayerSelection()")
	gLog:info(tLogPlayer)

	gLog:info(string.format("MenuPlayerSelection: %s -> %s", tLogPlayer.playerName, subType))

	-- damageDone -> "Player Damage Done Breakdown"
	self.vars.tModeLast = self.vars.tMode
	self.vars.tMode = self.tModeFromSubType[subType]
end
--]]


-----------------------------------------------------------------------------------------------
-- ItemList Functions
-----------------------------------------------------------------------------------------------
-- clear the item list
function GalaxyMeter:DestroyItemList()
	-- destroy all the wnd inside the list
	for idx,wnd in ipairs(self.tItems) do
		wnd:Destroy()
	end

	-- clear the list item array
	self.tItems = {}
end


-- add an item into the item list
function GalaxyMeter:AddItem(i)
	-- load the window item for the list item
	local wnd = Apollo.LoadForm("GalaxyMeter.xml", "ListItem", self.wndItemList, self)
	
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

    self:Rover("tItems", self.tItems)
	
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
        gLog:info(string.format("control %s id %d, name '%s', button %d", tostring(wndControl), wndControl:GetId(), wndControl:GetName(), tostring(eMouseButton)))

        local id = wndControl:GetId()

        -- find relevant clicked menu item based on id of clicked control
        for i,v in ipairs(self.tItems) do
            if v.id == id and v.OnClick then
				gLog:info("Calling OnClick()")
				gLog:info(v)
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


function GalaxyMeter:Pack(...)
	return { ... }, select("#", ...)
end


function GalaxyMeter:OnSave(eType)
	local tSave = {}

	if eType == GameLib.CodeEnumAddonSaveLevel.General then

		tSave.settings = self.settings
		tSave.anchor = self:Pack(self.wndMain:GetAnchorOffsets())
		
		
	elseif eType == GameLib.CodeEnumAddonSaveLevel.Character then
	end
	
	return tSave
end


function GalaxyMeter:OnRestore(eType, t)
	if eType == GameLib.CodeEnumAddonSaveLevel.General then
		self.tSavedSettings = t
		self:Rover("tSavedSettings", self.tSavedSettings)
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

	self.Children.EncounterButton:SetText(self.vars.tLogDisplay.name)
	self.Children.TimeText:SetText("Timer: "..self:SecondsToString(self.vars.tLogDisplay.combat_length))
	
	self:HideEncounterDropDown()
	
	self:RefreshDisplay()
end


function GalaxyMeter:OnEncounterItemMouseEnter( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(true)
end


function GalaxyMeter:OnEncounterItemMouseExit( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(false)
end


-----------------------------------------------------------------------------------------------
-- GalaxyMeter Instance
-----------------------------------------------------------------------------------------------
local GalaxyMeterInst = GalaxyMeter:new()
GalaxyMeterInst:Init()
