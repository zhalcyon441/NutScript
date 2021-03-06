AddCSLuaFile()

if (CLIENT) then
	SWEP.PrintName = "Fists"
	SWEP.Slot = 1
	SWEP.SlotPos = 1
	SWEP.DrawAmmo = false
	SWEP.DrawCrosshair = false
end

SWEP.Author = "Chessnut"
SWEP.Instructions = "Primary Fire: [RAISED] Punch\nSecondary Fire: Knock/Pickup"
SWEP.Purpose = "Hitting things and knocking on doors."
SWEP.Drop = false

SWEP.ViewModelFOV = 36
SWEP.ViewModelFlip = false
SWEP.AnimPrefix	 = "rpg"

SWEP.ViewTranslation = 4

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = ""
SWEP.Primary.Damage = 5
SWEP.Primary.Delay = 0.75

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = 0
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = ""

SWEP.ViewModel = Model("models/weapons/v_fists.mdl")
SWEP.WorldModel = ""

SWEP.UseHands = true
SWEP.LowerAngles = Angle(0, 5, -20)

SWEP.FireWhenLowered = true

function SWEP:PreDrawViewModel(viewModel, weapon, client)
	local hands = player_manager.RunClass(client, "GetHandsModel")

	if (hands and hands.model) then
		viewModel:SetModel(hands.model)
	end
end

ACT_VM_FISTS_DRAW = 3
ACT_VM_FISTS_HOLSTER = 2

function SWEP:Deploy()
	if ( !IsValid(self.Owner) ) then
		return
	end

	local viewModel = self.Owner:GetViewModel()

	if ( IsValid(viewModel) ) then
		viewModel:SetPlaybackRate(0.5)
		viewModel:ResetSequence(ACT_VM_FISTS_DRAW)
	end

	return true
end

function SWEP:Holster()
	if ( !IsValid(self.Owner) ) then
		return
	end

	local viewModel = self.Owner:GetViewModel()

	if ( IsValid(viewModel) ) then
		viewModel:SetPlaybackRate(0.5)
		viewModel:ResetSequence(ACT_VM_FISTS_HOLSTER)
	end

	return true
end

function SWEP:Precache()
	util.PrecacheSound("npc/vort/claw_swing1.wav")
	util.PrecacheSound("npc/vort/claw_swing2.wav")
	util.PrecacheSound("physics/plastic/plastic_box_impact_hard1.wav")	
	util.PrecacheSound("physics/plastic/plastic_box_impact_hard2.wav")	
	util.PrecacheSound("physics/plastic/plastic_box_impact_hard3.wav")	
	util.PrecacheSound("physics/plastic/plastic_box_impact_hard4.wav")	
end

function SWEP:Initialize()
	self:SetWeaponHoldType("fist")
	self.LastHand = 0
end

function SWEP:DoPunchAnimation()
	self.LastHand = math.abs(1 - self.LastHand)

	local sequence = 4 + self.LastHand
	local viewModel = self.Owner:GetViewModel()

	if ( IsValid(viewModel) ) then
		viewModel:SetPlaybackRate(0.525)
		viewModel:SetSequence(sequence)
	end
end

function SWEP:PrimaryAttack()	
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

	if (!self.Owner:WepRaised()) then
		return
	end

	self:EmitSound("npc/vort/claw_swing"..math.random(1, 2)..".wav")

	local damage = self.Primary.Damage

	self:DoPunchAnimation()

	self.Owner:SetAnimation(PLAYER_ATTACK1)
	self.Owner:ViewPunch( Angle(self.LastHand + 2, self.LastHand + 5, 0.125) )

	timer.Simple(0.085, function()
		if (IsValid(self) and IsValid(self.Owner)) then
			local data = {}
				data.start = self.Owner:GetShootPos()
				data.endpos = data.start + self.Owner:GetAimVector() * 72
				data.filter = self.Owner
			local trace = util.TraceLine(data)

			if (self.Owner:GetPos():Distance(trace.HitPos or vector_origin) >= 108) then
				return
			end
			
			local shoot = false

			if (trace.Hit) then
				if ( IsValid(trace.Entity) ) then
					if ( trace.Entity:IsPlayer() ) then
						shoot = true
					end

					local class = string.lower( trace.Entity:GetClass() )

					if ( string.find(class, "breakable") ) then
						shoot = true
					end
				end
			end

			if (shoot) then
				local damage = self.Primary.Damage
				local result = nut.schema.Call("PlayerGetFistDamage", self.Owner, damage)

				if (result != nil) then
					damage = result
				end

				local bullet = {}
				bullet.Num = 1
				bullet.Src = self.Owner:GetShootPos()
				bullet.Dir = self.Owner:GetAimVector()
				bullet.Spread = Vector(0, 0, 0)
				bullet.Tracer = 0
				bullet.Force = 5
				bullet.Damage = damage

				self.Owner:FireBullets(bullet)
			elseif ( IsValid(trace.Entity) ) then
				if ( IsValid( trace.Entity:GetPhysicsObject() ) ) then
					trace.Entity:GetPhysicsObject():ApplyForceOffset(self.Owner:GetAimVector() * 500, trace.HitPos)
				end
			end

			nut.schema.Call("PlayerThrowPunch", self.Owner, shoot)
		end
	end)
end

function SWEP:CanCarry(entity)
	local physicsObject = entity:GetPhysicsObject()

	if (!IsValid(physicsObject)) then
		return false
	end

	if (physicsObject:GetMass() > 100 or !physicsObject:IsMoveable()) then
		return false
	end

	if (IsValid(entity.carrier)) then
		return false
	end

	return true
end

function SWEP:DoPickup(entity)
	if (entity:IsPlayerHolding()) then
		return
	end

	timer.Simple(FrameTime() * 10, function()
		if (!IsValid(entity) or entity:IsPlayerHolding()) then
			return
		end

		self.Owner:PickupObject(entity)
	end)

	self:SetNextSecondaryFire(CurTime() + 1)
end

function SWEP:SecondaryAttack()
	local trace = self.Owner:GetEyeTraceNoCursor()
	local entity = trace.Entity

	if (SERVER and IsValid(entity)) then
		local distance = self.Owner:EyePos():Distance(trace.HitPos)

		if (distance > 72) then
			return
		end

		if (string.find(entity:GetClass(), "door")) then
			if (nut.schema.Call("PlayerCanKnock", self.Owner, entity) == false) then
				return
			end

			self.Owner:ViewPunch( Angle(-1.3, 1.8, 0) )
			self.Owner:EmitSound("physics/plastic/plastic_box_impact_hard"..math.random(1, 4)..".wav")	
			self.Owner:SetAnimation(PLAYER_ATTACK1)

			self:DoPunchAnimation()
			self:SetNextSecondaryFire(CurTime() + 0.4)
			self:SetNextPrimaryFire(CurTime() + 1)
		elseif (!entity:IsPlayer() and !entity:IsNPC() and self:CanCarry(entity)) then
			self:DoPickup(entity)
		end
	end
end