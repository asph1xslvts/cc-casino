-- casino.lua  (OpenComputers / OpenOS)
-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP:
--   1. Run  convert_icons.py  on your PC to get icons.lua
--   2. Copy  casino.lua  and  icons.lua  to /home/  on your OC computer
--   3. Requires: Tier-2+ GPU + Screen  (Tier-3 recommended for best color)
--   4. Run:  casino
-- ─────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════
-- [1] OC LIBRARIES
-- ═══════════════════════════════════════════════════════════════
local component = require("component")
local event     = require("event")
local keyboard  = require("keyboard")
local shell     = require("shell")
local unicode   = require("unicode")

local gpu = component.gpu

-- Set resolution: up to 120x40, capped by GPU max
local MAX_W, MAX_H = gpu.maxResolution()
local W = math.min(120, MAX_W)
local H = math.min(40,  MAX_H)
gpu.setResolution(W, H)

-- Screen address used to filter touch events
local screenAddr = gpu.getScreen()

-- ═══════════════════════════════════════════════════════════════
-- [2] CONFIGURATION
-- ═══════════════════════════════════════════════════════════════
local CFG = {
    minBet    = 1,
    maxBet    = 10,
    startBal  = 1000,
    startPot  = 5000,
    startBank = 2500,
    saveFile  = shell.getWorkingDirectory() .. "/casino_save.dat",
}

local MULT = {
    diamond     = 50,
    nether_star = 30,
    emerald     = 20,
    ender_pearl = 15,
    gold_ingot  = 10,
    iron_ingot  = 5,
}

local SYMBOLS = {"diamond","nether_star","emerald","ender_pearl","gold_ingot","iron_ingot"}

-- ═══════════════════════════════════════════════════════════════
-- [3] LOAD ICONS
-- ═══════════════════════════════════════════════════════════════
local scriptDir = shell.getWorkingDirectory()
local iconsPath = scriptDir .. "/icons.lua"

local loader, err = loadfile(iconsPath)
if not loader then
    error("Cannot load icons.lua from " .. iconsPath .. "\nError: " .. tostring(err), 0)
end
local icons = loader()

local ICW = icons.CHAR_WIDTH
local ICH = icons.CHAR_HEIGHT

-- ═══════════════════════════════════════════════════════════════
-- [4] COLOR MAPPING: CC blit hex digit -> OC 24-bit RGB integer
-- ═══════════════════════════════════════════════════════════════
local BLIT_RGB = {
    ["0"]=0xF0F0F0, ["1"]=0xF2B233, ["2"]=0xE57FD8, ["3"]=0x99B2F2,
    ["4"]=0xDEDE6C, ["5"]=0x7FCC19, ["6"]=0xF2B2CC, ["7"]=0x4C4C4C,
    ["8"]=0x999999, ["9"]=0x4C99B2, ["a"]=0xB266E5, ["b"]=0x3366CC,
    ["c"]=0x7F664C, ["d"]=0x57A64E, ["e"]=0xCC4C4C, ["f"]=0x111111,
}

-- ═══════════════════════════════════════════════════════════════
-- [5] UI COLORS
-- ═══════════════════════════════════════════════════════════════
local C = {
    bg=0x111111, border=0x3366CC, title=0x4C99B2, header=0x4C99B2,
    text=0xF0F0F0, dim=0x999999, stat=0xDEDE6C, win=0x7FCC19,
    lose=0xCC4C4C, info=0x99B2F2, mult=0xDEDE6C, btnBet=0x3366CC,
    btnSpin=0x7FCC19, btnExit=0xCC4C4C, slotBord=0x3366CC,
    slotBg=0x111111, avatar=0x4C99B2, player=0xDEDE6C,
}

-- ═══════════════════════════════════════════════════════════════
-- [6] GAME STATE
-- ═══════════════════════════════════════════════════════════════
local state = {
    balance  = CFG.startBal,
    bet      = CFG.minBet,
    pot      = CFG.startPot,
    bank     = CFG.startBank,
    reels    = {"diamond", "emerald", "gold_ingot"},
    spinning = false,
    msg      = "",
    msgClr   = C.text,
}

