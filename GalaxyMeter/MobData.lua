--
-- Created by IntelliJ IDEA.
-- User: john
-- Date: 3/17/14
-- Time: 3:11 PM
--

local GM = Apollo.GetAddon("GalaxyMeter")
local MobData = {}


function MobData:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self

	return o
end


function MobData:Init()

	Apollo.RegisterEventHandler("CombatLogDamage", 	"OnCombatLogDamage", self)
	--Apollo.RegisterEventHandler("CombatLogDeflect",	"OnCombatLogDeflect", self)
	--Apollo.RegisterEventHandler("CombatLogHeal", 	"OnCombatLogHeal", self)


	GM:AddMenu("Mob Damage Done: Spell", {
		name = "Mob Damage Done",
		pattern = "Mob Damage %s",
		type = "damageDone",
		segType = "mobs",
		display = GM.GetOverallList,
		report = GM.ReportGenericList,
		prev = GM.MenuPrevious,
		next = function(...)
			self:MenuActorSelection(...)	-- Select specific mob
		end,
		sort = function(a,b) return a.t > b.t end,
		format = function(...)
			return GM:FormatAmountTime(...)
		end
	})

	GM:AddMenu("Mob Damage Taken: Spell", {
		name = "Mob Damage Taken",
		pattern = "Mob Damage %s",
		type = "damageTaken",
		segType = "mobs",
		display = GM.GetOverallList,
		report = GM.ReportGenericList,
		prev = GM.MenuPrevious,
		next = function(...)
			self:MenuActorSelection(...)	-- Select specific mob
		end,
		sort = function(a,b) return a.t > b.t end,
		format = function(...)
			return GM:FormatAmountTime(...)
		end
	})

	GM:AddMenu("Mob Damage Done: Unit", {
		name = "Mob Damage Done",
		pattern = "Mob Damage %s",
		type = "damaged",
		segType = "mobs",
		display = GM.GetUnitList,
		report = GM.ReportGenericList,
		prev = GM.MenuPrevious,
		next = nil,
		sort = function(a,b) return a.t > b.t end,
		format = function(...)
			return GM:FormatAmountTime(...)
		end
	})

	GM:AddMenu("Mob Damage Taken: Unit", {
		name = "Mob Damage Taken",
		pattern = "Mob Damage %s",
		type = "damagedBy",
		segType = "mobs",
		display = GM.GetUnitList,
		report = GM.ReportGenericList,
		prev = GM.MenuPrevious,
		next = nil,
		sort = function(a,b) return a.t > b.t end,
		format = function(...)
			return GM:FormatAmountTime(...)
		end
	})

	self.tModeFromSubType = {
		["damageTaken"] = {
			name = "%s's Damage Taken",
			pattern = "%s's Damage Taken from %s",
			display = self.GetActorList,
			report = GM.ReportGenericList,
			type = "damageIn",
			segType = "mobs",
			prev = GM.MenuPrevious,
			next = GM.MenuSpell,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return GM:FormatAmountTime(...)
			end
		},
		["damageDone"] = {
			name = "%s's Damage Done",
			pattern = "%s's Damage Done by %s",
			display = self.GetActorList,
			report = GM.ReportGenericList,
			type = "damageOut",
			segType = "mobs",
			prev = GM.MenuPrevious,
			next = GM.MenuSpell,
			sort = function(a,b) return a.t > b.t end,
			format = function(...)
				return GM:FormatAmountTime(...)
			end
		}
	}

end


--[[
- @param m GalaxyMeter, this was passed in by GetOverallList
 ]]
function MobData:MenuActorSelection(m, nActorId)

	--GM:Rover("MobDataActorSelection", {m=m, self=self, nActorId=nActorId})

	local actor = GM:FindMob(GM:GetLogDisplay(), nActorId)

	if not actor then
		GM.Log:info("cant find actor " .. nActorId .. " in MenuActorSelection")
		return
	end

	local mode = GM:GetCurrentMode()

	GM:LogActorId(nActorId)
	GM:LogType(mode.type)
	GM:LogActorName(actor.strName)

	GM.Log:info(string.format("MenuActorSelection: %s -> %s", actor.strName, mode.type))

	GM:LogModeType(GM.tListFromSubType[mode.type])	-- Save this because as we delve deeper into menus the type isn't necessarily set

	local newMode = self.tModeFromSubType[mode.type]

	GM:PushMode(newMode)

	GM:Dirty(true)
