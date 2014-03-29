--
-- Created by IntelliJ IDEA.
-- User: john
-- Date: 3/19/14
-- Time: 4:27 PM
--

local GM = Apollo.GetAddon("GalaxyMeter")
local Deaths = {
	nLogTimeWindow = 10,
	tTypeMapping = {
		[GameLib.CodeEnumDamageType.Physical] 	= Apollo.GetString("DamageType_Physical"),
		[GameLib.CodeEnumDamageType.Tech] 		= Apollo.GetString("DamageType_Tech"),
		[GameLib.CodeEnumDamageType.Magic] 		= Apollo.GetString("DamageType_Magic"),
		[GameLib.CodeEnumDamageType.Fall] 		= Apollo.GetString("DamageType_Fall"),
		[GameLib.CodeEnumDamageType.Suffocate] 	= Apollo.GetString("DamageType_Suffocate"),
		["Unknown"] 							= Apollo.GetString("CombatLog_SpellUnknown"),
		["UnknownDamageType"] 					= Apollo.GetString("CombatLog_SpellUnknown"),
	},
}

function Deaths:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self

	return o
end


function Deaths:Init()


	Apollo.SetConsoleVariable("cmbtlog.disableDelayDeath", false)
	Apollo.SetConsoleVariable("cmbtlog.disableDeath", false)

	--Apollo.RegisterEventHandler("CombatLogAbsorption",				"OnCombatLogAbsorption", self)
	Apollo.RegisterEventHandler("GalaxyMeterLogDamage",				"OnGalaxyMeterLogDamage", self)
	--Apollo.RegisterEventHandler("CombatLogDeath",					"OnCombatLogDeath", self)
	--Apollo.RegisterEventHandler("CombatLogDeflect",					"OnCombatLogDeflect", self)
	--Apollo.RegisterEventHandler("CombatLogDispel",					"OnCombatLogDispel", self)
	--Apollo.RegisterEventHandler("CombatLogDelayDeath",				"OnCombatLogDelayDeath", self)
	--Apollo.RegisterEventHandler("CombatLogFallingDamage",			"OnCombatLogFallingDamage", self)
	Apollo.RegisterEventHandler("GalaxyMetertLogHeal",					"OnGalaxyMeterLogHeal", self)
	--Apollo.RegisterEventHandler("CombatLogImmunity",				"OnCombatLogImmunity", self)


	GM:AddMenu("Player Deaths", {
		name = "Player Deaths",
		pattern = "Player Deaths on %s",
		display = self.GetDeathsList,
		report = GM.ReportGenericList,
		segType = "players",
		type = "deaths",
		prev = GM.MenuPrevious,
		next = self.MenuPlayerDeathSelection,
		sort = function(a,b) return a.t > b.t end,
		format = function(...)
			return GM:FormatAmount(...)
		end
	})

	GM.Log:info("Deaths:Init()")
	GM:Dirty(true)

	--local bDead = tMemberInfo.nHealth == 0 and tMemberInfo.nHealthMax ~= 0

end


--[[
- @param m GalaxyMeter, this was passed in by GetOverallList
--]]
function Deaths:MenuPlayerDeathSelection(tActor)

	if not tActor then
		GM.Log:info("cant find actor in MenuActorSelection")
		return
	end

	local mode = GM:GetCurrentMode()

	--GM:LogActorId(tActor.id)
	--GM:LogActor(tActor)
	--GM:LogType(mode.type)

	GM.Log:info(string.format("MenuPlayerDeathSelection: %s", tActor.strName))


	self:PrintPlayerDeath(tActor)

	--GM:LogModeType(GM.tListFromSubType[mode.type])

	-- Open window

	--local newMode = self.tModeFromSubType[mode.type]

	--GM:PushMode(newMode)

	--GM:Dirty(true)
end



function Deaths:GetDeathsList()
	local tList = {}

	local mode = GM:GetCurrentMode()
	local tLogSegment = GM:GetLogDisplay()
	local tLogActors = tLogSegment[mode.segType]

	local nTotalDeaths = 0

	for k, tActor in pairs(tLogActors) do

		-- Get all deaths for this actor
		local tDeaths = tActor.deaths or {}
		local nDeaths = #tDeaths

		if nDeaths > 0 then

			nTotalDeaths = nTotalDeaths + nDeaths

			table.insert(tList, {
				n = k,
				t = nDeaths,
				tStr = mode.format(nDeaths),
				c = GM.kDamageTypeToColor[2],
				progress = 1,
				click = function(_, btn)
					if btn == 0 and mode.next then
						mode.next(Deaths, tActor)	--> self.MenuPlayerDeathSelection
					elseif btn == 1 then
						mode.prev(GM)
					end
				end
			})
		end
	end

	local tTotal = {
		-- "Deaths on %s"
		n = string.format(mode.pattern, tLogSegment.name),
		t = nTotalDeaths,
		c = GM.kDamageStrToColor.Self,
		tStr = mode.format(nTotalDeaths),
		progress = 1,
	}

	return tList, tTotal, tTotal.n, tTotal.n
end


