local config = require("jellotris.config")
local shapes = require("jellotris.shapes")
local Face = require("jellotris.face")
local Rock = {}
Rock.__index = Rock

function Rock.new(world, name, x, y, id, options)
    options = options or {}
    local cells = options.cells or shapes.definitions[name].cells
    local min_x, min_y, max_x, max_y = shapes.bounds(cells)
    local middle_x, middle_y = (min_x + max_x) / 2, (min_y + max_y) / 2
    local active = options.active or false
    local self = setmetatable({
        name = name, material = "rock", color = config.rock_color, id = id,
        cells = {}, active = active, locked = not active,
        target_angle = options.angle or 0, age = 0,
        slammed = false, contact_time = 0, has_landed = false,
    }, Rock)

    -- One rigid body, four independently removable stone fixtures.
    -- Placed stone is genuinely static, including fragments left by a line clear.
    self.body = love.physics.newBody(world, x, y, active and "dynamic" or "static")
    self.body:setAngle(self.target_angle)
    self.body:setBullet(true)
    self.body:setLinearDamping(0.65)
    self.body:setAngularDamping(1)
    self.body:setGravityScale(0.14)
    local half, bevel = config.cell_size / 2 - 0.4, 3
    for _, source in ipairs(cells) do
        local cx = (source[1] + 0.5 - middle_x) * config.cell_size
        local cy = (source[2] + 0.5 - middle_y) * config.cell_size
        local shape = love.physics.newPolygonShape(
            cx - half + bevel, cy - half, cx + half - bevel, cy - half,
            cx + half, cy - half + bevel, cx + half, cy + half - bevel,
            cx + half - bevel, cy + half, cx - half + bevel, cy + half,
            cx - half, cy + half - bevel, cx - half, cy - half + bevel)
        local fixture = love.physics.newFixture(self.body, shape, 1.4)
        fixture:setFriction(0.42)
        fixture:setRestitution(0.04)
        local cell = {x = cx, y = cy, fixture = fixture, alive = true, piece = self}
        fixture:setUserData({piece = self, cell = cell})
        self.cells[#self.cells + 1] = cell
    end
    Face.attach(self)
    return self
end

function Rock:center()
    local x, y = self.body:getPosition()
    local vx, vy = self.body:getLinearVelocity()
    return x, y, vx, vy
end

function Rock:angle()
    return self.body:getAngle()
end

function Rock:cell_center(cell)
    return self.body:getWorldPoint(cell.x, cell.y)
end

function Rock:cell_vertex(cell, index)
    local half = config.cell_size / 2
    local x = cell.x + ((index - 1) % 3 - 1) * half
    local y = cell.y + (math.floor((index - 1) / 3) - 1) * half
    return self.body:getWorldPoint(x, y)
end

function Rock:stabilize()
    -- Rigid fixtures already preserve volume and shape.
end

function Rock:drive(dt, horizontal, soft_drop, level)
    self.age = self.age + dt
    if not self.active then return end
    local vx, vy = self.body:getLinearVelocity()
    local target_speed = self.slammed and 980 or (soft_drop and 290 or 46 + level * 5)
    local fx = (horizontal * 185 - vx) * 11
    local fy = (target_speed - vy) * (self.slammed and 9 or 4) - config.gravity * 0.14
    self.body:applyForce(fx * self.body:getMass(), fy * self.body:getMass())
    local difference = (self.target_angle - self.body:getAngle() + math.pi) % (math.pi * 2) - math.pi
    local angular_acceleration = difference * 95 - self.body:getAngularVelocity() * 14
    self.body:applyTorque(angular_acceleration * self.body:getInertia())
end

function Rock:set_active(active)
    self.active, self.locked = active, not active
    self.body:setLinearVelocity(0, 0)
    self.body:setAngularVelocity(0)
    self.body:setType(active and "dynamic" or "static")
    if active then self.body:setAwake(true) end
end

function Rock:slam()
    if not self.active then return end
    self.slammed = true
    local vx, vy = self.body:getLinearVelocity()
    self.body:setLinearVelocity(vx * 0.45, math.max(vy, 880))
end

function Rock:remove_cells(removed)
    local remaining = 0
    for _, cell in ipairs(self.cells) do
        if cell.alive and removed[cell] then
            cell.alive = false
            cell.fixture:destroy()
            if cell.mesh then cell.mesh:release(); cell.mesh = nil end
        end
        if cell.alive then remaining = remaining + 1 end
    end
    if remaining == 0 and not self.body:isDestroyed() then self.body:destroy() end
    Face.attach(self)
    return remaining > 0
end

function Rock:destroy()
    local removed = {}
    for _, cell in ipairs(self.cells) do removed[cell] = true end
    self:remove_cells(removed)
end

return Rock
