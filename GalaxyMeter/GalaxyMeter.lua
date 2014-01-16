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
local kDamageToColor = {
	["Self"] 					= CColor.new(1, .75, 0, 1),
	["DamageType_Physical"] 	= CColor.new(1, .5, 0, 1),
	["DamageType_Tech"]			= CColor.new(.6, 0, 1, 1),
	["DamageType_Magic"]		= CColor.new(0, 0, 1, 1),
	["DamageType_Healing"]		= CColor.new(0, 1, 0, 1),
	["DamageType_Fall"]			= CColor.new(.5, .5, .5, 1),
	["DamageType_Suffocate"]	= CColor.new(.3, 0, 1, 1),
	["DamageType_Unknown"]		= CColor.new(.5, .5, .5, 1),
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


-- From: http://lua-users.org/wiki/SplitJoin
-- Compatibility: Lua-5.1
function GalaxyMeter:string_split(p,d)
	local t, ll
	t={}
	ll=0
	if(#p == 1) then return {p} end
    while true do
		l=string.find(p,d,ll,true) -- find the next d in the string
		if l~=nil then -- if "not not" found then..
			table.insert(t, string.sub(p,ll,l-1)) -- Save it in our array.
			ll=l+1 -- save just after where we found it for searching next time.
		else
			table.insert(t, string.sub(p,ll)) -- Save what's left in our array.
			break -- Break at end, as it should be, according to the lua manual.
		end
    end
	return t
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
	    Apollo.RegisterSlashCommand("galmet",							"OnGalaxyMeterOn", self)
	
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
		Apollo.StartTimer("PlayerCheckTimer")
		
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
            {   name = "Overall Damage Done",       -- Display name
                pattern = "Damage on %s",           --
                display = self.GetListOverall,
                report = self.ReportOverallList,
                type = "damageDone"},

            {   name = "Overall Damage Taken",
                pattern = "Damage from %s",
                display = self.GetListOverall,
                report = self.ReportOverallList,
                type = "damageTaken"},

            {   name = "Overall Healing Done",
                pattern = "Healing Done on %s",
                display = self.GetListOverall,
                report = self.ReportOverallList,
                type = "healingDone"},

            {   name = "Overall Healing Taken",
                pattern = "Healing Taken on %s",
                display = self.GetListOverall,
                report = self.ReportOverallList,
                type = "healingTaken"},

            {   name = "%s's Damage Done",
                pattern = "%s's Damage to %s",
                display = self.GetPlayerList,
                report = self.ReportPlayerList,
                type = "damageOut"},

            {   name = "%s's Damage Taken",
                pattern = "%s's Damage Taken from %s",
                display = self.GetPlayerList,
                report = self.ReportPlayerList,
                type = "damageIn"},

            {   name = "%s's Healing Done",
                pattern = "%s's Healing Done on %s",
                display = self.GetPlayerList,
                reporty = self.ReportPlayerList,
                type = "healingOut"},

            {   name = "%s's Healing Taken",
                pattern = "%s's Healing Taken on %s",
                display = self.GetPlayerList,
                report = self.ReportPlayerList,
                type = "healingIn"},
        }


        self.vars = {
            -- modes
            nModeIndex = 5,
            tMode = self.tModes[5],   -- Default to player damage done
            nLogIndex = 0,
            tLogDisplay = nil, -- Log currently displayed
            strLogPlayer = GameLib.GetPlayerUnit():GetName(),     -- Current player log being displayed, default to yourself
            bGrouped = false,
        }

        -- Combat Log

        self:NewLogSegment()


		gLog:info("OnLoad finished")
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
	--else
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
	
	--if self.tCurrentLog == nil then return end
	
	self.tCurrentLog.combat_length = os.clock() - self.tCurrentLog.start

	if self.vars.logdisplay == self.tCurrentLog then
		self.Children.TimeText:SetText("Timer: " .. self:SecondsToString(self.tCurrentLog.combat_length))
		
		self:DisplayUpdate()
    else
        gLog:info("logdisplay: " .. tostring(self.vars.logdisplay))
        gLog:info("tCurrentLog: " .. tostring(self.tCurrentLog))
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
	-- Start new log segment if someone is in combat and we're not, or vice versa
	--if (groupInCombat and not self.bInCombat) or (not groupInCombat and self.bInCombat) then
		
		gLog:info("StartLogSegment()")

        self.tCurrentLog.start = os.clock()

		--self.tCurrentLog = {
		--	start = os.clock(),
		--	combat_length = 0,
        --    name = "",          -- Segment name
		--	["players"] = {},   -- Array containing players involved in this segment
		--	["mobs"] = {},      -- Array containing mobs involved in this segment
		--}

		Apollo.StartTimer("CombatTimer")
		
		--[[
		if not self.wndMain:IsVisible() then
			self:RestoreWindowPosition()
		
    		self.wndMain:Show(true)
		else
			-- Set Focus if at last position
			if self.vars.logindex == self.vars.logdisplay + 1 then
				self.vars.logdisplay = self.vars.logindex
				self.Children.EncounterButton:SetText(Target)
				self:ResetDisplayOrder()
			end
		end
		--]]
	--else	
	--	Apollo.StopTimer("CombatTimer")
	--end
end


function GalaxyMeter:NewLogSegment()
    -- Push a new log entry to the top of the history stack
    local log = {
        start = 0,
        combat_length = 0,
        name = "",          -- Segment name
        ["players"] = {},   -- Array containing players involved in this segment
        ["mobs"] = {},      -- Array containing mobs involved in this segment
    }

    if self.log then
        table.insert(self.log, 1, log)
    else
        self.log = {}
        table.insert(self.log, log)
    end

    self.tCurrentLog = self.log[1]

    if self.vars.nLogIndex == 0 then
        -- If we were looking at the previous current log, set logdisplay to the new one
        self.vars.tLogDisplay = self.tCurrentLog
    else
        self.vars.nLogIndex = self.vars.nLogIndex + 1
        self.vars.tLogDisplay = self.log[self.vars.nLogIndex]
    end

    self:Rover("NewLogSegment: vars", self.vars)
end


function GalaxyMeter:PushLogSegment()
	gLog:info("Pushing log segment")

    self:Rover("lastLog", self.tCurrentLog)
    self:Rover("log", self.log)

    -- Pop off oldest, TODO Add config option to keep N old logs
    if #self.log >= 50 then
        table.remove(self.log)
    end

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
end

-----------------------------------------------------------------------------------------------
-- Channel Manager Functions
-----------------------------------------------------------------------------------------------
function GalaxyMeter:SetGroupLogChannel(GroupLeader)
	--Simple preventation to keep users from 'bumping' into the channel
	--self.ChannelName = string.format("GalMet_%s_%s", GroupLeader, string.reverse(GroupLeader))
	
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
	
	self.vars.grouped = true
	self:SetGroupLogChannel(GroupLeader)
end


function GalaxyMeter:OnGroupLeft()
	self.vars.grouped = false
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
	return self.vars.logdisplay
end


-- @return LogDisplayPlayerId, or nil
function GalaxyMeter:GetLogDisplayPlayerId()
	return self.vars.logdisplay.playerid
end


-- @return LogDisplayTimer, or nil
function GalaxyMeter:GetLogDisplayTimer()
	return self.vars.logdisplay.combat_length
end


function GalaxyMeter:SetLogTitle(title)
	if self.tCurrentLog.name == "" then
		self.tCurrentLog.name = title
		if self.tCurrentLog == self.vars.logdisplay then
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



function GalaxyMeter:OnAttackMissed(unitCaster, unitTarget, eMissType, strArgSpellName)
	if not self.bInCombat then return nil end
	
	local strSpellName = "Unknown" if strArgSpellName and string.len(strArgSpellName) > 0 then strSpellName = strArgSpellName end

	local CombatEvent = self:NewCombatEvent(unitCaster, unitTarget, eMissType, 0, strSpellName)
	
	self:UpdateDamageSpell(CombatEvent)
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
	if not self.bInCombat then return nil end

    -- TODO Move this into NewCombatEvent
    local strSpellName = "Unknown" if strArgSpellName and string.len(strArgSpellName) > 0 then strSpellName = strArgSpellName end

    local event = self:NewCombatEvent(unitCaster, unitTarget, 0, eDamageType, strSpellName, nDamage, nShieldAbsorbed, nAbsorptionAmount, bCritical)

    -- Determine the spell TypeId, still need unitTarget and unitCaster for that
    if self:IsHealEvent(event.DamageType) then

        event.TypeId = self:GetHealEventType(unitCaster, unitTarget)

    else

        -- Check if incoming dmg on pet or self for now, which we aren't tracking yet
        if not self:ShouldThrowAwayDamageEvent(unitCaster, unitTarget) then
            event.TypeId = self:GetDamageEventType(unitCaster, unitTarget)
        end

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
function GalaxyMeter:FindPlayer(tLog, playerName)
    return tLog[playerName]
end


-- Find or create player data table
-- @return Player data table
-- TODO Why do I pass in tEvent here instead of strPlayerName?
function GalaxyMeter:GetPlayer(tLog, tEvent)

    local playerName = tEvent.PlayerName

    gLog:info(string.format("GetPlayer(tLog, %s)", playerName))

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
end


function GalaxyMeter:UpdatePlayerSpell(tEvent)
    local CasterId = tEvent.CasterId
    local spellName = tEvent.SpellName
    local casterType = tEvent.CasterType
    local nAmount = tEvent.Damage
    local activeLog = nil

    if (casterType == "Player" or casterType == "Pet") then
        -- Caster is a player or pet
        activeLog = self.tCurrentLog["players"]
    else
        -- I guess it's a mob?
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

        local spellOut = self:GetSpell(player.healingOut, spellName)
        local spellIn = self:GetSpell(player.healingIn, spellName)

        self:TallySpellAmount(tEvent, spellOut)
        self:TallySpellAmount(tEvent, spellIn)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingOut then
        player.healingDone = player.healingDone + nAmount
        spell = self:GetSpell(player.healingOut, spellName)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingIn then
        player.healingTaken = player.healingTaken + nAmount
        spell = self:GetSpell(player.healingIn, spellName)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageInOut then

        -- Another special case where the spell we cast also damaged ourself?

        player.damageDone = player.damageDone + nAmount
        player.damageTaken = player.damageTaken + nAmount

        local spellOut = self:GetSpell(player.damageOut, spellName)
        local spellIn = self:GetSpell(player.damageIn, spellName)

        self:TallySpellAmount(tEvent, spellOut)
        self:TallySpellAmount(tEvent, spellIn)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerDamageOut then
        player.damageDone = player.damageDone + nAmount
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

--[[
function GalaxyMeter:UpdateHealingSpell(tEvent)
    local CasterId = tEvent.CasterId
    local spellName = tEvent.SpellName
    local casterType = tEvent.CasterType
    local nAmount = tEvent.Damage


    local activeLog = nil

    if (casterType == "Player" or casterType == "Pet") then
        -- Caster is a player or pet
        activeLog = self.tCurrentLog["players"]
    else
        -- I guess it's a mob?
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

    -- Break into healing done/received handling
    local spell = nil

    -- Player tally and spell type
    if tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingInOut then

        -- Special handling for self healing, we want to count this as both healing done and received
        -- Maybe add option to enable tracking for this

        player.healingDone = player.healingDone + nAmount
        player.healingTaken = player.healingTaken + nAmount

        local spellOut = self:GetSpell(player.healingOut, spellName)
        local spellIn = self:GetSpell(player.healingIn, spellName)

        self:TallySpellAmount(spellOut, nAmount)
        self:TallySpellAmount(spellIn, nAmount)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingOut then
        player.healingDone = player.healingDone + nAmount
        spell = self:GetSpell(player.healingOut, spellName)

    elseif tEvent.TypeId == eTypeDamageOrHealing.PlayerHealingIn then
        player.healingTaken = player.healingTaken + nAmount
        spell = self:GetSpell(player.healingIn, spellName)

    else
        gLog:fatal(string.format("Unknown heal type %d in UpdateHealingSpell!", tEvent.TypeId))
        gLog:fatal(string.format("Spell: %s, Caster: %s, Target: %s, Amount: %d",
                                spellName, CasterId, tEvent.Target, nAmount))
    end

    if spell then
        self:TallySpellAmount(spell, nAmount)
    end
end

function GalaxyMeter:UpdateDamageSpell(tEvent)
	local CasterId = tEvent.CasterId
	local spellName = tEvent.SpellName
    local casterType = tEvent.CasterType
	local activeLog = nil
	

    if (casterType == "Player" or casterType == "Pet") then
        -- Caster is a player or pet
        activeLog = self.tCurrentLog["players"]
    else
        -- I guess it's a mob?
        -- If we got here after already attempting to not pay attention to incoming damage, then I need to fix this
        --Log = self.tCurrentLog["mobs"]
        gLog:warn(string.format("Unknown caster type '%s', going to fail... Id: %s, Spell: %s", casterType, CasterId, spellName))
    end

    if not activeLog then
        gLog:fatal("Nil log after checking casterType: " .. casterType)
        return
    end


    local nDamage = tEvent.Damage

    -- Have seen a problem here using an Engineer where nDamage is nil, debug
    if nDamage == nil then
        self:Rover("EngError CombatEvent", tEvent)
        return
    end

    -- Finds existing or creates new player entry
    -- Make sure CombatEvent.classid is properly set to the player if their pet used a spell!!!
    local player = self:GetPlayer(activeLog, tEvent)

    -- Player total damage
    player.damageDone = player.damageDone + nDamage

    -- Finds existing or create new spell entry
    local spell = self:GetSpell(player.damageOut, spellName)

    self:TallySpellAmount(tEvent, spell)
end
--]]


function GalaxyMeter:CompareDisplay(Index, Text)
	if not self.DisplayOrder[Index] or ( self.DisplayOrder[Index] and self.DisplayOrder[Index] ~= Text ) then
		self.DisplayOrder[Index] = Text
		return true
	end
end



-----------------------------------------------------------------------------------------------
-- List Generators
--
-- These are pretty similar... Consider consolidating them into a more generic method
-----------------------------------------------------------------------------------------------

-- @param tLogSegment Log entry currently being displayed
-- @param type Segment subtype, healingIn/Out etc
function GalaxyMeter:GetOverallList(tLogSegment, subType)

    local tList = {}

    for k,v in pairs(tLogSegment.players) do
        table.insert(tList, {
            n = k,
            t = v[subType],
            c = self.ClassToColor[v.classId],
        })
    end

    return tList, nil
end


-- Get player listing for this segment
-- @param tLogSegment Log segment of interest
-- @param subType Dmg/Healing In/Out etc
-- @param strModeName
-- @param playerName
-- @return Tables containing player damage done
--    1) Ordered list of individual spells
--    2) Total
function GalaxyMeter:GetPlayerList(tLogSegment, subType, strModeName, playerName)
    local tList = {}

    local tTotal = {
        n = strModeName,
        --n = tPlayerLog.playerName .. "'s Total Damage",
        t = tLogSegment.players[playerName].damageDone,
        c = kDamageToColor.Self
    }

    for k,v in pairs(tLogSegment.players[playerName][subType]) do
        table.insert(tList, {
            n = k,
            t = v.total,
            c = kHostilityToColor[3]
        })
    end

    return tList, tTotal
