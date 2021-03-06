-- ALl of this just for hands that match the player model.
-- And we'll include some misc. player stuff too.

local PLAYER = {}
PLAYER.DisplayName = "NutScript Player"

local modelList = {}

for k, v in pairs(player_manager.AllValidModels()) do
	modelList[string.lower(v)] = k
end

function PLAYER:SetupDataTables()
	self.Player:NetworkVar("Bool", 0, "NutWepRaised")

	if (SERVER and #player.GetAll() > 1) then
		netstream.Start(nil, "nut_PlayerDataTables")
	end
end

function PLAYER:GetHandsModel()
	local hands = nut.schema.Call("PlayerGetHandsModel", self.Player)

	if (hands) then
		return hands
	end

	local model = string.lower(self.Player:GetModel())

	for k, v in pairs(modelList) do
		if (string.find(string.gsub(model, "_", ""), v)) then
			model = v

			break
		end
	end

	return player_manager.TranslatePlayerHands(model)
end

local playerMeta = FindMetaTable("Player")

-- Weapon raising/lowering stuff.
do
	function playerMeta:WepRaised()
		if (CLIENT and self != LocalPlayer() and !self.GetNutWepRaised) then
			RunConsoleCommand("ns_sendplydt")
		end
		
		return self.GetNutWepRaised and self:GetNutWepRaised() or false
	end

	if (SERVER) then
		function playerMeta:SetWepRaised(raised, weapon)
			if (!IsValid(self) or !self.character) then
				return
			end

			self:SetNutWepRaised(raised)

			weapon = weapon or self:GetActiveWeapon()

			if (IsValid(weapon)) then
				local time = 9001

				if (weapon.FireWhenLowered or raised) then
					time = 0.8
				end

				weapon:SetNextPrimaryFire(CurTime() + time)
				weapon:SetNextSecondaryFire(CurTime() + time)
			end
		end

		hook.Add("PlayerSwitchWeapon", "nut_AutoLower", function(client, oldWeapon, newWeapon)
			client:DrawViewModel(newWeapon.DrawViewModel != false)

			if (!newWeapon.AlwaysRaised and !nut.config.alwaysRaised[newWeapon:GetClass()]) then
				client:SetWepRaised(false, newWeapon)

				-- Need this some some SWEPs can override the first time we set it to false.
				timer.Simple(0.5, function()
					if (!IsValid(client)) then
						return
					end

					client:SetWepRaised(false, newWeapon)
				end)
			else
				client:SetWepRaised(true, newWeapon)
			end
		end)

		concommand.Add("ns_sendplydt", function(client, command, arguments)
			if (#player.GetAll() < 2) then
				return
			end
			
			if (client:GetNutVar("nextUpdate", 0) < CurTime()) then
				netstream.Start(client, "nut_PlayerDataTables")

				client:SetNutVar("nextUpdate", CurTime() + 10)
			end
		end)
	else
		netstream.Hook("nut_PlayerDataTables", function(data)
			for k, v in pairs(player.GetAll()) do
				if (v != LocalPlayer() and !v.GetNutWepRaised) then
					player_manager.RunClass(v, "SetupDataTables")
				end
			end
		end)
	end
end

-- Player ragdoll.
do
	function playerMeta:IsPenetrating()
		local physicsObject = self:GetPhysicsObject()
		local position = self:GetPos()
		local entities = ents.FindInBox(position + Vector(-32, -32, 0), position + Vector(32, 32, 84))

		for k, v in pairs(entities) do
			if ((self.ragdoll and self.ragdoll == v) or v == self) then
				continue
			end
			
			if (string.find(v:GetClass(), "prop_") or v:IsPlayer() or v:IsNPC()) then
				return true
			end
		end

		if (IsValid(physicsObject)) then
			return physicsObject:IsPenetrating()
		end

		return true
	end

	if (SERVER) then
		function playerMeta:ForceRagdoll()
			self.ragdoll = ents.Create("prop_ragdoll")
			self.ragdoll:SetModel(self:GetModel())
			self.ragdoll:SetPos(self:GetPos())
			self.ragdoll:SetAngles(self:GetAngles())
			self.ragdoll:SetSkin(self:GetSkin())
			self.ragdoll:SetColor(self:GetColor())
			self.ragdoll:Spawn()
			self.ragdoll:Activate()
			self.ragdoll:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			self.ragdoll.player = self
			self.ragdoll:CallOnRemove("RestorePlayer", function()
				if (IsValid(self)) then
					self:UnRagdoll()
				end
			end)
			self.ragdoll.grace = CurTime() + 1

			for i = 0, self.ragdoll:GetPhysicsObjectCount() do
				local physicsObject = self.ragdoll:GetPhysicsObjectNum(i)

				if (IsValid(physicsObject)) then
					physicsObject:SetVelocity(self:GetVelocity() * 1.25)
				end
			end

			local weapons = {}

			for k, v in pairs(self:GetWeapons()) do
				weapons[#weapons + 1] = v:GetClass()
			end

			self:SetNutVar("weapons", weapons)
			self:StripWeapons()
			self:Freeze(true)
			self:SetNetVar("ragdoll", self.ragdoll:EntIndex())
			self:SetNoDraw(true)

			local uniqueID = "nut_RagSafePos"..self:EntIndex()

			timer.Create(uniqueID, 0.33, 0, function()
				if (!IsValid(self) or !IsValid(self.ragdoll)) then
					if (IsValid(self.ragdoll)) then
						self.ragdoll:Remove()
					end

					timer.Remove(uniqueID)

					return
				end

				local position = self:GetPos()

				if (self:GetNutVar("lastPos",position) != position and !self:IsPenetrating() and self:IsInWorld()) then
					self:SetNutVar("lastPos", position)
				end

				self:SetPos(self.ragdoll:GetPos())
			end)
		end

		function playerMeta:UnRagdoll(samePos)
			if (self:GetNetVar("ragdoll") == 0) then
				return
			end
			
			local isValid = IsValid(self.ragdoll)
			local position = self:GetNutVar("lastPos")

			if (samePos and isValid) then
				self:SetPos(self.ragdoll:GetPos())
			elseif (position) then
				self:SetPos(position)
			end

			self:SetMoveType(MOVETYPE_WALK)
			self:SetCollisionGroup(COLLISION_GROUP_PLAYER)
			self:Freeze(false)
			self:SetNoDraw(false)
			self:SetNetVar("ragdoll", 0)
			self:DropToFloor()
			self:SetMainBar()
			self:SetNutVar("lastPos", nil)

			if (isValid) then
				local physicsObject = self.ragdoll:GetPhysicsObject()

				if (IsValid(physicsObject)) then
					self:SetVelocity(physicsObject:GetVelocity())
				end
			end

			for k, v in pairs(self:GetNutVar("weapons", {})) do
				self:Give(v)
			end

			self:SetNutVar("weapons", nil)

			if (isValid) then
				self.ragdoll:Remove()
			end

			timer.Remove("nut_RagTime"..self:EntIndex())
		end

		function playerMeta:SetTimedRagdoll(time)
			local suffix = "s"

			if (time == 1) then
				suffix = ""
			end

			self:ForceRagdoll()

			if (time > 0) then
				self:SetMainBar("You are regaining conciousness.", time)

				timer.Create("nut_RagTime"..self:EntIndex(), time, 1, function()
					if (IsValid(self)) then
						self:UnRagdoll()
					end
				end)
			end
		end

		hook.Add("PlayerDeath", "nut_UnRagdoll", function(client)
			client:UnRagdoll(true)
		end)

		hook.Add("EntityTakeDamage", "nut_FallenOver", function(entity, damageInfo)
			if (IsValid(entity.player) and (entity.grace or 0) < CurTime()) then
				entity.player:TakeDamageInfo(damageInfo)
			end
		end)
	else
		hook.Add("CalcView", "nut_RagdollView", function(client, origin, angles, fov)
			local entIndex = client:GetNetVar("ragdoll")

			if (entIndex and entIndex > 0) then
				local entity = Entity(entIndex)

				if (IsValid(entity)) then
					local index = entity:LookupAttachment("eyes")
					local attachment = entity:GetAttachment(index)

					local view = {}
						view.origin = attachment.Pos
						view.angles = attachment.Ang
					return view
				end
			end
		end)
	end

	hook.Add("ShouldCollide", "nut_RagdollPlayer", function(entity, entity2)
		if (entity:IsPlayer() and entity:GetNetVar("ragdoll", 0) != 0 and !entity2:IsWorld()) then
			return false
		end
	end)
end

-- Player nut variable accessors.
do
	function playerMeta:SetNutVar(key, value)
		self.nut = self.nut or {}
		self.nut[key] = value
	end

	function playerMeta:GetNutVar(key, default)
		self.nut = self.nut or {}

		return self.nut[key] or default
	end
end

player_manager.RegisterClass("player_nut", PLAYER, "player_default")