--
-- Created by IntelliJ IDEA.
-- User: john
-- Date: 3/10/14
-- Time: 4:04 PM
--

local GM = Apollo.GetAddon("GalaxyMeter")
local Interrupts = {
	EnumState = {
		Unknown = 0,
		Vulnerable = 1,
	}
}
local Queue

Interrupts.__index = Interrupts

-- Allow 'c = Class(blah)' syntax
--setmetatable(Interrupts, {})


local kTrackUnitType = {
	NonPlayer = true,
}


function Interrupts.new()
	local self = setmetatable({}, Interrupts)

	self.tTrackedUnits = {}

	return self
end


function Interrupts:Init()

	Queue = GM.Queue

	--Apollo.RegisterEventHandler("CombatLogCCState",					"OnCombatLogCCState", self)
	--Apollo.RegisterEventHandler("CombatLogCCStateBreak",			"OnCombatLogCCStateBreak", self)
	Apollo.RegisterEventHandler("CombatLogInterrupted",				"OnCombatLogInterrupted", self)
	Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor",	"OnCombatLogModifyInterruptArmor", self)


	Apollo.RegisterEventHandler("GalaxyMeterLogStart",				"OnLogStarted", self)
	Apollo.RegisterEventHandler("GalaxyMeterLogStop",				"OnLogStopped", self)

	Apollo.RegisterEventHandler("UnitCreated",						"OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed",					"OnUnitDestroyed", self)

	Apollo.RegisterEventHandler("VarChange_FrameCount",				"OnFrame", self)


	self.tListFromSubType = {
		["interrupts"] = "interruptOut",
		["interrupted"] = "interruptIn",
	}

	-- Reverse table
	self.tSubTypeFromList = {}
	for k, v in pairs(self.tListFromSubType) do
		self.tSubTypeFromList[v] = k
	end


	GM:AddMenu("Player Interrupts", {
		name = "Player Interrupts",
		pattern = "Interrupts on %s",
		type = "interrupts",
		segType = "players",
		display = GM.GetOverallList,
		report = GM.ReportGenericList,
		prev = GM.MenuPrevious,
		next = self.MenuActorSelection,
		sort = function(a,b) return a.t > b.t end,
		format = function(...)
			return GM:FormatAmount(...)
		end
	})


	-- List of all mobs that casted something this segment
	GM:AddMenu("Mob Casts", {
		name = "Mob Casts",
		--pattern = "%s's Casts",
		type = "casts",
		segType = "mobs",
		display = GM.GetOverallList,
		report = nil,
		prev = GM.MenuPrevious,
		next = self.MenuActorSelection,	-- Select specific mob to view its casts
		sort = function(a,b) return a.t > b.t end,
		format = function(...)
			return GM:FormatAmount(...)
		end
	})

	self.tModeFromSubType = {
		["interrupts"] = {
			name = "%s's Interrupts",
			pattern = "",
			display = self.GetInterruptList,
			report = GM.ReportGenericList,
			type = "interruptOut",
			prev = GM.MenuPrevious,
			next = self.MenuScalarSelection,
			sort = function(a,b) return a.t > b.t end,
		},

		-- Display all casts of a specific mob
		["casts"] = {
			name = "%s's Casts",
			display = self.GetCastList,
			report = nil,
			prev = GM.MenuPrevious,
			next = self.MenuCastBreakdownSelection,	-- Select specific spell to get the breakdown
			sort = function(a,b) return a.t > b.t end,
			format = function(from, to)
				return string.format("%.1f - %.1f", from, to)
			end
		},
	}

end


function Interrupts:OnLogStarted()
	self.tTrackedUnits = {}
end


function Interrupts:OnLogStopped()
end


