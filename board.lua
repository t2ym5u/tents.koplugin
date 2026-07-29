local UndoStack  = require("undo_stack")
local grid_utils = require("grid_utils")

local shuffle    = grid_utils.shuffle
local emptyGrid  = grid_utils.emptyGrid

-- Cell content (solution layer)
local CELL_EMPTY = 0
local CELL_TREE  = 1
local CELL_TENT  = 2

-- Player marks
local MARK_NONE  = 0
local MARK_TENT  = 1
local MARK_GRASS = 2

local SIZES = { 6, 8, 10, 12 }
local DEFAULT_N  = 8
local DEFAULT_DIFF = "medium"

-- Density of tent count per row (approximate trees per row)
local DENSITY = { easy = 0.5, medium = 0.65, hard = 0.8 }

-- ---------------------------------------------------------------------------
-- Generator
-- ---------------------------------------------------------------------------

local DIR4 = { {-1,0},{1,0},{0,-1},{0,1} }

local function inBounds(r, c, n)
    return r >= 1 and r <= n and c >= 1 and c <= n
end

local function tentsTouching(tents, r, c, n)
    for dr = -1, 1 do
        for dc = -1, 1 do
            if not (dr == 0 and dc == 0) then
                local nr, nc = r + dr, c + dc
                if inBounds(nr, nc, n) and tents[nr][nc] then
                    return true
                end
            end
        end
    end
    return false
end

local function generateSolution(n, num_pairs)
    -- returns trees[r][c], tents[r][c] or nil on failure
    for _ = 1, 30 do  -- retry outer loop
        local trees = emptyGrid(n, n, false)
        local tents = emptyGrid(n, n, false)
        local used  = emptyGrid(n, n, false)   -- occupied by any piece
        local placed = 0

        -- Build shuffled candidate tent positions
        local cells = {}
        for r = 1, n do
            for c = 1, n do cells[#cells + 1] = {r, c} end
        end
        shuffle(cells)

        for _, pos in ipairs(cells) do
            local r, c = pos[1], pos[2]
            if not used[r][c] and not tentsTouching(tents, r, c, n) then
                -- Try to find an adjacent tree cell
                local dirs = { {-1,0},{1,0},{0,-1},{0,1} }
                shuffle(dirs)
                for _, d in ipairs(dirs) do
                    local tr, tc = r + d[1], c + d[2]
                    if inBounds(tr, tc, n) and not used[tr][tc] then
                        -- Place tent at (r,c) and tree at (tr,tc)
                        tents[r][c]  = true
                        trees[tr][tc] = true
                        used[r][c]   = true
                        used[tr][tc] = true
                        placed = placed + 1
                        break
                    end
                end
            end
            if placed >= num_pairs then break end
        end

        if placed >= math.max(2, math.floor(num_pairs * 0.8)) then
            return trees, tents
        end
    end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- Uniqueness counter. The puzzle's visible state is tree positions (shown
-- directly) plus row/col tent-count clues -- there's no "given" mask on
-- the unknown tent layer at all. The win-check compares literally against
-- the stored solution, but the REAL constraint set this checks is: each
-- tree gets exactly one tent, orthogonally adjacent, no two tents adjacent
-- to each other (incl. diagonally), and the resulting per-row/col tent
-- counts match the shown clues. MRV backtracking over trees (fewest legal
-- candidate tent cells first): each tree picks one of its up-to-4
-- orthogonal empty neighbors as its tent, no two trees may claim the same
-- cell, no two placed tents may be adjacent, and the final row/col counts
-- must exactly match the clues.
-- ---------------------------------------------------------------------------

