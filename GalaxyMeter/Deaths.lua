--
-- Created by IntelliJ IDEA.
-- User: john
-- Date: 3/19/14
-- Time: 4:27 PM
--

local Deaths = {
	nLogTimeWindow = 6,
	tTypeMapping = {
		[GameLib.CodeEnumDamageType.Physical] 	= Apollo.GetString("DamageType_Physical"),
		[GameLib.CodeEnumDamageType.Tech] 		= Apollo.GetString("DamageType_Tech"),
		[GameLib.CodeEnumDamageType.Magic] 		= Apollo.GetString("DamageType_Magic"),
		[GameLib.CodeEnumDamageType.Fall] 		= Apollo.GetString("DamageType_Fall"),
		[GameLib.CodeEnumDamageType.Suffocate] 	= Apollo.GetString("DamageType_Suffocate"),
		["Unknown"] 							= Apollo.GetString("CombatLog_SpellUnknown"),
		["UnknownDamageType"] 					= Apollo.GetString("CombatLog_SpellUnknown"),
	},
	tTypeColor = {
		[GameLib.CodeEnumDamageType.Heal] 			= "ff00ff00",
		[GameLib.CodeEnumDamageType.HealShields] 	= "ff00ffae",
		[GameLib.CodeEnumDamageType.Physical ]		= "ffff80ff",
		[GameLib.CodeEnumDamageType.Tech ]			= "ff9900ff",
		[GameLib.CodeEnumDamageType.Magic ]			= "ff0000ff",
		[GameLib.CodeEnumDamageType.Fall ]			= "ff808080",
		[GameLib.CodeEnumDamageType.Suffocate ]		= "ff4c00ff",

	}
}
local GM = Apollo.GetAddon("GalaxyMeter")
GM.Deaths = Deaths

local kstrFontBold 						= "CRB_InterfaceMedium_BB" -- TODO TEMP, allow customizing
local kstrColorCombatLogOutgoing 		= "ff2f94ac"
local kstrColorCombatLogIncomingGood 	= "ff4bacc6"
local kstrColorCombatLogIncomingBad 	= "ffff4200"
local kstrColorCombatLogUNKNOWN 		= "ffffffff"
local kstrCurrencyColor 				= "fffff533"
local kstrStateColor 					= "ff9a8460"

local tTypeToColor = {
	--[GM.eTypeDamageOrHealing.DamageInOut]	= kstrColorCombatLogUNKNOWN,
	[GM.eTypeDamageOrHealing.DamageIn]		= kstrColorCombatLogIncomingBad,
	[GM.eTypeDamageOrHealing.DamageOut]		= kstrColorCombatLogOutgoing,
	[GM.eTypeDamageOrHealing.HealingInOut]	= kstrColorCombatLogIncomingGood,
	[GM.eTypeDamageOrHealing.HealingIn]		= kstrColorCombatLogIncomingGood,
	[GM.eTypeDamageOrHealing.HealingOut]	= kstrColorCombatLogOutgoing,
}

function Deaths:Init()


	Apollo.SetConsoleVariable("cmbtlog.disableDelayDeath", false)
	Apollo.SetConsoleVariable("cmbtlog.disableDeath", false)

	Apollo.RegisterEventHandler("CombatLogAbsorption",				"OnCombatLogAbsorption", self)
	Apollo.RegisterEventHandler(GM.kEventDamage,					"OnDamage", self)
	--Apollo.RegisterEventHandler("CombatLogDeath",					"OnCombatLogDeath", self)
	Apollo.RegisterEventHandler(GM.kEventDeflect,					"OnDeflect", self)
	--Apollo.RegisterEventHandler("CombatLogDispel",					"OnCombatLogDispel", self)
	--Apollo.RegisterEventHandler("CombatLogDelayDeath",				"OnCombatLogDelayDeath", self)
	--Apollo.RegisterEventHandler("CombatLogFallingDamage",			"OnCombatLogFallingDamage", self)
	Apollo.RegisterEventHandler(GM.kEventHeal,						"OnHeal", self)
	Apollo.RegisterEventHandler("CombatLogImmunity",				"OnCombatLogImmunity", self)


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

	self.chatLine = {}

	self.wndDeathLog = Apollo.LoadForm(GM.xmlMainDoc, "DeathLogWindow", nil, self)
	self.wndDeathLog:Show(false)

	self.btnReport = self.wndDeathLog:FindChild("ButtonReport")
	self.lblTitle = self.wndDeathLog:FindChild("LabelTitle")
	self.wndTextBox = self.wndDeathLog:FindChild("ChatBox")

	GM.Logger:info("Deaths:Init()")
	GM:Dirty(true)
