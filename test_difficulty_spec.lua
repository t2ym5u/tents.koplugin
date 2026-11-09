-- Difficulty guarantees for Tents: every size x level builds a unique
-- puzzle quickly, the game's logic solver finishes it with no trial and a
-- tier-2 count inside the level's window (Easy: tier 1 only), levels are
-- ordered (more trees, more tier-2 steps), and a seed gives the same puzzle
-- without reading the clock.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Runs fn with os.clock/os.time/os.date replaced by functions that fail:
-- a generator must bound its work by counts, never by time.
local function withoutClock(fn)
    local oc, ot, od = os.clock, os.time, os.date
    local function boom(name) return function() error("generator read " .. name, 2) end end
    os.clock, os.time, os.date = boom("os.clock"), boom("os.time"), boom("os.date")
    local ok, err = pcall(fn)
    os.clock, os.time, os.date = oc, ot, od
    if not ok then error(err, 0) end
end

describe("Tents difficulty", function()
    local Board

    setup(function()
        Board = require("board")
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

        it("every size and level builds within a generous time bound", function()
            for _, n in ipairs(Board.SIZES) do
                for _, d in ipairs({ "easy", "medium", "hard" }) do
                    local worst = 0
                    for seed = 1, 5 do
                        math.randomseed(seed * 131 + n)
                        local b = Board:new{ n = n, empty = true }
                        local t0 = os.clock()
                        b:generate(d)
                        worst = math.max(worst, os.clock() - t0)
                    end
                    assert.is_true(worst < 1.5, ("n=%d %s took %.2f s"):format(n, d, worst))
                end
            end
        end)

        it("generation never reads the clock", function()
            for _, n in ipairs(Board.SIZES) do
                for _, d in ipairs({ "easy", "medium", "hard" }) do
                    local b = Board:new{ n = n, empty = true }
                    math.randomseed(n * 19)
                    withoutClock(function() b:generate(d) end)
                end
            end
        end)
    end)
end)
