local Title = {}
Title.__index = Title

function Title.new(font, shader)
    local self = setmetatable({shader = shader}, Title)
    self.mask = love.graphics.newCanvas(300, 195)
    love.graphics.push("all")
    love.graphics.setCanvas(self.mask)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    -- Thicken the built-in font into a playful, slightly uneven logo mask.
    for i = 0, 11 do
        local angle = i * math.pi / 6
        local dx, dy = math.cos(angle) * 1.7, math.sin(angle) * 1.7
        love.graphics.print("JELLO", 20 + dx, 13 + dy, -0.035, 1.15, 1.15)
        love.graphics.print("TRIS", 44 + dx, 88 + dy, 0.025, 1.25, 1.15)
    end
    love.graphics.pop()
    if shader then shader:send("texel_size", {1 / 300, 1 / 195}) end
    return self
end

function Title:draw(x, y, time)
    love.graphics.push("all")
    -- Small rising droplets surround the logo without drifting over the stats.
    for i = 1, 20 do
        local progress = (time * 0.12 + i * 0.137) % 1
        local px = x + 18 + (i * 71) % 264 + math.sin(time + i) * 6
        local py = y + 192 - progress * 205
        local opacity = math.sin(progress * math.pi) * 0.42
        love.graphics.setColor(0.52, 0.95, 0.72, opacity)
        love.graphics.circle(i % 3 == 0 and "line" or "fill", px, py, 1.2 + i % 3)
    end
    local bob = math.sin(time * 1.3) * 2
    love.graphics.setColor(0.015, 0.06, 0.07, 0.9)
    for depth = 8, 2, -2 do love.graphics.draw(self.mask, x + depth * 0.4, y + depth + bob) end
    love.graphics.setColor(1, 1, 1)
    if self.shader then self.shader:send("time", time) end
    love.graphics.setShader(self.shader)
    love.graphics.draw(self.mask, x, y + bob)
    love.graphics.pop()
end

return Title
