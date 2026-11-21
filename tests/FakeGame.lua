-- A fake game for the offline tests. It loads the addon's Lua files in TOC order into an
-- environment of its own (the XML files are skipped) and fakes only what the addon calls. Tests
-- drive it like a player (log in, target, fight, toggle the controller interface, reload) and
-- read back only what the game would see: layouts selected, CVars set, AutoSetupDB, reload requests,
-- the reload popup and chat.
--
-- Reading a global or a field the fake doesn't provide fails loudly instead of returning nil, so a
-- new API call in the addon shows up here. ABSENT lists the globals the addon only tests for.

local FakeGame = {}
FakeGame.__index = FakeGame

local MKB, GAMEPAD = 0, 1
local CONTROLLER_CVAR = "InputDeviceInterfaceStyle"

-- Globals the addon checks for and copes without; reading them gives nil.
local ABSENT = {
    AutoSetupDB = true, -- before the first logout there is no saved file
    C_DamageMeter = true,
    QoLAPI = true, -- the QoL feature provider
}

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[DeepCopy(k)] = DeepCopy(v) end
    return copy
end
FakeGame.DeepCopy = DeepCopy

-- A table whose missing fields are an error.
local function Strict(name, t)
    return setmetatable(t, {
        __index = function(_, key)
            error("fake game: " .. name .. "." .. tostring(key) .. " is not faked", 2)
        end,
    })
end

local function TocLuaFiles(tocPath)
    local files = {}
    for rawLine in io.lines(tocPath) do
        local line = rawLine:gsub("\r$", "")
        if not line:match("^#") and line:match("%.lua$") then
            table.insert(files, (line:gsub("\\", "/")))
        end
    end
    return files
end

-- opts:
--   resolution          "1920x1080" (default)
--   controllerInterface the client has the controller interface (default true)
--   inputMode           "keyboard" (default) or "controller"
--   layouts             user layouts: { { name = "keyboard-pc" }, { name = "controller-pc", controller = true } }
--   saved               AutoSetupDB as the saved file holds it (nil: first start)
function FakeGame.new(opts)
    opts = opts or {}
    local self = setmetatable({}, FakeGame)
    self.resolution = opts.resolution or "1920x1080"
    self.controllerInterface = opts.controllerInterface ~= false
    self.style = (opts.inputMode == "controller") and GAMEPAD or MKB
    self.cvars = { uiScale = "1.0" }
    if self.controllerInterface then self.cvars[CONTROLLER_CVAR] = tostring(self.style) end
    self.blockControllerCVar = false -- the game refuses the addon's SetCVar on the input mode
    self.saved = DeepCopy(opts.saved)

    -- Edit Mode: the presets first, then the user's layouts, as EditModeManagerFrame:GetLayouts() has them.
    self.layouts = {
        { layoutName = "Modern", layoutType = 0, interfaceStyle = MKB },
        { layoutName = "Classic", layoutType = 0, interfaceStyle = MKB },
    }
    if self.controllerInterface then
        table.insert(self.layouts, { layoutName = "Gamepad", layoutType = 0, interfaceStyle = GAMEPAD })
    end
    for _, layout in ipairs(opts.layouts or {}) do
        table.insert(self.layouts, {
            layoutName = layout.name,
            layoutType = 1,
            -- Keyboard layouts saved before the controller interface have no style at all.
            interfaceStyle = layout.controller and GAMEPAD or nil,
        })
    end
    self:SelectPresetForStyle()
    self.editModeOpen = false

    self.selectedLayouts = {} -- names passed to C_EditMode.SetActiveLayout, in order
    self.cvarSets = {}        -- { name, value } for every SetCVar
    self.reloadRequests = 0
    self.popupShown = false
    self.popupText = nil
    self.chat = {}
    self.errors = {}
    return self
end

function FakeGame:SelectPresetForStyle()
    for i, layout in ipairs(self.layouts) do
        if layout.layoutType == 0 and layout.interfaceStyle == self.style then
            self.activeLayout = i
            return
        end
    end
end

function FakeGame:ActiveLayoutName()
    return self.layouts[self.activeLayout].layoutName
end

