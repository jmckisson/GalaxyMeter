--
-- Created by IntelliJ IDEA.
-- User: john
-- Date: 4/7/14
-- Time: 11:30 AM
--

local GM = Apollo.GetAddon("GalaxyMeter")

local clock = os.clock
local format = string.format
local max = math.max
local setmetatable = setmetatable


local ActorProto = {}
ActorProto.__index = ActorProto

--[[
setmetatable(ActorProto, {
	__call = function(cls, ...)
		local self = setmetatable({}, cls)
		return self
	end
})
--]]


function ActorProto:_init()
	-- Totals
	self.damageDone = 0                         -- Total Damage Done
	self.damageTaken = 0                        -- Total Damage Taken
	self.healingDone = 0                        -- Total Healing Done
	self.healingTaken = 0                       -- Total Healing Taken

	-- Spells
	self.damageIn = {}                          -- Damage Taken
	self.damageOut = {}                         -- Damage Done
	self.healingIn = {}                         -- Healing Taken
	self.healingOut = {}                        -- Healing Done

	-- Targets
	self.damaged = {}
	self.damagedBy = {}
	self.healed = {}
	self.healedBy = {}
end


--[[
-- Return serialization friendly data table
 ]]
function ActorProto:GetData()
	return {
		damageDone = self.damageDone,
		damageTaken = self.damageTaken,
		healingDone = self.healingDone,
		healingTaken = self.healingTaken,
		damageIn = self.damageIn,
		damageOut = self.damageOut,
		healingIn = self.healingIn,
		healingOut = self.healingOut,
		damaged = self.damaged,
		damagedBy = self.damagedBy,
		healed = self.healed,
		healedBy = self.healedBy,
	}
end


-- TODO Be clever with init or something to initialize these values
function ActorProto:SetData(tData)
	-- Totals
	self.damageDone = tData.damageDone		-- Total Damage Done
	self.damageTaken = tData.damageTaken	-- Total Damage Taken
	self.healingDone = tData.healingDone    -- Total Healing Done
	self.healingTaken = tData.healingTaken	-- Total Healing Taken

	-- Spells
	self.damageIn = tData.damageIn          -- Damage Taken
	self.damageOut = tData.damageOut        -- Damage Done
	self.healingIn = tData.healingIn        -- Healing Taken
	self.healingOut = tData.healingOut      -- Healing Done

	-- Targets
	self.damaged = tData.damaged
	self.damagedBy = tData.damagedBy
	self.healed = tData.healed
	self.healedBy = tData.healedBy
end


-----------------------------------------
-- Mob : ActorProto
-----------------------------------------
local Mob = {}
Mob.__index = Mob
GM.Mob = Mob

setmetatable(Mob, {
	__index = ActorProto,
	-- Allow m = Mob() syntax
	__call = function(cls, ...)
		local self = setmetatable({}, cls)
		self:_init(...)
		return self
	end
})

function Mob:_init(nId, tUnit)
	ActorProto._init(self)

	self.id = nId

	if tUnit then
		self.strName = tUnit:GetName()
		self.classId = tUnit:GetClassId()
	end
end


--[[
-- Return serialization friendly data table
 ]]
function Mob:GetData()
	return {
		id = self.id,
		strName = self.strName,
		classId = self.classId,
		data = ActorProto.GetData(self),
	}
end


function Mob:SetData(tData)
	ActorProto.SetData(self, tData.data)

	self.strName = tData.strName
	self.classId = tData.classId
end


-----------------------------------------
-- Player : ActorProto
-----------------------------------------
local Player = {}
Player.__index = Player
GM.Player = Player

setmetatable(Player, {
	__index = ActorProto,
	-- Allow m = Player() syntax
	__call = function(cls, ...)
		local self = setmetatable({}, cls)
		self:_init(...)
		return self
	end
})


function Player:_init(tPlayerInfo)

	ActorProto._init(self)

	self.strName = tPlayerInfo.strName

	if tPlayerInfo.nId then
		self.playerId = tPlayerInfo.nId		-- Player GUID?
	end

	if tPlayerInfo.nClassId then
		self.classId = tPlayerInfo.nClassId	-- Player Class Id
	end

	-- Custom colors
	if GM.ClassToColor[self.strName] then
		self.classId = self.strName
	end
end


--[[
-- Return serialization friendly data table
 ]]
function Player:GetData()

	local t = {
		strName = self.strName,
		playerId = self.playerId,
		classId = self.classId,
		firstAction = self.firstAction,
		lastAction = self.lastAction,
		deaths = self.deaths,
		data = ActorProto.GetData(self)
	}

	return t
end



function Player:SetData(tData)
	ActorProto.SetData(self, tData.data)

	if tData.firstAction then
		self.firstAction = tData.firstAction
	end

	if tData.lastAction then
		self.lastAction = tData.lastAction
	end

	-- This assumes that there is a deaths module, we shouldnt have to
	-- know about that here
	if tData.deaths then
		self.deaths = tData.deaths
	end
end



--[[
-- Get activity time for an actor in a log segment
 ]]
function ActorProto:GetActiveTime()
	local nTimeTotal = 0

	if self.firstAction then
		nTimeTotal = self.lastAction - self.firstAction
	end

	return max(1, nTimeTotal)
end


