--
-- Created by IntelliJ IDEA.
-- User: john
-- Date: 3/17/14
-- Time: 3:11 PM
--

local GM = Apollo.GetAddon("GalaxyMeter")
local MobData = {
	eTypeDamageOrHealing = {
		DamageInOut = 0,
		DamageIn = 1,
		DamageOut = 2,
		HealingInout = 3,
		HealingIn = 4,
		HealingOut = 5,
	}
}

MobData.__index = MobData

function MobData.new()
	local self = setmetatable({}, MobData)

	return self
end


function MobData:Init()

	Apollo.RegisterEventHandler("CombatLogDamage", 	"OnCombatLogDamage", self)


end


function MobData:IsMobOrMobPet(unit)
	if not  unit then return false end

	if not unit:IsACharacter(unit) and (unit:GetUnitOwner() and not unit:GetUnitOwner():IsACharacter()) then
		return true
	end

	return false
end


function MobData:GetDamageEventType(unitCaster, unitTarget)

	self:Rover("GetDmgType", {caster = unitCaster, target = unitTarget})

	local bSourceIsMob = self:IsMobOrMobPet(unitCaster)
	local bTargetIsMob = self:IsMobOrMobPet(unitTarget)
	local bSourceIsCharacter = GM:IsPlayerOrPlayerPet(unitCaster)
	local bTargetIsCharacter = GM:IsPlayerOrPlayerPet(unitTarget)

	--[[
	 source mob or pet 		&& target player or pet => mob dmg out
	 source player or pet	&& target mob or pet	=> mob dmg in
	 source mob or pet		&& target mob or pet	=> mob dmg in/out
	 --]]

	if bSourceIsMob and bTargetIsCharacter then
		return MobData.eTypeDamageOrHealing.DamageOut

	elseif bSourceIsCharacter and bTargetIsMob then
		return MobData.eTypeDamageOrHealing.DamageIn

	elseif bSourceIsMob and bTargetIsMob then
		return MobData.eTypeDamageOrHealing.DamageInOut

	else
		-- Ignore
		return 0
	end

end


function MobData:OnCombatLogDamage(tEventArgs)

	if not tEventArgs.unitCaster or not tEventArgs.unitTarget then
		return
	end

	-- Not interested in character to character data
	if GM:IsPlayerOrPlayerPet(tEventArgs.unitCaster) and GM:IsPlayerOrPlayerPet(tEventArgs.unitTarget) then
		return
	end

	local tInfo = GM:HelperCasterTargetSpell(tEventArgs, true, true)

	local tEvent = {
		unitCaster = tEventArgs.unitCaster,
		strCaster = tInfo.strCaster,
		strCasterType = tInfo.strCasterType,
		unitTarget = tEventArgs.unitTarget,
		strTarget = tInfo.strTarget,
		strTargetType = tInfo.strTargetType,
		strSpellName = tInfo.strSpellName,
		nCasterClassId = tInfo.nCasterClassId,
		nTargetClassId = tInfo.nTargetClassId,

		bDeflect = false,
		nDamageRaw = tEventArgs.nRawDamage,
		nShield = tEventArgs.nShield,
		nAbsorb = tEventArgs.nAbsorption,
		bPeriodic = tEventArgs.bPeriodic,
		bVulnerable = tEventArgs.bTargetVulnerable,
		nOverkill = tEventArgs.nOverkill,
		eResult = tEventArgs.eCombatResult,
		eDamageType = tEventArgs.eDamageType,
		eEffectType = tEventArgs.eEffectType,
	}

	tEvent.nTypeId = self:GetDamageEventType(tEvent.unitCaster, tEvent.unitTarget)

	if tEvent.nTypeId and tEvent.nTypeId > 0 and tEvent.nDamage then

		if self:IsMobOrMobPet(tEvent.unitCaster) then
			tEvent.nId = tEvent.nCasterId
		else
			tEvent.nId = tEvent.nTargetId
		end

		self:UpdateMobSpell(tEvent)

	else
		GM.Log:error(string.format("OnCLDamage: Something went wrong!  Invalid type Id, dmg raw %d, dmg %d", tEventArgs.nRawDamage, tEventArgs.nDamageAmount))

	end

end


