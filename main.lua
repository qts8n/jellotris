local Game = require("jellotris.game")
local Audio = require("jellotris.audio")
local Renderer = require("jellotris.renderer")

local game, renderer
local test_mode = false
local smoke_mode, smoke_frames = false, 0

function love.load(arguments)
    for _, argument in ipairs(arguments) do
        if argument == "--export-icon" then
            test_mode = true
            local ok, result = xpcall(require("tools.icon"), debug.traceback)
            if not ok then io.stderr:write(result .. "\n") end
            love.event.quit(ok and 0 or 1)
            return
        end
        if argument == "--test" then test_mode = true end
        if argument == "--smoke" then smoke_mode = true end
    end
    love.graphics.setDefaultFilter("linear", "linear")
    love.graphics.setBackgroundColor(0.025, 0.045, 0.06)
    love.keyboard.setKeyRepeat(false)
    renderer = Renderer.new()
    game = Game.new(Audio.new(), { no_save = test_mode or smoke_mode })

    if test_mode then
        local ok, result = xpcall(function()
            require("tests.run")(game, renderer)
        end, debug.traceback)
        if not ok then io.stderr:write(result .. "\n") end
        love.event.quit(ok and 0 or 1)
    end
end

function love.update(dt)
    if test_mode then return end
    local left = love.keyboard.isDown("left", "a")
    local right = love.keyboard.isDown("right", "d")
    game:update(dt, {
        horizontal = (right and 1 or 0) - (left and 1 or 0),
        soft_drop = love.keyboard.isDown("down", "s"),
    })
end

function love.draw()
    if renderer and game then renderer:draw(game) end
    if smoke_mode then
        smoke_frames = smoke_frames + 1
        if smoke_frames >= 3 then
            assert(#renderer.shader_errors == 0, "Packaged shaders failed to compile")
            print("Packaged game rendered successfully.")
            love.event.quit(0)
        end
    end
end

function love.keypressed(key, scancode, is_repeat)
    if not is_repeat then game:keypressed(key) end
end

function love.mousepressed(x, y, button)
    if button == 1 and renderer:button_hit(x, y) then
        game:keypressed(renderer.button.action or (game.state == "paused" and "p" or "return"))
    end
end

function love.focus(focused)
    if not focused and game and game.state == "playing" then game.state = "paused" end
end

function love.quit()
    if game and game.state ~= "ready" then game:update_best() end
end
