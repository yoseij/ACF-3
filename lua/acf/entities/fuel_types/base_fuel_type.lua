local Classes = ACF.Classes

local POOL_DEPTH    = 0.005 -- m, spilled fuel spreads out to this depth, which sets how much of it burns at once
local POOL_MAX_AREA = 2 -- m², a hull floor can't hold a wider spill

Classes.DefineClass("ACF.FuelTypes.FuelType", function(CLASS)
    CLASS.ID          = "FuelType"
    CLASS.Name        = "Fuel Type"
    CLASS.Density     = 0.832 -- kg per liter (or kg per kWh for electric)
    CLASS.IsElectric  = false

    -- Fire
    CLASS.CanSelfSeal      = true -- Whether tanks can have a self-sealing liner
    CLASS.BurnRate         = 0.04 -- kg/m²/s off a large spill (Babrauskas large-pool burning rates)
    CLASS.HeatOfCombustion = 44e6 -- J/kg
    CLASS.CanFireball      = false -- Whether a ruptured, lit tank flashes over
    CLASS.IgnitionChance   = {} -- Chance per Hit, Jet or Fire (see ACF.Damage.Fire.GetIgnitionSource); Fire and HotSurface are per second when sustained

    --- @return vector # Inside size of a tank left for fuel once any liner is in.
    function CLASS:GetFuelSpace(Size, SelfSealing)
        if not SelfSealing or not self.CanSelfSeal then return Size end

        return Size - Vector(2, 2, 2) * ACF.FuelSealLiner
    end

    --- @return number # Liters per second escaping the tank's holes.
    function CLASS:GetLeakRate(Tank)
        return Tank:GetOrificeFlow()
    end

    --- Lets fuel out of the tank into the spill around it, which is what actually burns.
    function CLASS:Release(Tank, Liters)
        Tank:Spill(Liters)
    end

    --- @return number # Liters a rupture sprays out to flash over when lit.
    function CLASS:GetFlashAmount(Tank)
        return self.CanFireball and Tank.Amount * ACF.FuelFireballFraction or 0
    end

    --- @return boolean # Whether fuel is out in the open, where flames can reach it.
    function CLASS:IsExposed(Tank)
        return Tank.Leaking > 0 or Tank.Spilled > 0
    end

    --- @return boolean # Whether a tank of this fuel has anything that can burn right now.
    function CLASS:CanBurn(Tank)
        return self:IsExposed(Tank) -- Only spilled fuel burns
    end

    --- Subtypes also get the fraction of the tank the hit destroyed.
    --- @return number # Chance a hit from Source lights the fuel.
    function CLASS:GetIgnitionChance(Source)
        return self.IgnitionChance[Source] or 0
    end

    --- Burns a tank's spill across its whole surface, so a small one burns slower and dies down as it shrinks.
    --- @return number|nil # Heat released in watts, nil once there's nothing left to burn.
    function CLASS:Burn(Tank, DeltaTime)
        local Spilled = Tank.Spilled

        if Spilled <= 0 then
            if Tank.Leaking > 0 then return 0 end -- More is on its way

            return
        end

        local Volume = Spilled / (self.Density * 1000) -- m³
        local Area   = math.min(Volume / POOL_DEPTH, POOL_MAX_AREA)
        local Burnt  = math.min(Spilled, self.BurnRate * ACF.FuelBurnRateMult * Area * DeltaTime)

        Tank.Spilled = Spilled - Burnt

        return Burnt * self.HeatOfCombustion / DeltaTime
    end

    -- Optional display hooks (overridden by subtypes, e.g. Electric):
    --   CLASS.ConsumptionText(PeakkW, _, Efficiency) -> string
    --   CLASS.FuelTankText(Capacity, Mass[, EmptyMass]) -> string
    --   CLASS.FuelTankOverlay(Fuel, State)
end)