end

--[[
-- @param tLogSegment Log entry currently being displayed
function GalaxyMeter:DisplayPlayerList(tLogSegment, strModeName, type)

    -- This should be safe if the above is there
    local PlayerId = self.PlayerName

    if self.wndMain:IsVisible() and tLogSegment.players[PlayerId] then

        local tPlayerList = self:GetPlayerList(tLogSegment.players[PlayerId], type)

        self:DisplayList(tPlayerList)
    end
end

-- @param tLogSegment Log entry currently being displayed
function GalaxyMeter:DisplayOverallList(tLogSegment, type)
    --if self.wndMain:IsVisible() then

        return self:GetOverallList(tLogSegment, type)

        --self:DisplayList(tPlayerList)
    --end
end
--]]


-----------------------------------------------------------------------------------------------
-- Report Generators
-----------------------------------------------------------------------------------------------

-- Entry point from Report UI button
-- Report current log to X channel
function GalaxyMeter:OnReport( wndHandler, wndControl, eMouseButton )

    local mode = self.vars.mode

    local tLogSegment = self:GetLogDisplay()
    --[[
    if not tLogSegment then

        -- When reporting, combat has -usually- stopped, so if logdisplay = 0 then
        -- currentlog will have already been pushed, so we should index log[1], which would
        -- have been the previous
        if self.vars.logdisplay == 0 and self.log[1] then
            tLogSegment = self.log[1]
        else
            gLog:warn("nil log in OnReport, display index: " .. self.vars.logdisplay)
        end
    end
    --]]


    if self.bDebug then
        self:Rover("vars: OnReport", self.vars)

        if self.vars.logplayer == "" then
            gLog:fatal("OnReport: vars.logplayer not set")
            return
        end

        if not tLogSegment.players[self.vars.logplayer] then
            gLog:fatal(string.format("OnReport: tLogSegment.players[%s] is nil", self.vars.logplayer))
            return
        end
    end

    -- TODO: Properly detect whos report we're looking at
    local tPlayerLog = tLogSegment.players[self.vars.logplayer]

    self:Rover("tPlayerLog: OnReport", tPlayerLog)

    -- We don't really want the mode name here.. need to pass in the report type

    -- Calls ReportOverallList, ReportPlayerList, etc
    local tReportStrings = mode.report(self, tLogSegment, mode.type, tPlayerLog.playerName)

    -- Report to guild, eventually this will be configurable
    for i=1,#tReportStrings do
        ChatSystemLib.Command("/g " .. tReportStrings[i])
    end