-- Find and return spell from spell type table, will create the spell entry if it doesn't exist
-- @param tSpellTypeLog reference to specific spell type table, ie log.players["guy"].damageOut
-- @return Spell data table
function ActorProto:GetSpell(tSpellTypeLog, spellName)

	--gLog:info(format("GetSpell(tSpellTypeLog, %s)", spellName))

	if not tSpellTypeLog[spellName] then
		tSpellTypeLog[spellName] = {

			-- Info
			name = spellName,

			-- Counters
			castCount = 0,              -- total number of hits, includes crits
			critCount = 0,              -- total number of crits
			deflectCount = 0,

			-- Totals
			total = 0,                  -- total damage, totalNormal + totalCrit
			totalCrit = 0,              -- total damage from crits
			totalShield = 0,            -- damage or healing done to shields
			totalAbsorption = 0,        --
			avg = 0, avgCrit = 0,
		}
	end

	return tSpellTypeLog[spellName]
end


function ActorProto:UpdateActiveTime()
	local timeNow = clock()

	if not self.firstAction then
		self.firstAction = timeNow
	end
	self.lastAction = timeNow
end


function ActorProto:UpdateSpell(tEvent)
	local strSpellName = tEvent.strSpellName
	local nAmount = tEvent.nDamage or 0

	--[[
	if not nAmount and not tEvent.bDeflect then
		gLog:error("UpdateSpell: nAmount is nil, spell: " .. strSpellName)
		self:Rover("nil nAmount Spell", tEvent)
		return
	end
	--]]

	--Event_FireGenericEvent("SendVarToRover", "UpdateSpell", {tEvent=tEvent, player=self})


	local spell = nil
	local strCaster = tEvent.tCasterInfo.strName
	local strTarget = tEvent.tTargetInfo.strName

	-- Player tally and spell type
	if tEvent.nTypeId == GM.eTypeDamageOrHealing.HealingInOut then

		-- Special handling for self healing, we want to count this as both healing done and received
		-- Maybe add option to enable tracking for this

		local strTarget = tEvent.tTargetInfo.strName

		self.healingDone = self.healingDone + tEvent.nEffectiveHeal
		self.healingTaken = self.healingTaken + nAmount
		self.healed[strTarget] = (self.healed[strTarget] or 0) + tEvent.nEffectiveHeal

		if tEvent.nOverheal > 0 then
			self.overheal = (self.overheal or 0) + tEvent.nOverheal
		end

		local spellOut = self:GetSpell(self.healingOut, strSpellName)
		local spellIn = self:GetSpell(self.healingIn, strSpellName)

		GM:TallySpellAmount(tEvent, spellOut)
		GM:TallySpellAmount(tEvent, spellIn)

		GM:Dirty(true)

	elseif tEvent.nTypeId == GM.eTypeDamageOrHealing.HealingOut then

		self.healingDone = self.healingDone + tEvent.nEffectiveHeal
		self.healed[strTarget] = (self.healed[strTarget] or 0) + tEvent.nEffectiveHeal

		if tEvent.nOverheal > 0 then
			self.overheal = (self.overheal or 0) + tEvent.nOverheal
		end

		spell = self:GetSpell(self.healingOut, strSpellName)

	elseif tEvent.nTypeId == GM.eTypeDamageOrHealing.HealingIn then

		self.healingTaken = self.healingTaken + nAmount
		self.healedBy[strCaster] = (self.healedBy[strCaster] or 0) + tEvent.nEffectiveHeal

		spell = self:GetSpell(self.healingIn, strSpellName)

	elseif tEvent.nTypeId == GM.eTypeDamageOrHealing.DamageInOut then

		-- Another special case where the spell we cast also damaged ourself?
		self.damageDone = self.damageDone + nAmount
		self.damageTaken = self.damageTaken + nAmount
		self.damaged[strTarget] = (self.damaged[strTarget] or 0) + nAmount

		local spellOut = self:GetSpell(self.damageOut, strSpellName)
		local spellIn = self:GetSpell(self.damageIn, strSpellName)

		GM:TallySpellAmount(tEvent, spellOut)
		GM:TallySpellAmount(tEvent, spellIn)

		GM:Dirty(true)

	elseif tEvent.nTypeId == GM.eTypeDamageOrHealing.DamageOut then
		if not tEvent.bDeflect then
			self.damageDone = self.damageDone + nAmount
			self.damaged[strTarget] = (self.damaged[strTarget] or 0) + nAmount
		end

		spell = self:GetSpell(self.damageOut, strSpellName)

	elseif tEvent.nTypeId == GM.eTypeDamageOrHealing.DamageIn then

		if not tEvent.bDeflect then
			self.damageTaken = self.damageTaken + nAmount
			self.damagedBy[strCaster] = (self.damagedBy[strCaster] or 0) + nAmount
		end

		local strCasterNameSpell = ("%s: %s"):format(strCaster, strSpellName)

		spell = self:GetSpell(self.damageIn, strCasterNameSpell)

	else
		self:Rover("UpdateSpell Error", tEvent)
		GM.Logger:error("Unknown type in UpdateSpell!")
		GM.Logger:error(format("Spell: %s, Caster: %s, Target: %s, Amount: %d",
			strSpellName, strCaster, strTarget, nAmount or 0))

		-- spell should be null here, safe to continue on...
	end

	if spell then
		GM:TallySpellAmount(tEvent, spell)
		GM:Dirty(true)
	end

end