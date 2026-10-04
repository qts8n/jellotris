local Face = {}

function Face.attach(piece)
    -- Called at spawn and after clears, never during rendering. Keep the same
    -- host through rotation and deformation unless that particular cell is gone.
    if piece.face_cell and piece.face_cell.alive then return end
    piece.face_cell = nil
    local center_x, center_y
    local closest = math.huge
    for _, cell in ipairs(piece.cells) do
        if cell.alive then
            if not center_x then center_x, center_y = piece:center() end
            local x, y = piece:cell_center(cell)
            local distance = (x - center_x)^2 + (y - center_y + 9)^2
            if distance < closest then
                piece.face_cell, closest = cell, distance
            end
        end
    end
end

function Face.draw(x, y, angle, material, blink, slammed, scale)
    love.graphics.push("all")
    love.graphics.translate(x, y)
    love.graphics.rotate(angle or 0)
    love.graphics.scale(scale or 1)
    love.graphics.setColor(0.055, 0.10, 0.10, 0.95)
    love.graphics.setLineWidth(1.6)
    for _, eye_x in ipairs({-5, 5}) do
        love.graphics.ellipse("fill", eye_x, -2, 1.9, blink and 0.6 or 2.4)
    end
    if material == "rock" then
        -- Inward-pointing brows, heavy eyelids, and a permanently downturned mouth.
        love.graphics.line(-8, -7, -3, -4)
        love.graphics.line(3, -4, 8, -7)
        love.graphics.arc("line", "open", 0, 6, 3.5, math.pi + 0.3, math.pi * 2 - 0.3)
    elseif slammed then
        love.graphics.ellipse("fill", 0, 3, 2, 3)
    else
        love.graphics.arc("line", "open", 0, 0.5, 3.5, 0.35, math.pi - 0.35)
    end
    love.graphics.pop()
end

return Face
