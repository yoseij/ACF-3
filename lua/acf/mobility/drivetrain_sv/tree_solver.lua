jit.off(true, true) -- Short loops once a tick, where recording traces costs more than it saves

local ACF        = ACF
local Drivetrain = ACF.Mobility.Drivetrain
local TreeSolver = Drivetrain.TreeSolver or {}

Drivetrain.TreeSolver = TreeSolver
TreeSolver.__index    = TreeSolver

local Pivoting  = Drivetrain.Pivoting
local IMMOVABLE = Drivetrain.ImmovableInertia
local huge      = math.huge

local MAX_ROUNDS = 4    -- Per clutch, as the dense solver allows
-- A clutch that barely moves its output leaves the output's speed to pin its input instead
local MIN_GAIN   = 1e-9

-- Set when a junction found nothing to divide by, so the tick is left to the dense solver
local Degenerate = false

-- The one plain clutch from a differential's left side to its right, which locks or limits them; nil unless
-- there's exactly that one between them, as the junction solves it together with the carrier
local function FindLocker(Clutches, Carrier)
	local Left, Right = Carrier.Output, Carrier.Right
	local Found

	for K, Clutch in ipairs(Clutches) do
		if Clutch ~= Carrier then
			local In, Out = Clutch.Input, Clutch.Output

			if (In == Left or In == Right) and (Out == Left or Out == Right) then
				if Found or Clutch.Terminals ~= 2 or In ~= Left then return end

				Found = K
			end
		end
	end

	return Found
end

