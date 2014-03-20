--
-- Created by IntelliJ IDEA.
-- User: john
-- Date: 3/19/14
-- Time: 4:27 PM
--

local GM = Apollo.GetAddon("GalaxyMeter")
local Queue = GM.Queue
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
	Apollo.RegisterEventHandler("CombatLogAbsorption",				"OnCombatLogAbsorption", self)
	Apollo.RegisterEventHandler("CombatLogDamage",					"OnCombatLogDamage", self)
	Apollo.RegisterEventHandler("CombatLogDeath",					"OnCombatLogDeath", self)
	Apollo.RegisterEventHandler("CombatLogDeflect",					"OnCombatLogDeflect", self)
	Apollo.RegisterEventHandler("CombatLogDispel",					"OnCombatLogDispel", self)
	Apollo.RegisterEventHandler("CombatLogDelayDeath",				"OnCombatLogDelayDeath", self)
	Apollo.RegisterEventHandler("CombatLogFallingDamage",			"OnCombatLogFallingDamage", self)
	Apollo.RegisterEventHandler("CombatLogHeal",					"OnCombatLogHeal", self)
	Apollo.RegisterEventHandler("CombatLogImmunity",				"OnCombatLogImmunity", self)


	GM:AddMenu("Player Deaths", {
		name = "Player Deaths",
		pattern = "Player Deaths on %s",
		display = self.GetDeathsList,
		report = GM.ReportGenericList,
		segType = "players",
		type = "deaths",
		prev = GM.MenuPrevious,
		next = nil,
		sort = function(a,b) return a.t > b.t end,
		format = function(...)
			return GM:FormatAmount(...)
		end
	})

end



function Deaths:GetDeathsList()
	local tList = {}

	local mode = GM:GetCurrentMode()
	local tLogSegment = GM:GetLogDisplay()
	local tLogActors = tLogSegment[mode.segType]

	local nTotalDeaths = 0

	for k, v in pairs(tLogActors) do

		-- Get all deaths for this actor
		local tDeaths = v.deaths or {}
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
						mode.next(GM, k)
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




