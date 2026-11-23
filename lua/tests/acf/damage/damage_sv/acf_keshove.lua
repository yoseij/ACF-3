local Ones = Vector( 1, 1, 1 )

return {
    groupName = "ACF.KeShove",

    beforeEach = function( State )
        State.applyForceStub = stub()

        State.Ent = {
            ACF_TotalMass = 1,
            ACF_PhysicalMass = 1,
            ACF_MassTime = math.huge,

            IsValid = function() return true end,
            WorldToLocal = function() return Ones end,
            LocalToWorld = function() return Ones end,
            GetPhysicsObject = function()
                return {
                    IsValid = function() return true end,
                    ApplyForceOffset = State.applyForceStub,
                    GetMass = function() return 1 end,
                }
            end,
            GetChildren = function() return {} end,
            -- Not part of a contraption, so it keeps its own count
            CFW_GetContraption = function() return nil end,
            GetAncestor = function() return State.Ent end, -- For simplicity's sake, we'll pretend the ent's ancestor is itself
        }
    end,

    cases = {
        {
            name = "Shoves the target",
            func = function( State )
                local Ent = State.Ent

                ACF.KEShove( Ent, Ones, Ones, 1 )

                expect( State.applyForceStub ).was.called()
            end
        },

        {
            name = "Does not shove invalid targets",
            func = function( State )
                local Ent = State.Ent
                Ent.IsValid = function() return false end

                ACF.KEShove( Ent, Ones, Ones, 1 )

                expect( State.applyForceStub ).wasNot.called()
            end
        },
        {
            name = "Does not shove the entity if ACF_KEShove hook returns false",
            func = function( State )
                hook.Add( "ACF_OnPushEntity", "Test", function() return false end )
                local Ent = State.Ent

                ACF.KEShove( Ent, Ones, Ones, 1 )

                expect( State.applyForceStub ).wasNot.called()
            end,

            cleanup = function()
                hook.Remove( "ACF_OnPushEntity", "Test" )
            end
        },

        {
            name = "Calculates the Mass if its mass was never counted",
            func = function( State )
                local Ent = State.Ent
                Ent.ACF_MassTime = nil

                local calcMass = stub( ACF.Contraption, "CalcMassRatio" )
                ACF.KEShove( Ent, Ones, Ones, 1 )

                expect( calcMass ).was.called()
            end
        },

        {
            name = "Calculates the Mass if its mass count is stale",
            func = function( State )
                local Ent = State.Ent
                Ent.ACF_MassTime = -math.huge

                local calcMass = stub( ACF.Contraption, "CalcMassRatio" )
                ACF.KEShove( Ent, Ones, Ones, 1 )

                expect( calcMass ).was.called()
            end
        },

        {
            name = "Does not recount a fresh count",
            func = function( State )
                local Ent = State.Ent
                Ent.ACF_MassTime = CurTime()

                local calcMass = stub( ACF.Contraption, "CalcMassRatio" )
                ACF.KEShove( Ent, Ones, Ones, 1 )

                expect( calcMass ).wasNot.called()
            end
        },

        {
            name = "Scales the shove by its contraption's count, not its own",
            func = function( State )
                local Ent   = State.Ent
                local Con   = { ACF_PhysicalMass = 1, ACF_TotalMass = 4, ACF_MassTime = math.huge }
                local Force

                Ent.CFW_GetContraption = function() return Con end
                Ent.GetPhysicsObject = function()
                    return {
                        IsValid = function() return true end,
                        ApplyForceOffset = function( _, Applied ) Force = Applied end,
                        GetMass = function() return 1 end,
                    }
                end

                ACF.KEShove( Ent, Ones, Ones, 1 )

                expect( Force:Length() ).to.aboutEqual( 0.25, 1e-6 )
            end
        }
    }
}