end

--[[
-- @param tLog Log entry pertaining to segment of interest
function GalaxyMeter:BuildPlayerReport(tLog, strPlayerName, Listing)
    table.sort(Listing, function(a,b) return a.t > b.t end)

    local total = 0
    local tStrings = {}

    local combatLength = tLog.combat_length

    for i=1,#Listing do
        local v = Listing[i]
        if i == 1 then
            total = v.t
        else
            table.insert(tStrings, string.format("%d) %s - %s (%.2f)  %.2f%%",
                i - 1, v.n, v.t, v.t / combatLength, v.t / total * 100))
        end
    end


    table.insert(tStrings, 1, string.format("%s's %s on %s - %d (%.2f) - %s",
        strPlayerName,
        tReportTypes[self.vars.mode],
        tLog.name,  --
        total,
        total / combatLength,
        self:SecondsToString(combatLength)))

    return tStrings
end
--]]


-- @param tLogSegment Log segment pertaining to the SEGMENT of interest
-- @param subType Damage In or Out
-- @param strModeName
-- @param strPlayerName Player of interest in the log segment
function GalaxyMeter:ReportPlayerList(tLogSegment, subType, strModeName, strPlayerName)

    -- Here we should:
    -- 1) Get log entry pertaining to the player of interest
    -- 2) Build report strings
    -- 3) Return strings to the report handler

    local tPlayerLog = tLogSegment.players[strPlayerName]

    local tPlayerList = self:GetPlayerList(tPlayerLog, subType)

    table.sort(tPlayerList, function(a,b) return a.t > b.t end)

    local combatLength = tLogSegment.combat_length
    local tStrings = {}
    local total = tPlayerList[1].t

    table.insert(tStrings, string.format("%s on %s - %d (%.2f) - %s",
        --"%s's blah on %s"
        string.format(self.vars.mode.pattern, strPlayerName, self.vars.mode.name, tLogSegment.name),
        --strPlayerName,
        --tReportTypes[self.vars.mode],
        --tLogSegment.name,  --
        total,
        total / combatLength,
        self:SecondsToString(combatLength)))

    for i=1,#tPlayerList do
        local v = tPlayerList[i]
        table.insert(tStrings, string.format("%d) %s - %s (%.2f)  %.2f%%",
            i, v.n, v.t, v.t / combatLength, v.t / total * 100))
    end

    return tStrings