-- ═══════════════════════════════════════════════════════════════
-- [7] PERSISTENCE
-- ═══════════════════════════════════════════════════════════════
local function saveGame()
    local f = io.open(CFG.saveFile, "w")
    if not f then return end
    f:write(state.balance.."\n"..state.bet.."\n"..state.pot.."\n"..state.bank.."\n")
    f:close()
end

local function loadGame()
    local f = io.open(CFG.saveFile, "r")
    if not f then return end
    state.balance = tonumber(f:read("*l")) or CFG.startBal
    state.bet     = tonumber(f:read("*l")) or CFG.minBet
    state.pot     = tonumber(f:read("*l")) or CFG.startPot
    state.bank    = tonumber(f:read("*l")) or CFG.startBank
    state.bet     = math.max(CFG.minBet, math.min(CFG.maxBet, state.bet))
    f:close()
end

-- ═══════════════════════════════════════════════════════════════
-- [8] DRAWING UTILITIES
-- ═══════════════════════════════════════════════════════════════
local function put(x, y, text, fg, bg)
    gpu.setForeground(fg or C.text)
    gpu.setBackground(bg or C.bg)
    gpu.set(x, y, text)
end

local function fill(x, y, w, h, bg)
    gpu.setBackground(bg or C.bg)
    gpu.fill(x, y, w, h, " ")
end

local function putCenter(y, text, fg, bg, x1, x2)
    x1 = x1 or 1; x2 = x2 or W
    local x = x1 + math.floor((x2-x1+1-unicode.len(text))/2)
    if x < x1 then x = x1 end
    put(x, y, text, fg, bg)
end

local function drawBox(x, y, w, h, fg, bg)
    put(x, y,     "+"..string.rep("-",w-2).."+", fg, bg)
    for dy=1,h-2 do put(x,y+dy,"|"..string.rep(" ",w-2).."|",fg,bg) end
    put(x, y+h-1, "+"..string.rep("-",w-2).."+", fg, bg)
end

-- Upper-half-block char: U+2580, UTF-8: E2 96 80
-- icons.lua stores this as byte 143 (CC convention)
local UPPER_BLOCK = "\226\150\128"

local function drawIcon(x, y, name)
    local icon = icons[name]
    if not icon then return end
    for row_i, row in ipairs(icon) do
        local chars_str, fg_str, bg_str = row[1], row[2], row[3]
        for col = 1, ICW do
            local ch = (chars_str:byte(col) == 143) and UPPER_BLOCK or " "
            gpu.setForeground(BLIT_RGB[fg_str:sub(col,col)] or C.bg)
            gpu.setBackground(BLIT_RGB[bg_str:sub(col,col)] or C.bg)
            gpu.set(x+col-1, y+row_i-1, ch)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- [9] LAYOUT
-- ═══════════════════════════════════════════════════════════════
local LW      = 24
local RX      = LW + 2
local RW      = W - LW - 1
local BOX_W   = ICW + 2
local BOX_H   = ICH + 2
local REELS_W = BOX_W*3 + 4
local REELS_X = LW+1 + math.floor((W-LW-1-REELS_W)/2)
local BTN_Y   = H - 2
local BET_Y   = H - 3
local REELS_Y = BET_Y - 1 - BOX_H

-- ═══════════════════════════════════════════════════════════════
-- [10] BUTTON SYSTEM
-- ═══════════════════════════════════════════════════════════════
local buttons = {}

local function regBtn(x1,y1,x2,y2,action)
    table.insert(buttons,{x1=x1,y1=y1,x2=x2,y2=y2,action=action})
end

local function calcBetBtns()
    local defs = {
        {"-10","bet:-10"},{"-5","bet:-5"},{"-1","bet:-1"},
        {"Bet "..state.bet,"spin"},
        {"+1","bet:1"},{"+5","bet:5"},{"+10","bet:10"},
    }
    local totalW = -1
    for _,d in ipairs(defs) do totalW = totalW + unicode.len(d[1]) + 3 end
    local cx = LW+1 + math.floor((W-LW-1-totalW)/2)
    local result = {}
    for _,d in ipairs(defs) do
        local lbl = "["..d[1].."]"
        local vl  = unicode.len(lbl)
        table.insert(result,{x=cx,y=BTN_Y,label=lbl,vlen=vl,action=d[2],isSpin=(d[2]=="spin")})
        cx = cx + vl + 1
    end
    return result