function Interrupts:GetCastList()
	local mode = GM:GetCurrentMode()
	local tLogDisplay = GM:GetLogDisplay()
	local nActorId = GM:LogActorId()

	local tActor = GM:GetMob(tLogDisplay, nActorId)

	local tList = {}
	for k, v in pairs(tActor.casts) do
		table.insert(tList, {
			n = mode.format(v.nStart, v.nStop),	-- Left text, Time from-to
			t = k,	-- index
			tStr = "",	-- right text
			progress = 1,
			click = function(m, btn)
				if btn == 0 and mode.next then
					mode.next(self, v)
				elseif btn == 1 and mode.prev then
					mode.prev(self)
				end
			end
		})
	end

	return tList, nil, mode.name, ""
end


function Interrupts:GetCastBreakdown(tVulnDetail)
	local mode = GM:GetCurrentMode()
	local tLogDisplay = GM:GetLogDisplay()
	local nActorId = GM:LogActorId()

	local tActor = GM:GetMob(tLogDisplay, nActorId)

	local tList = {}
	for k, v in pairs(tActor.casts) do
		table.insert(tList, {
			n = mode.format(v.nStart, v.nStop),	-- Left text, Player name
			t = k,	-- index
			tStr = "",	-- right text
			progress = 1,
			click = function(m, btn)
				if btn == 0 and mode.next then
					mode.next(self, v)
				elseif btn == 1 and mode.prev then
					mode.prev(self)
				end
			end
		})
	end

	return tList, nil, mode.name, ""
end


function Interrupts:MenuCastBreakdownSelection(tVuln)

	-- Find players who interrupted this mob during this time

	local newMode = {
		display = function()

		end
	}

	self:PushMode(newMode)
end


-- An actor was clicked from an Overall menu, update the mode to the appropriate selection
-- @param strName Actor name
function Interrupts:MenuActorSelection(strName)

	local mode = GM:GetCurrentMode()

	GM:LogActorName(strName)
	GM:LogType(mode.type)

	local tLogDisplay = GM:GetLogDisplay()

	local nActorId = nil

	-- Find actor id
	if mode.strCurrentModeType == "mobs" then
		for id, v in pairs(tLogDisplay[mode.strCurrentModeType]) do
			if v.name == strName then
				nActorId = id
				break
			end
		end
	else
		if tLogDisplay.players[strName] then
			nActorId = tLogDisplay.players[strName].id
		end
	end

	if nActorId == nil then
		GM.Log:warn("Could not locate actor Id for " .. strName)
		return
	end

	GM:LogActorId(nActorId)

	GM.Log:info(string.format("MenuActorSelection: %s -> %s", strName, strSegmentType))

	GM:LogModeType(self.tListFromSubType[mode.type])	-- Save this because as we delve deeper into menus the type isn't necessarily set

	local newMode = self.tModeFromSubType[mode.type]

	self:PushMode(newMode)

	--self.bDirty = true
end


-- Special case scalar list, we create a temporary mode tailored to the specific list we're interested in
function Interrupts:MenuScalarSelection(name)

	GM:Rover("ScalarSelection", {
		param_Name = name,
		vars = self.vars,
	})

	local strLogType = GM:LogType()				-- players/mobs
	local strPlayerName = GM:LogPlayerName()	-- selected player name
	local strModeType = GM:LogModeType()		-- interruptOut/In/etc

	local tLog = GM:GetLogDisplay()

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

	GM:PushMode(newMode)

	--self.bDirty = true
end


