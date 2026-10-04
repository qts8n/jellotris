local config = require("jellotris.config")
local shapes = require("jellotris.shapes")
local Face = require("jellotris.face")
local Title = require("jellotris.title")
local Renderer = {}
Renderer.__index = Renderer

local colors = {
    text = {0.91, 0.96, 0.93}, muted = {0.44, 0.59, 0.59},
    mint = {0.73, 0.96, 0.61}, teal = {0.33, 0.82, 0.72},
    panel = {0.058, 0.105, 0.126}, border = {0.13, 0.23, 0.25},
}

local function color(value, alpha)
    love.graphics.setColor(value[1], value[2], value[3], alpha or 1)
end

local function rounded_panel(x, y, width, height)
    color(colors.panel, 0.98)
    love.graphics.rectangle("fill", x, y, width, height, 14)
    color(colors.border, 0.75)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, width - 1, height - 1, 14)
end

function Renderer.new()
    local self = setmetatable({ fonts = {}, time = 0, shaders = {}, shader_errors = {} }, Renderer)
    for _, size in ipairs({10, 11, 12, 13, 14, 16, 18, 22, 28, 36, 54, 64}) do
        self.fonts[size] = love.graphics.newFont(size)
    end
    self.canvas = love.graphics.newCanvas(config.width, config.height)
    self.canvas:setFilter("linear", "linear")
    for _, name in ipairs({"jelly", "background", "title", "rock"}) do
        local path = "assets/" .. name .. ".glsl"
        local ok, shader = pcall(love.graphics.newShader, path)
        if ok then self.shaders[name] = shader
        else
            self.shader_errors[#self.shader_errors + 1] = tostring(shader)
            print("Shader fallback (" .. name .. "): " .. tostring(shader))
        end
    end
    if self.shaders.background then
        self.shaders.background:send("resolution", {config.width, config.height})
    end
    self.preview_mesh = love.graphics.newMesh({
        {0, 0, 0, 0}, {1, 0, 1, 0}, {1, 1, 1, 1}, {0, 1, 0, 1},
    }, "fan", "static")
    self.title = Title.new(self.fonts[64], self.shaders.title)
    return self
end

function Renderer:text(text, x, y, size, tint, width, align)
    love.graphics.setFont(self.fonts[size or 14])
    color(tint or colors.text)
    if width then love.graphics.printf(text, x, y, width, align or "left")
    else love.graphics.print(text, x, y) end
end

function Renderer:label(text, x, y, tint)
    self:text(text, x, y, 11, tint or colors.muted)
end

function Renderer:preview(specimen, cx, cy, size, opacity)
    if not specimen then return end
    if type(specimen) == "string" then specimen = {name = specimen, material = "jelly"} end
    local name, material = specimen.name, specimen.material
    local definition = shapes.definitions[name]
    local min_x, min_y, max_x, max_y = shapes.bounds(definition.cells)
    local width, height = max_x - min_x, max_y - min_y
    local shader = self.shaders[material or "jelly"]
    love.graphics.setShader(shader)
    if shader then shader:send("seed", 0) end
    color(material == "rock" and config.rock_color or definition.color, opacity or 1)
    for _, cell in ipairs(definition.cells) do
        love.graphics.draw(self.preview_mesh,
            cx + (cell[1] - min_x - width / 2) * size,
            cy + (cell[2] - min_y - height / 2) * size, 0, size, size)
    end
    love.graphics.setShader()
    if material == "rock" then
        local cell = definition.cells[1]
        Face.draw(cx + (cell[1] + 0.5 - min_x - width / 2) * size,
            cy + (cell[2] + 0.5 - min_y - height / 2) * size, 0, "rock", false, false, size / 32)
    end
end

function Renderer:draw_brand(game)
    self.title:draw(43, 80, self.time)

    rounded_panel(64, 294, 258, 188)
    self:label("SCORE", 86, 314)
    self:text(string.format("%06d", math.floor(game.score)), 84, 335, 36, colors.text)
    color(colors.border)
    love.graphics.line(86, 393, 300, 393)
    self:label("LINES", 86, 410)
    self:label("LEVEL", 204, 410)
    self:text(string.format("%02d", game.lines), 86, 430, 28, colors.mint)
    self:text(string.format("%02d", game.level), 204, 430, 28, colors.text)
    rounded_panel(64, 496, 258, 46)
    self:label("BEST", 85, 513)
    self:text(string.format("%06d", math.floor(game.best)), 211, 509, 16, colors.text)
end

function Renderer:draw_sidebar(game)
    local x = 756
    self:label("NEXT", x, 100, colors.text)
    rounded_panel(x, 129, 258, 227)
    for i = 1, 3 do
        local cy = 169 + (i - 1) * 72
        self:text(string.format("0%d", i), x + 21, cy - 8, 12, colors.muted)
        self:preview(game.queue[i], x + 138, cy, i == 1 and 25 or 22, i == 1 and 1 or 0.75)
        if i < 3 then
            color(colors.border, 0.5)
            love.graphics.line(x + 20, cy + 35, x + 238, cy + 35)
        end
    end
    self:label("HOLD", x, 381, colors.text)
    self:text("C / SHIFT", x + 182, 380, 11, colors.muted)
    rounded_panel(x, 410, 258, 90)
    if game.held then self:preview(game.held, x + 129, 455, 25, game.hold_used and 0.35 or 1)
    else self:text("--", x, 444, 18, colors.muted, 258, "center") end
    rounded_panel(x, 520, 258, 54)
    self:text("H  controls", x + 18, 540, 12, colors.text)
    self:text("P  pause", x + 164, 540, 12, colors.muted)
    if game.audio.muted then self:label("MUTED  /  M", x + 160, 593) end
end

function Renderer:draw_board(game)
    local x, y, width, height = config.board_x, config.board_y, config.cell_size * config.columns,
        config.cell_size * config.rows
    for i = 3, 1, -1 do
        color(colors.teal, 0.025)
        love.graphics.rectangle("fill", x - i * 5, y - i * 5, width + i * 10, height + i * 10, 18)
    end
    love.graphics.setColor(0.025, 0.06, 0.078, 0.97)
    love.graphics.rectangle("fill", x, y, width, height, 10)
    color(colors.border)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x - 1, y - 1, width + 2, height + 2, 10)

    love.graphics.setScissor(x, y, width, height)
    for column = 1, config.columns - 1 do
        color(colors.border, 0.20)
        love.graphics.line(x + column * config.cell_size, y, x + column * config.cell_size, y + height)
    end
    for row = 1, config.rows - 1 do
        color(colors.border, row % 5 == 0 and 0.35 or 0.2)
        love.graphics.line(x, y + row * config.cell_size, x + width, y + row * config.cell_size)
    end
    if game.active then
        local cx, cy = game.active:center()
        color(game.active.color, 0.035)
        love.graphics.rectangle("fill", cx - 16, math.max(y, cy), 32, y + height - math.max(y, cy))
        color(game.active.color, 0.3)
        for dot_y = math.max(y + 6, cy + 65), y + height - 5, 15 do
            love.graphics.circle("fill", cx, dot_y, 1)
        end
    end

    love.graphics.push()
    local shake = game.effects.shake
    love.graphics.translate(math.sin(self.time * 89) * shake, math.cos(self.time * 73) * shake * 0.55)
    for _, piece in ipairs(game.pieces) do self:draw_piece(piece) end
    self:draw_particles(game.effects)
    love.graphics.pop()

    if game.effects.flash > 0 then
        color(colors.mint, game.effects.flash * 0.25)
        love.graphics.rectangle("fill", x, y, width, height)
    end
    love.graphics.setScissor()

    -- Side ticks report occupied bands, making the relaxed line rule visible.
    for row, band in ipairs(game.bands) do
        local amount = band.coverage
        color(amount >= config.line_coverage and colors.mint or colors.teal, 0.12 + amount * 0.65)
        love.graphics.rectangle("fill", x + width + 9, y + (row - 1) * 32 + 13, 3 + amount * 9, 3, 1)
    end
    self:draw_labels(game.effects)
