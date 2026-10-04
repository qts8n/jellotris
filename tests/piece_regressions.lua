local config = require("jellotris.config")
local Face = require("jellotris.face")

return function(game, renderer, check, advance, empty_board)
    -- Keep pushing after contact: both materials must continue sliding downward.
    for _, material in ipairs({"jelly", "rock"}) do
        for _, direction in ipairs({-1, 1}) do
            game:reset(false)
            empty_board()
            game:spawn({name = "O", material = material})
            local piece = game.active
            local touched_wall = false
            game.world:setCallbacks(function(a, b)
                game:begin_contact(a, b)
                local first, second = a:getUserData(), b:getUserData()
                if first and second and (first.kind == "wall" or second.kind == "wall") then
                    touched_wall = true
                end
            end)
            advance(1.5, {horizontal = direction})
            local _, before_y = piece:center()
            advance(1, {horizontal = direction})
            local _, after_y = piece:center()
            check(touched_wall and piece.active and after_y - before_y > config.cell_size,
                material .. " keeps falling while held against the " .. (direction < 0 and "left" or "right") .. " wall")
        end
    end

    -- Observe the actual draw coordinates, not just a model field: this catches
    -- accidental reintroduction of the renderer's nearest-cell calculation.
    local original_draw = Face.draw
    local expected_piece, expected_cell, face_draws
    Face.draw = function(x, y, ...)
        local expected_x, expected_y = expected_piece:cell_center(expected_cell)
        assert(math.abs(x - expected_x) < 0.001 and math.abs(y - expected_y - 2) < 0.001,
            "rendered face jumped to a different cell")
        face_draws = face_draws + 1
        original_draw(x, y, ...)
    end
    local ok, error_message = xpcall(function()
        for _, material in ipairs({"jelly", "rock"}) do
            game:reset(false)
            empty_board()
            game:spawn({name = "O", material = material})
            local piece = game.active
            local face_cell = piece.face_cell
            check(face_cell and face_cell.alive, material .. " chooses its face cell at spawn")
            expected_piece, expected_cell, face_draws = piece, face_cell, 0
            game:rotate(1)
            for _ = 1, 8 do
                advance(0.2, {horizontal = -1})
                renderer:draw_piece(piece)
                assert(piece.face_cell == face_cell, "face cell changed during motion")
            end
            check(face_draws == 8, material .. " face stays on its chosen cell through rotation and wall compression")

            piece:set_active(false)
            game.active, game.spawn_delay = nil, 100
            local other
            for _, cell in ipairs(piece.cells) do
                if cell ~= face_cell then other = cell; break end
            end
            piece:remove_cells({[other] = true})
            check(piece.face_cell == face_cell, material .. " keeps its face when a different cell clears")
            renderer:draw_piece(piece)
            piece:remove_cells({[face_cell] = true})
            check(piece.face_cell and piece.face_cell ~= face_cell and piece.face_cell.alive,
                material .. " moves the face to a surviving cell only when its host clears")
            expected_cell = piece.face_cell
            advance(0.4)
            renderer:draw_piece(piece)
            piece:destroy()
            check(piece.face_cell == nil, material .. " drops its face reference when completely cleared")
            game.pieces = {}
        end
    end, debug.traceback)
    Face.draw = original_draw
    assert(ok, error_message)
end
