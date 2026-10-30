local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase        = require("screen_base")
local MenuHelper        = require("menu_helper")
local TentsBoard        = lrequire("board")
local TentsBoardWidget  = lrequire("board_widget")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- TentsScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Tents and Trees — Rules

Place tents in the grid so every tree has exactly one tent.

Rules:
• Each tree must be paired with exactly one tent in an orthogonally adjacent cell (not diagonal).
• Each tent is paired with exactly one tree.
• No two tents may be adjacent — even diagonally.
• The number of tents in each row and column must match the clue for that line.

Empty cells without trees or tents are grass.

Tap a cell to cycle it: tent, then grass, then empty again. Long-press a cell to mark it as grass directly.
]])

local GAME_RULES_FR = [[
Tentes et Arbres — Règles

Placez des tentes dans la grille de sorte que chaque arbre soit associé à exactement une tente.

Règles :
• Chaque arbre doit être associé à exactement une tente dans une case orthogonalement adjacente (pas en diagonale).
• Chaque tente est associée à exactement un arbre.
• Deux tentes ne peuvent pas être adjacentes — même en diagonale.
• Le nombre de tentes dans chaque ligne et colonne doit correspondre à l'indice de cette ligne ou colonne.

Les cases vides sans arbre ni tente sont de l'herbe.

Appuyez sur une case pour la faire défiler : tente, puis herbe, puis vide. Un appui long marque directement la case comme herbe.
]]

local TentsScreen = ScreenBase:extend{}

function TentsScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n",     TentsBoard.DEFAULT_N)
    local diff  = self.plugin:getSetting("difficulty", "medium")
    self.board  = TentsBoard:new{ n = n, difficulty = diff }
    if not self.board:load(state) then
        -- fresh puzzle
    end
    self.mode = "tent"   -- or "grass"
    ScreenBase.init(self)
end

function TentsScreen:serializeState()
    return self.board:serialize()
end

function TentsScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Tents and Trees"), function()
        return {
            { text = _("New game"),     callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = self:_sizeLabel(), callback = function() self:openSizeMenu() end },
            { text = T(_("Difficulty: %1"), self:_diffLabel()), callback = function() self:openDiffMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Undo"),   callback = function() self:onUndo() end },
            { text = _("Check"),  callback = function() self:onCheck() end },
            { text = _("Hint"),   callback = function() self:onHint() end },
            { text = _("Reveal"), callback = function() self:onReveal() end },
        }),
    }

    -- The widget draws its own thick border around the grid (the clues sit
    -- outside it), so the frame stays borderless: one visible edge, not two.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * frame_pad
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local board_max = math.max(math.min(budget_w, budget_h) - frame_extra, 80)
    self.board_widget = TentsBoardWidget:new{
        board      = self.board,
        max_width  = board_max,
        max_height = board_max,
        cellTapCallback  = function(r, c) self:onCellTap(r, c) end,
        cellHoldCallback = function(r, c) self:onCellHold(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function TentsScreen:onCellTap(r, c)
    self.board:cycleCell(r, c)
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function TentsScreen:onCellHold(r, c)
    self.board:setMark(r, c, TentsBoard.MARK_GRASS)
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function TentsScreen:onUndo()
    self.board:undoMove()
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function TentsScreen:onCheck()
    self.board:check()
    self.board_widget:refresh()
    self:updateStatus()
end

function TentsScreen:onReveal()
    self.board:reveal()
    self.board_widget:refresh()
    self:updateStatus(_("Solution revealed."))
    self.plugin:saveState(self.board:serialize())
end

function TentsScreen:onNewGame()
    local n    = self.plugin:getSetting("grid_n",     TentsBoard.DEFAULT_N)
    local diff = self.plugin:getSetting("difficulty", "medium")
    self.board = TentsBoard:new{ n = n, difficulty = diff }
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function TentsScreen:openSizeMenu()
    local items = {}
    for _, n in ipairs(TentsBoard.SIZES) do
        items[#items + 1] = { id = n, text = string.format("%d\xC3\x97%d", n, n) }
    end
    MenuHelper.openPickerMenu{
        title      = _("Select size"),
        items      = items,
        current_id = self.plugin:getSetting("grid_n", TentsBoard.DEFAULT_N),
        parent     = self,
        on_select  = function(n)
            self.plugin:saveSetting("grid_n", n)
            if self.size_btn then
                self.size_btn:setText(self:_sizeLabel(), self.size_btn.width)
            end
            self:onNewGame()
        end,
    }
end

function TentsScreen:openDiffMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        parent    = self,
        on_select = function(diff)
            self.plugin:saveSetting("difficulty", diff)
            if self.diff_btn then
                self.diff_btn:setText(T(_("Difficulty: %1"), self:_diffLabel()), self.diff_btn.width)
            end
            self:onNewGame()
        end,
    }
end

function TentsScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.won then
        status = _("Puzzle solved!")
    else
        local tents = 0
        local n = self.board.n
        for r = 1, n do
            for c = 1, n do
                if self.board.marks[r][c] == TentsBoard.MARK_TENT then
                    tents = tents + 1
                end
            end
        end
        local total = 0
        for _, v in ipairs(self.board.row_clues) do total = total + v end
        status = self:joinStatus(
            T("%1×%1", n),
            self:_diffLabel(),
            T(_("Tents: %1/%2"), tents, total))
    end
    ScreenBase.updateStatus(self, status)
    -- Every move, hint, undo and reveal ends here, so the bar follows the board.
    self:refreshActionBar()
end

-- Reveal marks the board won, so it ends the round too.
function TentsScreen:isRoundOver()
    return self.board.won
end

function TentsScreen:_sizeLabel()
    local n = self.plugin:getSetting("grid_n", TentsBoard.DEFAULT_N)
    return T(_("Size: %1"), string.format("%d\xC3\x97%d", n, n))
end

function TentsScreen:_diffLabel()
    local diff = self.plugin:getSetting("difficulty", "medium")
    local labels = { easy = _("Easy"), medium = _("Medium"), hard = _("Hard") }
    return labels[diff] or diff
end

return TentsScreen