end

local function handleTouch(tx,ty)
    for _,b in ipairs(buttons) do
        if tx>=b.x1 and tx<=b.x2 and ty>=b.y1 and ty<=b.y2 then return b.action end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════
-- [11] UI DRAWING
-- ═══════════════════════════════════════════════════════════════
local function drawFrame()
    fill(1,1,W,H,C.bg)
    put(1,1,"+"..string.rep("-",W-2).."+",C.border,C.bg)
    for y=2,H-1 do put(1,y,"|",C.border,C.bg); put(W,y,"|",C.border,C.bg) end
    put(1,H,"+"..string.rep("-",W-2).."+",C.border,C.bg)
    for y=1,H do put(LW+1,y,"|",C.border,C.bg) end
    put(LW+1,1,"+",C.border,C.bg); put(LW+1,H,"+",C.border,C.bg)
end

local function drawLeftPanel()
    local x=2
    put(x,2,  "  General info:",    C.header,C.bg)
    put(x,4,  "Play at your own",   C.dim,   C.bg)
    put(x,5,  "risk. Items are",    C.dim,   C.bg)
    put(x,6,  "not returned.",      C.dim,   C.bg)
    put(x,8,  "Total coins:",       C.text,  C.bg)
    put(x,9,  "  "..state.pot.." c.",C.stat, C.bg)
    put(x,11, "Payout bank:",       C.text,  C.bg)
    put(x,12, "  "..state.bank.." c.",C.stat,C.bg)
    put(x,14, string.rep("-",LW-2), C.border,C.bg)
    put(x,15, "  __(^v^)__",        C.avatar,C.bg)
    put(x,17, "Player:",            C.text,  C.bg)
    local addr=""
    pcall(function() addr=tostring(component.computer.address()):sub(1,10) end)
    put(x,18, "  "..addr,           C.player,C.bg)
    put(x,20, "Balance:",           C.text,  C.bg)
    put(x,21, "  "..state.balance.." c.",C.stat,C.bg)
    fill(x,23,LW-2,1,C.bg)
    if state.spinning then
        put(x,23,"Spinning...",C.win,C.bg)
    elseif state.msg~="" then
        local m=state.msg
        if unicode.len(m)>LW-2 then m=unicode.sub(m,1,LW-2) end
        put(x,23,m,state.msgClr,C.bg)
    else
        put(x,23,"Ready.",C.dim,C.bg)
    end
    put(3,H-2,"[ Exit ]",C.btnExit,C.bg)
end

local function drawWinTable()
    putCenter(2,"* OpenCasino *",C.title,C.bg,LW+2,W-1)
    put(RX,4, "Win table:",              C.header,C.bg)
    put(RX,5, "Payout = bet x bonus",   C.text,  C.bg)
    put(RX,7, "2 same on edges  - x1",  C.info,  C.bg)
    put(RX,8, "2 same adjacent  - x2",  C.info,  C.bg)
    local rows={
        {"3x iron_ingot ", 5}, {"3x gold_ingot ", 10},
        {"3x ender_pearl", 15},{"3x emerald    ", 20},
        {"3x nether_star", 30},{"3x diamond    ", 50},
    }
    for i,r in ipairs(rows) do
        put(RX,9+i, r[1].." - Bonus x"..r[2],C.mult,C.bg)
    end
    put(RX,17,"Min bet: "..CFG.minBet.." c.",C.dim,C.bg)
    put(RX,18,"Max bet: "..CFG.maxBet.." c.",C.dim,C.bg)
end

local function drawReels()
    for i=1,3 do
        local bx=REELS_X+(i-1)*(BOX_W+2)
        drawBox(bx,REELS_Y,BOX_W,BOX_H,C.slotBord,C.bg)
        fill(bx+1,REELS_Y+1,ICW,ICH,C.slotBg)
        drawIcon(bx+1,REELS_Y+1,state.reels[i])
    end
