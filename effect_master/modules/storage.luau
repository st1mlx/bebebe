local Module = { VERSION = 8 }

local Controller
local Serializer
local ReplicatedStorage
local ContentProvider
local hasFileSystem = false
local AssetsFolder
local HitFolder
local SpawnFolder
local failedSerialized = {}
local failedFileContents = {}

-- These aliases were previously captured from the all-in-one outer scope.
-- They MUST exist inside storage.luau when the module is loaded remotely.
local table_insert = table.insert
local task_wait = task.wait

local function refreshAssetFolders()
    if not AssetsFolder or AssetsFolder.Parent ~= ReplicatedStorage then
        AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
        HitFolder = nil
        SpawnFolder = nil
    end
    if AssetsFolder then
        if not HitFolder or HitFolder.Parent ~= AssetsFolder then
            HitFolder = AssetsFolder:FindFirstChild("HitEffects")
        end
        if not SpawnFolder or SpawnFolder.Parent ~= AssetsFolder then
            SpawnFolder = AssetsFolder:FindFirstChild("SpawnEffects")
        end
    end
    return HitFolder, SpawnFolder
end

function Module.Init(deps)
    assert(type(deps) == "table", "Storage.Init: deps table required")
    Controller = assert(deps.Controller, "Storage.Init: Controller required")
    Serializer = assert(deps.Serializer, "Storage.Init: Serializer required")
    ReplicatedStorage = deps.ReplicatedStorage or game:GetService("ReplicatedStorage")
    ContentProvider = deps.ContentProvider or game:GetService("ContentProvider")
    hasFileSystem = deps.hasFileSystem == true
    refreshAssetFolders()
    return Module
end

function Module.ensureEffectInstanceLoaded(entry)
    if not entry then return nil end
    local id = entry.ItemID
    local cached = Controller.InstanceCache[id]
    if cached then
        local valid = pcall(function() return cached.ClassName end)
        if valid then return cached end
        Controller.InstanceCache[id] = nil
    end

    local hitFolder, spawnFolder = refreshAssetFolders()
    local found = (hitFolder and hitFolder:FindFirstChild(id)) or (spawnFolder and spawnFolder:FindFirstChild(id))
    if found then
        Controller.InstanceCache[id] = found
        failedSerialized[id] = nil
        return found
    end

    local serialized = Controller.CloudCache[id]
    if serialized and failedSerialized[id] ~= serialized then
        local deserialized = Serializer.deserializeInstance(serialized)
        if deserialized then
            Controller.InstanceCache[id] = deserialized
            failedSerialized[id] = nil
            return deserialized
        end
        failedSerialized[id] = serialized
    end

    if hasFileSystem then
        local subDir = (entry.Category == "SpawnEffect") and "spawn" or "hit"
        local categoryPrefix = (entry.Category == "SpawnEffect") and "SpawnEffect" or "HitEffect"
        local candidates = {
            "effect/" .. subDir .. "/" .. id,
            "effect/" .. subDir .. "/" .. id .. ".txt",
            id,
            id .. ".txt",
        }

        for _, rarityName in ipairs({ "Mythical", "Legendary", "Epic", "Rare", "Uncommon", "Common", "Special" }) do
            local legacyName = categoryPrefix .. "__" .. rarityName .. "__" .. id .. ".txt"
            table_insert(candidates, legacyName)
            table_insert(candidates, "effect/" .. subDir .. "/" .. legacyName)
        end

        if type(listfiles) == "function" and type(isfolder) == "function" then
            local folderPath = "effect/" .. subDir
            if isfolder(folderPath) then
                local okList, files = pcall(listfiles, folderPath)
                if okList and type(files) == "table" then
                    for _, candidatePath in ipairs(files) do
                        local normalized = tostring(candidatePath):gsub("\\", "/")
                        local base = normalized:match("([^/]+)$") or normalized
                        if base:find(id, 1, true) then
                            table_insert(candidates, candidatePath)
                        end
                    end
                end
            end
        end

        local checked = {}
        for _, filePath in ipairs(candidates) do
            if not checked[filePath] then
                checked[filePath] = true
                if isfile(filePath) then
                    local ok, raw = pcall(readfile, filePath)
                    if ok and raw and raw ~= "" and failedFileContents[filePath] ~= raw then
                        local deserialized = Serializer.deserializeInstance(raw)
                        if deserialized then
                            Controller.InstanceCache[id] = deserialized
                            failedFileContents[filePath] = nil
                            return deserialized
                        end
                        failedFileContents[filePath] = raw
                    end
                end
            end
        end
    end

    return nil
end

function Module.preloadAssetsAsync(instances)
    if not instances or #instances == 0 then return false end

    -- Do NOT pass a whole 100-200 KB hierarchy to PreloadAsync in one shot.
    -- Collect only content-bearing Instances and preload them in small batches.
    local targets = {}
    local seen = setmetatable({}, { __mode = "k" })

    local function addTarget(instance)
        if not instance or seen[instance] then return end
        seen[instance] = true
        table_insert(targets, instance)
    end

    local function collect(root)
        if not root then return end
        local function consider(instance)
            if instance:IsA("ParticleEmitter")
                or instance:IsA("Beam")
                or instance:IsA("Trail")
                or instance:IsA("Sound")
                or instance:IsA("MeshPart")
                or instance:IsA("SpecialMesh")
                or instance:IsA("Decal")
                or instance:IsA("Texture")
                or instance:IsA("ImageLabel")
                or instance:IsA("ImageButton")
                or instance:IsA("SurfaceAppearance")
                or instance:IsA("VideoFrame")
            then
                addTarget(instance)
            end
        end

        consider(root)
        for index, descendant in ipairs(root:GetDescendants()) do
            consider(descendant)
            if index % 80 == 0 then task_wait() end
        end
    end

    for _, root in ipairs(instances) do
        collect(root)
    end

    if #targets == 0 then return true end

    local okAll = true
    local batchSize = 10
    for first = 1, #targets, batchSize do
        local batch = {}
        local last = math.min(first + batchSize - 1, #targets)
        for index = first, last do
            table_insert(batch, targets[index])
        end
        local ok = pcall(function()
            ContentProvider:PreloadAsync(batch)
        end)
        okAll = okAll and ok
        task_wait()
    end
    return okAll
end

function Module.purgeInactiveEffects()
    for id, inst in pairs(Controller.InstanceCache) do
        if not Controller.Selected or Controller.Selected.ItemID ~= id then
            if inst and inst.Parent == nil then
                pcall(inst.Destroy, inst)
                Controller.InstanceCache[id] = nil
                if Controller.PreloadedEffects then Controller.PreloadedEffects[id] = nil end
                if Controller.PreloadInFlight then Controller.PreloadInFlight[id] = nil end
            end
        end
    end
end
return Module
