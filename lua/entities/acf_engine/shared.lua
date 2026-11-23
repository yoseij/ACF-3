DEFINE_BASECLASS("acf_base_scalable")

ACF.Entities.AutoRegister(2026111101, function(CLASS)
	-- A layout of an engine family, carrying its own size and engine type; the layout clamps both to what it
	-- comes in.
	MENU_FIELD("ACF.Engines.BaseEngine", "Engine", {Title = "#acf.menu.fields.acf_engine.engine", OnlyAllowSubtypes = true, OnlyAllowLeafTypes = true, InstantiateTypeForDefault = "ACF.Engines.V8"})
	LINKED_ENTITY_ARRAY_FIELD("Gearboxes", {AcceptableClasses = {acf_gearbox = true}})
	LINKED_ENTITY_ARRAY_FIELD("Cranks",    {AcceptableClasses = {acf_engine = true}})
	LINKED_ENTITY_ARRAY_FIELD("Wheels")
	-- Else a pasted engine just won't run
	LINKED_ENTITY_ARRAY_FIELD("FuelTanks", {AcceptableClasses = {acf_fueltank = true}, WarnOnLinkFail = true})

	function CLASS:VerifyData()
		self.Engine:VerifyData()
	end
end, "Engine", "Engines")

ENT.IsACFEngine = true -- Used by the engine legality restrictions

ENT.ACF_StaticWireInputs = {
	"Active (If set to a non-zero value, it'll attempt to start the engine.)",
	"Throttle (On a range from 0 to 100, defines how much power will be given to the engine. Electric motors take -100 to 100, running backwards below 0.)",
	"Brake (Sets the brake torque, in N·m, on each wheel linked to its crank.)",
}

ENT.ACF_StaticWireOutputs = {
	"RPM (Current rotations per minute of the engine.)",
	"Torque (Current torque, in nM, output by the engine.)",
	"Power (Current power, in kW, output by the engine.)",
	"Fuel Use (Amount of fuel, in liters per minute, being consumed by the engine.)",
	"Running (1 while the engine fires, 0 while it's off, cranking or stalled.)",
	"Mass (Total mass detected on the vehicle by the engine.)",
	"Physical Mass (Physical mass detected on the vehicle by the engine.)",
	"Entity (The engine itself.) [ENTITY]",
}

-- Returns the engine instance backing this entity: a sized layout with its engine type.
function ENT:GetEngine()
	return self:ACF_GetUserVar("Engine")
end