end


function Deaths:ResizeChatLines()
	for idx, value in pairs(self.chatLine) do
		self.chatLine[idx]:SetHeightToContentHeight()
	end

	self.wndTextBox:ArrangeChildrenVert()
	self.wndTextBox:SetVScrollPos(self.wndTextBox:GetVScrollRange())
end


function Deaths:OnResize( wndHandler, wndControl )
	self:ResizeChatLines()
	wndControl:ToFront()
end


function Deaths:OnButtonClose( wndHandler, wndControl, eMouseButton )
	self.wndDeathLog:Show(false)
end


function Deaths:OnButtonReport( wndHandler, wndControl, eMouseButton )
	self:PrintPlayerDeath(wndControl:GetData())
end


function Deaths:OnRestore(eType, t)
	GM.Logger:info("OnRestore()")

	if not t then return end

	if eType == GameLib.CodeEnumAddonSaveLevel.General then
		if t.settings then
			if t.settings.anchor then
				self.wndDeathLog:SetAnchorOffsets(unpack(t.settings.anchor))
			end
		end
	end
end


function Deaths:OnSave(eType)
	GM.Log:info("OnSave()")

	local tSave = {
		settings = {}
	}

	if eType == GameLib.CodeEnumAddonSaveLevel.General then
		tSave.settings.anchor = {self.wndDeathLog:GetAnchorOffsets()}
	end

	return tSave
end


function Deaths:MenuPlayerDeathSelection(tActor)

	if not tActor then
		GM.Logger:info("cant find actor in MenuActorSelection")
		return
	end

	GM.Logger:info(string.format("MenuPlayerDeathSelection: %s", tActor.strName))

	self:DisplayPlayerDeath(tActor)
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


function Deaths:DisplayPlayerDeath(tActor)
	if tActor.deaths then

		local log = tActor.deaths[#tActor.deaths].log

		self.lblTitle:SetText(string.format("Death log for %s", tActor.strName))

		for i = 1, #log do
			local strText = log[i].strMessage

			if not self.chatLine[i] then
				self.chatLine[i] = Apollo.LoadForm(GM.xmlMainDoc, "ChatLine", self.wndTextBox, self)
			end

			local strLine = ("<T Font=\"%s\">%s</T>"):format(kstrFontBold, strText)

			-- When is this ever an xml doc?
			if type(strLine) == "string" then
				self.chatLine[i]:SetText(strLine)
			else
				self.chatLine[i]:SetDoc(strLine)
			end
		end

		-- Trim Remainder
		if #self.chatLine > #log then
			for i = #log + 1, #self.chatLine do
				self.chatLine[i]:Destroy()
				self.chatLine[i] = nil
			end
		end

		self:ResizeChatLines()
		self.btnReport:SetData(tActor)
		self.wndDeathLog:Show(true)
	end
end


function Deaths:PrintPlayerDeath(tActor)

	if tActor.deaths then

		local log = tActor.deaths[#tActor.deaths].log

		local strReportChannel = GM:ReportChannel()

		ChatSystemLib.Command(string.format("/%s Death log for %s:", strReportChannel, tActor.strName))

		for i = 1, #log do
			local strStrippedMsg = log[i].strMessage:gsub("%b<>", "")

			ChatSystemLib.Command(string.format("/%s %s", strReportChannel, strStrippedMsg))
		end
	end
end



function Deaths:PrintPlayerLog(strPlayerName)

	if strPlayerName == nil or strPlayerName == "" then
		return
	end

	local tPlayerLog = GM:GetLogDisplay().players[strPlayerName]

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

	local tm = GameLib.GetLocalTime()

	-- Create log entry
	local tNewLogEntry = {
		nClockTime = os.clock(),
		strMessage = ("<T TextColor=\"ffaec26b\">%d:%02d:%02d::</T> %s"):format(tm.nHour, tm.nMinute, tm.nSecond, tEvent.strResult),
		nType = tEvent.nTypeId,
		bDeath = tEvent.bDeath or false	-- Move this into nType?
	}

	--GM.Log:info(tNewLogEntry.strMessage)

	if tEvent.bCasterIsPlayer then
		local tActor = GM:GetLog().players[tEvent.tCasterInfo.strName]

		self:AddLogEntryPlayer(tNewLogEntry, tActor)
	end

	if tEvent.bTargetIsPlayer and tEvent.unitCaster:GetId() ~= tEvent.unitTarget:GetId() then
		local tActor = GM:GetLog().players[tEvent.tTargetInfo.strName]

		self:AddLogEntryPlayer(tNewLogEntry, tActor)
	end

end


function Deaths:GetAttributedName(tUnitInfo)

	local nHealthPct = (tUnitInfo.unit:GetHealth() / tUnitInfo.unit:GetMaxHealth()) * 100

	local strHpColor = "ff00cc00"	-- 100%, green
	if nHealthPct < 100 and nHealthPct >= 75 then
		strHpColor = "ff66ccff"	-- 100-75%, blueish
	elseif nHealthPct < 75 and nHealthPct >= 35 then
		strHpColor = "ffffff00"	-- 74-35%, yellow
	elseif nHealthPct < 35 and nHealthPct >= 10 then
		strHpColor = "ffff6600" -- orange
	else
		strHpColor = "ffff0000" -- red
	end

	return ("%s(<T TextColor=\"%s\">%d%%</T>)"):format(tUnitInfo.strName, strHpColor, nHealthPct)
end


-----------------------------------------------------------------------------------------------
-- Combat Log Events
-----------------------------------------------------------------------------------------------

function Deaths:OnCombatLogAbsorption(tEventArgs)
	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.tCasterInfo.strName, tCastInfo.strSpellName, tCastInfo.tTargetInfo.strName)
	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_GrantAbsorption"), tCastInfo.strResult, tostring(tEventArgs.nAmount))

	if tEventArgs.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
		--self:PostOnChannel("Absorption")
		tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), tCastInfo.strResult)
	end

	self:AddLogEntry(tCastInfo)