end

local vertex_map = { 1, 2, 5, 1, 5, 4, 2, 3, 6, 2, 6, 5, 4, 5, 8, 4, 8, 7, 5, 6, 9, 5, 9, 8 }

function Renderer:draw_piece(piece)
    local angle = piece:angle()
    local shader = self.shaders[piece.material]
    love.graphics.setShader(shader)
    if shader then shader:send("seed", piece.id * 1.7) end
    color(piece.color)
    for _, cell in ipairs(piece.cells) do
        if cell.alive then
            local vertices = cell.vertices or {}
            for i = 1, 9 do
                local px, py = piece:cell_vertex(cell, i, angle)
                local vertex = vertices[i] or {}
                vertex[1], vertex[2] = px, py
                vertex[3], vertex[4] = (i - 1) % 3 / 2, math.floor((i - 1) / 3) / 2
                vertices[i] = vertex
            end
            cell.vertices = vertices
            if not cell.mesh then
                cell.mesh = love.graphics.newMesh(vertices, "triangles", "dynamic")
                cell.mesh:setVertexMap(vertex_map)
            else cell.mesh:setVertices(vertices) end
            love.graphics.draw(cell.mesh)
        end
    end
    love.graphics.setShader()

    local face_cell = piece.face_cell
    if face_cell and face_cell.alive then
        local x, y = piece:cell_center(face_cell)
        local blink = (self.time + piece.id * 0.73) % 4.7 < 0.11
        Face.draw(x, y + 2, angle, piece.material, blink, piece.slammed and piece.active)
    end
end

function Renderer:draw_particles(effects)
    for _, p in ipairs(effects.particles) do
        color(p.color, math.min(1, p.life / p.duration * 2))
        love.graphics.ellipse("fill", p.x, p.y, p.radius, p.radius * (1 + math.abs(p.vy) / 500))
    end
    for _, ring in ipairs(effects.rings) do
        color(ring.color, ring.life * 0.9)
        love.graphics.setLineWidth(1.5)
        love.graphics.ellipse("line", ring.x, ring.y, (1 - ring.life * 2) * 48 + 5,
            (1 - ring.life * 2) * 15 + 2)
    end