function Deaths:PrintPlayerDeath()
	-- Find player log
	local strPlayerName = self.vars.strCurrentPlayerName

	if strPlayerName == nil or strPlayerName == "" then
		GM.Log:info("PrintPlayerDeath nil player")
		return
	end

	local tPlayerLog = self:GetPlayer(self.vars.tLogDisplay, {PlayerName=strPlayerName})

	if tPlayerLog.deaths then

		local log = tPlayerLog.deaths[#tPlayerLog.deaths].log

		if log.last < log.first then return end

		for i = log.first, log.last do
			ChatSystemLib.Command(string.format("/2 %s:: %s", log[i].strTime, log[i].strMessage))
		end
	end
end



function Deaths:PrintPlayerLog(strPlayerName)

	if strPlayerName == nil or strPlayerName == "" then
		return
	end

	local tPlayerLog = GM:GetPlayer(GM:GetLogDisplay().players, {PlayerName=strPlayerName})

	tPlayerLog.log = tPlayerLog.log or Queue.new()

	local log = tPlayerLog.log

	if log.last < log.first then return end

	local strReportChannel = GM:ReportChannel()

	for i = log.first, log.last do
		ChatSystemLib.Command(string.format("/%s %s:: %s", strReportChannel, log[i].strTime, log[i].strMessage))
	end
end


function Deaths:AddLogEntryPlayer(tLogEntry, tPlayer)
	tPlayer.log = tPlayer.log or Queue.new()

	local log = tPlayer.log

	-- Append latest
	log:PushRight(tLogEntry)

	-- Remove non-recent events
	local nTimeThreshold = tLogEntry.nClockTime - Deaths.nLogTimeWindow

	while log[log.first].nClockTime < nTimeThreshold do
		log:PopLeft()
	end
end


function Deaths:AddLogEntry(tEvent)

	local nTypeId, bCasterIsPlayer, bTargetIsPlayer = GM:GetDamageEventType(tEvent.unitCaster, tEvent.unitTarget)

	local tActorLog

	if nTypeId == 0 then
		GM.Log:error("AddLogEntry: Something went wrong!  Invalid type Id")
		return
	end

	-- Create log entry
	local tm = GameLib.GetLocalTime()
	local tNewLogEntry = {
		nClockTime = os.clock(),
		strTime = ("%d:%02d:%02d"):format(tm.nHour, tm.nMinute, tm.nSecond),
	}

	if bCasterIsPlayer then
		tActorLog = GM:GetPlayer(GM:GetLog().players, {PlayerName=tEvent.strCaster})

		self:AddLogEntryPlayer(tNewLogEntry, tActorLog)
	end

	if bTargetIsPlayer and tEvent.unitCaster:GetId() ~= tEvent.unitTarget:GetId() then
		tActorLog = GM:GetPlayer(GM:GetLog().players, {PlayerName=tEvent.strTarget})

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


function Deaths:OnCombatLogDeath(tEventArgs)
	if GM:Debug() then
		GM.Log:info("OnCombatLogDeath()")
		GM.Log:info(tEventArgs)
		GM:Rover("CLDeath", tEventArgs)
	end

	if not tEventArgs.unitCaster then return end

	if tEventArgs.unitCaster:IsACharacter() then

		local strName = tEventArgs.unitCaster:GetName()

		local tPlayerLog = GM:GetPlayer(GM:GetCurrentLog().players, {PlayerName=strName})

		if tPlayerLog.log then

			tPlayerLog.deaths = tPlayerLog.deaths or {}

			local tCopy = Queue.copy(tPlayerLog.log)

			table.insert(tPlayerLog.deaths, {
				time = os.clock(),
				log = tCopy,
			})
		else
			GM.Log:warn(strName .. " died without entries in combat log!")
		end

	end
end


function Deaths:OnCombatLogDamage(tEventArgs)
	-- Example Combat Log Message: 17:18: Alvin uses Mind Stab on Space Pirate for 250 Magic damage (Critical).
	local tTextInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tTextInfo then return end

	-- System treats environment damage as coming from the player
	local bEnvironmentDmg = tTextInfo.strCaster == tTextInfo.strTarget

	local strDamage = tEventArgs.nDamageAmount

	if tEventArgs.unitTarget and tEventArgs.unitTarget:IsMounted() then
		tTextInfo.strTarget = String_GetWeaselString(Apollo.GetString("CombatLog_MountedTarget"), tTextInfo.strTarget)
	end

	tTextInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tTextInfo.strCaster, tTextInfo.strSpellName, tTextInfo.strTarget)

	if bEnvironmentDmg then
		tTextInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_EnvironmentDmg"), tTextInfo.strSpellName, tTextInfo.strTarget)
	end

	local strDamageType = Apollo.GetString("CombatLog_UnknownDamageType")
	if tEventArgs.eDamageType then
		strDamageType = Deaths.tTypeMapping[tEventArgs.eDamageType]
	end

	local strDamageMethod = nil
	if tEventArgs.bPeriodic then
		strDamageMethod = Apollo.GetString("CombatLog_PeriodicDamage")
	elseif tEventArgs.eEffectType == Spell.CodeEnumSpellEffectType.DistanceDependentDamage then
		strDamageMethod = Apollo.GetString("CombatLog_DistanceDependent")
	elseif tEventArgs.eEffectType == Spell.CodeEnumSpellEffectType.DistributedDamage then
		strDamageMethod = Apollo.GetString("CombatLog_DistributedDamage")
	else
		strDamageMethod = Apollo.GetString("CombatLog_BaseDamage")
	end

	if strDamageMethod then
		tTextInfo.strResult = String_GetWeaselString(strDamageMethod, tTextInfo.strResult, strDamage, strDamageType)
	end

	if tEventArgs.nShield and tEventArgs.nShield > 0 then
		tTextInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageShielded"), tTextInfo.strResult, tEventArgs.nShield)
	end

	if tEventArgs.nAbsorption and tEventArgs.nAbsorption > 0 then
		tTextInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageAbsorbed"), tTextInfo.strResult, tEventArgs.nAbsorption)
	end

	if tEventArgs.nOverkill and tEventArgs.nOverkill > 0 then
		tTextInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageOverkill"), tTextInfo.strResult, tEventArgs.nOverkill)
	end

	if tEventArgs.bTargetVulnerable then
		tTextInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageVulnerable"), tTextInfo.strResult)
	end

	if tEventArgs.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
		tTextInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), tTextInfo.strResult)
	end

	self:AddLogEntry(tTextInfo)

	if tEventArgs.bTargetKilled then
		tEventArgs.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_TargetKilled"), tTextInfo.strCaster, tTextInfo.strTarget)
		self:AddLogEntry(tTextInfo)
	end

end


function Deaths:OnCombatLogFallingDamage(tEventArgs)

	-- Example Combat Log Message: 17:18: Alvin suffers 246 falling damage
	tEventArgs.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_FallingDamage"), tEventArgs.nDamageAmount)

	self:AddLogEntry(tEventArgs)
end


function Deaths:OnCombatLogHeal(tEventArgs)

	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.strCaster, tCastInfo.strSpellName, tCastInfo.strTarget)

	local strHealType = ""
	if tEventArgs.eEffectType == Spell.CodeEnumSpellEffectType.HealShields then
		strHealType = Apollo.GetString("CombatLog_HealShield")
	else
		strHealType = Apollo.GetString("CombatLog_HealHealth")
	end
	tCastInfo.strResult = String_GetWeaselString(strHealType, tCastInfo.strResult, tEventArgs.nHealAmount)

	if tEventArgs.nOverheal and tEventArgs.nOverheal > 0 then
		tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Overheal"), tCastInfo.strResult, tEventArgs.nOverheal)
	end

	if tEventArgs.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
		tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), tCastInfo.strResult)
	end

	self:AddLogEntry(tCastInfo)
end


function Deaths:OnCombatLogDeflect(tEventArgs)
	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.strCaster, tCastInfo.strSpellName, tCastInfo.strTarget)
	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Deflect"), tCastInfo.strResult)

	self:AddLogEntry(tCastInfo)
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