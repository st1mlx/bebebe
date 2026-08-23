-- Effect Master v16 deployment verifier
local HttpService = game:GetService("HttpService")
local ROOT = "https://raw.githubusercontent.com/st1mlx/bebebe/refs/heads/main/effect_master/"
local MODULES = {
    { "serializer.luau", 9 },
    { "catalog.luau", 13 },
    { "storage.luau", 9 },
    { "vfx_player.luau", 16 },
    { "router.luau", 4 },
}

local function fetch(url)
    local body = game:HttpGet(url .. (url:find("?", 1, true) and "&" or "?") .. "verify=" .. tostring(os.time()))
    assert(type(body) == "string" and #body > 16, "Empty response: " .. url)
    assert(not body:find("404: Not Found", 1, true), "404: " .. url)
    return body
end

print("[EffectMaster v16] verifying modules...")
for _, spec in ipairs(MODULES) do
    local name, minimumVersion = spec[1], spec[2]
    local source = fetch(ROOT .. "modules/" .. name)
    local chunk, compileError = loadstring(source, "@" .. name)
    assert(chunk, "Compile failed " .. name .. ": " .. tostring(compileError))
    local ok, module = pcall(chunk)
    assert(ok, "Runtime failed " .. name .. ": " .. tostring(module))
    assert(type(module) == "table", name .. " returned " .. typeof(module))
    assert((module.VERSION or 0) >= minimumVersion,
        name .. " is old. Got VERSION " .. tostring(module.VERSION) .. ", expected >= " .. minimumVersion)
    print("  OK", name, "VERSION", module.VERSION)
end

print("[EffectMaster v16] verifying public index...")
local indexRaw = fetch(ROOT .. "effects/index.json")
local index = HttpService:JSONDecode(indexRaw)
assert(type(index) == "table" and type(index.Effects) == "table", "Invalid effects/index.json")
local count = 0
for _ in pairs(index.Effects) do count += 1 end
assert(count >= 307, "Public index is incomplete: " .. tostring(count))
print("  OK index:", count, "effects; build:", index.Build)

local critical = {
    "_hitEffectDemonicFireRing",
    "_hitEffectFlamingPandemonium",
    "_hitEffectBarzilBlackhole",
    "_hitEffectDamned",
    "_hitEffectEnergized",
    "_hitEffectHaloHeart",
    "_hitEffectNecrobloxicon",
    "_hitEffectDiceTornado",
    "_hitEffectPortal",
    "_hitEffectRelude",
    "_hitEffectSaintMarked",
}

print("[EffectMaster v16] verifying 11 critical Mythicals...")
for _, id in ipairs(critical) do
    local info = assert(index.Effects[id], "Missing index entry: " .. id)
    assert(info.Rarity == "Mythical", id .. " rarity is " .. tostring(info.Rarity))
    local payload = fetch(ROOT .. "effects/" .. info.Path)
    assert(#payload > 1000, id .. " payload is suspiciously small")
    print("  OK", id, info.Name, #payload, "bytes")
end

print("[EffectMaster v16] DEPLOYMENT OK")
