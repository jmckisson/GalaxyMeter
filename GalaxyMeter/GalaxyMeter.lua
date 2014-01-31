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
local GalMet_LogVersion = 5
local bDebug = true
local bGroupSync = true
local bSyncSpells = true
local nSyncFrequency = 4.5


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


-- Message types for use in the ICCommLib channel
local eMsgType = {
	CombatEvent = 0,
	CombatStopEvent = 1,
	Spell = 2,
	Totals = 3,
	List = 4,	-- Damaged/Healed list?
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

	self.bNeedNewLog = false

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

		-- Chat: Shared Logging
		if bGroupSync then
			Apollo.RegisterEventHandler("Group_Join",						"OnGroupJoin", self)
			Apollo.RegisterEventHandler("Group_Left",						"OnGroupLeft", self)
			Apollo.RegisterEventHandler("Group_Updated",					"OnGroupUpdated", self)
		end

		-- Combat Timer
	    Apollo.CreateTimer("CombatTimer", 0.05, true)
	    Apollo.RegisterTimerHandler("CombatTimer", 						"OnTimer", self)
		Apollo.StopTimer("CombatTimer")
		
		-- Player Check Timer
	    Apollo.CreateTimer("PlayerCheckTimer", 1, true)	-- Pulsing Timer
	    Apollo.RegisterTimerHandler("PlayerCheckTimer", 				"OnPlayerCheckTimer", self)
		Apollo.StopTimer("PlayerCheckTimer")
		
	    -- Load Forms
	    self.wndMain = Apollo.LoadForm("GalaxyMeter.xml", "GalaxyMeterForm", nil, self)
	    self.wndMain:Show(false)
		self.wndEncList = self.wndMain:FindChild("EncounterList")
	    self.wndEncList:Show(false)
	
		-- Store Child Widgets
		self.Children = {}
		self.Children.TimeText = self.wndMain:FindChild("Time_Text")
		self.Children.DisplayText = self.wndMain:FindChild("Display_Text")
		--self.Children.EncounterButton = self.wndMain:FindChild("EncounterButton")
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
            ["Player Damage Done"] = {
                name = "Overall Damage Done",       		-- Display name
                pattern = "Damage done on %s",           	--
                display = self.GetOverallList,
                report = self.ReportGenericList,
                type = "damageDone",
                prev = self.MenuMain,						-- Right Click, previous menu
                next = self.MenuPlayerSelection,			-- Left Click, next menu
                sort = function(a,b) return a.t > b.t end,
            },
            ["Player Damage Taken"] = {
                name = "Overall Damage Taken",
                pattern = "Damage taken from %s",
                display = self.GetOverallList,
                report = self.ReportGenericList,
                type = "damageTaken",
                prev = self.MenuMain,
                next = self.MenuPlayerSelection,
                sort = function(a,b) return a.t > b.t end,
            },
            ["Player Healing Done"] = {
                name = "Overall Healing Done",
                pattern = "Healing Done on %s",
                display = self.GetOverallList,
                report = self.ReportGenericList,
                type = "healingDone",
                prev = self.MenuMain,
                next = self.MenuPlayerSelection,
                sort = function(a,b) return a.t > b.t end,
            },
            ["Player Healing Received"] = {
                name = "Overall Healing Taken",
                pattern = "Healing Taken on %s",
                display = self.GetOverallList,
                report = self.ReportGenericList,
                type = "healingTaken",
                prev = self.MenuMain,
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
			["Interrupts"] = {
				name = "Interrupts",
				display = nil,
				report = nil,
				--display = self.GetInterruptList,
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
				prev = self.MenuMain,
				next = nil,
				sort = function(a,b) return a.t > b.t end,
			},
        }

        self.tMainMenu = {
            ["Player Damage Done"] = self.tModes["Player Damage Done"],
            ["Player Damage Taken"] = self.tModes["Player Damage Taken"],
			["Player Healing Done"] = self.tModes["Player Healing Done"],
			["Player Healing Received"] = self.tModes["Player Healing Received"],
			["Interrupts"] = self.tModes["Interrupts"],
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

	if bGroupSync then
		if self.bInCombat and os.clock() - (self.tLastSync or 0) >= nSyncFrequency then
			local tChanged = self.tCurrentLog.changed

			local tPlayer = self.tCurrentLog.players[self.PlayerName]

			if not tPlayer then
				gLog:fatal(string.format("Error finding player %s in current log", self.PlayerName))
			else

				--Always send damage/healing in/out
				self:QueueSpellSync("t", {tPlayer.damageDone, tPlayer.damageTaken, tPlayer.healingDone, tPlayer.healingTaken})

				if bSyncSpells then
					for spellType, spells in pairs(tChanged) do

						for k, changed in pairs(spells) do
							if changed then
								gLog:info("==> " .. k)

								self:QueueSpellSync(spellType, k)

								tChanged[spellType][k] = false
							end
						end
					end
				end

				self.tLastSync = os.clock()

				self:Rover("tSyncQueue", self.tSyncQueue)
			end
		end

		if self.tSyncQueue then
			if self.CommChannel then
				local result = self.CommChannel:SendMessage(self.tSyncQueue)
				if not result then
					gLog:warn("Error calling SendMessage()")
				end
			end
			self.tSyncQueue = nil
			--gLog:info("Cleared tSyncQueue")
		end

	end

end


--[[
Format:
 {	name = "Player Name",
 	msgs = {
 		[1] = {
 			type = type,
 			data = data,
 		},
 		[2] = etc
 	},
 }
 --]]
function GalaxyMeter:QueueSpellSync(type, tData)
	self.tSyncQueue = self.tSyncQueue or {name = self.PlayerName, msgs = {}}

	local tMsg = nil

	if type == "t" then
		-- totals
		tMsg = {
			t = eMsgType.Totals,	-- totals update
			d = tData				-- totals data
		}
	else
		-- Find player and spell
		local player = self.tCurrentLog.players[self.PlayerName]

		if not player then
			gLog:fatal(string.format("QueueSpellSync: Error finding player '%s'", self.PlayerName))
		end

		local spell = player[type][tData]

		if not spell then
			gLog:fatal(string.format("QueueSpellSync: Error finding spell '%s->%s'", type, tData))
			return
		end

		tMsg = {
			t = eMsgType.Spell,	-- spell update
			s = type,			-- school
			d = spell,			-- spell data
		}

	end

	if tMsg then
		table.insert(self.tSyncQueue.msgs, tMsg)
	else
		gLog:warn(string.format("tMsg nil in QueueSpellSync, type %s, data %s", type, tstring(tData)))
	end
end


-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnTimer
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnTimer()
	
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
	Apollo.StartTimer("PlayerCheckTimer")
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
	end

	self.bDirty = true

	Apollo.StartTimer("CombatTimer")
end


function GalaxyMeter:NewLogSegment()
    -- Push a new log entry to the top of the history stack
    local log = {
        start = 0,
        combat_length = 0,
        name = "Current",	-- Segment name
        ["players"] = {},	-- Array containing players involved in this segment
        ["mobs"] = {},		-- Array containing mobs involved in this segment
		["changed"] = {
			["damageOut"] = {},
			["damageIn"] = {},
			["healingOut"] = {},
			["healingIn"] = {},
		},	-- Array indicating which spells have been recently updated
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

    --self:Rover("lastLog", self.tCurrentLog)
    --self:Rover("log", self.log)

    -- Pop off oldest, TODO Add config option to keep N old logs
    if #self.log >= 50 then
        table.remove(self.log)
    end

    Apollo.StopTimer("CombatTimer")

	-- We no longer need the changed section
	self.tCurrentLog.changed = nil

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
	
	if unit:GetId() == GameLib.GetPlayerUnit():GetId() then
	
		-- We weren't in combat before, so start new segment
		if not self.bInCombat then
			self.bNeedNewLog = true
            gLog:info("Setting bNeedNewLog = true")
        end

		-- If we were in combat, and not anymore...
        if self.bInCombat and not bInCombat then
			gLog:info("Sending combat stop message")
			self:SendCombatMessage(eMsgType.CombatStopEvent, {})
			-- Combat timer will still run until the last member of the group exits combat
        end
	
		self.bInCombat = bInCombat
	else
		if unit:IsInYourGroup() then
			local playerName = unit:GetName()
			if self.tGroupMembers[playerName] == nil then
				self.tGroupMembers[playerName] = {}
			end

			gLog:info(string.format("OnEnteredCombat, group member %s combat %s", playerName, tostring(bInCombat)))

			self.tGroupMembers[playerName] = {
				name = playerName,
				id = unit:GetId(),
				class = unit:GetClass(),
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
	self.CommChannel = nil
	self.ChannelName = ""
end


function GalaxyMeter:OnCombatMessage(channel, tData)

	if not bGroupSync or channel ~= self.CommChannel then return nil end

	local playerName = tData.name

	-- Ignore messages sent by yourself?
	if tData.playerName == self.PlayerName then
		gLog:warn("Ignored sync msg sent by self")
		return
	end

	local player = self:GetPlayer(self.tCurrentLog.players, {PlayerName = playerName})

	gLog:info("=> data from " .. playerName)
	self:Rover("chanCombatMsg", tMsg)
	--gLog:info(tData)

	-- Assume that this group member is in combat
	if self.tGroupMembers[playerName] == nil then
		gLog:warn(string.format("OnCombatMessage, added %s to group list", playerName))
		-- player class won't be set properly when initializing here
		self.tGroupMembers[playerName] = {
			combat = true,
			name = playerName,	-- redundant
		}
	elseif not self.tGroupMembers[playerName].combat then
		gLog:warn(string.format("Group member %s in combat now! old value: %s", playerName, tostring(self.tGroupMembers[playerName].combat)))
		self.tGroupMembers[playerName].combat = true
	end

	local bGroupInCombat = self:GroupInCombat()

	--gLog:info(string.format("** %s msg, start: %d, needNew: %s, groupInCombat: %s", tMsg.playerName, self.tCurrentLog.start, tostring(self.bNeedNewLog), tostring(bGroupInCombat)))

	-- If the current segment hasnt started and a group member is in combat, flag for creation of a new log
	if self.tCurrentLog.start == 0 and not self.bNeedNewLog then
		if bGroupInCombat then
			gLog:warn("OnCombatMessage: NeedNewLog = true")
			self:StartLogSegment()

			-- Ok we don't have the target information anymore so try to findthem by name in your group and get their target
			-- and hope its correct
			--self.tCurrentLog.name = tEvent.Target
		else
			--gLog:warn("group not in combat")
		end
	end

	for k, v in pairs(tData.msgs) do
		local tMsg = v

		if tMsg.t == eMsgType.CombatEvent then

		elseif tMsg.t == eMsgType.Spell then
			local spellSchool = tMsg.s
			local spellName = tMsg.d.name

			player[spellSchool][spellName] = tMsg.d

			self.bDirty = true

		elseif tMsg.t == eMsgType.Totals then
			player.damageDone = tMsg.d[1]
			player.damageTaken = tMsg.d[2]
			player.healingDone = tMsg.d[3]
			player.healingTaken = tMsg.d[4]

			self.bDirty = true

		elseif tMsg.t == eMsgType.CombatStopEvent then
			gLog:warn("chanMsgCombatStopEvent from " .. playerName)
			self.tGroupMembers[playerName].combat = false
		end

	end -- end for pairs(tData)
end



function GalaxyMeter:SendCombatMessage(eType, tEvent)
	if bGroupSync and self.CommChannel then
		
		local msg = {
            name = self.PlayerName,
			msgs = {}
		}
		msg.msgs[1] = {type = eType}

		-- whatever just send immediately
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
				id = i,	-- What do we use this for?
				combat = false,
            }
        end

        table.insert(tTempMembers, charName)
	end
	
	-- Maintain list of current group members
    -- Now remove items in tGroupMembers that don't exist in the temp table
	for p in pairs(self.tGroupMembers) do
		-- If not in temp members, remove
		if tTempMembers[p] ~= nil then

            tTempMembers[p] = nil
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
	gLog:info("OnCombatLogDispel()")
	gLog:info(tEventArgs)
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
	gLog:info("OnCombatLogInterrupted()")
	gLog:info(tEventArgs)
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

	gLog:info("OnCombatLogModifyInterruptArmor()")
	gLog:info(tEventArgs)

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
	gLog:info("OnCombatLogDelayDeath()")
	gLog:info(tEventArgs)
	--[[
	local tCastInfo = self:HelperCasterTargetSpell(tEventArgs, false, true)
	local strSaved = String_GetWeaselString(Apollo.GetString("CombatLog_NotDeadYet"), tCastInfo.strCaster, tCastInfo.strSpellName)
	self:PostOnChannel(string.format("<P TextColor=\"%s\">%s</P>", kstrStateColor, strSaved))
	--]]
end


function GalaxyMeter:OnCombatLogDeath(tEventArgs)
	gLog:info("OnCombatLogDeath()")
	gLog:info(tEventArgs)
	--[[
	self:PostOnChannel(string.format("<P TextColor=\"%s\">%s</P>", kstrStateColor, Apollo.GetString("CombatLog_Death")))
	--]]
end


function GalaxyMeter:OnCombatLogAbsorption(tEventArgs)
	gLog:info("OnCombatLogAbsorption()")
	gLog:info(tEventArgs)
end


function GalaxyMeter:OnCombatLogResurrect(tEventArgs)
end


function GalaxyMeter:OnCombatLogTransference(tEventArgs)
	-- OnCombatLogDamage does exactly what we need so just pass along the tEventArgs
	self:OnCombatLogDamage(tEventArgs)

	gLog:info("OnCombatLogTransference()")
	gLog:info(tEventArgs)

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
	self:Rover("CombatLogDeflect", tEventArgs)

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

	tEvent.TypeId = self:GetDamageEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	-- Should we trigger a new log segment?
	if self.bNeedNewLog then
		self:StartLogSegment()
		self.bNeedNewLog = false
		if tEventArgs.unitTarget:GetType() == "NonPlayer" then
			self.tCurrentLog.name = tEvent.Target
		else
			self.tCurrentLog.name = tEventArgs.unitTarget:GetTarget():GetName()
		end
		gLog:info(string.format("OnDeflect: Set activeLog.name to %s", self.tCurrentLog.name))
	end

	self:SetPlayerSpellUpdated(tEvent)
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
	tEvent.Vuln = tEventArgs.bVulnerable
	tEvent.Overkill = tEventArgs.nOverkill
	tEvent.Result = tEventArgs.eCombatResult
	tEvent.DamageType = tEventArgs.eDamageType
	tEvent.EffectType = tEventArgs.eEffectType

	tEvent.PlayerName = self.PlayerName

	-- if bCaster then player class is caster class, otherwise its the target class
	--if tInfo.strCasterType == "NonPlayer" then

	tEvent.bCaster = (tInfo.strCasterType ~= "NonPlayer")

	-- Check if incoming dmg on pet or self for now, which we aren't tracking yet
	if self:ShouldThrowAwayDamageEvent(tEventArgs.unitCaster, tEventArgs.unitTarget) then
		return
	end

	-- Workaround for lower level players dealing a severely reduced damage to target dummies
	if tEvent.Target == "Target Dummy" and GameLib.GetPlayerUnit():GetLevel() < 50 then
		tEvent.Damage = tEventArgs.nRawDamage
	else
		tEvent.Damage = tEventArgs.nDamageAmount
	end

	tEvent.TypeId = self:GetDamageEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	-- Should we trigger a new log segment?
	if self.bNeedNewLog then
		self:StartLogSegment()
		self.bNeedNewLog = false

		if tEventArgs.unitTarget:GetType() == "NonPlayer" then
			self.tCurrentLog.name = tEvent.Target
		else
			--self.tCurrentLog.name = tEvent.Caster
			self.tCurrentLog.name = tEventArgs.unitTarget:GetTarget():GetName()
		end
		gLog:info(string.format("OnDamage: Set activeLog.name to %s", self.tCurrentLog.name))
	end

	if tEvent.TypeId > 0 and tEvent.Damage then
		self:SetPlayerSpellUpdated(tEvent)
		self:UpdatePlayerSpell(tEvent)
	else
		gLog:warn("OnDamage: Something went wrong!  Invalid type Id!")
		return
	end

	-- Count pet actions as actions of the player, done after UpdateSpell because AddPlayer sets CasterClassId to CombatEvent.Caster
	if not tEventArgs.unitCaster then
		--gLog:info(string.format("Pet Damage, set CasterID to %s", CombatEvent.CasterId))
		event.CasterClassId = self.unitPlayer:GetClassId()
	else

		-- Check unitCaster here to prevent nil caster events from being sent
		--[[
		if tEvent.Caster == self.PlayerName then
			self:SendCombatMessage(eMsgType.CombatEvent, tEvent)
		end
		--]]
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
		self:SetPlayerSpellUpdated(tEvent)
		self:UpdatePlayerSpell(tEvent)
	else
		gLog:warn("OnHeal: Something went wrong!  Invalid type Id!")
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
	}

	if bSpell then
		tInfo.strSpellName = self:HelperGetNameElseUnknown(tEventArgs.splCallingSpell)
	end

	-- TODO It's probably better to detect pets by using unitCaster/TargetOwner
	if tEventArgs.unitCaster then
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
		gLog:info(string.format("HelperCasterTargetSpell unitCaster nil(pet?): Caster[%d] %s, Target[%d] %s",
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

	local selfId = self.unitPlayer:GetId()

    if unitTarget:GetId() == selfId then

        if unitCaster:GetId() == selfId then
            return eTypeDamageOrHealing.PlayerDamageInOut
        end

        return eTypeDamageOrHealing.PlayerDamageIn
	else
		self:Rover("GetDmgType", {selfId = selfId, casterId = unitCaster:GetId(), targetId = unitTarget:GetId()})

		-- Ok so the dmg might be from a pet
		if unitCaster:GetId() == selfId or (unitCaster:GetUnitOwner() and unitCaster:GetUnitOwner():GetId() == selfId) then
		-- This is being set when the caster is not yourself

       		return eTypeDamageOrHealing.PlayerDamageOut
		else

			gLog:info("Unknown dmg type")
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

    --gLog:info(string.format("GetPlayer(tLog, %s)", playerName))

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

		if tEvent.bCaster then
			player.classId = tEvent.CasterClassId
		else
			player.classId = tEvent.TargetClassId
		end

        tLog[playerName] = player
    end

    --self:Rover("tCurrentLog: GetPlayer", tLog)
    --self:Rover("tEvent: GetPlayer", tEvent)

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
            --missCount = 0,
            --dodgeCount = 0,
            --blockCount = 0,

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

	local nAmount = tEvent.Damage

	-- Spell Total
	tSpell.total = tSpell.total + nAmount

	if tEvent.Result == GameLib.CodeEnumCombatResult.Critical then
		tSpell.critCount = tSpell.critCount + 1
		tSpell.totalCrit = tSpell.totalCrit + nAmount
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


--
function GalaxyMeter:SetPlayerSpellUpdated(tEvent)
	local changeLog = self.tCurrentLog.changed

	local spellName = tEvent.SpellName

	-- I don't think we need to set or check the damaged/healed tables as the check will be done on the receiving end

	if tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingInOut then
		changeLog.healingOut[spellName], changeLog.healingIn[spellName] = true, true

	elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingOut then
		changeLog.healingOut[spellName] = true

	elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingIn then
		changeLog.healingIn[spellName] = true

	elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageInOut then
		changeLog.damageOut[spellName], changeLog.damageIn[spellName] = true, true

	elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageOut then
		changeLog.damageOut[spellName] = true

	elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageIn then
		changeLog.damageIn[spellName] = true

	else
		self:Rover("SetPlayerSpellUpdated Error", tEvent)
		gLog:fatal("Unknown type in SetPlayerSpellUpdated!")
		gLog:fatal(string.format("Spell: %s, Caster: %s, Target: %s, Amount: %d",
			spellName, tEvent.Caster, tEvent.Target, tEvent.nAmount or 0))

	end

	--self:Rover("changeLog", changeLog)

end


function GalaxyMeter:UpdatePlayerSpell(tEvent)
    local CasterId = tEvent.CasterId
    local spellName = tEvent.SpellName
    local casterType = tEvent.CasterType
    local nAmount = tEvent.Damage
    local activeLog = nil

	if not nAmount and not tEvent.Deflect then
		gLog:fatal("UpdatePlayerSpell: nAmount is nil, spell: " .. spellName)
		self:Rover("nil nAmount Spell", tEvent)
		return
	end

	activeLog = self.tCurrentLog.players

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
        gLog:fatal("Unknown type in UpdatePlayerSpell!")
        gLog:fatal(string.format("Spell: %s, Caster: %s, Target: %s, Amount: %d",
            spellName, tEvent.Caster, tEvent.Target, nAmount or 0))

		-- spell should be null here, safe to continue on...
    end

    if spell then
        self:TallySpellAmount(tEvent, spell)
		self.bDirty = true
    end

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
	local tTotal = {t=0}

    for k, v in pairs(tSegmentType) do

		local nAmount = v[mode.type] or 0

		tTotal.t = tTotal.t + nAmount

        table.insert(tList, {
            n = k,
            t = nAmount,
            c = self.ClassToColor[v.classId],
			click = function(m, btn)
				gLog:info("OverallMenu, current mode =")
				gLog:info(mode)

				-- Call next/prev
				-- args are the specific player log table, subType
				if btn == 0 and mode.next then
					gLog:info("Overall -> Next " .. k .. " " .. mode.type)
					mode.next(self, k, tSegmentType)

				elseif btn == 1 and mode.prev then
					gLog:info("Overall -> Prev")
					--m.Rover(m, "GetOverallList: tList", m.vars.tMode)
					mode.prev(self, v)

					self.bDirty = true
				end

			end
        })
	end

	local strTotalText = string.format("%s - %d (%.2f) - %s",
		string.format(mode.pattern, tLogSegment.name),
		tTotal.t,
		tTotal.t / tLogSegment.combat_length,
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
			c = kDamageTypeToColor[v.dmgType],
			tStr = nil,
			click = function(m, btn)
				if btn == 0 and mode.next then
					gLog:info("Player -> Next")
					mode.next(self, v)

				elseif btn == 1 then
					gLog:info("Player -> Prev")
					--m.Rover(m, "GetOverallList: tList", m.vars.tMode)
					mode.prev(self)
				end
			end
        })
	end

	local strDisplayText = string.format("%s's %s", tPlayerLog.playerName, mode.type)

	-- "%s's Damage to %s"
	local strModePatternTemp = string.format(mode.pattern, tPlayerLog.playerName, tLogSegment.name)

	local strTotalText = string.format("%s - %d (%.2f) - %s",
		--"%s's blah on %s"
		strModePatternTemp,
		tTotal.t,
		tTotal.t / tLogSegment.combat_length,
		self:SecondsToString(tLogSegment.combat_length))

	--[[
	self:Rover("PlayerList: pattern", {
		text = strTotalText,
		modePattern = mode.pattern,
		modeName = mode.name,
		formattedPattern = strModePatternTemp,
		strDisplayText = strDisplayText,
	})
	--]]

    return tList, tTotal, strDisplayText, strTotalText
end


--[[
function GalaxyMeter:GetOverhealList()

	local tLogSegment = self.vars.tLogDisplay
	local mode = self.vars.tMode

	local tSegmentType = tLogSegment.players

	local tList = {}
	local tTotal = {t=0}

	for k, v in pairs(tSegmentType) do

		local nAmount = v[mode.type]

		tTotal.t = tTotal.t + nAmount

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
		tTotal.t,
		tTotal.t / tLogSegment.combat_length,
		self:SecondsToString(tLogSegment.combat_length))

	return tList, tTotal, mode.name, strTotalText
end
--]]


function GalaxyMeter:GetSpellList()
	local tSpell = self.vars.tCurrentSpell

	if not tSpell then
		gLog:fatal("GetSpellList() nil tSpell")
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

	if tSpell.max and tSpell.min then
		table.insert(tList, {n = "Min/Max", tStr = string.format("%d / %d", tSpell.min, tSpell.max), click = cFunc})
	end

	table.insert(tList, {n = "Total Shields", tStr = tostring(tSpell.totalShield), click = cFunc})
	table.insert(tList, {n = "Total Absorbed", tStr = tostring(tSpell.totalAbsorption), click = cFunc})
	table.insert(tList, {n = "Deflects", tStr = string.format("%d (%.2f%%)", tSpell.deflectCount, tSpell.deflectCount / tSpell.castCount * 100), click = cFunc})


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

	if not mode.display or not mode.report then
		return
	end

    local tReportStrings = mode.report(self, mode.display(self))

	-- Report to guild, eventually this will be configurable
	local chan = "g"

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

	local tList, tTotal, strDisplayText = mode.display(self)	-- Self reference needed for calling object method

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
	self:NewLogSegment()
	self.vars.nLogIndex = 0
	self.vars.tLogDisplay = self.vars.tCurentLog
	self.vars.tMode = self.tModes["Main Menu"]
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
	if time >= 60 then
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
-- @param k sub-subsection in log segment
-- @param tSegmentType subsection in main log, ie players or mobs
function GalaxyMeter:MenuPlayerSelection(k, tSegmentType)

	local mode = self.vars.tMode

	--gLog:info(string.format("MenuPlayerSelection: %s -> %s", tLogPlayer.playerName, subType))

	self.vars.tCurrentPlayer = tSegmentType[k]

	self:PushMode()
	-- damageDone -> "Player Damage Done Breakdown", etc
	self.vars.tMode = self.tModeFromSubType[mode.type]

	self.vars.tCurrentPlayerSpells = tSegmentType[k][self.vars.tMode.type]

	self:Rover("tCurrentPlayer", self.vars.tCurrentPlayer)
	self:Rover("tCurrentPlayerSpells", self.vars.tCurrentPlayerSpells)

	self.bDirty = true
end


function GalaxyMeter:MenuPlayerSpell(tSpell)
	self:PushMode()

	self.vars.tCurrentSpell = tSpell

	self.vars.tMode = self.tModes["Spell Breakdown"]

	self.bDirty = true
end


function GalaxyMeter:MenuPrevious()
	local tMode = self:PopMode()
	if tMode then
		self.vars.tMode = tMode
		self.bDirty = true
	end
end




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

			--[[
			if v.id == id then
				if bDebug then
					gLog:info("OnClick() " .. tostring(eMouseButton))
					gLog:info(v)
				end
				if eMouseButton == 0 and v.next then
					v.next(self)
				elseif eMouseButton == 1 and v.prev then
					v.prev(self)
				end
			end
			--]]


            if v.id == id and v.OnClick then
				if bDebug then
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


-----------------------------------------------------------------------------------------------
-- GalaxyMeter Instance
-----------------------------------------------------------------------------------------------
local GalaxyMeterInst = GalaxyMeter:new()
GalaxyMeterInst:Init()
