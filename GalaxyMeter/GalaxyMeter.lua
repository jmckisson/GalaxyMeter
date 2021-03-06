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

-- Global -> Local
local clock = os.clock
local error = error
local math = math
local pairs = pairs
local setmetatable = setmetatable
local string = string
local table = table
local tonumber = tonumber
local tostring = tostring
local unpack = unpack
local Apollo = Apollo
local ApolloTimer = ApolloTimer
local CColor = CColor
local ChatSystemLib = ChatSystemLib
local Event_FireGenericEvent = Event_FireGenericEvent
local GameLib = GameLib
local GroupLib = GroupLib
local XmlDoc = XmlDoc


-----------------------------------------------------------------------------------------------
-- GalaxyMeter Module Definition
-----------------------------------------------------------------------------------------------
local GalaxyMeter = {
	nVersion = 18,
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
	},
	kEventDamage = "GalaxyMeterDamage",
	kEventDeflect = "GalaxyMeterDeflect",
	kEventHeal = "GalaxyMeterHeal",
	tDefaultSettings = {
		bDebug = false,
		strReportChannel = "g",
		nReportLines = 5,
		nFormatType = 1,
		bPersistLogs = true,
	},
}

local function HexToCColor(color)
	local r = tonumber(string.sub(color,1,2), 16) / 255
	local g = tonumber(string.sub(color,3,4), 16) / 255
	local b = tonumber(string.sub(color,5,6), 16) / 255
	local a = tonumber(string.sub(color,5,6 or "FF"), 16) / 255
	return CColor.new(r,g,b,1)
end



local gLog
local GM
local Player
local Mob

local Queue = {}
function Queue.new()
	return {first = 0, last = -1}
end

function Queue.PushLeft(queue, value)
	local first = queue.first - 1
	queue.first = first
	queue[first] = value
	return first
end


function Queue.PushRight(queue, value)
	local last = queue.last + 1
	queue.last = last
	queue[last] = value
	return last
end


function Queue.PopLeft(queue)
	local first = queue.first
	if first > queue.last then error("queue is empty") end
	local value = queue[first]
	queue[first] = nil        -- to allow garbage collection
	queue.first = first + 1
	return value
end


function Queue.PopRight(queue)
	local last = queue.last
	if queue.first > last then error("queue is empty") end
	local value = queue[last]
	queue[last] = nil         -- to allow garbage collection
	queue.last = last - 1
	return value
end


function Queue.Size(queue)
	return queue.last - queue.first + 1
end


----------------------------------
-- Log Definition
----------------------------------
local Log = {
	entries = Queue.new(),
	nDisplayIdx = 0,
	nCurrentIdx = 0,
}
Log.__index = Log

setmetatable(Log, {
	-- Allow l = Log() syntax
	__call = function(cls, ...)
		local self = setmetatable({}, cls)
		self:_init(...)
		return self
	end
})


-- Factory method
function Log.CreateNewLog(strName)

	Log.entries = Log.entries or Queue.new()

	local log = Log(strName)

	log.idx = Queue.PushRight(Log.entries, log)

	Log.nCurrentIdx = log.idx

	return log
end


function Log.RestoreLogs(tLogData)

	Log.entries = Queue.new()

	for k, v in pairs(tLogData) do
		gLog:info("   Restoring log: " .. v.name)

		local log = Log(v.name)

		log:Restore(v)

		log.idx = Queue.PushRight(Log.entries, log)
	end

	-- This sets nCurrentIdx
	Log.CreateNewLog("Current")

	if Log.entries.first < Log.entries.last then
		Log.nDisplayIdx = Log.entries.last - 1
	else
		Log.nDisplayIdx = Log.entries.last
	end
end


function Log.SerializeLogs()

	--gLog:info("SerializeLogs()")
	--GM:Rover("SerializeLogs", Log.entries)

	-- Get rid of current entry if its not in progress (should be blank)

	local currentLog = GM:GetLog()

	if not currentLog then return end

	if currentLog.start == 0 then
		Queue.PopRight(Log.entries)
	end

	local entries = Log.entries

	local tLogData = {}
	-- This effectively resets the first/last counters
	for i = entries.first, entries.last do
		local data = entries[i]:GetData()

		gLog:info()

		table.insert(tLogData, data)
	end

	return tLogData
end


function Log:_init(strTitle)
	self.name = strTitle
	self.players = {}
	self.mobs = {}
	self.start = 0
end