function FakeGame:LastSelectedLayout()
    return self.selectedLayouts[#self.selectedLayouts]
end

-- The values the addon wrote to a CVar, in order.
function FakeGame:CVarSets(name)
    local values = {}
    for _, set in ipairs(self.cvarSets) do
        if set[1] == name then table.insert(values, set[2]) end
    end
    return values
end

function FakeGame:ChatContains(text)
    for _, line in ipairs(self.chat) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- The environment the addon runs in
-------------------------------------------------------------------------------

function FakeGame:Frame()
    local frame = { events = {}, scripts = {} }
    frame.RegisterEvent = function(f, event) f.events[event] = true end
    frame.UnregisterEvent = function(f, event) f.events[event] = nil end
    frame.IsEventRegistered = function(f, event) return f.events[event] == true end
    frame.SetScript = function(f, script, fn) f.scripts[script] = fn end
    frame.GetScript = function(f, script) return f.scripts[script] end
    table.insert(self.frames, frame)
    return Strict("frame", frame)
end

function FakeGame:BuildEnv()
    local game = self
    local env = {}

    for _, name in ipairs({ "string", "table", "math", "pairs", "ipairs", "next", "type", "tostring",
        "tonumber", "error", "pcall", "select", "setmetatable", "getmetatable", "unpack",
        "rawget", "rawset", "assert" }) do
        env[name] = _G[name]
    end
    env._G = env
    -- WoW's xpcall passes extra arguments to the function; Lua 5.1's drops them.
    env.xpcall = function(fn, handler, ...)
        local n, args = select("#", ...), { ... }
        return xpcall(function() return fn(unpack(args, 1, n)) end, handler)
    end
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        table.insert(game.chat, table.concat(parts, " "))
    end
    env.date = os.date
    env.wipe = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
    env.CopyTable = DeepCopy
    env.CallErrorHandler = function(err) table.insert(game.errors, err) end
    env.SlashCmdList = {}

    env.Enum = Strict("Enum", {
        InputDeviceInterfaceType = Strict("Enum.InputDeviceInterfaceType", { Mkb = MKB, Gamepad = GAMEPAD }),
        AddOnEnableState = Strict("Enum.AddOnEnableState", { None = 0, Some = 1, All = 2 }),
        EditModeLayoutType = Strict("Enum.EditModeLayoutType", { Preset = 0, Account = 1, Character = 2, Server = 3 }),
    })

    -- Screen and CVars
    env.GetPhysicalScreenSize = function()
        local w, h = game.resolution:match("^(%d+)x(%d+)$")
        return tonumber(w), tonumber(h)
    end
    local function GetCVar(name) return game.cvars[name] end
    local function SetCVar(name, value)
        value = tostring(value)
        table.insert(game.cvarSets, { name, value })
        if name == CONTROLLER_CVAR and game.blockControllerCVar then return false end
        game.cvars[name] = value
        return true
    end
    env.GetCVar, env.SetCVar = GetCVar, SetCVar
    env.C_CVar = Strict("C_CVar", { GetCVar = GetCVar, SetCVar = SetCVar })
    local absent = DeepCopy(ABSENT)
    if self.controllerInterface then
        env.C_InputInterfaceStyle = Strict("C_InputInterfaceStyle", {
            GetCurrentStyle = function() return game.style end,
        })
    else
        absent.C_InputInterfaceStyle = true
    end
    env.C_EventUtils = Strict("C_EventUtils", { IsEventValid = function() return true end })

    -- Combat and units
    env.InCombatLockdown = function() return game.lockdown == true end
    env.UnitAffectingCombat = function(unit) return unit == "player" and game.inCombat == true end
    env.UnitExists = function(unit)
        if unit == "target" then return game.target == true end
        if unit == "softenemy" then return game.softEnemy == true end
        return unit == "player"
    end

    -- Frames, timers, callbacks
    env.CreateFrame = function() return game:Frame() end
    env.C_Timer = Strict("C_Timer", {
        After = function(_, fn) table.insert(game.timers, fn) end,
        NewTicker = function(_, fn)
            table.insert(game.tickers, fn)
            return { Cancel = function() end }
        end,
    })
    env.EventRegistry = Strict("EventRegistry", {
        RegisterCallback = function(_, event, fn) game.callbacks[event] = fn end,
    })

    -- Edit Mode
    env.C_EditMode = Strict("C_EditMode", {
        SetActiveLayout = function(index)
            local layout = game.layouts[index] or error("SetActiveLayout: no layout " .. tostring(index))
            table.insert(game.selectedLayouts, layout.layoutName)
            game.activeLayout = index
            -- The game fires this synchronously, from inside the call.
            game:Fire("EDIT_MODE_LAYOUTS_UPDATED")
        end,
    })
    env.EditModeManagerFrame = Strict("EditModeManagerFrame", {
        IsEditModeActive = function() return game.editModeOpen end,
        IsInitialized = function() return true end,
        GetActiveLayoutInfo = function() return game.layouts[game.activeLayout] end,
        GetLayouts = function() return game.layouts end,
    })

    -- AddOns: AutoSetup alone, enabled.
    local addons = { { name = "AutoSetup", title = "AutoSetup", enabled = true } }
    local function FindAddOn(nameOrIndex)
        if type(nameOrIndex) == "number" then return addons[nameOrIndex] end
        for _, addon in ipairs(addons) do
            if addon.name == nameOrIndex then return addon end
        end
    end
    env.C_AddOns = Strict("C_AddOns", {
        GetNumAddOns = function() return #addons end,
        GetAddOnInfo = function(i)
            local addon = FindAddOn(i)
            return addon.name, addon.title
        end,
        GetAddOnEnableState = function(nameOrIndex)
            return FindAddOn(nameOrIndex).enabled and 2 or 0
        end,
        EnableAddOn = function(nameOrIndex) FindAddOn(nameOrIndex).enabled = true end,
        DisableAddOn = function(nameOrIndex) FindAddOn(nameOrIndex).enabled = false end,
        SaveAddOns = function() end,
        LoadAddOn = function() end,
    })

    -- Reload and the reload popup (AutoSetup_ReloadPopup.xml)
    env.C_UI = Strict("C_UI", { Reload = function() game.reloadRequests = game.reloadRequests + 1 end })
    env.ReloadUI = env.C_UI.Reload
    env.AutoSetupReloadPopup = Strict("AutoSetupReloadPopup", { Show = function() game.popupShown = true end })
    env.AutoSetupReloadPopupMessage = Strict("AutoSetupReloadPopupMessage", {
        SetText = function(_, text) game.popupText = text end,
    })

    env.AutoSetupDB = DeepCopy(self.saved)

    return setmetatable(env, {
        __index = function(_, key)
            if absent[key] then return nil end
            error("fake game: global " .. tostring(key) .. " is not faked", 2)
        end,
    })
end

-------------------------------------------------------------------------------
-- Driving the game
-------------------------------------------------------------------------------

-- Fire an event at every frame that registered it, like the game does.
function FakeGame:Fire(event, ...)
    local frames = {}
    for i, frame in ipairs(self.frames) do frames[i] = frame end
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

-- Run every pending C_Timer.After callback, also those they start. Tickers don't run.
function FakeGame:RunTimers()
    local rounds = 0
    while #self.timers > 0 do
        rounds = rounds + 1
        if rounds > 100 then error("fake game: timers keep starting timers") end
        local timers = self.timers
        self.timers = {}
        for _, fn in ipairs(timers) do fn() end
    end
end

-- Start the client and log in: the addon loads with the saved file, the world comes up and
-- Edit Mode's layouts arrive.
function FakeGame:Login()
    self.frames, self.timers, self.tickers, self.callbacks = {}, {}, {}, {}
    self.lockdown, self.inCombat, self.target, self.softEnemy = false, false, false, false
    self.env = self:BuildEnv()

    local ns = {}
    for _, path in ipairs(TocLuaFiles("AutoSetup.toc")) do
        local chunk = assert(loadfile(path))
        setfenv(chunk, self.env)
        chunk("AutoSetup", ns)
    end

    self:Fire("ADDON_LOADED", "AutoSetup")
    self:Fire("PLAYER_LOGIN")
    self:Fire("PLAYER_ENTERING_WORLD")
    self:Fire("EDIT_MODE_LAYOUTS_UPDATED")
    self:RunTimers()
    return self
end

-- What the client writes to the saved file at logout or reload.
function FakeGame:SavedDB()
    return self.env.AutoSetupDB
end

-- Reload the UI: the client saves AutoSetupDB, a changed input mode CVar takes effect, and the
-- addon loads again in a fresh Lua state.
function FakeGame:Reload()
    self.saved = DeepCopy(self.env.AutoSetupDB)
    if self.controllerInterface then
        local style = tonumber(self.cvars[CONTROLLER_CVAR]) or MKB
        if style ~= self.style then
            self.style = style
            self:SelectPresetForStyle()
        end
    end
    return self:Login()
end

-- The player toggles the controller interface in the game's options: it switches without a reload
-- and the game puts a layout of the new mode in place.
function FakeGame:SetInputMode(mode)
    self.style = (mode == "controller") and GAMEPAD or MKB
    self.cvars[CONTROLLER_CVAR] = tostring(self.style)
    local active = self.layouts[self.activeLayout]
    if (active.interfaceStyle or MKB) ~= self.style then self:SelectPresetForStyle() end
    self:Fire("INPUT_DEVICE_INTERFACE_TRANSITION")
    self:RunTimers()
end

function FakeGame:SetTarget(exists)
    self.target = exists
    self:Fire("PLAYER_TARGET_CHANGED")
    self:RunTimers()
end

-- The game fires PLAYER_REGEN_DISABLED just before the lockdown starts, and ENABLED just after it ends.
function FakeGame:StartCombat()
    self.inCombat = true
    self:Fire("PLAYER_REGEN_DISABLED")
    self.lockdown = true
    self:RunTimers()
end

function FakeGame:EndCombat()
    self.lockdown = false
    self.inCombat = false
    self:Fire("PLAYER_REGEN_ENABLED")
    self:RunTimers()
end

return FakeGame