end

local function drawBetButtons()
    fill(LW+2,BET_Y-1,W-LW-2,1,C.bg)
    putCenter(BET_Y-1,"Spinning for "..state.bet.." c.",C.text,C.bg,LW+2,W-1)
    local btns=calcBetBtns()
    buttons={}
    regBtn(3,H-2,10,H-2,"exit")
    fill(LW+2,BTN_Y,W-LW-2,1,C.bg)
    for _,b in ipairs(btns) do
        put(b.x,b.y,b.label,b.isSpin and C.btnSpin or C.btnBet,C.bg)
        regBtn(b.x,b.y,b.x+b.vlen-1,b.y,b.action)
    end
end

local function redraw()
    drawFrame(); drawLeftPanel(); drawWinTable(); drawReels(); drawBetButtons()
end

local function partialRedraw()
    drawLeftPanel(); drawReels(); drawBetButtons()
end

-- ═══════════════════════════════════════════════════════════════
-- [12] GAME LOGIC
-- ═══════════════════════════════════════════════════════════════
local function checkWin(r)
    local a,b,c=r[1],r[2],r[3]
    if a==b and b==c then
        local m=MULT[a] or 5
        return m,"3x "..a.."!  Bonus x"..m
    end
    if a==b or b==c then return 2,"Two adjacent!  x2" end
    if a==c          then return 1,"Two on edges!  x1" end
    return 0,"No luck..."
end

local function animateSpin(final)
    state.spinning=true
    local stops={12,16,20}
    for step=1,20 do
        for i=1,3 do
            state.reels[i]=(step<stops[i]) and SYMBOLS[math.random(#SYMBOLS)] or final[i]
        end
        drawReels(); drawLeftPanel()
        os.sleep(0.06)
    end
    state.reels=final; state.spinning=false
end

local function doSpin()
    if state.spinning then return end
    if state.balance<state.bet then
        state.msg="Not enough coins!"; state.msgClr=C.lose
        partialRedraw(); return
    end
    state.balance=state.balance-state.bet
    state.pot=state.pot+state.bet
    state.bank=state.bank+math.floor(state.bet*0.4)
    state.msg=""
    local final={}
    for i=1,3 do final[i]=SYMBOLS[math.random(#SYMBOLS)] end
    animateSpin(final)
    local mult,msg=checkWin(final)
    if mult>0 then
        local gain=state.bet*mult
        state.balance=state.balance+gain
        state.bank=math.max(0,state.bank-gain)
        state.msg=msg.."  +"..gain.." c.!"; state.msgClr=C.win
    else
        state.msg=msg; state.msgClr=C.lose
    end
    saveGame(); partialRedraw()
end

local function changeBet(delta)
    state.bet=math.max(CFG.minBet,math.min(CFG.maxBet,state.bet+delta))
end

-- ═══════════════════════════════════════════════════════════════
-- [13] MAIN LOOP
-- ═══════════════════════════════════════════════════════════════
local function main()
    math.randomseed(os.time())
    loadGame()
    gpu.setBackground(C.bg); gpu.fill(1,1,W,H," ")
    redraw()

    while true do
        local etype,p1,p2,p3=event.pull()

        if etype=="touch" and p1==screenAddr then
            local action=handleTouch(p2,p3)
            if action=="exit" then break
            elseif action=="spin" then doSpin()
            elseif action and action:sub(1,4)=="bet:" then
                changeBet(tonumber(action:sub(5)) or 0); drawBetButtons()
            end

        elseif etype=="key_down" then
            local code=p3
            if code==keyboard.keys.space or code==keyboard.keys.enter then doSpin()
            elseif code==keyboard.keys.left  then changeBet(-1); drawBetButtons()
            elseif code==keyboard.keys.right then changeBet(1);  drawBetButtons()
            elseif code==keyboard.keys.q     then break
            end

        elseif etype=="interrupted" then break
        end
    end

    saveGame()
    gpu.setBackground(C.bg); gpu.setForeground(C.text)
    gpu.fill(1,1,W,H," "); gpu.set(1,1,"Casino closed. Goodbye!")
end

main()