function Deaths:PrintPlayerDeath(tActor)

	if tActor.deaths then

		local log = tActor.deaths[#tActor.deaths].log

		if log.last < log.first then return end

		local strReportChannel = GM:ReportChannel()

		ChatSystemLib.Command(string.format("/%s Death log for %s:", strReportChannel, tActor.strName))

		for i = log.first, log.last do
			ChatSystemLib.Command(string.format("/%s %s:: %s", strReportChannel, log[i].strTime, log[i].strMessage))
		end
	end
end



function Deaths:PrintPlayerLog(strPlayerName)

	if strPlayerName == nil or strPlayerName == "" then
		return
	end

	local tPlayerLog = GM:GetPlayer(GM:GetLogDisplay().players, {PlayerName=strPlayerName})

	tPlayerLog.log = tPlayerLog.log or GM.Queue.new()

	local log = tPlayerLog.log

	if log.last < log.first then return end

	local strReportChannel = GM:ReportChannel()

	for i = log.first, log.last do
		ChatSystemLib.Command(string.format("/%s %s:: %s", strReportChannel, log[i].strTime, log[i].strMessage))
	end
end


function Deaths:AddLogEntryPlayer(tLogEntry, tPlayer)

	tPlayer.log = tPlayer.log or GM.Queue.new()

	--GM:Rover("tPlayer", {entry=tLogEntry, player=tPlayer, log=tPlayer.log, q=GM.Queue})

	local log = tPlayer.log

	-- Append latest
	GM.Queue.PushRight(tPlayer.log, tLogEntry)

	-- Remove non-recent events
	local nTimeThreshold = tLogEntry.nClockTime - Deaths.nLogTimeWindow

	while tPlayer.log[tPlayer.log.first].nClockTime < nTimeThreshold do
		GM.Queue.PopLeft(tPlayer.log)
	end
end


function Deaths:AddLogEntry(tEvent)

	--GM.Log:info(tEvent)

	-- Create log entry
	local tm = GameLib.GetLocalTime()
	local tNewLogEntry = {
		nClockTime = os.clock(),
		strTime = ("%d:%02d:%02d"):format(tm.nHour, tm.nMinute, tm.nSecond),
		strMessage = tEvent.strResult,
	}

	--GM.Log:info(tNewLogEntry)

	if tEvent.bCasterIsPlayer then
		local tActorLog = GM:GetPlayer(GM:GetLog().players, {PlayerName=tEvent.strCaster})

		self:AddLogEntryPlayer(tNewLogEntry, tActorLog)
	end

	if tEvent.bTargetIsPlayer and tEvent.unitCaster:GetId() ~= tEvent.unitTarget:GetId() then
		local tActorLog = GM:GetPlayer(GM:GetLog().players, {PlayerName=tEvent.strTarget})

		self:AddLogEntryPlayer(tNewLogEntry, tActorLog)
	end

end

-----------------------------------------------------------------------------------------------
-- Combat Log Events
-----------------------------------------------------------------------------------------------

function Deaths:OnCombatLogAbsorption(tEventArgs)
	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.strCaster, tCastInfo.strSpellName, tCastInfo.strTarget)
	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_GrantAbsorption"), tCastInfo.strResult, tEventArgs.nAmount)

	if tEventArgs.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
		--self:PostOnChannel("Absorption")
		tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), tCastInfo.strResult)
	end

	self:AddLogEntry(tCastInfo)
end


function Deaths:OnCombatLogDelayDeath(tEventArgs)
	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, false, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_NotDeadYet"), tCastInfo.strCaster, tCastInfo.strSpellName)

	self:AddLogEntry(tCastInfo)
end


function Deaths:AddPlayerDeath(unitPlayer)

	if unitPlayer:IsACharacter() then

		local strName = unitPlayer:GetName()

		local tPlayerLog = GM:GetPlayer(GM:GetLog().players, {PlayerName=strName})

		if tPlayerLog.log then

			tPlayerLog.deaths = tPlayerLog.deaths or {}

			GM.Log:info(tPlayerLog.strName .. " death")

			local tCopy = GM.Queue.copy(tPlayerLog.log)

			table.insert(tPlayerLog.deaths, {
				time = os.clock(),
				log = tCopy,
			})
		else
			GM.Log:warn(strName .. " died without entries in combat log!")
		end

	else
		GM.Log:warn("unitPlayer not a player!")
	end
end


-- This seems to only be returning the player
function Deaths:OnCombatLogDeath(tEventArgs)
	if GM:Debug() then
		GM.Log:info("OnCombatLogDeath()")
		GM.Log:info(tEventArgs)
		GM:Rover("CLDeath", tEventArgs)
	end

	if not tEventArgs.unitCaster then return end

	self:AddPlayerDeath(tEventArgs)
end