function Interrupts:UpdatePlayerInterrupt(tEvent)

	-- Do we care about the interrupting spell?
	-- If it was a spell that did damage then it would be logged by the damage handler
	--local strSpellName = tEvent.strInterruptingSpell
	local activeLog = GM:GetLog().players

	local player = GM:GetPlayer(activeLog, tEvent)

	local playerId = GameLib.GetPlayerUnit():GetId()


	if tEvent.CasterId == playerId and tEvent.TargetId == playerId then
		GM.Log:info("Self interrupt?")

		--player.interrupts = (player.interrupts or 0) + 1
		--player.interrupted = (player.interrupted or 0) + 1

	elseif tEvent.CasterId == playerId then
		-- The player interrupted something
		--gLog:info("Player interrupted " .. tEvent.Target)
		--[[
		player.interrupts = (player.interrupts or 0) + 1
		player.interruptOut = player.interruptOut or {}

		player.interruptOut[tEvent.Target] = player.interruptOut[tEvent.Target] or {}

		local target = player.interruptOut[tEvent.Target]

		if not target[tEvent.SpellName] then
			target[tEvent.SpellName] = 1
		else
			target[tEvent.SpellName] = target[tEvent.SpellName] + 1
		end
		--]]

		player.interruptOut = player.interruptOut or {}
		player.interruptOut[tEvent.strTarget] = player.interruptOut[tEvent.strTarget] or {}

		local target = player.interruptOut[tEvent.strTarget]

		-- Spell that was interrupted
		local spell = target[tEvent.strSpellName] or {}

		table.insert(spell, {
			t = tEvent.nTime,
			n = tEvent.nAmount,
			spl = tEvent.splInterruptingSpell,
		})


	elseif tEvent.TargetId == playerId then
		--[[
		GM.Log:info("Target interrupted")

		player.interrupted = (player.interrupted or 0) + 1
		player.interruptIn = player.interruptIn or {}

		player.interruptIn[tEvent.Caster] = player.interruptIn[tEvent.Caster] or {}

		local target = player.interruptIn[tEvent.Caster]

		if not target[tEvent.SpellName] then
			target[tEvent.SpellName] = 1
		else
			target[tEvent.SpellName] = target[tEvent.SpellName] + 1
		end

		--]]
	end

	player.lastAction = tEvent.nTime

	--[[
	if spell then
		self:TallySpellAmount(tEvent, spell)	-- only used for castCount
		self.bDirty = true
	end
	--]]

end



function Interrupts:OnCombatLogInterrupted(tEventArgs)
	--gLog:info("OnCombatLogInterrupted()")
	--gLog:info(tEventArgs)

	GM:Rover("Interrupted", tEventArgs)

	local tInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	local tEvent = {
		nAmount = tEventArgs.nAmount or 1,	-- Uhm...?
		nTime = os.clock(),
		Caster = tInfo.strCaster,	-- Caster of the interrupting spell
		CasterId = tInfo.nCasterId,
		CasterType = tInfo.strCasterType,
		Target = tInfo.strTarget, -- Target of the interrupting spell
		CasterId = tInfo.nCasterId,
		TargetType = tInfo.strTargetType,
		--CasterClassId = tInfo.nCasterClassId,
		--TargetClassId = tInfo.nTargetClassId,

		Deflect = false,
		CastResult = tEventArgs.eCastResult,
		Result = tEventArgs.eCombatResult,

		-- if bCaster then player class is caster class, otherwise its the target class
		bCaster = (tInfo.strCasterType ~= "NonPlayer"),

		-- Spell that was casting and got interrupted
		strInterruptedSpellName = tInfo.strSpellName,

		-- Spell that interrupted the casting spell
		strInterruptingSpell = tEventArgs.splInterruptingSpell:GetName(),
	}


	self:UpdatePlayerInterrupt(tEvent)

end



