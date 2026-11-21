-- Saved data from version 2 becomes version 3 once, at login.

return function(test, check, FakeGame)
    test("version 2 profiles keep their layouts as keyboard layouts and their controller support", function()
        local game = FakeGame.new({
            saved = {
                version = 2,
                profiles = {
                    ["1920x1080"] = { name = "PC", editLayoutBase = "pc", editLayoutTarget = "pc-combat",
                        nativeControllerSupport = false, scale = 0.8 },
                    ["2560x1440"] = { name = "Wide", editLayoutBase = "wide" },
                    ["1280x800"] = { name = "Deck", nativeControllerSupport = true },
                },
            },
        }):Login()

        check.eq(game:SavedDB(), {
            version = 3,
            profiles = {
                -- false and no value both become an explicit Off: no value now means Leave alone
                ["1920x1080"] = { name = "PC", keyboardLayoutBase = "pc", keyboardLayoutTarget = "pc-combat",
                    controllerSupport = false, scale = 0.8 },
                ["2560x1440"] = { name = "Wide", keyboardLayoutBase = "wide", controllerSupport = false },
                ["1280x800"] = { name = "Deck", controllerSupport = true },
            },
        }, "saved data")
    end)

    test("version 1 data goes through both steps", function()
        local game = FakeGame.new({
            saved = { ["1920x1080"] = { name = "PC", editLayoutBase = "pc", autoReload = true } },
        }):Login()

        check.eq(game:SavedDB(), {
            version = 3,
            profiles = { ["1920x1080"] = { name = "PC", keyboardLayoutBase = "pc", controllerSupport = false } },
        }, "saved data")
    end)

    test("a migrated Off profile still turns the controller interface off at login", function()
        local game = FakeGame.new({
            inputMode = "controller",
            saved = { version = 2, profiles = { ["1920x1080"] = { name = "PC", editLayoutBase = "pc" } } },
        }):Login()

        check.eq(game:CVarSets("InputDeviceInterfaceStyle"), { "0" }, "controller support CVar writes")
    end)

    test("a failed migration step leaves the saved data as it was", function()
        local saved = { version = 2, profiles = "not a table" }
        local game = FakeGame.new({ saved = saved }):Login()

        check.eq(game:SavedDB(), saved, "saved data")
        check.eq(#game.errors, 1, "errors reported")
        check.yes(game:ChatContains("Couldn't read the saved profiles"), "the player is told")
    end)

    test("data from a newer AutoSetup is left alone but its profile applies", function()
        local saved = {
            version = 4,
            profiles = { ["1920x1080"] = { name = "PC", keyboardLayoutBase = "pc", futureField = 1 } },
        }
        local game = FakeGame.new({ saved = saved, layouts = { { name = "pc" } } }):Login()

        check.eq(game:SavedDB(), saved, "saved data")
        check.eq(game.selectedLayouts, { "pc" }, "layouts selected")
    end)

    test("a first start saves an empty version 3 file", function()
        local game = FakeGame.new():Login()
        check.eq(game:SavedDB(), { version = 3, profiles = {} }, "saved data")
    end)
end
