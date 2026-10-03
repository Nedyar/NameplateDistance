-- lua5.1 Tests/run.lua [addon folder]
--
-- Runs tests.lua against the addon's real files, in a stand-in for the game
-- (mock.lua). Lua 5.1 is the game's Lua. The addon folder defaults to the one
-- holding this Tests folder.
local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
local ADDON = arg[1] or (HERE .. "/..")

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

-- The release files, for the checks on the version and the packaging.
SOURCES = {
    ["mock.lua"] = Read(HERE .. "/mock.lua"),
    ["NameplateDistance.toc"] = Read(ADDON .. "/NameplateDistance.toc"),
    ["CHANGELOG.md"] = Read(ADDON .. "/CHANGELOG.md"),
    [".pkgmeta"] = Read(ADDON .. "/.pkgmeta"),
}

-- The addon's files, in the order of its TOC: the tests load them as the game
-- does, so a file missing from the TOC, or listed but missing, shows up.
FILES = {}
for line in SOURCES["NameplateDistance.toc"]:gmatch("[^\r\n]+") do
    local file = line:match("^%s*(.-)%s*$")
    if file ~= "" and not file:find("^#") then
        FILES[#FILES + 1] = (file:gsub("\\", "/"))
    end
end
for _, file in ipairs(FILES) do
    SOURCES[file] = Read(ADDON .. "/" .. file)
end

-- Every text the code looks up in its translations, L["..."] or ns.L["..."],
-- for the check that each language file has exactly these.
KEYS = {}
local seen = {}
for _, file in ipairs(FILES) do
    if not file:find("^Locales/") then
        local source = SOURCES[file]
        local at = 1
        while true do
            local start, quote = source:find('L%["', at)
            if not start then
                break
            end
            local before = source:sub(start - 1, start - 1)
            local prefixed = before == "." and source:sub(start - 3, start - 1) == "ns."
            -- The literal ends at the first quote no backslash escapes.
            local stop = quote + 1
            while source:sub(stop, stop) ~= '"' do
                stop = stop + (source:sub(stop, stop) == "\\" and 2 or 1)
            end
            if (prefixed or not before:find("[%w_.]")) and source:sub(stop + 1, stop + 1) == "]" then
                local key = assert(loadstring("return " .. source:sub(quote, stop)))()
                if not seen[key] then
                    seen[key] = true
                    KEYS[#KEYS + 1] = key
                end
            end
            at = stop + 1
        end
    end
end

-- The mock replaces print to record what the addon prints.
print_real = print

local chunk = assert(loadfile(HERE .. "/tests.lua"))
local ok, failures = xpcall(chunk, debug.traceback)
if not ok then
    print_real("CRASH: " .. tostring(failures))
    os.exit(2)
end
os.exit(failures == 0 and 0 or 1)