function Interrupts:OnCombatLogCCState(tEventArgs)
	--[[
		if not self.unitPlayer then
		self.unitPlayer = GameLib.GetControlledUnit()
	end

	local tCastInfo = self:HelperCasterTargetSpell(tEventArgs, true, false)
	if tEventArgs.unitTarget == self.unitPlayer then
		if not tEventArgs.bRemoved then
			local strState = String_GetWeaselString(Apollo.GetString("CombatLog_CCState"), tEventArgs.strState)
			self:PostOnChannel(string.format("<T TextColor=\"%s\">%s</T>", kstrStateColor, strState))
		else
			local strState = String_GetWeaselString(Apollo.GetString("CombatLog_CCFades"), tEventArgs.strState)
			self:PostOnChannel(string.format("<T TextColor=\"%s\">%s</T>", kstrStateColor, strState))
		end
	end

	-- aside from the above text, we only care if this was an add
	if tEventArgs.bRemoved then
		return
	end

	-- display the effects of the cc state
	tCastInfo.strSpellName = string.format("<T Font=\"%s\">%s</T>", kstrFontBold, tEventArgs.splCallingSpell:GetName())
	local strResult = String_GetWeaselString(Apollo.GetString("CombatLog_BaseSkillUse"), tCastInfo.strCaster, tCastInfo.strSpellName, tCastInfo.strTarget)

	if tEventArgs.eResult == CombatFloater.CodeEnumCCStateApplyRulesResult.Stacking_DoesNotStack then
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_CCDoesNotStack"), strResult, tEventArgs.strState)
	elseif tEventArgs.eResult == CombatFloater.CodeEnumCCStateApplyRulesResult.Target_Immune then
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_CCImmune"), strResult)
	else
		local strEffect = string.format("<T TextColor=\"white\">%s</T>", tEventArgs.strState)
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_CCSideEffect"), strResult, strEffect)
	end

	if tEventArgs.nInterruptArmorHit > 0 and tEventArgs.unitTarget:GetInterruptArmorValue() > 0 then
		local strAmount = string.format("<T TextColor=\"white\">-%s</T>", tEventArgs.nInterruptArmorHit)
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_InterruptArmorRemoved"), strResult, strAmount)
	end

	local nRemainingIA = tEventArgs.unitTarget:GetInterruptArmorValue() - tEventArgs.nInterruptArmorHit
	if nRemainingIA >= 0 then
		local strAmount = string.format("<T TextColor=\"white\">%s</T>", nRemainingIA)
		strResult = String_GetWeaselString(Apollo.GetString("CombatLog_InterruptArmorLeft"), strResult, strAmount)
	end

	self:PostOnChannel(string.format("<T TextColor=\"%s\">%s</T>", self:HelperPickColor(tEventArgs), strResult))
	--]]
end


function Interrupts:OnCombatLogCCStateBreak(tEventArgs)
	if GM.bDebug then
		GM.Log:info("OnCombatLogCCStateBreak()")
		GM.Log:info(tEventArgs)
	end
end


--[[
- Log each interrupt armor in as well as the time
-
- @param tEventArgs {
-			nAmount,
-			unitCaster,
-			unitTarget,
-			splCallingSpell,
-		 }
]]
function Interrupts:OnCombatLogModifyInterruptArmor(tEventArgs)

	local tInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	--[[
	local tEvent = {
		nAmount = tEventArgs.nAmount,	-- Uhm...?
		nTime = os.clock(),
		Caster = tInfo.strCaster,	-- Caster of the interrupting spell
		CasterId = tInfo.nCasterId,
		CasterType = tInfo.strCasterType,
		Target = tInfo.strTarget, -- Target of the interrupting spell
		TargetId = tInfo.nTargetId,
		TargetType = tInfo.strTargetType,
		--CasterClassId = tInfo.nCasterClassId,
		--TargetClassId = tInfo.nTargetClassId,

		Deflect = false,

		-- Spell that was casting and got interrupted
		strInterruptedSpellName = tInfo.strSpellName,

		-- Spell that interrupted the casting spell
		strInterruptingSpell = tEventArgs.splInterruptingSpell:GetName(),
	}
	--]]

	tInfo.nTime = os.clock()
	tInfo.eCastResult = tEventArgs.eCastResult
	tInfo.eCombatResult = tEventArgs.eCombatResult

	-- if bCaster then player class is caster class, otherwise its the target class
	--tInfo.bCaster = (tInfo.strCasterType ~= "NonPlayer")

	-- Spell that interrupted the casting spell
	tInfo.strInterruptingSpell = tEventArgs.splInterruptingSpell:GetName()

	self:UpdatePlayerInterrupt(tInfo)

	--[[
	if tEventArgs.unitCaster:IsThePlayer() or tEventArgs.unitCaster:GetType() ~= "NonPlayer" then

		local nVulnerabilityTime = unit:GetCCStateTimeRemaining(Unit.CodeEnumCCState.Vulnerability)

	end
	--]]

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