end


--[[
function MobData:MenuSpell(tSpell, tActor)
	GM:LogActor(tActor)
	GM:LogSpell(tSpell.name)

	GM:PushMode(GM.tModes["Spell Breakdown"])

	GM:Dirty(true)
end
--]]


-- Get actor listing for this segment
-- @return Tables containing actor damage done etc
--    1) Ordered list of individual spells
--    2) Total
function MobData:GetActorList()
	local tList = {}

	-- These should have already been set
	local nActorId = GM:LogActorId()
	local strName = GM:LogActorName()
	local mode = GM:GetCurrentMode()
	local tLogSegment = GM:GetLogDisplay()

	--local tActor = GM:LogActor()

	local tActorLog = tLogSegment[mode.segType][nActorId]

	-- convert to damageDone/damageTaken
	local dmgTypeTotal = GM.tSubTypeFromList[mode.type]

	local nDmgTotal = tActorLog[dmgTypeTotal]

	local nTime = GM:GetLogDisplayTimer()

	GM:Rover("GetActorList", {dmgTypeTotal=dmgTypeTotal, nDmgTotal=nDmgTotal, tActorLog=tActorLog})

	local tTotal = {
		n = string.format("%s's %s", strName, mode.type),
		t = nDmgTotal, -- "Damage to XXX"
		c = GM.kDamageStrToColor.Self,
		tStr = mode.format(nDmgTotal, nTime),
		progress = 1,
		click = function(m, btn)
			if btn == 0 and mode.nextTotal then
				mode.nextTotal(self, tActorLog)
			elseif btn == 1 and mode.prev then
				mode.prev(self)
			end
		end
	}

	local nMax = 0
	for k, v in pairs(tActorLog[mode.type]) do
		if v.total > nMax then nMax = v.total end
	end

	for k, v in pairs(tActorLog[mode.type]) do

		table.insert(tList, {
			n = k,
			t = v.total,
			c = GM.kDamageTypeToColor[v.dmgType],
			tStr = mode.format(v.total, nTime),
			progress = v.total / nMax,
			click = function(m, btn)
				if btn == 0 and mode.next then
					mode.next(self, v, tActorLog)
				elseif btn == 1 then
					mode.prev(self)
				end
			end
		})
	end

	local strDisplayText = string.format("%s's %s", strName, mode.type)

	-- "%s's Damage to %s"
	local strModePatternTemp = string.format(mode.pattern, strName, tLogSegment.name)

	-- Move to Report
	local strTotalText = string.format("%s - %d (%.2f) - %s",
		--"%s's blah on %s"
		strModePatternTemp,
		nDmgTotal,
		nDmgTotal / tLogSegment.combat_length,
		self:SecondsToString(tLogSegment.combat_length))

	return tList, tTotal, strDisplayText, strTotalText
end


--[[
-- Returns list of mobs who have been damaged or have done damage
function MobData:GetMobUnitList()

	local mode = GM:GetCurrentMode()
	local tLogSegment = GM:GetLogDisplay()
	local tLogActors = tLogSegment[mode.segType]	--log.mobs

	local nTime = GM:GetLogDisplayTimer()

	local tList = {}
	local nSum, nMax = 0, 0

	local typeTotal = GM.tTotalFromListType[mode.type]

	-- Find individual actor sum, total sum, and total max
	for nActorId, tActor in pairs(tLogActors) do

		if tActor.typeTotal > 0 then	--log.mobs[mobId].damaged[] => typeTotal damageDone

			local nActorSum = 0
			for k, v in pairs(tActor[mode.type]) do
				nSum = nSum + v
				if v > nMax then nMax = v end
			end

		end
	end


	-- Build list
	for nActorId, tActor in pairs(tLogActors) do

		-- Check if its been damaged/damageBy'd
		--if #tActor[mode.type] > 0 then
		if tActor.typeTotal > 0 then

			--local nActorTotal = tActorTotal[tActor.name]
			local nActorTotal = tActor.typeTotal

			table.insert(tList, {
				n = tActor.name,
				t = nActorTotal,
				c = GM.ClassToColor[tActor.classId],
				tStr = mode.format(nActorTotal, nTime),
				progress = nActorTotal / nMax,
				click = function(m, btn)
					if btn == 0 and mode.next then
						mode.next(GM, tActor)
					elseif btn == 1 and mode.prev then
						mode.prev(GM)
					end
				end
			})
		end
	end

	local tTotal = {
		n = "Some Stuff",
		c = GM.kDamageStrToColor.Self, progress = 1,
	}

	return tList, tTotal, mode.name, ""
end
--]]


