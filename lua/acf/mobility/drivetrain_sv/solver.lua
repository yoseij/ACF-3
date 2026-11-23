jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local Solver     = Drivetrain.Solver or {}

Drivetrain.Solver = Solver
Solver.__index    = Solver

local Pivoting = Drivetrain.Pivoting
local abs      = math.abs
local max      = math.max
local huge     = math.huge

-- Per clutch; flipping one clutch a round can take more rounds than flipping them all
local MAX_ROUNDS = 4
local DEPENDENT  = 1e-12 -- Relative to its own column, below it a clutch has no pivot of its own
-- Relative to its terms, what a clutch without a pivot may leave of its lock for it to repeat others
local CONSISTENT = 1e-9
local IMMOVABLE  = Drivetrain.ImmovableInertia

--- Exact for any layout, so a light gearbox driving several heavy wheels holds them together in one step.
--- @param Bodies table
--- @param Clutches table
function Solver.New(Bodies, Clutches)
	local Count    = #Clutches
	local Groups   = {}
	local Influence = {}
	local Touched  = {}
	local Seen     = {}

	for I = 1, Count * Count do Influence[I] = 0 end

	-- A push through one clutch changes the speed of the bodies it touches, and so the slip of every clutch
	-- on them
	for _, Body in ipairs(Bodies) do
		local Members, Terminals = {}, {}

		for I, Clutch in ipairs(Clutches) do
			for Terminal = 1, Clutch.Terminals do
				if Clutch:GetBody(Terminal) == Body then
					Members[#Members + 1]     = I
					Terminals[#Terminals + 1] = Terminal
				end
			end
		end

		if Members[1] then
			local Size  = #Members
			local Cells = {} -- Flat Size², the coupling cell each pair of members adds to

			for P = 1, Size do
				for Q = 1, Size do
					local Cell = (Members[P] - 1) * Count + Members[Q]

					Cells[(P - 1) * Size + Q] = Cell

					if not Seen[Cell] then
						Seen[Cell]            = true
						Touched[#Touched + 1] = Cell
					end
				end
			end

			Groups[#Groups + 1] = {
				Body      = Body,
				Members   = Members,
				Terminals = Terminals,
				Cells     = Cells,
				Sense     = {},
				Effect    = {},
			}
		end
	end

	return setmetatable({
		Clutches  = Clutches,
		Count     = Count,
		Groups    = Groups,
		Influence = Influence, -- Count² flat: change in one clutch's slip per unit impulse through another
		Touched   = Touched, -- The only cells that are ever nonzero
		Slip      = {},
		Bound     = {},
		BoundSign = {},
		After     = {},
		Wants     = {},
		IsFree    = {},
		Free      = {},
		Size      = 0,
		Matrix    = {},
		Rhs       = {},
		Limit     = {}, -- Per free clutch this round: its capacity, for when it can only hold
		Blocked   = {},
	}, Solver)
end

do -- MARK: Linear algebra
	local function SwapRows(Matrix, Rhs, Size, A, B, From)
		local BaseA, BaseB = (A - 1) * Size, (B - 1) * Size

		for K = From, Size do
			Matrix[BaseA + K], Matrix[BaseB + K] = Matrix[BaseB + K], Matrix[BaseA + K]
		end

		Rhs[A], Rhs[B] = Rhs[B], Rhs[A]
	end

	local MinPivot = {} -- Per column, reused across calls
	-- Per row: the size of what went into its right-hand side, which cancels to nothing when it repeats
	local RhsScale = {}
	local Skipped  = {} -- Rows whose column had no pivot, reused across calls

	-- Zeroed rather than left behind, as a row without a pivot may later move into a later column's place
	local function Reduce(Matrix, Rhs, Size, Base, Col, Row, Diag)
		local RowBase = (Row - 1) * Size
		local Factor  = Matrix[RowBase + Col] / Diag

		if Factor == 0 then return end

		for K = Col + 1, Size do
			Matrix[RowBase + K] = Matrix[RowBase + K] - Factor * Matrix[Base + K]
		end

		Matrix[RowBase + Col] = 0
		Rhs[Row]              = Rhs[Row] - Factor * Rhs[Col]
		RhsScale[Row]         = RhsScale[Row] + abs(Factor) * RhsScale[Col]
	end

	-- Gaussian elimination with partial pivoting, in place; the solution is left in Rhs. A clutch without a
	-- pivot of its own either repeats others, as one in parallel does, and is given nothing so they carry it,
	-- or it closes a loop of locks that disagree, such as two immovable outputs at different speeds, and
	-- could only hold with an endless push: it is held at its Limit against the slip instead, and marked
	-- Blocked. Pivots are judged against the clutch's own column, as one behind a big reduction has a tiny
	-- pivot next to a light gearbox's, yet repeats nothing. A row left without a pivot can still hold a later
	-- column's only one, so it stays a candidate.
	function Solver.Eliminate(Matrix, Rhs, Size, Limit, Blocked)
		local SkippedCount = 0

		for Col = 1, Size do
			local Scale = 0

			for Row = 1, Size do Scale = max(Scale, abs(Matrix[(Row - 1) * Size + Col])) end

			MinPivot[Col] = Scale * DEPENDENT
			RhsScale[Col] = abs(Rhs[Col])
		end

		for Col = 1, Size do
			local Pivot, Best = Col, abs(Matrix[(Col - 1) * Size + Col])
			local FromSkipped = false

			for Row = Col + 1, Size do
				local Value = abs(Matrix[(Row - 1) * Size + Col])

				if Value > Best then Pivot, Best = Row, Value end
			end

			for S = 1, SkippedCount do
				local Row   = Skipped[S]
				local Value = abs(Matrix[(Row - 1) * Size + Col])

				if Value > Best then Pivot, Best, FromSkipped = Row, Value, true end
			end

			if Best > MinPivot[Col] then
				if Pivot ~= Col then
					-- From a skipped row above, every column is swapped, as the row that moves up there is
					-- read from its place on
					SwapRows(Matrix, Rhs, Size, Col, Pivot, FromSkipped and 1 or Col)

					RhsScale[Col], RhsScale[Pivot] = RhsScale[Pivot], RhsScale[Col]
				end

				local Base = (Col - 1) * Size
				local Diag = Matrix[Base + Col]

				for Row = Col + 1, Size do Reduce(Matrix, Rhs, Size, Base, Col, Row, Diag) end
				for S = 1, SkippedCount do Reduce(Matrix, Rhs, Size, Base, Col, Skipped[S], Diag) end
			else
				SkippedCount          = SkippedCount + 1
				Skipped[SkippedCount] = Col
			end
		end

		for Row = Size, 1, -1 do
			local Base  = (Row - 1) * Size
			local Sum   = Rhs[Row]
			local Scale = RhsScale[Row]

			for K = Row + 1, Size do
				local Term = Matrix[Base + K] * Rhs[K]

				Sum   = Sum - Term
				Scale = Scale + abs(Term)
			end

			local Diag = Matrix[Base + Row]

			Blocked[Row] = false

			if abs(Diag) > MinPivot[Row] then
				Rhs[Row] = Sum / Diag
			elseif abs(Sum) <= CONSISTENT * Scale then
				Rhs[Row] = 0
			else
				local Held = Limit[Row]

				-- A rigid one has no capacity to hold at, so it gives way to the rest of the loop
				if Held == huge then Held = 0 end

				-- A pivot this small is negative, as every clutch's own is
				Rhs[Row]     = Sum > 0 and -Held or Held
				Blocked[Row] = true
			end
		end
	end
end

do -- MARK: Solving
	function Solver:Prepare()
		local Clutches  = self.Clutches
		local Count     = self.Count
		local Influence = self.Influence
		local Touched   = self.Touched
		local Slip      = self.Slip
		local Bound     = self.Bound
		local BoundSign = self.BoundSign
		local Groups    = self.Groups

		for I = 1, #Touched do Influence[Touched[I]] = 0 end

		for I = 1, Count do
			local Clutch = Clutches[I]

			Slip[I] = Clutch:GetSlip() + Clutch.Bias

			-- A clutch that slipped last tick most likely still does, so solving starts with it held at its
			-- capacity again; one a limit already fixed keeps what it was fixed at, and one made rigid since,
			-- as a differential locked while its limited slip slipped, has no capacity to start from
			if Bound[I] and BoundSign[I] and Clutch.MaxImpulse > 0 and Clutch.MaxImpulse < huge
				and not Clutch.Fixed then
				Clutch.Impulse = BoundSign[I] * Clutch.MaxImpulse
			else
				Bound[I] = false
			end
		end

		for G = 1, #Groups do
			local Group     = Groups[G]
			local Inertia   = Group.Body.Inertia
			local Members   = Group.Members
			local Terminals = Group.Terminals
			local Cells     = Group.Cells
			local Sense     = Group.Sense
			local Effect    = Group.Effect
			local Size      = #Members

			for P = 1, Size do
				local Clutch   = Clutches[Members[P]]
				local Terminal = Terminals[P]

				Sense[P]  = Clutch:GetSense(Terminal)
				Effect[P] = Inertia < IMMOVABLE and Clutch:GetEffect(Terminal) / Inertia or 0
			end

			for P = 1, Size do
				local Base      = (P - 1) * Size
				local Direction = Sense[P]

				for Q = 1, Size do
					local Cell = Cells[Base + Q]

					Influence[Cell] = Influence[Cell] + Direction * Effect[Q]
				end
			end
		end

		-- A compliant clutch gives way in proportion to what it carries, so its lock has slip to spare
		for I = 1, Count do
			local Softness = Clutches[I].Softness

			if Softness ~= 0 then
				local Cell = (I - 1) * Count + I

				Influence[Cell] = Influence[Cell] - Softness
			end
		end
	end

	-- Locks every clutch that is neither held at its capacity nor fixed by a limit, against the impulses of
	-- those that are
	local function SolveFree(self)
		local Clutches = self.Clutches
		local Count    = self.Count
		local Influence = self.Influence
		local Slip     = self.Slip
		local Bound    = self.Bound
		local IsFree   = self.IsFree
		local Free     = self.Free
		local Matrix   = self.Matrix
		local Rhs      = self.Rhs
		local Limit    = self.Limit
		local Blocked  = self.Blocked
		local Size     = 0

		for I = 1, Count do
			local Clutch = Clutches[I]
			local Open   = Clutch.MaxImpulse > 0 and not Clutch.Fixed and not Bound[I]

			IsFree[I] = Open

			if Open then
				Size       = Size + 1
				Free[Size] = I
			end
		end

		self.Size = Size

		if Size == 0 then return end

		-- Of a loop of locks that can't all hold, the last is left without a pivot to slip, so one that can't
		-- slip goes first
		for P = 2, Size do
			local I = Free[P]

			if Clutches[I].MaxImpulse == huge then
				local Q = P - 1

				while Q >= 1 and Clutches[Free[Q]].MaxImpulse ~= huge do
					Free[Q + 1] = Free[Q]
					Q           = Q - 1
				end

				Free[Q + 1] = I
			end
		end

		for P = 1, Size do
			local Row   = (Free[P] - 1) * Count
			local Value = -Slip[Free[P]]

			for K = 1, Count do
				if not IsFree[K] then Value = Value - Influence[Row + K] * Clutches[K].Impulse end
			end

			Rhs[P]   = Value
			Limit[P] = Clutches[Free[P]].MaxImpulse

			local Base = (P - 1) * Size

			for Q = 1, Size do Matrix[Base + Q] = Influence[Row + Free[Q]] end
		end

		Solver.Eliminate(Matrix, Rhs, Size, Limit, Blocked)

		for P = 1, Size do
			local I = Free[P]

			Clutches[I].Impulse = Rhs[P]

			if Blocked[P] then -- Held from here on, so the pivoting checks it pushes the right way
				Bound[I]  = true
				IsFree[I] = false
			end
		end
	end

	-- Each held clutch's slip once this round's impulses are in, for the pivoting to judge
	local function Settle(self)
		local Clutches = self.Clutches
		local Count    = self.Count
		local Influence = self.Influence
		local Slip     = self.Slip
		local Bound    = self.Bound
		local After    = self.After

		for I = 1, Count do
			if Bound[I] then
				local Value = Slip[I]
				local Row   = (I - 1) * Count

				for K = 1, Count do Value = Value + Influence[Row + K] * Clutches[K].Impulse end

				After[I] = Value
			end
		end

		return Pivoting.Settle(self, Clutches, self.IsFree, Bound, After, self.Wants)
	end

	--- Keeps whatever the limits fixed since the last call.
	function Solver:Solve()
		local Clutches  = self.Clutches
		local Bound     = self.Bound
		local BoundSign = self.BoundSign

		local Settled = false

		Pivoting.Begin(self)

		for _ = 1, MAX_ROUNDS * self.Count + MAX_ROUNDS do
			SolveFree(self)

			if not Settle(self) then Settled = true break end
		end

		if not Settled then Pivoting.Project(Clutches, Bound) end

		for I = 1, self.Count do
			local Clutch = Clutches[I]

			Clutch.Saturated = Bound[I] or Clutch.Fixed

			if Bound[I] then BoundSign[I] = Clutch.Impulse < 0 and -1 or 1 end
		end
	end
end
