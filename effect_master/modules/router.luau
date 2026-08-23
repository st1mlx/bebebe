local Module = { VERSION = 4 }

local Controller
local VFX
local RNG = Random.new()

local bags = {}
local lastByRoute = {}

local ROUTE_TO_FIELD = {
    Hit = "SelectedHitEffect",
    Death = "SelectedDeathEffect",
    Kill = "SelectedKillVisualEffect",
}

local ROUTE_TO_RANDOM_FIELD = {
    Hit = "RandomHitEffect",
    Death = "RandomDeathEffect",
    Kill = "RandomKillVisualEffect",
}

local function getDefaultBase()
    local catalogByID = Controller.CatalogByID or {}
    return Controller.SelectedHitEffect
        or catalogByID["_hitEffectDefault"]
        or catalogByID["_hitEffectDefaultReworked"]
end

local function copyAndShuffle(values)
    local result = table.create(#values)
    for index, value in ipairs(values) do
        result[index] = value
    end
    for index = #result, 2, -1 do
        local swapIndex = RNG:NextInteger(1, index)
        result[index], result[swapIndex] = result[swapIndex], result[index]
    end
    return result
end

local function rebuildBag(route, catalog)
    bags[route] = {
        Catalog = catalog,
        Size = #catalog,
        Revision = Controller.CatalogRevision or 0,
        Values = copyAndShuffle(catalog),
    }
    return bags[route]
end

local function getBag(route, catalog)
    local bag = bags[route]
    if not bag or bag.Catalog ~= catalog or bag.Size ~= #catalog
        or bag.Revision ~= (Controller.CatalogRevision or 0) or #bag.Values == 0 then
        bag = rebuildBag(route, catalog)
    end
    return bag
end

local function setInheritedRoutes(entry)
    if not entry then return end
    Controller.SelectedHitEffect = entry
    if not Controller.DeathRouteOverride then
        Controller.SelectedDeathEffect = entry
    end
    if not Controller.KillRouteOverride then
        Controller.SelectedKillVisualEffect = entry
    end
end

function Module.Init(deps)
    assert(type(deps) == "table", "Router.Init: deps table required")
    Controller = assert(deps.Controller, "Router.Init: Controller required")
    VFX = assert(deps.VFX, "Router.Init: VFX required")
    Controller.DeathRouteOverride = Controller.DeathRouteOverride == true
    Controller.KillRouteOverride = Controller.KillRouteOverride == true
    Module.SyncDefaults()
    return Module
end

function Module.SyncDefaults()
    local base = getDefaultBase()
    if base then setInheritedRoutes(base) end
    return base
end

function Module.SetBase(entry)
    if not entry then return nil end
    setInheritedRoutes(entry)
    return entry
end

function Module.SetStudioSelection(route, entry)
    if not entry then return nil end
    if route == "Hit" then
        setInheritedRoutes(entry)
    elseif route == "Death" then
        Controller.DeathRouteOverride = true
        Controller.SelectedDeathEffect = entry
    elseif route == "Kill" then
        Controller.KillRouteOverride = true
        Controller.SelectedKillVisualEffect = entry
    else
        return nil
    end
    return entry
end

function Module.ResetOverrides()
    Controller.DeathRouteOverride = false
    Controller.KillRouteOverride = false
    setInheritedRoutes(getDefaultBase())
end

function Module.GetSelected(route)
    local field = ROUTE_TO_FIELD[route]
    if not field then return nil end
    return Controller[field] or Module.SyncDefaults()
end

function Module.InvalidateCatalog()
    table.clear(bags)
end

function Module.Choose(route)
    local selected = Module.GetSelected(route)
    local randomField = ROUTE_TO_RANDOM_FIELD[route]
    if not randomField or not Controller[randomField] then
        return selected
    end

    local catalog = Controller.CatalogHit
    if not catalog or #catalog == 0 then return selected end

    local bag = getBag(route, catalog)
    local repeatedCandidate
    while #bag.Values > 0 do
        local index = #bag.Values
        local candidate = bag.Values[index]
        bag.Values[index] = nil
        if candidate then
            local candidateID = candidate.ItemID or candidate.Name
            local support = candidate.RouteSupport
            local routeMayExist = not support or support[route] ~= false
            if routeMayExist and VFX.canPlayEffect(candidate, route, true) then
                if #catalog == 1 or candidateID ~= lastByRoute[route] then
                    lastByRoute[route] = candidateID
                    return candidate
                end
                repeatedCandidate = repeatedCandidate or candidate
            end
        end
    end

    if repeatedCandidate then
        lastByRoute[route] = repeatedCandidate.ItemID or repeatedCandidate.Name
        return repeatedCandidate
    end
    return selected
end
return Module
