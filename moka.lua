-- MOKA by yabastar#0000

-- PrimeUI by JackMacWindows
-- Public domain/CC0

local expect = require "cc.expect".expect

-- Initialization code
local PrimeUI = {}
do
    local coros = {}
    local restoreCursor

    --- Adds a task to run in the main loop.
    ---@param func function The function to run, usually an `os.pullEvent` loop
    function PrimeUI.addTask(func)
        expect(1, func, "function")
        local t = {coro = coroutine.create(func)}
        coros[#coros+1] = t
        _, t.filter = coroutine.resume(t.coro)
    end

    --- Sends the provided arguments to the run loop, where they will be returned.
    ---@param ... any The parameters to send
    function PrimeUI.resolve(...)
        coroutine.yield(coros, ...)
    end

    --- Clears the screen and resets all components. Do not use any previously
    --- created components after calling this function.
    function PrimeUI.clear()
        -- Reset the screen.
        term.setCursorPos(1, 1)
        term.setCursorBlink(false)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        -- Reset the task list and cursor restore function.
        coros = {}
        restoreCursor = nil
    end

    --- Sets or clears the window that holds where the cursor should be.
    ---@param win window|nil The window to set as the active window
    function PrimeUI.setCursorWindow(win)
        expect(1, win, "table", "nil")
        restoreCursor = win and win.restoreCursor
    end

    --- Gets the absolute position of a coordinate relative to a window.
    ---@param win window The window to check
    ---@param x number The relative X position of the point
    ---@param y number The relative Y position of the point
    ---@return number x The absolute X position of the window
    ---@return number y The absolute Y position of the window
    function PrimeUI.getWindowPos(win, x, y)
        if win == term then return x, y end
        while win ~= term.native() and win ~= term.current() do
            if not win.getPosition then return x, y end
            local wx, wy = win.getPosition()
            x, y = x + wx - 1, y + wy - 1
            _, win = debug.getupvalue(select(2, debug.getupvalue(win.isColor, 1)), 1) -- gets the parent window through an upvalue
        end
        return x, y
    end

    --- Runs the main loop, returning information on an action.
    ---@return any ... The result of the coroutine that exited
    function PrimeUI.run()
        while true do
            -- Restore the cursor and wait for the next event.
            if restoreCursor then restoreCursor() end
            local ev = table.pack(os.pullEvent())
            -- Run all coroutines.
            for _, v in ipairs(coros) do
                if v.filter == nil or v.filter == ev[1] then
                    -- Resume the coroutine, passing the current event.
                    local res = table.pack(coroutine.resume(v.coro, table.unpack(ev, 1, ev.n)))
                    -- If the call failed, bail out. Coroutines should never exit.
                    if not res[1] then error(res[2], 2) end
                    -- If the coroutine resolved, return its values.
                    if res[2] == coros then return table.unpack(res, 3, res.n) end
                    -- Set the next event filter.
                    v.filter = res[2]
                end
            end
        end
    end
end

function PrimeUI.label(win, x, y, text, fgColor, bgColor)
    expect(1, win, "table")
    expect(2, x, "number")
    expect(3, y, "number")
    expect(4, text, "string")
    fgColor = expect(5, fgColor, "number", "nil") or colors.white
    bgColor = expect(6, bgColor, "number", "nil") or colors.black
    win.setCursorPos(x, y)
    win.setTextColor(fgColor)
    win.setBackgroundColor(bgColor)
    win.write(text)
end

function PrimeUI.horizontalLine(win, x, y, width, fgColor, bgColor)
    expect(1, win, "table")
    expect(2, x, "number")
    expect(3, y, "number")
    expect(4, width, "number")
    fgColor = expect(5, fgColor, "number", "nil") or colors.white
    bgColor = expect(6, bgColor, "number", "nil") or colors.black
    -- Use drawing characters to draw a thin line.
    win.setCursorPos(x, y)
    win.setTextColor(fgColor)
    win.setBackgroundColor(bgColor)
    win.write(("\x8C"):rep(width))
end

function PrimeUI.borderBox(win, x, y, width, height, fgColor, bgColor)
    expect(1, win, "table")
    expect(2, x, "number")
    expect(3, y, "number")
    expect(4, width, "number")
    expect(5, height, "number")
    fgColor = expect(6, fgColor, "number", "nil") or colors.white
    bgColor = expect(7, bgColor, "number", "nil") or colors.black
    -- Draw the top-left corner & top border.
    win.setBackgroundColor(bgColor)
    win.setTextColor(fgColor)
    win.setCursorPos(x - 1, y - 1)
    win.write("\x9C" .. ("\x8C"):rep(width))
    -- Draw the top-right corner.
    win.setBackgroundColor(fgColor)
    win.setTextColor(bgColor)
    win.write("\x93")
    -- Draw the right border.
    for i = 1, height do
        win.setCursorPos(win.getCursorPos() - 1, y + i - 1)
        win.write("\x95")
    end
    -- Draw the left border.
    win.setBackgroundColor(bgColor)
    win.setTextColor(fgColor)
    for i = 1, height do
        win.setCursorPos(x - 1, y + i - 1)
        win.write("\x95")
    end
    -- Draw the bottom border and corners.
    win.setCursorPos(x - 1, y + height)
    win.write("\x8D" .. ("\x8C"):rep(width) .. "\x8E")
end

function PrimeUI.inputBox(win, x, y, width, action, fgColor, bgColor, replacement, history, completion, default)
    expect(1, win, "table")
    expect(2, x, "number")
    expect(3, y, "number")
    expect(4, width, "number")
    expect(5, action, "function", "string")
    fgColor = expect(6, fgColor, "number", "nil") or colors.white
    bgColor = expect(7, bgColor, "number", "nil") or colors.black
    expect(8, replacement, "string", "nil")
    expect(9, history, "table", "nil")
    expect(10, completion, "function", "nil")
    expect(11, default, "string", "nil")
    -- Create a window to draw the input in.
    local box = window.create(win, x, y, width, 1)
    box.setTextColor(fgColor)
    box.setBackgroundColor(bgColor)
    box.clear()
    -- Call read() in a new coroutine.
    PrimeUI.addTask(function()
        -- We need a child coroutine to be able to redirect back to the window.
        local coro = coroutine.create(read)
        -- Run the function for the first time, redirecting to the window.
        local old = term.redirect(box)
        local ok, res = coroutine.resume(coro, replacement, history, completion, default)
        term.redirect(old)
        -- Run the coroutine until it finishes.
        while coroutine.status(coro) ~= "dead" do
            -- Get the next event.
            local ev = table.pack(os.pullEvent())
            -- Redirect and resume.
            old = term.redirect(box)
            ok, res = coroutine.resume(coro, table.unpack(ev, 1, ev.n))
            term.redirect(old)
            -- Pass any errors along.
            if not ok then error(res) end
        end
        -- Send the result to the receiver.
        if type(action) == "string" then PrimeUI.resolve("inputBox", action, res)
        else action(res) end
        -- Spin forever, because tasks cannot exit.
        while true do os.pullEvent() end
    end)
end

local hostdata = "SERVER"
local tickSpeed = 10
local serverName = "server"..tostring(os.getComputerID())
local mokaFormat = "{3}"
local reboundnum = "disable"

if fs.exists(".moka") == false then
    if fs.exists("tmp") == true then
        shell.run("delete","tmp")
    end
    shell.run("wget","https://pastebin.com/raw/3LfWxRWh","tmp")
    local bigfont = require("tmp")
    term.clear()
    term.setCursorPos(1,1)
    bigfont.bigPrint("Welcome")
    shell.run("delete","tmp")
    print("...to MOKA 0.1-dev.22\n\n\nPress any key to continue...")
    os.pullEvent("key")
    term.clear()
    term.setCursorPos(1,1)
    
    PrimeUI.clear()
    PrimeUI.label(term.current(), 3, 2, "Host for protocol... (edit in .moka)")
    PrimeUI.horizontalLine(term.current(), 3, 3, #("Host for protocol... (edit in .moka)") + 2)
    PrimeUI.borderBox(term.current(), 4, 7, 40, 1)
    PrimeUI.inputBox(term.current(), 4, 7, 40, "result")
    local _, _, text = PrimeUI.run()
    hostdata = text
    local mokafile = fs.open(".moka", "w")
    mokafile.write("return {[1]=\""..text.."\"")
    
    PrimeUI.clear()
    PrimeUI.label(term.current(), 3, 2, "tickSpeed... (reccomended == 10)")
    PrimeUI.horizontalLine(term.current(), 3, 3, #("tickSpeed... (reccomended == 10)") + 2)
    PrimeUI.borderBox(term.current(), 4, 7, 40, 1)
    PrimeUI.inputBox(term.current(), 4, 7, 40, "result")
    local _, _, text = PrimeUI.run()
    tickSpeed = tonumber(text)
    mokafile.write(",[2]="..text)
    
    PrimeUI.clear()
    PrimeUI.label(term.current(), 3, 2, "serverName... (press enter for default)")
    PrimeUI.horizontalLine(term.current(), 3, 3, #("serverName... (press enter for default)") + 2)
    PrimeUI.borderBox(term.current(), 4, 7, 40, 1)
    PrimeUI.inputBox(term.current(), 4, 7, 40, "result")
    local _, _, text = PrimeUI.run()
    
    if text ~= "" then
        mokafile.write(",[3]=\""..text.."\"")
        serverName = text
    end

    PrimeUI.clear()
    PrimeUI.label(term.current(), 3, 2, "mokaFormat... (press enter for default)")
    PrimeUI.horizontalLine(term.current(), 3, 3, #("mokaFormat... (press enter for default)") + 2)
    PrimeUI.borderBox(term.current(), 4, 7, 40, 1)
    PrimeUI.inputBox(term.current(), 4, 7, 40, "result")
    local _, _, text = PrimeUI.run()

    if text ~= "" then
        mokafile.write(",[4]=\""..text.."\"")
        mokaFormat = text
    else
        mokafile.write(",[4]=\"{3}\"")
    end

    PrimeUI.clear()
    PrimeUI.label(term.current(), 3, 2, "reboundClient #... (press enter to disable)")
    PrimeUI.horizontalLine(term.current(), 3, 3, #("reboundClient #... (press enter to disable)") + 2)
    PrimeUI.borderBox(term.current(), 4, 7, 40, 1)
    PrimeUI.inputBox(term.current(), 4, 7, 40, "result")
    local _, _, text = PrimeUI.run()
    
    if text ~= "" then
        mokafile.write(",[5]="..text.."}")
        reboundnum = tonumber(text)
    else
        mokafile.write(",[5]=\"disable\"}")
    end
    
    mokafile.close()
    term.clear()
    term.setCursorPos(1,1)
    print("Thank you for installing MOKA!")
    sleep(1)
else
    io.write("[")
    term.setTextColor(colors.green)
    io.write("INIT")
    term.setTextColor(colors.white)
    print("]: Getting mokafile data...")
    dataTable = loadfile(".moka")()
    local function okay(text)
        io.write("[")
        term.setTextColor(colors.green)
        io.write("OKAY")
        term.setTextColor(colors.white)
        print("]: "..text)
    end

    
    local function warn(text)
        io.write("[")
        term.setTextColor(colors.yellow)
        io.write("WARN")
        term.setTextColor(colors.white)
        print("]: "..text)
    end
    
    local function nilvalue(text)
        io.write("[")
        term.setTextColor(colors.red)
        io.write("NILV")
        term.setTextColor(colors.white)
        print("]: "..text)
    end

    local nilevent = false
    local function dohostdata()
        hostdata = dataTable[1]
    end
    
    local function dotickSpeed()
        tickSpeed = dataTable[2]
    end
    
    local function donewServerName()
        newServerName = dataTable[3]
    end
    
    local function donewmokaFormat()
        newmokaFormat = dataTable[4]
    end

    local function doreboundnum()
        newreboundnum = dataTable[5]
    end
    
    local ok1,_ = pcall(dohostdata)
    local ok2,_ = pcall(dotickSpeed)
    local ok3,_ = pcall(donewServerName)
    local ok4,_ = pcall(donewmokaFormat)
    local ok5,_ = pcall(doreboundnum)
    
    if ok1 == false then
        nilvalue("Could not retreive hostdata")
        nilevent = true
    end

    if ok2 == false then
        nilvalue("Could not retreive tickSpeed")
        nilevent = true
    end

    if ok3 == false then
        nilvalue("Could not retreive serverName")
        nilevent = true
    end

    if ok4 == false then
        nilvalue("Could not retreive mokaFormat")
        nilevent = true
    end
    
    if ok5 == false then
        nilvalue("Could not retreive reboundnum")
        nilevent = true
    end
    
    if hostdata ~= nil then
        okay("hostdata "..hostdata)
    else
        nilvalue("hostdata")
        nilevent = true
    end

    if tickSpeed ~= nil then
        okay("tickSpeed "..tickSpeed)
    else
        nilvalue("tickSpeed")
        nilevent = true
    end

    if newServerName ~= nil then
        okay("serverName "..newServerName)
    else
        warn("serverName not defined, setting to default instead")
    end

    if newmokaFormat ~= nil then
        okay("mokaFormat "..newmokaFormat)
    else
        warn("mokaFormat not defined, setting to default instead")
    end
    
    if newreboundnum ~= nil then
        okay("reboundnum "..newreboundnum)
    else
        warn("reboundnum not defined, setting to default instead")
    end
    
    if nilevent == true then
        term.setTextColor(colors.red)
        print("MOKA: Error detected. Press R to enter recovery mode, C to continue with default values (not reccomended!), or Q to exit.")
        local k = 0
        repeat
            _,k = os.pullEvent("key")
        until k == keys.r or k == keys.q or k == keys.c
        if k == keys.q then
            os.queueEvent("terminate")
        end
        if k == keys.r then
            shell.run("wget","https://pastebin.com/raw/3LfWxRWh","tmp")
            local bigfont = require("tmp")
            term.setCursorPos(1,1)
            term.setBackgroundColor(colors.blue)
            term.clear()
            term.setTextColor(colors.white)
            bigfont.bigPrint("Error")
            shell.run("delete", "tmp")
            print("Attempting to fix...\n\n")
            shell.run("delete", "moka.lua")
            shell.run("delete", ".moka")
            shell.run("wget", "https://raw.githubusercontent.com/inutogen/MOKA/main/moka.lua")
            print("Fixes applied. Press any key to continue...")
            os.pullEvent("key")
            term.setBackgroundColor(colors.black)
            term.clear()
            term.setCursorPos(1,1)
            os.queueEvent("terminate")
        end
    end
end

if newServerName ~= nil then
    serverName = newServerName
end

if newmokaFormat ~= nil then
    mokaFormat = newmokaFormat
end

if newreboundnum ~= nil then
    reboundnum = newreboundnum
end

local function compare(formatv, message)
    local expectedCount = tonumber(formatv:match("{(%d+)}"))

    if not expectedCount then
        return false
    end

    if type(message) == "table" then
        return #message == expectedCount
    else
        return false
    end
end

local function reboundClient(pos, newPos, maxval)
    local a = vector.new(pos[1],pos[2],pos[3])
    local b = vector.new(newPos[1],newPos[2],newPos[3])
    local check = b:length() - a:length()
    return abs(check)>maxval
end

term.setTextColor(colors.white)
print("MOKA running")
peripheral.find("modem", rednet.open)
rednet.host(hostdata, serverName)
local idlist = {}
local pos = {}
local received = {}
local temprec = {}
local function getData()
    while true do
        local id,msg,prot = rednet.receive()
        if msg == "received" then
            received[id] = true
        elseif prot == "find" then
            if msg == hostname then
                rednet.send(id,"host")
            else
                rednet.send(id,"nonhost")
            end
        else
            if prot == hostdata then
                local findcorrect = compare(mokaFormat, msg)
                if findcorrect == true then
                    if reboundnum ~= "disable" then
                        if pos[id] ~= nil then
                            local checkRebound = reboundClient(pos[id],msg,tonumber(reboundnum))
                            if checkRebound == false then
                                pos[id] = msg
                            end
                        else
                          pos[id] = msg
                        end
                    else
                        pos[id] = msg
                    end
                end
            end
        end
    end
end

local function gameTick()
    while true do
        sleep(1/tickSpeed)
        print(textutils.serialise(pos))
        rednet.broadcast(textutils.serialise(pos),(hostdata.."R"))
    end
end

local function bootConnection()
    while true do
        sleep(0.3)
        for id, isReceived in pairs(received) do
            if not isReceived then
                table.remove(pos,id)
            end
        end
        for id, _ in pairs(received) do
            received[id] = false
        end
    end
end

parallel.waitForAny(getData, gameTick, bootConnection)
