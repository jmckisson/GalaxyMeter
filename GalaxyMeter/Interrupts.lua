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
		Casting = 1,
	},
	eTypeInterrupt = {
		InOut = 1,
		In = 2,
		Out = 3,
	}
}
local Queue


local kTrackUnitType = {
	NonPlayer = true,
}



function Interrupts:new(o)
	o = o or {}

	setmetatable(o, self)
	self.__index = self

	self.tTrackedUnits = {}

	return o
end


function Interrupts:Init()

	Queue = GM.Queue


	Apollo.SetConsoleVariable("cmbtlog.disableInterrupted", false)
	Apollo.SetConsoleVariable("cmbtlog.disableModifyInterruptArmor", false)

	Apollo.RegisterEventHandler("CombatLogCCState",					"OnCombatLogCCState", self)
	--Apollo.RegisterEventHandler("CombatLogCCStateBreak",			"OnCombatLogCCStateBreak", self)
	Apollo.RegisterEventHandler("CombatLogInterrupted",				"OnCombatLogInterrupted", self)
	--Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor",	"OnCombatLogModifyInterruptArmor", self)


	Apollo.RegisterEventHandler("GalaxyMeterLogStart",				"OnLogStarted", self)
	Apollo.RegisterEventHandler("GalaxyMeterLogStop",				"OnLogStopped", self)

	Apollo.RegisterEventHandler("UnitCreated",						"OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed",					"OnUnitDestroyed", self)

	Apollo.RegisterEventHandler("TargetUnitChanged",				"OnTargetUnitChanged", self)
	Apollo.RegisterEventHandler("UnitEnteredCombat",				"OnUnitEnteredCombat", self)

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

	--[[
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
	--]]


	-- List of all mobs that casted something this segment
	GM:AddMenu("Mob Casts", {
		name = "Mob Casts",
		--pattern = "%s's Casts",
		type = "casts",
		segType = "mobs",
		display = function(...)
			return self:GetMobList(...)
		end,
		report = nil,
		prev = GM.MenuPrevious,
		next = function(...)
			self:MenuActorSelection(...)	-- Select specific mob to view its casts
		end,
		sort = function(a,b) return a.t > b.t end,
		format = function(...)
			return GM:FormatAmount(...)
		end
	})

	self.tModeFromSubType = {
		["interrupts"] = {
			name = "%s's Interrupts",
			pattern = "",
			display = function()
				return self:GetInterruptList()
			end,
			report = GM.ReportGenericList,
			type = "interruptOut",
			segType = "players",
			prev = GM.MenuPrevious,
			next = function(...)
				self:MenuScalarSelection(...)
			end,
			sort = function(a,b) return a.t > b.t end,
		},

		-- Display all casts of a specific mob
		["casts"] = {
			name = "%s's Casts",
			display = function(...)
				return self:GetCastList(...)
			end,
			report = nil,
			prev = GM.MenuPrevious,
			next = function(...)
				GM:Rover("castModeNext", {self=self})
				self:MenuCastBreakdownSelection(...)	-- Select specific spell to get the breakdown
			end,
			sort = function(a,b) return a.t > b.t end,
			format = function(from, to)

				if not to then
					return string.format("%.1f - Casting (%.1fs)", from, os.clock() - from)
				end

				return string.format("%.1f - %.1f (%.1fs)", from, to, to - from)
			end
		},
	}

	GM.Log:info("Interrupts:Init()")

end


function Interrupts:OnLogStarted()
	--self.tTrackedUnits = {}
end


function Interrupts:OnLogStopped()
end


