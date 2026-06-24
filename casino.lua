-- casino.lua
-- OpenCasino for CC:Tweaked
-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP:
--   1. Run  convert_icons.py  on your PC to get icons.lua
--   2. Copy  casino.lua  and  icons.lua  to the same folder on your CC computer
--   3. Attach an Advanced Monitor to any side of the computer
--      Recommended: 3 wide × 2 tall Advanced Monitors -> run at text scale 0.5
--   4. Run:  casino
-- ─────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════
-- [1] CONFIGURATION
-- ═══════════════════════════════════════════════════════════════
local CFG = {
    minBet      = 1,
    maxBet      = 10,
    startBal    = 1000,
    startPot    = 5000,   -- displayed "total coins" counter
    startBank   = 2500,   -- payout bank
    saveFile    = "casino_save.dat",
    textScale   = 0.5,    -- 0.5 = maximum resolution (requires Advanced Monitor)
}

-- Win multipliers (3 of a kind)
local MULT = {
    diamond     = 50,
    nether_star = 30,
    emerald     = 20,
    ender_pearl = 15,
    gold_ingot  = 10,
    iron_ingot  = 5,
}

-- Russian display names
local ITEM_RU = {
    diamond     = "Алмаз",
    nether_star = "Звезда",
    emerald     = "Изумруд",
    ender_pearl = "Жемчуг",
    gold_ingot  = "Золото",
    iron_ingot  = "Железо",
}

-- Spin reel symbol pool (ordered by value)
local SYMBOLS = { "diamond","nether_star","emerald","ender_pearl","gold_ingot","iron_ingot" }

-- ═══════════════════════════════════════════════════════════════
-- [2] LOAD ICONS
-- ═══════════════════════════════════════════════════════════════
local scriptDir = fs.getDir(shell.getRunningProgram())

local ok, icons = pcall(dofile, fs.combine(scriptDir, "icons.lua"))
if not ok then
    error("Could not load icons.lua - run convert_icons.py first!\n" .. tostring(icons), 0)
end

local ICW = icons.CHAR_WIDTH   -- 9  chars wide
local ICH = icons.CHAR_HEIGHT  -- 8  chars tall

-- ═══════════════════════════════════════════════════════════════
-- [3] MONITOR SETUP
-- ═══════════════════════════════════════════════════════════════
local monSide = nil
local mon     = nil

for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
        mon     = peripheral.wrap(name)
        monSide = name
        break
    end
end

if not mon then
    error("No monitor found!  Attach an Advanced Monitor to the computer.", 0)
end

mon.setTextScale(CFG.textScale)
local W, H = mon.getSize()

-- ═══════════════════════════════════════════════════════════════
-- [4] COLOR CONSTANTS
-- ═══════════════════════════════════════════════════════════════
local C = {
    bg        = colors.black,
    border    = colors.blue,
    title     = colors.cyan,
    header    = colors.cyan,
    text      = colors.white,
    dim       = colors.lightGray,
    stat      = colors.yellow,
    win       = colors.lime,
    lose      = colors.red,
    info      = colors.lightBlue,
    mult      = colors.yellow,
    btnBet    = colors.blue,
    btnSpin   = colors.green,
    btnExit   = colors.red,
    slotBord  = colors.blue,
    slotBg    = colors.black,
    avatar    = colors.cyan,
    player    = colors.yellow,
}

-- blit color: convert colors.* constant -> single hex-digit string
-- Used when we want to draw with setTextColor + write, not blit
-- (for the slot borders we use write, not blit, so we just use setTextColor)

-- ═══════════════════════════════════════════════════════════════
-- [5] GAME STATE
-- ═══════════════════════════════════════════════════════════════
local state = {
    balance  = CFG.startBal,
    bet      = CFG.minBet,
    pot      = CFG.startPot,
    bank     = CFG.startBank,
    reels    = { "diamond", "emerald", "gold_ingot" },
    spinning = false,
    msg      = "",
    msgClr   = colors.white,
}

-- ═══════════════════════════════════════════════════════════════
-- [6] PERSISTENCE
-- ═══════════════════════════════════════════════════════════════
local function saveGame()
    local path = fs.combine(scriptDir, CFG.saveFile)
    local f = fs.open(path, "w")
    if not f then return end
    f.writeLine(tostring(state.balance))
    f.writeLine(tostring(state.bet))
    f.writeLine(tostring(state.pot))
    f.writeLine(tostring(state.bank))
    f.close()
end