end


function GalaxyMeter:ReportOverallList(tLogSegment, subType, strModeName, strPlayerName)
    local tPlayerList = self:GetOverallList(tLogSegment, subType)

    table.sort(tPlayerList, function(a,b) return a.t > b.t end)

    local combatLength = tLogSegment.combat_length
    local tStrings = {}

    -- Get total
    local total = 0
    for i=1,#tPlayerList do
        total = total + tPlayerList[i].t
    end

    table.insert(tStrings, string.format("%s - %d (%.2f) - %s",
        string.format(self.vars.mode.pattern, tLogSegment.name),
        total,
        total / combatLength,
        self:SecondsToString(combatLength)))

    for i=1,#tPlayerList do
        local v = tPlayerList[i]
        table.insert(tStrings, string.format("%d) %s - %s (%.2f)  %.2f%%",
            i, v.n, v.t, v.t / combatLength, v.t / total * 100))
    end

    return tStrings
end


-- Main list display function, this will assemble list items and draw them to the window
-- TODO Maybe combine this with Get*List or something to avoid to much looping? Also we call GetLogDisplayTimer
function GalaxyMeter:DisplayList(Listing)
	--table.sort(Listing, function(a,b) return a.t > b.t end)

	local Arrange = false
	for k,v in ipairs(Listing) do		
		if not self.tItems[k] then
			self:AddItem(k)
		end
		local wnd = self.tItems[k]
		if self:CompareDisplay(k, v.n) then
			wnd.left_text:SetText(v.n)
			wnd.bar:SetBarColor(v.c)
			Arrange = true
		end		
		wnd.right_text:SetText(string.format("%s (%.2f)", v.t, v.t / self:GetLogDisplayTimer()))
		wnd.bar:SetProgress(v.t / Listing[1].t)
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

    local tLogSegment = self:GetLogDisplay()

    if not tLogSegment then
        gLog:warn("nil Log in DisplayUpdate")
        return
    end

    local mode = self.vars.mode

    if self.bDebug then

        self:Rover("vars", self.vars)

        if self.vars.logplayer == "" then
            gLog:fatal("DisplayUpdate: vars.logplayer not defined")
            return
        end

        if not tLogSegment.players[self.vars.logplayer] then
            gLog:fatal(string.format("DisplayUpdate: log.players[%s] not defined", self.vars.logplayer))
            return
        end

    end


    -- Format the 'total' line
    -- If its an overall list we want it to say "Overall Damage Done" etc
    -- If its a player list it should say "Player's Damage Done on Whatever"

    local strPlayerName = tLogSegment.players[self.vars.logplayer].name

    if not strPlayerName or strPlayerName == "" then
        strPlayerName = self.PlayerName
    end

    local displayText = string.format(mode.pattern, strPlayerName, tLogSegment.name)

    --n = string.format(strModePattern, tPlayerLog.playerName),

    -- Text below the meter
    self.Children.DisplayText:SetText(mode.name)

    --

    -- Calls GetOverallList(tLogSegment, subType), GetPlayerList(tLogSegment, subType, strModeName, strPlayerName)
    local tList, tTotal = mode.display(self, tLogSegment, mode.type, displayText, strPlayerName)

    --if option to show totals
    if tTotal ~= nil then
        table.insert(tList, 1, tTotal)
    end

    table.sort(tList, function(a,b) return a.t > b.t end)

    self:Rover("DisplayUpdate: tList", tList)

    self:DisplayList(tList)
