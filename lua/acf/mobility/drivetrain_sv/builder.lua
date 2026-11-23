local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain

-- kg·m², ACF gearboxes have none; seen through a big reduction even this little adds up
local GEARBOX_INERTIA = 1e-4
-- An effector absorbs its load without ever turning, an engine block holds its shaft, a brake its wheel
local SINK_INERTIA    = 1e15
local RPM_TO_RADS     = ACF.RPMToRadS

local Collect, BuildShafts, BuildOutputs

local function ByIndex(A, B) return A:EntIndex() < B:EntIndex() end

-- Speeds kept on the entities seed the rebuilt bodies, so one that went non-finite would otherwise come back
-- with every rebuild, even with a new engine
local function IsFinite(Value) return Value == Value and Value ~= math.huge and Value ~= -math.huge end

local function SortedKeys(Set)
	local List = {}

	for Entity in pairs(Set) do
		if IsValid(Entity) then List[#List + 1] = Entity end
	end

	table.sort(List, ByIndex)

	return List
end

do -- MARK: Collecting
	local function Visit(Set, Seen, Stack)
		for Entity in pairs(Set) do
			if IsValid(Entity) and not Seen[Entity] then
				Seen[Entity]      = true
				Stack[#Stack + 1] = Entity
			end
		end
	end

	local function VisitWheels(Wheels, Seen, Stack)
		for Wheel in pairs(Wheels) do
			if IsValid(Wheel) then
				if Wheel.ACF_Gearboxes then Visit(Wheel.ACF_Gearboxes, Seen, Stack) end
				if Wheel.ACF_Engines then Visit(Wheel.ACF_Engines, Seen, Stack) end
			end
		end
	end

	-- Every engine and gearbox reachable through mobility links, running or not. Everything that turns the
	-- same wheel joins one train, so the wheel is one body all of it pushes on; two trains would each take
	-- the other's push for the ground's.
	function Collect(Root)
		local Seen      = { [Root] = true }
		local Stack     = { Root }
		local Engines   = {}
		local Gearboxes = {}

		while Stack[1] do
			local Entity = table.remove(Stack)
			local Live   = Entity.ACF_LiveData

			if Entity:GetClass() == "acf_engine" then
				Engines[#Engines + 1] = Entity

				Visit(Live.Gearboxes, Seen, Stack)
				Visit(Live.Cranks, Seen, Stack)
				VisitWheels(Live.Wheels, Seen, Stack)
			else
				Gearboxes[#Gearboxes + 1] = Entity

				Visit(Entity.Engines, Seen, Stack)
				Visit(Entity.GearboxIn, Seen, Stack)
				Visit(Live.GearboxOut, Seen, Stack)
				VisitWheels(Live.Wheels, Seen, Stack)
			end
		end

		table.sort(Engines, ByIndex)
		table.sort(Gearboxes, ByIndex)

		return Engines, Gearboxes
	end
end

do -- MARK: Shafts
	local function Join(Other, ShaftOf, Body, Stack)
		if IsValid(Other) and ACF.IsOperational(Other) and not ShaftOf[Other] then
			ShaftOf[Other]    = Body
			Stack[#Stack + 1] = Other
		end
	end

	-- Engines driving a common gearbox's input, or joined crank to crank, turn as one rigid body, running or
	-- not
	local function JoinShaft(Engine, ShaftOf, Body)
		local Stack     = { Engine }
		local Engines   = {}
		local Gearboxes = {}
		local Seen      = {}

		ShaftOf[Engine] = Body

		while Stack[1] do
			local Member = table.remove(Stack)

			Engines[#Engines + 1] = Member
			Body.Inertia          = Body.Inertia + Member.Inertia

			for Gearbox in pairs(Member.ACF_LiveData.Gearboxes) do
				if IsValid(Gearbox) and not Seen[Gearbox] then
					Seen[Gearbox]             = true
					Gearboxes[#Gearboxes + 1] = Gearbox

					for Other in pairs(Gearbox.Engines) do Join(Other, ShaftOf, Body, Stack) end
				end
			end

			for Other in pairs(Member.ACF_LiveData.Cranks) do Join(Other, ShaftOf, Body, Stack) end
		end

		table.sort(Engines, ByIndex)
		table.sort(Gearboxes, ByIndex)

		return Engines, Gearboxes
	end

	local function NewShaft(Engine, ShaftOf, System)
		local Body               = System:AddBody(Drivetrain.Body.New(0))
		local Engines, Gearboxes = JoinShaft(Engine, ShaftOf, Body)
		local RPM                = 0
		-- Tables of the engines that can stall, which a launch clutch keeps from it
		local Stalling           = {}

		for _, Member in ipairs(Engines) do
			if not IsFinite(Member.FlyRPM) then Member.FlyRPM = 0 end

			RPM = RPM + Member.FlyRPM

			if Drivetrain.Adapters[Member.DrivetrainAdapter].CanStall then
				Stalling[#Stalling + 1] = Member:GetTable()
			end
		end

		Body.Omega = RPM / #Engines * RPM_TO_RADS

		return {
			Body        = Body,
			Engines     = Engines,
			Stalling    = Stalling,
			Gearboxes   = Gearboxes,
			LaunchFeeds = {},
		}
	end

	function BuildShafts(Engines, Gearboxes, System)
		local ShaftOf = {}
		local Shafts  = {}
		local BodyOf  = {}

		for _, Engine in ipairs(Engines) do
			if ACF.IsOperational(Engine) and not ShaftOf[Engine] then
				Shafts[#Shafts + 1] = NewShaft(Engine, ShaftOf, System)
			end
		end

		for _, Gearbox in ipairs(Gearboxes) do
			local Body = System:AddBody(Drivetrain.Body.New(GEARBOX_INERTIA))

			if not IsFinite(Gearbox.ACF_InputOmega or 0) then Gearbox.ACF_InputOmega = nil end

			Body.Omega      = Gearbox.ACF_InputOmega or 0
			BodyOf[Gearbox] = Body
		end

		return ShaftOf, Shafts, BodyOf
	end
end

do -- MARK: Outputs
	local function AddClutch(System, Input, Output)
		-- Ratio, gain and capacity are set every tick
		return System:AddClutch(Drivetrain.Clutch.New(Input, Output, 0, 1, 0))
	end

	local function AddDriveshafts(Shafts, BodyOf, Boxes, System)
		for _, Shaft in ipairs(Shafts) do
			for _, Gearbox in ipairs(Shaft.Gearboxes) do
				local Body   = BodyOf[Gearbox]
				local Box    = Boxes[Gearbox]
				local Clutch = AddClutch(System, Shaft.Body, Body)

				if not Gearbox.ACF_InputOmega then Body.Omega = Shaft.Body.Omega end

				Box:AddFeed(Clutch, true)

				if Box.LaunchClutch then Shaft.LaunchFeeds[#Shaft.LaunchFeeds + 1] = Clutch end
			end
		end
	end

	local function AddGearboxes(Box, BodyOf, Boxes, System)
		local Links = Box.Entity.ACF_LiveData.GearboxOut

		for _, Target in ipairs(SortedKeys(Links)) do
			local Link   = Links[Target]
			local Clutch = AddClutch(System, Box:GetSideBody(Link.Side), BodyOf[Target])

			Box:AddLink(Clutch, Link, Boxes[Target])
			Boxes[Target]:AddFeed(Clutch, false)
		end
	end

	-- The block is the input, as only an output gets its impulses handed on to physics
	local function AddBrake(System, Adapter)
		local Block = System:AddBody(Drivetrain.Body.New(SINK_INERTIA))

		Adapter:AttachBrake(System:AddClutch(Drivetrain.Brake.New(Block, Adapter.Body)))
	end

	-- One adapter per wheel, however many things turn it; the first to reach it measures its spin against its
	-- own chassis
	local function GetWheel(Wheel, Axis, Reference, WheelOf, Train, System, Adapters)
		local Adapter = WheelOf[Wheel]

		if Adapter then return Adapter end

		Adapter = Drivetrain.Adapters.Wheel.New(Wheel, Axis, Reference, Train)

		if not Adapter then return end

		System:AddBody(Adapter.Body)
		System:AddLimit(Adapter.SpinCap)
		AddBrake(System, Adapter)

		WheelOf[Wheel]          = Adapter
		Adapters[#Adapters + 1] = Adapter

		return Adapter
	end

	local function AddWheels(Box, WheelOf, Train, System, Adapters)
		local Links = Box.Entity.ACF_LiveData.Wheels

		for _, Wheel in ipairs(SortedKeys(Links)) do
			local Link    = Links[Wheel]
			local Adapter = GetWheel(Wheel, Link.Axis, Box.Entity, WheelOf, Train, System, Adapters)

			if Adapter then
				local Clutch = AddClutch(System, Box:GetSideBody(Link.Side), Adapter.Body)

				Adapter:Couple(Clutch)
				Box:AddLink(Clutch, Link, Adapter, Adapter:GetAxisSign(Link.Axis))
			end
		end
	end

	-- Effectors read an engine's speed, so each gearbox gets the shaft that reaches it first, the same one
	-- every build
	local function FindFeeds(Shafts)
		local FeedOf = {}
		local Queue  = {}
		local Head   = 1

		for _, Shaft in ipairs(Shafts) do
			for _, Gearbox in ipairs(Shaft.Gearboxes) do
				if not FeedOf[Gearbox] then
					FeedOf[Gearbox]   = Shaft.Body
					Queue[#Queue + 1] = Gearbox
				end
			end
		end

		while Queue[Head] do
			local Gearbox = Queue[Head]

			Head = Head + 1

			for _, Target in ipairs(SortedKeys(Gearbox.ACF_LiveData.GearboxOut)) do
				if not FeedOf[Target] then
					FeedOf[Target]    = FeedOf[Gearbox]
					Queue[#Queue + 1] = Target
				end
			end
		end

		return FeedOf
	end

	local function AddEffectors(Box, Feed, Train, System, Adapters)
		local Links = Box.Entity.ACF_LiveData.Effectors

		for _, Effector in ipairs(SortedKeys(Links)) do
			local Link    = Links[Effector]
			local Sink    = System:AddBody(Drivetrain.Body.New(SINK_INERTIA))
			local Clutch  = AddClutch(System, Box:GetSideBody(Link.Side), Sink)
			local Adapter = Drivetrain.Adapters.Effector.New(Effector, Clutch, Train, Feed)

			Adapters[#Adapters + 1] = Adapter

			Box:AddLink(Clutch, Link, Adapter)
		end
	end

	-- ShaftBody is nil for an engine that doesn't work, which only brakes them, as a wrecked gearbox still
	-- brakes its wheels
	local function AddCrankWheels(Direct, ShaftBody, Engine, WheelOf, Train, System, Adapters)
		local Links = Engine.ACF_LiveData.Wheels

		for _, Wheel in ipairs(SortedKeys(Links)) do
			local Link    = Links[Wheel]
			local Adapter = GetWheel(Wheel, Link.Axis, Engine, WheelOf, Train, System, Adapters)

			if Adapter and ShaftBody then
				local Clutch = AddClutch(System, ShaftBody, Adapter.Body)

				Adapter:Couple(Clutch)
				Direct:AddLink(Clutch, Link, Adapter, Adapter:GetAxisSign(Link.Axis))
			elseif Adapter then
				Direct:AddBrake(Link, Adapter)
			end
		end
	end

	local function AddDirect(Engines, ShaftOf, WheelOf, Train, System, Adapters)
		for _, Engine in ipairs(Engines) do
			if next(Engine.ACF_LiveData.Wheels) then
				local Direct = Drivetrain.Adapters.Direct.New(Engine, Train)

				AddCrankWheels(Direct, ShaftOf[Engine], Engine, WheelOf, Train, System, Adapters)

				Adapters[#Adapters + 1] = Direct
			end
		end
	end

	function BuildOutputs(Engines, Gearboxes, ShaftOf, Shafts, BodyOf, Train, System, Adapters)
		local Boxes   = {}
		local WheelOf = {}
		local FeedOf  = FindFeeds(Shafts)

		for _, Gearbox in ipairs(Gearboxes) do
			Boxes[Gearbox] = Drivetrain.Adapters[Gearbox.ClassData.DrivetrainAdapter].New(Gearbox,
				BodyOf[Gearbox], Train, System)
		end

		AddDriveshafts(Shafts, BodyOf, Boxes, System)

		for _, Gearbox in ipairs(Gearboxes) do
			local Box = Boxes[Gearbox]

			AddGearboxes(Box, BodyOf, Boxes, System)
			AddWheels(Box, WheelOf, Train, System, Adapters)
			AddEffectors(Box, FeedOf[Gearbox], Train, System, Adapters)
		end

		AddDirect(Engines, ShaftOf, WheelOf, Train, System, Adapters)

		-- Last, so they see their wheels first
		for _, Gearbox in ipairs(Gearboxes) do Adapters[#Adapters + 1] = Boxes[Gearbox] end
	end
end

--- Marks every engine and gearbox it reaches with the result, which is how Invalidate finds it.
--- @param Root entity
--- @return table
function Drivetrain.Build(Root)
	local Engines, Gearboxes      = Collect(Root)
	local System                  = Drivetrain.System.New()
	local ShaftOf, Shafts, BodyOf = BuildShafts(Engines, Gearboxes, System)
	local Adapters                = {}
	local Members                 = {}
	local Train                   = Drivetrain.Powertrain.New(System, Adapters, Members)

	Train.Root = Root

	for I, Shaft in ipairs(Shafts) do Train.Shafts[I] = Shaft.Body end

	for _, Shaft in ipairs(Shafts) do
		for _, Engine in ipairs(Shaft.Engines) do
			local Block    = System:AddBody(Drivetrain.Body.New(SINK_INERTIA))
			local Friction = System:AddClutch(Drivetrain.Clutch.New(Shaft.Body, Block, 1, 1, 0))

			local Adapter  = Drivetrain.Adapters[Engine.DrivetrainAdapter]

			Members[#Members + 1]   = Engine:GetTable()
			Adapters[#Adapters + 1] = Adapter.New(Engine, Shaft.Body, Friction)
		end
	end

	BuildOutputs(Engines, Gearboxes, ShaftOf, Shafts, BodyOf, Train, System, Adapters)

	for _, Shaft in ipairs(Shafts) do
		local Feeds = Shaft.LaunchFeeds

		if Feeds[1] and Shaft.Stalling[1] then
			System:AddLimit(Drivetrain.Limits.LaunchClutch.ForEngines(Shaft.Body, Feeds, Shaft.Stalling))
		end
	end

	System:Finalize()

	for _, Engine in ipairs(Engines) do Engine.ACF_Powertrain = Train end
	for _, Gearbox in ipairs(Gearboxes) do Gearbox.ACF_Powertrain = Train end

	return Train
end