function Interrupts:GetEventType(unitCaster, unitTarget)

	local bSourceIsCharacter = GM:IsPlayerOrPlayerPet(unitCaster)
	local bTargetIsCharacter = GM:IsPlayerOrPlayerPet(unitTarget)

	--[[
	 source mob or pet 		&& target player or pet => mob interrupt out
	 source player or pet	&& target mob or pet	=> mob interrupt in
	 source mob or pet		&& target mob or pet	=> mob interrupt in/out

	 ignore:
	 source player or pet	&& target player or pet => player interrupt in/out
	 --]]

	--[[
	GM:Rover("GetEventType", {	caster = unitCaster,
								target = unitTarget,
								bSourceIsMob = not bSourceIsCharacter,
								bTargetIsMob = not bTargetIsCharacter,
								bSourceIsCharacter = bSourceIsCharacter,
								bTargetIsCharacter = bTargetIsCharacter,
							})
	--]]

	-- source mob, target player
	if not bSourceIsCharacter and bTargetIsCharacter then
		return Interrupts.eTypeInterrupt.Out

	-- source player, target mob
	elseif bSourceIsCharacter and not bTargetIsCharacter then
		return Interrupts.eTypeInterrupt.In

	-- source mob, target mob
	elseif not bSourceIsCharacter and not bTargetIsCharacter then
		return Interrupts.eTypeInterrupt.InOut

	else
		-- Ignore
		return 0
	end

end


function Interrupts:GetMobList()

	local tLogSegment = GM:GetLogDisplay()
	local mode = GM:GetCurrentMode()

	-- Grab segment type from mode: players/mobs/etc
	local tSegmentType = tLogSegment[mode.segType]

	-- Get total
	local tTotal = {t = 0, c = GM.kDamageStrToColor.Self, progress = 1}
	tTotal.tStr = ""

	local tList = {}
	for k, v in pairs(tSegmentType) do

		-- Only show people who have contributed
		if v[mode.type] and #v[mode.type] > 0 then

			local nAmount = #v[mode.type]

			table.insert(tList, {
				n = v.name,
				t = nAmount,
				tStr = "",
				c = GM.kDamageStrToColor.Red,
				progress = 1,
				click = function(m, btn)
				-- arg is the specific actor log table
					if btn == 0 and mode.next then
						mode.next(v)

					elseif btn == 1 and mode.prev then
						-- MenuPrevious needs self reference to be GalaxyMeter
						mode.prev(GM)
					end
				end
			})
		end
	end

	return tList, tTotal, mode.name, ""
end


function Interrupts:GetCastList()
	local mode = GM:GetCurrentMode()
	local tLogDisplay = GM:GetLogDisplay()
	local nActorId = GM:LogActorId()

	local tActor = GM:GetMob(tLogDisplay, nActorId)

	local tTotal = {t = 0, c = GM.kDamageStrToColor.Self, progress = 1}
	tTotal.tStr = ""

	local tList = {}
	for i, v in ipairs(tActor.casts) do
		table.insert(tList, {
			n = v.strSpell,	-- cast name
			t = i,	-- index
			tStr = mode.format(v.nStart, v.nStop),	-- Right text, Time from-to
			c = GM.kDamageStrToColor.Red,
			progress = 1,
			click = function(m, btn)
				if btn == 0 and mode.next then
					GM:Rover("CastListModeNext", {self=self, v=v, mode=mode})
					mode.next(v)
				elseif btn == 1 and mode.prev then
					-- MenuPrevious needs self reference to be GalaxyMeter
					mode.prev(GM)
				end
			end
		})
	end

	return tList, tTotal, string.format(mode.name, tActor.name), ""
end


function Interrupts:GetCastBreakdown(tMobCast)

	--GM:Rover("GetCastBreakdownStart", {self=self, tMobCast=tMobCast})

	-- Find players who interrupted this mob during this time
	local mode = GM:GetCurrentMode()

	local tLogDisplay = GM:GetLogDisplay()
	local tLogPlayers = tLogDisplay.players

	local nActorId = GM:LogActorId()

	if not nActorId then
		GM:Rover("GCastBreakDownNilActor", {tMobCast=tMobCast})
		return
	end

	local tTotal = {t = 0, c = GM.kDamageStrToColor.Self, progress = 1,
		n = string.format("%s: %s", GM:LogActorName(), mode.name), tStr = ""
	}

	local tList = {}
	for playerName, tPlayer in pairs(tLogPlayers) do

		-- If this particular individual began to proceed to interrupt this particular mobs spell
		if tPlayer.interruptOut and tPlayer.interruptOut[nActorId] and tPlayer.interruptOut[nActorId][tMobCast.strSpell] then

			-- Find interrupts within the time window
			for idx, tPlayerCast in pairs(tPlayer.interruptOut[nActorId][tMobCast.strSpell]) do

				if tPlayerCast.nTime >= tMobCast.nStart and tPlayerCast.nTime <= tMobCast.nStop then

					table.insert(tList, {
						n = string.format("%s: %s (%d)", playerName, tPlayerCast.strSpell, tPlayerCast.nAmount),
						t = tPlayerCast.nTime,
						tStr = string.format("%.1fs", tMobCast.nStop - tPlayerCast.nTime),	-- time remaining
						progress = 0,
						click = function(m, btn)
							if btn == 1 and mode.prev then
								-- MenuPrevious needs the self reference to be GalaxyMeter
								mode.prev(GM)
							end
						end
					})
				end
			end
		end
	end


	--GM:Rover("GetCastBreakdownStop", {list=tList, players=tLogPlayers, tMobCast=tMobCast})

	return tList, tTotal, mode.name, ""