end


function Deaths:OnCombatLogDelayDeath(tEventArgs)
	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, false, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_NotDeadYet"), tCastInfo.tCasterInfo.strName, tCastInfo.strSpellName)

	self:AddLogEntry(tCastInfo)
end


function Deaths:AddPlayerDeath(unitPlayer)

	if unitPlayer:IsACharacter() then

		local strName = unitPlayer:GetName()

		local tPlayerLog = GM:GetLog().players[strName]

		if tPlayerLog.log then

			tPlayerLog.deaths = tPlayerLog.deaths or {}

			GM.Logger:info(tPlayerLog.strName .. " death")

			local tDeathLog = {}
			for i = tPlayerLog.log.first, tPlayerLog.log.last do
				local entry = tPlayerLog.log[i]

				-- Only copy incoming damage and heals
				if entry.nType == GM.eTypeDamageOrHealing.DamageIn
				or entry.nType == GM.eTypeDamageOrHealing.HealingIn
				or entry.nType == GM.eTypeDamageOrHealing.HealingInOut
				or entry.bDeath then
					table.insert(tDeathLog, entry)
				end
			end

			table.insert(tPlayerLog.deaths, {
				time = os.clock(),
				log = tDeathLog,
			})

		else
			GM.Logerg:warn(strName .. " died without entries in combat log!")
		end

	else
		GM.Logger:warn("unitPlayer not a player!")
	end
end


-- This seems to only be returning the player
function Deaths:OnCombatLogDeath(tEventArgs)
	if GM:Debug() then
		GM.Logger:info("OnCombatLogDeath()")
		GM.Logger:info(tEventArgs)
		GM:Rover("CLDeath", tEventArgs)
	end

	if not tEventArgs.unitCaster then return end

	self:AddPlayerDeath(tEventArgs)
end


function Deaths:OnDamage(tEvent)

	local strDamageColor = self:HelperDamageColor(tEvent.eDamageType)

	--HelperPickColor
	local strColor = tTypeToColor[tEvent.nTypeId] or kstrColorCombatLogUNKNOWN

	-- System treats environment damage as coming from the player
	local bEnvironmentDmg = tEvent.tCasterInfo.nId == tEvent.tTargetInfo.nId
	if bEnvironmentDmg then
		strColor = kstrColorCombatLogIncomingBad
	end

	local strDamage = string.format("<T TextColor=\"%s\">%s</T>", strDamageColor, tEvent.nDamage)

	local strCaster = self:GetAttributedName(tEvent.tCasterInfo)
	local strTarget = self:GetAttributedName(tEvent.tTargetInfo)

	if tEvent.tTargetInfo.unit and tEvent.tTargetInfo.unit:IsMounted() then
		strTarget = String_GetWeaselString(Apollo.GetString("CombatLog_MountedTarget"), strTarget)
	end

	local strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), strCaster, tEvent.strSpellName, strTarget)

	if bEnvironmentDmg then
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_EnvironmentDmg"), tEvent.strSpellName, strTarget)
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
		strResult = String_GetWeaselString(strDamageMethod, strResult, strDamage, strDamageType)
	end

	if tEvent.nShield and tEvent.nShield > 0 then
		local strAmountShielded = string.format("<T TextColor=\"%s\">%s</T>", strDamageColor, tEvent.nShield)
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageShielded"), strResult, strAmountShielded)
	end

	if tEvent.nAbsorption and tEvent.nAbsorption > 0 then
		local strAmountAbsorbed = string.format("<T TextColor=\"%s\">%s</T>", strDamageColor, tEvent.nAbsorption)
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageAbsorbed"), strResult, strAmountAbsorbed)
	end

	if tEvent.nOverkill and tEvent.nOverkill > 0 then
		local strAmountOverkill = string.format("<T TextColor=\"%s\">%s</T>", strDamageColor, tEvent.nOverkill)
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageOverkill"), strResult, strAmountOverkill)
	end

	if tEvent.bTargetVulnerable then
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_DamageVulnerable"), strResult)
	end

	if tEvent.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), strResult)
	end

	tEvent.strResult = string.format("<T TextColor=\"%s\">%s</T>", strColor, strResult)

	self:AddLogEntry(tEvent)

	-- Sometimes seeing this after combat has ended if the target is the player
	-- Might be a problem with death detection, or the game actually thinking we're
	-- out of combat right before we died...
	if tEvent.bTargetKilled then
		tEvent.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_TargetKilled"), strCaster, strTarget)
		tEvent.bDeath = true
		self:AddLogEntry(tEvent)

		if tEvent.tTargetInfo.unit:IsACharacter() then
			self:AddPlayerDeath(tEvent.tTargetInfo.unit)
		end
	end

