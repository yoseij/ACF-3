local RecacheBindOutput = ENT.RecacheBindOutput
local GetBindState = ENT.GetBindState

local function Init(Entity)
	Entity.GearboxEnds          = {}   -- Gearboxes connected to a wheel
	Entity.GearboxIntermediates = {}   -- Or otherwise
	Entity.Reversers            = {}   -- Gearboxes below the main one that reverse the wheels on gear 2
	Entity.DriveGearboxes       = {}   -- Gearboxes the controller shifts between neutral, forward and reverse
	Entity.Wheels               = {}   -- Wheels
	Entity.Engines              = {}   -- Engines
	-- End gearboxes driving left wheels, each with the set of its outputs that do
	Entity.LeftGearboxes        = {}
	Entity.RightGearboxes       = {}   -- Same for the right wheels
	Entity.LeftWheels           = {}   -- Wheels connected to the left drive wheel
	Entity.RightWheels          = {}   -- Wheels connected to the right drive wheel
	Entity.DoubleDiffs          = {}   -- Double differentials splitting left from right, each with the sign of Steer Rate that slows its left side
	Entity.ControllerWelds      = {}   -- Keep track of the welds we created
	Entity.SteerPlatesSorted    = {}   -- Steer plates sorted by their position
	Entity.SteerPhysicsObjects  = {}   -- Steering physics objects
	Entity.SteerAngles          = {}   -- Steering angles for the steer plates
	Entity.SteerPercents        = {}   -- The four steer shares, read into it each steering update
	Entity.GearboxEndCount      = 1    -- Number of endpoint gearboxes
	Entity.Speed                = 0
end

