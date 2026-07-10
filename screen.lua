local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
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
    local sw           = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    local btn_width = is_landscape
        and math.max(math.floor(sw * 0.35), 100)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("New"),  callback = function() self:onNewGame() end },
            { id = "size_btn",  text = self:_sizeLabel(),
              callback = function() self:openSizeMenu() end },
            { id = "diff_btn",  text = self:_diffLabel(),
              callback = function() self:openDiffMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.size_btn = top_buttons:getButtonById("size_btn")
    self.diff_btn = top_buttons:getButtonById("diff_btn")

    local margin      = Size.margin.default
    local padding     = Size.padding.large
    local frame_extra = (padding + margin) * 2
    local board_max
    if is_landscape then
        board_max = math.min(sw - math.floor(sw * 0.4) - frame_extra, sh - frame_extra)
    else
        board_max = math.min(sw - frame_extra, sh - 160 - frame_extra)
    end
    board_max = math.max(board_max, 80)

    self.board_widget = TentsBoardWidget:new{
        board      = self.board,
        max_width  = board_max,
        max_height = board_max,
        cellTapCallback  = function(r, c) self:onCellTap(r, c) end,
        cellHoldCallback = function(r, c) self:onCellHold(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = padding,
        margin  = margin,
        self.board_widget,
    }

    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("Undo"),   callback = function() self:onUndo() end },
            { text = _("Check"),  callback = function() self:onCheck() end },
            { text = _("Reveal"), callback = function() self:onReveal() end },
        }},
    }

    if is_landscape then
        local panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            panel,
        }
    else
        local content = VerticalGroup:new{
            align = "center",
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(top_buttons, content, bottom_buttons)
    end
    self[1] = self.layout
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
        title      = _("Grid size"),
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
                self.diff_btn:setText(self:_diffLabel(), self.diff_btn.width)
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
        status = T(_("Tents: %1/%2  Tap=cycle  Long=grass"), tents, total)
    end
    ScreenBase.updateStatus(self, status)
end

function TentsScreen:_sizeLabel()
    local n = self.plugin:getSetting("grid_n", TentsBoard.DEFAULT_N)
    return string.format("%d\xC3\x97%d", n, n)
end

function TentsScreen:_diffLabel()
    local diff = self.plugin:getSetting("difficulty", "medium")
    local labels = { easy = _("Easy"), medium = _("Medium"), hard = _("Hard") }
    return labels[diff] or diff
end

return TentsScreen