function Deaths:OnGalaxyMeterLogDamage(tEvent)
	-- Example Combat Log Message: 17:18: Alvin uses Mind Stab on Space Pirate for 250 Magic damage (Critical).

	-- System treats environment damage as coming from the player
	local bEnvironmentDmg = tEvent.strCaster == tEvent.strTarget

	local strDamage = tostring(tEvent.nDamage)

	if tEvent.unitTarget and tEvent.unitTarget:IsMounted() then
		tEvent.strTarget = String_GetWeaselString(Apollo.GetString("CombatLog_MountedTarget"), tEvent.strTarget)
	end

	tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tEvent.strCaster, tEvent.strSpellName, tEvent.strTarget)

	if bEnvironmentDmg then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_EnvironmentDmg"), tEvent.strSpellName, tEvent.strTarget)
	end

	local strDamageType = Apollo.GetString("CombatLog_UnknownDamageType")
	if tEvent.eDamageType then
		strDamageType = Deaths.tTypeMapping[tEvent.eDamageType]
	end

	local strDamageMethod = nil
	if tEvent.bPeriodic then
		strDamageMethod = Apollo.GetString("CombatLog_PeriodicDamage")
	elseif tEvent.eEffectType == Spell.CodeEnumSpellEffectType.DistanceDependentDamage then
		strDamageMethod = Apollo.GetString("CombatLog_DistanceDependent")
	elseif tEvent.eEffectType == Spell.CodeEnumSpellEffectType.DistributedDamage then
		strDamageMethod = Apollo.GetString("CombatLog_DistributedDamage")
	else
		strDamageMethod = Apollo.GetString("CombatLog_BaseDamage")
	end

	if strDamageMethod then
		tEvent.strResult = String_GetWeaselString(strDamageMethod, tEvent.strResult, strDamage, strDamageType)
	end

	if tEvent.nShield and tEvent.nShield > 0 then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageShielded"), tEvent.strResult, tostring(tEvent.nShield))
	end

	if tEvent.nAbsorption and tEvent.nAbsorption > 0 then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageAbsorbed"), tEvent.strResult, tostring(tEvent.nAbsorption))
	end

	if tEvent.nOverkill and tEvent.nOverkill > 0 then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageOverkill"), tEvent.strResult, tostring(tEvent.nOverkill))
	end

	if tEvent.bTargetVulnerable then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageVulnerable"), tEvent.strResult)
	end

	if tEvent.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), tEvent.strResult)
	end

	self:AddLogEntry(tEvent)

	if tEvent.bTargetKilled then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_TargetKilled"), tEvent.strCaster, tEvent.strTarget)
		self:AddLogEntry(tEvent)

		if tEvent.unitTarget:IsACharacter() then
			self:AddPlayerDeath(tEvent.unitTarget)
		end
	end

end


function Deaths:OnCombatLogFallingDamage(tEventArgs)

	-- Example Combat Log Message: 17:18: Alvin suffers 246 falling damage
	tEventArgs.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_FallingDamage"), tEventArgs.nDamageAmount)

	self:AddLogEntry(tEventArgs)
end


function Deaths:OnGalaxyMeterLogHeal(tEvent)

	tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tEvent.strCaster, tEvent.strSpellName, tEvent.strTarget)

	local strHealType = ""
	if tEvent.eEffectType == Spell.CodeEnumSpellEffectType.HealShields then
		strHealType = Apollo.GetString("CombatLog_HealShield")
	else
		strHealType = Apollo.GetString("CombatLog_HealHealth")
	end
	tEvent.strResult = String_GetWeaselString(strHealType, tEvent.strResult, tostring(tEvent.nHealAmount))

	if tEvent.nOverheal and tEvent.nOverheal > 0 then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Overheal"), tEvent.strResult, tostring(tEvent.nOverheal))
	end

	if tEvent.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), tEvent.strResult)
	end

	self:AddLogEntry(tEvent)
end


function Deaths:OnCombatLogDeflect(tEvent)

	tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tEvent.strCaster, tEvent.strSpellName, tEvent.strTarget)
	tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Deflect"), tEvent.strResult)

	self:AddLogEntry(tEvent)
end


function Deaths:OnCombatLogImmunity(tEventArgs)
	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.strCaster, tCastInfo.strSpellName, tCastInfo.strTarget)
	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Immune"), tCastInfo.strResult)

	self:AddLogEntry(tCastInfo)
end


function Deaths:OnCombatLogDispel(tEventArgs)
	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.strCaster, tCastInfo.strSpellName, tCastInfo.strTarget)

	local strAppend = Apollo.GetString("CombatLog_DispelSingle")
	if tEventArgs.bRemovesSingleInstance then
		strAppend = Apollo.GetString("CombatLog_DispelMultiple")
	end

	local tSpellCount = {
		["name"] = Apollo.GetString("CombatLog_SpellUnknown"),
		["count"] = tEventArgs.nInstancesRemoved
	}

	local strArgRemovedSpellName = tEventArgs.splRemovedSpell:GetName()
	if strArgRemovedSpellName and strArgRemovedSpellName ~= "" then
		tSpellCount["name"] = strArgRemovedSpellName
	end

	tCastInfo.strResult = String_GetWeaselString(strAppend, tCastInfo.strResult, tSpellCount)

	self:AddLogEntry(tCastInfo)
end


GM.Deaths = Deaths:new()