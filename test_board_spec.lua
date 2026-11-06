local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("TentsBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    local function newBoard(diff)
        math.randomseed(42)
        return Board:new({ n = 6, difficulty = diff or "easy" })
    end

    describe("new / generate", function()
        it("creates a 6x6 board where every tree has a matching tent count", function()
            local b = newBoard()
            assert.are.equal(6, b.n)
            local trees, tents = 0, 0
            for r = 1, b.n do
                for c = 1, b.n do
                    if b.trees[r][c] then trees = trees + 1 end
                    if b.tents_sol[r][c] then tents = tents + 1 end
                end
            end
            assert.are.equal(trees, tents)
        end)

        it("row/col clues match the actual solution tent counts", function()
            local b = newBoard()
            for r = 1, b.n do
                local cnt = 0
                for c = 1, b.n do if b.tents_sol[r][c] then cnt = cnt + 1 end end
                assert.are.equal(cnt, b.row_clues[r])
            end
        end)

        it("no two solution tents are adjacent (including diagonally)", function()
            local b = newBoard()
            local n = b.n
            for r = 1, n do
                for c = 1, n do
                    if b.tents_sol[r][c] then
                        for dr = -1, 1 do
                            for dc = -1, 1 do
                                if not (dr == 0 and dc == 0) then
                                    local nr, nc = r + dr, c + dc
                                    if nr >= 1 and nr <= n and nc >= 1 and nc <= n then
                                        assert.is_false(b.tents_sol[nr][nc] and true or false)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end)

    describe("cycleCell / setMark", function()
        it("cycles a non-tree cell none -> tent -> grass -> none", function()
            local b = newBoard()
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if not b.trees[rr][cc] then r, c = rr, cc; break end
                end
                if r then break end
            end
            assert.are.equal(Board.MARK_NONE, b.marks[r][c])
            b:cycleCell(r, c)
            assert.are.equal(Board.MARK_TENT, b.marks[r][c])
            b:cycleCell(r, c)
            assert.are.equal(Board.MARK_GRASS, b.marks[r][c])
            b:cycleCell(r, c)
            assert.are.equal(Board.MARK_NONE, b.marks[r][c])
        end)

        it("refuses to mark a tree cell", function()
            local b = newBoard()
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if b.trees[rr][cc] then r, c = rr, cc; break end
                end
                if r then break end
            end
            assert.is_false(b:cycleCell(r, c))
        end)
    end)

    describe("undoMove", function()
        it("restores the previous mark", function()
            local b = newBoard()
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if not b.trees[rr][cc] then r, c = rr, cc; break end
                end
                if r then break end
            end
            b:cycleCell(r, c)
            assert.is_true(b:undoMove())
            assert.are.equal(Board.MARK_NONE, b.marks[r][c])
        end)
    end)

    describe("reveal", function()
        it("places the solution's tents/grass and wins", function()
            local b = newBoard()
            b:reveal()
            assert.is_true(b.won)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips trees, solution tents and marks", function()
            local b = newBoard()
            b:reveal()
            local data = b:serialize()

            local b2 = Board:new({ n = 6 })
            assert.is_true(b2:load(data))
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(b.trees[r][c], b2.trees[r][c])
                    assert.are.equal(b.tents_sol[r][c], b2.tents_sol[r][c])
                end
            end
        end)

        it("load returns false for invalid data", function()
            local b = newBoard()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)

    describe("empty / countSolutions", function()
        it("new{ empty = true } builds no puzzle, and load fills it", function()
            local saved = Board:new{ n = 8, difficulty = "hard" }:serialize()
            local b = Board:new{ n = 8, difficulty = "hard", empty = true }
            assert.is_nil(b.trees)
            assert.is_true(b:load(saved))
            assert.are.same(saved, b:serialize())
        end)

        it("counts every placement when the clues allow several", function()
            -- Two trees side by side on a 4x4 board, at (2,2) and (2,3).
            local trees = {}
            for r = 1, 4 do trees[r] = { false, false, false, false } end
            trees[2][2], trees[2][3] = true, true
            -- Tents (1,2) and (3,3): row clues 1,0,1,0, col clues 0,1,1,0.
            -- (3,2)+(1,3) satisfies the same clues: two solutions.
            local count, exhausted = Board._countSolutions(
                trees, { 1, 0, 1, 0 }, { 0, 1, 1, 0 }, 4, 10, 1e7)
            assert.is_false(exhausted)
            assert.are.equal(2, count)
        end)

        it("counts tent layouts, not pairings", function()
            -- 3x3 ring: trees on the edge middles, tents in the corners.
            -- Each tree can take either neighbouring corner, so two
            -- pairings give the very same tents: one solution.
            local trees = {}
            for r = 1, 3 do trees[r] = { false, false, false } end
            trees[1][2], trees[2][1], trees[2][3], trees[3][2] = true, true, true, true
            local count, exhausted = Board._countSolutions(
                trees, { 2, 0, 2 }, { 2, 0, 2 }, 3, 10, 1e7)
            assert.is_false(exhausted)
            assert.are.equal(1, count)
        end)
    end)

    describe("generator (1.6.0)", function()
        local function trees(b)
            local k = 0
            for r = 1, b.n do for c = 1, b.n do if b.trees[r][c] then k = k + 1 end end end
            return k
        end

        it("every puzzle: one solution, no trial and error, in its level's window", function()
            for _, n in ipairs(Board.SIZES) do
                for _, d in ipairs({ "easy", "medium", "hard" }) do
                    local lvl = Board.LEVELS[d](n)
                    for seed = 1, 30 do
                        math.randomseed(seed)
                        local b = Board:new{ n = n, difficulty = d }
                        local count, exhausted = Board._countSolutions(
                            b.trees, b.row_clues, b.col_clues, n, 2, 1e7)
                        assert.is_false(exhausted)
                        assert.are.equal(1, count)
                        local solved, t2 = Board._logicSolve(b.trees, b.row_clues, b.col_clues, n, 2)
                        assert.is_true(solved, ("n=%d %s seed=%d needs trial"):format(n, d, seed))
                        assert.is_true(t2 >= lvl.min_t2 and t2 <= lvl.max_t2,
                            ("n=%d %s seed=%d: %d tier-2 steps"):format(n, d, seed, t2))
                        -- real puzzles, not a few lonely trees (was 3 to 9)
                        assert.is_true(trees(b) >= math.floor(n * n / 8),
                            ("n=%d %s seed=%d: %d trees"):format(n, d, seed, trees(b)))
                    end
                end
            end
        end)

        it("levels really differ: more trees and more tier-2 steps", function()
            for _, n in ipairs(Board.SIZES) do
                local avg = {}
                for _, d in ipairs({ "easy", "medium", "hard" }) do
                    local t, k = 0, 0
                    for seed = 1, 20 do
                        math.randomseed(seed)
                        local b = Board:new{ n = n, difficulty = d }
                        local _, t2 = Board._logicSolve(b.trees, b.row_clues, b.col_clues, n, 2)
                        t, k = t + t2, k + trees(b)
                    end
                    avg[d] = { t2 = t / 20, trees = k / 20 }
                end
                assert.are.equal(0, avg.easy.t2)
                assert.is_true(avg.medium.t2 > avg.easy.t2 and avg.hard.t2 > avg.medium.t2,
                    ("n=%d t2 %.1f/%.1f/%.1f"):format(n, avg.easy.t2, avg.medium.t2, avg.hard.t2))
                assert.is_true(avg.medium.trees > avg.easy.trees and avg.hard.trees > avg.medium.trees)
            end
        end)

        it("the same seed gives the same puzzle", function()
            for _, n in ipairs(Board.SIZES) do
                math.randomseed(77)
                local a = Board:new{ n = n, difficulty = "hard" }:serialize()
                math.randomseed(77)
                local b = Board:new{ n = n, difficulty = "hard" }:serialize()
                assert.are.same(a, b)
            end
        end)

        it("reports progress and stays quick (12x12 Hard)", function()
            local t = os.clock()
            local calls = 0
            for seed = 1, 30 do
                math.randomseed(seed)
                local b = Board:new{ n = 12, difficulty = "hard", empty = true }
                b:generate("hard", function(f)
                    calls = calls + 1
                    assert.is_true(f >= 0 and f <= 1)
                end)
            end
            assert.is_true(calls > 0)
            assert.is_true(os.clock() - t < 3, "30 puzzles took " .. (os.clock() - t) .. " s")
        end)

        it("logicSolve never decides a cell against the only solution", function()
            -- raw random layouts, unique or not, both tiers
            local bad = 0
            for seed = 1, 300 do
                math.randomseed(seed)
                local n = 6 + 2 * (seed % 2)
                local tr, te = Board._generateSolution(n, math.floor(n * n * (0.12 + (seed % 9) * 0.01)))
                local rc, cc = {}, {}
                for i = 1, n do rc[i], cc[i] = 0, 0 end
                for r = 1, n do for c = 1, n do
                    if te[r][c] then rc[r] = rc[r] + 1; cc[c] = cc[c] + 1 end
                end end
                local count = Board._countSolutions(tr, rc, cc, n, 2, 1e7)
                local solved, _, s = Board._logicSolve(tr, rc, cc, n, 2)
                if solved and count ~= 1 then bad = bad + 1 end
                if count == 1 then
                    for r = 1, n do for c = 1, n do
                        local v = s[(r - 1) * n + c]
                        if v and v ~= 0 and (v == 1) ~= te[r][c] then bad = bad + 1 end
                    end end
                end
            end
            assert.are.equal(0, bad)
        end)
    end)

    describe("win check (rules, not the stored solution)", function()
        local function blank(n)
            local g = {}
            for r = 1, n do g[r] = {} for c = 1, n do g[r][c] = false end end
            return g
        end

        local function puzzle(tree_cells, rows, cols)
            local b = Board:new{ n = 3, empty = true }
            b.trees, b.tents_sol, b.wrong_cells = blank(3), blank(3), blank(3)
            for _, p in ipairs(tree_cells) do b.trees[p[1]][p[2]] = true end
            b.row_clues, b.col_clues = rows, cols
            b.marks = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
            return b
        end

        it("accepts any layout that keeps the rules", function()
            -- the 3x3 ring; the stored solution is left empty on purpose
            local b = puzzle({ { 1, 2 }, { 2, 1 }, { 2, 3 }, { 3, 2 } }, { 2, 0, 2 }, { 2, 0, 2 })
            b:setMark(1, 1, Board.MARK_TENT)
            b:setMark(1, 3, Board.MARK_TENT)
            b:setMark(3, 1, Board.MARK_TENT)
            assert.is_false(b.won)
            b:setMark(2, 2, Board.MARK_GRASS)   -- grass marks are optional
            b:setMark(3, 3, Board.MARK_TENT)
            assert.is_true(b.won)
        end)

        it("refuses a tent that no tree can take", function()
            -- counts are right, but (1,1) only touches the tree diagonally
            local b = puzzle({ { 2, 2 } }, { 1, 0, 0 }, { 1, 0, 0 })
            b:setMark(1, 1, Board.MARK_TENT)
            assert.is_false(b.won)
        end)

        it("refuses touching tents", function()
            -- trees (1,1) and (3,3); tents (1,2) and (2,3) touch diagonally
            local b = puzzle({ { 1, 1 }, { 3, 3 } }, { 1, 1, 0 }, { 0, 1, 1 })
            b:setMark(1, 2, Board.MARK_TENT)
            b:setMark(2, 3, Board.MARK_TENT)
            assert.is_false(b.won)
        end)
    end)

    describe("old saves", function()
        it("a 1.5.x save loads and can still be won", function()
            -- 6x6 puzzle saved by 1.5.2 (3 trees)
            local data = {
                n = 6, difficulty = "easy", won = false,
                row_clues = { 1, 0, 1, 0, 1, 0 }, col_clues = { 1, 0, 0, 1, 0, 1 },
                trees = {}, tents_sol = {}, marks = {},
            }
            for i = 1, 36 do data.trees[i], data.tents_sol[i], data.marks[i] = 0, 0, 0 end
            local function at(r, c) return (r - 1) * 6 + c end
            data.trees[at(2, 1)], data.tents_sol[at(1, 1)] = 1, 1
            data.trees[at(3, 3)], data.tents_sol[at(3, 4)] = 1, 1
            data.trees[at(4, 6)], data.tents_sol[at(5, 6)] = 1, 1
            local b = Board:new{ n = 6, empty = true }
            assert.is_true(b:load(data))
            b:setMark(1, 1, Board.MARK_TENT)
            b:setMark(3, 4, Board.MARK_TENT)
            assert.is_false(b.won)
            b:setMark(5, 6, Board.MARK_TENT)
            assert.is_true(b.won)
        end)
    end)
end)
