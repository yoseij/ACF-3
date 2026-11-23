local ACF  = ACF
local Fuel = ACF.Mobility.Fuel or {}

ACF.Mobility.Fuel = Fuel

-- Engines draw from the fuel tanks linked to them, lowest priority value first

--- Flags an engine that has no tank linked while the server requires fuel.
function Fuel.Refresh(Engine)
	local Missing = ACF.RequireFuel and not next(Engine.ACF_LiveData.FuelTanks)

	Engine:SetRequirement("engine_no_fuel", not Missing)
end

--- Drops cached tanks of engines that should now prefer this tank.
function Fuel.Notify(Tank)
	local Priority = Tank.FuelPriority

	for Engine in pairs(Tank.Engines) do
		local Current = Engine.FuelTank

		if Current and Current ~= Tank and Priority < Current.FuelPriority then
			Engine.FuelTank = nil
		end
	end
end