function MobData:UpdateMobSpell(tEvent)
	local nCasterId = tEvent.unitCaster:GetId()
	local strSpellName = tEvent.strSpellName
	local strCasterType = tEvent.strCasterType
	local nAmount = tEvent.nDamage

	if not nAmount and not tEvent.bDeflect then
		GM.Log:error("UpdatePlayerSpell: nAmount is nil, spell: " .. spellName)
		self:Rover("nil nAmount Spell", tEvent)
		return
	end

	local tActiveLog = GM:GetLog().mobs

	-- Finds existing or creates new player entry
	local mob = self:GetMob(tActiveLog, nCasterId, tEvent.unitCaster)


	local spell = nil

	-- Player tally and spell type
	if tEvent.nTypeId == MobData.eTypeDamageOrHealing.HealingInOut then

		-- Special handling for self healing, we want to count this as both healing done and received
		-- Maybe add option to enable tracking for this

		local nEffective = nAmount - tEvent.nOverheal

		mob.healingDone = mob.healingDone + nEffective
		mob.healingTaken = mob.healingTaken + nAmount
		mob.healed[tEvent.strTarget] = (mob.healed[tEvent.strTarget] or 0) + nEffective

		if tEvent.nOverheal > 0 then
			mob.overheal = (mob.overheal or 0) + tEvent.nOverheal
		end

		local spellOut = GM:GetSpell(mob.healingOut, strSpellName)
		local spellIn = GM:GetSpell(mob.healingIn, strSpellName)

		--self:TallySpellAmount(tEvent, spellOut)
		--self:TallySpellAmount(tEvent, spellIn)

		GM:Dirty(true)

	elseif tEvent.nTypeId == MobData.eTypeDamageOrHealing.HealingOut then

		local nEffective = nAmount - tEvent.nOverheal

		mob.healingDone = mob.healingDone + nEffective
		mob.healed[tEvent.strTarget] = (mob.healed[tEvent.strTarget] or 0) + nEffective

		if tEvent.nOverheal > 0 then
			mob.overheal = (mob.overheal or 0) + tEvent.nOverheal
		end

		spell = GM:GetSpell(mob.healingOut, strSpellName)

	elseif tEvent.nTypeId == MobData.eTypeDamageOrHealing.HealingIn then

		local nEffective = nAmount - tEvent.nOverheal

		mob.healingTaken = mob.healingTaken + nAmount
		mob.healedBy[tEvent.strTarget] = (mob.healedBy[tEvent.strTarget] or 0) + nEffective

		spell = GM:GetSpell(mob.healingIn, strSpellName)

	elseif tEvent.nTypeId == MobData.eTypeDamageOrHealing.DamageInOut then

		-- Another special case where the spell we cast also damaged ourself?
		mob.damageDone = mob.damageDone + nAmount
		mob.damageTaken = mob.damageTaken + nAmount
		mob.damaged[tEvent.strTarget] = (mob.damaged[tEvent.strTarget] or 0) + nAmount

		local spellOut = GM:GetSpell(mob.damageOut, strSpellName)
		local spellIn = GM:GetSpell(mob.damageIn, strSpellName)

		--self:TallySpellAmount(tEvent, spellOut)
		--self:TallySpellAmount(tEvent, spellIn)

		GM:Dirty(true)

	elseif tEvent.nTypeId == MobData.eTypeDamageOrHealing.PlayerDamageOut then
		if not tEvent.bDeflect then
			mob.damageDone = mob.damageDone + nAmount
			mob.damaged[tEvent.strTarget] = (mob.damaged[tEvent.strTarget] or 0) + nAmount
		end

		spell = GM:GetSpell(mob.damageOut, strSpellName)

	elseif tEvent.nTypeId == MobData.eTypeDamageOrHealing.DamageIn then
		if not tEvent.bDeflect then
			mob.damageTaken = mob.damageTaken + nAmount
			mob.damagedBy[tEvent.strTarget] = (mob.damagedBy[tEvent.strTarget] or 0) + nAmount
		end

		local strMobNameSpell = ("%s: %s"):format(tEvent.strCaster, strSpellName)

		spell = GM:GetSpell(mob.damageIn, strMobNameSpell)

	else
		self:Rover("UpdateMobSpell Error", tEvent)
		GM.Log:error("Unknown type in UpdateMobSpell!")
		GM.Log:error(string.format("Spell: %s, Caster: %s, Target: %s, Amount: %d",
			strSpellName, tEvent.strCaster, tEvent.strTarget, nAmount or 0))

		-- spell should be null here, safe to continue on...
	end

	if spell then
		mob.lastAction = os.clock()
		self:TallySpellAmount(tEvent, spell)
		GM:Dirty(true)
	end

end

GM.MobData = MobData.new()