end


function GalaxyMeter:ResetDisplayOrder()
	self.DisplayOrder = {}
end


function GalaxyMeter:RefreshDisplay()
    self:ResetDisplayOrder()
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
	self.vars.logindex = 0
	self.vars.logdisplay = 0
    self.vars.logplayer = ""
	self:RefreshDisplay()
end


function GalaxyMeter:OnModeLeft( wndHandler, wndControl, eMouseButton )
	self.vars.modeIndex = self.vars.modeIndex - 1
	if self.vars.modeIndex < 1 then
		self.vars.modeIndex = #self.tModes
    end

    self.vars.mode = #self.tModes[self.vars.modeIndex]
	
	self:Rover("vars", self.vars)
	
	self:RefreshDisplay()
end


function GalaxyMeter:OnModeRight( wndHandler, wndControl, eMouseButton )
	self.vars.modeIndex = self.vars.modeIndex + 1
	if self.vars.modeIndex > #self.tModes then
		self.vars.modeIndex = 1
    end

    self.vars.mode = #self.tModes[self.vars.modeIndex]
	
	self:Rover("vars", self.vars)
	
	self:RefreshDisplay()
end


function GalaxyMeter:OnEncounterDropDown( wndHandler, wndControl, eMouseButton )
	if not self.wndEncList:IsVisible() then
		self.wndEncList:Show(true)
		
		-- Newest Entry at the Top
		for i=#self.log, 1, -1 do
			local wnd = Apollo.LoadForm("GalaxyMeter.xml", "EncounterItem", self.Children.EncItemList, self)
			table.insert(self.tEncItems, wnd)
			
			local TimeString = self:SecondsToString(self.log[i].combat_length)
			
			wnd:FindChild("Text"):SetText(self.log[i].id .. " - " .. TimeString)
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
	self.tItems[i].bar = wnd:FindChild("PercentBar")
	self.tItems[i].left_text = wnd:FindChild("LeftText")
	self.tItems[i].right_text = wnd:FindChild("RightText")	

	self.tItems[i].bar:SetMax(1)
	self.tItems[i].bar:SetProgress(0)
	self.tItems[i].left_text:SetTextColor(kcrNormalText)
	--end
	wnd:SetData(i)
	
	return self.tItems[i]