local function countSolutions(trees, row_clues, col_clues, n, limit, node_budget)
    local tree_list = {}
    for r = 1, n do
        for c = 1, n do
            if trees[r][c] then tree_list[#tree_list + 1] = { r = r, c = c } end
        end
    end

    local tent_at = {}
    for r = 1, n do tent_at[r] = {}; for c = 1, n do tent_at[r][c] = false end end
    local claimed_by = {}
    local row_count, col_count = {}, {}
    for i = 1, n do row_count[i] = 0; col_count[i] = 0 end

    local placed = {}
    for i = 1, #tree_list do placed[i] = false end

    local solutions, nodes, exhausted = 0, 0, false

    local function cellKey(r, c) return r * 1000 + c end

    local function tentsTouching(r, c)
        for dr = -1, 1 do
            for dc = -1, 1 do
                if not (dr == 0 and dc == 0) then
                    local nr, nc = r + dr, c + dc
                    if inBounds(nr, nc, n) and tent_at[nr][nc] then return true end
                end
            end
        end
        return false
    end

    local function candidatesFor(tree)
        local cands = {}
        for _, d in ipairs(DIR4) do
            local nr, nc = tree.r + d[1], tree.c + d[2]
            if inBounds(nr, nc, n) and not trees[nr][nc]
                and not claimed_by[cellKey(nr, nc)]
                and not tentsTouching(nr, nc) then
                cands[#cands + 1] = { nr, nc }
            end
        end
        return cands
    end

    local function search()
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end

        local best_i, best_cands, best_len = nil, nil, math.huge
        for i = 1, #tree_list do
            if not placed[i] then
                local cands = candidatesFor(tree_list[i])
                if #cands < best_len then
                    best_len, best_cands, best_i = #cands, cands, i
                    if best_len == 0 then break end
                end
            end
        end

        if not best_i then
            for r = 1, n do if row_count[r] ~= row_clues[r] then return end end
            for c = 1, n do if col_count[c] ~= col_clues[c] then return end end
            solutions = solutions + 1
            return
        end
        if best_len == 0 then return end

        placed[best_i] = true
        for _, cell in ipairs(best_cands) do
            local r, c = cell[1], cell[2]
            tent_at[r][c] = true
            claimed_by[cellKey(r, c)] = true
            row_count[r] = row_count[r] + 1
            col_count[c] = col_count[c] + 1

            search()

            tent_at[r][c] = false
            claimed_by[cellKey(r, c)] = nil
            row_count[r] = row_count[r] - 1
            col_count[c] = col_count[c] - 1
            if solutions >= limit or exhausted then break end
        end
        placed[best_i] = false
    end

    search()
    return solutions, exhausted
end

local function uniquenessNodeBudget(n)
    if n <= 8 then return 30000 end
    if n <= 10 then return 60000 end
    return 100000
end

-- ---------------------------------------------------------------------------
-- TentsBoard
-- ---------------------------------------------------------------------------

local TentsBoard = {}
TentsBoard.__index = TentsBoard

function TentsBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        n          = opts.n          or DEFAULT_N,
        difficulty = opts.difficulty or DEFAULT_DIFF,
        trees      = nil,    -- solution trees
        tents_sol  = nil,    -- solution tents
        marks      = nil,    -- player marks
        row_clues  = nil,
        col_clues  = nil,
        wrong_cells= nil,
        won        = false,
        undo       = UndoStack:new{ max_size = 500 },
    }, self)
    obj:generate()
    return obj
end

-- The win-check compares literally against the stored solution, so the
-- clues shown (tree positions + row/col counts) need to pin down that
-- exact tent placement uniquely -- there's no "given" mask to dig here,
-- so like hitori/nurikabe/starbattle this generates+verifies whole
-- candidate solutions instead. Measured pre-fix: real, moderate ambiguity
-- (roughly 60-87% unique across sizes/difficulties, worse at hard).
function TentsBoard:generate(diff)
    self.difficulty = diff or self.difficulty
    local n = self.n
    local density = DENSITY[self.difficulty] or 0.65
    local num_pairs = math.max(2, math.floor(n * density))
    local node_budget = uniquenessNodeBudget(n)

    local best_trees, best_tents, best_row_clues, best_col_clues

    for attempt = 1, 60 do
        local trees, tents = generateSolution(n, num_pairs)
        if trees then
            local row_clues, col_clues = {}, {}
            for r = 1, n do
                local cnt = 0
                for c = 1, n do if tents[r][c] then cnt = cnt + 1 end end
                row_clues[r] = cnt
            end
            for c = 1, n do
                local cnt = 0
                for r = 1, n do if tents[r][c] then cnt = cnt + 1 end end
                col_clues[c] = cnt
            end

            if not best_trees then
                best_trees, best_tents, best_row_clues, best_col_clues = trees, tents, row_clues, col_clues
            end

            local solutions, exhausted = countSolutions(trees, row_clues, col_clues, n, 2, node_budget)
            if solutions == 1 and not exhausted then
                best_trees, best_tents, best_row_clues, best_col_clues = trees, tents, row_clues, col_clues
                break
            end
        end
    end

    local trees, tents = best_trees, best_tents
    if not trees then
        -- Fallback: minimal puzzle
        trees = emptyGrid(n, n, false)
        tents = emptyGrid(n, n, false)
        if n >= 2 then
            trees[1][2] = true; tents[1][1] = true
            if n >= 4 then trees[3][4] = true; tents[3][3] = true end
        end
        best_row_clues, best_col_clues = {}, {}
        for r = 1, n do
            local cnt = 0
            for c = 1, n do if tents[r][c] then cnt = cnt + 1 end end
            best_row_clues[r] = cnt
        end
        for c = 1, n do
            local cnt = 0
            for r = 1, n do if tents[r][c] then cnt = cnt + 1 end end
            best_col_clues[c] = cnt
        end
    end

    self.trees     = trees
    self.tents_sol = tents
    self.marks     = emptyGrid(n, n, MARK_NONE)
    self.wrong_cells = emptyGrid(n, n, false)
    self.won       = false
    self.undo:clear()
    self.row_clues = best_row_clues
    self.col_clues = best_col_clues
end

function TentsBoard:setMark(r, c, mark)
    if self.trees[r][c] then return false end  -- can't mark tree cells
    if self.won then return false end
    local old = self.marks[r][c]
    if old == mark then
        -- Cycle: none → tent → grass → none
        mark = MARK_NONE
    end
    self.undo:push{ r = r, c = c, old = old }
    self.marks[r][c]        = mark
    self.wrong_cells[r][c]  = false
    self:_checkWin()
    return true
