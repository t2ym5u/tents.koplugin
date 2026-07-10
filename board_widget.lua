local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local gwb      = require("grid_widget_base")
local drawLine = gwb.drawLine

local TentsBoard = require("board")

local C_BG    = Blitbuffer.COLOR_WHITE
local C_FG    = Blitbuffer.COLOR_BLACK
local C_GRID  = Blitbuffer.COLOR_GRAY_9
local C_TREE  = Blitbuffer.COLOR_GRAY_3
local C_TENT  = Blitbuffer.COLOR_GRAY_7
local C_GRASS = Blitbuffer.COLOR_GRAY_D
local C_WRONG = Blitbuffer.COLOR_GRAY_2
local C_CLUE  = Blitbuffer.COLOR_BLACK

-- ---------------------------------------------------------------------------
-- TentsBoardWidget
-- ---------------------------------------------------------------------------

local TentsBoardWidget = InputContainer:extend{
    board      = nil,
    max_width  = 0,
    max_height = 0,
    cellTapCallback  = nil,
    cellHoldCallback = nil,
}

function TentsBoardWidget:init()
    local board = self.board
    local n     = board.n

    -- Reserve space for clue numbers along edges
    -- cell_size is based on available space minus clue column/row
    local avail_w = self.max_width
    local avail_h = self.max_height
    -- clue area = 1 extra row/col of cells
    local cell = math.floor(math.min(avail_w / (n + 1), avail_h / (n + 1)))
    cell = math.max(cell, 10)
    self.cell  = cell
    self.clue_w = cell
    self.w     = cell * (n + 1)
    self.h     = cell * (n + 1)
    self.dimen = Geom:new{ w = self.w, h = self.h }

    local num_size = math.max(7, math.floor(cell * 0.5))
    self.num_face  = Font:getFace("cfont", num_size)
    local sym_size = math.max(6, math.floor(cell * 0.45))
    self.sym_face  = Font:getFace("cfont", sym_size)

    self.paint_rect = nil

    self.ges_events = {
        CellTap  = { GestureRange:new{ ges = "tap",          range = self.dimen } },
        CellHold = { GestureRange:new{ ges = "hold_release", range = self.dimen } },
    }
end

local function centeredText(bb, text, face, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, cx * 2, face, text, true, false)
    local tx = cx - math.floor(m.x / 2)
    local ty = cy - math.floor((m.y_bottom - m.y_top) / 2)
    RenderText:renderUtf8Text(bb, tx, ty, face, text, true, false, color or Blitbuffer.COLOR_BLACK)
end

function TentsBoardWidget:_cellOrigin(r, c)
    -- Grid cells start at (clue_w, clue_w) offset
    local x = self.paint_rect.x + self.clue_w + (c - 1) * self.cell
    local y = self.paint_rect.y + self.clue_w + (r - 1) * self.cell
    return x, y
end

function TentsBoardWidget:onCellTap(ges)
    if not self.paint_rect then return end
    local lx = ges.pos.x - self.paint_rect.x - self.clue_w
    local ly = ges.pos.y - self.paint_rect.y - self.clue_w
    if lx < 0 or ly < 0 then return end
    local c = math.floor(lx / self.cell) + 1
    local r = math.floor(ly / self.cell) + 1
    local n = self.board.n
    if r >= 1 and r <= n and c >= 1 and c <= n then
        if self.cellTapCallback then self.cellTapCallback(r, c) end
    end
    return true
end

function TentsBoardWidget:onCellHold(ges)
    if not self.paint_rect then return end
    local lx = ges.pos.x - self.paint_rect.x - self.clue_w
    local ly = ges.pos.y - self.paint_rect.y - self.clue_w
    if lx < 0 or ly < 0 then return end
    local c = math.floor(lx / self.cell) + 1
    local r = math.floor(ly / self.cell) + 1
    local n = self.board.n
    if r >= 1 and r <= n and c >= 1 and c <= n then
        if self.cellHoldCallback then self.cellHoldCallback(r, c) end
    end
    return true
end

function TentsBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

function TentsBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local n     = board.n
    local cell  = self.cell
    local cw    = self.clue_w
    local thin  = 1

    bb:paintRect(x, y, self.w, self.h, C_BG)

    -- Grid cells
    for r = 1, n do
        for c = 1, n do
            local cx, cy = self:_cellOrigin(r, c)
            local mark  = board.marks[r][c]
            local is_tree  = board.trees[r][c]
            local is_wrong = board.wrong_cells and board.wrong_cells[r][c]

            local bg = C_BG
            if is_tree       then bg = C_TREE
            elseif is_wrong  then bg = C_WRONG
            elseif mark == TentsBoard.MARK_TENT  then bg = C_TENT
            elseif mark == TentsBoard.MARK_GRASS then bg = C_GRASS
            end

            local pad = math.max(1, math.floor(cell * 0.05))
            bb:paintRect(cx + pad, cy + pad, cell - 2*pad, cell - 2*pad, bg)

            -- Symbol
            if is_tree then
                centeredText(bb, "T", self.sym_face,
                    cx + cell//2, cy + cell//2, C_BG)
            elseif mark == TentsBoard.MARK_TENT then
                centeredText(bb, "^", self.sym_face,
                    cx + cell//2, cy + cell//2, C_FG)
            elseif mark == TentsBoard.MARK_GRASS then
                centeredText(bb, ".", self.sym_face,
                    cx + cell//2, cy + cell//2, C_FG)
            end
        end
    end

    -- Grid lines
    local gx = x + cw
    local gy = y + cw
    local gw = cell * n
    local gh = cell * n
    for i = 0, n do
        drawLine(bb, gx + i*cell, gy,      thin, gh, C_GRID)
        drawLine(bb, gx,          gy + i*cell, gw, thin, C_GRID)
    end
    -- Border
    local bw = math.max(2, thin)
    drawLine(bb, gx,          gy,          gw, bw, C_FG)
    drawLine(bb, gx,          gy + gh - bw, gw, bw, C_FG)
    drawLine(bb, gx,          gy,          bw, gh, C_FG)
    drawLine(bb, gx + gw - bw, gy,         bw, gh, C_FG)

    -- Row clues (right side)
    for r = 1, n do
        local cy = y + cw + (r - 1) * cell + cell // 2
        local cx = x + cw + gw + cw // 2
        centeredText(bb, tostring(board.row_clues[r] or 0),
            self.num_face, cx, cy, C_CLUE)
    end

    -- Column clues (bottom)
    for c = 1, n do
        local cx = x + cw + (c - 1) * cell + cell // 2
        local cy = y + cw + gh + cw // 2
        centeredText(bb, tostring(board.col_clues[c] or 0),
            self.num_face, cx, cy, C_CLUE)
    end
end

return TentsBoardWidget
