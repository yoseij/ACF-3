local ACF     = ACF
local Classes = ACF.Classes
local GetType = Classes.GetTypeByName
local PAGE    = "acf_engine"

local ENGINE_BASE = "ACF.Engines.BaseEngine"

local HPColor     = Color(255, 65, 65)
local TorqueColor = Color(65, 65, 255)
local IdleColor   = Color(127, 0, 0)

local function GetEngineType(FQN) return Classes.GetSubtypeByName("ACF.EngineTypes.BaseEngineType", FQN) end
local function GetFuelType(FQN)   return Classes.GetSubtypeByName("ACF.FuelTypes.FuelType", FQN) end

local function GetFuels(Data)
	local Fuels = {}

	for FQN in pairs(Data.Fuel) do
		Fuels[#Fuels + 1] = GetFuelType(FQN)
	end

	return Fuels
end

-- A fuel tank copied into the menu keeps its fuel, even one this engine doesn't use
local function GetFuelChoices(Fuels)
	local Choices = {}

	for _, Fuel in ipairs(Fuels) do Choices[Classes.GetTypeName(Fuel)] = Fuel end

	for _, Type in ipairs(ACF.Menu.PreferredTypes or {}) do
		local Name = Classes.GetTypeName(Type)

		if GetFuelType(Name) then Choices[Name] = Type end
	end

	return Choices
end

local function UpdateEngineStats(Label, Data)
	local RPM        = Data.RPM
	local PeakTqRPM  = math.Round(Data.PeakTqRPM)
	local PeakkW     = Data.PeakPower
	local PeakkWRPM  = Data.PeakPowerRPM
	local Mass       = ACF.FormatMass(Data.Mass or 0)
	local Cost       = ACF.FormatCost(5 + Data.PeakPower / ACF.EngineKwPerPoint)
	local Torque     = math.Round(Data.Torque)
	local TorqueFeet = math.Round(Data.Torque * ACF.NmToFtLb)
	local Type       = GetEngineType(Data.Type)
	local Efficiency = Type.Efficiency
	local FuelList   = ""

	local RPMText         = language.GetPhrase("acf.menu.engines.rpm_stats")
	local PowerText       = language.GetPhrase("acf.menu.engines.power_stats")
	local ConsumptionText = language.GetPhrase("acf.menu.engines.consumption_stats")

	for _, Fuel in ipairs(GetFuels(Data)) do
		local AddText
		if Fuel.ConsumptionText then
			AddText = Fuel.ConsumptionText(PeakkW, PeakkWRPM, Efficiency, Type, Fuel)
		else
			local Rate = ACF.FuelRate * Efficiency * PeakkW / (60 * Fuel.Density)
			AddText = ConsumptionText:format(Fuel.Name, math.Round(Rate, 2), math.Round(Rate * ACF.LToGal, 2), PeakkWRPM)
		end

		FuelList = FuelList .. "\n" .. AddText .. "\n"
	end

	local Power = PowerText:format(Torque, TorqueFeet, PeakTqRPM, math.Round(PeakkW), math.Round(PeakkW * ACF.KwToHp), PeakkWRPM)

	Label:SetText(RPMText:format(RPM.Idle, RPM.PeakMin, RPM.PeakMax, RPM.Limit, Mass, Cost, FuelList, Power))
end

local function Build(Menu, Contexts)
	local Engine = Contexts.Engine
	local Fuel   = Contexts.Fuel
	local TankSize = Vector(Fuel:Get("FuelSizeX") or 24, Fuel:Get("FuelSizeY") or 24, Fuel:Get("FuelSizeZ") or 24)

	Menu:AddTitle("#acf.menu.engines.settings")
	Menu:AddWikiLink("Engines", "docs/acf_tutorials/engines.html")
	Menu:AddPresets(Engine)

	local EngineClass = Menu:AddComboBox()
	local EngineList  = Menu:AddComboBox()
	-- The chosen layout's own controls: engine type, size, gearing
	local Options     = Menu:AddPanel("ACF_Panel")

	local EngineBase    = Menu:AddCollapsible("#acf.menu.engines.engine_info", nil, "icon16/monitor_edit.png")
	local EngineName    = EngineBase:AddTitle()
	local EngineDesc    = EngineBase:AddLabel()
	local EnginePreview = EngineBase:AddModelPreview(nil, true, "Primary")
	local EngineStats   = EngineBase:AddLabel()

	local PowerGraph = Menu:AddGraph()
	local PGWidth    = Menu:GetWide()
	PowerGraph:SetSize(PGWidth, PGWidth / 2)
	PowerGraph:SetXLabel("#acf.menu.engines.rpm")
	PowerGraph:SetYLabel("#acf.menu.engines.times_100")
	PowerGraph:SetXSpacing(1000)
	PowerGraph:SetYSpacing(100)
	PowerGraph:SetFidelity(24)

	Menu:AddTitle("#acf.menu.fuel.settings")
	Menu:AddPresets(Fuel, { Keep = { "Shape", "FuelSizeX", "FuelSizeY", "FuelSizeZ" } }) -- Presets leave the tank's size alone

	local FuelType  = Menu:AddComboBox()
	local FuelShape = Menu:AddComboBox()
	FuelShape:AddChoice("Box", "ACF.ContainerShapes.Box")
	FuelShape:AddChoice("Sphere", "ACF.ContainerShapes.Sphere")
	FuelShape:AddChoice("Cylinder", "ACF.ContainerShapes.Cylinder")

	local Min = ACF.ContainerMinSize
	local Max = ACF.ContainerMaxSize

	local SizeX = Menu:AddSlider("#acf.menu.fuel.tank_length", Min, Max)
	local SizeY = Menu:AddSlider("#acf.menu.fuel.tank_width", Min, Max)
	local SizeZ = Menu:AddSlider("#acf.menu.fuel.tank_height", Min, Max)

	Menu:AddField(Fuel, "FuelPriority", { Title = "#acf.menu.fuel.priority", wang = true })

	local FuelBase    = Menu:AddCollapsible("#acf.menu.fuel.tank_info", nil, "icon16/cup_edit.png")
	local FuelDesc    = FuelBase:AddLabel()
	local FuelPreview = FuelBase:AddModelPreview(nil, true, "Secondary")
	local FuelInfo    = FuelBase:AddLabel()

	function FuelType:UpdateFuelText()
		if not self.Selected then return end

		local ShapeInst = Fuel:Get("Shape")
		local Shape = (ShapeInst and ShapeInst.GetType) and ShapeInst:GetType() or GetType("ACF.ContainerShapes.Box")

		local Volume = Shape.ShapeCalculation(TankSize)

		local Capacity = Volume * ACF.gCmToKgIn
		local Mass     = Capacity * self.Selected.Density

		local FuelText
		if self.Selected.FuelTankText then
			FuelText = self.Selected.FuelTankText(Capacity, Mass)
		else
			local Text = language.GetPhrase("acf.menu.fuel.tank_stats")
			FuelText = Text:format(math.Round(Capacity, 2), math.Round(Capacity * ACF.LToGal, 2), ACF.FormatMass(Mass))
		end

		FuelDesc:SetText("Scalable Fuel Tank\n\nShape: " .. (Shape.Name or "Box"))
		FuelInfo:SetText(FuelText)
	end

	local function ScalePreview()
		if IsValid(FuelPreview) then FuelPreview:SetModelScale(TankSize * 12) end
	end

	-- Everything shown about the engine comes from the sized instance in the context
	local ShownFuels -- The fuels the fuel combo lists, so it is only rebuilt when they change

	local function Refresh()
		local Instance = Engine:Get("Engine")

		if not (Instance and Instance.GetStats) then return end

		local Data   = Instance:GetStats()
		local Family = Classes.GetBaseClass(Instance:GetType())

		EngineName:SetText(Data.Name)
		EngineDesc:SetText(language.GetPhrase(Family.Description))

		EnginePreview:UpdateModel(Data.Model)
		EnginePreview:UpdateSettings(Data.Preview)
		EnginePreview:SetModelScale(Data.Scale, true)

		UpdateEngineStats(EngineStats, Data)

		PowerGraph:SetXRange(0, Data.RPM.Limit)
		PowerGraph:SetYRange(0, math.max(math.ceil(Data.PeakPower * ACF.KwToHp), Data.Torque) * 1.1)
		PowerGraph:SetFidelity(10)

		PowerGraph:Clear()
		PowerGraph:PlotPoint(language.GetPhrase("acf.menu.engines.peak_hp"), Data.PeakPowerRPM,
			math.Round(Data.PeakPower * ACF.KwToHp), HPColor)
		PowerGraph:PlotPoint(language.GetPhrase("acf.menu.engines.peak_nm"), Data.PeakTqRPM,
			math.Round(Data.Torque), TorqueColor)

		PowerGraph:PlotLimitFunction(language.GetPhrase("acf.menu.engines.torque"), Data.RPM.Idle, Data.RPM.Limit, TorqueColor, function(X)
			local Position = math.Remap(X, Data.RPM.Idle, Data.RPM.Limit, 0, 1)

			return ACF.GetTorque(Data.TorqueCurve, Position) * Data.Torque
		end)

		PowerGraph:PlotLimitFunction(language.GetPhrase("acf.menu.engines.hp"), Data.RPM.Idle, Data.RPM.Limit, HPColor, function(X)
			local Position = math.Remap(X, Data.RPM.Idle, Data.RPM.Limit, 0, 1)

			return (ACF.GetTorque(Data.TorqueCurve, Position) * Data.Torque * X) * ACF.KwToHp / 9548.8
		end)

		PowerGraph:PlotLimitLine(language.GetPhrase("acf.menu.engines.idle_rpm"), false, Data.RPM.Idle, IdleColor)

		local Fuels = GetFuels(Data)
		local Names = {}

		for I, Fuel in ipairs(Fuels) do Names[I] = Classes.GetTypeName(Fuel) end

		table.sort(Names)

		local Key = table.concat(Names, ",")

		if Key ~= ShownFuels then
			ShownFuels = Key

			ACF.Menu.LoadClassCombo(FuelType, GetFuelChoices(Fuels), "ID", nil, PAGE, "fuel")
		end
	end

	Engine:OnChange("acf_engine_menu", "Engine", Refresh)

	local Bound -- The instance the layout's controls edit

	-- The layout's controls: what it burns, how big it is, and for a turbine whether its output is geared
	-- down
	local function BuildOptions(Layout)
		Options:ClearAll()

		local Sub = ACF.Menu.SubContext(Engine, "Engine")

		if not Sub then return end

		Bound = Sub.Instance

		local Types = {}

		for I, FQN in ipairs(Layout.EngineTypes) do
			Types[I] = GetType(FQN)
		end

		-- A family that burns one thing has nothing to choose; VerifyData has already given it that type
		if #Types > 1 then
			local TypeCombo = Options:AddComboBox()

			function TypeCombo:OnSelect(Index, _, Data)
				if self.Selected == Data then return end
				self.ListData.Index = Index
				self.Selected = Data
				ACF.Menu.SaveClassCombo(PAGE, "enginetype", Data)

				Sub:Set("EngineType", Data())
			end

			ACF.Menu.LoadClassCombo(TypeCombo, Types, "Name", nil, PAGE, "enginetype")
		end

		for _, Field in ipairs({ "Displacement", "Power", "Geared" }) do
			if Classes.GetTypeFieldByName(Layout, Field) then
				ACF.Menu.AddField(Options, Sub, Field, { Title = "#acf.menu.engines." .. Field:lower() })
			end
		end

		Options:InvalidateParent()
	end

	-- Picking a layout, a copy or a preset all put a new instance in the context, which the controls must
	-- follow
	Engine:OnChange("acf_engine_menu_options", "Engine", function()
		local Instance = Engine:Get("Engine")

		if Instance and Instance.GetType and Instance ~= Bound then BuildOptions(Instance:GetType()) end
	end)

	function EngineClass:OnSelect(Index, _, Data)
		if self.Selected == Data then return end
		self.ListData.Index = Index
		self.Selected = Data
		ACF.Menu.SaveClassCombo(PAGE, "group", Data)

		ACF.Menu.LoadClassCombo(EngineList, Classes.GetChildren(Data), "Order", nil, PAGE, "engine")
	end

	function EngineList:OnSelect(Index, _, Layout)
		if self.Selected == Layout then return end
		self.ListData.Index = Index
		self.Selected = Layout
		ACF.Menu.SaveClassCombo(PAGE, "engine", Layout)

		local Current  = Engine:Get("Engine")
		local Instance = Layout()

		-- Size and type carry over between layouts where they fit; VerifyData settles what doesn't
		if Current and Current.GetType then
			for _, Field in ipairs(Classes.GetTypeFields(Layout)) do
				local Value = rawget(Current, Field.Name)

				if Value ~= nil then Instance[Field.Name] = Value end
			end
		end

		Instance:VerifyData()

		Engine:Set("Engine", Instance) -- Which refreshes the page
	end

	function FuelType:OnSelect(Index, _, Data)
		if self.Selected == Data then return end
		self.ListData.Index = Index
		self.Selected = Data
		ACF.Menu.SaveClassCombo(PAGE, "fuel", Data)

		Fuel:Set("FuelType", Classes.GetTypeName(Data))
		self:UpdateFuelText()
	end

	function FuelShape:OnSelect(_, _, Data)
		Fuel:Set("Shape", Data)

		local ShapeClass = GetType(Data) or GetType("ACF.ContainerShapes.Box")
		if IsValid(FuelPreview) then FuelPreview:UpdateModel(ShapeClass.Model, "models/props_canal/metalcrate001d") end

		FuelType:UpdateFuelText()
	end

	local function BindSize(Slider, Axis, Field)
		function Slider:OnValueChanged(Value)
			local N = math.Round(Value)
			self:SetValue(N)
			TankSize[Axis] = N
			Fuel:Set(Field, N)
			FuelType:UpdateFuelText()
			ScalePreview()
		end
	end

	BindSize(SizeX, "x", "FuelSizeX")
	BindSize(SizeY, "y", "FuelSizeY")
	BindSize(SizeZ, "z", "FuelSizeZ")

	ACF.Menu.LoadClassCombo(EngineClass, Classes.GetChildren(GetType(ENGINE_BASE)), "Name", nil, PAGE, "group")

	-- Restore shape (fires OnSelect) then seed the size sliders (fires their handlers -> context + preview).
	local ShapeInst = Fuel:Get("Shape")
	local ShapeFQN  = (ShapeInst and ShapeInst.GetType) and Classes.GetTypeName(ShapeInst:GetType()) or "ACF.ContainerShapes.Box"
	FuelShape:ChooseOptionID(ShapeFQN == "ACF.ContainerShapes.Sphere" and 2 or ShapeFQN == "ACF.ContainerShapes.Cylinder" and 3 or 1)

	SizeX:SetValue(TankSize.x)
	SizeY:SetValue(TankSize.y)
	SizeZ:SetValue(TankSize.z)
end

ACF.Menu.RegisterPage({
	ID       = "acf_engine",
	Category = "#acf.menu.mobility",
	Name     = "#acf.menu.engines",
	Icon     = "car",
	Order    = 201,

	Contexts = { Engine = "acf_engine", Fuel = "acf_fueltank" },

	Actions = {
		{ Bind = "left",       Context = "Engine", Preview = true, Desc = "Spawn a new engine, or update the one you're aiming at." },
		{ Bind = "shift+left", Context = "Fuel",   Preview = true, Desc = "Spawn a new fuel tank, or update the one you're aiming at." },
		{ Bind = "right",      Commit = "link", Desc = "Select gearboxes, then an engine, to link them (hold R to unlink)." },
	},

	Build = Build,
})
