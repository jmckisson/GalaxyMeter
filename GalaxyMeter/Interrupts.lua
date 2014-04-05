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

	Apollo.SetConsoleVariable("cmbtlog.disableInterrupted", false)
	Apollo.SetConsoleVariable("cmbtlog.disableModifyInterruptArmor", false)

	Apollo.RegisterEventHandler("CombatLogCCState",					"OnCombatLogCCState", self)
	--Apollo.RegisterEventHandler("CombatLogCCStateBreak",			"OnCombatLogCCStateBreak", self)
	--Apollo.RegisterEventHandler("CombatLogInterrupted",				"OnCombatLogInterrupted", self)
	Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor",	"OnCombatLogModifyInterruptArmor", self)


	Apollo.RegisterEventHandler("GalaxyMeterLogStart",				"OnLogStarted", self)
	Apollo.RegisterEventHandler("GalaxyMeterLogStop",				"OnLogStopped", self)

	Apollo.RegisterEventHandler("UnitCreated",						"OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed",					"OnUnitDestroyed", self)

	Apollo.RegisterEventHandler("TargetUnitChanged",				"OnTargetUnitChanged", self)
	Apollo.RegisterEventHandler("UnitEnteredCombat",				"OnUnitEnteredCombat", self)

	self.timerFrame = ApolloTimer.Create(0.1, true, "OnFrame", self)
	--Apollo.RegisterEventHandler("VarChange_FrameCount",				"OnFrame", self)


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
			report = GM.ReportGenericList,
			prev = GM.MenuPrevious,
			next = function(...)
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
	GM:Dirty(true)

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
	 source mob or pet 		&& target player or pet => mob interrupt in
	 source player or pet	&& target mob or pet	=> mob interrupt out
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
		return Interrupts.eTypeInterrupt.In

	-- source player, target mob
	elseif bSourceIsCharacter and not bTargetIsCharacter then
		return Interrupts.eTypeInterrupt.Out

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
				n = v.strName,
				t = nAmount,
				tStr = tostring(nAmount),
				c = GM.ClassToColor[v.classId],
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


	-- Hack to fix error when starting new segment while looking at mob casts for a mob that doesn't exist
	-- yet in the new segment
	if not tActor.casts then
		GM.vars.tMode = GM:PopMode()
		GM:RefreshDisplay()
		return
	end

	local tList = {}
	local nIdx = 0
	for i, v in ipairs(tActor.casts) do

		nIdx = nIdx + 1
		local strTime = mode.format(v.nStart, v.nStop)	-- Right text, Time from-to

		table.insert(tList, {
			n = v.strSpell,	-- cast name
			t = i,	-- index
			tStr = strTime,
			strReport = ("%d) %s %s"):format(nIdx, v.strSpell, strTime),
			c = GM.kDamageStrToColor.Red,
			progress = 1,
			click = function(m, btn)
				if btn == 0 and mode.next then
					mode.next(v)
				elseif btn == 1 and mode.prev then
					-- MenuPrevious needs self reference to be GalaxyMeter
					mode.prev(GM)
				end
			end
		})
	end

	return tList, tTotal, string.format(mode.name, tActor.strName), ("%s's Casts"):format(tActor.strName)
end


