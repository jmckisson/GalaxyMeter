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


-----------------------------------------------------------------------------------------------
-- GalaxyMeter Module Definition
-----------------------------------------------------------------------------------------------
local GalaxyMeter = {
	nVersion = 17,
	eTypeDamageOrHealing = {
		DamageInOut = 1,
		DamageIn = 2,
		DamageOut = 3,
		HealingInOut = 4,
		HealingIn = 5,
		HealingOut = 6,
	},
	-- Damage Type Colors (Get Proper Colors)
	kDamageStrToColor = {
		["Self"] 					= CColor.new(1, .75, 0, 1),
		["DamageType_Physical"] 	= CColor.new(1, .5, 0, 1),
		["DamageType_Tech"]			= CColor.new(.6, 0, 1, 1),
		["DamageType_Magic"]		= CColor.new(0, 0, 1, 1),
		["DamageType_Healing"]		= CColor.new(0, 1, 0, 1),
		["DamageType_Fall"]			= CColor.new(.5, .5, .5, 1),
		["DamageType_Suffocate"]	= CColor.new(.3, 0, 1, 1),
		["DamageType_Unknown"]		= CColor.new(.5, .5, .5, 1),
	},
	kDamageTypeToString = {
		[0]	= "Physical",
		[1]	= "Tech",
		[2]	= "Magic",
		[3]	= "Heal",
		[4] = "Heal Shield",
		[5]	= "Falling",
		[6]	= "Suffocate",
	},
	kClass = {
		"Warrior", "Engineer", "Esper", "Medic", "Stalker", "Unknown" , "Spellslinger",
	},
	kDamageTypeToColor = {},
	tTotalFromListType = {
		["damaged"]		= "damageDone",
		["damagedBy"]	= "damageTaken",
		["healed"]		= "healingDone",
		["healedBy"]	= "healingDaken",
	},
	tDamageTypeToString = {
		["damaged"] = "Damage Done",
		["damagedBy"] = "Damage Taken",
		["healed"] = "Healing Done",
		["healedby"] = "Healing Taken",
	}
}

local gLog
local Queue
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------

local kcrNormalText = CColor.new(1,1,0.7,0.7)


