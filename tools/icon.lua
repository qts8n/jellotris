-- Render the application icon from the same materials and faces as the game.
-- Called by tools/build.py; PNGs are then wrapped as native ICO / ICNS files.
local Face = require("jellotris.face")
local config = require("jellotris.config")

return function()
    local graphics = love.graphics
    local canvas = graphics.newCanvas(1024, 1024)
    local jelly = graphics.newShader("assets/jelly.glsl")
    local rock = graphics.newShader("assets/rock.glsl")
    local background = graphics.newShader("assets/background.glsl")
    local quad = graphics.newMesh({{0, 0, 0, 0}, {1, 0, 1, 0}, {1, 1, 1, 1}, {0, 1, 0, 1}}, "fan")
    jelly:send("time", 0)
    jelly:send("seed", 4)
    rock:send("seed", 8)
    background:send("time", 4)
    background:send("resolution", {1024, 1024})

    graphics.push("all")
    graphics.setCanvas(canvas)
    graphics.clear(0, 0, 0, 0)
    graphics.setColor(1, 1, 1)
    graphics.setShader(background)
    graphics.rectangle("fill", 20, 20, 984, 984, 190)
    graphics.setShader()
    graphics.setColor(0.025, 0.06, 0.08, 0.3)
    graphics.rectangle("fill", 20, 20, 984, 984, 190)

    graphics.push()
    graphics.translate(502, 475)
    graphics.rotate(-0.12)
    for _, cell in ipairs({{0, 0}, {1, 0}, {2, 0}, {1, 1}}) do
        local x, y = -330 + cell[1] * 220, -220 + cell[2] * 220
        graphics.setShader()
        graphics.setColor(0.01, 0.025, 0.04, 0.5)
        graphics.rectangle("fill", x + 10, y + 22, 220, 220, 30)
        graphics.setShader(jelly)
        graphics.setColor(0.52, 0.95, 0.64)
        graphics.draw(quad, x, y, 0, 220, 220)
    end
    graphics.setShader()
    Face.draw(0, -100, 0, "jelly", false, false, 7)
    graphics.pop()

    graphics.push()
    graphics.translate(731, 747)
    graphics.rotate(0.12)
    graphics.setColor(0.01, 0.02, 0.03, 0.6)
    graphics.rectangle("fill", -111, -95, 242, 242, 24)
    graphics.setShader(rock)
    graphics.setColor(config.rock_color)
    graphics.draw(quad, -121, -121, 0, 242, 242)
    graphics.setShader()
    Face.draw(0, 5, 0, "rock", false, false, 7)
    graphics.pop()

    -- A few little bubbles remain readable without adding text to the icon.
    graphics.setColor(0.58, 1, 0.77, 0.65)
    graphics.circle("fill", 204, 688, 15)
    graphics.circle("fill", 177, 755, 8)
    graphics.circle("line", 304, 166, 12)
    graphics.setCanvas()
    graphics.pop()

    for _, size in ipairs({16, 24, 32, 48, 64, 128, 256, 512, 1024}) do
        local resized = graphics.newCanvas(size, size)
        graphics.push("all")
        graphics.setCanvas(resized)
        graphics.clear(0, 0, 0, 0)
        graphics.setColor(1, 1, 1)
        graphics.setBlendMode("alpha", "premultiplied")
        graphics.draw(canvas, 0, 0, 0, size / 1024, size / 1024)
        graphics.pop()
        local pixels = resized:newImageData()
        -- Canvas pixels are premultiplied; PNG stores straight alpha.
        pixels:mapPixel(function(_, _, r, g, b, a)
            if a > 0 then return r / a, g / a, b / a, a end
            return 0, 0, 0, 0
        end)
        local encoded = pixels:encode("png")
        local path = love.filesystem.getSource() .. "/build/icons/icon-" .. size .. ".png"
        local file = assert(io.open(path, "wb"))
        file:write(encoded:getString())
        file:close()
        encoded:release()
        pixels:release()
        resized:release()
    end
    print("Rendered application icons at 16–1024 px.")
end
