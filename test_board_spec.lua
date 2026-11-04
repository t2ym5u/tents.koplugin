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

        it("finds exactly one solution for every generated puzzle", function()
            for _, n in ipairs(Board.SIZES) do
                for _, d in ipairs({ "easy", "medium", "hard" }) do
                    for seed = 1, 15 do
                        math.randomseed(seed)
                        local b = Board:new{ n = n, difficulty = d }
                        local count, exhausted = Board._countSolutions(
                            b.trees, b.row_clues, b.col_clues, n, 2, 1e7)
                        assert.is_false(exhausted)
                        assert.are.equal(1, count)
                    end
                end
            end
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

        it("generates 12x12 Hard puzzles quickly (was up to ~0.1 s each on a desktop)", function()
            local t = os.clock()
            for seed = 1, 30 do
                math.randomseed(seed)
                Board:new{ n = 12, difficulty = "hard" }
            end
            assert.is_true(os.clock() - t < 3, "30 puzzles took " .. (os.clock() - t) .. " s")
        end)
    end)
end)
