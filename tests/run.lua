-- Integration tests run in LÖVE itself: real Box2D, real GLSL compilation.
-- Usage: love . --test (or xvfb-run -a love . --test on a headless machine).
local config = require("jellotris.config")
local shapes = require("jellotris.shapes")
local Rows = require("jellotris.rows")
local Game = require("jellotris.game")

return function(game, renderer)
    local passed = 0
    local function check(condition, message)
        assert(condition, message)
        passed = passed + 1
        print("PASS " .. message)
    end
    local function advance(seconds, input)
        for _ = 1, math.ceil(seconds * 60) do game:update(1 / 60, input or {}) end
    end
    local function empty_board()
        for _, piece in ipairs(game.pieces) do piece:destroy() end
        game.pieces, game.active = {}, nil
        game.spawn_delay = 100
    end
    local function screenshot(path)
        renderer:draw(game)
        local data = renderer.canvas:newImageData()
        local encoded = data:encode("png")
        local file = assert(io.open(path, "wb"))
        file:write(encoded:getString())
        file:close()
        data:release()
        encoded:release()
    end

    -- Exercise normal startup with real filesystem return values. Use a separate
    -- save identity so these fixtures never overwrite the player's best score.
    local original_identity = love.filesystem.getIdentity()
    love.filesystem.setIdentity(original_identity .. "-persistence-tests")
    local function load_best(options)
        local loaded = Game.new(game.audio, options)
        local best = loaded.best
        for _, piece in ipairs(loaded.pieces) do piece:destroy() end
        loaded.world:destroy()
        return best
    end
    local persistence_ok, persistence_error = xpcall(function()
        love.filesystem.remove("best.txt")
        check(load_best() == 0, "first launch starts without a saved score")
        assert(love.filesystem.write("best.txt", "12345"))
        check(load_best() == 12345, "startup loads the saved score as a decimal number")
        check(load_best({no_save = true}) == 0, "no-save mode ignores the saved score")
        assert(love.filesystem.write("best.txt", ""))
        check(load_best() == 0, "an empty saved score falls back to zero")
        assert(love.filesystem.write("best.txt", "not a score"))
        check(load_best() == 0, "a malformed saved score falls back to zero")
    end, debug.traceback)
    love.filesystem.remove("best.txt")
    love.filesystem.setIdentity(original_identity)
    assert(persistence_ok, persistence_error)

    love.math.setRandomSeed(74621)
    game:reset(true)
    game.audio.muted = true
    check(#renderer.shader_errors == 0, "all four GLSL shaders compile")
    local bag = shapes.new_bag()
    for _ = 1, 10 do
        local seen = {}
        for _ = 1, 7 do seen[bag:next()] = true end
        local count = 0
        for _ in pairs(seen) do count = count + 1 end
        assert(count == 7, "seven-bag repeated a piece")
    end
    check(true, "every seven-bag contains all seven tetrominoes")

    advance(3)
    screenshot("/tmp/jellotris-ready.png")
    check(game.state == "ready", "title screen simulates a live jelly pile")
    game:keypressed("return")
    check(game.state == "playing" and #game.active.cells == 4, "Enter starts a standard tetromino")
    local first = game.active.name
    game:keypressed("c")
    check(game.held.name == first and game.hold_used, "hold stores the active piece")
    local held_active = game.active
    game:keypressed("c")
    check(game.active == held_active, "hold cannot be repeated before placement")
    local _, initial_y = game.active:center()
    game:keypressed("p")
    advance(0.5)
    local _, paused_y = game.active:center()
    check(game.state == "paused" and paused_y == initial_y, "pause freezes the physics world")
    game:keypressed("escape")
    game:keypressed("x")
    advance(0.55, {horizontal = 1})
    local moved_x = game.active:center()
    check(moved_x > config.board_x + 180, "horizontal input applies physical steering")
    check(math.abs(game.active:angle()) > 0.7, "rotation turns the physical spring lattice")

    local dropped = game.active
    game:keypressed("space")
    advance(1.6)
    check(not dropped.active and game.score >= 20, "slam collides, releases, and awards points")
    check(game.active ~= nil and not game.hold_used, "a new piece spawns and restores hold")
    local before_swap = game.active.name
    game:hold()
    check(game.active.name == first and game.held.name == before_swap, "reserve swaps with the active piece")

    require("tests.rocks")(game, renderer, check, advance, empty_board)
    require("tests.piece_regressions")(game, renderer, check, advance, empty_board)

    -- A real, level row must clear and destroy orphan bodies/joints.
    game:reset(false)
    empty_board()
    local bottom = config.board_y + config.rows * config.cell_size
    for column = 1, 10 do
        game:add_piece("O", config.board_x + (column - 0.5) * config.cell_size, bottom - 16,
            {cells = {{0, 0}}})
    end
    advance(0.38)
    check(game.lines == 1 and game.score == 100, "physical full row clears and scores")
    check(#game.pieces == 0 and game.world:getBodyCount() == 1 and game.world:getJointCount() == 0,
        "line clear leaves no orphan physics bodies or joints")

    -- Overlap must not count as coverage, and falling active cells cannot clear.
    empty_board()
    for _ = 1, 12 do
        game:add_piece("O", config.board_x + 40, bottom - 16, {cells = {{0, 0}}})
    end
    check(not Rows.scan(game.pieces)[20].full, "overlapping tiles cannot fake a full row")
    empty_board()
    local fragment = game:add_piece("I", config.board_x + 160, bottom - 18)
    fragment:set_active(true)
    check(Rows.scan(game.pieces)[20].coverage == 0, "the controlled piece cannot prematurely fill a row")
    fragment:set_active(false)
    local removed = {[fragment.cells[2]] = true, [fragment.cells[3]] = true}
    check(fragment:remove_cells(removed), "partially cleared pieces retain their remaining cells")
    advance(0.5)
    check(not fragment.cells[2].alive and fragment.cells[1].alive, "severed spring fragments keep simulating")
    renderer:draw(game)
    check(true, "partially cleared meshes render without destroyed-body access")

    -- Multi-line scoring and cascading use the same detector as normal play.
    game:reset(false)
    empty_board()
    for row = 18, 20 do
        for column = 1, 10 do
            game:add_piece("O", config.board_x + (column - 0.5) * 32,
                config.board_y + (row - 0.5) * 32, {cells = {{0, 0}}})
        end
    end
    advance(0.38)
    check(game.lines == 3 and game.score == 500, "simultaneous triple clear uses the correct reward")
    for column = 1, 10 do
        game:add_piece("O", config.board_x + (column - 0.5) * 32, bottom - 16, {cells = {{0, 0}}})
    end
    advance(0.75)
    check(game.lines == 4 and game.score == 700 and game.combo == 2, "quick cascades multiply the next clear")
    for row = 17, 20 do
        for column = 1, 10 do
            game:add_piece("O", config.board_x + (column - 0.5) * 32,
                config.board_y + (row - 0.5) * 32, {cells = {{0, 0}}})
        end
    end
    advance(0.75)
    check(game.lines == 8 and game.level == 2 and game.score == 3100,
        "a four-line cascade scores correctly and advances the level")

    -- Stress every shape together, including violent impacts and wall contacts.
    game:reset(false)
    empty_board()
    game.state = "ready"
    for i = 1, 28 do
        local piece = game:add_piece(shapes.order[(i - 1) % 7 + 1],
            config.board_x + 65 + ((i * 67) % 190), config.board_y + 70,
            {angle = (i % 5 - 2) * 0.22})
        if i % 3 == 0 then piece:slam() end
        advance(0.3)
    end
    advance(3)
    local largest_stretch, node_count, smallest_area = 0, 0, math.huge
    local perimeter = {1, 2, 3, 6, 9, 8, 7, 4}
    for _, piece in ipairs(game.pieces) do
        for _, node in ipairs(piece.nodes) do
            local x, y = node.body:getPosition()
            assert(x == x and y == y, "physics produced NaN")
            assert(x > config.board_x - 10 and x < config.board_x + 330, "particle escaped side wall")
            assert(y < bottom + 12, "particle tunneled through floor")
            node_count = node_count + 1
        end
        for _, link in ipairs(piece.links) do
            local ax, ay = link.a.body:getPosition()
            local bx, by = link.b.body:getPosition()
            local distance = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
            largest_stretch = math.max(largest_stretch, math.abs(distance - link.joint:getLength()))
        end
        for _, cell in ipairs(piece.cells) do
            local area = 0
            for i, index in ipairs(perimeter) do
                local ax, ay = cell.nodes[index].body:getPosition()
                local bx, by = cell.nodes[perimeter[i % #perimeter + 1]].body:getPosition()
                area = area + (ax * by - bx * ay) / 2
            end
            smallest_area = math.min(smallest_area, area / cell.rest_area)
        end
    end
    check(node_count > 600, "stress pile simulates more than 600 spring particles")
    check(largest_stretch > 0.1 and largest_stretch < 45, "pile deforms while springs remain bounded")
    print(string.format("  Stress: %d particles, %.1f px maximum spring deformation, %.0f%% minimum cell volume",
        node_count, largest_stretch, smallest_area * 100))
    check(smallest_area > 0.3, "volume recovery prevents collapsed or inverted cells in a heavy pile")
    game.state = "playing"
    game.score, game.lines, game.level = 2450, 12, 2
    game.held = "T"
    screenshot("/tmp/jellotris-playing.png")
    check(true, "gameplay canvas renders a full physics pile")

    game:reset(false)
    empty_board()
    game:add_piece("O", config.board_x + 160, config.board_y, {cells = {{0, 0}}})
    for _, node in ipairs(game.pieces[1].nodes) do node.body:setType("static") end
    advance(1.6)
    check(game.state == "gameover", "persistent overflow ends the run")
    game:keypressed("r")
    check(game.state == "playing" and game.score == 0 and #game.pieces == 1, "restart resets the world and score")
    empty_board()
    game:add_piece("O", config.board_x + 160, config.board_y + 26)
    game:spawn("T")
    check(game.state == "gameover" and game.active == nil,
        "a blocked spawn ends the run before creating overlapping soft bodies")
    renderer:draw(game)
    game:reset(true)
    local width, height = love.graphics.getDimensions()
    assert(love.window.setMode(720, 560, {resizable = true, vsync = 0}))
    renderer:draw(game)
    local button = renderer.button
    check(renderer:button_hit(renderer.offset_x + (button.x + button.width / 2) * renderer.scale,
        renderer.offset_y + (button.y + button.height / 2) * renderer.scale),
        "resized canvas keeps the start button's hit area aligned")
    check(not renderer:button_hit(0, 0), "letterbox margins do not activate buttons")
    assert(love.window.setMode(width, height, {resizable = true, vsync = 0}))
    print(string.format("\n%d integration checks passed. Screenshots: /tmp/jellotris-{ready,playing}.png", passed))
end