function Interrupts:GetCastBreakdown(tMobCast)

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
	local nIdx = 0
	for playerName, tPlayer in pairs(tLogPlayers) do

		-- If this particular individual began to proceed to interrupt this particular mobs spell
		if tPlayer.interruptOut and tPlayer.interruptOut[nActorId] and tPlayer.interruptOut[nActorId][tMobCast.strSpell] then

			-- Find interrupts within the time window
			for idx, tPlayerCast in pairs(tPlayer.interruptOut[nActorId][tMobCast.strSpell]) do

				if tPlayerCast.nTime >= tMobCast.nStart and tPlayerCast.nTime <= tMobCast.nStop then

					local strN = string.format("%s: %s (%d)", playerName, tPlayerCast.strSpell, tPlayerCast.nAmount)

					local strTStr = string.format("%.2fs", tPlayerCast.nTime - tMobCast.nStart)	-- reaction time

					nIdx = nIdx + 1

					table.insert(tList, {
						n = strN,
						t = tPlayerCast.nTime,
						strReport = ("%d) %s - %s"):format(nIdx, strN, strTStr),
						tStr = strTStr,
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

	return tList, tTotal, mode.name, ("%s's Cast Interrupts"):format(GM:LogActorName())
end


function Interrupts:MenuCastBreakdownSelection(tMobCast)

	GM:Rover("MenuCastBreakdown", {self=self, tMobCast=tMobCast})

	local newMode = {
		name = string.format("%s Interrupts", tMobCast.strSpell),
		display = function()
			return self:GetCastBreakdown(tMobCast)
		end,
		report = GM.ReportGenericList,
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

	GM:LogActorName(tActor.strName)
	GM:LogType(mode.type) -- casts

	local nActorId = tActor.id

	GM:LogActorId(nActorId)

	GM.Log:info(string.format("MenuActorSelection: %s -> %s", tActor.strName, mode.type))

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
		GM.Log:info(tEvent.tCasterInfo.strName .. " interrupted " .. tEvent.tTargetInfo.strName)

		player.interrupts = (player.interrupts or 0) + 1

		player.interruptOut = player.interruptOut or {}
		player.interruptOut[tEvent.nTargetId] = player.interruptOut[tEvent.nTargetId] or {}

		local target = player.interruptOut[tEvent.nTargetId]

		GM:Rover("PlayerInterrupted", {player=player, target=target, event=tEvent})

		-- Find spell that was interrupted by time if GetCastName() failed
		--if not tEvent.strInterruptedSpell or tEvent.strInterruptedSpell == "" then
			GM.Log:info("No strInterruptedSpell")
			local tMob = GM:FindMob(GM:GetLog(), tEvent.nTargetId)
			if not tMob then
				GM.Log:error(string.format("Could not locate mob %s for interrupt", tEvent.strTarget))
				return
			end

			if not tMob.casts then
				GM.Log:error("mob has no casts")
				return
			end

			local found = false
			for i=1, #tMob.casts do
				local cast = tMob.casts[i]
				if not found and tEvent.nTime >= cast.nStart and (not cast.nStop or tEvent.nTime <= cast.nStop) then
					tEvent.strInterruptedSpell = cast.strSpell
					found = true
				end
			end

			if not found then
				GM.Log:error("failed to find cast")
				return
			end

		--end


		target[tEvent.strInterruptedSpell] = target[tEvent.strInterruptedSpell] or {}

		table.insert(target[tEvent.strInterruptedSpell], {
			nTime = tEvent.nTime,
			nAmount = tEvent.nAmount,
			strTargetName = tEvent.strTarget,
			strSpell = tEvent.strInterruptingSpell,
		})

		GM.Log:info(string.format("Interrupt: caster='%s:%s' target='%s:%s'",
			tEvent.tCasterInfo.strName, tEvent.strInterruptingSpell, tEvent.tTargetInfo.strname, tEvent.strInterruptedSpell))


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
	gLog:info("OnCombatLogInterrupted()")
	gLog:info(tEventArgs)

	if GM:IsPlayerOrPlayerPet(tEventArgs.unitCaster) then

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

		local tPlayer = GM:GetLog().players[tEvent.tCasterInfo.strName]

		GM.Log:info({tEvent=tEvent})

		tEvent.nTypeId = Interrupts.eTypeInterrupt.Out

		self:UpdateInterrupt(tEvent, tPlayer)
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
	-- result 0 removed = false
	-- result 10?? removed = true
	--if tEventArgs.eResult ~= CombatFloater.CodeEnumCCStateApplyRulesResult.Target_InterruptArmorReduced then
	if tEventArgs.eResult ~= 0 then
		return
	end

	if GM:IsPlayerOrPlayerPet(tEventArgs.unitCaster) then

		if GM:Debug() then
			GM.Log:info("CCStateIA")
			GM.Log:info(tEventArgs)
		end

		local tEvent = GM:HelperCasterTargetSpell(tEventArgs, true, true)

		tEvent.nAmount = tEventArgs.nInterruptArmorHit
		tEvent.nTime = os.clock()
		tEvent.bDeflect = false
		tEvent.bRemoved = tEventArgs.bRemoved
		tEvent.eResult = tEventArgs.eResult
		tEvent.eState = tEventArgs.eState

		-- Spell that interrupted the casting spell
		tEvent.strInterruptingSpell = tEventArgs.splCallingSpell:GetName()

		-- Spell that was casting and got interrupted
		tEvent.strInterruptedSpell = tEventArgs.unitTarget:GetCastName()

		local tPlayer = GM:GetLog().players[tEvent.tCasterInfo.strName]

		GM.Log:info({tEvent=tEvent})

		tEvent.nTypeId = Interrupts.eTypeInterrupt.Out

		self:UpdateInterrupt(tEvent, tPlayer)

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
	end

	if GM:IsPlayerOrPlayerPet(tEventArgs.unitCaster) then

		local tEvent = GM:HelperCasterTargetSpell(tEventArgs, true, true)

		tEvent.nAmount = tEventArgs.nAmount	-- Uhm...?
		tEvent.nTime = os.clock()
		tEvent.eCastResult = tEventArgs.eCastResult
		tEvent.eCombatResult = tEventArgs.eCombatResult

		tEvent.bDeflect = false

		-- Spell that was casting and got interrupted
		tEvent.strInterruptedSpell = tEvent.strSpellName

		-- Spell that interrupted the casting spell
		tEvent.strInterruptingSpell = tEventArgs.splInterruptingSpell:GetName()

		local tPlayer = GM:GetLog().players[tEvent.tCasterInfo.strName]

		GM.Log:info({tEvent=tEvent})

		tEvent.nTypeId = Interrupts.eTypeInterrupt.Out

		self:UpdateInterrupt(tEvent, tPlayer)
	end

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

			GM.Log:info(string.format("%s cast start %s", tUnitInfo.unit:GetName(), tUnitInfo.unit:GetCastName()))

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