local hook        = hook
local ACF         = ACF
local Contraption = ACF.Contraption


function ACF.KEShove(Target, Pos, Vec, KE)
	if not IsValid(Target) then return end
	if Target.ACF_Killed then return end

	if not hook.Run("ACF_OnPushEntity", Target, Pos, Vec, KE) then return end

	local Ancestor = Target:GetAncestor()

	if not IsValid(Ancestor) then
		Ancestor = Target
	end

	local Phys = Ancestor:GetPhysicsObject()

	if IsValid(Phys) then
		local Count    = Contraption.UpdateMassRatio(Ancestor)
		local Ratio    = Count.ACF_PhysicalMass / Count.ACF_TotalMass
		local LocalPos = Ancestor:WorldToLocal(Pos) * Ratio

		if KE ~= KE then
			local ErrorText = "Congratulations, you've just found a bug on ACF. Report this to the developer team.\nAffected entity"
			ErrorNoHaltWithStack(ErrorText, Target, Ancestor)

			return
		end

		Phys:ApplyForceOffset(Vec:GetNormalized() * KE * Ratio, Ancestor:LocalToWorld(LocalPos))
	end
end