end

-- when a list item is selected
function GalaxyMeter:OnListItemSelected(wndHandler, wndControl)
    -- make sure the wndControl is valid
    if wndHandler ~= wndControl then
        return
    end
    
    -- change the old item's text color back to normal color
    local wndItemText
    if self.wndSelectedListItem ~= nil then
        wndItemText = self.wndSelectedListItem:FindChild("LeftText")
        wndItemText:SetTextColor(kcrNormalText)
    end
    
	-- wndControl is the item selected - change its color to selected
	self.wndSelectedListItem = wndControl
	wndItemText = self.wndSelectedListItem:FindChild("LeftText")
    wndItemText:SetTextColor(kcrSelectedText)
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
	self.logdisplay = wndHandler:GetData()
	self.Children.EncounterButton:SetText(self.log[self.logdisplay].id)
	self.Children.TimeText:SetText("Timer: "..self:SecondsToString(self.log[self.logdisplay].combat_length))
	
	self:HideEncounterDropDown()
	
	self:RefreshDisplay()
end

function GalaxyMeter:OnEncounterItemMouseEnter( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(true)
end

function GalaxyMeter:OnEncounterItemMouseExit( wndHandler, wndControl, x, y )
	wndHandler:FindChild("Highlight"):Show(false)
end

---------------------------------------------------------------------------------------------------
-- ListItem Functions
---------------------------------------------------------------------------------------------------

function GalaxyMeter:OnListItemMouseEnter( wndHandler, wndControl, x, y )
	--gLog:info("OnListItemMouseEnter()")
end

function GalaxyMeter:OnListItemButtonUp( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY )
	--gLog:info("OnListItemButtonUp()")
end

function GalaxyMeter:OnListItemButtonDown( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation )
	--gLog:info("OnListItemButtonDown()")
end

-----------------------------------------------------------------------------------------------
-- GalaxyMeter Instance
-----------------------------------------------------------------------------------------------
local GalaxyMeterInst = GalaxyMeter:new()
GalaxyMeterInst:Init()
