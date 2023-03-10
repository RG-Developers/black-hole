AddCSLuaFile()

-- Создаем новую энтити и задаем ей модель
DEFINE_BASECLASS( "base_anim" )

ENT.PrintName = "Black Hole - Eating"
ENT.Category = "Black Hole"

ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Editable = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar( "Float", 0, "BlackHoleSize", { KeyName = "BlackHoleSize", Edit = { type = "Float", min = 1, max = 10000, order = 1 } } )
    if ( SERVER ) then
        self:NetworkVarNotify( "BlackHoleSize", self.OnBallSizeChanged )
    end
end
if ( SERVER ) then
    function ENT:OnBallSizeChanged( varname, oldvalue, newvalue )
        -- Do not rebuild if the size wasn't changed
        if ( oldvalue == newvalue ) then return end
        self.TargetAttractRadius = newvalue
    end
end

-- Инициализация энтити
function ENT:Initialize()
    self:SetModel("models/Combine_Helicopter/helicopter_bomb01.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WORLD)
    self:SetMaterial("models/shiny")
    self:SetColor(Color(0,0,0,255))

    -- Задаем начальный радиус притяжения и силу притяжения
    self.AttractRadius = 0
    self.TargetAttractRadius = 1000
    self.AttractStrength = 0
    self.refractMaterial = Material("models/props_c17/fisheyelens")

    self:RebuildPhysics()

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        phys:Wake()
    end
    self:SetNWInt("AttractRadius", self.AttractRadius)
    self:SetBlackHoleSize(self.TargetAttractRadius)
    if CLIENT then
        local radius = self.AttractRadius
        local vOffset = self:GetPos()

        local emitter = ParticleEmitter( vOffset )
        timer.Create("BlackHoleDisk"..self:EntIndex(), 0.1, 0, function()
            if not IsValid(self) then
                return
            end

            local Low, High = self:WorldSpaceAABB()
            local size = High.x - Low.x
            Low.y = Low.y - size
            High.y = High.y + size
            Low.x = Low.x - size
            High.x = High.x + size
            for i=0,50 do
                local vPos = Vector( math.Rand( Low.x, High.x ), math.Rand( Low.y, High.y ), (Low.z + High.z) / 2 )
                local particle = emitter:Add( "effects/spark", vPos )
                if ( particle ) then
                    local vel = ((self:GetPos() - vPos) / 2)
                    vel:Rotate(Angle(0,90,0))
                    particle:SetVelocity( vel )
                    particle:SetLifeTime( 0 )
                    particle:SetDieTime( 2 )
                    particle:SetStartAlpha( 255 )
                    particle:SetEndAlpha( 0 )
                    particle:SetStartSize( self:GetNWInt("AttractRadius") / 50 )
                    particle:SetEndSize( 0 )
                    --particle:SetRoll( math.Rand(0, 360) )
                    particle:SetRollDelta( 0 )
                    particle:SetRoll(90)
                    particle:SetColor(math.random(200,255), math.random(0,155), 0)

                    particle:SetAirResistance( 0 )
                    particle:SetGravity( vel )
                    particle:SetCollide( false )

                end
            end
        end)
    end
end

function ENT:SpawnFunction( ply, tr, ClassName )

    if ( !tr.Hit ) then return end

    local SpawnPos = tr.HitPos + tr.HitNormal * 10

    -- Make sure the spawn position is not out of bounds
    local oobTr = util.TraceLine( {
        start = tr.HitPos,
        endpos = SpawnPos,
        mask = MASK_SOLID_BRUSHONLY
    } )

    if ( oobTr.Hit ) then
        SpawnPos = oobTr.HitPos + oobTr.HitNormal * ( tr.HitPos:Distance( oobTr.HitPos ) / 2 )
    end

    local ent = ents.Create( ClassName )
    ent:SetPos( SpawnPos )
    ent:Spawn()

    return ent

end

function ENT:RebuildPhysics()
    local size = self:GetNWInt("AttractRadius") / 1000 * 32
    self:PhysicsInitSphere( size )
    self:SetCollisionBounds( Vector( -size, -size, -size ), Vector( size, size, size ) )
    self:PhysWake()
    --self:SetMoveType(MOVETYPE_NONE)
    if IsValid(self) and IsValid(self:GetPhysicsObject()) then
        self:GetPhysicsObject():EnableGravity(false)
    end
    --self:SetNotSolid( true )
end

-- Обновление энтити
function ENT:Think()
    if SERVER then
        self.AttractRadius = self.AttractRadius + math.floor((self.TargetAttractRadius - self.AttractRadius) / 50)
        if self.AttractRadius ~= self:GetNWInt("AttractRadius") then
            self:SetNWInt("AttractRadius", self.AttractRadius)
            self:RebuildPhysics()
            self:GetPhysicsObject():SetMass(self.AttractRadius)
            self.AttractStrength = self.AttractRadius * .5
            self:SetNWInt("AttractStrength", self.AttractStrength)
        end
        -- Находим все объекты в заданном радиусе
        local objects = ents.FindInSphere(self:GetPos(), self.AttractRadius)

        -- Притягиваем каждый объект к энтити
        for _, object in pairs(objects) do
            if object ~= self then -- Исключаем саму энтити из притяжения
                if not IsValid(object) or not IsValid(object:GetPhysicsObject()) then continue end
                if object:IsPlayer() and not object:Alive() then return end

                local direction = self:GetPos() - object:GetPos()
                local distance = direction:Length()

                if distance < self:GetNWInt("AttractRadius") / 1000 * 50 then
                    if object:IsPlayer() then
                        object:Kill()
                        continue
                    end
                    if object:GetClass() == "black_hole" or object:GetClass() == "black_hole_nonadmin" then
                        if self.AttractStrength < object:GetNWInt("AttractStrength") then continue end
                        self.TargetAttractRadius = self.TargetAttractRadius + object:GetNWInt("AttractStrength") * 0.5
                        object:Remove()
                        continue
                    end
                    self.TargetAttractRadius = self.TargetAttractRadius + object:GetPhysicsObject():GetMass() * 0.5
                    object:Remove()
                    continue
                end

                -- Задаем силу притяжения, которая затухает по мере отдаления от энтити
                local force = direction:GetNormalized() * (self.AttractStrength * (self.AttractRadius - distance) / self.AttractRadius) + (Vector(0,0,-1) - direction:GetNormalized() * -600)
                local dt = engine.TickInterval() 
                if object:IsPlayer() then
                    if object:IsOnGround() then
                        object:SetVelocity( force * dt + Vector(0,0,500) * ((self.AttractRadius - distance) / self.AttractRadius))
                    else
                        object:SetVelocity( force * dt )
                    end
                end
                object:GetPhysicsObject():AddVelocity( force * dt )
            end
        end
        -- Задержка между обновлениями
        self:NextThink(CurTime() + 0.02)
    end
    return true
end

-- Отрисовываем радиус притяжения на клиентах
if CLIENT then
    function ENT:Draw()
        local event_horizon = Color(0, 127, 255, 55)
        local black_hole = Color(0, 0, 0, 255)
        local affection_radius = Color(255, 0, 0, 15)
        local detail = 16
        --self:DrawModel()

        self.refractMaterial:SetFloat( "$envmap", 0 )
        self.refractMaterial:SetFloat( "$envmaptint", 0 )
        self.refractMaterial:SetInt( "$ignorez", 1 )

        local baserad = self:GetNWInt("AttractRadius")
        local str = 0.5

        baserad = baserad * ((((math.sin(RealTime()) + 1) / 2) / 10 * str) + (1 - (str/10)))

        for mul=64,33, -64 do
            self.refractMaterial:SetFloat( "$refractamount", -(1/(mul/4)) )
            render.SetMaterial(self.refractMaterial)
            render.DrawSphere(self:GetPos(), (baserad / 1000 * mul), detail, detail, event_horizon)
            render.DrawSphere(self:GetPos(), -(baserad / 1000 * mul), detail, detail, event_horizon)
        end

        render.SetColorMaterial()
        render.DrawSphere(self:GetPos(), (baserad / 1000 * 64), detail, detail, event_horizon)
        render.DrawSphere(self:GetPos(), (self:GetNWInt("AttractRadius")), detail, detail, affection_radius)
        render.DrawSphere(self:GetPos(), (baserad / 1000 * 32), detail, detail, black_hole)
        render.DrawSphere(self:GetPos(), -(baserad / 1000 * 64), detail, detail, event_horizon)
        render.DrawSphere(self:GetPos(), -(self:GetNWInt("AttractRadius")), detail, detail, affection_radius)
        render.DrawSphere(self:GetPos(), -(baserad / 1000 * 32), detail, detail, black_hole)
    end
end