end


function Interrupts:MenuCastBreakdownSelection(tMobCast)

	GM:Rover("MenuCastBreakdown", {self=self, tMobCast=tMobCast})

	local newMode = {
		name = string.format("%s Interrupts", tMobCast.strSpell),
		display = function()
			return self:GetCastBreakdown(tMobCast)
		end,
		report = nil,
		next = nil,
		prev = GM.MenuPrevious,
		sort = function(a, b) return a.t > b.t end,
		format = function() return string.format() end
	}

	GM:PushMode(newMode)

	GM:Dirty(true)
end


-- An actor was clicked from an Overall menu, update the mode to the appropriate selection
-- @param tActor Actor table
function Interrupts:MenuActorSelection(tActor)

	--GM:Rover("InterruptMenuActorSelf", self)

	local mode = GM:GetCurrentMode()

	GM:LogActorName(tActor.name)
	GM:LogType(mode.type) -- casts

	local nActorId = tActor.id

	GM:LogActorId(nActorId)

	GM.Log:info(string.format("MenuActorSelection: %s -> %s", tActor.name, mode.type))

	local newMode = self.tModeFromSubType[mode.type]

	GM:PushMode(newMode)

	GM:Dirty(true)
end


function Interrupts:MenuCastSelection(name)

	GM:Rover("CastSelection", {
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

	GM:Dirty(true)
end


function Interrupts:UpdateInterrupt(tEvent, player)

	-- Do we care about the interrupting spell?
	-- If it was a spell that did damage then it would be logged by the damage handler
	--local strSpellName = tEvent.strInterruptingSpell


	if tEvent.nTypeId == Interrupts.eTypeInterrupt.InOut then
		GM.Log:info("Self interrupt?")

		--player.interrupts = (player.interrupts or 0) + 1
		--player.interrupted = (player.interrupted or 0) + 1

	elseif tEvent.nTypeId == Interrupts.eTypeInterrupt.Out then
		-- The player interrupted something
		GM.Log:info(tEvent.strCaster .. " interrupted " .. tEvent.strTarget)

		GM:Rover("PlayerInterrupted", {player=player, event=tEvent})

		player.interrupts = (player.interrupts or 0) + 1

		player.interruptOut = player.interruptOut or {}
		player.interruptOut[tEvent.nTargetId] = player.interruptOut[tEvent.nTargetId] or {}

		local target = player.interruptOut[tEvent.nTargetId]

		-- Spell that was interrupted
		target[tEvent.strInterruptedSpell] = target[tEvent.strInterruptedSpell] or {}

		table.insert(target[tEvent.strInterruptedSpell], {
			nTime = tEvent.nTime,
			nAmount = tEvent.nAmount,
			strTargetName = tEvent.strTarget,
			--strSpell = tEvent.strInterruptingSpell,
		})


	elseif tEvent.nTypeId == Interrupts.eTypeInterrupt.In then
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

end



function Interrupts:OnCombatLogInterrupted(tEventArgs)
	--gLog:info("OnCombatLogInterrupted()")
	--gLog:info(tEventArgs)

	GM:Rover("Interrupted", tEventArgs)

	--strCaster,	-- Caster of the interrupting spell
	--strTarget,	-- Target of the interrupting spell
	local tEvent = GM:HelperCasterTargetSpell(tEventArgs, true, true)


	tEvent.nAmount = tEventArgs.nAmount or 1	-- Uhm...?
	tEvent.nTime = os.clock()
	tEvent.bDeflect = false
	tEvent.eCastResult = tEventArgs.eCastResult
	tEvent.eResult = tEventArgs.eCombatResult

	-- Spell that was casting and got interrupted
	tEvent.strInterruptedSpell = tEvent.strSpellName

	-- Spell that interrupted the casting spell
	tEvent.strInterruptingSpell = tEventArgs.splInterruptingSpell:GetName()

	tEvent.nTypeId = self:GetEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	if tEvent.nTypeId > 0 then

		GM:AssignPlayerInfo(tEvent, tEventArgs)

		local player = GM:GetPlayer(GM:GetLog().players, tEvent)

		self:UpdateInterrupt(tEvent, player)
	end

end


--[[
- tEventArgs {
	unitCaster
	unitTarget
	bRemoved
	bHideFloater
	eState
	eResult - CombatFloater.CodeEnumCCStateApplyRulesResult.Target_InterruptArmorReduced
	nInterruptArmorHit
	splCallingSpell
	strState
- }
 ]]
function Interrupts:OnCombatLogCCState(tEventArgs)

	if not tEventArgs.eResult then
		return
	end

	-- We're only interested in InterruptArmor
	if tEventArgs.eResult ~= CombatFloater.CodeEnumCCStateApplyRulesResult.Target_InterruptArmorReduced then
		return
	end

	if GM:Debug() then
		GM.Log:info("CCStateIA")
		GM.Log:info(tEventArgs)
		GM:Rover("CCStateIA", tEventArgs)
	end

	local tEvent = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	tEvent.nAmount = tEventArgs.nInterruptArmorHit	-- Uhm...?
	tEvent.nTime = os.clock()
	tEvent.bDeflect = false
	tEvent.bRemoved = tEventArgs.bRemoved
	tEvent.eResult = tEventArgs.eResult
	tEvent.eState = tEventArgs.eState

	-- Spell that was casting and got interrupted
	tEvent.strInterruptedSpell = tEventArgs.splCallingSpell:GetName()

	-- Spell that interrupted the casting spell
	--tEvent.strInterruptingSpell = tEventArgs.splCallingSpell:GetName()

	tEvent.nTypeId = self:GetEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	if tEvent.nTypeId > 0 then

		GM:AssignPlayerInfo(tEvent, tEventArgs)

		local player = GM:GetPlayer(GM:GetLog().players, tEvent)

		self:UpdateInterrupt(tEvent, player)
	end

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

	--]]
