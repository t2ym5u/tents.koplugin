local UndoStack  = require("undo_stack")
local grid_utils = require("grid_utils")
local Hint       = require("hint")

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

-- What each level asks for (1.6.0).
--   pairs          tree/tent pairs, as a share of the n*n cells (a full
--                  grid packs about n*n/5); before 1.6.0 this was n*0.5 to
--                  n*0.8 pairs for the WHOLE grid, so a 12x12 had 6 to 9
--                  trees, most rows were empty and every puzzle solved
--                  itself
--   min_t2/max_t2  how many tier-2 deductions (see logicSolve) the
--                  solution needs; tier 1 alone when both are 0
-- Never trial and error, at any level.
local LEVELS = {
    easy   = function(n) return { pairs = 0.15, min_t2 = 0, max_t2 = 0 } end,
    medium = function(n) return { pairs = 0.18, min_t2 = 1,
                                  max_t2 = n >= 10 and 4 or (n >= 8 and 3 or 2) } end,
    hard   = function(n) return { pairs = 0.22, min_t2 = n >= 10 and 5 or (n >= 8 and 4 or 3),
                                  max_t2 = math.huge } end,
}

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

-- One random layout of up to num_pairs tent/tree pairs: tents never touch
-- (not even diagonally), each tree sits orthogonally next to its own tent.
-- Returns trees, tents (boolean grids) and the number of pairs placed.
local function generateSolution(n, num_pairs)
    local trees = emptyGrid(n, n, false)
    local tents = emptyGrid(n, n, false)
    local used  = emptyGrid(n, n, false)   -- occupied by any piece
    local placed = 0

    local cells = {}
    for r = 1, n do
        for c = 1, n do cells[#cells + 1] = { r, c } end
    end
    shuffle(cells)

    for _, pos in ipairs(cells) do
        if placed >= num_pairs then break end
        local r, c = pos[1], pos[2]
        if not used[r][c] and not tentsTouching(tents, r, c, n) then
            local d0 = math.random(4)
            for k = 0, 3 do
                local d = DIR4[(d0 + k - 1) % 4 + 1]
                local tr, tc = r + d[1], c + d[2]
                if inBounds(tr, tc, n) and not used[tr][tc] then
                    tents[r][c]   = true
                    trees[tr][tc] = true
                    used[r][c]    = true
                    used[tr][tc]  = true
                    placed = placed + 1
                    break
                end
            end
        end
    end
    return trees, tents, placed
end

-- ---------------------------------------------------------------------------
-- Human-style solver, no trial and error. Cells are unknown (0), tent (1)
-- or grass (-1); tree cells are never touched.
--   tier 1  a full line is closed with grass, a line with exactly as many
--           open cells as tents still missing is filled with tents, the
--           8 cells around a tent are grass, a tree with one free
--           neighbour gets its tent there, a tent next to one free tree
--           belongs to it, and a cell next to no free tree is grass.
--   tier 2  a cell touching every possible tent of a tree is grass (that
--           tree's tent will touch it), and line reasoning: list the ways
--           the line's missing tents fit its open cells (never two side by
--           side); a cell used by all of them is a tent, by none of them
--           grass, and a cell next to the line touched by every way is
--           grass.
-- Each tier-2 step goes back to tier 1, so tier2 counts the steps a
-- player could not take with tier 1 alone. Every rule is sound, so
-- reaching the full grid proves the solution is the only one.
-- Returns solved (every cell decided), tier2, and the cell states.
-- ---------------------------------------------------------------------------

-- Neighbour lists and lines for an n x n grid, built once per size.
local geometry_cache = {}
local function geometry(n)
    local g = geometry_cache[n]
    if g then return g end
    local ortho, king, lines = {}, {}, {}
    for r = 1, n do
        for c = 1, n do
            local o, k = {}, {}
            for dr = -1, 1 do
                for dc = -1, 1 do
                    if (dr ~= 0 or dc ~= 0) and inBounds(r + dr, c + dc, n) then
                        local j = (r + dr - 1) * n + c + dc
                        k[#k + 1] = j
                        if dr == 0 or dc == 0 then o[#o + 1] = j end
                    end
                end
            end
            ortho[(r - 1) * n + c], king[(r - 1) * n + c] = o, k
        end
    end
    for r = 1, n do
        local l = {}
        for c = 1, n do l[#l + 1] = (r - 1) * n + c end
        lines[#lines + 1] = l
    end
    for c = 1, n do
        local l = {}
        for r = 1, n do l[#l + 1] = (r - 1) * n + c end
        lines[#lines + 1] = l
    end
    g = { ortho = ortho, king = king, lines = lines }
    geometry_cache[n] = g
    return g
end

local function logicSolve(trees, row_clues, col_clues, n, max_tier)
    max_tier = max_tier or 2
    local N = n * n
    local s = {}
    local geo = geometry(n)
    local ortho, king = geo.ortho, geo.king
    local tree_of = {}          -- cell -> tree number
    local tree_cell = {}        -- tree number -> cell
    for r = 1, n do
        for c = 1, n do
            if trees[r][c] then
                local i = (r - 1) * n + c
                tree_cell[#tree_cell + 1] = i
                tree_of[i] = #tree_cell
            end
        end
    end
    -- a cell next to no tree can never hold a tent
    for i = 1, N do
        if tree_of[i] then
            s[i] = false
        else
            s[i] = -1
            for _, j in ipairs(ortho[i]) do
                if tree_of[j] then s[i] = 0; break end
            end
        end
    end
    local lines, line_k = geo.lines, {}
    for r = 1, n do line_k[r] = row_clues[r] or 0 end
    for c = 1, n do line_k[n + c] = col_clues[c] or 0 end

    local pair_t, pair_c = {}, {}   -- tree -> its tent cell, cell -> tree
    local line_idle = {}

    local function setTent(i)
        if s[i] ~= 0 then return false end
        s[i] = 1
        for _, j in ipairs(king[i]) do
            if s[j] == 0 then s[j] = -1 end
        end
        return true
    end
    local function setGrass(i)
        if s[i] ~= 0 then return false end
        s[i] = -1
        return true
    end
    -- the cells that can still be tree t's tent
    local function candidates(t)
        local out = {}
        for _, j in ipairs(ortho[tree_cell[t]]) do
            local v = s[j]
            if v and v >= 0 and not pair_c[j] then out[#out + 1] = j end
        end
        return out
    end

    local function tier1()
        local progress = false
        for li, l in ipairs(lines) do
            local k = line_k[li]
            local t, u = 0, 0
            for q = 1, #l do
                local v = s[l[q]]
                if v == 1 then t = t + 1 elseif v == 0 then u = u + 1 end
            end
            if u > 0 then
                if t >= k then
                    for q = 1, #l do progress = setGrass(l[q]) or progress end
                elseif t + u == k then
                    for q = 1, #l do progress = setTent(l[q]) or progress end
                end
            end
        end
        for t = 1, #tree_cell do
            if not pair_t[t] then
                local only, cnt = nil, 0
                for _, j in ipairs(ortho[tree_cell[t]]) do
                    local v = s[j]
                    if v and v >= 0 and not pair_c[j] then only, cnt = j, cnt + 1 end
                end
                if cnt == 1 then
                    pair_t[t], pair_c[only] = only, t
                    setTent(only)
                    progress = true
                end
            end
        end
        for i = 1, N do
            if s[i] == 1 and not pair_c[i] then
                local only, cnt = nil, 0
                for _, j in ipairs(ortho[i]) do
                    local t = tree_of[j]
                    if t and not pair_t[t] then only, cnt = t, cnt + 1 end
                end
                if cnt == 1 then
                    pair_t[only], pair_c[i] = i, only
                    progress = true
                end
            end
        end
        for i = 1, N do
            if s[i] == 0 then
                local free = false
                for _, j in ipairs(ortho[i]) do
                    local t = tree_of[j]
                    if t and not pair_t[t] then free = true; break end
                end
                if not free then progress = setGrass(i) or progress end
            end
        end
        return progress
    end

    local function tier2()
        -- a cell touching every possible tent of a tree
        for t = 1, #tree_cell do
            if not pair_t[t] then
                local cands = candidates(t)
                local is_cand = {}
                for _, j in ipairs(cands) do is_cand[j] = true end
                local count = {}
                for _, j in ipairs(cands) do
                    for _, x in ipairs(king[j]) do
                        if s[x] == 0 and not is_cand[x] then count[x] = (count[x] or 0) + 1 end
                    end
                end
                local progress = false
                for x, k in pairs(count) do
                    if k == #cands then progress = setGrass(x) or progress end
                end
                if progress then return true end
            end
        end
        -- line reasoning
        for li, l in ipairs(lines) do
            local open, t = {}, 0
            for q = 1, #l do
                local v = s[l[q]]
                if v == 1 then t = t + 1 elseif v == 0 then open[#open + 1] = q end
            end
            local need = line_k[li] - t
            -- cells only ever go from unknown to decided, so a line with
            -- as many open cells as when it last gave nothing gives
            -- nothing again
            if need > 0 and need < #open and line_idle[li] ~= #open then
                local used, ways = {}, 0
                for _, q in ipairs(open) do used[q] = 0 end
                local touch_all
                local pick = {}
                local function rec(a, left, last)
                    if left == 0 then
                        ways = ways + 1
                        local touched = {}
                        for q in pairs(pick) do
                            used[q] = used[q] + 1
                            for _, x in ipairs(king[l[q]]) do
                                if s[x] == 0 then touched[x] = true end
                            end
                        end
                        if not touch_all then
                            touch_all = touched
                        else
                            for x in pairs(touch_all) do
                                if not touched[x] then touch_all[x] = nil end
                            end
                        end
                        return
                    end
                    for p = a, #open - left + 1 do
                        local q = open[p]
                        if q > last + 1 then
                            pick[q] = true
                            rec(p + 1, left - 1, q)
                            pick[q] = nil
                        end
                    end
                end
                rec(1, need, -1)
                local progress = false
                if ways > 0 then
                    local on_line = {}
                    for _, q in ipairs(open) do
                        on_line[l[q]] = true
                        if used[q] == ways then progress = setTent(l[q]) or progress
                        elseif used[q] == 0 then progress = setGrass(l[q]) or progress end
                    end
                    for x in pairs(touch_all) do
                        if not on_line[x] then progress = setGrass(x) or progress end
                    end
                end
                if progress then return true end
                line_idle[li] = #open
            end
        end
        return false
    end

    local t2 = 0
    while true do
        if not tier1() then
            if max_tier >= 2 and tier2() then
                t2 = t2 + 1
            else
                break
            end
        end
    end
    for i = 1, N do
        if s[i] == 0 then return false, t2, s end
    end
    return true, t2, s
end

-- Does the stored solution match what the solver deduced?
local function sameAsSolution(s, tents, n)
    for r = 1, n do
        for c = 1, n do
            local v = s[(r - 1) * n + c]
            if v ~= false and (v == 1) ~= (tents[r][c] == true) then return false end
        end
    end
    return true
end

local function lineCounts(tents, n)
    local row_clues, col_clues = {}, {}
    for i = 1, n do row_clues[i] = 0; col_clues[i] = 0 end
    for r = 1, n do
        for c = 1, n do
            if tents[r][c] then
                row_clues[r] = row_clues[r] + 1
                col_clues[c] = col_clues[c] + 1
            end
        end
    end
    return row_clues, col_clues
end


-- ---------------------------------------------------------------------------
-- Exact solution counter (the specs cross-check logicSolve with it).
-- Counts tent layouts that keep every rule: each tree gets exactly one
-- tent, orthogonally adjacent, no two tents touch (incl. diagonally), and
-- the per-row/col tent counts match the clues. MRV backtracking over trees
-- (fewest legal candidate tent cells first); two pairings that give the
-- same tents count once.
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
    local seen = {}

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
            -- A row or column already holding its clue's worth of tents
            -- takes no more: dropping those cells here (rather than only
            -- checking the counts once every tree is placed) lets MRV see
            -- the real choices and prunes dead branches early.
            if inBounds(nr, nc, n) and not trees[nr][nc]
                and not claimed_by[cellKey(nr, nc)]
                and row_count[nr] < row_clues[nr]
                and col_count[nc] < col_clues[nc]
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
            -- count tent layouts, not pairings: two trees may swap tents
            -- without changing what the player sees
            local key = {}
            for r = 1, n do
                for c = 1, n do key[#key + 1] = tent_at[r][c] and "1" or "0" end
            end
            key = table.concat(key)
            if not seen[key] then
                seen[key] = true
                solutions = solutions + 1
            end
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
    -- opts.empty: the caller loads a save or generates itself, so don't
    -- build a puzzle that would be thrown away.
    if not opts.empty then obj:generate() end
    return obj
end

TentsBoard.LEVELS = LEVELS
-- Candidates tried per puzzle before settling for the closest one; small
-- grids are cheap to try and rarely land in the Medium/Hard window.
TentsBoard.ATTEMPTS = { [6] = 600, [8] = 250 }
TentsBoard.DEFAULT_ATTEMPTS = 150

-- Whole candidates are generated and graded: a random layout, then the
-- human-style solver (logicSolve). A candidate is kept when the solver
-- finishes it (so it has exactly one solution and needs no trial and
-- error) with a tier-2 count in the level's range. All work is bounded by
-- attempt counts, never the clock (same seed, same puzzle on every device).
-- on_progress(fraction), optional: called after every candidate.
function TentsBoard:generate(diff, on_progress)
    self.difficulty = diff or self.difficulty
    local n = self.n
    local level = (LEVELS[self.difficulty] or LEVELS.medium)(n)
    local num_pairs = math.max(2, math.floor(n * n * level.pairs + 0.5))
    local attempts = TentsBoard.ATTEMPTS[n] or TentsBoard.DEFAULT_ATTEMPTS

    -- Fallback if the budget runs out (rare, see the specs): the solvable
    -- candidate whose tier-2 count came closest to the range.
    local best, best_dist
    local attempt = 0
    while true do
        attempt = attempt + 1
        -- Past the budget with nothing solvable yet: fewer pairs, which
        -- always ends in a puzzle tier 1 solves.
        local want = num_pairs
        if attempt > attempts then
            want = math.max(1, num_pairs - math.floor((attempt - attempts) / 10))
        end
        local trees, tents, placed = generateSolution(n, want)
        if placed >= math.floor(want * 0.9) then
            local row_clues, col_clues = lineCounts(tents, n)
            local solved, t2, s = logicSolve(trees, row_clues, col_clues, n, 2)
            if solved and sameAsSolution(s, tents, n) then
                local dist = 0
                if t2 < level.min_t2 then dist = level.min_t2 - t2
                elseif t2 > level.max_t2 then dist = t2 - level.max_t2 end
                if not best or dist < best_dist then
                    best, best_dist = { trees, tents, row_clues, col_clues }, dist
                end
                if dist == 0 then break end
            end
        end
        if on_progress then on_progress(math.min(1, attempt / attempts)) end
        if attempt >= attempts and best then break end
    end

    self.trees     = best[1]
    self.tents_sol = best[2]
    self.row_clues = best[3]
    self.col_clues = best[4]
    self.marks     = emptyGrid(n, n, MARK_NONE)
    self.wrong_cells = emptyGrid(n, n, false)
    self.won       = false
    self.undo:clear()
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

-- Won when the tents keep every rule, whatever the stored solution says
-- (1.6.0; it compared with the solution before): each line holds its
-- clue's worth of tents, no two tents touch, and trees and tents pair up
-- one to one, each tent orthogonally next to its tree. Grass marks are
-- optional.
function TentsBoard:_checkWin()
    self.won = self:followsRules()
end

function TentsBoard:followsRules()
    local n = self.n
    local marks, trees = self.marks, self.trees
    local row, col = {}, {}
    for i = 1, n do row[i] = 0; col[i] = 0 end
    local tent_list, tree_count = {}, 0
    for r = 1, n do
        for c = 1, n do
            if trees[r][c] then
                tree_count = tree_count + 1
            elseif marks[r][c] == MARK_TENT then
                row[r] = row[r] + 1
                col[c] = col[c] + 1
                tent_list[#tent_list + 1] = { r, c }
            end
        end
    end
    for i = 1, n do
        if row[i] ~= (self.row_clues[i] or 0) or col[i] ~= (self.col_clues[i] or 0) then
            return false
        end
    end
    for _, p in ipairs(tent_list) do
        local r, c = p[1], p[2]
        for dr = -1, 1 do
            for dc = -1, 1 do
                if (dr ~= 0 or dc ~= 0) and inBounds(r + dr, c + dc, n)
                    and not trees[r + dr][c + dc] and marks[r + dr][c + dc] == MARK_TENT then
                    return false
                end
            end
        end
    end
    if #tent_list ~= tree_count then return false end
    -- one tree per tent: bipartite matching (augmenting paths)
    local owner = {}   -- tree key -> tent number
    local function tryTent(k, seen)
        local r, c = tent_list[k][1], tent_list[k][2]
        for _, d in ipairs(DIR4) do
            local tr, tc = r + d[1], c + d[2]
            if inBounds(tr, tc, n) and trees[tr][tc] then
                local key = (tr - 1) * n + tc
                if not seen[key] then
                    seen[key] = true
                    if not owner[key] or tryTent(owner[key], seen) then
                        owner[key] = k
                        return true
                    end
                end
            end
        end
        return false
    end
    for k = 1, #tent_list do
        if not tryTent(k, {}) then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

-- Marking grass is optional -- _checkWin treats it as an untouched cell -- so
-- only the tents decide the puzzle: cells the solution leaves empty read as
-- empty and never get offered, and equals() compares tent-ness. Tree cells
-- cannot be marked at all.
Hint.install(TentsBoard, {
    getUser     = function(b, r, c) return b.marks[r][c] end,
    getSolution = function(b, r, c) return b.tents_sol[r][c] and MARK_TENT or MARK_NONE end,
    isEmpty     = function(v) return v == MARK_NONE end,
    equals      = function(u, s) return (u == MARK_TENT) == (s == MARK_TENT) end,
    isGiven     = function(b, r, c) return b.trees[r][c] == true end,
    setCell     = function(b, r, c, v) return b:setMark(r, c, v) end,
    blank       = MARK_NONE,
})

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
TentsBoard._countSolutions = countSolutions   -- for the specs
TentsBoard._logicSolve     = logicSolve
TentsBoard._generateSolution = generateSolution

return TentsBoard
