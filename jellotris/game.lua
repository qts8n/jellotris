local config = require("jellotris.config")
local shapes = require("jellotris.shapes")
local Softbody = require("jellotris.softbody")
local Rock = require("jellotris.rock")
local Rows = require("jellotris.rows")
local Effects = require("jellotris.effects")
local Game = {}
Game.__index = Game

function Game.new(audio, options)
    local self = setmetatable({ audio = audio, options = options or {}, best = 0 }, Game)
    if not self.options.no_save then
        -- Capture only the contents; read also returns a byte count or an error.
        local saved_score = love.filesystem.read("best.txt")
        self.best = tonumber(saved_score) or 0
    end
    self:reset(true)
    return self
end

function Game:reset(menu)
    if self.world then
        for _, piece in ipairs(self.pieces) do piece:destroy() end
        self.world:destroy()
    end
    love.physics.setMeter(64)
    self.world = love.physics.newWorld(0, config.gravity, true)
    self.pieces, self.pending_impacts, self.row_timers = {}, {}, {}
    self.effects, self.bag, self.queue = Effects.new(), shapes.new_bag(), {}
    self.state = menu and "ready" or "playing"
    self.show_help = false
    self.help_previous_state = nil
    self.active, self.held, self.hold_used = nil, nil, false
    self.score, self.lines, self.level, self.combo = 0, 0, 1, 0
    self.clock, self.accumulator, self.spawn_delay, self.overflow_time = 0, 0, 0.2, 0
    self.next_id, self.clear_cooldown, self.combo_time = 1, 0, 0
    self.dealt = 0
    self.row_scan_time, self.bands = 0, Rows.scan({})
    self.last_message = ""
    for _ = 1, 4 do self.queue[#self.queue + 1] = self:deal() end

    local x, y = config.board_x, config.board_y
    local width, height = config.columns * config.cell_size, config.rows * config.cell_size
    self.walls = love.physics.newBody(self.world, 0, 0, "static")
    local boundaries = {
        { x - 15, y + height / 2 - 120, 30, height + 300, "wall" },
        { x + width + 15, y + height / 2 - 120, 30, height + 300, "wall" },
        { x + width / 2, y + height + 15, width + 60, 30, "floor" },
    }
    for _, boundary in ipairs(boundaries) do
        local fixture = love.physics.newFixture(self.walls,
            love.physics.newRectangleShape(boundary[1], boundary[2], boundary[3], boundary[4]))
        -- A held direction must not let contact friction pin a piece to a wall.
        fixture:setFriction(boundary[5] == "wall" and 0 or config.friction)
        fixture:setRestitution(0.16)
        fixture:setUserData({ kind = boundary[5] })
    end
    self.world:setCallbacks(function(a, b) self:begin_contact(a, b) end)
    if menu then
        -- Live soft bodies in the title screen double as a little physics aquarium.
        local specimens = {
            { "J", 65, 545, -0.12 }, { "O", 142, 608, 0, "rock" },
            { "L", 250, 525, 0.18 }, { "S", 94, 452, -0.22 },
            { "T", 211, 427, 0.15 }, { "I", 167, 353, -0.12 },
        }
        for _, specimen in ipairs(specimens) do
            self:add_piece(specimen[1], x + specimen[2], y + specimen[3],
                {angle = specimen[4], material = specimen[5]})
        end
    else
        self:spawn()
        self.audio:play("start")
    end
end

function Game:deal()
    self.dealt = self.dealt + 1
    return {name = self.bag:next(), material = self.dealt % config.rock_interval == 0 and "rock" or "jelly"}
end

function Game:add_piece(name, x, y, options)
    options = options or {}
    local kind = options.material == "rock" and Rock or Softbody
    local piece = kind.new(self.world, name, x, y, self.next_id, options)
    self.next_id = self.next_id + 1
    -- The board can hold only a small number of live groups. Reuse an unused ID
    -- before Box2D's signed 16-bit collision-group limit, even in a marathon.
    if self.next_id > 32000 then self.next_id = 1 end
    local used = {}
    for _, other in ipairs(self.pieces) do used[other.id] = true end
    used[piece.id] = true
    while used[self.next_id] do self.next_id = self.next_id % 32000 + 1 end
    self.pieces[#self.pieces + 1] = piece
    return piece
end

function Game:spawn(specimen)
    if self.state ~= "playing" then return end
    if not specimen then
        specimen = table.remove(self.queue, 1)
        self.queue[#self.queue + 1] = self:deal()
    end
    if type(specimen) == "string" then specimen = {name = specimen, material = "jelly"} end
    local name = specimen.name
    local x, y = config.board_x + config.columns * config.cell_size / 2, config.board_y + 26
    if self:spawn_blocked(name, x, y) then self:finish(); return end
    self.active = self:add_piece(name, x, y, {active = true, material = specimen.material})
    self.spawn_delay = 0
end

function Game:spawn_blocked(name, x, y)
    local cells = shapes.definitions[name].cells
    local min_x, min_y, max_x, max_y = shapes.bounds(cells)
    local middle_x, middle_y = (min_x + max_x) / 2, (min_y + max_y) / 2
    local clearance = config.cell_size * 0.85
    for _, source in ipairs(cells) do
        local target_x = x + (source[1] + 0.5 - middle_x) * config.cell_size
        local target_y = y + (source[2] + 0.5 - middle_y) * config.cell_size
        for _, piece in ipairs(self.pieces) do
            if not piece.active then
                for _, cell in ipairs(piece.cells) do
                    if cell.alive then
                        local cx, cy = piece:cell_center(cell)
                        if math.abs(cx - target_x) < clearance and math.abs(cy - target_y) < clearance then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function Game:begin_contact(a, b)
    local first, second = a:getUserData(), b:getUserData()
    if not first or not second then return end
    for _, pair in ipairs({ {first, second}, {second, first} }) do
        local data, other = pair[1], pair[2]
        local piece = data.piece
        local supported = other.kind == "floor" or (other.piece and not other.piece.active)
        if piece and piece.active and supported then
            local x, y
            if data.node then x, y = data.node.body:getPosition()
            else x, y = piece:cell_center(data.cell) end
            local _, cy, _, vy = piece:center()
            if y >= cy - 6 then
                if not piece.has_landed then
                    piece.has_landed = true
                    self.pending_impacts[#self.pending_impacts + 1] = {
                        x = x, y = y, color = piece.color, power = math.min(1.5, math.abs(vy) / 550),
                        material = piece.material,
                    }
                end
            end
        end
    end
end

function Game:release_piece()
    if not self.active then return end
    local piece = self.active
    piece:set_active(false)
    if piece.material == "rock" then
        local x, y = piece:center()
        self.effects:impact(x, y, piece.color, 0.8)
        self.audio:play("stone")
    end
    self.score = self.score + (piece.slammed and 20 or 10)
    self.active, self.hold_used, self.spawn_delay = nil, false, 0.40
end

function Game:hold()
    if not self.active or self.hold_used or self.active.slammed then return end
    local outgoing = {name = self.active.name, material = self.active.material}
    local incoming = self.held
    self.active:destroy()
    for i, piece in ipairs(self.pieces) do
        if piece == self.active then table.remove(self.pieces, i); break end
    end
    self.active = nil
    self.held = outgoing
    self:spawn(incoming)
    self.hold_used = true
    self.audio:play("hold")
end

function Game:rotate(direction)
    if not self.active or self.active.slammed then return end
    self.active.target_angle = self.active.target_angle + direction * math.pi / 2
    self.audio:play("rotate", direction > 0 and 1 or 0.85)
end

function Game:clear_rows(bands)
    local removed, count, center_y = {}, 0, 0
    for index, band in ipairs(bands) do
        if band.full and (self.row_timers[index] or 0) >= config.line_settle_time then
            count, center_y = count + 1, center_y + config.board_y + (index - 0.5) * config.cell_size
            for _, cell in ipairs(band.cells) do
                removed[cell] = true
                local x, y = cell.piece:cell_center(cell)
                self.effects:burst(x, y, cell.piece.color, 14, 170)
            end
        end
    end
    if count == 0 then return end
    for i = #self.pieces, 1, -1 do
        if not self.pieces[i]:remove_cells(removed) then table.remove(self.pieces, i) end
    end
    self.combo = self.combo_time > 0 and self.combo + 1 or 1
    self.combo_time = 3
    local rewards = {100, 300, 500, 800}
    local points = (rewards[math.min(count, 4)] + math.max(0, count - 4) * 300)
        * self.level * self.combo
    self.score, self.lines = self.score + points, self.lines + count
    self.level = 1 + math.floor(self.lines / 8)
    self.row_timers, self.clear_cooldown = {}, 0.45
    self.effects.shake, self.effects.flash = 9, 0.32
    local names = { "SQUISH!", "DOUBLE GOO!", "TRIPLE GOO!", "JELLOTRIS!" }
    self.last_message = names[math.min(count, 4)]
    self.effects:label(self.last_message .. "  +" .. points,
        config.board_x + 160, center_y / count, {0.73, 1.0, 0.76})
    self.audio:play("clear", 1 + math.min(5, self.combo - 1) * 0.12)
    self:update_best()
end

function Game:update_best()
    if self.score > self.best then
        self.best = self.score
        if not self.options.no_save then love.filesystem.write("best.txt", tostring(self.best)) end
    end
end

function Game:finish()
    if self.active then self.active:set_active(false); self.active = nil end
    self.state = "gameover"
    self.last_message = "That was a beautiful mess."
    self:update_best()
    self.audio:play("over")
end

function Game:step(dt, input)
    self.clock = self.clock + dt
    for _, piece in ipairs(self.pieces) do piece:stabilize() end
    if self.active then self.active:drive(dt, input.horizontal or 0, input.soft_drop, self.level) end
    self.world:update(dt, 8, 4)
    for _, impact in ipairs(self.pending_impacts) do
        self.effects:impact(impact.x, impact.y, impact.color, impact.power)
        self.audio:play(impact.material == "rock" and "stone" or "land", 0.9 + love.math.random() * 0.2)
    end
    self.pending_impacts = {}
    if self.state ~= "playing" then return end

    self.combo_time = math.max(0, self.combo_time - dt)
    self.clear_cooldown = math.max(0, self.clear_cooldown - dt)
    if self.active and self.active.has_landed then
        self.active.contact_time = self.active.contact_time + dt
        if self.active.contact_time >= (self.active.slammed and 0.10 or 0.65) then self:release_piece() end
    end

    self.row_scan_time = self.row_scan_time + dt
    if self.row_scan_time >= 0.05 then
        self.bands = Rows.scan(self.pieces)
        if self.clear_cooldown == 0 then
            for row, band in ipairs(self.bands) do
                self.row_timers[row] = band.full and (self.row_timers[row] or 0) + self.row_scan_time or 0
            end
            self:clear_rows(self.bands)
        end
        self.row_scan_time = 0
    end

    -- Top-out depends on the settled pile, so a normal spawn above the lip is safe.
    local overflow = false
    for _, piece in ipairs(self.pieces) do
        if not piece.active then
            for _, cell in ipairs(piece.cells) do
                if cell.alive then
                    local _, y = piece:cell_center(cell)
                    if y < config.board_y + 8 then overflow = true end
                end
            end
        end
    end
    self.overflow_time = overflow and self.overflow_time + dt or 0
    if self.overflow_time > 1.4 then self:finish(); return end
    if not self.active then
        self.spawn_delay = self.spawn_delay - dt
        if self.spawn_delay <= 0 and not overflow then self:spawn() end
    end
end

function Game:update(dt, input)
    if self.state == "paused" then return end
    self.effects:update(dt)
    self.accumulator = self.accumulator + math.min(dt, 0.10)
    while self.accumulator >= config.fixed_dt do
        self:step(config.fixed_dt, input or {})
        self.accumulator = self.accumulator - config.fixed_dt
    end
end

function Game:keypressed(key)
    if key == "m" then self.audio:toggle(); return end
    if key == "h" or key == "f1" or (key == "escape" and self.show_help) then
        self.show_help = not self.show_help
        if self.show_help then
            self.help_previous_state = self.state
            if self.state == "playing" then self.state = "paused" end
        elseif self.help_previous_state then
            self.state = self.help_previous_state
            self.help_previous_state = nil
        end
        return
    end
    if self.show_help then return end
    if key == "return" or key == "kpenter" then
        if self.state == "ready" or self.state == "gameover" then self:reset(false); return end
    end
    if key == "p" or key == "escape" then
        if self.state == "playing" then self.state = "paused"
        elseif self.state == "paused" then self.state = "playing" end
        return
    end
    if key == "r" then self:reset(false); return end
    if self.state ~= "playing" then return end
    if key == "up" or key == "x" or key == "w" then self:rotate(1)
    elseif key == "z" or key == "q" then self:rotate(-1)
    elseif key == "c" or key == "lshift" or key == "rshift" then self:hold()
    elseif key == "space" and self.active and not self.active.slammed then
        self.active:slam()
        self.audio:play("drop")
    end
end

return Game