-- Drivetrain related
do
	local CLUTCH_FLOW = 0
	local CLUTCH_BLOCK = 1
	local PARK_GRACE = 0.15 -- s with no key held before parking; changing keys leaves a tick or two with none
	local UNSIDED = "" -- Side of a single-output gearbox, whose only inputs are the unsided ones
	local OUTPUT_FIELDS = { "Wheels", "GearboxOut" } -- A gearbox's links to what it drives

	--- Finds the components of the drive train
	--- Input is the "main" gearbox of the drivetrain
	--- returns multiple arrays, one for Wheels, engines, wheel gearboxes and intermediate gearboxes
	--- This should be enough for general use, obviously it can't cover every edge case.
	local function DiscoverDriveTrain(Target)
		local Queued  = { [Target] = true }
		local Checked = {}
		local Current, Class, Sources

		local Wheels, Engines, Ends, Intermediates = {}, {}, {}, {}

		while next(Queued) do
			Current = next(Queued)
			Class   = Current:GetClass()
			Sources = ACF.GetAllLinkSources(Class)

			Queued[Current] = nil
			Checked[Current] = true

			if Class == "acf_engine" then
				Engines[Current] = true
			elseif Class == "acf_gearbox" then
				if Sources.Wheels and next(Sources.Wheels(Current)) then Ends[Current] = true else Intermediates[Current] = true end
			elseif Class == "prop_physics" then
				Wheels[Current] = true
			end

			for Name, Action in pairs(Sources) do
				if Name == "FuelTanks" then continue end -- A shared tank would pull in unrelated engines

				for Entity in pairs(Action(Current)) do
					if not (Checked[Entity] or Queued[Entity]) then
						Queued[Entity] = true
					end
				end
			end
		end
		return Wheels, Engines, Ends, Intermediates
	end

	-- Automatics take gear 2 as reverse and shift into their last gear for it
	local function CanReverse(Gearbox)
		local Gears = Gearbox.Gears
		local Reverse = Gearbox.Automatic and Gears[Gearbox.GearCount] or Gears[2]

		return Gears[1] ~= nil and Reverse ~= nil and Gears[1] * Reverse < 0
	end

	--- Finds the reversing gearboxes below the main one that shift for reverse: the first one on each path
	--- down to the wheels. Wheels that no reverser turns would keep going forward, and two in series cancel
	--- out, so unless every path holds exactly one, none is used and the main gearbox reverses on its own
	--- reverse gear.
	local function DiscoverReversers(MainGearbox)
		local Reversers = {}
		local Queue, Seen = { MainGearbox }, { [MainGearbox] = true }

		while #Queue > 0 do
			local Current = table.remove(Queue)

			for Wheel in pairs(Current:ACF_GetUserVar("Wheels") or {}) do
				if IsValid(Wheel) then return {} end
			end

			for Gearbox in pairs(Current:ACF_GetUserVar("GearboxOut") or {}) do
				if IsValid(Gearbox) and not Seen[Gearbox] then
					Seen[Gearbox] = true

					if CanReverse(Gearbox) then Reversers[Gearbox] = true else Queue[#Queue + 1] = Gearbox end
				end
			end
		end

		for Reverser in pairs(Reversers) do
			local Below, Checked = { Reverser }, { [Reverser] = true }

			while #Below > 0 do
				for Gearbox in pairs(table.remove(Below):ACF_GetUserVar("GearboxOut") or {}) do
					if Reversers[Gearbox] then return {} end

					if IsValid(Gearbox) and not Checked[Gearbox] then
						Checked[Gearbox] = true
						Below[#Below + 1] = Gearbox
					end
				end
			end
		end

		return Reversers
	end

	--- Finds the "side" of the gearbox that the wheel is connected to. This corresponds to the wire inputs.
	local function GetLROutput(Gearbox, Wheel)
		local lp = Gearbox:GetAttachment(Gearbox:LookupAttachment("driveshaftL")).Pos
		local rp = Gearbox:GetAttachment(Gearbox:LookupAttachment("driveshaftR")).Pos
		local d1 = Wheel:GetPos():Distance(lp or Vector())
		local d2 = Wheel:GetPos():Distance(rp or Vector())
		if d1 < d2 then return "Left" else return "Right" end
	end

	--- Creates/Removes weld constraints from the Left/Right Wheels to baseplate or between them.
	local function SetLatches(SelfTbl, Engage)
		if SelfTbl:GetDisableWeldBrake() == 1 then return end
		for Wheel in pairs(SelfTbl.Wheels) do
			local AlreadyHasWeld = SelfTbl.ControllerWelds[Wheel]
			if Engage and not AlreadyHasWeld then
				SelfTbl.ControllerWelds[Wheel] = constraint.Weld(SelfTbl.ACF_LiveData.Baseplate, Wheel, 0, 0, 0, true, true)
			elseif not Engage and AlreadyHasWeld then
				SelfTbl.ControllerWelds[Wheel]:Remove()
				SelfTbl.ControllerWelds[Wheel] = nil
			end
		end
	end

	-- Sets an input for an entity, if it exists and the value has changed since last time.
	local function TriggerSafe(SelfTbl, Entity, Name, Value)
		if not IsValid(Entity) then return end
		-- A dual clutch gearbox has no unsided Brake, say
		if Entity.Inputs and not Entity.Inputs[Name] then return end
		if not SelfTbl.LastInputs then SelfTbl.LastInputs = {} end
		if not SelfTbl.LastInputs[Entity] then SelfTbl.LastInputs[Entity] = {} end
		if SelfTbl.LastInputs[Entity][Name] ~= Value then
			SelfTbl.LastInputs[Entity][Name] = Value
			Entity:TriggerInput(Name, Value)
		end
	end

	local function SetAll(SelfTbl, TblName, Name, Value)
		for Entity in pairs(SelfTbl[TblName]) do TriggerSafe(SelfTbl, Entity, Name, Value) end
	end

	-- Puts the drive gearboxes in neutral (0), forward (1) or reverse (2). Those that can't reverse stay
	-- forward, since gear 2 would be another forward gear or clamp back to 1 on them
	local function SetDriveGear(SelfTbl, Drive, SkipEnds)
		for Gearbox in pairs(SelfTbl.DriveGearboxes) do
			if not (SkipEnds and SelfTbl.GearboxEnds[Gearbox]) then
				TriggerSafe(SelfTbl, Gearbox, "Gear",
					(Drive == 2 and not SelfTbl.Reversers[Gearbox]) and 1 or Drive)
			end
		end
	end

	-- Sets an input on one side's end gearboxes: on each of their outputs driving that side, or once on the
	-- whole gearbox
	local function SetSide(SelfTbl, Gearboxes, Name, Value, NotSided)
		for Gearbox, Outputs in pairs(Gearboxes) do
			if NotSided then
				TriggerSafe(SelfTbl, Gearbox, Name, Value)
			else
				for Output in pairs(Outputs) do
					TriggerSafe(SelfTbl, Gearbox, Output == UNSIDED and Name or Output .. " " .. Name, Value)
				end
			end
		end
	end

	local function SetLeft(SelfTbl, Name, Value, NotSided)
		SetSide(SelfTbl, SelfTbl.LeftGearboxes, Name, Value, NotSided)
	end

	local function SetRight(SelfTbl, Name, Value, NotSided)
		SetSide(SelfTbl, SelfTbl.RightGearboxes, Name, Value, NotSided)
	end

	-- Positive turns left
	local function SetDoubleDiffs(SelfTbl, Rate)
		for Gearbox, Sign in pairs(SelfTbl.DoubleDiffs) do TriggerSafe(SelfTbl, Gearbox, "Steer Rate", Rate * Sign) end
	end

	-- Whether a gearbox output's target is, or drives, one of the given wheels
	local function DrivesAny(Target, Wheels)
		local Queue, Seen = { Target }, { [Target] = true }

		while #Queue > 0 do
			local Current = table.remove(Queue)

			if Wheels[Current] then return true end

			if Current:GetClass() == "acf_gearbox" then
				for _, Field in ipairs(OUTPUT_FIELDS) do
					for Next in pairs(Current:ACF_GetUserVar(Field) or {}) do
						if IsValid(Next) and not Seen[Next] then
							Seen[Next] = true
							Queue[#Queue + 1] = Next
						end
					end
				end
			end
		end

		return false
	end

	-- Steer Rate slows a double differential's side 0 when negative and side 1 when positive, and the side of a link
	-- comes from where its target sits, so which one is left is read from the links. Nil unless one side drives
	-- only left wheels and the other only right ones.
	local function GetDoubleDiffSign(Gearbox, LeftWheels, RightWheels)
		local LeftSide, RightSide

		for _, Field in ipairs(OUTPUT_FIELDS) do
			for Target, Link in pairs(Gearbox:ACF_GetUserVar(Field) or {}) do
				if IsValid(Target) and istable(Link) and Link.Side then
					local Left, Right = DrivesAny(Target, LeftWheels), DrivesAny(Target, RightWheels)

					if Left == Right then return end
					if Left then
						if LeftSide and LeftSide ~= Link.Side then return end
						LeftSide = Link.Side
					else
						if RightSide and RightSide ~= Link.Side then return end
						RightSide = Link.Side
					end
				end
			end
		end

		if LeftSide == nil or LeftSide == RightSide then return end

		return LeftSide == 1 and 1 or -1
	end

	-- Steer Rate at this speed: 0.5 stops the inner side
	local function GetDoubleDiffRate(Entity, Speed)
		local Low, Top = Entity:GetDoubleDiffSteerLow(), Entity:GetDoubleDiffSteerTop()
		local MinSpeed, MaxSpeed = Entity:GetSpeedLow(), Entity:GetSpeedTop()

		if MinSpeed == MaxSpeed then return Low end

		return math.Clamp(math.Remap(Speed, MinSpeed, MaxSpeed, Low, Top), math.min(Low, Top), math.max(Low, Top))
	end

	-- m, half the wheel's span across its axle: of a wheel's three sizes the middle one is its diameter
	local function GetWheelRadius(Wheel)
		local Size  = Wheel:OBBMaxs() - Wheel:OBBMins()
		local Sizes = { Size.x, Size.y, Size.z }

		table.sort(Sizes)

		return 0.5 * Sizes[2] * ACF.InchToMeter
	end

	-- Brake Strength is a percentage of what locks every wheel at full tyre grip (friction caps at 1) with
	-- the vehicle's full weight on its linked wheels, the largest of them setting the lever; gearbox brakes
	-- take N·m
	local function UpdateBrakeScale(SelfTbl)
		local Baseplate     = SelfTbl.ACF_LiveData.Baseplate
		local Radius, Count = 0, 0

		-- Measured once per analysis, which gives the wheels a new table
		if SelfTbl.RadiusFor ~= SelfTbl.Wheels then SelfTbl.RadiusFor, SelfTbl.RadiusOf = SelfTbl.Wheels, {} end

		local RadiusOf = SelfTbl.RadiusOf

		for Wheel in pairs(SelfTbl.Wheels) do
			if IsValid(Wheel) then
				local Own = RadiusOf[Wheel] or GetWheelRadius(Wheel)

				RadiusOf[Wheel] = Own
				Radius          = math.max(Radius, Own)
				Count           = Count + 1
			end
		end

		if Count == 0 or not IsValid(Baseplate) then
			SelfTbl.BrakeScale = 0

			return
		end

		local Mass    = ACF.Contraption.UpdateMassRatio(Baseplate).ACF_TotalMass
			or Baseplate:GetPhysicsObject():GetMass()
		local Gravity = physenv.GetGravity():Length() * ACF.InchToMeter

		SelfTbl.BrakeScale = Mass * Gravity * Radius / (Count * 100)
	end

	-- N·m on each wheel, from a Brake Strength in the unit the controller is set to
	local function GetBrakeTorque(Entity, SelfTbl, BrakeStrength)
		if Entity:GetBrakeUnit() == 1 then return BrakeStrength end
		if not SelfTbl.BrakeScale then UpdateBrakeScale(SelfTbl) end

		return BrakeStrength * SelfTbl.BrakeScale
	end

	-- Locks or releases the brake on both sides. When locking, also blocks the clutches and engages the weld latches
	local function SetParkingBrake(SelfTbl, State, Torque)
		Torque = State and Torque or 0

		SetLeft(SelfTbl, "Brake", Torque) SetRight(SelfTbl, "Brake", Torque)
		-- Differentials HAVE TO BE DIFFERENT
		SetLeft(SelfTbl, "Brake", Torque, true) SetRight(SelfTbl, "Brake", Torque, true)

		if State then
			SetLeft(SelfTbl, "Clutch", CLUTCH_BLOCK) SetRight(SelfTbl, "Clutch", CLUTCH_BLOCK)
			SetLatches(SelfTbl, true)
		end
	end

	--- Steer a plate left or right
	local function SetSteerPlate(SelfTbl, BasePlate, SteerPlate, TURN_ANGLE, TURN_RATE)
		local TURN = SelfTbl.SteerAngles[SteerPlate] or 0
		TURN = TURN + math.Clamp(TURN_ANGLE - TURN, -TURN_RATE, TURN_RATE)
		SelfTbl.SteerAngles[SteerPlate] = TURN
		SteerPlate:SetAngles(BasePlate:LocalToWorldAngles(Angle(0, TURN, 0)))
	end

	--- Intentionally Supported drivetrains:
	--- Single Transaxial gearbox with dual clutch -> basic ww2 style
	--- Single Transaxial gearbox with transfers -> basic neutral steer style
	--- Main gearbox with transfers to wheels -> basic wheeled
	function ENT:AnalyzeDrivetrain(MainGearbox)
		-- Need a list of all linked wheels
		if not IsValid(MainGearbox) then return end

		local baseplate = self:ACF_GetUserVar("Baseplate")
		if not baseplate then return end

		-- What this analysis was made from, so RefreshDrivetrain can tell when it goes stale
		self.AnalyzedGearbox, self.AnalyzedBaseplate, self.AnalyzedGears = MainGearbox, baseplate, MainGearbox.Gears

		-- Recalculate the drive train components
		self.Wheels, self.Engines, self.GearboxEnds, self.GearboxIntermediates = DiscoverDriveTrain(MainGearbox)

		-- A reconfigure builds a new gear table, which is how RefreshDrivetrain notices a gearbox below the
		-- main one changed
		self.AnalyzedBoxGears = {}
		for Gearbox in pairs(self.GearboxEnds) do self.AnalyzedBoxGears[Gearbox] = Gearbox.Gears end
		for Gearbox in pairs(self.GearboxIntermediates) do self.AnalyzedBoxGears[Gearbox] = Gearbox.Gears end
		self.SteerPlatesSorted = {}

		self.GearboxEndCount = table.Count(self.GearboxEnds)

		-- Process gears
		local ForwardGears = {}
		local ReverseGears = {}
		for Index, Ratio in ipairs(MainGearbox.Gears) do
			if Ratio > 0 then table.insert(ForwardGears, Index) elseif Ratio < 0 then table.insert(ReverseGears, Index) end -- A 0 gear drives neither way
		end
		table.sort(ForwardGears, function(A, B) return MainGearbox.Gears[A] < MainGearbox.Gears[B] end)
		table.sort(ReverseGears, function(A, B) return MainGearbox.Gears[A] > MainGearbox.Gears[B] end)

		self.ForwardGears, self.ReverseGears = ForwardGears, ReverseGears
		self.MainReverses = ReverseGears[1] ~= nil

		-- Gear 2 is their reverse whatever its sign, so it may not reverse at all
		if MainGearbox.Automatic or MainGearbox.CVT then
			self.ForwardGears, self.ReverseGears = {1}, {2}
			self.MainReverses = CanReverse(MainGearbox)
		end

		-- Determine the Left/Right wheels assuming the vehicle is built north
		local LeftWheels, RightWheels = {}, {}
		local avg, count = 0, 0
		for Wheel in pairs(self.Wheels) do
			avg, count = avg + baseplate:WorldToLocal(Wheel:GetPos()).y, count + 1
		end
		avg = avg / count

		for Wheel in pairs(self.Wheels) do
			if baseplate:WorldToLocal(Wheel:GetPos()).y > avg then LeftWheels[Wheel] = true else RightWheels[Wheel] = true end
		end
		self.LeftWheels, self.RightWheels = LeftWheels, RightWheels

		-- Each side's end gearboxes, with the outputs that drive that side: a dual clutch gearbox brakes and
		-- declutches each output on its own, any other gearbox as a whole
		local GetWheels = ACF.GetAllLinkSources("acf_gearbox").Wheels
		local LeftGearboxes, RightGearboxes = {}, {}
		for Gearbox in pairs(self.GearboxEnds) do
			for Wheel in pairs(GetWheels(Gearbox)) do
				local Side = LeftWheels[Wheel] and LeftGearboxes or RightWheels[Wheel] and RightGearboxes

				if Side then
					Side[Gearbox] = Side[Gearbox] or {}
					Side[Gearbox][Gearbox.DualClutch and GetLROutput(Gearbox, Wheel) or UNSIDED] = true
				end
			end

			-- A whole gearbox driving both sides can't steer them; it only takes the unsided inputs, such as
			-- parking
			if not Gearbox.DualClutch and LeftGearboxes[Gearbox] and RightGearboxes[Gearbox] then
				LeftGearboxes[Gearbox], RightGearboxes[Gearbox] = {}, {}
			end
		end
		self.LeftGearboxes, self.RightGearboxes = LeftGearboxes, RightGearboxes

		-- Those no longer steered would keep the last rate they were given
		for Gearbox in pairs(self.DoubleDiffs) do
			if IsValid(Gearbox) then Gearbox:TriggerInput("Steer Rate", 0) end
		end

		local DoubleDiffs = {}
		for _, Gearboxes in ipairs({ self.GearboxEnds, self.GearboxIntermediates }) do
			for Gearbox in pairs(Gearboxes) do
				if Gearbox.DoubleDiff then DoubleDiffs[Gearbox] = GetDoubleDiffSign(Gearbox, LeftWheels, RightWheels) end
			end
		end
		self.DoubleDiffs = DoubleDiffs

		for v in pairs(self:ACF_GetUserVar("SteerPlates")) do
			local PhysObj = v:GetPhysicsObject()
			if IsValid(PhysObj) then PhysObj:EnableGravity(false) end
			self.SteerPlatesSorted[#self.SteerPlatesSorted + 1] = v
		end

		table.sort(self.SteerPlatesSorted, function(A, B)
			return baseplate:WorldToLocal(A:GetPos()).x > baseplate:WorldToLocal(B:GetPos()).x
		end)

		self.CanSteer = #self.SteerPlatesSorted > 0 -- Steer if there are any steer plates

		-- Without a reversing gearbox below it, the main gearbox reverses on its own reverse gear
		self.Reversers = DiscoverReversers(MainGearbox)

		-- The main gearbox is left to the shifter, which a neutral or reverse here would fight
		local DriveGearboxes = {}
		for Gearbox in pairs(self.GearboxEnds) do DriveGearboxes[Gearbox] = true end
		for Gearbox in pairs(self.Reversers) do DriveGearboxes[Gearbox] = true end
		DriveGearboxes[MainGearbox] = nil

		-- Those still in the drivetrain but no longer shifted would keep the neutral or reverse they were
		-- last given
		for Gearbox in pairs(self.DriveGearboxes) do
			local Kept = self.GearboxEnds[Gearbox] or self.GearboxIntermediates[Gearbox]

			if Kept and IsValid(Gearbox) and not DriveGearboxes[Gearbox] then
				Gearbox:TriggerInput("Gear", 1)
			end
		end
		self.DriveGearboxes = DriveGearboxes

		-- Can't neutral steer if a gearbox is connected to both sides
		self.CanNeutral = true
		for Gearbox in pairs(self.LeftGearboxes) do if self.RightGearboxes[Gearbox] then self.CanNeutral = false break end end
		for Gearbox in pairs(self.RightGearboxes) do if self.LeftGearboxes[Gearbox] then self.CanNeutral = false break end end

		-- Set default shift RPMs to one of the engine's powerbands
		local Engine = next(self.Engines)
		if IsValid(Engine) then
			if self:GetShiftMinRPM() == 0 then self:SetShiftMinRPM(Engine.PeakMinRPM + 100) end
			if self:GetShiftMaxRPM() == 0 then self:SetShiftMaxRPM(Engine.PeakMaxRPM - 100) end
		end

		self.LastInputs = {}
		self.LastGear = 0
		self.LastTrueGear = 0
		self.BrakeScale = nil -- Worked out again from the wheels now found
	end

	local function SameKeys(A, B)
		for Key in pairs(A) do if not B[Key] then return false end end
		for Key in pairs(B) do if not A[Key] then return false end end

		return true
	end

	local function SameGears(Analyzed)
		for Gearbox, Gears in pairs(Analyzed) do
			if Gearbox.Gears ~= Gears then return false end
		end

		return true
	end

	--- Analyzes the drivetrain again when it changed since the last analysis, such as wheels or steer plates linked later,
	--- a baseplate linked after the gearbox, or any of its gearboxes reconfigured
	function ENT:RefreshDrivetrain()
		local Gearbox = self:ACF_GetUserVar("Gearbox")
		if not (IsValid(Gearbox) and IsValid(self:ACF_GetUserVar("Baseplate"))) then return end

		if self.AnalyzedGearbox == Gearbox and self.AnalyzedBaseplate == self:ACF_GetUserVar("Baseplate") and self.AnalyzedGears == Gearbox.Gears then
			local Wheels, Engines, Ends, Intermediates = DiscoverDriveTrain(Gearbox)

			if SameKeys(Wheels, self.Wheels) and SameKeys(Engines, self.Engines) and SameKeys(Ends, self.GearboxEnds)
				and SameKeys(Intermediates, self.GearboxIntermediates)
				and SameKeys(DiscoverReversers(Gearbox), self.Reversers)
				and table.Count(self:ACF_GetUserVar("SteerPlates")) == #self.SteerPlatesSorted
				and SameGears(self.AnalyzedBoxGears) then
				return
			end
		end

		-- Welds of wheels that leave the drivetrain would never be released otherwise
		for Wheel, Weld in pairs(self.ControllerWelds) do
			if IsValid(Weld) then Weld:Remove() end

			self.ControllerWelds[Wheel] = nil
		end

		self:AnalyzeDrivetrain(Gearbox)
	end

	--- Applies or releases the wire parking brake, and toggles mobility control accordingly
	function ENT:SetWireParkingBrake(SelfTbl, State)
		self:SetDisableMobility(State)
		-- Either may be the low one
		local Strength = math.max(self:GetBrakeStrength(), self:GetBrakeStrengthTop())

		SetParkingBrake(SelfTbl, State, GetBrakeTorque(self, SelfTbl, Strength))
		if not State then SetLatches(SelfTbl, false) end
	end

	--- Turns the steer plates toward A/D
	local function UpdateSteering(self, SelfTbl, A, D, Speed)
		local MinSpeed, MaxSpeed = self:GetSpeedLow(), self:GetSpeedTop()
		local SteerLow, SteerTop = self:GetSteerLow(), self:GetSteerTop()
		local SteerStrength = SteerLow
		-- Held at either end's angle past its speed, or it would turn the other way at speed
		if MinSpeed ~= MaxSpeed then
			SteerStrength = math.Remap(Speed, MinSpeed, MaxSpeed, SteerLow, SteerTop)
			SteerStrength = math.Clamp(SteerStrength, math.min(SteerLow, SteerTop),
				math.max(SteerLow, SteerTop))
		end

		local TURN_ANGLE = A and SteerStrength or D and -SteerStrength or 0
		local TURN_RATE = self:GetSteerRate() or 0
		local SteerPercents = SelfTbl.SteerPercents

		SteerPercents[1], SteerPercents[2] = self:GetSteerPercent1(), self:GetSteerPercent2()
		SteerPercents[3], SteerPercents[4] = self:GetSteerPercent3(), self:GetSteerPercent4()

		-- Each plate turns at the rate of its share, so plates with smaller angles don't arrive early; the
		-- largest keeps the full rate
		local MaxPercent = 0
		for Index in ipairs(SelfTbl.SteerPlatesSorted) do MaxPercent = math.max(MaxPercent, math.abs(SteerPercents[Index] or 0)) end

		for Index, SteerPlate in ipairs(SelfTbl.SteerPlatesSorted) do
			if IsValid(SteerPlate) then
				local Percent = SteerPercents[Index] or 0 -- Only four plates have a share
				-- One with no share still returns straight
				local Rate = Percent ~= 0 and TURN_RATE * math.abs(Percent) / MaxPercent or TURN_RATE

				SetSteerPlate(SelfTbl, SelfTbl.ACF_LiveData.Baseplate, SteerPlate, TURN_ANGLE * Percent, Rate)
				local PhysicsObject = SelfTbl.SteerPhysicsObjects[SteerPlate] or SteerPlate:GetPhysicsObject()
				SelfTbl.SteerPhysicsObjects[SteerPlate] = PhysicsObject
				PhysicsObject:EnableMotion(false)
			end
		end
	end

	--- Handles driving, gearing, clutches, latches and brakes
	function ENT:ProcessDrivetrain(SelfTbl)
		-- Log speed even if drivetrain is invalid
		if not IsValid(SelfTbl.ACF_LiveData.Baseplate) then return end

		local Unit = self:GetSpeedUnit()
		local Conv = Unit == 0 and 0.09144 or 0.05681 -- Converts u/s to km/h or mph (Assumes 1u = 1in)
		local Speed = SelfTbl.ACF_LiveData.Baseplate:GetVelocity():Length() * Conv
		SelfTbl.Speed = Speed
		RecacheBindOutput(self, SelfTbl, "Speed", Speed)

		if not IsValid(SelfTbl.ACF_LiveData.Gearbox) then return end
		if self:GetDisableMobility() then return end

		local W, A, S, D = GetBindState(SelfTbl, "MoveForward"), GetBindState(SelfTbl, "TurnLeft"), GetBindState(SelfTbl, "MoveBack"), GetBindState(SelfTbl, "TurnRight")
		local IsBraking = GetBindState(SelfTbl, "Brake")

		if self:GetFlipAD() then A, D = D, A end

		local IsLateral = W or S						-- Forward/backward movement
		local IsTurning = A or D						-- Left/right movement
		local IsMoving = IsLateral or (not self:GetThrottleIgnoresAD() and IsTurning) -- Moving in any direction

		-- Only two transfer setups can reasonably be expected to neutral steer
		local IsNeutral = not IsLateral and IsTurning
		local ShouldNeutral = self.CanNeutral and not self:GetForceCarSteering()
		local ShouldSteer = self.CanSteer or self:GetForceCarSteering()

		-- Automatic parking in the gap between two keys would brake and declutch both sides for a tick,
		-- throwing the engines' load off at once and stalling them, so it waits a moment
		local Now = CurTime()

		if IsMoving then SelfTbl.LastMoving = Now end

		local Parking = not (IsMoving or IsBraking) and self:GetBrakeEngagement() == 1

		if Parking and SelfTbl.LastMoving and Now - SelfTbl.LastMoving < PARK_GRACE then return end

		-- Throttle the engines
		SetAll(SelfTbl, "Engines", "Throttle", IsMoving and 100 or self:GetThrottleIdle() or 0)

		local MinSpeed, MaxSpeed = self:GetSpeedLow(), self:GetSpeedTop()
		local MinBrake, MaxBrake = self:GetBrakeStrength(), self:GetBrakeStrengthTop()
		local BrakeStrength = MinBrake
		if MinSpeed ~= MaxSpeed then -- Speed based braking, held at either end's value past its speed
			BrakeStrength = math.Remap(Speed, MinSpeed, MaxSpeed, MinBrake, MaxBrake)
			BrakeStrength = math.Clamp(BrakeStrength, math.min(MinBrake, MaxBrake),
				math.max(MinBrake, MaxBrake))
		end

		local BrakeTorque = GetBrakeTorque(self, SelfTbl, BrakeStrength)

		if IsBraking or (self:GetBrakeEngagement() == 1 and not IsMoving) then -- Braking
			SetParkingBrake(SelfTbl, true, BrakeTorque)
			SetDoubleDiffs(SelfTbl, 0)

			-- Only the weld latches tie the wheels to the baseplate, so without them the plates can keep
			-- turning
			if ShouldSteer and self:GetDisableWeldBrake() == 1 then
				UpdateSteering(self, SelfTbl, A, D, Speed)
			end

			return
		end

		local DriveGear = (W and 1) or (S and 2) or (A and 1) or (D and 1) or 0

		-- Both rates at 0 keep brake steering, which is what controllers made before this setting did
		local DoubleDiffSteering = next(SelfTbl.DoubleDiffs) ~= nil
			and (self:GetDoubleDiffSteerLow() ~= 0 or self:GetDoubleDiffSteerTop() ~= 0)

		if not ShouldSteer then
			-- Tank steering
			SetLatches(SelfTbl, false)
			if IsNeutral and ShouldNeutral then
				-- Neutral steering, gears follow A/D
				SetLeft(SelfTbl, "Brake", 0) SetRight(SelfTbl, "Brake", 0)
				SetLeft(SelfTbl, "Clutch", CLUTCH_FLOW) SetRight(SelfTbl, "Clutch", CLUTCH_FLOW)
				SetDriveGear(SelfTbl, 1, true) -- A reverser above the ends would undo the backwards side
				SetLeft(SelfTbl, "Gear", A and 2 or 1, true) SetRight(SelfTbl, "Gear", D and 2 or 1, true)
				SetDoubleDiffs(SelfTbl, 0)
			elseif DoubleDiffSteering then
				-- The double differentials steer, pivoting on the spot past 0.5 when there is no W/S
				SetDriveGear(SelfTbl, DriveGear)

				SetLeft(SelfTbl, "Brake", 0) SetRight(SelfTbl, "Brake", 0)
				SetLeft(SelfTbl, "Clutch", CLUTCH_FLOW) SetRight(SelfTbl, "Clutch", CLUTCH_FLOW)

				local Turn = (A and 1 or 0) - (D and 1 or 0)

				SetDoubleDiffs(SelfTbl, Turn == 0 and 0 or Turn * (IsLateral and GetDoubleDiffRate(self, Speed) or 1))
			else
				-- Normal driving, gears follow W/S
				SetDriveGear(SelfTbl, DriveGear)

				SetLeft(SelfTbl,  "Brake",  A and BrakeTorque or 0)
				SetRight(SelfTbl, "Brake",  D and BrakeTorque or 0)
				SetLeft(SelfTbl,  "Clutch", A and CLUTCH_BLOCK or CLUTCH_FLOW)
				SetRight(SelfTbl, "Clutch", D and CLUTCH_BLOCK or CLUTCH_FLOW)
				SetDoubleDiffs(SelfTbl, 0)
			end
		else
			-- Car steering
			SetParkingBrake(SelfTbl, false)
			SetLeft(SelfTbl, "Clutch", CLUTCH_FLOW) SetRight(SelfTbl, "Clutch", CLUTCH_FLOW)
			SetLatches(SelfTbl, false) -- Revert braking if not braking
			SetDoubleDiffs(SelfTbl, 0) -- Switching to car steering mid-turn would leave them turning

			SetDriveGear(SelfTbl, DriveGear)

			UpdateSteering(self, SelfTbl, A, D, Speed)
		end
	end

	--- Handles gear shifting
	function ENT:ProcessDrivetrainLowFreq(SelfTbl)
		local Gearbox = SelfTbl.ACF_LiveData.Gearbox
		if not IsValid(Gearbox) then return end

		-- Mass and wheels rarely change, and the mass count is shared and slow anyway
		UpdateBrakeScale(SelfTbl)

		local _, S = GetBindState(SelfTbl, "MoveForward"), GetBindState(SelfTbl, "MoveBack")

		local Gear = SelfTbl.LastGear

		local RPM, Count = 0, 0
		for Engine in pairs(SelfTbl.Engines) do
			if IsValid(Engine) then
				RPM = RPM + Engine.FlyRPM
				Count = Count + 1
			end
		end
		if Count > 0 then RPM = RPM / Count end

		-- CVTs and automatics only pick drive or reverse here, which is driving rather than shifting
		if not (Gearbox.CVT or Gearbox.Automatic) then
			local MinRPM, MaxRPM = self:GetShiftMinRPM(), self:GetShiftMaxRPM()
			if MinRPM == MaxRPM then return end -- Probably not set by the user
			if self:GetDisableAutoShifter() then return end
			if RPM > MaxRPM then Gear = Gear + 1
			elseif RPM < MinRPM then Gear = Gear - 1 end
		end

		local UseReverser = next(SelfTbl.Reversers) ~= nil
		local TrueGear = 0
		if S and not UseReverser then
			Gear = math.Clamp(Gear, 1, #self.ReverseGears)
			TrueGear = self.ReverseGears[Gear] or 0
		else
			Gear = math.Clamp(Gear, 1, #self.ForwardGears)
			TrueGear = self.ForwardGears[Gear] or 0
		end

		if TrueGear ~= SelfTbl.LastTrueGear then
			Gearbox:TriggerInput("Gear", TrueGear)
		end
		SelfTbl.LastGear = Gear
		SelfTbl.LastTrueGear = TrueGear
	end
end

-- Drivetrain hints, refreshed by the controller's clock
do
	local SIDEWAYS = 0.7 -- Average alignment of the wheel axles with the baseplate's forward past which it faces sideways

	-- How well the driven wheels' axles line up with the baseplate's forward, 0 when they all roll forward
	local function GetSidewaysness(Controller)
		local Forward    = Controller:ACF_GetUserVar("Baseplate"):GetForward()
		local Sum, Count = 0, 0

		for Gearbox in pairs(Controller.GearboxEnds) do
			if IsValid(Gearbox) then
				for Wheel, Link in pairs(Gearbox:ACF_GetUserVar("Wheels")) do
					local Phys = IsValid(Wheel) and Wheel:GetPhysicsObject()

					if IsValid(Phys) then
						Sum, Count = Sum + math.abs(Phys:LocalToWorldVector(Link.Axis):Dot(Forward)), Count + 1
					end
				end
			end
		end

		return Count > 0 and Sum / Count or 0
	end

	-- Left and right come from the baseplate's frame, so a baseplate facing sideways splits the wheels front and back instead
	local function UpdateWheelSides(Controller, Analyzed)
		local Reason

		if Analyzed then
			local TankSteering = not (Controller.CanSteer or Controller:GetForceCarSteering())

			if GetSidewaysness(Controller) > SIDEWAYS then
				Reason = "The baseplate faces sideways to the wheels"
			elseif TankSteering and not (next(Controller.LeftWheels) and next(Controller.RightWheels)) then
				Reason = "All driven wheels are on one side"
			end
		end

		if not Reason then return Controller:SetRequirement("controller_wheel_sides", true) end

		Controller:SetRequirement("controller_wheel_sides", false, {
			Reason    = Reason,
			Baseplate = Controller:ACF_GetUserVar("Baseplate"),
			Left      = table.GetKeys(Controller.LeftWheels),
			Right     = table.GetKeys(Controller.RightWheels),
		})
	end

	function ENT:UpdateDrivetrainHints()
		local Gearbox      = self:ACF_GetUserVar("Gearbox")
		local HasBaseplate = IsValid(self:ACF_GetUserVar("Baseplate"))
		local HasGearbox   = IsValid(Gearbox)
		local Contraption  = self:CFW_GetContraption()
		local HasEngines   = Contraption and Contraption.Engines and next(Contraption.Engines) ~= nil
		local Analyzed     = HasBaseplate and HasGearbox and next(self.Wheels) ~= nil

		ACF.Hints.Set(self, "controller_no_baseplate", not HasBaseplate)
		ACF.Hints.Set(self, "controller_no_gearbox", HasEngines and not HasGearbox)

		-- Automatics and CVTs have nothing to shift, the controller only picks drive or reverse for them
		local Manual   = Analyzed and not (Gearbox.Automatic or Gearbox.CVT)
		local ShiftRPM = Manual and not self:GetDisableAutoShifter() and self:GetShiftMinRPM() == self:GetShiftMaxRPM()

		ACF.Hints.Set(self, "controller_shift_rpm", ShiftRPM, ShiftRPM and { RPM = self:GetShiftMinRPM() } or nil)

		-- A reversing gearbox below the main one does the reversing instead of a reverse gear on it
		ACF.Hints.Set(self, "controller_no_reverse",
			Analyzed and not next(self.Reversers) and not self.MainReverses)

		UpdateWheelSides(self, Analyzed)
	end
end

ACF.RegisterControllerLink("acf_gearbox", {
	Field = "Gearbox",
	Single = true,
	OnLinked = function(Controller, Target)
		Controller:AnalyzeDrivetrain(Target)
	end,
})

ACF.RegisterControllerLink("acf_baseplate", {
	Field = "Baseplate",
	Single = true,
	OnLinked = function(Controller, Target)
		local Pod = Target:ACF_GetUserVar("Seat")
		if IsValid(Pod) and not Controller:ACF_GetUserVar("Seat") then Controller:Link(Pod) end
	end,
	OnUnlinked = function(Controller, Target)
		local Pod = Target:ACF_GetUserVar("Seat")
		if IsValid(Pod) and not Controller:ACF_GetUserVar("Seat") then Controller:Unlink(Pod) end
	end,
})

ACF.RegisterControllerLink("prop_physics", {
	Field = "SteerPlates",
	Single = false,
})

return Init