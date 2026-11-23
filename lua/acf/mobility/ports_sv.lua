local ACF      = ACF
local Mobility = ACF.Mobility
local Ports    = Mobility.Ports or {}

Mobility.Ports = Ports

-- Between two gearboxes, which drives the other comes from how they face each other, not from the order they
-- were picked in: one's output always goes into the other's input.

--- Side (0 left, 1 right) and output plane of a gearbox facing a world position. A single-output gearbox has
--- only side 0.
--- @param Gearbox entity
--- @param WorldPos vector
--- @return number
--- @return table
function Ports.GetSide(Gearbox, WorldPos)
	if Gearbox.SingleOutput or Gearbox:WorldToLocal(WorldPos).y < 0 then return 0, Gearbox.OutL end

	return 1, Gearbox.OutR
end

--- How far the shaft from a gearbox's output to another's input bends, and the side it leaves from.
--- @param Source entity
--- @param Target entity
--- @return number # Degrees
--- @return number # Side
local function GetGearboxAngle(Source, Target)
	local Side, Plane = Ports.GetSide(Source, Target:LocalToWorld(Target.In.Pos))

	return ACF.DetermineDriveshaftAngle(Target, Target.In, Source, Plane), Side
end

--- Which of two linked gearboxes drives the other: the one whose output faces the other's input best.
--- @param A entity # Picked first, which wins a tie
--- @param B entity
--- @return entity # Source
--- @return entity # Target
--- @return number # Degrees the shaft bends
function Ports.PickGearboxes(A, B)
	local Forward  = GetGearboxAngle(A, B)
	local Backward = GetGearboxAngle(B, A)

	if Backward < Forward then return B, A, Backward end

	return A, B, Forward
end