end

function TentsBoard:cycleCell(r, c)
    if self.trees[r][c] then return false end
    local cur = self.marks[r][c]
    local next_mark
    if cur == MARK_NONE  then next_mark = MARK_TENT
    elseif cur == MARK_TENT  then next_mark = MARK_GRASS
    else                      next_mark = MARK_NONE
    end
    return self:setMark(r, c, next_mark)
end

function TentsBoard:undoMove()
    local entry = self.undo:pop()
    if not entry then return false end
    self.marks[entry.r][entry.c]       = entry.old
    self.wrong_cells[entry.r][entry.c] = false
    self.won = false
    return true
end

function TentsBoard:check()
    local n = self.n
    self.wrong_cells = emptyGrid(n, n, false)

    -- Check row/col counts
    for r = 1, n do
        local cnt = 0
        for c = 1, n do if self.marks[r][c] == MARK_TENT then cnt = cnt + 1 end end
        if cnt ~= self.row_clues[r] then
            for c = 1, n do
                if self.marks[r][c] == MARK_TENT then
                    self.wrong_cells[r][c] = true
                end
            end
        end
    end
    for c = 1, n do
        local cnt = 0
        for r = 1, n do if self.marks[r][c] == MARK_TENT then cnt = cnt + 1 end end
        if cnt ~= self.col_clues[c] then
            for r = 1, n do
                if self.marks[r][c] == MARK_TENT then
                    self.wrong_cells[r][c] = true
                end
            end
        end
    end

    -- Check adjacency between tents
    for r = 1, n do
        for c = 1, n do
            if self.marks[r][c] == MARK_TENT then
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if not (dr == 0 and dc == 0) then
                            local nr, nc = r + dr, c + dc
                            if inBounds(nr, nc, n) and self.marks[nr][nc] == MARK_TENT then
                                self.wrong_cells[r][c] = true
                                self.wrong_cells[nr][nc] = true
                            end
                        end
                    end
                end
            end
        end
    end
end

function TentsBoard:reveal()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            if not self.trees[r][c] then
                self.marks[r][c] = self.tents_sol[r][c] and MARK_TENT or MARK_GRASS
            end
        end
    end
    self.won = true
end

function TentsBoard:_checkWin()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            if not self.trees[r][c] then
                local should = self.tents_sol[r][c] and MARK_TENT or MARK_NONE
                -- Accept MARK_GRASS as equivalent to MARK_NONE for win check
                local actual = self.marks[r][c]
                if actual == MARK_GRASS then actual = MARK_NONE end
                if actual ~= should then
                    self.won = false
                    return
                end
            end
        end
    end
    self.won = true
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function TentsBoard:serialize()
    local n = self.n
    local trees_flat, tents_flat, marks_flat = {}, {}, {}
    for r = 1, n do
        for c = 1, n do
            trees_flat[#trees_flat + 1] = self.trees[r][c] and 1 or 0
            tents_flat[#tents_flat + 1] = self.tents_sol[r][c] and 1 or 0
            marks_flat[#marks_flat + 1] = self.marks[r][c]
        end
    end
    return {
        n          = n,
        difficulty = self.difficulty,
        trees      = trees_flat,
        tents_sol  = tents_flat,
        marks      = marks_flat,
        row_clues  = self.row_clues,
        col_clues  = self.col_clues,
        won        = self.won,
    }
end

function TentsBoard:load(data)
    if type(data) ~= "table" or not data.trees then return false end
    local n = data.n or DEFAULT_N
    self.n          = n
    self.difficulty = data.difficulty or DEFAULT_DIFF
    self.trees      = emptyGrid(n, n, false)
    self.tents_sol  = emptyGrid(n, n, false)
    self.marks      = emptyGrid(n, n, MARK_NONE)
    self.wrong_cells= emptyGrid(n, n, false)
    local idx = 1
    for r = 1, n do
        for c = 1, n do
            self.trees[r][c]     = (data.trees[idx]    or 0) == 1
            self.tents_sol[r][c] = (data.tents_sol[idx] or 0) == 1
            self.marks[r][c]     = data.marks[idx] or MARK_NONE
            idx = idx + 1
        end
    end
    self.row_clues = data.row_clues or {}
    self.col_clues = data.col_clues or {}
    self.won       = data.won or false
    self.undo:clear()
    return true
end

TentsBoard.CELL_EMPTY = CELL_EMPTY
TentsBoard.CELL_TREE  = CELL_TREE
TentsBoard.CELL_TENT  = CELL_TENT
TentsBoard.MARK_NONE  = MARK_NONE
TentsBoard.MARK_TENT  = MARK_TENT
TentsBoard.MARK_GRASS = MARK_GRASS
TentsBoard.SIZES      = SIZES
TentsBoard.DEFAULT_N  = DEFAULT_N

return TentsBoard