end


function Deaths:OnCombatLogFallingDamage(tEventArgs)

	-- Example Combat Log Message: 17:18: Alvin suffers 246 falling damage
	tEventArgs.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_FallingDamage"), tEventArgs.nDamageAmount)

	self:AddLogEntry(tEventArgs)
end


function Deaths:OnHeal(tEvent)

	--GM:Rover("GMLogHeal", {tEvent=tEvent})

	local strDamageColor = self:HelperDamageColor(tEvent.eDamageType)

	--HelperPickColor
	local strColor = tTypeToColor[tEvent.nTypeId] or kstrColorCombatLogUNKNOWN

	local strSpellName = tEvent.strSpellName

	local strAmount = string.format("<T TextColor=\"%s\">%s</T>", strDamageColor, tEvent.nDamage)

	local strCaster = self:GetAttributedName(tEvent.tCasterInfo)
	local strTarget = self:GetAttributedName(tEvent.tTargetInfo)

	local strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), strCaster, tEvent.strSpellName, strTarget)

	local strHealType = ""
	if tEvent.eEffectType == Spell.CodeEnumSpellEffectType.HealShields then
		strHealType = Apollo.GetString("CombatLog_HealShield")
	else
		strHealType = Apollo.GetString("CombatLog_HealHealth")
	end
	strResult = String_GetWeaselString(strHealType, strResult, strAmount)

	if tEvent.nOverheal and tEvent.nOverheal > 0 then
		local strOverhealAmount = string.format("<T TextColor=\"white\">%s</T>", tEvent.nOverheal)
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Overheal"), strResult, strOverhealAmount)
	end

	if tEvent.eCombatResult == GameLib.CodeEnumCombatResult.Critical then
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Critical"), strResult)
	end

	tEvent.strResult = string.format("<T TextColor=\"%s\">%s</T>", strColor, strResult)

	self:AddLogEntry(tEvent)
end


function Deaths:OnDeflect(tEvent)

	local strColor = tTypeToColor[tEvent.nTypeId] or kstrColorCombatLogUNKNOWN

	local strCaster = self:GetAttributedName(tEvent.tCasterInfo)
	local strTarget = self:GetAttributedName(tEvent.tTargetInfo)

	local strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), strCaster, tEvent.strSpellName, strTarget)
	strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Deflect"), strResult)

	tEvent.strResult = string.format("<T TextColor=\"%s\">%s</T>", strColor, strResult)

	self:AddLogEntry(tEvent)
end


function Deaths:OnCombatLogImmunity(tEventArgs)
	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.tCasterInfo.strName, tCastInfo.strSpellName, tCastInfo.tTargetInfo.strName)
	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_Immune"), tCastInfo.strResult)

	self:AddLogEntry(tCastInfo)
end


function Deaths:OnCombatLogDispel(tEventArgs)
	local tCastInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tCastInfo then return end

	tCastInfo.strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.tCasterInfo.strName, tCastInfo.strSpellName, tCastInfo.tTargetInfo.strName)

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


function Deaths:HelperDamageColor(nArg)
	if nArg and self.tTypeColor[nArg] then
		return self.tTypeColor[nArg]
	end
	return kstrColorCombatLogUNKNOWN
end