--- Most drivetrains are trees, so two passes do instead of a matrix: going up, each subtree shrinks to the
--- impulse its link to the parent needs per unit of the parent's speed; coming down, every speed and impulse
--- follows. A differential and the locker between its sides make one junction: its input's child, with both
--- sides hanging off it.
--- @param Bodies table
--- @param Clutches table
--- @return table? # nil for a loop, or a differential entered from a side, left to the dense solver
function TreeSolver.New(Bodies, Clutches)
	local Index      = {}
	local Adjacent   = {}
	local Junctions  = {} -- Per differential's carrier: its sides and its locker
	local InJunction = {} -- Per locker: its carrier, as the junction solves it rather than the tree

	for I, Body in ipairs(Bodies) do
		Index[Body]  = I
		Adjacent[I]  = {}
	end

	for C, Clutch in ipairs(Clutches) do
		if Clutch.Terminals == 3 then
			local In, Left, Right = Index[Clutch.Input], Index[Clutch.Output], Index[Clutch.Right]
			local Locker          = FindLocker(Clutches, Clutch)

			if not In or not Left or not Right or not Locker or InJunction[Locker] then return end
			if In == Left or In == Right or Left == Right then return end

			Junctions[C]       = { Left = Left, Right = Right, Locker = Locker }
			InJunction[Locker] = C
		elseif Clutch.Terminals ~= 2 then
			return
		end
	end

	for C, Clutch in ipairs(Clutches) do
		local Junction = Junctions[C]

		if Junction then
			local In = Index[Clutch.Input]

			Adjacent[In][#Adjacent[In] + 1]                         = C
			Adjacent[Junction.Left][#Adjacent[Junction.Left] + 1]   = C
			Adjacent[Junction.Right][#Adjacent[Junction.Right] + 1] = C
		elseif not InJunction[C] then
			local In, Out = Index[Clutch.Input], Index[Clutch.Output]

			if not In or not Out or In == Out then return end

			Adjacent[In][#Adjacent[In] + 1]   = C
			Adjacent[Out][#Adjacent[Out] + 1] = C
		end
	end

	local Order      = {} -- Every body, each after its parent
	local ParentEdge = {}
	local IsOutput   = {} -- Whether a body is its parent clutch's output
	local Children   = {} -- Per body, the clutches and junctions to its children
	local Visited    = {}

	for I = 1, #Bodies do Children[I] = {} end

	local function Visit(Other, C, AsOutput)
		Visited[Other]    = true
		ParentEdge[Other] = C
		IsOutput[Other]   = AsOutput
		Order[#Order + 1] = Other
	end

	-- Hangs whatever a clutch or junction leads to off the body it was reached from; false where that makes
	-- no tree
	local function Attach(B, C)
		local Junction = Junctions[C]

		if Junction then
			-- Entered from a side, its input would hang below it, which the passes don't solve
			if Index[Clutches[C].Input] ~= B then return false end
			if Visited[Junction.Left] or Visited[Junction.Right] then return false end

			Visit(Junction.Left, C, true)
			Visit(Junction.Right, C, true)
		else
			local Clutch = Clutches[C]
			local Other  = Index[Clutch.Input] == B and Index[Clutch.Output] or Index[Clutch.Input]

			if Visited[Other] then return false end -- A loop, or two clutches between the same bodies

			Visit(Other, C, Index[Clutch.Output] == Other)
		end

		Children[B][#Children[B] + 1] = C

		return true
	end

	-- Bodies come shafts first, so engines become the roots
	for Root = 1, #Bodies do
		if not Visited[Root] then
			Visit(Root, 0, false)

			local Head = #Order

			while Head <= #Order do
				local B = Order[Head]

				Head = Head + 1

				for _, C in ipairs(Adjacent[B]) do
					if C ~= ParentEdge[B] and not Attach(B, C) then return end
				end
			end
		end
	end

	local TermIndex, ChildOf = {}, {}

	for C, Clutch in ipairs(Clutches) do
		local Terms = {}

		for Terminal = 1, Clutch.Terminals do Terms[Terminal] = Index[Clutch:GetBody(Terminal)] end

		TermIndex[C] = Terms
	end

	for B = 1, #Bodies do
		local C = ParentEdge[B]

		if C ~= 0 and not Junctions[C] then ChildOf[C] = B end
	end

	local Fallback = Drivetrain.Solver.New(Bodies, Clutches)

	return setmetatable({
		Bodies      = Bodies,
		Clutches    = Clutches,
		Count       = #Clutches,
		Order       = Order,
		ParentEdge  = ParentEdge,
		IsOutput    = IsOutput,
		Children    = Children,
		TermIndex   = TermIndex, -- Per clutch: the bodies it touches, by terminal
		ChildOf     = ChildOf,
		Junctions   = Junctions,
		Fallback    = Fallback,
		Bound       = Fallback.Bound, -- Shared, so either solver warm starts from the other's last tick
		BoundSign   = Fallback.BoundSign,
		UseFallback = false,
		Free        = {},
		Fixed       = {}, -- Per body: impulse from the clutches not solved this round
		UpInertia   = {}, -- Per body: its locked subtree as one inertia and momentum, in its own frame
		UpMomentum  = {},
		OutInertia  = {}, -- Per body: everything locked to it outside its subtree, in its own frame
		OutMomentum = {},
		-- Per clutch or junction to a child: what the child's subtree adds to the parent, in the parent's
		-- frame
		AddInertia  = {},
		AddMomentum = {},
		Speed       = {}, -- Per body: speed once this round's impulses are in
		After       = {}, -- Per held clutch: its slip once this round's impulses are in
		Wants       = {},
		RigidParent = {}, -- Per body, for finding immovable bodies rigidly tied together
		RigidSeen   = {},
	}, TreeSolver)
end

do -- MARK: Solving
	local function FindRoot(Parent, B)
		while Parent[B] ~= B do
			Parent[B] = Parent[Parent[B]]
			B         = Parent[B]
		end

		return B
	end

	local function IsRigid(Clutch)
		return Clutch.MaxImpulse == huge and Clutch.Softness == 0 and not Clutch.Fixed
	end

	-- Two immovable bodies tied by clutches that can neither slip nor give, at different speeds, need an
	-- endless push to lock; the dense solver gives way there instead. Any clutch that can slip is held at its
	-- capacity by the pivoting.
	local function RigidlyJoined(self)
		local Bodies   = self.Bodies
		local Clutches = self.Clutches
		local Touches  = 0

		-- Brake blocks and engine blocks are immovable too, but only ever held by clutches that slip
		for C = 1, self.Count do
			local Clutch = Clutches[C]

			if IsRigid(Clutch) then
				for Terminal = 1, Clutch.Terminals do
					if Clutch:GetBody(Terminal).Inertia >= IMMOVABLE then Touches = Touches + 1 end
				end
			end
		end

		if Touches < 2 then return false end

		local Parent = self.RigidParent
		local Seen   = self.RigidSeen
		local Joined = false

		for B = 1, #Bodies do Parent[B] = B end

		for C = 1, self.Count do
			local Clutch = Clutches[C]

			if IsRigid(Clutch) then
				local Terms = self.TermIndex[C]
				local In    = FindRoot(Parent, Terms[1])

				-- A differential's sides join only through its input, at the least
				for Terminal = 2, #Terms do Parent[FindRoot(Parent, Terms[Terminal])] = In end
			end
		end

		for B = 1, #Bodies do
			if Bodies[B].Inertia >= IMMOVABLE then
				local Root = FindRoot(Parent, B)

				if Seen[Root] then Joined = true end

				Seen[Root] = true
			end
		end

		for B = 1, #Bodies do Seen[B] = nil end

		return Joined
	end

	--- Leaves ticks this solver can't take to the dense one.
	function TreeSolver:Prepare()
		local Clutches  = self.Clutches
		local Bound     = self.Bound
		local BoundSign = self.BoundSign
		local Fallback  = false

		for C = 1, self.Count do
			local Clutch = Clutches[C]

			-- One a limit already fixed keeps what it was fixed at; one made rigid since, as a locked
			-- differential, starts free
			if Bound[C] and Clutch.MaxImpulse > 0 and Clutch.MaxImpulse < huge and not Clutch.Fixed then
				Clutch.Impulse = BoundSign[C] * Clutch.MaxImpulse
			else
				Bound[C] = false
			end

			if Clutch.MaxImpulse > 0 and Clutch.Gain <= MIN_GAIN then Fallback = true end
		end

		if not Fallback and RigidlyJoined(self) then Fallback = true end

		self.UseFallback = Fallback

		if Fallback then self.Fallback:Prepare() end
	end

	-- A clutch seen from the child end: the child's share of its impulse, the child's speed per unit of the
	-- parent's, and the parent's share
	local function Across(Clutch, ChildIsOutput)
		if ChildIsOutput then return Clutch.Gain, Clutch.Ratio, -Clutch.Ratio end

		return -Clutch.Ratio, 1 / Clutch.Ratio, Clutch.Gain
	end

	-- A compliant clutch's give and windup, as speed the child may lag the parent's lead by; slip counts the
	-- other way round, and in the input's frame, when the child is the input
	local function Compliance(Clutch, ChildIsOutput)
		local Sense = ChildIsOutput and 1 or -Clutch.Ratio

		return Clutch.Softness / Sense, Clutch.Bias / Sense
	end

	-- The impulses that hold whichever of a junction's carrier (P) and locker (Q) are free, given each of
	-- its three sides (input, left, right) as a mobility and the speed it would turn at untouched. One side
	-- may instead be given a speed (mobility 0, speed 0, Given 1), and P and Q then come as a constant plus a
	-- share of that speed. Expanded so each side's speed carries its own weight and the divisor is a sum, as
	-- an immovable side next to a light one would otherwise cancel nearly all of it.
	local function SolveJunction(Carrier, Locker, CF, KF, M0, V0, G0, ML, VL, GL, MR, VR, GR)
		local Ratio, Gain, Sc, Bc = Carrier.Ratio, Carrier.Gain, Carrier.Softness, Carrier.Bias
		local Rk, Gk, Sk, Bk      = Locker.Ratio, Locker.Gain, Locker.Softness, Locker.Bias
		local Rigid               = Ratio * Ratio * M0 + Sc
		local Sides               = 0.25 * Gain * (ML + MR)

		if CF and KF then
			local Y   = Rk * Rk * ML + Gk * MR + Sk
			local Det = Rigid * Y + Sides * Sk + 0.25 * Gain * ML * MR * (1 + Rk) * (Gk + Rk)

			if Det == 0 then Degenerate = true return 0, 0, 0, 0 end

			-- What each side's speed weighs in the carrier's impulse
			local WL = 0.5 * (Gk * MR * (1 + Rk) + Sk)
			local WR = 0.5 * (Rk * ML * (1 + Rk) + Sk)
			local Cp = 0.5 * (Rk * ML - Gk * MR)
			local Cq = 0.5 * Gain * (Rk * ML - MR)
			local SG = 0.25 * Gain * (1 + Rk)

			local Pc = ((Ratio * V0 + Bc) * Y - WL * VL - WR * VR + Cp * Bk) / Det
			local Ps = (Ratio * G0 * Y - WL * GL - WR * GR) / Det
			local Qc = ((Rk * VL - VR) * Rigid + SG * (VL * MR - VR * ML) + Cq * (Ratio * V0 + Bc)
				+ (Rigid + Sides) * Bk) / Det
			local Qs = ((Rk * GL - GR) * Rigid + SG * (GL * MR - GR * ML) + Cq * Ratio * G0) / Det

			return Pc, Ps, Qc, Qs
		elseif CF then
			local A = Rigid + Sides

			if A == 0 then Degenerate = true return 0, 0, 0, 0 end

			return (Ratio * V0 - 0.5 * (VL + VR) + Bc) / A, (Ratio * G0 - 0.5 * (GL + GR)) / A, 0, 0
		elseif KF then
			local Y = Rk * Rk * ML + Gk * MR + Sk

			if Y == 0 then Degenerate = true return 0, 0, 0, 0 end

			return 0, 0, (Rk * VL - VR + Bk) / Y, (Rk * GL - GR) / Y
		end

		return 0, 0, 0, 0
	end

	-- What the rest of a junction looks like from each of its sides: the impulse it puts on that side, as a
	-- constant less a share of the side's speed. SolveJunction with that side's speed given, worked out for
	-- both sides at once, with the terms the given side zeroes left out and the rest added in the same order,
	-- so it comes out exactly the same.
	local function SideViews(Carrier, Locker, CF, KF, M0, V0, ML, VL, MR, VR, Half)
		local Ratio, Gain, Sc, Bc = Carrier.Ratio, Carrier.Gain, Carrier.Softness, Carrier.Bias
		local Rk, Gk, Sk, Bk      = Locker.Ratio, Locker.Gain, Locker.Softness, Locker.Bias

		if CF and KF then
			local Rigid = Ratio * Ratio * M0 + Sc
			local Lead  = Ratio * V0 + Bc
			local SG    = 0.25 * Gain * (1 + Rk)

			-- Left given: everything from the right
			local SidesL = 0.25 * Gain * MR
			local YL     = Gk * MR + Sk
			local DetL   = Rigid * YL + SidesL * Sk

			-- Right given: everything from the left
			local SidesR = 0.25 * Gain * ML
			local YR     = Rk * Rk * ML + Sk
			local DetR   = Rigid * YR + SidesR * Sk

			if DetL == 0 or DetR == 0 then Degenerate = true return 0, 0, 0, 0 end

			local WL  = 0.5 * (Gk * MR * (1 + Rk) + Sk)
			local WR  = 0.5 * Sk
			local Pc  = (Lead * YL - WR * VR + 0.5 * -(Gk * MR) * Bk) / DetL
			local Ps  = -WL / DetL
			local Qc  = (-VR * Rigid + 0.5 * Gain * -MR * Lead + (Rigid + SidesL) * Bk) / DetL
			local Qs  = (Rk * Rigid + SG * MR) / DetL
			local OML = Half * Pc - Rk * Qc
			local OIL = Rk * Qs - Half * Ps

			WL = 0.5 * Sk
			WR = 0.5 * (Rk * ML * (1 + Rk) + Sk)
			Pc = (Lead * YR - WL * VL + 0.5 * (Rk * ML) * Bk) / DetR
			Ps = -WR / DetR
			Qc = (Rk * VL * Rigid + 0.5 * Gain * (Rk * ML) * Lead + (Rigid + SidesR) * Bk) / DetR
			Qs = (-Rigid - SG * ML) / DetR

			return OML, OIL, Half * Pc + Gk * Qc, -Half * Ps - Gk * Qs
		elseif CF then
			local Rigid = Ratio * Ratio * M0 + Sc
			local AL    = Rigid + 0.25 * Gain * MR
			local AR    = Rigid + 0.25 * Gain * ML

			if AL == 0 or AR == 0 then Degenerate = true return 0, 0, 0, 0 end

			return Half * ((Ratio * V0 - 0.5 * VR + Bc) / AL), -(Half * (-0.5 / AL)),
				Half * ((Ratio * V0 - 0.5 * VL + Bc) / AR), -Half * (-0.5 / AR)
		end

		local YL = Gk * MR + Sk
		local YR = Rk * Rk * ML + Sk

		if YL == 0 or YR == 0 then Degenerate = true return 0, 0, 0, 0 end

		return -(Rk * ((-VR + Bk) / YL)), Rk * (Rk / YL), Gk * ((Rk * VL + Bk) / YR), -(Gk * (-1 / YR))
	end

	-- Going up: with its carrier free, a junction adds both sides' subtrees to its input, through whatever
	-- the locker holds
	local function JunctionUp(self, C)
		local Junction   = self.Junctions[C]
		local Clutches   = self.Clutches
		local UpInertia  = self.UpInertia
		local UpMomentum = self.UpMomentum
		local Carrier    = Clutches[C]
		local L, R       = Junction.Left, Junction.Right

		local Pc, Ps = SolveJunction(Carrier, Clutches[Junction.Locker], true, self.Free[Junction.Locker],
			0, 0, 1,
			1 / UpInertia[L], UpMomentum[L] / UpInertia[L], 0,
			1 / UpInertia[R], UpMomentum[R] / UpInertia[R], 0)

		self.AddInertia[C]  = Carrier.Ratio * Ps
		self.AddMomentum[C] = -Carrier.Ratio * Pc
	end

	-- Coming down: the junction's impulses between its input's side and both of its own, then each side's
	-- speed and what the rest of the junction looks like from it
	local function JunctionDown(self, C, SideInertia, SideMomentum)
		local Junction    = self.Junctions[C]
		local Clutches    = self.Clutches
		local Free        = self.Free
		local UpInertia   = self.UpInertia
		local UpMomentum  = self.UpMomentum
		local OutInertia  = self.OutInertia
		local OutMomentum = self.OutMomentum
		local Speed       = self.Speed
		local L, R        = Junction.Left, Junction.Right
		local K           = Junction.Locker
		local Carrier     = Clutches[C]
		local Locker      = Clutches[K]
		local CF, KF      = Free[C], Free[K]

		if not CF and not KF then -- Nothing ties the sides to anything, so each is the root of its own group
			OutInertia[L], OutMomentum[L] = 0, 0
			OutInertia[R], OutMomentum[R] = 0, 0
			Speed[L] = UpMomentum[L] / UpInertia[L]
			Speed[R] = UpMomentum[R] / UpInertia[R]

			return
		end

		local M0, V0 = 0, 0

		if CF then M0, V0 = 1 / SideInertia, SideMomentum / SideInertia end

		local ML, VL = 1 / UpInertia[L], UpMomentum[L] / UpInertia[L]
		local MR, VR = 1 / UpInertia[R], UpMomentum[R] / UpInertia[R]
		local Half   = 0.5 * Carrier.Gain
		local Rk, Gk = Locker.Ratio, Locker.Gain

		local P, _, Q = SolveJunction(Carrier, Locker, CF, KF, M0, V0, 0, ML, VL, 0, MR, VR, 0)

		if CF then Carrier.Impulse = P end
		if KF then Locker.Impulse = Q end

		Speed[L] = VL + ML * (Half * P - Rk * Q)
		Speed[R] = VR + MR * (Half * P + Gk * Q)

		OutMomentum[L], OutInertia[L], OutMomentum[R], OutInertia[R] = SideViews(Carrier, Locker, CF, KF, M0,
			V0, ML, VL, MR, VR, Half)
	end

	-- Coming down: a plain clutch's impulse between its parent's side and its child's subtree
	local function ClutchDown(self, D, SideInertia, SideMomentum)
		local Child                           = self.ChildOf[D]
		local Clutch                          = self.Clutches[D]
		local IsOutput                        = self.IsOutput[Child]
		local ChildShare, Follow, ParentShare = Across(Clutch, IsOutput)
		local Give, Lean                      = Compliance(Clutch, IsOutput)
		local ChildInertia, ChildMomentum     = self.UpInertia[Child], self.UpMomentum[Child]
		local Impulse = (Follow * SideMomentum / SideInertia - ChildMomentum / ChildInertia + Lean)
			/ (ChildShare / ChildInertia - Follow * ParentShare / SideInertia + Give)
		local Through = Give * SideInertia / Follow -- The parent side, seen through the give

		Clutch.Impulse          = Impulse
		self.Speed[Child]       = (ChildMomentum + ChildShare * Impulse) / ChildInertia
		self.OutInertia[Child]  = -ChildShare * SideInertia / (Follow * ParentShare - Give * SideInertia)
		self.OutMomentum[Child] = -ChildShare * (SideMomentum + Lean * SideInertia / Follow)
			/ (ParentShare - Through)
	end

	-- Locks every free clutch against the impulses of the rest. Going up, each locked subtree becomes one
	-- inertia and momentum; coming down, each clutch is solved between everything on either side of it, as a
	-- speed difference over the two sides' summed mobility, so an immovable output only adds its tiny
	-- mobility instead of a huge inertia to cancel.
	local function Pass(self)
		local Bodies      = self.Bodies
		local Clutches    = self.Clutches
		local Order       = self.Order
		local ParentEdge  = self.ParentEdge
		local IsOutput    = self.IsOutput
		local Children    = self.Children
		local TermIndex   = self.TermIndex
		local Junctions   = self.Junctions
		local Bound       = self.Bound
		local Free        = self.Free
		local Fixed       = self.Fixed
		local UpInertia   = self.UpInertia
		local UpMomentum  = self.UpMomentum
		local OutInertia  = self.OutInertia
		local OutMomentum = self.OutMomentum
		local AddInertia  = self.AddInertia
		local AddMomentum = self.AddMomentum
		local Speed       = self.Speed

		for B = 1, #Bodies do Fixed[B] = 0 end

		for C = 1, self.Count do
			local Clutch = Clutches[C]
			local IsFree = Clutch.MaxImpulse > 0 and not Clutch.Fixed and not Bound[C]

			Free[C] = IsFree

			if not IsFree then
				local Impulse = Clutch.Impulse

				if Impulse ~= 0 then
					local Terms = TermIndex[C]

					for Terminal = 1, #Terms do
						local B = Terms[Terminal]

						Fixed[B] = Fixed[B] + Clutch:GetEffect(Terminal) * Impulse
					end
				end
			end
		end

		for K = #Order, 1, -1 do
			local B        = Order[K]
			local Body     = Bodies[B]
			local Inertia  = Body.Inertia
			local Momentum = Inertia * Body.Omega + Fixed[B]

			for _, D in ipairs(Children[B]) do
				if Free[D] then
					if Junctions[D] then JunctionUp(self, D) end -- Both of its sides are summed up by now

					Inertia  = Inertia + AddInertia[D]
					Momentum = Momentum + AddMomentum[D]
				end
			end

			UpInertia[B], UpMomentum[B] = Inertia, Momentum

			local C = ParentEdge[B]

			if C ~= 0 and Free[C] and not Junctions[C] then
				local ChildShare, Follow, ParentShare = Across(Clutches[C], IsOutput[B])
				local Give, Lean                      = Compliance(Clutches[C], IsOutput[B])
				local Share                           = ChildShare + Give * Inertia

				AddInertia[C]  = -ParentShare * Inertia * Follow / Share
				AddMomentum[C] = ParentShare * (Lean * Inertia - Momentum) / Share
			end
		end

		for K = 1, #Order do
			local B = Order[K]
			local C = ParentEdge[B]

			-- The root of a locked group, or a body nothing locks; a junction's sides were set coming down to
			-- it
			if C == 0 or not Free[C] and not Junctions[C] then
				OutInertia[B], OutMomentum[B] = 0, 0
				Speed[B] = UpMomentum[B] / UpInertia[B]
			end

			local Body        = Bodies[B]
			local OwnInertia  = Body.Inertia + OutInertia[B]
			local OwnMomentum = Body.Inertia * Body.Omega + Fixed[B] + OutMomentum[B]
			local Kids        = Children[B]

			for _, D in ipairs(Kids) do
				local Junction = Junctions[D]

				if Free[D] or Junction then
					-- Summed afresh, as subtracting a heavy sibling would cancel
					local SideInertia, SideMomentum = OwnInertia, OwnMomentum

					for _, E in ipairs(Kids) do
						if E ~= D and Free[E] then
							SideInertia  = SideInertia + AddInertia[E]
							SideMomentum = SideMomentum + AddMomentum[E]
						end
					end

					if Junction then
						JunctionDown(self, D, SideInertia, SideMomentum)
					else
						ClutchDown(self, D, SideInertia, SideMomentum)
					end
				end
			end
		end
	end

	-- Each held clutch's slip once this round's impulses are in, for the pivoting to judge
	local function Settle(self)
		local Clutches  = self.Clutches
		local Bound     = self.Bound
		local Speed     = self.Speed
		local TermIndex = self.TermIndex
		local After     = self.After

		for C = 1, self.Count do
			if Bound[C] then
				local Clutch = Clutches[C]
				local Terms  = TermIndex[C]
				local Slip   = 0

				for Terminal = 1, #Terms do
					Slip = Slip + Clutch:GetSense(Terminal) * Speed[Terms[Terminal]]
				end

				After[C] = Slip - Clutch.Softness * Clutch.Impulse + Clutch.Bias
			end
		end

		return Pivoting.Settle(self, Clutches, self.Free, Bound, After, self.Wants)
	end

	--- Keeps whatever the limits fixed since the last call.
	function TreeSolver:Solve()
		if self.UseFallback then return self.Fallback:Solve() end

		local Clutches  = self.Clutches
		local Bound     = self.Bound
		local BoundSign = self.BoundSign

		local Settled = false

		Degenerate = false

		Pivoting.Begin(self)

		for _ = 1, MAX_ROUNDS * self.Count + MAX_ROUNDS do
			Pass(self)

			if Degenerate then break end
			if not Settle(self) then Settled = true break end
		end

		if Degenerate then -- Rare enough that this tick is simply solved again the general way
			-- The dense solver warm starts from the signs, which have to be those the rounds so far held at
			for C = 1, self.Count do
				if Bound[C] then BoundSign[C] = Clutches[C].Impulse < 0 and -1 or 1 end
			end

			self.Fallback:Prepare()

			return self.Fallback:Solve()
		end

		if not Settled then Pivoting.Project(Clutches, Bound) end

		for C = 1, self.Count do
			local Clutch = Clutches[C]

			Clutch.Saturated = Bound[C] or Clutch.Fixed

			if Bound[C] then BoundSign[C] = Clutch.Impulse < 0 and -1 or 1 end
		end
	end
end
