local Effects = {}
Effects.__index = Effects

function Effects.new()
    return setmetatable({ particles = {}, rings = {}, labels = {}, shake = 0, flash = 0 }, Effects)
end

function Effects:burst(x, y, color, count, power)
    for _ = 1, count do
        local angle = love.math.random() * math.pi * 2
        local speed = (0.3 + love.math.random() * 0.7) * power
        local lifetime = 0.35 + love.math.random() * 0.5
        self.particles[#self.particles + 1] = {
            x = x, y = y, vx = math.cos(angle) * speed, vy = math.sin(angle) * speed - 70,
            radius = 1.5 + love.math.random() * 3.5, life = lifetime, duration = lifetime,
            color = color,
        }
    end
    -- Bound visual debris during large cascades.
    while #self.particles > 650 do table.remove(self.particles, 1) end
end

function Effects:impact(x, y, color, power)
    self:burst(x, y, color, math.floor(5 + power * 12), 65 + power * 130)
    self.rings[#self.rings + 1] = { x = x, y = y, life = 0.5, color = color }
    self.shake = math.max(self.shake, math.min(7, power * 5))
end

function Effects:label(text, x, y, color)
    self.labels[#self.labels + 1] = { text = text, x = x, y = y, life = 1.5, color = color }
end

function Effects:update(dt)
    self.shake = math.max(0, self.shake - dt * 20)
    self.flash = math.max(0, self.flash - dt * 2)
    for i = #self.particles, 1, -1 do
        local p = self.particles[i]
        p.life = p.life - dt
        p.vy = p.vy + 360 * dt
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        if p.life <= 0 then table.remove(self.particles, i) end
    end
    for i = #self.rings, 1, -1 do
        local ring = self.rings[i]
        ring.life = ring.life - dt
        if ring.life <= 0 then table.remove(self.rings, i) end
    end
    for i = #self.labels, 1, -1 do
        local label = self.labels[i]
        label.life, label.y = label.life - dt, label.y - dt * 24
        if label.life <= 0 then table.remove(self.labels, i) end
    end
end

return Effects
