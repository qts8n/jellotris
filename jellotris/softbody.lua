local config = require("jellotris.config")
local shapes = require("jellotris.shapes")
local Face = require("jellotris.face")
local Softbody = {}
Softbody.__index = Softbody
local perimeter = { 1, 2, 3, 6, 9, 8, 7, 4 }

local function key(x, y)
    return x .. ":" .. y
end

local function rotate(x, y, angle)
    local cosine, sine = math.cos(angle), math.sin(angle)
    return x * cosine - y * sine, x * sine + y * cosine
end

function Softbody.new(world, name, x, y, id, options)
    options = options or {}
    local definition = shapes.definitions[name]
    local source_cells = options.cells or definition.cells
    local min_x, min_y, max_x, max_y = shapes.bounds(source_cells)
    local origin_x, origin_y = (min_x + max_x) / 2, (min_y + max_y) / 2
    local angle = options.angle or 0
    local self = setmetatable({
        name = name, material = "jelly", color = definition.color, id = id,
        nodes = {}, cells = {}, links = {}, age = 0,
        active = options.active or false, target_angle = angle,
        slammed = false, contact_time = 0, has_landed = false,
    }, Softbody)

    -- A 3 x 3 lattice per square, with shared points at touching edges.
    -- Circles provide continuous collision; springs provide actual deformation.
    local node_map, occupied = {}, {}
    for _, cell in ipairs(source_cells) do
        for sy = 0, 1 do
            for sx = 0, 1 do
                occupied[key(cell[1] * 2 + sx, cell[2] * 2 + sy)] = true
            end
        end
    end

    local function get_node(gx, gy)
        local node_key = key(gx, gy)
        if node_map[node_key] then return node_map[node_key] end

        -- Inset surface particles, so their collision circles sit inside the skin.
        local left = occupied[key(gx - 1, gy - 1)] or occupied[key(gx - 1, gy)]
        local right = occupied[key(gx, gy - 1)] or occupied[key(gx, gy)]
        local above = occupied[key(gx - 1, gy - 1)] or occupied[key(gx, gy - 1)]
        local below = occupied[key(gx - 1, gy)] or occupied[key(gx, gy)]
        local inset = config.particle_radius
        local inset_x = not left and inset or (not right and -inset or 0)
        local inset_y = not above and inset or (not below and -inset or 0)
        local rest_x = (gx / 2 - origin_x) * config.cell_size + inset_x
        local rest_y = (gy / 2 - origin_y) * config.cell_size + inset_y
        local rx, ry = rotate(rest_x, rest_y, angle)
        local body = love.physics.newBody(world, x + rx, y + ry, "dynamic")
        body:setFixedRotation(true)
        body:setBullet(true)
        body:setLinearDamping(0.65)
        body:setGravityScale(self.active and 0.14 or 1)
        local fixture = love.physics.newFixture(body,
            love.physics.newCircleShape(config.particle_radius), 0.9)
        fixture:setFriction(config.friction)
        fixture:setRestitution(config.restitution)
        fixture:setGroupIndex(-id)
        local node = {
            body = body, fixture = fixture, rest_x = rest_x, rest_y = rest_y,
            skin_x = -inset_x, skin_y = -inset_y, index = #self.nodes + 1,
        }
        fixture:setUserData({ piece = self, node = node })
        node_map[node_key] = node
        self.nodes[#self.nodes + 1] = node
        return node
    end

    local link_map = {}
    local function connect(a, b, cell)
        local lo, hi = math.min(a.index, b.index), math.max(a.index, b.index)
        local link_key = key(lo, hi)
        local link = link_map[link_key]
        if not link then
            local ax, ay = a.body:getPosition()
            local bx, by = b.body:getPosition()
            local joint = love.physics.newDistanceJoint(a.body, b.body, ax, ay, bx, by, false)
            joint:setFrequency(config.spring_frequency)
            joint:setDampingRatio(config.spring_damping)
            link = { joint = joint, a = a, b = b, owners = {} }
            link_map[link_key] = link
            self.links[#self.links + 1] = link
        end
        link.owners[#link.owners + 1] = cell
    end

    for _, source in ipairs(source_cells) do
        local cell = { nodes = {}, alive = true, piece = self }
        for gy = 0, 2 do
            for gx = 0, 2 do
                cell.nodes[#cell.nodes + 1] = get_node(source[1] * 2 + gx, source[2] * 2 + gy)
            end
        end
        for i, a in ipairs(cell.nodes) do
            local ax, ay = (i - 1) % 3, math.floor((i - 1) / 3)
            for j = i + 1, 9 do
                local bx, by = (j - 1) % 3, math.floor((j - 1) / 3)
                local dx, dy = math.abs(ax - bx), math.abs(ay - by)
                -- Short structural/shear springs plus long diagonal braces.
                if math.max(dx, dy) == 1 or (dx == 2 and dy == 2) then
                    connect(a, cell.nodes[j], cell)
                end
            end
        end
        cell.rest_cx, cell.rest_cy, cell.rest_area = 0, 0, 0
        for _, node in ipairs(cell.nodes) do
            cell.rest_cx = cell.rest_cx + node.rest_x / 9
            cell.rest_cy = cell.rest_cy + node.rest_y / 9
            node.cell_count = (node.cell_count or 0) + 1
        end
        for i, index in ipairs(perimeter) do
            local a, b = cell.nodes[index], cell.nodes[perimeter[i % #perimeter + 1]]
            cell.rest_area = cell.rest_area + (a.rest_x * b.rest_y - b.rest_x * a.rest_y) / 2
        end
        self.cells[#self.cells + 1] = cell
    end
    Face.attach(self)
    return self
end

function Softbody:stabilize()
    for _, cell in ipairs(self.cells) do
        if cell.alive and cell.nodes[5].body:isAwake() then
            local cx, cy, vx, vy = 0, 0, 0, 0
            for _, node in ipairs(cell.nodes) do
                local x, y = node.body:getPosition()
                local nvx, nvy = node.body:getLinearVelocity()
                cx, cy, vx, vy = cx + x / 9, cy + y / 9, vx + nvx / 9, vy + nvy / 9
            end

            -- A best-fit rotation is torque-free: settled jelly can lean or roll.
            -- Recovering each cell's rest shape prevents a lattice from folding
            -- inside out, which distance springs alone cannot distinguish.
            local dot, cross = 0, 0
            for _, node in ipairs(cell.nodes) do
                local x, y = node.body:getPosition()
                local rx, ry = node.rest_x - cell.rest_cx, node.rest_y - cell.rest_cy
                dot = dot + rx * (x - cx) + ry * (y - cy)
                cross = cross + rx * (y - cy) - ry * (x - cx)
            end
            local angle = math.atan2(cross, dot)
            for _, node in ipairs(cell.nodes) do
                local body = node.body
                local x, y = body:getPosition()
                local nvx, nvy = body:getLinearVelocity()
                local rx, ry = rotate(node.rest_x - cell.rest_cx, node.rest_y - cell.rest_cy, angle)
                local fx = (cx + rx - x) * config.shape_stiffness - (nvx - vx) * config.shape_damping
                local fy = (cy + ry - y) * config.shape_stiffness - (nvy - vy) * config.shape_damping
                local mass = body:getMass() / node.cell_count
                body:applyForce(fx * mass, fy * mass)
            end

            -- Pressure is the signed-area gradient. Compression pushes outward,
            -- expansion pulls inward, conserving the square's jelly volume.
            local area = 0
            for i, index in ipairs(perimeter) do
                local ax, ay = cell.nodes[index].body:getPosition()
                local bx, by = cell.nodes[perimeter[i % #perimeter + 1]].body:getPosition()
                area = area + (ax * by - bx * ay) / 2
            end
            -- Pressure rises sharply near collapse, like an incompressible gel.
            -- Capping the ratio bounds impulses even after an extreme slam.
            local volume_ratio = math.max(0.20, area / cell.rest_area)
            local strain = math.max(-0.5, 1 / volume_ratio - 1)
            for i, index in ipairs(perimeter) do
                local body = cell.nodes[index].body
                local px, py = cell.nodes[perimeter[(i - 2) % #perimeter + 1]].body:getPosition()
                local nx, ny = cell.nodes[perimeter[i % #perimeter + 1]].body:getPosition()
                local force = config.pressure * strain * body:getMass() / cell.nodes[index].cell_count
                body:applyForce((ny - py) * 0.5 * force, (px - nx) * 0.5 * force)
            end
        end
    end
end

function Softbody:center()
    local x, y, vx, vy, count = 0, 0, 0, 0, 0
    for _, node in ipairs(self.nodes) do
        if not node.body:isDestroyed() then
            local nx, ny = node.body:getPosition()
            local nvx, nvy = node.body:getLinearVelocity()
            x, y, vx, vy = x + nx, y + ny, vx + nvx, vy + nvy
            count = count + 1
        end
    end
    if count == 0 then return 0, 0, 0, 0 end
    return x / count, y / count, vx / count, vy / count
end

function Softbody:angle()
    local cx, cy = self:center()
    local dot, cross = 0, 0
    for _, node in ipairs(self.nodes) do
        if not node.body:isDestroyed() then
            local x, y = node.body:getPosition()
            dot = dot + node.rest_x * (x - cx) + node.rest_y * (y - cy)
            cross = cross + node.rest_x * (y - cy) - node.rest_y * (x - cx)
        end
    end
    return math.atan2(cross, dot)
end

function Softbody:cell_center(cell)
    return cell.nodes[5].body:getPosition()
end

function Softbody:skin_position(node, angle)
    local x, y = node.body:getPosition()
    local sx, sy = rotate(node.skin_x, node.skin_y, angle)
    return x + sx, y + sy
end

function Softbody:cell_vertex(cell, index, angle)
    return self:skin_position(cell.nodes[index], angle)
end

function Softbody:set_active(active)
    self.active = active
    for _, node in ipairs(self.nodes) do
        if not node.body:isDestroyed() then
            node.body:setGravityScale(active and 0.14 or 1)
            node.body:setAwake(true)
        end
    end
end

function Softbody:drive(dt, horizontal, soft_drop, level)
    self.age = self.age + dt
    if not self.active then return end
    local cx, cy, vx, vy = self:center()
    local rest_cx, rest_cy = 0, 0
    for _, node in ipairs(self.nodes) do
        rest_cx, rest_cy = rest_cx + node.rest_x, rest_cy + node.rest_y
    end
    rest_cx, rest_cy = rest_cx / #self.nodes, rest_cy / #self.nodes
    local target_speed = self.slammed and 980 or (soft_drop and 290 or 46 + level * 5)
    local vertical_force = (target_speed - vy) * (self.slammed and 9 or 4)

    for _, node in ipairs(self.nodes) do
        local body = node.body
        local x, y = body:getPosition()
        local nvx, nvy = body:getLinearVelocity()
        local rx, ry = rotate(node.rest_x - rest_cx, node.rest_y - rest_cy, self.target_angle)
        -- Gentle shape matching steers orientation without teleporting the mesh.
        local fx = (cx + rx - x) * 95 - (nvx - vx) * 8
        local fy = (cy + ry - y) * 95 - (nvy - vy) * 8
        fx = fx + (horizontal * 185 - vx) * 11
        fy = fy + vertical_force - config.gravity * 0.14
        body:applyForce(fx * body:getMass(), fy * body:getMass())
    end
end

function Softbody:slam()
    self.slammed = true
    for _, node in ipairs(self.nodes) do
        local vx, vy = node.body:getLinearVelocity()
        node.body:setLinearVelocity(vx * 0.45, math.max(vy, 880))
    end
end

function Softbody:remove_cells(removed)
    local used = {}
    for _, node in ipairs(self.nodes) do node.cell_count = 0 end
    for _, cell in ipairs(self.cells) do
        if removed[cell] then cell.alive = false end
        if cell.alive then
            for _, node in ipairs(cell.nodes) do
                used[node] = true
                node.cell_count = node.cell_count + 1
            end
        elseif cell.mesh then
            cell.mesh:release()
            cell.mesh = nil
        end
    end
    -- Remove orphan springs before bodies; never mutate Box2D inside a callback.
    for _, link in ipairs(self.links) do
        local keep = false
        for _, owner in ipairs(link.owners) do keep = keep or owner.alive end
        if not keep and not link.joint:isDestroyed() then link.joint:destroy() end
    end
    for _, node in ipairs(self.nodes) do
        if not used[node] and not node.body:isDestroyed() then node.body:destroy() end
    end
    Face.attach(self)
    return next(used) ~= nil
end

function Softbody:destroy()
    local removed = {}
    for _, cell in ipairs(self.cells) do removed[cell] = true end
    self:remove_cells(removed)
end

return Softbody