end

function Renderer:draw_labels(effects)
    for _, label in ipairs(effects.labels) do
        love.graphics.setFont(self.fonts[18])
        love.graphics.setColor(0.02, 0.055, 0.07, math.min(1, label.life * 2))
        love.graphics.printf(label.text, label.x - 180 + 1, label.y + 1, 360, "center")
        color(label.color, math.min(1, label.life * 2))
        love.graphics.printf(label.text, label.x - 180, label.y, 360, "center")
    end
end

function Renderer:draw_overlay(game)
    if game.show_help then self:draw_help(); return end
    if game.state == "playing" then return end
    local ready = game.state == "ready"
    if not ready then
        love.graphics.setColor(0.02, 0.05, 0.065, 0.75)
        love.graphics.rectangle("fill", config.board_x, config.board_y, 320, 640, 10)
    end
    local top = ready and 218 or 290
    rounded_panel(397, top, 286, ready and 223 or 214)
    self:text(ready and "JELLY + STONE" or (game.state == "paused" and "PAUSED" or "JAR IS FULL"),
        405, top + 24, 11, colors.teal, 270, "center")
    self:text(ready and "Ready to wobble?" or (game.state == "paused" and "Jelly on hold." or "Nice mess."),
        405, top + 52, 22, colors.text, 270, "center")
    self:text(ready and "Jelly bends. Stone stays.\nH for controls."
        or (game.state == "paused" and "Your wobble will be right here."
        or string.format("%d points  /  %d lines", game.score, game.lines)),
        415, top + 94, 13, colors.muted, 250, "center")
    local button_y = top + 155
    color(colors.mint)
    love.graphics.rectangle("fill", 427, button_y, 226, 40, 9)
    self:text(game.state == "paused" and "P / ESC    RESUME" or "ENTER    LET'S JELLY",
        427, button_y + 12, 12, {0.08, 0.16, 0.12}, 226, "center")
    self.button = {x = 427, y = button_y, width = 226, height = 40}
end

function Renderer:draw_help()
    love.graphics.setColor(0.015, 0.03, 0.05, 0.85)
    love.graphics.rectangle("fill", 0, 0, config.width, config.height)
    rounded_panel(326, 158, 428, 500)
    self:text("How to jelly", 354, 183, 28, colors.mint)
    self:text("Fill horizontal bands to clear them.\nJelly falls into gaps. Every fifth piece is stone:\nit stays put until its cells are cleared.",
        354, 235, 14, colors.text, 372)
    local controls = {
        {"A D / LEFT RIGHT", "Slide"}, {"W / UP / X", "Turn right"},
        {"Q / Z", "Turn left"}, {"S / DOWN", "Fall faster"},
        {"SPACE", "Slam"}, {"C / SHIFT", "Hold / swap"},
        {"P / ESC", "Pause"}, {"R / M", "Restart / mute"},
    }
    for i, control in ipairs(controls) do
        local y = 315 + (i - 1) * 30
        self:text(control[1], 354, y, 12, colors.muted)
        self:text(control[2], 569, y, 13, colors.text)
    end
    color(colors.mint)
    love.graphics.rectangle("fill", 354, 590, 372, 40, 8)
    self:text("H / ESC    BACK", 354, 602, 12, {0.08, 0.16, 0.12}, 372, "center")
    self.button = {x = 354, y = 590, width = 372, height = 40, action = "h"}
end

function Renderer:draw(game)
    self.time = self.time + love.timer.getDelta()
    love.graphics.push("all")
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0.035, 0.065, 0.085, 1)
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)
    if self.shaders.background then
        self.shaders.background:send("time", self.time)
        love.graphics.setShader(self.shaders.background)
        love.graphics.rectangle("fill", 0, 0, config.width, config.height)
        love.graphics.setShader()
    end
    if self.shaders.jelly then self.shaders.jelly:send("time", self.time) end
    self:draw_brand(game)
    self:draw_sidebar(game)
    self:draw_board(game)
    self.button = nil
    self:draw_overlay(game)

    love.graphics.setCanvas()
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
    local width, height = love.graphics.getDimensions()
    self.scale = math.min(width / config.width, height / config.height)
    self.offset_x, self.offset_y = (width - config.width * self.scale) / 2, (height - config.height * self.scale) / 2
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.draw(self.canvas, self.offset_x, self.offset_y, 0, self.scale, self.scale)
    love.graphics.pop()
end

function Renderer:button_hit(x, y)
    if not self.button or not self.scale then return false end
    x, y = (x - self.offset_x) / self.scale, (y - self.offset_y) / self.scale
    local button = self.button
    return x >= button.x and x <= button.x + button.width and y >= button.y and y <= button.y + button.height
end

return Renderer