function MobData:GetDamageEventType(unitCaster, unitTarget)

	local bSourceIsCharacter = GM:IsPlayerOrPlayerPet(unitCaster)
	local bTargetIsCharacter = GM:IsPlayerOrPlayerPet(unitTarget)

	--[[
	 source mob or pet 		&& target player or pet => mob dmg out
	 source player or pet	&& target mob or pet	=> mob dmg in
	 source mob or pet		&& target mob or pet	=> mob dmg in/out
	 --]]

	--[[
	GM:Rover("MobGetDmgType", {	caster = unitCaster,
								target = unitTarget,
								bSourceIsMob = not bSourceIsCharacter,
								bTargetIsMob = not bTargetIsCharacter,
								bSourceIsCharacter = bSourceIsCharacter,
								bTargetIsCharacter = bTargetIsCharacter,
							})
	--]]

	if not bSourceIsCharacter and bTargetIsCharacter then
		return GM.eTypeDamageOrHealing.DamageOut

	elseif bSourceIsCharacter and not bTargetIsCharacter then
		return GM.eTypeDamageOrHealing.DamageIn

	elseif not bSourceIsCharacter and not bTargetIsCharacter then
		return GM.eTypeDamageOrHealing.DamageInOut

	else
		-- Ignore
		return 0
	end

end


function MobData:OnCombatLogDamage(tEventArgs)

	if not tEventArgs.unitCaster or not tEventArgs.unitTarget then
		GM.Log:info("discarding mob dmg no unit or caster")
		return
	end

	local bCasterIsPlayer = GM:IsPlayerOrPlayerPet(tEventArgs.unitCaster)

	-- Not interested in character to character data
	if bCasterIsPlayer and GM:IsPlayerOrPlayerPet(tEventArgs.unitTarget) then
		GM.Log:info("discarding mob dmg player dmg only")
		return
	end

	local tEvent = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tEvent then return end

	tEvent.bDeflect = false
	--tEvent.unitCaster = tEventArgs.unitCaster
	--tEvent.unitTarget = tEventArgs.unitTarget
	tEvent.nDamageRaw = tEventArgs.nRawDamage
	tEvent.nShield = tEventArgs.nShield
	tEvent.nAbsorb = tEventArgs.nAbsorption
	tEvent.bPeriodic = tEventArgs.bPeriodic
	tEvent.bVulnerable = tEventArgs.bTargetVulnerable
	tEvent.nOverkill = tEventArgs.nOverkill
	tEvent.eResult = tEventArgs.eCombatResult
	tEvent.eDamageType = tEventArgs.eDamageType
	tEvent.eEffectType = tEventArgs.eEffectType
	tEvent.nDamage = tEventArgs.nDamageAmount

	tEvent.nTypeId = self:GetDamageEventType(tEventArgs.unitCaster, tEventArgs.unitTarget)

	GM:Rover("MobEvent", tEvent)

	if tEvent.nTypeId > 0 and tEvent.nDamage then

		GM:TryStartSegment(tEvent, tEventArgs.unitTarget)

		local mob

		if not bCasterIsPlayer then
			mob = GM:GetMob(GM:GetLog(), tEvent.nCasterId, tEventArgs.unitCaster)
		else
			mob = GM:GetMob(GM:GetLog(), tEvent.nTargetId, tEventArgs.unitTarget)
		end

		GM:Rover("mob", {mob = mob})

		GM:UpdateSpell(tEvent, mob)

	else
		GM.Log:error(string.format("OnCLDamage: Something went wrong!  Invalid type Id, dmg raw %d, dmg %d", tEventArgs.nRawDamage, tEventArgs.nDamageAmount))

	end

end


function MobData:OnCombatLogHeal(tEventArgs)
	if not tEventArgs.unitCaster or not tEventArgs.unitTarget then
		return
	end

	-- Not interested in character to character data
	if GM:IsPlayerOrPlayerPet(tEventArgs.unitCaster) and GM:IsPlayerOrPlayerPet(tEventArgs.unitTarget) then
		return
	end

	local tEvent = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	if not tEvent then return end

end


GM.MobData = MobData:new()