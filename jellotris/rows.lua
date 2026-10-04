local config = require("jellotris.config")
local rows = {}

-- With sliding/rotating bodies there is no authoritative integer board.
-- Bin tile centers into horizontal bands, then measure their combined footprint.
-- Small seams are forgiven; overlapping tiles cannot count the same space twice.
function rows.scan(pieces)
    local bands = {}
    for row = 1, config.rows do bands[row] = { cells = {}, intervals = {}, coverage = 0 } end
    local left, width = config.board_x, config.columns * config.cell_size
    for _, piece in ipairs(pieces) do
        if not piece.active then
            for _, cell in ipairs(piece.cells) do
                if cell.alive then
                    local x, y = piece:cell_center(cell)
                    local row = math.floor((y - config.board_y) / config.cell_size) + 1
                    if bands[row] then
                        local band = bands[row]
                        band.cells[#band.cells + 1] = cell
                        local half_width = config.cell_size * 0.53
                        band.intervals[#band.intervals + 1] = {
                            math.max(0, x - half_width - left),
                            math.min(width, x + half_width - left),
                        }
                    end
                end
            end
        end
    end
    for _, band in ipairs(bands) do
        table.sort(band.intervals, function(a, b) return a[1] < b[1] end)
        local covered, finish = 0, 0
        for _, interval in ipairs(band.intervals) do
            local start = math.max(finish, interval[1])
            covered = covered + math.max(0, interval[2] - start)
            finish = math.max(finish, interval[2])
        end
        band.coverage = covered / width
        band.full = band.coverage >= config.line_coverage and #band.cells >= 9
    end
    return bands
end

return rows
