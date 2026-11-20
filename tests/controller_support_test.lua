-- Controller support (Leave alone / On / Off) sets the input mode only at PLAYER_LOGIN.

return function(test, check, FakeGame)
    local LAYOUTS = { { name = "keyboard-pc" }, { name = "controller-pc", controller = true } }
    local CVAR = "InputDeviceInterfaceStyle"

    local function Saved(controllerSupport)
        return { version = 3, profiles = { ["1920x1080"] = { name = "PC", controllerSupport = controllerSupport,
            keyboardLayoutBase = "keyboard-pc", controllerLayoutBase = "controller-pc" } } }
    end

    test("Leave alone never sets the CVar, in either input mode", function()
        for _, mode in ipairs({ "keyboard", "controller" }) do
            local game = FakeGame.new({ inputMode = mode, layouts = LAYOUTS, saved = Saved(nil) }):Login()
            game:SetInputMode(mode == "keyboard" and "controller" or "keyboard")
            game:Reload()
            check.eq(game:CVarSets(CVAR), {}, "CVar writes starting in " .. mode)
            check.eq(game.reloadRequests, 0, "reloads starting in " .. mode)
            check.no(game.popupShown, "reload popup starting in " .. mode)
        end
    end)

    test("a new profile leaves controller support alone", function()
        local game = FakeGame.new():Login()
        local profile = game.env.AutoSetup.EnsureProfile("1920x1080")
        check.eq(profile.controllerSupport, nil, "controller support")
        check.eq(profile.controllerLayoutBase, nil, "controller Base layout")
        check.eq(profile.controllerLayoutTarget, nil, "controller Target layout")
    end)

    test("On switches to controller at login, reloads once and then applies the controller layout", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS, saved = Saved(true) }):Login()
        check.eq(game:CVarSets(CVAR), { "1" }, "CVar writes")
        check.eq(game.reloadRequests, 1, "reloads")
        check.eq(game.selectedLayouts, {}, "layouts selected before the reload")

        game:Reload()
        check.eq(game:CVarSets(CVAR), { "1" }, "CVar writes after the reload")
        check.eq(game.reloadRequests, 1, "reloads after the reload")
        check.eq(game.selectedLayouts, { "controller-pc" }, "layouts selected after the reload")
        check.no(game.popupShown, "reload popup")
    end)

    test("Off switches to keyboard at login and reloads", function()
        local game = FakeGame.new({ inputMode = "controller", layouts = LAYOUTS, saved = Saved(false) }):Login()
        check.eq(game:CVarSets(CVAR), { "0" }, "CVar writes")
        check.eq(game.reloadRequests, 1, "reloads")

        game:Reload()
        check.eq(game.selectedLayouts, { "keyboard-pc" }, "layouts selected after the reload")
    end)

    test("a switch that doesn't survive the reload doesn't reload again, and the popup says so", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS, saved = Saved(true) }):Login()
        -- The CVar took, but the client comes back in keyboard mode.
        game.cvars[CVAR] = "0"
        game:Reload()

        check.eq(game:CVarSets(CVAR), { "1", "1" }, "CVar writes")
        check.eq(game.reloadRequests, 1, "reloads")
        check.yes(game.popupShown, "reload popup shown")
        check.eq(game.selectedLayouts, {}, "layouts selected while the switch waits for a reload")
    end)

    test("a blocked switch applies the layouts of the actual input mode and shows the popup", function()
        local game = FakeGame.new({ inputMode = "keyboard", layouts = LAYOUTS, saved = Saved(true) })
        game.blockControllerCVar = true
        game:Login()

        check.eq(game.reloadRequests, 0, "reloads")
        check.eq(game.selectedLayouts, { "keyboard-pc" }, "layouts selected")
        check.yes(game.popupShown, "reload popup shown")
        check.yes(game.popupText:find("blocked", 1, true), "popup says the game blocked it")
    end)

    test("a profile set to On, with the player in keyboard mode by hand, applies the keyboard layout", function()
        local game = FakeGame.new({ inputMode = "controller", layouts = LAYOUTS, saved = Saved(true) }):Login()
        check.eq(game.selectedLayouts, { "controller-pc" }, "after login")

        game:SetInputMode("keyboard")
        check.eq(game:LastSelectedLayout(), "keyboard-pc", "after switching by hand")
        check.eq(game:CVarSets(CVAR), {}, "CVar writes")
    end)
end
