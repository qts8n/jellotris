local shapes = {}

shapes.order = { "I", "O", "T", "S", "Z", "J", "L" }
shapes.definitions = {
    I = { cells = { {0, 0}, {1, 0}, {2, 0}, {3, 0} }, color = {0.26, 0.86, 0.96} },
    O = { cells = { {0, 0}, {1, 0}, {0, 1}, {1, 1} }, color = {1.00, 0.81, 0.32} },
    T = { cells = { {1, 0}, {0, 1}, {1, 1}, {2, 1} }, color = {0.72, 0.52, 1.00} },
    S = { cells = { {1, 0}, {2, 0}, {0, 1}, {1, 1} }, color = {0.55, 0.92, 0.43} },
    Z = { cells = { {0, 0}, {1, 0}, {1, 1}, {2, 1} }, color = {1.00, 0.39, 0.53} },
    J = { cells = { {0, 0}, {0, 1}, {1, 1}, {2, 1} }, color = {0.36, 0.57, 1.00} },
    L = { cells = { {2, 0}, {0, 1}, {1, 1}, {2, 1} }, color = {1.00, 0.59, 0.29} },
}

function shapes.bounds(cells)
    local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
    for _, cell in ipairs(cells) do
        min_x, min_y = math.min(min_x, cell[1]), math.min(min_y, cell[2])
        max_x, max_y = math.max(max_x, cell[1] + 1), math.max(max_y, cell[2] + 1)
    end
    return min_x, min_y, max_x, max_y
end

-- A shuffled seven-bag prevents long droughts of a particular tetromino.
function shapes.new_bag(random)
    local bag = { remaining = {}, random = random or love.math.random }
    function bag:next()
        if #self.remaining == 0 then
            for _, name in ipairs(shapes.order) do
                self.remaining[#self.remaining + 1] = name
            end
            for i = #self.remaining, 2, -1 do
                local j = self.random(i)
                self.remaining[i], self.remaining[j] = self.remaining[j], self.remaining[i]
            end
        end
        return table.remove(self.remaining)
    end
    return bag
end

return shapes