function Interrupts:OnUnitCreated(unit)

	if GM:GetLog().start > 0 then

		local nUnitId = unit:GetId()

		--[[
		if self.uPlayerUnit == nil then
			self.tUnitsBacklog[nUnitId] = unit
			return
		end
		--]]

		if not kTrackUnitType[unit:GetType()] then
			return
		end

		if self.tTrackedUnits[nUnitId] then
			return
		end

		self:TrackUnit(unit)
	end
end


function Interrupts:OnUnitDestroyed(unit)

	if GM:GetLog().start > 0 then

		local nUnitId = unit:GetId()

		--[[
		if self.uPlayerUnit == nil then
			self.tUnitsBacklog[nUnitId] = nil
			return
		end
		--]]

		if not self.tTrackedUnits[nUnitId] then
			return
		end

		self:UntrackUnit(nUnitId)
	end
end


function Interrupts:TrackUnit(unit)
	self.tTrackedUnits[unit:GetId()] = {
		unit = unit,
		state = Interrupts.EnumState.Unknown,
	}
end


function Interrupts:UntrackUnit(nUnitId)
	self.tTrackedUnits[nUnitId] = nil
end


--[[
- This builds entries in the mob vulnerable table
- mob#Id {
-	vulnerable {
-		[1] {
-			-- Is nLength important if we log start and stop times?
-			nStart	- Time MoO started
-			nStop	- Time MoO stopped
-			nLength	- Time remaining on the MoO when it started
-			}
-		[2]	....
-	}
- }
]]
function Interrupts:OnFrame()

	local tLogSegment = GM:GetLog()
	local timeNow = os.clock()

	for nUnitId, tUnitInfo in pairs(self.tTrackedUnits) do

		local bIsCasting = tUnitInfo.unit:ShouldShowCastBar()

		-- Not currently vulnerable, and there's time remaining on a MoO
		if tUnitInfo.state ~= Interrupts.EnumState.Casting  then

			-- Unit just started casting
			tUnitInfo.state = Interrupts.EnumState.Casting

			-- Create moo start entry
			local tCast = {
				strSpell = tUhitInfo.unit:GetCastName(),
				nStart = timeNow,	--Start time
				nLength = tUnitInfo.unit:GetCastDuration(),	-- Total length of the cast
			}

			tUnitInfo.tCast = tCast

			-- Find mob in log
			local tMob = GM:GetMob(tLogSegment, nUnitId, tCast.unit)

			tMob.casts = tMob.casts or {}

			table.insert(tMob.casts, tCast)

		-- Unit was vulnerable
		elseif tUnitInfo.state == Interrupts.EnumState.Vulnerable then

			-- But not anymore
			if not bIsCasting then

				-- Oh shit
				if not tUnitInfo.tCast then
					GM.Log:error("Cast ended without starting")
				else

					local tMob = GM:GetMob(tLogSegment, nUnitId)

					-- Current cast should be the last entry in this mobs table
					if not tMob or not tMob.casts then

						GM.Log:error(string.format("No entry for mob[%d] ending cast", nUnitId))

					else

						local tCast = tMob.casts[#tMob.casts]

						-- Sanity check
						if tCast.nStart == tUnitInfo.tCast.nStart then
							tCast.nStop = timeNow

						else
							GM.Log:error("That is not the moo we're looking for [mob: %d spl: '%s' start: %d != %d]",
								nUnitId, tCast.strSpell, tCast.nStart, tUnitInfo.tCast.nStart)
						end

					end
				end

				-- No matter what happened, we're not in a moo so reset these
				tUnitInfo.tCast = nil
				tUnitInfo.state = Interrupts.EnumState.Unknown
			end
		end
	end
end


GM.Interrupts = Interrupts.new()