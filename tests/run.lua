-- Offline tests, Lua 5.1, run from the repository root:  lua tests/run.lua [tests/<file>_test.lua ...]
-- Without arguments it runs every file in FILES.
-- Each test file returns function(test, check, FakeGame) and registers its tests with test(name, fn).
-- A failed check or error fails that test; any failure makes the exit code 1.

local FakeGame = dofile("tests/FakeGame.lua")

local FILES = {
    "tests/migration_test.lua",
    "tests/layouts_test.lua",
    "tests/controller_support_test.lua",
}
if arg and #arg > 0 then FILES = arg end

local tests = {}
local function test(name, fn)
    table.insert(tests, { name = name, fn = fn })
end

local function Show(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for k in pairs(value) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do table.insert(parts, tostring(k) .. " = " .. Show(value[k])) end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local check = {}

-- Equal values; tables compare by contents.
function check.eq(actual, expected, what)
    if not Same(actual, expected) then
        error((what or "value") .. ": expected " .. Show(expected) .. ", got " .. Show(actual), 2)
    end
end

function check.yes(value, what)
    if not value then error((what or "condition") .. " should hold", 2) end
end

function check.no(value, what)
    if value then error((what or "condition") .. " should not hold", 2) end
end

for _, file in ipairs(FILES) do
    dofile(file)(test, check, FakeGame)
end

local failed = 0
for _, t in ipairs(tests) do
    local ok, err = xpcall(t.fn, debug.traceback)
    if ok then
        print("ok   " .. t.name)
    else
        failed = failed + 1
        print("FAIL " .. t.name .. "\n     " .. tostring(err):gsub("\n", "\n     "))
    end
end

print(string.format("\n%d tests, %d failed", #tests, failed))
os.exit(failed > 0 and 1 or 0)