end


function Interrupts:OnCombatLogCCStateBreak(tEventArgs)
	if GM:Debug() then
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

	if GM:Debug() then
		GM.Log:info("OnCombatLogModifyInterruptArmor")
		GM.Log:info(tEventArgs)
		GM:Rover("ModifyIA", tEventArgs)
	end

	local tInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	local tEvent = {
		nAmount = tEventArgs.nAmount,	-- Uhm...?
		nTime = os.clock(),
		strCaster = tInfo.strCaster,	-- Caster of the interrupting spell
		nCasterId = tInfo.nCasterId,
		strCasterType = tInfo.strCasterType,
		strTarget = tInfo.strTarget,	-- Target of the interrupting spell
		nTargetId = tInfo.nTargetId,
		strTargetType = tInfo.strTargetType,
		eCastResult = tEventArgs.eCastResult,
		eCombatResult = tEventArgs.eCombatResult,

		Deflect = false,

		-- Spell that was casting and got interrupted
		strInterruptedSpell = tInfo.strSpellName,

		-- Spell that interrupted the casting spell
		strInterruptingSpell = tEventArgs.splInterruptingSpell:GetName(),
	}


	tEvent.nTypeId = self:GetEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	if tEvent.nTypeId > 0 then

		GM:AssignPlayerInfo(tEvent, tEventArgs)

		local player = GM:GetPlayer(GM:GetLog().players, tEvent)

		self:UpdateInterrupt(tEvent, player)
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
	--]]
end