function Log:Restore(tData)
	self.start = tData.start
	if tData.stop then self.stop = tData.stop end

	gLog:info(string.format("    %d Players", #tData.players))

	self.players = {}
	for k, v in pairs(tData.players) do

		-- TODO Make player table keys match tPlayerInfo keys so we can use table as param without translating
		local player = Player({
			strName = v.strName,
			nId = v.playerId,
			nClassId = v.classId,
		})

		player:SetData(v)

		self.players[v.strName] = player
	end

	gLog:info(string.format("    %d Mobs", #tData.mobs))

	self.mobs = {}
	for k, v in pairs(tData.mobs) do

		local mob = Mob({nId=v.id})

		mob:SetData(v)

		self.mobs[v.id] = mob
	end
end


function Log:GetCombatLength()
	if self.start == 0 then
		return 0
	elseif not self.stop then
		return clock() - self.start
	else
		return self.stop - self.start
	end
end


--[[
-- Return serialization friendly data table
]]
function Log:GetData()
	local t = {
		name = self.name,
		start = self.start,
		players = {},
		mobs = {},
	}

	if self.stop then
		t.stop = self.stop
	end

	for _, player in pairs(self.players) do
		table.insert(t.players, player:GetData())
	end

	for _, mob in pairs(self.mobs) do
		table.insert(t.mobs, mob:GetData())
	end

	return t
end


function Log:IsActive()
	return self.start > 0 and not self.stop
end


function Log:Start()
	--gLog:info(string.format("Log %d start, %.1fs", self.idx, self.start))
	self.start = clock()
end


function Log:Stop()
	self.stop = clock()
	--gLog:info(string.format("Log %d stop, time %.1f, length %.1fs", self.idx, self.stop, self:GetCombatLength()))
end


function Log:TryStart(tEvent)

	local target = tEvent.tTargetInfo.unit

	-- Should we trigger a new log segment?
	if self.start == 0 and target:GetType() ~= "Harvest" then

		self:Start()
		GM.timerDisplay:Start()
		GM.timerTimer:Start()

		local displayIdx = Log.nDisplayIdx

		if GM.settings.bDebug then
			gLog:info(string.format("TryStart(%d @ %.1f) %.1fs, current %d, display %d",
				self.idx, self.start, self:GetCombatLength(), Log.nCurrentIdx, Log.nDisplayIdx))
		end

		-- Switch to the newly started segment if we're looking at the most recent segment
		if displayIdx == self.idx - 1 then
			if GM.settings.bDebug then
				gLog:info(string.format("Display(%d : %.1fs) -> Current(%d :%.1fs)",
					displayIdx, Log.entries[Log.nDisplayIdx]:GetCombatLength(), self.idx, self:GetCombatLength()))
			end

			Log.nDisplayIdx = self.idx
		end

		if not target:IsACharacter() then
			self.name = tEvent.tTargetInfo.strName
		else
			-- So attacking plants sometimes returns not NonPlayer, with a nil targettarget
			if target:GetTarget() then
				self.name = target:GetTarget():GetName()
			else
				self.name = "Unknown"
			end
		end

		Event_FireGenericEvent("GalaxyMeterLogStart", self)

		--gLog:info(string.format("TryStart: Set activeLog.name to %s, targetType %s", self.name, target:GetType()))
	end
end


function Log:GetTimeString()
	local time = self:GetCombatLength()
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


-- Find but do not create ne entry if missing
function Log:FindMob(nMobId)
	return self.mobs[nMobId]
end


--[[
-- Find or create mob data table
-- @return Mob data table
--]]
function Log:GetMob(nMobId, unit)

	local mob = self:FindMob(nMobId)

	if not mob then

		mob = Mob(nMobId, unit)

		self.mobs[nMobId] = mob
	end

	return mob
end


--[[
-- Find or create player data table
-- @return Player data table
--]]
function Log:GetPlayer(strName, tPlayerInfo)

	local player = self.players[strName]

	if not player then

		player = Player(tPlayerInfo)

		self.players[strName] = player
	end


	if not player.classId then
		--gLog:error(string.format("%s missing ClassId", player.strName))
		player.classId = 0
	end

	if tPlayerInfo.nClassId ~= player.classId then
		if not GalaxyMeter.ClassToColor[strName] then
			gLog:warn(string.format("%s ClassId mismatch, was %s, now %s", player.strName, tostring(player.classId), tostring(tPlayerInfo.nClassId)))
			player.classId = tPlayerInfo.nClassId
		end
	end

	-- Update player active time if this log is active
	-- Log may not be active if combat ended and the new segment hasnt started yet because heals
	-- don't trigger segment starts
	if self.start > 0 then
		player:UpdateActiveTime()
	end

	return player
end

 
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

GalaxyMeter.ClassToColor = {
	HexToCColor("855513"),	-- Warrior
	HexToCColor("cf1518"),	-- Engineer
	HexToCColor("c875c4"),	-- Esper
	HexToCColor("2cc93f"),	-- Medic
	HexToCColor("d7de1f"),	-- Stalker
	HexToCColor("ffffff"),	-- Corrupted
	HexToCColor("5491e8"),	-- Spellslinger
	[23] = CColor.new(1, 0, 0, 1),	-- NonPlayer
	["Humera"] = HexToCColor("6e1dbf"),
	--["LemonKing"] = self:HexToCColor("f3f315"),
	["LemonKing"] = HexToCColor("f7ff00"),
	["Ricardo"] = HexToCColor("006699"),
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
		level = GeminiLogging.FATAL,
		pattern = "[%d] %n [%c:%l] - %m",
		appender = "GeminiConsole"
	})

	GM = self
	GalaxyMeter.Log = Log
	GalaxyMeter.Logger = gLog
	GalaxyMeter.Queue = Queue
	Player = self.Player
	Mob = self.Mob
	self.Log = Log
	
	-- Slash Commands
	Apollo.RegisterSlashCommand("galaxy", 							"OnGalaxyMeterOn", self)
	Apollo.RegisterSlashCommand("lkm", 								"OnGalaxyMeterOn", self)

	-- Player Updates
	Apollo.RegisterEventHandler("ChangeWorld", 						"OnChangeWorld", self)

	-- Self Combat Logging
	Apollo.RegisterEventHandler("UnitEnteredCombat", 				"OnEnteredCombat", self)
	Apollo.RegisterEventHandler("UnitCreated",						"OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed",					"OnUnitDestroyed", self)
	--Apollo.RegisterEventHandler("SpellCastFailed", 				"OnSpellCastFailed", self)
	--Apollo.RegisterEventHandler("SpellEffectCast", 				"OnSpellEffectCast", self)
	--Apollo.RegisterEventHandler("CombatLogAbsorption",			"OnCombatLogAbsorption", self)
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

	-- Handled by Configure
	self.settings = {
		bDebug = false,
		strReportChannel = "g",
		nReportLines = 5,
		nFormatType = 1,
		bPersistLogs = true,
	}

	self.bGroupInCombat = false
	self.bInCombat = false


	-- Display Modes, list of mode names, callbacks for display and report, and log subtype indices
	-- TODO Move these into the individual menu builders
	self.tModes = {
		["Main Menu"] = {
			name = "Main Menu",
			display = self.DisplayMainMenu,
			report = nil,
			prev = nil,
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
				if self.settings.nFormatType == 2 then
					return self:FormatAmountActiveTime(...)
				elseif self.settings.nFormatType == 3 then
					return self:FormatAmountActiveTimeLength(...)
				end

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
				if self.settings.nFormatType == 2 then
					return self:FormatAmountActiveTime(...)
				elseif self.settings.nFormatType == 3 then
					return self:FormatAmountActiveTimeLength(...)
				end

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
	}

	self.bPetAffectingCombat = false
	self:NewLogSegment()

	Log.nDisplayIdx = Log.entries.last

	self.Deaths:Init()
	self.MobData:Init()

	self.timerPulse:Start()

	gLog:info(string.format("OnLoad() current %d, display %d", Log.nCurrentIdx, Log.nDisplayIdx))
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


function GalaxyMeter:DebugLogTimes()

	local log = self:GetLogDisplay()

	if not log then return end

	local nLogTime = log:GetCombatLength()

	for _, actor in pairs(log.players) do

		local nActorTime = actor:GetActiveTime()

		if nActorTime > nLogTime then
			gLog:info(string.format("[log %d : %.1fs : %.1f] %s :: first %.1f last %.1f active %.1fs",
				log.idx, nLogTime, log.start, actor.strName, actor.firstAction, actor.lastAction, nActorTime))

			break
		end
	end

end


-----------------------------------------------------------------------------------------------
-- Timers
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnPulse()

	--[[
	if self.settings.bDebug then
		self:DebugLogTimes()
	end
	--]]

	local currentLog = self:GetLog()

	-- Check if the rest of the group is out of combat
	if currentLog.start > 0 and not self:GroupInCombat() then

		self.timerDisplay:Stop()
		self.timerTimer:Stop()
		self:GetLog():Stop()

		if currentLog:GetCombatLength() > 10 then
			gLog:info("OnPulse: stopping combat segment")

			-- Pop off oldest, TODO Add config option to keep N old logs
			if Queue.Size(Log.entries) >= 30 then
				Queue.PopLeft(Log.entries)
			end

			Event_FireGenericEvent("GalaxyMeterLogStop", self:GetLog())

			self:NewLogSegment()	-- sets nCurrentIdx to new segment idx

			if self.settings.bDebug then
				gLog:info(string.format("Push current %d, display %d, first %d, last %d",
					Log.nCurrentIdx, Log.nDisplayIdx, Log.entries.first, Log.entries.last))
			end

		else
			gLog:info("OnPulse: short segment, clearing")

			Queue.PopRight(Log.entries)

			self:NewLogSegment()

			self.Children.TimeText:SetText("0.0s")
			self:RefreshDisplay()
		end

	end
end


function GalaxyMeter:OnDisplayTimer()

	if self.wndMain:IsVisible() and Log.nDisplayIdx == Log.entries.last then

		if self.bDirty then
			self:RefreshDisplay()
			self.bDirty = false
		end
	end
end


function GalaxyMeter:OnTimerTimer()

	local currentLog = self:GetLog()

	if self.wndMain:IsVisible() and Log.nDisplayIdx == currentLog.idx then

		self.Children.TimeText:SetText(currentLog:GetTimeString())
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
			--gLog:info("bPetAffectingCombat true")
		end
	end

end


function GalaxyMeter:OnUnitDestroyed(unit)

	if unit and unit:GetUnitOwner() and unit:GetUnitOwner():IsThePlayer() then
		self.bPetAffectingCombat = false
		--gLog:info("bPetAffectingCombat false")
	end

end


-- OK, somehow the game thinks I'm out of combat sometimes when im not... this makes it try a few times
local nCombatCount = 0
local function FixCombatBug(bCombat)
	local bInCombat = false

	if not bCombat then
		if nCombatCount < 2 then
			nCombatCount = nCombatCount + 1
			bInCombat = true
		else
			nCombatCount = 0
		end
	else
		nCombatCount = 0
	end

	--[[
	if nCombatCount > 0 then
		gLog:info("nCombatCount: " .. nCombatCount)
	end
	--]]

	return bInCombat or bCombat
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

	-- WHY DOES THE GAME SOMETIMES RETURN ISINCOMBAT FALSE WHEN IM IN COMBAT KSAJDFKSJDFKS
	local bSelfInCombat = GameLib.GetPlayerUnit():IsInCombat() or self.bPetAffectingCombat or self.bInCombat

	local nMemberCount = GroupLib.GetMemberCount()
	if nMemberCount == 0 then

		--self.bGroupInCombat = bSelfInCombat
		self.bGroupInCombat = FixCombatBug(bSelfInCombat)

		if not self.bGroupInCombat then
			gLog:info(string.format("GroupInCombat: self %s, pet %s, returning %s",
				tostring(GameLib.GetPlayerUnit():IsInCombat()), tostring(self.bPetAffectingCombat), tostring(self.bGroupInCombat)))
		end

		return self.bGroupInCombat
	end

	local bCombat = false

	for i = 1, nMemberCount do
		local tUnit = GroupLib.GetUnitForGroupMember(i)

		if tUnit and (tUnit:IsInCombat() or (bSelfInCombat and tUnit:IsDead())) then
			bCombat = true

			break
		end

	end

	if not bSelfInCombat and not bCombat then
		bCombat = FixCombatBug(bSelfInCombat)

		gLog:info(string.format("GroupInCombat: grp out, bSelfInCombat %s, self.bInCombat %s", tostring(bSelfInCombat), tostring(self.bInCombat)))
	end

	self.bGroupInCombat = bCombat
	
	return bCombat
end


function GalaxyMeter:NewLogSegment()

	-- tCurrentLog always points to the segment in progress, even if it hasnt started yet
    local newLog = Log.CreateNewLog("Current")

   	--self.tCurrentLog = newLog

	self:Rover("log", Log.entries)
end



-----------------------------------------------------------------------------------------------
-- GalaxyMeter OnEnteredCombat
-----------------------------------------------------------------------------------------------
function GalaxyMeter:OnEnteredCombat(unit, bInCombat)
	
	if unit:GetId() == GameLib.GetPlayerUnit():GetId() then

		-- We weren't in combat before, so start new segment
		if not bInCombat and not self.bPetAffectingCombat then
			-- Hm, we shouldnt set this flag if the spell was a heal...
			--gLog:info("OnEnteredCombat: self combat false")
			self.bInCombat = false
        else
			--gLog:info("OnEnteredCombat: self combat true")
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

	if strArg == "debug" then
		self.settings.bDebug = not self.settings.bDebug

		if self.settings.bDebug then
			gLog.level = "INFO"
		else
			gLog.level = "FATAL"
		end

		gLog:fatal("bDebug = " .. tostring(self.settings.bDebug))

	elseif strArg == "interrupt" then
		self.Interrupts:Init()

	elseif strArg == "default" then
		self.settings = GalaxyMeter.tDefaultSettings

	elseif strArg == "test" then
		self:Rover("SLog", Log.SerializeLogs())

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

		elseif args[1] == "format" and args[2] then
			self.settings.nFormatType = tonumber(args[2])
			gLog:info("Format type: " .. self.settings.nFormatType)

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


-- Current log is always the 'last' entry in the queue
function GalaxyMeter:GetLog()
	return Log.entries[Log.entries.last]
end


function GalaxyMeter:GetLogDisplay()
	return Log.entries[Log.nDisplayIdx]
end



function GalaxyMeter:SetLogTitle(title)

	local log = self:GetLog()

	if log.name == "" then
		log.name = title
		if Log.entries.last == Log.nDisplayIdx then
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

	if self.tIsDummy[tEvent.tTargetInfo.strName] then
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


-- TODO handle multiple healevents in tHealData[]
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
	if tEventArgs.tHealData and self:GetLog():IsActive() then

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

		--[[
		tEvent.nTypeId = self:GetHealEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

		if tEvent.nTypeId > 0 and tEvent.nDamage then

			self:AssignPlayerInfo(tEvent, tEventArgs)

			local player = self:GetPlayer(self.tCurrentLog.players, tEvent)

			self:UpdateSpell(tEvent, player)
		else
			gLog:error(string.format("OnCLTransference: Something went wrong! type %d dmg %d", tEvent.nTypeId, tEvent.nDamage or 0))
		end
		--]]

		if tEvent.nDamage then
			self:ProcessHeal(tEvent, tEventArgs)
		else
			gLog:error(string.format("OnCLTransference: Something went wrong! dmg %d", tEvent.nDamage or 0))
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

	tEvent.nTypeId = self:GetDamageEventType(tEvent)

	if tEvent.nTypeId > 0 then

		local log = self:GetLog()

		log:TryStart(tEvent)

		if log:IsActive() then
			local player = log:GetPlayer(tEvent.tPlayerInfo.strName, tEvent.tPlayerInfo)
			player:UpdateSpell(tEvent)

			Event_FireGenericEvent(GalaxyMeter.kEventDeflect, tEvent)
		end
	else
		if tEvent.nTypeId ~= -1 then
			gLog:error(string.format("OnCLDeflect: Something went wrong!  Caster '%s', Target '%s', Spell '%s'",
				tEvent.tCasterInfo.strName, tEvent.tTargetInfo.strName, tEvent.strSpellName))
		end
	end
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

	tEvent.nTypeId = self:GetDamageEventType(tEvent)

	if tEvent.nTypeId > 0 then

		local log = self:GetLog()

		log:TryStart(tEvent)

		if log:IsActive() then

			local player = log:GetPlayer(tEvent.tPlayerInfo.strName, tEvent.tPlayerInfo)

			--self:Rover("OnCLDamage", {tEvent=tEvent, player=player})

			player:UpdateSpell(tEvent)

			Event_FireGenericEvent(GalaxyMeter.kEventDamage, tEvent)
		end

	else
		gLog:error(string.format("OnCLDamage: Something went wrong!  Invalid type Id, dmg raw %d, dmg %d", tEventArgs.nRawDamage, tEventArgs.nDamageAmount))

	end

end


function GalaxyMeter:OnCombatLogHeal(tEventArgs)

	-- Heals don't trigger log start
	if self:GetLog().start == 0 then return end

	local tEvent = self:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tEvent then return end

	tEvent.bDeflect = false
	tEvent.nDamage = tEventArgs.nHealAmount
	--tEvent.nHealAmount = tEventArgs.nHealAmount
	--tEvent.Shield = tEventArgs.nShield
	--tEvent.Absorb = tEventArgs.nAbsorption
	--tEvent.Periodic = tEventArgs.bPeriodic
	tEvent.nOverheal = tEventArgs.nOverheal
	tEvent.eResult = tEventArgs.eCombatResult
	tEvent.eEffectType = tEventArgs.eEffectType
	tEvent.eDamageType = tEventArgs.eDamageType

	if not self.tLastHeal then
		self.tLastHeal = {
			time = os.time(),
			d = tEvent.nDamage,
			c = tEvent.tCasterInfo.strName,
			t = tEvent.tTargetInfo.strName,
		}
	else
		if self.tLastHeal.d == tEvent.nDamage
		and self.tLastHeal.c == tEvent.tCasterInfo.strName
		and self.tLastHeal.t == tEvent.tTargetInfo.strName then
			if os.time() - self.tLastHeal.time < 0.1 then
				--gLog:info("Discarding duplicate heal")
				self.tLastHeal = nil
				return
			end
		end

		self.tLastHeal = nil
	end

	-- Temporary hack until we switch to checking spell effect type instead of tEvent.DamageType
	if tEventArgs.eEffectType == Spell.CodeEnumSpellEffectType.Heal then
		tEvent.eDamageType = GameLib.CodeEnumDamageType.Heal
	elseif tEventArgs.eEffectType == Spell.CodeEnumSpellEffectType.HealShields then
		tEvent.eDamageType = GameLib.CodeEnumDamageType.HealShields
	end

	if not tEventArgs.unitTarget or not tEventArgs.unitCaster then
		gLog:error(string.format("OnCLHeal: nil unitTarget or caster, caster[%d] %s, target [%d] %s",
			self:GetUnitId(tEventArgs.unitCaster), self:HelperGetNameElseUnknown(tEventArgs.unitCaster),
			self:GetUnitId(tEventArgs.unitTarget), self:HelperGetNameElseUnknown(tEventArgs.unitTarget)))
		return
	end

	if tEvent.nDamage then

		self:ProcessHeal(tEvent, tEventArgs)
	else
		gLog:error("OnCLHeal: Something went wrong!  Invalid type Id!")
	end
end


-- Used by both OnCombatLogHeal and OnCombatLogTransference
function GalaxyMeter:ProcessHeal(tEvent)

	tEvent.nEffectiveHeal = tEvent.nDamage

	-- If target is at max health, nDamage == nOverheal
	if tEvent.tTargetInfo.nHealth == tEvent.tTargetInfo.nMaxHealth then
		tEvent.nEffectiveHeal = tEvent.nDamage - tEvent.nOverheal
	end

	--[[
	gLog:info(string.format("Heal:: %s => %s  nAmount %d, nOverheal %d, nEffective %d",
		tEvent.tCasterInfo.strName, tEvent.tTargetInfo.strName,
		tEvent.nDamage, tEvent.nOverheal, tEvent.nEffectiveHeal))
	--]]

	if tEvent.tCasterInfo.nId == tEvent.tTargetInfo.nId then
		tEvent.nTypeId = GalaxyMeter.eTypeDamageOrHealing.HealingInOut

		tEvent.tPlayerInfo = tEvent.tCasterInfo

		local player = self:GetLog():GetPlayer(tEvent.tPlayerInfo.strName, tEvent.tPlayerInfo)

		player:UpdateSpell(tEvent)

		Event_FireGenericEvent(GalaxyMeter.kEventHeal, tEvent)

		return
	end

	if tEvent.tCasterInfo.bIsPlayer then

		tEvent.nTypeId = GalaxyMeter.eTypeDamageOrHealing.HealingOut

		tEvent.tPlayerInfo = tEvent.tCasterInfo

		local player = self:GetLog():GetPlayer(tEvent.tPlayerInfo.strName, tEvent.tPlayerInfo)

		player:UpdateSpell(tEvent)

		Event_FireGenericEvent(GalaxyMeter.kEventHeal, tEvent)
	end

	if tEvent.tTargetInfo.bIsPlayer then

		tEvent.nTypeId = GalaxyMeter.eTypeDamageOrHealing.HealingIn

		tEvent.tPlayerInfo = tEvent.tTargetInfo

		local player = self:GetLog():GetPlayer(tEvent.tPlayerInfo.strName, tEvent.tPlayerInfo)

		player:UpdateSpell(tEvent)

		Event_FireGenericEvent(GalaxyMeter.kEventHeal, tEvent)
	end

end


--[[
-- Sets up an event object with name, id, class etc of the caster and target.
-- If the caster is a pet then strCaster/Id/Class are set to its owner
 ]]
function GalaxyMeter:HelperCasterTargetSpell(tEventArgs, bTarget, bSpell)
	local tInfo = {
		strSpellName = nil,
		strColor = nil,
		tCasterInfo = {
			bSourcePet = false,
			strName = nil,
			nClassId = nil,
			nId = nil,
			unit = tEventArgs.unitCaster,
		},
		tTargetInfo = {
			bSourcePet = false,
			strName = nil,
			nClassId = nil,
			nId = nil,
			unit = tEventArgs.unitTarget,
		},
	}

	if bSpell then
		tInfo.strSpellName = self:HelperGetNameElseUnknown(tEventArgs.splCallingSpell)

		if tEventArgs.eDamageType == Spell.CodeEnumSpellEffectType.DistanceDependentDamage then
			tInfo.strSpellName = ("%s (Distance)"):format(tInfo.strSpellName)
		elseif tEventArgs.eDamageType == Spell.CodeEnumSpellEffectType.DistributedDamage then
			tInfo.strSpellName = ("%s (Distributed)"):format(tInfo.strSpellName)
		end

		if tEventArgs.bPeriodic then
			tInfo.strSpellName = ("%s (Dot)"):format(tInfo.strSpellName)
		end
	end

	if tEventArgs.unitCaster then

		if tEventArgs.unitCasterOwner and tEventArgs.unitCasterOwner:IsACharacter() then
			-- Caster is a pet, assign caster to the owners name
			tInfo.tCasterInfo.bSourcePet = true

			tInfo.strSpellName = ("%s: %s"):format(tEventArgs.unitCaster:GetName(), tInfo.strSpellName)

			tInfo.tCasterInfo.unit = tEventArgs.unitCasterOwner

			tInfo.tCasterInfo.strName = tEventArgs.unitCasterOwner:GetName()
			--tInfo.tCasterInfo.nClassId = tEventArgs.unitCasterOwner:GetClassId()
			--tInfo.tCasterInfo.nHealth = tEventArgs.unitCasterOwner:GetHealth()
			--tInfo.tCasterInfo.nMaxHealth = tEventArgs.unitCasterOwner:GetMaxHealth()
		else
			-- Caster was not a pet
			tInfo.tCasterInfo.strName = self:HelperGetNameElseUnknown(tEventArgs.unitCaster)
		end

		tInfo.tCasterInfo.bIsPlayer = self:IsPlayerOrPlayerPet(tEventArgs.unitCaster)
		tInfo.tCasterInfo.nId = tEventArgs.unitCaster:GetId()
		tInfo.tCasterInfo.nClassId = tInfo.tCasterInfo.unit:GetClassId()
		tInfo.tCasterInfo.nHealth = tInfo.tCasterInfo.unit:GetHealth()
		tInfo.tCasterInfo.nMaxHealth = tInfo.tCasterInfo.unit:GetMaxHealth()

	else
		-- No caster for this spell, wtf should I do?
		local nTargetId = self:GetUnitId(tEventArgs.unitTarget)
		local strTarget = self:HelperGetNameElseUnknown(tEventArgs.unitTarget)

		-- Hack to fix Pets sometimes having no unitCaster
		gLog:warn(string.format("HelperCasterTargetSpell unitCaster nil(pet?): Caster[%d] %s, Target[%d] %s, Spell: '%s'",
			0, "Unknown", nTargetId, strTarget, tInfo.strSpellName or "Unknown"))

		return nil
	end

	if bTarget then
		tInfo.tTargetInfo.strName = self:HelperGetNameElseUnknown(tEventArgs.unitTarget)
		if tEventArgs.unitTargetOwner and tEventArgs.unitTargetOwner:GetName() then
			tInfo.tTargetInfo.strName = string.format("%s (%s)", tInfo.tTargetInfo.strName, tEventArgs.unitTargetOwner:GetName())
		end

		if tEventArgs.unitTarget then
			tInfo.tTargetInfo.nId = tEventArgs.unitTarget:GetId()
			tInfo.tTargetInfo.nClassId = tEventArgs.unitTarget:GetClassId()
			tInfo.tTargetInfo.bIsPlayer = self:IsPlayerOrPlayerPet(tEventArgs.unitTarget)
			tInfo.tTargetInfo.nHealth = tInfo.tTargetInfo.unit:GetHealth()
			tInfo.tTargetInfo.nMaxHealth = tInfo.tTargetInfo.unit:GetMaxHealth()
		else
			-- Uhh? no target, no idea what to set classid to
			gLog:warn(string.format("HelperCasterTargetSpell nil unitTarget, caster '%s', strTarget '%s', spell '%s'", tInfo.tCasterInfo.strName, tInfo.tTargetInfo.strName, tInfo.strSpellName))
			return nil
		end

	end

	tInfo.tPlayerInfo = {}

	if tInfo.tCasterInfo.bIsPlayer then
		tInfo.tPlayerInfo = tInfo.tCasterInfo
	elseif tInfo.tTargetInfo.bIsPlayer then
		tInfo.tPlayerInfo = tInfo.tTargetInfo
	else
		gLog:warn("Caster nor Target is a player")
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

	-- Pets still sometimes return a nil unitTarget?

	return false
end


--[[
-- @return {true if unit is player OR pet, true only if unit is a player pet}
 ]]
function GalaxyMeter:IsPlayerOrPlayerPet(unit)
	if not unit then return false, false end

	local bIsPlayer = unit:IsACharacter()
	local bIsPet = unit:GetUnitOwner() and unit:GetUnitOwner():IsACharacter()

	return (bIsPlayer or bIsPet), bIsPet
end


function GalaxyMeter:GetDamageEventType(tEvent)

	--[[
	 source mob or pet 		&& target player or pet => mob dmg out
	 source player or pet	&& target mob or pet	=> mob dmg in
	 source mob or pet		&& target mob or pet	=> mob dmg in/out
	 --]]

	local retVal = 0

	if tEvent.tTargetInfo.unit:IsACharacter() then
		-- Target is a player`

        -- Self damage
		if tEvent.tCasterInfo.unit:IsACharacter() and tEvent.tTargetInfo.nId == tEvent.tCasterInfo.nId then
            return GalaxyMeter.eTypeDamageOrHealing.DamageInOut
        end

        retVal = GalaxyMeter.eTypeDamageOrHealing.DamageIn

	else
		-- Target is not a player

		if tEvent.tCasterInfo.bIsPlayer then
			-- This is being set when the caster is not yourself
       		retVal = GalaxyMeter.eTypeDamageOrHealing.DamageOut

		-- Or to a pet
		elseif tEvent.tTargetInfo.bIsPlayer then
			--gLog:info("Damage targetting player pet")
			retVal = -1
		end

		if retVal == 0 then
			gLog:error("Unknown dmg type")
		end

	end

	return retVal
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


function GalaxyMeter:FormatAmountActiveTimeLength(nAmount, nTime, nTimeTotal)
	return ("%s (%s) (%s)t - %.1fs"):format(
		FormatScaleAmount(nAmount),
		FormatScaleAmount(nAmount / nTime),
		FormatScaleAmount(nAmount / nTimeTotal),
		nTime)
end


function GalaxyMeter:FormatAmountActiveTime(nAmount, nTime, nTimeTotal)
	return ("%s (%s) (%s)t"):format(
		FormatScaleAmount(nAmount),
		FormatScaleAmount(nAmount / nTime),
		FormatScaleAmount(nAmount / nTimeTotal))
end


function GalaxyMeter:FormatAmountTime(nAmount, nTime)
	return ("%s (%s)"):format(FormatScaleAmount(nAmount), FormatScaleAmount(nAmount / nTime))
end


function GalaxyMeter:FormatAmount(nCount)
	return ("%s"):format(nCount)
end



-----------------------------------------------------------------------------------------------
-- List Generators
--
-- TODO These are pretty similar... Consider refactoring them into a more generic method
-----------------------------------------------------------------------------------------------
--[[
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
--]]


--[[
-- We got here from a MenuUnitDetailSelection menu
-- Display what spells from the actor damaged/healed the target
 ]]
function GalaxyMeter:GetActorUnitList()
	local mode = self:GetCurrentMode()
	local tLogSegment = self:GetLogDisplay()
	local tActor = self:LogActor()

	-- Who did this actor interact with?
	local typeTotal = GalaxyMeter.tTotalFromListType[mode.type]

	local nMax = 0
	local nActorTotal = tActor[typeTotal]

	-- Find max
	for k, v in pairs(tActor[mode.type]) do
		if v > nMax then v = nMax end
	end

	local nTime = tActor:GetActiveTime()

	-- Build list
	local tList = {}
	for k, v in pairs(tActor[mode.type]) do

		--self:Rover("GetActorUnitList", {nTime = nTime, k=k, v=v})

		table.insert(tList, {
			n = k,
			t = v,
			tStr = mode.format(v, nTime),
			progress = v / nMax,
			c = GalaxyMeter.ClassToColor[23],	-- This should be the class of the target...
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
		c = GalaxyMeter.ClassToColor[tActor.classId],
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

	local nTime = tLogSegment:GetCombatLength()

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

			local nActorTime = tActor:GetActiveTime()

			table.insert(tList, {
				n = tActor.strName,
				t = nActorTotal,
				c = GalaxyMeter.ClassToColor[tActor.classId],
				tStr = mode.format(nActorTotal, nActorTime),
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
		FormatScaleAmount(tTotal.t / nTime),
		tLogSegment:GetTimeString())

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

	local tLogSegment = self:GetLogDisplay()
	local mode = self.vars.tMode

	-- Grab segment type from mode: players/mobs/etc
	local tSegmentType = tLogSegment[mode.segType]

	local nTime = tLogSegment:GetCombatLength()

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
	tTotal.tStr = mode.format(tTotal.t, nTime, nTime)

	local tList = {}
    for k, tActor in pairs(tSegmentType) do

		-- Only show people who have contributed
		if tActor[mode.type] and tActor[mode.type] > 0 then

			local nAmount = tActor[mode.type]

			local nActorTime = tActor:GetActiveTime()


			table.insert(tList, {
				n = tActor.strName,
				t = nAmount,
				tStr = mode.format(nAmount, nActorTime, nTime),
				c = GalaxyMeter.ClassToColor[tActor.classId],
				progress = nAmount / nMax,
				click = function(m, btn)
					-- arg is the specific actor log table
					if btn == 0 and mode.next then
						mode.next(self, tActor)

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
		FormatScaleAmount(tTotal.t / nTime),
		tLogSegment:GetTimeString())

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
	local tLogSegment = self:GetLogDisplay()

	if not tLogSegment[mode.segType]
	or not tLogSegment[mode.segType][strPlayerName] then

		gLog:error(string.format("Cannot index mode in segment, name '%s', mode:", strPlayerName))
		gLog:error(mode)

		self.vars.tMode = self:PopMode()
	end

	local tPlayerLog = tLogSegment[mode.segType][strPlayerName]

	-- convert to damageDone/damageTaken
	local dmgTypeTotal = self.tSubTypeFromList[mode.type]

	local nDmgTotal = tPlayerLog[dmgTypeTotal]

	local nTime = tPlayerLog:GetActiveTime()

	--pattern = "%s's Damage to %s",
	local strModePattern = mode.pattern:format(strPlayerName, tLogSegment.name)

	--name = "%s's Damage Done",
	local strModeName = mode.name:format(strPlayerName)

	local nLogTime = tLogSegment:GetCombatLength()

	local tTotal = {
		n = strModeName,
        t = nDmgTotal, -- "Damage to XXX"
        c = GalaxyMeter.kDamageStrToColor.Self,

		-- 1.2M (5.3K)
		tStr = mode.format(nDmgTotal, nTime, nLogTime),
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
			tStr = mode.format(v.total, nTime, nLogTime),
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

	--local strDisplayText = string.format("%s's %s", strPlayerName, mode.type)

	-- Move to Report
	local strTotalText = string.format("%s - %d (%.2f) - %s",
		--"%s's blah on %s"
		strModePattern,
		nDmgTotal,
		nDmgTotal / nTime,
		tLogSegment:GetTimeString())

    return tList, tTotal, strModeName, strTotalText
end


function GalaxyMeter:GetSpellList()

	--strModeType = damageOut
	--strCurrentLogType = damageDone

	local strActorName = self:LogActorName()

	--local tActorLog = self.vars.tLogActor

	--local tPlayerLogSpells = tActorLog[self.vars.strModeType]
	--local tSpell = tPlayerLogSpells[self.vars.strCurrentSpellName]

	local tSpell = self:LogSpell()

	if not tSpell then
		gLog:error("GetSpellList() nil tSpell")

		self.vars.tmode = self:PopMode()

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

	local strTotalText = strDisplayText .. " for " .. Log.entries[Log.nDisplayIdx].name

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

	table.insert(tList, {n = "Time Active", tStr = ("%.1fs"):format(tPlayerLog:GetActiveTime()), click = cFunc})

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

	local strTotalText = strDisplayText .. " for " .. Log.entries[Log.nDisplayIdx].name

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

	local tLogSegment = self:GetLogDisplay()
	local mode = self.vars.tMode
	local nTime = tLogSegment:GetCombatLength()
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
				i, v.n, FormatScaleAmount(v.t), FormatScaleAmount(v.t / nTime), v.t / total * 100))
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
			--wnd.bar:SetText(v.n)
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

	Log.entries = Queue.new()

	self:NewLogSegment()

	Log.nDisplayIdx = Log.entries.last

	local strMode = self.vars.strMainMode

	self.vars = {
		strCurrentLogType = "",
		strCurrentPlayerName = "",
		strCurrentSpellName = "",
		strModeType = "",
		tModeLast = {},
		tMode = self.tModes["Main Menu"],
	}

	if strMode then
		self.vars.strMainMode = strMode
		self:PushMode(self.tModes[strMode])
	end

	self.Children.EncounterText:SetText(self:GetLogDisplay().name)
	self.Children.TimeText:SetText("0.0s")
	self:RefreshDisplay()
end


function GalaxyMeter:OnEncounterDropDown( wndHandler, wndControl, eMouseButton )
	if not self.wndEncList:IsVisible() then

		-- Newest Entry at the Top
		for i = Log.entries.last, Log.entries.first, -1 do
			local wnd = Apollo.LoadForm(self.xmlMainDoc, "EncounterItem", self.Children.EncItemList, self)
			table.insert(self.tEncItems, wnd)

			local log = Log.entries[i]
			
			local TimeString = log:GetTimeString()
			
			wnd:FindChild("Text"):SetText(log.name .. " - " .. TimeString)
			wnd:FindChild("Highlight"):Show(false)
			wnd:SetData(i)
		end
		self.Children.EncItemList:ArrangeChildrenVert()
		self.wndEncList:Show(true)
	else
		self:HideEncounterDropDown()
	end
end


function GalaxyMeter:HideEncounterDropDown()
	self.tEncItems = {}
	self.Children.EncItemList:DestroyChildren()
	self.wndEncList:Show(false)
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

				if v --[[and Log.entries[Log.nDisplayIdx].start > 0--]] and btn == 0 then

					self.vars.strMainMode = k

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
function GalaxyMeter:MenuPlayerSelection(tPlayer)

	local mode = self.vars.tMode

	--self.vars.strCurrentPlayerName = strPlayerName

	self:LogActor(tPlayer)
	self:LogActorName(tPlayer.strName)
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

	self:LogActorId(tActor.id)
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


--[[
-- We got here by clicking the total line in a player spell breakdown
 ]]
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

		gLog:info("OnSave() General")

		tSave.version = GalaxyMeter.nVersion
		tSave.settings = self.settings

		--if self.wndMain then
			tSave.settings.anchor = {self.wndMain:GetAnchorOffsets()}
		--else
		--	tSave.settings.anchor = self.settings.anchor
		--end

		tSave.bActive = self.wndMain:IsVisible()

		-- Deaths module
		tSave.deaths = self.Deaths:OnSave(eType)

	elseif eType == GameLib.CodeEnumAddonSaveLevel.Character then

		gLog:info("OnSave() Character")

		if self.settings.bPersistLogs then
			tSave.tLogData = Log.SerializeLogs()
		end

		tSave.strMainMode = self.vars.strMainMode
	end
	
	return tSave
end


function GalaxyMeter:OnRestore(eType, t)

	if eType == GameLib.CodeEnumAddonSaveLevel.General then

		if not t or not t.version or t.version < GalaxyMeter.nVersion then
			return
		end

		gLog:info("OnRestore() General")

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
		else
			self.settings = GalaxyMeter.tDefaultSettings
		end

		-- Deaths module
		self.Deaths:OnRestore(eType, t.deaths)

	elseif eType == GameLib.CodeEnumAddonSaveLevel.Character then

		gLog:info("OnRestore() Character")

		if t.tLogData then
			gLog:info("  Restoring Logs")

			Log.RestoreLogs(t.tLogData)

			if t.strMainMode then
				self:PushMode(self.tModes[t.strMainMode])
			end

			self.Children.EncounterText:SetText(self:GetLogDisplay().name)
			self.Children.TimeText:SetText(self:GetLogDisplay():GetTimeString())
			self:RefreshDisplay()
		end

	end
end


---------------------------------------------------------------------------------------------------
-- EncounterItem Functions
---------------------------------------------------------------------------------------------------

function GalaxyMeter:OnEncounterItemSelected( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY )
	local logIdx = wndHandler:GetData()

	Log.nDisplayIdx = logIdx
	-- Should we do a sanity check on the current mode? For now just force back to main menu
	self.vars.tMode = self.tModes["Main Menu"]
	self.vars.tModeLast = {}

	gLog:info(string.format("EncounterSelected() logIdx(Data) %d, current %d, display %d",
		logIdx, Log.nCurrentIdx, Log.nDisplayIdx))

	self.Children.EncounterText:SetText(self:GetLogDisplay().name)
	
	self:HideEncounterDropDown()

	-- Right now this only updates in OnTimer, should probably look at the bDirty logic and move it into RefreshDisplay
	self.Children.TimeText:SetText(self:GetLogDisplay():GetTimeString())

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




-----------------------------------------------------------------------------------------------
-- GalaxyMeter Instance
-----------------------------------------------------------------------------------------------
local GalaxyMeterInst = GalaxyMeter:new()
Apollo.RegisterAddon(GalaxyMeterInst, false, "", {"GeminiLogging-1.1"})
