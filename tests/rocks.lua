local config = require("jellotris.config")

return function(game, renderer, check, advance, empty_board)
    game:reset(false)
    check(game.active.material == "jelly" and game.queue[4].material == "rock",
        "the fifth dealt piece is visibly stone in the queue")
    for index = 6, 20 do
        local specimen = game:deal()
        assert(specimen.material == (index % config.rock_interval == 0 and "rock" or "jelly"))
    end
    check(true, "stone cadence remains consistent across bags")

    empty_board()
    game:spawn({name = "L", material = "rock"})
    local rock = game.active
    game:keypressed("x")
    advance(0.55, {horizontal = 1})
    local x = rock:center()
    local ax, ay = rock:cell_center(rock.cells[2])
    local bx, by = rock:cell_center(rock.cells[3])
    check(x > config.board_x + 180 and math.abs(rock:angle()) > 0.7,
        "falling stone responds to steering and rotation")
    check(math.abs(math.sqrt((ax - bx)^2 + (ay - by)^2) - config.cell_size) < 0.001,
        "stone holds its rigid tetromino shape")
    game:hold()
    check(game.held.name == "L" and game.held.material == "rock", "hold retains a stone's material")
    -- Release the replacement away from spawn, then swap the stored rock back.
    for _, node in ipairs(game.active.nodes) do
        local nx, ny = node.body:getPosition()
        node.body:setPosition(nx, ny + 180)
    end
    game:release_piece()
    game:spawn()
    game:hold()
    check(game.active.name == "L" and game.active.material == "rock", "held stone comes back as a rigid body")

    game:reset(false)
    empty_board()
    game:spawn({name = "O", material = "rock"})
    rock = game.active
    game:keypressed("space")
    advance(1.6)
    check(rock.locked and rock.body:getType() == "static" and not rock.active,
        "placing stone permanently converts its body to static")
    local frozen_x, frozen_y = rock:center()
    local frozen_angle = rock:angle()
    local jelly = game:add_piece("I", frozen_x, frozen_y - 120)
    jelly:slam()
    advance(2)
    local after_x, after_y = rock:center()
    check(after_x == frozen_x and after_y == frozen_y and rock:angle() == frozen_angle,
        "jelly impacts cannot move placed stone")
    check(rock:remove_cells({[rock.cells[3]] = true, [rock.cells[4]] = true}),
        "a partial clear breaks only the selected stone cells")
    advance(0.5)
    check(#rock.body:getFixtures() == 2 and rock.body:getType() == "static" and select(2, rock:center()) == frozen_y,
        "unsupported stone fragments remain fixed with only their surviving fixtures")
    renderer:draw(game)
    check(true, "stone shaders and partial fragments render")

    game:reset(false)
    empty_board()
    local bottom = config.board_y + config.rows * config.cell_size
    for column = 1, 10 do
        game:add_piece("O", config.board_x + (column - 0.5) * config.cell_size, bottom - 16,
            {cells = {{0, 0}}, material = column % 2 == 0 and "rock" or "jelly"})
    end
    advance(0.38)
    check(game.lines == 1 and #game.pieces == 0 and game.world:getBodyCount() == 1,
        "mixed stone/jelly rows clear without leaving colliders behind")

    game:reset(false)
    local _, before_y = game.active:center()
    game:keypressed("h")
    advance(0.3)
    renderer:draw(game)
    check(game.show_help and game.state == "paused" and select(2, game.active:center()) == before_y,
        "help pauses gameplay while controls are visible")
    game:keypressed("escape")
    check(not game.show_help and game.state == "playing", "closing help restores the previous play state")
    game:keypressed("p")
    game:keypressed("h")
    game:keypressed("h")
    check(game.state == "paused", "help does not accidentally resume an already paused game")
end
