-- Which Edit Mode layout AutoSetup selects: the Base or Target layout of the input mode the game is in.

return function(test, check, FakeGame)
    local LAYOUTS = {
        { name = "keyboard-pc" }, { name = "keyboard-combat" },
        { name = "controller-pc", controller = true }, { name = "controller-combat", controller = true },
        { name = "steam-deck", controller = true },
    }

    -- A version 3 file with one profile for 1920x1080.
    local function Saved(profile)
        profile.name = profile.name or "PC"
        return { version = 3, profiles = { ["1920x1080"] = profile } }
    end

    local function BothModes(extra)
        local profile = { keyboardLayoutBase = "keyboard-pc", controllerLayoutBase = "controller-pc" }
        for k, v in pairs(extra or {}) do profile[k] = v end
        return Saved(profile)
    end

    test("Leave alone in controller mode selects the controller Base layout, and the keyboard one after switching", function()
        local game = FakeGame.new({ inputMode = "controller", layouts = LAYOUTS, saved = BothModes() }):Login()
        check.eq(game.selectedLayouts, { "controller-pc" }, "after login")

        game:SetInputMode("keyboard")
        check.eq(game.selectedLayouts, { "controller-pc", "keyboard-pc" }, "after switching to keyboard")

        game:SetInputMode("controller")
        check.eq(game:LastSelectedLayout(), "controller-pc", "after switching back")
    end)

    test("Leave alone in keyboard mode selects the keyboard Base layout", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS, saved = BothModes() }):Login()
        check.eq(game.selectedLayouts, { "keyboard-pc" }, "after login")
    end)

    test("a mid-session switch changes only the layout: no CVar, no reload, no popup", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS,
            saved = BothModes({ scale = 0.8 }) }):Login()
        local cvarWrites = #game.cvarSets

        game:SetInputMode("controller")
        check.eq(game:LastSelectedLayout(), "controller-pc", "layout")
        check.eq(#game.cvarSets, cvarWrites, "CVar writes after the switch")
        check.eq(game.reloadRequests, 0, "reloads")
        check.no(game.popupShown, "reload popup shown")
    end)

    test("the Target layout of the current input mode applies with a target, the Base layout without", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS, saved = BothModes({
            keyboardLayoutTarget = "keyboard-combat", controllerLayoutTarget = "controller-combat" }) }):Login()

        game:SetTarget(true)
        check.eq(game:LastSelectedLayout(), "keyboard-combat", "keyboard with a target")

        game:SetInputMode("controller")
        check.eq(game:LastSelectedLayout(), "controller-combat", "switched to controller while targeting")

        game:SetTarget(false)
        check.eq(game:LastSelectedLayout(), "controller-pc", "controller without a target")
    end)

    test("target changes apply in a mode with a Target layout after switching from one without", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS,
            saved = BothModes({ controllerLayoutTarget = "controller-combat" }) }):Login()

        game:SetTarget(true)
        check.eq(game.selectedLayouts, { "keyboard-pc" }, "keyboard has no Target layout: the Base layout stays")

        game:SetTarget(false)
        game:SetInputMode("controller")
        game:SetTarget(true)
        check.eq(game:LastSelectedLayout(), "controller-combat", "controller with a target")
    end)

    test("combat switches to the Target layout and back when it ends", function()
        local game = FakeGame.new({ inputMode = "controller", layouts = LAYOUTS,
            saved = BothModes({ controllerLayoutTarget = "controller-combat" }) }):Login()

        game:StartCombat()
        check.eq(game:LastSelectedLayout(), "controller-combat", "in combat")
        game:EndCombat()
        check.eq(game:LastSelectedLayout(), "controller-pc", "after combat")
    end)

    test("an input mode switch in combat waits until combat ends", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS, saved = BothModes() }):Login()

        game:StartCombat()
        game:SetInputMode("controller")
        check.eq(game.selectedLayouts, { "keyboard-pc" }, "layouts selected in combat")

        game:EndCombat()
        check.eq(game:LastSelectedLayout(), "controller-pc", "after combat")
    end)

    test("a switch in combat to a mode with a Target layout picks up targets once combat ends", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS,
            saved = BothModes({ controllerLayoutTarget = "controller-combat" }) }):Login()

        game:StartCombat()
        game:SetInputMode("controller")
        game:EndCombat()
        check.eq(game:LastSelectedLayout(), "controller-pc", "after combat")

        game:SetTarget(true)
        check.eq(game:LastSelectedLayout(), "controller-combat", "target after combat")
    end)

    test("an empty controller Base layout leaves Edit Mode alone in controller mode", function()
        local game = FakeGame.new({ inputMode = "controller", layouts = LAYOUTS,
            saved = Saved({ keyboardLayoutBase = "keyboard-pc" }) }):Login()
        check.eq(game.selectedLayouts, {}, "layouts selected")
        check.eq(game:ActiveLayoutName(), "Gamepad", "active layout")
    end)

    test("a layout name that belongs to the other input mode selects nothing", function()
        local game = FakeGame.new({ inputMode = "controller", layouts = LAYOUTS,
            saved = Saved({ controllerLayoutBase = "keyboard-pc" }) }):Login()
        check.eq(game.selectedLayouts, {}, "layouts selected")
    end)

    test("names match without color codes, case or spaces", function()
        local game = FakeGame.new({ inputMode = "controller", layouts = LAYOUTS,
            saved = Saved({ controllerLayoutBase = " |cffff0000Controller-PC|r " }) }):Login()
        check.eq(game.selectedLayouts, { "controller-pc" }, "layouts selected")
    end)

    test("only the profile of the current resolution applies", function()
        local saved = { version = 3, profiles = {
            ["1920x1080"] = { name = "PC", keyboardLayoutBase = "keyboard-pc" },
            ["1280x800"] = { name = "Deck", controllerLayoutBase = "steam-deck" },
        } }
        local game = FakeGame.new({ resolution = "1280x800", inputMode = "controller",
            layouts = LAYOUTS, saved = saved }):Login()
        check.eq(game.selectedLayouts, { "steam-deck" }, "layouts selected")
    end)

    test("without the controller interface only the keyboard layouts apply, whatever the profile says", function()
        local game = FakeGame.new({ controllerInterface = false, layouts = { { name = "keyboard-pc" } },
            saved = BothModes({ controllerSupport = true }) }):Login()
        check.eq(game.selectedLayouts, { "keyboard-pc" }, "layouts selected")
        check.eq(game.cvarSets, {}, "CVar writes")
        check.no(game.popupShown, "reload popup shown")
    end)

    test("leaving Edit Mode applies the layout that waited for it", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS, saved = BothModes() }):Login()
        game.editModeOpen = true
        game:SetInputMode("controller")
        check.eq(game.selectedLayouts, { "keyboard-pc" }, "while Edit Mode is open")

        game.editModeOpen = false
        game.callbacks["EditMode.Exit"]()
        game:RunTimers()
        check.eq(game:LastSelectedLayout(), "controller-pc", "after leaving Edit Mode")
    end)
end