function Interrupts:OnUnitEnteredCombat(unit, bCombat)

	--GM.Log:info("UnitEnteredCombat: " .. unit:GetName())

	if unit and bCombat then
		local nUnitId = unit:GetId()

		if not kTrackUnitType[unit:GetType()] then
			return
		end

		if self.tTrackedUnits[nUnitId] then
			return
		end

		self:TrackUnit(unit)
	end
end

function Interrupts:OnTargetUnitChanged(unit)

	if unit then
		--GM.Log:info("TargetUnitChanged: " .. unit:GetName())

		local nUnitId = unit:GetId()

		if not kTrackUnitType[unit:GetType()] then
			return
		end

		if self.tTrackedUnits[nUnitId] then
			return
		end

		self:TrackUnit(unit)
	end
end


function Interrupts:OnUnitCreated(unit)

	local nUnitId = unit:GetId()

	if not kTrackUnitType[unit:GetType()] then
		return
	end

	if self.tTrackedUnits[nUnitId] then
		return
	end

	self:TrackUnit(unit)

end


function Interrupts:OnUnitDestroyed(unit)

	local nUnitId = unit:GetId()

	if not self.tTrackedUnits[nUnitId] then
		return
	end

	self:UntrackUnit(nUnitId)

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
- This builds entries in the mob casts table
- mob#Id {
-	casts {
-		[1] {
-			-- Is nLength important if we log start and stop times?
-			nStart	- Time cast started
-			nStop	- Time cast stopped
-			nLength	- Time remaining on the cast when it started
-			nArmorValue - IA of the cast
-			strSpell - Spell Name
-			}
-		[2]	....
-	}
- }
]]
function Interrupts:OnFrame()

	if not GM.bGroupInCombat then return end

	local tLogSegment = GM:GetLog()
	local timeNow = os.clock()

	for nUnitId, tUnitInfo in pairs(self.tTrackedUnits) do

		local bIsCasting = (tUnitInfo.unit:IsCasting() or tUnitInfo.unit:ShouldShowCastBar())

		--[[
		if bIsCasting then
			GM.Log:info(string.format("%s casting state %d", tUnitInfo.unit:GetName(), tUnitInfo.state))
			GM:Rover("Casting:"..tUnitInfo.unit:GetName(), tUnitInfo)
		end
		--]]

		-- Not currently casting, and there's time remaining on a cast
		if bIsCasting and tUnitInfo.state == Interrupts.EnumState.Unknown then

			-- Unit just started casting
			tUnitInfo.state = Interrupts.EnumState.Casting

			--GM.Log:info(string.format("%s cast start %s", tUnitInfo.unit:GetName(), tUnitInfo.unit:GetCastName()))

			-- Create cast start entry
			local tCast = {
				strSpell = tUnitInfo.unit:GetCastName(),
				nStart = timeNow,	--Start time
				nLength = tUnitInfo.unit:GetCastDuration(),	-- Total length of the cast
				nArmorValue = tUnitInfo.unit:GetInterruptArmorValue()
			}

			tUnitInfo.tCast = tCast

			--GM:Rover("Cast", tUnitInfo)

			-- Find mob in log
			local tMob = GM:GetMob(tLogSegment, nUnitId, tUnitInfo.unit)

			tMob.casts = tMob.casts or {}

			table.insert(tMob.casts, tCast)


		-- Unit was casting
		elseif tUnitInfo.state == Interrupts.EnumState.Casting then

			-- But not anymore
			if not bIsCasting then

				-- Oh shit
				if not tUnitInfo.tCast then
					GM.Log:error("Cast ended without starting")
				else

					local tMob = GM:FindMob(tLogSegment, nUnitId)

					-- Current cast should be the last entry in this mobs table
					if not tMob or not tMob.casts then

						GM.Log:error(string.format("No entry for mob[%d] ending cast", nUnitId))

					else

						local tCast = tMob.casts[#tMob.casts]

						-- Sanity check
						if tCast.nStart == tUnitInfo.tCast.nStart then
							tCast.nStop = timeNow

						else
							GM.Log:error("That is not the cast we're looking for [mob: %d spl: '%s' start: %d != %d]",
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


GM.Interrupts = Interrupts:new()