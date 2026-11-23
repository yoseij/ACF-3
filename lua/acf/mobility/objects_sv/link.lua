local ACF	= ACF
local Meta	= {}
local String	= "Link [Source = %s, Target = %s, Origin = %s, Axis = %s]"
local Objects	= ACF.Mobility.Objects

function Objects.Link(Source, Target)
	local Link = {
		Source    = Source,
		Target    = Target,
		Origin    = Vector(),
		TargetPos = Vector(),
		Axis      = Vector(1, 0, 0),
	}

	setmetatable(Link, Meta)

	return Link
end

function Meta:ToString()
	return String:format(self.Source, self.Target, self.Origin, self.Axis)
end

AccessorFunc(Meta, "Source", "Source")
AccessorFunc(Meta, "Target", "Target")
AccessorFunc(Meta, "Origin", "Origin", FORCE_VECTOR)
AccessorFunc(Meta, "Axis", "Axis", FORCE_VECTOR)
AccessorFunc(Meta, "TargetPos", "TargetPos", FORCE_VECTOR)

Meta.__index	= Meta
Meta.__tostring	= Meta.ToString