GalaxyMeter.kDamageTypeToColor = {
	[0]	= GalaxyMeter.kDamageStrToColor["DamageType_Physical"],
	[1]	= GalaxyMeter.kDamageStrToColor["DamageType_Tech"],
	[2]	= GalaxyMeter.kDamageStrToColor["DamageType_Magic"],
	[3]	= GalaxyMeter.kDamageStrToColor["DamageType_Healing"],
	[4]	= GalaxyMeter.kDamageStrToColor["DamageType_Healing"],
	[5]	= GalaxyMeter.kDamageStrToColor["DamageType_Fall"],
	[6]	= GalaxyMeter.kDamageStrToColor["DamageType_Suffocate"],
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


function GalaxyMeter:OnLoad()

	-- Setup GeminiLogging
	local GeminiLogging = Apollo.GetPackage("GeminiLogging-1.1").tPackage

	gLog = GeminiLogging:GetLogger({
		level = GeminiLogging.INFO,
		pattern = "[%d] %n [%c:%l] - %m",
		appender = "GeminiConsole"
	})

	GalaxyMeter.Log = gLog

	Queue = Apollo.GetPackage("drafto_Queue-1.1").tPackage

	GalaxyMeter.Queue = Queue

	Queue.copy = function(list)
		local qNew = {first = list.first, last = list.last}

		for i = qNew.first, qNew.last do
			qNew[i] = list[i]
		end

		return qNew
	end
	
	-- Slash Commands
	Apollo.RegisterSlashCommand("galaxy", 							"OnGalaxyMeterOn", self)
	Apollo.RegisterSlashCommand("lkm", 								"OnGalaxyMeterOn", self)

	-- Player Updates
	Apollo.RegisterEventHandler("ChangeWorld", 						"OnChangeWorld", self)

	-- Self Combat Logging
	--Apollo.RegisterEventHandler("UnitEnteredCombat", 				"OnEnteredCombat", self)
	Apollo.RegisterEventHandler("UnitCreated",						"OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed",					"OnUnitDestroyed", self)
	--Apollo.RegisterEventHandler("SpellCastFailed", 				"OnSpellCastFailed", self)
	--Apollo.RegisterEventHandler("SpellEffectCast", 				"OnSpellEffectCast", self)
	--Apollo.RegisterEventHandler("CombatLogString", 				"OnCombatLogString", self)
	--Apollo.RegisterEventHandler("GenericEvent_CombatLogString", 	"OnCombatLogString", self)
	--Apollo.RegisterEventHandler("CombatLogAbsorption",				"OnCombatLogAbsorption", self)
	Apollo.RegisterEventHandler("CombatLogDamage",					"OnCombatLogDamage", self)
	Apollo.RegisterEventHandler("CombatLogDispel",					"OnCombatLogDispel", self)
	Apollo.RegisterEventHandler("CombatLogHeal",					"OnCombatLogHeal", self)
	Apollo.RegisterEventHandler("CombatLogDeflect", 				"OnCombatLogDeflect", self)
	Apollo.RegisterEventHandler("CombatLogTransference",			"OnCombatLogTransference", self)


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

	-- Timer timer
	self.timerTimer = ApolloTimer.Create(0.1, true, "OnTimerTimer", self)
	self.timerTimer:Stop()

	-- Display Timer
	self.timerDisplay = ApolloTimer.Create(0.2, true, "OnDisplayTimer", self)
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
		[23] = CColor.new(1, 0, 0, 1),	-- NonPlayer
		["Humera"] = self:HexToCColor("6e1dbf"),
		--["LemonKing"] = self:HexToCColor("f3f315"),
		["LemonKing"] = self:HexToCColor("f7ff00"),
		["Ricardo"] = self:HexToCColor("006699"),
	}

	-- Handled by Configure
	self.settings = {
		bDebug = false,
		strReportChannel = "g",
		nReportLines = 5,
	}

	self.bGroupInCombat = false


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
			prev = self.MenuPrevious,					-- Right Click, previous menu
			next = self.MenuPlayerSelection,			-- Left Click, next menu
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
		},
		["Player Damage Taken"] = {
			name = "Damage Taken by Ability",
			pattern = "Damage taken from %s",
			display = self.GetOverallList,
			report = self.ReportGenericList,
			type = "damageTaken",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuPlayerSelection,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
		},
		["Player Damage Done: Unit"] = {
			name = "Overall Damage Done",       		-- Display name
			pattern = "Damage done on %s",           	--
			display = self.GetUnitList,
			report = self.ReportGenericList,
			type = "damaged",
			segType = "players",
			prev = self.MenuPrevious,					-- Right Click, previous menu
			next = self.MenuUnitDetailSelection,		-- Left Click, next menu
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
		},
		["Player Damage Taken: Unit"] = {
			name = "Damage Taken By Mob",
			pattern = "Damage taken from %s",
			display = self.GetUnitList,
			report = self.ReportGenericList,
			type = "damagedBy",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuUnitDetailSelection,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
		},
		["Player Effective Healing"] = {
			name = "Overall Healing Done",
			pattern = "Healing Done on %s",
			display = self.GetOverallList,
			report = self.ReportGenericList,
			type = "healingDone",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuPlayerSelection,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
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
			format = function(...)
				return self:FormatAmountTime(...)
			end
		},
		["Player Damage Done Breakdown"] = {
			name = "%s's Damage Done",
			pattern = "%s's Damage to %s",
			display = self.GetPlayerList,
			report = self.ReportGenericList,
			type = "damageOut",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuSpell,
			nextTotal = self.MenuPlayerSpellTotal,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
		},
		["Player Damage Taken Breakdown"] = {
			name = "%s's Damage Taken",
			pattern = "%s's Damage Taken from %s",
			display = self.GetPlayerList,
			report = self.ReportGenericList,
			type = "damageIn",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuSpell,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
		},
		["Player Healing Done Breakdown"] = {
			name = "%s's Healing Done",
			pattern = "%s's Healing Done on %s",
			display = self.GetPlayerList,
			report = self.ReportGenericList,
			type = "healingOut",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuSpell,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
		},
		["Player Healing Received Breakdown"] = {
			name = "%s's Healing Received",
			pattern = "%s's Healing Received on %s",
			display = self.GetPlayerList,
			report = self.ReportGenericList,
			type = "healingIn",
			segType = "players",
			prev = self.MenuPrevious,
			next = self.MenuSpell,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
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
		["Dispels"] = {
			name = "Dispels",
			display = nil,
			report = nil,
			--display = self.GetDispelList,
			sort = function(a,b) return a.t > b.t end,
		},
		["Player Overhealing"] = {
			name = "Player Overhealing",
			pattern = "%s's Overhealing",
			display = self.GetOverallList,
			report = self.ReportGenericList,
			type = "overheal",
			segType = "players",
			prev = self.MenuPrevious,
			next = nil,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return self:FormatAmountTime(...)
			end
		},
	}

	self.tMainMenu = {
		["Player Damage Done"] = self.tModes["Player Damage Done"],
		["Player Damage Done: Unit"] = self.tModes["Player Damage Done: Unit"],
		["Player Damage Taken"] = self.tModes["Player Damage Taken"],
		["Player Damage Taken: Unit"] = self.tModes["Player Damage Taken: Unit"],
		["Player Effective Healing"] = self.tModes["Player Effective Healing"],
		["Player Healing Received"] = self.tModes["Player Healing Received"],
		--["Dispels"] = self.tModes["Dispels"],
		["Player Overhealing"] = self.tModes["Player Overhealing"],
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


	-- Quick check if our spell target is a dummy
	self.tIsDummy = {}
	self.tIsDummy["Target Dummy"] = true
	self.tIsDummy["Formidable Target Dummy"] = true
	self.tIsDummy["Weak Target Dummy"] = true


	self.vars = {
		-- modes
		tMode = self.tModes["Main Menu"],   -- Default to Main Menu
		nLogIndex = 0,
		--bGrouped = false,
	}

	self.timerPulse:Start()

	self.bPetAffectingCombat = false
	self.bNeedNewLog = true
	self:NewLogSegment()

	self.vars.tLogDisplay = self.log[1]

	self.MobData:Init()

	gLog:info("OnLoad()")

end



function GalaxyMeter:AddMenu(strName, tMenu)
	self.tMainMenu[strName] = tMenu
end



function GalaxyMeter:OnConfigure()
	self:ConfigOn()
end


function GalaxyMeter:Debug(val)
	if val then
		self.settings.bDebug = val
	end

	return self.settings.bDebug
end


function GalaxyMeter:Dirty(val)
	if val then
		self.bDirty = val
	end

	return self.bDirty
end



-----------------------------------------------------------------------------------------------
-- Timers
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnPulse()
	
	local unitPlayer = GameLib.GetPlayerUnit()
	if unitPlayer then
		self.unitPlayer = unitPlayer
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

					if self.ClassToColor[strCharName] then
						self.vars.tLogDisplay.players[strCharName].classId = strCharName
					else

						self.vars.tLogDisplay.players[strCharName].classId = unitMember:GetClassId()
					end
				end

			end
		end
	end


	-- Check if the rest of the group is out of combat
	if self.tCurrentLog.start > 0 then
		if not self:GroupInCombat() --[[and not self.bInCombat--]] then
			gLog:info("OnPulse pushing combat segment")
			self:PushLogSegment()
		else
			--gLog:info("OnPlayerCheckTimer - Not pushing segment, group in combat")
		end
	else
		--gLog:warn("no log checking timer")
	end

end


function GalaxyMeter:OnDisplayTimer()

	if self.wndMain:IsVisible() and self.vars.tLogDisplay == self.tCurrentLog then

		if self.bDirty then
			self:RefreshDisplay()
			self.bDirty = false
		end
	end
end


function GalaxyMeter:OnTimerTimer()

	self.tCurrentLog.combat_length = os.clock() - self.tCurrentLog.start

	if self.wndMain:IsVisible() and self.vars.tLogDisplay == self.tCurrentLog then

		self.Children.TimeText:SetText(self:SecondsToString(self.vars.tLogDisplay.combat_length))
	end
end


-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnChangeWorld
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnChangeWorld()
	-- Restarts Player Check Timer to update Player Id based on New Zone
	self.timerPulse:Start()
end


function GalaxyMeter:OnUnitCreated(unit)

	if unit and unit:GetUnitOwner() then
		if unit:GetUnitOwner():IsThePlayer() then
			self.bPetAffectingCombat = true
			gLog:info("bPetAffectingCombat true")
		end
	end

end


function GalaxyMeter:OnUnitDestroyed(unit)

	if unit and unit:GetUnitOwner() and unit:GetUnitOwner():IsThePlayer() then
		self.bPetAffectingCombat = false
		gLog:info("bPetAffectingCombat false")
	end

end


--[[
-- Determine if group is in combat by scanning all group members.
-- Checks if a pet owned by the player unit may be affecting their
-- combat status, ie Esper Geist.
-- @return true if any group members are in combat
 ]]
function GalaxyMeter:GroupInCombat()

	if not GameLib.GetPlayerUnit() then
		gLog:info("GroupInCombat: No Player Unit, returning false")
		return false
	end

	local bSelfInCombat = GameLib.GetPlayerUnit():IsInCombat() or self.bPetAffectingCombat

	local nMemberCount = GroupLib.GetMemberCount()
	if nMemberCount == 0 then

		--gLog:info("GroupInCombat: returning  " .. tostring(bSelfInCombat))
		return bSelfInCombat
	end

	local bCombat = false

	for i = 1, nMemberCount do
		local tUnit = GroupLib.GetUnitForGroupMember(i)

		if tUnit and tUnit:IsInCombat() or (bSelfInCombat and tUnit:IsDead()) then
			bCombat = true
			break
		end
	end

	self.bGroupInCombat = bCombat

	if not bCombat then
		self.bNeedNewLog = true
	end
	
	return bCombat
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
	self.timerTimer:Start()

	Event_FireGenericEvent("GalaxyMeterLogStart", self.tCurrentLog)
end


function GalaxyMeter:TryStartSegment(tEvent, unitTarget)
	-- Should we trigger a new log segment?
	if self.bNeedNewLog then
		self:StartLogSegment()

		if not unitTarget:IsACharacter() then
			self.tCurrentLog.name = tEvent.strTarget
		else
			-- So attacking plants sometimes returns not NonPlayer, with a nil targettarget
			if unitTarget:GetTarget() then
				self.tCurrentLog.name = unitTarget:GetTarget():GetName()
			else
				self.tCurrentLog.name = "Unknown"
			end
		end
		gLog:info(string.format("OnCLDamage: Set activeLog.name to %s", self.tCurrentLog.name))
	end
end


function GalaxyMeter:NewLogSegment()
    -- Push a new log entry to the top of the history stack
    local log = {
        start = 0,
		stop = 0,
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

	self.tCurrentLog.stop = os.clock()

    -- Pop off oldest, TODO Add config option to keep N old logs
    if #self.log >= 30 then
        table.remove(self.log)
    end

	self.timerDisplay:Stop()
	self.timerTimer:Stop()

	-- Save player active times
	for k, player in pairs(self.tCurrentLog.players) do
		player.timeActive = player.lastAction - player.firstAction
	end

	Event_FireGenericEvent("GalaxyMeterLogStop", self.tCurrentLog)

    self:NewLogSegment()
end


-- Returns the time (in seconds) a player has been active for a set.
function GalaxyMeter:GetActiveTime(tLog, tPlayer)
	local maxtime = 0

	-- Add recorded time (for total set)
	if tPlayer.timeActive > 0 then
		maxtime = tPlayer.timeActive
	end

	-- Add in-progress time if set is not ended.
	if not tLog.stop and tPlayer.firstAction then
		maxtime = maxtime + tPlayer.lastAction - tPlayer.firstAction
	end

	return maxtime
end



-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnEnteredCombat
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnEnteredCombat(unit, bInCombat)
	
	if unit:GetId() == GameLib.GetPlayerUnit():GetId() then

		-- We weren't in combat before, so start new segment
		if not bInCombat and not self.bPetAffectingCombat then
			-- Hm, we shouldnt set this flag if the spell was a heal...
			--self.bNeedNewLog = true
			gLog:info("OnEnteredCombat: self combat false")
			self.bInCombat = false
            --gLog:info("Self out of combat: Setting bNeedNewLog = true")
        else
			gLog:info("OnEnteredCombat: self combat true")
			self.bInCombat = true
		end
	end
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

	if strArg == "deaths" then
		self.Deaths:Init()

	elseif strArg == "debug" then
		self.settings.bDebug = not self.settings.bDebug
		gLog:info("bDebug = " .. tostring(self.settings.bDebug))

	elseif strArg == "interrupt" then
		self.Interrupts:Init()

	elseif strArg == "" then

		if self.wndMain:IsVisible() then
			self.settings.anchor = {self.wndMain:GetAnchorOffsets()}
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

		if args[1] == "channel" and args[2] then
			self.settings.strReportChannel = args[2]
			gLog:info("Reporting to channel: " .. self.settings.strReportChannel)

		elseif args[1] == "report" and args[2] then
			self.settings.nReportLines = tonumber(args[2])
			gLog:info("Set report lines to " .. self.settings.nReportLines)

		elseif args[1] == "log" and args[2] and self.Deaths then
			self.Deaths:PrintPlayerLog(args[2])
		end

	end
end


-----------------------------------------------------------------------------------------------
-- Accessors/Mutators
-----------------------------------------------------------------------------------------------

function GalaxyMeter:GetTarget()
	-- Safe Target String
	local unitTarget = GameLib.GetTargetUnit()
	if unitTarget then
		return unitTarget:GetName()
	end
	return "Unknown"
end


function GalaxyMeter:LogActor(tActor)
	if tActor then
		self.vars.tLogActor = tActor
	end

	return self.vars.tLogActor
end


function GalaxyMeter:LogActorId(nId)
	if nId then
		self.vars.nCurrentActorId = nId
	end

	return self.vars.nCurrentActorId
end


function GalaxyMeter:LogActorName(str)
	if str then
		self.vars.strCurrentPlayerName = str
	end

	return self.vars.strCurrentPlayerName
end


function GalaxyMeter:GetCurrentMode()
	return self.vars.tMode
end


function GalaxyMeter:LogSpell(tSpell)
	if tSpell then
		self.vars.tLogSpell = tSpell
	end

	return self.vars.tLogSpell
end


function GalaxyMeter:LogType(str)
	if str then
		self.vars.strCurrentLogType = str
	end

	return self.vars.strCurrentLogType
end


function GalaxyMeter:LogModeType(str)
	if str then
		self.vars.strModeType = str
	end

	return self.vars.strModeType
end



function GalaxyMeter:GetLog()
	return self.tCurrentLog
end


function GalaxyMeter:GetLogDisplay()
	return self.vars.tLogDisplay
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


function GalaxyMeter:ReportChannel(chan)
	if chan then
		self.settings.strReportChannel = chan
	end

	return self.settings.strReportChannel
end


function GalaxyMeter:ReportLines(lines)
	if lines then
		self.settings.nReportLines = lines
	end

	return self.settings.nReportLines
end


-- Workaround for players dealing a severely reduced damage to target dummies
function GalaxyMeter:StupidDummyDamage(tEvent, tEventArgs)

	if self.tIsDummy[tEvent.strTarget] then
		if not tEventArgs.nRawDamage then
			gLog:error(string.format("nRawDamage nil for %s", tEvent.strSpellName or "Unknown"))
			tEvent.nDamage = tEventArgs.nDamageAmount
		else
			tEvent.nDamage = tEventArgs.nRawDamage
		end
	else
		tEvent.nDamage = tEventArgs.nDamageAmount
	end
end


-- Assign Name, ID, Class to player if they are the caster or target
-- TODO Move this into HelperCasterTargetSpell
function GalaxyMeter:AssignPlayerInfo(tEvent, tEventArgs)
	if self:IsPlayerOrPlayerPet(tEventArgs.unitCaster) then
		tEvent.PlayerName, tEvent.PlayerId, tEvent.ClassId = tEvent.strCaster, tEvent.nCasterId, tEvent.nCasterClassId
	else
		tEvent.PlayerName, tEvent.PlayerId, tEvent.ClassId = tEvent.strTarget, tEvent.nTargetId, tEvent.nTargetClassId
	end
end


function GalaxyMeter:OnCombatLogDispel(tEventArgs)
	if self.settings.bDebug then
		gLog:info("OnCombatLogDispel()")
		gLog:info(tEventArgs)
	end
end



function GalaxyMeter:OnCombatLogAbsorption(tEventArgs)
	if self.settings.bDebug then
		gLog:info("OnCombatLogAbsorption()")
		gLog:info(tEventArgs)
	end
end



function GalaxyMeter:OnCombatLogTransference(tEventArgs)
	-- OnCombatLogDamage does exactly what we need so just pass along the tEventArgs
	self:OnCombatLogDamage(tEventArgs)

	--[[
	if self.settings.bDebug then
		gLog:info("OnCombatLogTransference()")
		gLog:info(tEventArgs)
	end
	--]]

	--[[
	tHealData {
	 	eVitalType
	 	nHealAmount
	 	nOverHeal
	--]]
	if tEventArgs.tHealData then
		local tEvent = self:HelperCasterTargetSpell(tEventArgs, true, true)

		if not tEvent then return end

		tEvent.bDeflect = false
		tEvent.nDamage = tEventArgs.tHealData[1].nHealAmount
		--tEvent.Shield = tEventArgs.nShield
		--tEvent.Absorb = tEventArgs.nAbsorption
		--tEvent.Periodic = tEventArgs.bPeriodic
		tEvent.nOverheal = tEventArgs.tHealData[1].nOverheal
		--tEvent.eResult = tEventArgs.eCombatResult
		tEvent.eVitalType = tEventArgs.tHealData[1].eVitalType

		--tEvent.eEffectType = tEventArgs.eEffectType

		-- Temporary hack until we switch to checking spell effect type instead of tEvent.DamageType
		tEvent.eDamageType = GameLib.CodeEnumDamageType.Heal

		tEvent.nTypeId = self:GetHealEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

		if tEvent.nTypeId > 0 and tEvent.nDamage then

			self:AssignPlayerInfo(tEvent, tEventArgs)

			local player = self:GetPlayer(self.tCurrentLog.players, tEvent)

			self:UpdateSpell(tEvent, player)
		else
			gLog:error(string.format("OnCLTransference: Something went wrong! type %d dmg %d", tEvent.nTypeId, tEvent.nDamage or 0))
		end
	end

end


function GalaxyMeter:OnCombatLogDeflect(tEventArgs)
	-- An error may occur here where tEventArgs is nil??

	local tEvent = self:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tEvent then return end

	tEvent.nDamage = 0
	tEvent.bDeflect = true
	tEvent.eResult = tEventArgs.eCombatResult

	-- Guarantee that unitCaster and unitTarget exist
	if not tEventArgs.unitCaster or not tEventArgs.unitTarget then
		self:Rover("CLDeflect:error", tEventArgs)
		gLog:error("OnCLDeflect - nil caster or target")
		return
	end

	tEvent.nTypeId = self:GetDamageEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	self:TryStartSegment(tEvent, tEventArgs.unitTarget)

	local activeLog = self.tCurrentLog.players

	self:AssignPlayerInfo(tEvent, tEventArgs)

	local player = self:GetPlayer(activeLog, tEvent)
	self:UpdateSpell(tEvent, player)
end


function GalaxyMeter:OnCombatLogDamage(tEventArgs)

	local tEvent = self:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tEvent then return end

	tEvent.bDeflect = false
	tEvent.nDamageRaw = tEventArgs.nRawDamage
	tEvent.nShield = tEventArgs.nShield
	tEvent.nAbsorb = tEventArgs.nAbsorption
	tEvent.bPeriodic = tEventArgs.bPeriodic
	tEvent.bVulnerable = tEventArgs.bTargetVulnerable
	tEvent.nOverkill = tEventArgs.nOverkill
	tEvent.eResult = tEventArgs.eCombatResult
	tEvent.eDamageType = tEventArgs.eDamageType
	tEvent.eEffectType = tEventArgs.eEffectType
	tEvent.bTargetKilled = tEventArgs.bTargetKilled

	if self:ShouldThrowAwayDamageEvent(tEventArgs.unitCaster, tEventArgs.unitTarget) then
		return
	end

	-- Guarantee that unitCaster and Target exist
	if not tEventArgs.unitCaster or not tEventArgs.unitTarget then
		self:Rover("CLDamage:error", tEventArgs)
		gLog:error("OnCLDamage - nil caster or target")
		return
	end

	self:StupidDummyDamage(tEvent, tEventArgs)

	tEvent.nTypeId = self:GetDamageEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	self:TryStartSegment(tEvent, tEventArgs.unitTarget)

	if tEvent.nTypeId > 0 and tEvent.nDamage then

		self:AssignPlayerInfo(tEvent, tEventArgs)

		local player = self:GetPlayer(self.tCurrentLog.players, tEvent)

		self:UpdateSpell(tEvent, player)

		Event_FireGenericEvent("GalaxyMeterLogDamage", tEvent)

	else
		gLog:error(string.format("OnCLDamage: Something went wrong!  Invalid type Id, dmg raw %d, dmg %d", tEventArgs.nRawDamage, tEventArgs.nDamageAmount))

	end

end


function GalaxyMeter:OnCombatLogHeal(tEventArgs)

	local tEvent = self:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tEvent then return end

	tEvent.bDeflect = false
	tEvent.nDamage = tEventArgs.nHealAmount
	tEvent.nHealAmount = tEventArgs.nHealAmount
	--tEvent.Shield = tEventArgs.nShield
	--tEvent.Absorb = tEventArgs.nAbsorption
	--tEvent.Periodic = tEventArgs.bPeriodic
	tEvent.nOverheal = tEventArgs.nOverheal
	tEvent.eResult = tEventArgs.eCombatResult
	tEvent.eEffectType = tEventArgs.eEffectType

	-- Temporary hack until we switch to checking spell effect type instead of tEvent.DamageType
	if tEventArgs.eEffectType == Spell.CodeEnumSpellEffectType.Heal then
		tEvent.eDamageType = GameLib.CodeEnumDamageType.Heal
	elseif tEventArgs.eEffectType == Spell.CodeEnumSpellEffectType.HealShields then
		tEvent.eDamageType = GameLib.CodeEnumDamageType.HealShields
	end

	tEvent.nTypeId = self:GetHealEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	if tEvent.nTypeId and tEvent.nTypeId > 0 and tEvent.nDamage then

		self:AssignPlayerInfo(tEvent, tEventArgs)

		local player = self:GetPlayer(self.tCurrentLog.players, tEvent)

		self:UpdateSpell(tEvent, player)

		Event_FireGenericEvent("GalaxyMeterLogHeal", tEvent)
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
		--strCasterType = nil,
		--strTargetType = nil,
		nCasterClassId = nil,
		nTargetClassId = nil,
		nCasterId = nil,
		nTargetId = nil,
		unitCaster = tEventArgs.unitCaster,
		unitTarget = tEventArgs.unitTarget,
	}

	if bSpell then
		tInfo.strSpellName = self:HelperGetNameElseUnknown(tEventArgs.splCallingSpell)
		if tEventArgs.bPeriodic then
			tInfo.strSpellName = tInfo.strSpellName .. " (Dot)"
		end
	end

	local bCasterIsPlayerOrPet = tEventArgs.unitCaster and self:IsPlayerOrPlayerPet(tEventArgs.unitCaster)
	local bTargetIsPlayerOrPet = tEventArgs.unitTarget and self:IsPlayerOrPlayerPet(tEventArgs.unitTarget)

	tInfo.bCasterIsPlayer = bCasterIsPlayerOrPet
	tInfo.bTargetIsPlayer = bTargetIsPlayerOrPet

	if tEventArgs.unitCaster then
		tInfo.nCasterId = tEventArgs.unitCaster:GetId()
		--tInfo.strCasterType = tEventArgs.unitCaster:GetType()

		if tEventArgs.unitCasterOwner and tEventArgs.unitCasterOwner:IsACharacter() then
			-- Caster is a pet, assign caster to the owners name

			tInfo.strSpellName = ("%s: %s"):format(tEventArgs.unitCaster:GetName(), tInfo.strSpellName)

			tInfo.strCaster = tEventArgs.unitCasterOwner:GetName()
			tInfo.nCasterClassId = tEventArgs.unitCasterOwner:GetClassId()

		else
			-- Caster was not a pet
			tInfo.strCaster = self:HelperGetNameElseUnknown(tEventArgs.unitCaster)
			tInfo.nCasterClassId = tEventArgs.unitCaster:GetClassId()
		end

		--[[
		-- Count pets as damage done by the player
		if tInfo.strCasterType == "Pet" then

			self:Rover("SpellPet", tEventArgs)

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
		--]]

	else
		-- No caster for this spell, wtf should I do?
		local nTargetId = self:GetUnitId(tEventArgs.unitTarget)
		local strTarget = self:HelperGetNameElseUnknown(tEventArgs.unitTarget)

		-- Hack to fix Pets sometimes having no unitCaster
		gLog:warn(string.format("HelperCasterTargetSpell unitCaster nil(pet?): Caster[%d] %s, Target[%d] %s, Spell: '%s'",
			0, "Unknown", nTargetId, strTarget, tInfo.strSpellName or "Unknown"))

		-- Set caster to our player name
		--tInfo.strCaster = self.PlayerName

		return nil
	end

	if bTarget then
		tInfo.strTarget = self:HelperGetNameElseUnknown(tEventArgs.unitTarget)
		if tEventArgs.unitTargetOwner and tEventArgs.unitTargetOwner:GetName() then
			tInfo.strTarget = string.format("%s (%s)", tInfo.strTarget, tEventArgs.unitTargetOwner:GetName())
		end

		if tEventArgs.unitTarget then
			tInfo.nTargetId = tEventArgs.unitTarget:GetId()
			--tInfo.strTargetType = tEventArgs.unitTarget:GetType()
			tInfo.nTargetClassId = tEventArgs.unitTarget:GetClassId()
		else
			--tInfo.strTargetType = "Unknown"
			-- Uhh? no target, no idea what to set classid to
			gLog:warn(string.format("HelperCasterTargetSpell nil unitTarget, caster '%s', strTarget '%s', spell '%s'", tInfo.strCaster, tInfo.strTarget, tInfo.strSpellName))
		end

	end

	return tInfo
end


function GalaxyMeter:HelperGetNameElseUnknown(nArg)
	if nArg and nArg:GetName() then
		local name = nArg:GetName()

		-- Fun
		--name = name:gsub("Rica", "Reta")
		name = name:gsub("yona", "yonaaaaaaaaaaaaa")

		return name
	end
	return Apollo.GetString("CombatLog_SpellUnknown")
end


function GalaxyMeter:ShouldThrowAwayDamageEvent(unitCaster, unitTarget)
    if unitTarget then

        -- Don't display damage taken by pets (yet)
		if unitTarget:GetUnitOwner() and unitTarget:GetUnitOwner():IsACharacter() then

            return true
        end

    else
        -- Keep events with no unitCaster for now because they may still be determined useful

	end

	return false
end


-- Determine the type of heal based on the caster and target
function GalaxyMeter:GetHealEventType(unitCaster, unitTarget)

	if not unitTarget or not unitCaster then
		gLog:error(string.format("GetHealEventType() nil unitTarget or caster, caster[%d] %s",
			self:GetUnitId(unitCaster), self:HelperGetNameElseUnknown(unitCaster)))
		return 0
	end

	if unitTarget:IsACharacter() then
		-- Self damage
		if unitCaster:IsACharacter() and unitTarget:GetId() == unitCaster:GetId() then
			return GalaxyMeter.eTypeDamageOrHealing.HealingInOut
		end

		return GalaxyMeter.eTypeDamageOrHealing.HealingIn
	else
		-- Target is not a player
		if unitCaster:IsACharacter() then
			return GalaxyMeter.eTypeDamageOrHealing.HealingOut
		end

		-- Ok so the dmg might be from a pet
		if unitCaster:GetUnitOwner() and unitCaster:GetUnitOwner():IsACharacter() then
			-- This is being set when the caster is not yourself

			return GalaxyMeter.eTypeDamageOrHealing.HealingOut
		end

		gLog:error("Unknown heal type")
		return 0
	end

	--[[
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

        gLog:warn(string.format("Unknown Heal - Caster: %s, Target: %s", self:HelperGetNameElseUnknown(unitCaster), self:HelperGetNameElseUnknown(unitTarget)))

        return eTypeDamageOrHealing.PlayerHealingOut
	end
	--]]
end



function GalaxyMeter:IsPlayerOrPlayerPet(unit)
	if not unit then return false end

	if unit:IsACharacter() or (unit:GetUnitOwner() and unit:GetUnitOwner():IsACharacter()) then
		return true
	end

	return false
end


function GalaxyMeter:GetDamageEventType(unitCaster, unitTarget)

	local bSourceIsPlayerOrPet = self:IsPlayerOrPlayerPet(unitCaster)
	local bTargetIsPlayerOrPet = self:IsPlayerOrPlayerPet(unitTarget)

	--[[
	 source mob or pet 		&& target player or pet => mob dmg out
	 source player or pet	&& target mob or pet	=> mob dmg in
	 source mob or pet		&& target mob or pet	=> mob dmg in/out
	 --]]

	local retVal = 0

	if unitTarget:IsACharacter() then

        -- Self damage
		if unitCaster:IsACharacter() and unitTarget:GetId() == unitCaster:GetId() then
            return GalaxyMeter.eTypeDamageOrHealing.DamageInOut
        end

        retVal = GalaxyMeter.eTypeDamageOrHealing.DamageIn
	else

		-- Target is not a player
		if bSourceIsPlayerOrPet then

			-- This is being set when the caster is not yourself
       		retVal = GalaxyMeter.eTypeDamageOrHealing.DamageOut

		-- Or to a pet
		elseif bTargetIsPlayerOrPet then
			gLog:info("Damage targetting player pet")
		end

		if retVal == 0 then
			gLog:error("Unknown dmg type")
		end

	end

	return retVal, bSourceIsPlayerOrPet, bTargetIsPlayerOrPet
end


-- Find but do not create ne entry if missing
function GalaxyMeter:FindMob(tLog, nMobId)
	return tLog.mobs[nMobId]
end


-- Find or create mob data table
-- @return Mob data table
function GalaxyMeter:GetMob(tLog, nMobId, unit)

    local mob = tLog.mobs[nMobId]

    if not mob then
        mob = {
            -- Info
			id = nMobId,

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
			damagedBy = {},
            healed = {},
			healedBy = {},
		}

		if unit then
			mob.strName = unit:GetName()
			mob.classId = unit:GetClassId()
		end

        tLog.mobs[nMobId] = mob
    end

    return mob
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
            strName = playerName,                -- Player name

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
			damagedBy = {},
			healed = {},
			healedBy = {},
		}

		if tEvent.PlayerId then
			player.playerId = tEvent.PlayerId             -- Player GUID?
		end

		if tEvent.ClassId then
			player.classId = tEvent.ClassId   	     			-- Player Class Id
		end

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

	if tEvent.bDeflect then
		tSpell.deflectCount = tSpell.deflectCount + 1
		-- We're done here, move along
		return
	end

	if tEvent.nOverheal then
		tSpell.overheal = (tSpell.overheal or 0) + tEvent.nOverheal
	end

	if not tSpell.dmgType then tSpell.dmgType = tEvent.eDamageType end

    -- Shield Absorption - Total damage includes dmg done to shields while spell breakdowns dont
    if tEvent.nShieldAbsorbed and tEvent.nShieldAbsorbed > 0 then
        tSpell.totalShield = tSpell.totalShield + tEvent.nShieldAbsorbed

        -- TODO Option to record shield damage into the total accumulation, or seperate totalShields
		tSpell.total = tSpell.total + tEvent.nShieldAbsorbed
    end

    -- Absorption
    if tEvent.nAbsorptionAmount and tEvent.nAbsorptionAmount > 0 then
        tSpell.totalAbsorption = tSpell.totalAbsorption + tEvent.nAbsorptionAmount

        tSpell.total = tSpell.total + tEvent.nAbsorptionAmount
	end

	local nAmount = tEvent.nDamage or 0

	if nAmount > 0 then

		-- Spell Total
		tSpell.total = tSpell.total + nAmount

		-- Crits
		if tEvent.eResult == GameLib.CodeEnumCombatResult.Critical then
			tSpell.critCount = tSpell.critCount + 1
			tSpell.totalCrit = tSpell.totalCrit + nAmount
			tSpell.avgCrit = tSpell.totalCrit / tSpell.critCount
		end

		-- Dmg while vulnerable
		if tEvent.bVulnerable then
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



function GalaxyMeter:UpdateSpell(tEvent, actor)
    local strSpellName = tEvent.strSpellName
    local nAmount = tEvent.nDamage

	if not nAmount and not tEvent.bDeflect then
		gLog:error("UpdateSpell: nAmount is nil, spell: " .. strSpellName)
		self:Rover("nil nAmount Spell", tEvent)
		return
	end

    local spell = nil

    -- Player tally and spell type
	if tEvent.nTypeId == GalaxyMeter.eTypeDamageOrHealing.HealingInOut then

        -- Special handling for self healing, we want to count this as both healing done and received
        -- Maybe add option to enable tracking for this

		local nEffective = nAmount - tEvent.nOverheal

        actor.healingDone = actor.healingDone + nEffective
		actor.healingTaken = actor.healingTaken + nAmount
		actor.healed[tEvent.strTarget] = (actor.healed[tEvent.strTarget] or 0) + nEffective

		if tEvent.nOverheal > 0 then
			actor.overheal = (actor.overheal or 0) + tEvent.nOverheal
		end

        local spellOut = self:GetSpell(actor.healingOut, strSpellName)
        local spellIn = self:GetSpell(actor.healingIn, strSpellName)

        self:TallySpellAmount(tEvent, spellOut)
        self:TallySpellAmount(tEvent, spellIn)

		self.bDirty = true

    elseif tEvent.nTypeId == GalaxyMeter.eTypeDamageOrHealing.HealingOut then

		local nEffective = nAmount - tEvent.nOverheal

		actor.healingDone = actor.healingDone + nEffective
		actor.healed[tEvent.strTarget] = (actor.healed[tEvent.strTarget] or 0) + nEffective

		if tEvent.nOverheal > 0 then
			actor.overheal = (actor.overheal or 0) + tEvent.nOverheal
		end

        spell = self:GetSpell(actor.healingOut, strSpellName)

    elseif tEvent.nTypeId == GalaxyMeter.eTypeDamageOrHealing.HealingIn then

		local nEffective = nAmount - tEvent.nOverheal

		actor.healingTaken = actor.healingTaken + nAmount
		actor.healedBy[tEvent.strCaster] = (actor.healedBy[tEvent.strCaster] or 0) + nEffective

        spell = self:GetSpell(actor.healingIn, strSpellName)

    elseif tEvent.nTypeId == GalaxyMeter.eTypeDamageOrHealing.DamageInOut then

        -- Another special case where the spell we cast also damaged ourself?
		actor.damageDone = actor.damageDone + nAmount
		actor.damageTaken = actor.damageTaken + nAmount
		actor.damaged[tEvent.strTarget] = (actor.damaged[tEvent.strTarget] or 0) + nAmount

        local spellOut = self:GetSpell(actor.damageOut, strSpellName)
        local spellIn = self:GetSpell(actor.damageIn, strSpellName)

        self:TallySpellAmount(tEvent, spellOut)
        self:TallySpellAmount(tEvent, spellIn)

		self.bDirty = true

    elseif tEvent.nTypeId == GalaxyMeter.eTypeDamageOrHealing.DamageOut then
		if not tEvent.bDeflect then
			actor.damageDone = actor.damageDone + nAmount
			actor.damaged[tEvent.strTarget] = (actor.damaged[tEvent.strTarget] or 0) + nAmount
		end

        spell = self:GetSpell(actor.damageOut, strSpellName)

    elseif tEvent.nTypeId == GalaxyMeter.eTypeDamageOrHealing.DamageIn then

		if not tEvent.bDeflect then
			actor.damageTaken = actor.damageTaken + nAmount
			actor.damagedBy[tEvent.strCaster] = (actor.damagedBy[tEvent.strCaster] or 0) + nAmount
		end

		local strCasterNameSpell = ("%s: %s"):format(tEvent.strCaster, strSpellName)

        spell = self:GetSpell(actor.damageIn, strCasterNameSpell)

	else
		self:Rover("UpdateSpell Error", tEvent)
        gLog:error("Unknown type in UpdateSpell!")
        gLog:error(string.format("Spell: %s, Caster: %s, Target: %s, Amount: %d",
            strSpellName, tEvent.strCaster, tEvent.strTarget, nAmount or 0))

		-- spell should be null here, safe to continue on...
    end

    if spell then
		local timeNow = os.clock()

		if not actor.firstAction then
			actor.firstAction = timeNow
		end
		actor.lastAction = timeNow
        self:TallySpellAmount(tEvent, spell)
		self.bDirty = true
    end

end



-----------------------------------------------------------------------------------------------
-- Data Formatters
-----------------------------------------------------------------------------------------------

local function FormatScaleAmount(nAmount)
	if nAmount > 1000000 then
		return ("%2.2fM"):format(nAmount / 1000000)
	elseif nAmount > 1000 then
		return ("%2.2fK"):format(nAmount / 1000)
	else
		return ("%2.2f"):format(nAmount)
	end
end


function GalaxyMeter:FormatAmountTime(nAmount, nTime)

	local strFmtAmount = FormatScaleAmount(nAmount)

	return ("%s (%s)"):format(strFmtAmount, FormatScaleAmount(nAmount / nTime))
end


function GalaxyMeter:FormatAmount(nCount)
	return ("%s"):format(nCount)
end



-----------------------------------------------------------------------------------------------
-- List Generators
--
-- TODO These are pretty similar... Consider refactoring them into a more generic method
-----------------------------------------------------------------------------------------------

function GalaxyMeter:GetScalarList()
	local tList = {}

	local tLogSegment = self.vars.tLogDisplay
	local strPlayerName = self.vars.strCurrentPlayerName

	local tPlayerLog = self:GetPlayer(tLogSegment, {PlayerName=strPlayerName})

	local mode = self.vars.tMode

	-- convert to interruptIn/Out
	local strListTypeTotal = self.tSubTypeFromList[mode.type]

	-- count of all totals from all sublists
	local tTotal = {
		n = string.format("%s's %s", strPlayerName, mode.type),
		--t = tPlayerLog[dmgTypeTotal],
		t = 0,
		c = GalaxyMeter.kDamageStrToColor.Self
	}

	for name, list in pairs(tPlayerLog[mode.type]) do
		local total = 0

		for spell, count in pairs(list) do
			tTotal.t = tTotal.t + count
			total = total + count
		end

		table.insert(tList, {
			n = name,
			--t = total,
			c = GalaxyMeter.kDamageTypeToColor[2],	-- TODO change this to something related to the type of mob/player that was interrupted
			tStr = mode.format(total),
			progress = 0,
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
		c = GalaxyMeter.kDamageTypeToColor.Self,
	}

	for name, count in pairs(tScalarList) do

		tTotal.t = tTotal.t + count

		table.insert(tList, {
			n = name,
			t = count,
			c = GalaxyMeter.kDamageTypeToColor[2],
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


--[[
-- We got here from a MenuUnitDetailSelection menu
-- Display what spells from the actor damaged/healed the target
 ]]
function GalaxyMeter:GetActorUnitList()
	local mode = self:GetCurrentMode()
	--local tLogSegment = self:GetLogDisplay()
	local tActor = self:LogActor()

	-- Who did this actor interact with?
	local typeTotal = GalaxyMeter.tTotalFromListType[mode.type]

	local nMax = 0
	local nActorTotal = tActor[typeTotal]

	-- Find max
	for k, v in pairs(tActor[mode.type]) do
		if v > nMax then v = nMax end
	end

	local nTime = self:GetLogDisplayTimer()

	-- Build list
	local tList = {}
	for k, v in pairs(tActor[mode.type]) do

		--self:Rover("GetActorUnitList", {nTime = nTime, k=k, v=v})

		table.insert(tList, {
			n = k,
			t = v,
			tStr = mode.format(v, nTime),
			progress = v / nMax,
			c = self.ClassToColor[23],	-- This should be the class of the target...
			click = function(m, btn)
				if btn == 1 and mode.prev then
					mode.prev(self)
				end
			end
		})
	end

	local tTotal = {
		n = mode.name,
		progress = 1,
		c = self.ClassToColor[tActor.classId],
		tStr = mode.format(nActorTotal, nTime),
	}

	return tList, tTotal, mode.name, ""
end


--[[
-- Returns list of actors who have been damaged or have done damage/healing
 ]]
function GalaxyMeter:GetUnitList()

	local mode = self:GetCurrentMode()
	local tLogSegment = self:GetLogDisplay()
	local tLogActors = tLogSegment[mode.segType]	--mobs or players

	local nTime = self:GetLogDisplayTimer()

	local tList = {}
	local nSum, nMax = 0, 0

	local typeTotal = GalaxyMeter.tTotalFromListType[mode.type]

	-- Find individual actor sum, total sum, and total max
	for nActorId, tActor in pairs(tLogActors) do

		--log.mobs[mobId].damaged[] => typeTotal damageDone
		--log.players[name].damagedBy[] => typeTotal damageTaken
		if tActor[typeTotal] > 0 then

			local nActorSum = 0
			for k, v in pairs(tActor[mode.type]) do
				nSum = nSum + v
				if v > nMax then nMax = v end
			end
		end
	end

	-- Build list of units that have interatec with this actor
	for nActorId, tActor in pairs(tLogActors) do

		-- Check if its been damaged/damageBy'd
		if tActor[typeTotal] > 0 then

			local nActorTotal = tActor[typeTotal]

			table.insert(tList, {
				n = tActor.strName,
				t = nActorTotal,
				c = self.ClassToColor[tActor.classId],
				tStr = mode.format(nActorTotal, nTime),
				progress = nActorTotal / nMax,
				click = function(m, btn)
					if btn == 0 and mode.next then
						mode.next(self, tActor)
					elseif btn == 1 and mode.prev then
						mode.prev(self)
					end
				end
			})
		end
	end

	local tTotal = {
		n = mode.name,
		t = nSum,
		c = GalaxyMeter.kDamageStrToColor.Self, progress = 1,
		tStr = mode.format(nSum, nTime),
	}

	local strReportTotalText = string.format("%s - %s (%s) - %s",
		string.format(mode.pattern, tLogSegment.name),
		FormatScaleAmount(tTotal.t),
		FormatScaleAmount(tTotal.t / tLogSegment.combat_length),
		self:SecondsToString(tLogSegment.combat_length))

	return tList, tTotal, mode.name, strReportTotalText
end


--[[
- @return tList, tTotal Overall list entries, total
- Do we need an option for players/mobs?
- @return {
- 		tList = ,
- 		tTotal = ,
- 		strModeName = ,
- 		strTotalText
- }
--]]
function GalaxyMeter:GetOverallList()

	local tLogSegment = self.vars.tLogDisplay
	local mode = self.vars.tMode

	-- Grab segment type from mode: players/mobs/etc
	local tSegmentType = tLogSegment[mode.segType]

	local nTime = self:GetLogDisplayTimer()

	-- Get total and max
	local nMax = 0
	local tTotal = {t = 0, c = GalaxyMeter.kDamageStrToColor.Self, progress = 1}
	for k, v in pairs(tSegmentType) do
		local n = (v[mode.type] or 0)
		tTotal.t = tTotal.t + n

		if n > nMax then
			nMax = n
		end
	end
	tTotal.tStr = mode.format(tTotal.t, nTime)

	local tList = {}
    for k, v in pairs(tSegmentType) do

		-- Only show people who have contributed
		if v[mode.type] and v[mode.type] > 0 then

			local nAmount = v[mode.type]

			table.insert(tList, {
				n = v.strName,
				t = nAmount,
				tStr = mode.format(nAmount, nTime),
				c = self.ClassToColor[v.classId],
				progress = nAmount / nMax,
				click = function(m, btn)
					-- arg is the specific actor log table
					if btn == 0 and mode.next then
						mode.next(self, k)

					elseif btn == 1 and mode.prev then
						mode.prev(self)
					end
				end
			})
		end
	end

	-- TODO This is only used for generating a report, refactor
	local strTotalText = string.format("%s - %s (%s) - %s",
		string.format(mode.pattern, tLogSegment.name),
		FormatScaleAmount(tTotal.t),
		FormatScaleAmount(tTotal.t / tLogSegment.combat_length),
		self:SecondsToString(tLogSegment.combat_length))

    return tList, tTotal, mode.name, strTotalText
end


-- Get player listing for this segment
-- @return Tables containing player damage done
--    1) Ordered list of individual spells
--    2) Total
function GalaxyMeter:GetPlayerList()
    local tList = {}

	-- These should have already been set
	local strPlayerName = self.vars.strCurrentPlayerName
	local mode = self.vars.tMode
	local tLogSegment = self.vars.tLogDisplay

	local tPlayerLog = tLogSegment[mode.segType][strPlayerName]

	-- convert to damageDone/damageTaken
	local dmgTypeTotal = self.tSubTypeFromList[mode.type]

	local nDmgTotal = tPlayerLog[dmgTypeTotal]

	local nTime = self:GetLogDisplayTimer()

	local tTotal = {
        n = string.format("%s's %s", strPlayerName, mode.type),
        t = nDmgTotal, -- "Damage to XXX"
        c = GalaxyMeter.kDamageStrToColor.Self,
		tStr = mode.format(nDmgTotal, nTime),
		progress = 1,
		click = function(m, btn)
			if btn == 0 and mode.nextTotal then
				mode.nextTotal(self, tPlayerLog)
			elseif btn == 1 and mode.prev then
				mode.prev(self)
			end
		end
	}

	local nMax = 0
	for k, v in pairs(tPlayerLog[mode.type]) do
		if v.total > nMax then nMax = v.total end
	end

    for k, v in pairs(tPlayerLog[mode.type]) do

		table.insert(tList, {
			n = k,
			t = v.total,
			c = GalaxyMeter.kDamageTypeToColor[v.dmgType],
			tStr = mode.format(v.total, nTime),
			progress = v.total / nMax,
			click = function(m, btn)
				if btn == 0 and mode.next then
					mode.next(self, v, tPlayerLog)
				elseif btn == 1 then
					mode.prev(self)
				end
			end
		})

	end

	local strDisplayText = string.format("%s's %s", strPlayerName, mode.type)

	-- "%s's Damage to %s"
	local strModePatternTemp = string.format(mode.pattern, strPlayerName, tLogSegment.name)

	-- Move to Report
	local strTotalText = string.format("%s - %d (%.2f) - %s",
		--"%s's blah on %s"
		strModePatternTemp,
		nDmgTotal,
		nDmgTotal / tLogSegment.combat_length,
		self:SecondsToString(tLogSegment.combat_length))

    return tList, tTotal, strDisplayText, strTotalText
end


function GalaxyMeter:GetSpellList()

	--strModeType = damageOut
	--strCurrentLogType = damageDone

	local strActorName = self:LogActorName()
	--local mode = self.vars.tMode

	local tActorLog = self.vars.tLogActor

	local tPlayerLogSpells = tActorLog[self.vars.strModeType]
	local tSpell = tPlayerLogSpells[self.vars.strCurrentSpellName]

	local tSpell = self:LogSpell()

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
		table.insert(tList, {n = string.format("Total Damage (%s)", GalaxyMeter.kDamageTypeToString[tSpell.dmgType]), tStr = tSpell.total, click = cFunc})
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


	local strDisplayText = string.format("%s's %s", strActorName, tSpell.name)

	local strTotalText = strDisplayText .. " for " .. self.vars.tLogDisplay.name

	return tList, nil, strDisplayText, strTotalText
end


function GalaxyMeter:GetSpellTotalsList()

	local strPlayerName = self.vars.strCurrentPlayerName
	local tPlayerLog = self.vars.tLogPlayer

	local modeType = self.vars.tMode.type

	local tSpells = tPlayerLog[modeType]

	local cFunc = function(m, btn)
		if btn == 1 then
			--gLog:info("spell totals previous")
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

    for i = 1, math.min(#tReportStrings, self.settings.nReportLines + 1) do
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
		if v.strReport then
			table.insert(tStrings, v.strReport)
		elseif v.t then
			table.insert(tStrings, string.format("%d) %s - %s (%s)  %.2f%%",
				i, v.n, FormatScaleAmount(v.t), FormatScaleAmount(v.t / tLogSegment.combat_length), v.t / total * 100))
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
function GalaxyMeter:DisplayList(Listing)

	local Arrange = false
	for k, v in ipairs(Listing) do
		if not self.tItems[k] then
			self:AddItem(k)
		end

		local wnd = self.tItems[k]

		if self:CompareDisplay(k, v.n) then
			wnd.id = wnd.wnd:GetId()
			wnd.left_text:SetText(v.n)
			wnd.bar:SetBarColor(v.c)
			Arrange = true
		end

		wnd.OnClick = v.click
		wnd.right_text:SetText(v.tStr)
		wnd.bar:SetProgress(v.progress)
	end
	
	-- Trim Remainder
	if #self.tItems > #Listing then
		for i = #Listing + 1, #self.tItems do
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

	-- Self reference needed for calling object method
	local tList, tTotal, strDisplayText = mode.display(self)

    if mode.sort ~= nil then
        table.sort(tList, mode.sort)
    end

	-- if option to show totals
	if tTotal ~= nil then
		if not tTotal.n then
			tTotal.n = strDisplayText
		end
		if tTotal.click == nil then
			tTotal.click = function(m, btn)
				if btn == 1 and mode.prev then
					--gLog:info("Totals prev")
					mode.prev(self)
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


-- when the Clear button is clicked
function GalaxyMeter:OnClearAll()

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


function GalaxyMeter:GetMode()
	return self.vars.tMode
end

-- Pop last mode off of the stack
function GalaxyMeter:PopMode()

	if self.vars.tModeLast and #self.vars.tModeLast > 0 then
		local mode = table.remove(self.vars.tModeLast)
		--gLog:info(self.vars.tModeLast)
		return mode
	end

	return nil
end


-- Push mode onto the stack
function GalaxyMeter:PushMode(tNewMode)
	self.vars.tModeLast = self.vars.tModeLast or {}

	table.insert(self.vars.tModeLast, self.vars.tMode)

	self.vars.tMode = tNewMode
end


-- TODO Generalize this into DisplayMenu or something
function GalaxyMeter:DisplayMainMenu()
    local tMenuList = {}

    for k, v in pairs(self.tMainMenu) do
        table.insert(tMenuList, {
            n = k,
            c = GalaxyMeter.kDamageStrToColor["DamageType_Physical"],
			progress = 1,
			click = function(m, btn)

				if v and self.vars.tLogDisplay.start > 0 and btn == 0 then

					-- Call next on CURRENT mode, v arg is next mode
					self:PushMode(v)

					self.bDirty = true
				end
			end
        })
	end

    return tMenuList, nil, "Main Menu"
end


-- A player was clicked from an Overall menu, update the mode to the appropriate selection
-- @param strPlayerName Player name
-- @param strSegmentType String identifier for segment type, players/mobs etc
function GalaxyMeter:MenuPlayerSelection(strPlayerName)

	local mode = self.vars.tMode

	self.vars.strCurrentPlayerName = strPlayerName
	self.vars.strCurrentLogType = mode.type

	gLog:info(string.format("MenuPlayerSelection: %s -> %s", self.vars.strCurrentPlayerName, self.vars.strCurrentLogType))

	self.vars.strModeType = self.tListFromSubType[mode.type]	-- Save this because as we delve deeper into menus the type isn't necessarily set

	local newMode = self.tModeFromSubType[mode.type]

	self:PushMode(newMode)

	self.bDirty = true
end


--[[
- Menu reached from 'Player Damage Done: Unit' -> 'Player Blah' clicked
- (GetUnitList)
- Previous menu was the Main Menu so it's safe to assign actor name and such
 ]]
function GalaxyMeter:MenuUnitDetailSelection(tActor)
	local mode = self:GetCurrentMode()

	self:Rover("MenuUnitDetailSelection", {vars=self.vars})

	self:LogActor(tActor)
	self:LogActorName(tActor.strName)
	self:LogType(mode.type)	-- damaged/By healed/healedBy
	self:LogModeType(self.tListFromSubType[mode.type])

	gLog:info(string.format("MenuUnitDetailSelection: %s -> %s", self:LogActorName(), self:LogType()))

	local newMode = {
		-- %s's Damage Done
		name = ("%s's %s"):format(tActor.strName, GalaxyMeter.tDamageTypeToString[mode.type]),
		display = self.GetActorUnitList,
		report = self.ReportGenericList,
		type = mode.type,
		segType = mode.segType,
		prev = self.MenuPrevious,
		-- Damage done to mob type by actor
		--next = self.MenuPlayerDmgByMobBreakdownSelection,
		sort = function(a, b) return a.t > b.t end,
		format = function(...)
			return GalaxyMeter:FormatAmountTime(...)
		end
	}

	self:PushMode(newMode)

	self:Dirty(true)
end


function GalaxyMeter:MenuSpell(tSpell, tActor)

	self:LogActor(tActor)
	self:LogSpell(tSpell)

	self:PushMode(self.tModes["Spell Breakdown"])

	self.bDirty = true
end


function GalaxyMeter:MenuPlayerSpellTotal(tPlayerLog)

	local mode = self.vars.tMode

	self.vars.tLogPlayer = tPlayerLog

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

	self:PushMode(newMode)

	self.bDirty = true

	self.vars.tMode = newMode
end


function GalaxyMeter:MenuPrevious()

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

function GalaxyMeter:OnListItemGenerateTooltip(wndHandler)
	wndHandler:SetTooltip(wndHandler:FindChild("LeftText"):GetText())
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

		tSave.version = GalaxyMeter.nVersion
		tSave.settings = self.settings

		--if self.wndMain then
			tSave.settings.anchor = {self.wndMain:GetAnchorOffsets()}
		--else
		--	tSave.settings.anchor = self.settings.anchor
		--end

		tSave.bActive = self.wndMain:IsVisible()
		
	elseif eType == GameLib.CodeEnumAddonSaveLevel.Character then
	end
	
	return tSave
end


function GalaxyMeter:OnRestore(eType, t)
	gLog:info("OnRestore()")

	if not t or not t.version or t.version < GalaxyMeter.nVersion then
		return
	end

	if eType == GameLib.CodeEnumAddonSaveLevel.General then

		if t.settings then
			self.settings = t.settings

			if t.settings.anchor then
				--self.settings.anchor = t.settings.anchor
				self.wndMain:SetAnchorOffsets(unpack(t.settings.anchor))

				-- Reopen if it was last open
				if t.bActive then
					self.wndMain:Show(true)
					self:RefreshDisplay()
				end
			end

		end
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
Apollo.RegisterAddon(GalaxyMeterInst, false, "", {"GeminiLogging-1.1", "drafto_Queue-1.1"})