local function loadGame()
    local path = fs.combine(scriptDir, CFG.saveFile)
    if not fs.exists(path) then return end
    local f = fs.open(path, "r")
    if not f then return end
    state.balance = tonumber(f.readLine()) or CFG.startBal
    state.bet     = tonumber(f.readLine()) or CFG.minBet
    state.pot     = tonumber(f.readLine()) or CFG.startPot
    state.bank    = tonumber(f.readLine()) or CFG.startBank
    state.bet     = math.max(CFG.minBet, math.min(CFG.maxBet, state.bet))
    f.close()
end

-- ═══════════════════════════════════════════════════════════════
-- [7] DRAWING UTILITIES
-- ═══════════════════════════════════════════════════════════════
local function clr(fg, bg)
    mon.setTextColor(fg or C.text)
    mon.setBackgroundColor(bg or C.bg)
end

local function put(x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    clr(fg, bg)
    mon.write(text)
end

local function fill(x, y, w, h, bg)
    clr(bg or C.bg, bg or C.bg)
    local line = string.rep(" ", w)
    for dy = 0, h - 1 do
        mon.setCursorPos(x, y + dy)
        mon.write(line)
    end
end

local function center(y, text, fg, bg, x1, x2)
    x1 = x1 or 1
    x2 = x2 or W
    local x = x1 + math.floor((x2 - x1 + 1 - #text) / 2)
    if x < x1 then x = x1 end
    put(x, y, text, fg, bg)
end

-- Draw a box with + - | corners/edges
local function box(x, y, w, h, fg, bg)
    fg = fg or C.border
    bg = bg or C.bg
    local top    = "+" .. string.rep("-", w - 2) .. "+"
    local middle = "|" .. string.rep(" ", w - 2) .. "|"
    local bot    = "+" .. string.rep("-", w - 2) .. "+"
    put(x, y,         top,    fg, bg)
    for dy = 1, h - 2 do
        put(x, y + dy, middle, fg, bg)
    end
    put(x, y + h - 1, bot,    fg, bg)
end

-- Draw an icon at terminal position (x, y) using blit
local function drawIcon(x, y, name)
    local icon = icons[name]
    if not icon then return end
    for i, row in ipairs(icon) do
        mon.setCursorPos(x, y + i - 1)
        mon.blit(row[1], row[2], row[3])
    end
end

-- ═══════════════════════════════════════════════════════════════
-- [8] LAYOUT  (all positions derived from W, H, ICW, ICH)
-- ═══════════════════════════════════════════════════════════════
local LW  = 24                  -- left panel width (including border char)
local RX  = LW + 2              -- right panel interior start x
local RW  = W - LW - 1         -- right panel interior width

local BOX_W = ICW + 2           -- slot box width  (icon + left/right border)
local BOX_H = ICH + 2           -- slot box height (icon + top/bot border)
local GAP   = 2                 -- gap between slot boxes

-- Total width of the 3 slot boxes + gaps
local REELS_W = BOX_W * 3 + GAP * 2
-- Center the reels horizontally within the right panel
local REELS_X = LW + 1 + math.floor((W - LW - 1 - REELS_W) / 2)

-- Position reels near bottom, leaving room for buttons
local BTN_Y   = H - 2
local BET_Y   = H - 3
local REELS_Y = BET_Y - 1 - BOX_H

-- ═══════════════════════════════════════════════════════════════
-- [9] BUTTON SYSTEM
-- ═══════════════════════════════════════════════════════════════
-- Buttons are recalculated every redraw so positions stay accurate
-- as bet value text length changes.

local buttons = {}

local function regBtn(x1, y1, x2, y2, action)
    table.insert(buttons, { x1=x1, y1=y1, x2=x2, y2=y2, action=action })
end

-- Returns ordered list of bet button definitions
local function betBtnDefs()
    return {
        { "-10",              "bet:-10" },
        { "-5",               "bet:-5"  },
        { "-1",               "bet:-1"  },
        { "Ставка "..state.bet, "spin"  },
        { "+1",               "bet:1"   },
        { "+5",               "bet:5"   },
        { "+10",              "bet:10"  },
    }
end

-- Returns list of {x, y, label, action, isSpin} for each bet button
local function calcBetBtns()
    local defs = betBtnDefs()
    local totalW = -1   -- -1: compensate for trailing space
    for _, d in ipairs(defs) do
        totalW = totalW + #d[1] + 3  -- "[" + label + "]" + " "
    end
    local cx = LW + 1 + math.floor((W - LW - 1 - totalW) / 2)
    local result = {}
    for _, d in ipairs(defs) do
        local lbl = "[" .. d[1] .. "]"
        table.insert(result, {
            x      = cx,
            y      = BTN_Y,
            label  = lbl,
            action = d[2],
            isSpin = (d[2] == "spin"),
        })
        cx = cx + #lbl + 1
    end
    return result
end

local function handleTouch(tx, ty)
    for _, b in ipairs(buttons) do
        if tx >= b.x1 and tx <= b.x2 and ty >= b.y1 and ty <= b.y2 then
            return b.action
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════
-- [10] UI DRAWING
-- ═══════════════════════════════════════════════════════════════
local function drawFrame()
    fill(1, 1, W, H, C.bg)

    -- Outer border
    clr(C.border, C.bg)
    put(1, 1, "+" .. string.rep("-", W - 2) .. "+", C.border, C.bg)
    for y = 2, H - 1 do
        put(1, y, "|", C.border, C.bg)
        put(W, y, "|", C.border, C.bg)
    end
    put(1, H, "+" .. string.rep("-", W - 2) .. "+", C.border, C.bg)

    -- Vertical divider
    for y = 1, H do
        put(LW + 1, y, "|", C.border, C.bg)
    end
    put(LW + 1, 1, "+", C.border, C.bg)
    put(LW + 1, H, "+", C.border, C.bg)
end

local function drawLeftPanel()
    local x = 2
    put(x, 2,  "  Общая инфо:",       C.header, C.bg)
    put(x, 4,  "Вы играете на свой",  C.dim, C.bg)
    put(x, 5,  "страх и риск.",       C.dim, C.bg)
    put(x, 6,  "Мы не возвращаем",    C.dim, C.bg)
    put(x, 7,  "предметы.",           C.dim, C.bg)

    -- Stats
    put(x, 9,  "Всего монет:",        C.text, C.bg)
    put(x, 10, "  "..state.pot.." м.",C.stat, C.bg)
    put(x, 12, "Банк выплат:",        C.text, C.bg)
    put(x, 13, "  "..state.bank.." м.",C.stat, C.bg)

    -- Divider
    put(x, 15, string.rep("-", LW - 2), C.border, C.bg)

    -- Avatar + player
    put(x, 16, "  __(^v^)__",         C.avatar, C.bg)
    put(x, 18, "Игрок:",              C.text,   C.bg)
    local pname = os.getComputerLabel() or ("PC #"..os.getComputerID())
    -- Trim name to fit
    if #pname > LW - 5 then pname = pname:sub(1, LW - 5) end
    put(x, 19, "  "..pname,           C.player, C.bg)

    put(x, 21, "Ваш баланс:",         C.text, C.bg)
    put(x, 22, "  "..state.balance.." м.", C.stat, C.bg)

    -- Status
    fill(x, 24, LW - 2, 1, C.bg)
    if state.spinning then
        put(x, 24, "Идёт игра...", C.win, C.bg)
    elseif state.msg ~= "" then
        local m = state.msg
        if #m > LW - 2 then m = m:sub(1, LW - 2) end
        put(x, 24, m, state.msgClr, C.bg)
    else
        put(x, 24, "Готово.", C.dim, C.bg)
    end

    -- Exit button
    put(3, H - 2, "[ Выход ]", C.btnExit, C.bg)
end

local function drawWinTable()
    center(2, "* OpenCasino *", C.title, C.bg, LW + 2, W - 1)

    put(RX, 4, "Инфо о выигрышах:",            C.header, C.bg)
    put(RX, 5, "Выигрыш = ставка * бонус",     C.text,   C.bg)
    put(RX, 7, "2 одинаковых по краям  - x1", C.info,   C.bg)
    put(RX, 8, "2 одинаковых рядом     - x2", C.info,   C.bg)

    local rows = {
        { "Три железа  ", "iron_ingot",   5  },
        { "Три золота  ", "gold_ingot",   10 },
        { "Три жемчуга ", "ender_pearl",  15 },
        { "Три изумруда", "emerald",      20 },
        { "Три звезды  ", "nether_star",  30 },
        { "Три алмаза  ", "diamond",      50 },
    }
    for i, r in ipairs(rows) do
        put(RX, 9 + i, r[1] .. " - Бонус x" .. r[3], C.mult, C.bg)
    end

    put(RX, 17, "Мин. ставка: "..CFG.minBet.." м.", C.dim, C.bg)
    put(RX, 18, "Макс. ставка: "..CFG.maxBet.." м.", C.dim, C.bg)
end

local function drawReels()
    for i = 1, 3 do
        local bx = REELS_X + (i - 1) * (BOX_W + GAP)
        -- Draw box border (blue on black)
        box(bx, REELS_Y, BOX_W, BOX_H, C.slotBord, C.bg)
        -- Fill interior with black then draw icon
        fill(bx + 1, REELS_Y + 1, ICW, ICH, C.slotBg)
        drawIcon(bx + 1, REELS_Y + 1, state.reels[i])
    end
end

local function drawBetButtons()
    -- Bet info line
    fill(LW + 2, BET_Y - 1, W - LW - 2, 1, C.bg)
    center(BET_Y - 1, "Крутим на "..state.bet.." м.", C.text, C.bg, LW + 2, W - 1)

    -- Buttons
    local btns = calcBetBtns()
    buttons = {}   -- clear and re-register

    -- Re-register exit button
    regBtn(3, H - 2, 11, H - 2, "exit")

    fill(LW + 2, BTN_Y, W - LW - 2, 1, C.bg)
    for _, b in ipairs(btns) do
        local fg = b.isSpin and C.btnSpin or C.btnBet
        put(b.x, b.y, b.label, fg, C.bg)
        regBtn(b.x, b.y, b.x + #b.label - 1, b.y, b.action)
    end
end

local function redraw()
    drawFrame()
    drawLeftPanel()
    drawWinTable()
    drawReels()
    drawBetButtons()
end

-- Redraw only the parts that change during gameplay
local function partialRedraw()
    drawLeftPanel()
    drawReels()
    drawBetButtons()
end

-- ═══════════════════════════════════════════════════════════════
-- [11] GAME LOGIC
-- ═══════════════════════════════════════════════════════════════
local function checkWin(r)
    local a, b, c = r[1], r[2], r[3]
    if a == b and b == c then
        local m = MULT[a] or 5
        return m, "Три "..ITEM_RU[a].."! Бонус x"..m
    end
    if a == b or b == c then
        return 2, "Два рядом!  Бонус x2"
    end
    if a == c then
        return 1, "Два по краям!  Бонус x1"
    end
    return 0, "Не повезло..."
end

local function animateSpin(final)
    state.spinning = true
    -- Each reel stops after a different number of steps
    local stops = { 12, 16, 20 }

    for step = 1, 20 do
        for i = 1, 3 do
            if step < stops[i] then
                state.reels[i] = SYMBOLS[math.random(#SYMBOLS)]
            else
                state.reels[i] = final[i]
            end
        end
        drawReels()
        drawLeftPanel()
        os.sleep(0.06)
    end

    state.reels   = final
    state.spinning = false
end

local function doSpin()
    if state.spinning then return end

    if state.balance < state.bet then
        state.msg    = "Мало монет!"
        state.msgClr = C.lose
        partialRedraw()
        return
    end

    state.balance = state.balance - state.bet
    state.pot     = state.pot  + state.bet
    state.bank    = state.bank + math.floor(state.bet * 0.4)
    state.msg     = ""

    -- Determine result
    local final = {}
    for i = 1, 3 do
        final[i] = SYMBOLS[math.random(#SYMBOLS)]
    end

    animateSpin(final)

    local mult, msg = checkWin(final)
    if mult > 0 then
        local gain = state.bet * mult
        state.balance = state.balance + gain
        state.bank    = math.max(0, state.bank - gain)
        state.msg     = msg .. "  +"..gain.." м.!"
        state.msgClr  = C.win
    else
        state.msg     = msg
        state.msgClr  = C.lose
    end

    saveGame()
    partialRedraw()
end

local function changeBet(delta)
    state.bet = math.max(CFG.minBet, math.min(CFG.maxBet, state.bet + delta))
end

-- ═══════════════════════════════════════════════════════════════
-- [12] MAIN LOOP
-- ═══════════════════════════════════════════════════════════════
local function main()
    math.randomseed(os.time() + os.getComputerID())
    loadGame()

    mon.clear()
    mon.setCursorBlink(false)
    redraw()

    while true do
        local ev = { os.pullEvent() }
        local et = ev[1]

        if et == "monitor_touch" and ev[2] == monSide then
            local action = handleTouch(ev[3], ev[4])
            if action == "exit" then
                break
            elseif action == "spin" then
                doSpin()
                -- drawBetButtons called inside doSpin -> partialRedraw
            elseif action and action:sub(1, 4) == "bet:" then
                changeBet(tonumber(action:sub(5)) or 0)
                drawBetButtons()
            end

        elseif et == "key" then
            local k = ev[2]
            if k == keys.space or k == keys.enter then
                doSpin()
            elseif k == keys.left  or k == keys.a then changeBet(-1); drawBetButtons()
            elseif k == keys.right or k == keys.d then changeBet(1);  drawBetButtons()
            elseif k == keys.q or k == keys.backspace then break
            end

        elseif et == "peripheral_detach" and ev[2] == monSide then
            -- Monitor removed; exit gracefully
            break

        elseif et == "term_resize" then
            W, H = mon.getSize()
            redraw()
        end
    end

    saveGame()
    mon.clear()
    mon.setCursorPos(1, 1)
    mon.setTextColor(colors.white)
    mon.setBackgroundColor(colors.black)
    mon.write("Casino closed. Goodbye!")
end

main()
