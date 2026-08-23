local Module = { VERSION = 13 }

local Controller
local HttpService
local hasFileSystem = false
local GITHUB_SECRET_URL = ""
local PUBLIC_EFFECT_INDEX_URL = ""

local table_insert = table.insert
local table_sort = table.sort
local Color3_fromRGB = Color3.fromRGB
local pcall = pcall
local pairs = pairs
local ipairs = ipairs

local function isAllowedSpecialKill(id)
    local normalized = tostring(id or ""):lower():gsub("[^%w]", "")
    return normalized:find("staffrave", 1, true) ~= nil
        or normalized:find("kittykatastrophe", 1, true) ~= nil
end

local ROUTE_MARKERS = {
    Hit = "_HIT_EFFECT",
    Death = "_DEATH_EFFECT",
    Kill = "_KILL_EFFECT",
    Spawn = "_SPAWN_EFFECT",
}

local ROUTE_BY_MARKER = {}
for route, marker in pairs(ROUTE_MARKERS) do
    ROUTE_BY_MARKER[marker] = route
end

local displayDirty = true
local dirtyCategories = { Hit = true, Spawn = true, Kill = true }

local function detectRouteSupport(serialized, instance, category)
    local support = {}
    local foundNamedRoute = false

    if type(serialized) == "string" and serialized ~= "" then
        for route, marker in pairs(ROUTE_MARKERS) do
            local found = serialized:find(marker, 1, true) ~= nil
            support[route] = found
            foundNamedRoute = foundNamedRoute or found
        end
    elseif instance then
        for route in pairs(ROUTE_MARKERS) do
            support[route] = false
        end

        local rootRoute = ROUTE_BY_MARKER[instance.Name]
        if rootRoute then
            support[rootRoute] = true
            foundNamedRoute = true
        end

        for _, descendant in ipairs(instance:GetDescendants()) do
            local route = ROUTE_BY_MARKER[descendant.Name]
            if route and not support[route] then
                support[route] = true
                foundNamedRoute = true
            end
        end
    else
        if category == "HitEffect" then return { Hit = true } end
        if category == "SpawnEffect" then return { Spawn = true } end
        return nil
    end

    -- A package stored under HitEffects is itself a valid Hit route even when
    -- only _DEATH_EFFECT/_KILL_EFFECT child containers are named. Several real
    -- Mythicals (Halo Heart, Portal, Relude, Energized, Damned, Enchanted)
    -- keep their hit particles in the shared/root layer instead of _HIT_EFFECT.
    if category == "HitEffect" then
        support.Hit = true
    elseif category == "SpawnEffect" then
        support.Spawn = true
    end
    return support
end

local function mergeRouteSupport(entry, serialized, instance, category)
    entry.RouteSupport = entry.RouteSupport or {}

    local function merge(detected)
        if not detected then return end
        for route, available in pairs(detected) do
            if available or entry.RouteSupport[route] == nil then
                entry.RouteSupport[route] = available
            end
        end
    end

    if serialized and entry._RouteSerializedSource ~= serialized then
        entry._RouteSerializedSource = serialized
        merge(detectRouteSupport(serialized, nil, category))
    end
    if instance and entry._RouteInstanceSource ~= instance then
        entry._RouteInstanceSource = instance
        merge(detectRouteSupport(nil, instance, category))
    end
end

function Module.Init(deps)
    assert(type(deps) == "table", "Catalog.Init: deps table required")
    Controller = assert(deps.Controller, "Catalog.Init: Controller required")
    HttpService = deps.HttpService or game:GetService("HttpService")
    hasFileSystem = deps.hasFileSystem == true
    GITHUB_SECRET_URL = assert(deps.GITHUB_SECRET_URL, "Catalog.Init: GITHUB_SECRET_URL required")
    PUBLIC_EFFECT_INDEX_URL = assert(deps.PUBLIC_EFFECT_INDEX_URL, "Catalog.Init: PUBLIC_EFFECT_INDEX_URL required")
    Controller.HitDisplayLookup = Controller.HitDisplayLookup or {}
    Controller.SpawnDisplayLookup = Controller.SpawnDisplayLookup or {}
    Controller.KillDisplayLookup = Controller.KillDisplayLookup or {}
    Controller.CatalogRevision = Controller.CatalogRevision or 0
    Controller.HitDisplayRevision = Controller.HitDisplayRevision or 0
    Controller.SpawnDisplayRevision = Controller.SpawnDisplayRevision or 0
    Controller.KillDisplayRevision = Controller.KillDisplayRevision or 0
    return Module
end

local RARITY = {
    Special = { Rank = 1, Label = "Special", Color = Color3_fromRGB(255, 140, 0), Hex = "#FFA500" },
    Mythical = { Rank = 2, Label = "Mythical", Color = Color3_fromRGB(255, 34, 71), Hex = "#FF2247" },
    Legendary = { Rank = 3, Label = "Legendary", Color = Color3_fromRGB(255, 215, 0), Hex = "#FFD700" },
    Epic = { Rank = 4, Label = "Epic", Color = Color3_fromRGB(185, 85, 255), Hex = "#B955FF" },
    Rare = { Rank = 5, Label = "Rare", Color = Color3_fromRGB(50, 150, 255), Hex = "#3296FF" },
    Uncommon = { Rank = 6, Label = "Uncommon", Color = Color3_fromRGB(46, 204, 113), Hex = "#2ECC71" },
    Common = { Rank = 7, Label = "Common", Color = Color3_fromRGB(200, 200, 200), Hex = "#C8C8C8" },
    Unknown = { Rank = 8, Label = "Unknown", Color = Color3_fromRGB(160, 160, 160), Hex = "#A0A0A0" },
}

local RARITY_MAP = {
    ["_hitEffectAbyss"] = "Epic",
    ["_hitEffectAngryCat"] = "Uncommon",
    ["_hitEffectAquaticGateway"] = "Rare",
    ["_hitEffectBabyNuke"] = "Epic",
    ["_hitEffectBarzilBlackhole"] = "Mythical",
    ["_hitEffectBarzilCoins"] = "Uncommon",
    ["_hitEffectBarzilPortalVortex"] = "Rare",
    ["_hitEffectBasketballExplosion"] = "Uncommon",
    ["_hitEffectBatty"] = "Rare",
    ["_hitEffectBinary"] = "Uncommon",
    ["_hitEffectBirdz"] = "Rare",
    ["_hitEffectBlackFeatherBurst"] = "Uncommon",
    ["_hitEffectBlizzard"] = "Legendary",
    ["_hitEffectBlossom"] = "Rare",
    ["_hitEffectBloxyCharms"] = "Epic",
    ["_hitEffectBlueExplosion"] = "Uncommon",
    ["_hitEffectBlueNova"] = "Legendary",
    ["_hitEffectBluePortal"] = "Rare",
    ["_hitEffectBoombox"] = "Rare",
    ["_hitEffectBootsAndHats"] = "Uncommon",
    ["_hitEffectBrainFog"] = "Rare",
    ["_hitEffectBread"] = "Uncommon",
    ["_hitEffectBrokenHeart"] = "Rare",
    ["_hitEffectBugsInfestation"] = "Uncommon",
    ["_hitEffectButterflies"] = "Rare",
    ["_hitEffectButterflyAscend"] = "Uncommon",
    ["_hitEffectCarrotBlast"] = "Epic",
    ["_hitEffectCartoonyWater"] = "Rare",
    ["_hitEffectCauldronBubbles"] = "Rare",
    ["_hitEffectChillingFog"] = "Epic",
    ["_hitEffectChip"] = "Rare",
    ["_hitEffectChocolate"] = "Rare",
    ["_hitEffectClassical"] = "Epic",
    ["_hitEffectClockExplosion"] = "Rare",
    ["_hitEffectClovers"] = "Uncommon",
    ["_hitEffectConfetti"] = "Rare",
    ["_hitEffectConjuringInk"] = "Rare",
    ["_hitEffectCookies&Milk"] = "Rare",
    ["_hitEffectCorruptingMark"] = "Epic",
    ["_hitEffectCosmicGlitter"] = "Epic",
    ["_hitEffectCozyMoon"] = "Rare",
    ["_hitEffectCrimsonSplash"] = "Rare",
    ["_hitEffectCrimsonUproar"] = "Rare",
    ["_hitEffectCroakingContamination"] = "Rare",
    ["_hitEffectCrows"] = "Rare",
    ["_hitEffectCupidsArrow"] = "Epic",
    ["_hitEffectCuriousCat"] = "Rare",
    ["_hitEffectCursed"] = "Epic",
    ["_hitEffectDamned"] = "Mythical",
    ["_hitEffectDarkness"] = "Legendary",
    ["_hitEffectDaveGoldenSlamdown"] = "Legendary",
    ["_hitEffectDaveHit"] = "Rare",
    ["_hitEffectDaveSlamdown"] = "Epic",
    ["_hitEffectDefault"] = "Common",
    ["_hitEffectDefaultReworked"] = "Common",
    ["_hitEffectDemonicFireRing"] = "Mythical",
    ["_hitEffectDemonicHex"] = "Legendary",
    ["_hitEffectDiamonds"] = "Special",
    ["_hitEffectDiceTornado"] = "Mythical",
    ["_hitEffectDiceToss"] = "Rare",
    ["_hitEffectDivergent"] = "Epic",
    ["_hitEffectDreamcore"] = "Legendary",
    ["_hitEffectDrumBeatdown"] = "Uncommon",
    ["_hitEffectDuckie"] = "Uncommon",
    ["_hitEffectDumbCat"] = "Rare",
    ["_hitEffectEasterEggDetonation"] = "Epic",
    ["_hitEffectEerieFog"] = "Legendary",
    ["_hitEffectElectricField"] = "Uncommon",
    ["_hitEffectEnchanted"] = "Epic",
    ["_hitEffectEnergized"] = "Mythical",
    ["_hitEffectEruptingBricks"] = "Epic",
    ["_hitEffectEvil"] = "Uncommon",
    ["_hitEffectEvilCat"] = "Uncommon",
    ["_hitEffectExplosion"] = "Uncommon",
    ["_hitEffectExplosives"] = "Epic",
    ["_hitEffectEye"] = "Rare",
    ["_hitEffectFallingBoulder"] = "Uncommon",
    ["_hitEffectFeathersBurst"] = "Uncommon",
    ["_hitEffectFireworks"] = "Rare",
    ["_hitEffectFishy"] = "Uncommon",
    ["_hitEffectFlameBurst"] = "Legendary",
    ["_hitEffectFlameThrower"] = "Rare",
    ["_hitEffectFlamingPandemonium"] = "Mythical",
    ["_hitEffectFloatingCandles"] = "Uncommon",
    ["_hitEffectFloralOutburst"] = "Epic",
    ["_hitEffectForcefield"] = "Uncommon",
    ["_hitEffectFractal"] = "Epic",
    ["_hitEffectGalacticDisco"] = "Rare",
    ["_hitEffectGarbage"] = "Uncommon",
    ["_hitEffectGhostlyCleavers"] = "Legendary",
    ["_hitEffectGlass"] = "Legendary",
    ["_hitEffectGlassBreaking"] = "Uncommon",
    ["_hitEffectGlitched"] = "Epic",
    ["_hitEffectGlitter"] = "Legendary",
    ["_hitEffectGloomingRunes"] = "Epic",
    ["_hitEffectGlow"] = "Rare",
    ["_hitEffectGold"] = "Rare",
    ["_hitEffectGoldenClovers"] = "Rare",
    ["_hitEffectGoldenCoins"] = "Rare",
    ["_hitEffectGoldenHorseshoe"] = "Rare",
    ["_hitEffectGoldenMoai"] = "Rare",
    ["_hitEffectGoldenSparkles"] = "Rare",
    ["_hitEffectGrassAndFireflies"] = "Uncommon",
    ["_hitEffectGravity"] = "Rare",
    ["_hitEffectGroggy"] = "Rare",
    ["_hitEffectHarmony"] = "Uncommon",
    ["_hitEffectHeart"] = "Uncommon",
    ["_hitEffectHelloCat"] = "Uncommon",
    ["_hitEffectHitman"] = "Legendary",
    ["_hitEffectHoly"] = "Legendary",
    ["_hitEffectIceFlash"] = "Epic",
    ["_hitEffectIceShards"] = "Epic",
    ["_hitEffectIceStab"] = "Rare",
    ["_hitEffectInk"] = "Rare",
    ["_hitEffectJackOLantern"] = "Legendary",
    ["_hitEffectJobApplication"] = "Uncommon",
    ["_hitEffectKiteTakeOff"] = "Uncommon",
    ["_hitEffectLandmineExplosion"] = "Epic",
    ["_hitEffectLavaSkulls"] = "Uncommon",
    ["_hitEffectLeaves"] = "Uncommon",
    ["_hitEffectLetsTakeALook"] = "Rare",
    ["_hitEffectLight"] = "Rare",
    ["_hitEffectLightning"] = "Legendary",
    ["_hitEffectLightningStrike"] = "Epic",
    ["_hitEffectLoomingFog"] = "Epic",
    ["_hitEffectLoveBite"] = "Legendary",
    ["_hitEffectLucky"] = "Uncommon",
    ["_hitEffectMarshmallowCritters"] = "Rare",
    ["_hitEffectMiniCrit"] = "Uncommon",
    ["_hitEffectMoonBeams"] = "Rare",
    ["_hitEffectMortisFan"] = "Rare",
    ["_hitEffectMoyai"] = "Uncommon",
    ["_hitEffectMulticoloredDetonation"] = "Epic",
    ["_hitEffectMushroomOutburst"] = "Uncommon",
    ["_hitEffectMusic"] = "Rare",
    ["_hitEffectNecrobloxicon"] = "Mythical",
    ["_hitEffectNoob"] = "Common",
    ["_hitEffectNorthernStar"] = "Epic",
    ["_hitEffectObjectTornado"] = "Epic",
    ["_hitEffectOogsDamnation"] = "Rare",
    ["_hitEffectOperaGXFirewall"] = "Rare",
    ["_hitEffectOperaGXShield"] = "Rare",
    ["_hitEffectOrnament"] = "Rare",
    ["_hitEffectPablosClownery"] = "Legendary",
    ["_hitEffectPainted"] = "Rare",
    ["_hitEffectPaparazzi"] = "Uncommon",
    ["_hitEffectPartyCat"] = "Rare",
    ["_hitEffectPastelConfetti"] = "Uncommon",
    ["_hitEffectPeppermint"] = "Rare",
    ["_hitEffectPhoenix"] = "Epic",
    ["_hitEffectPinched"] = "Epic",
    ["_hitEffectPixelBubbles"] = "Rare",
    ["_hitEffectPixelExplosion"] = "Rare",
    ["_hitEffectPixelSparkles"] = "Rare",
    ["_hitEffectPixelatedExplosion"] = "Rare",
    ["_hitEffectPixelatedLightning"] = "Rare",
    ["_hitEffectPixelatedSnow"] = "Rare",
    ["_hitEffectPlasmaBlast"] = "Epic",
    ["_hitEffectPobsLightSnack"] = "Rare",
    ["_hitEffectPoisonous"] = "Epic",
    ["_hitEffectPonderingORB"] = "Epic",
    ["_hitEffectPopstarSpectacle"] = "Legendary",
    ["_hitEffectPortal"] = "Mythical",
    ["_hitEffectPortalFog"] = "Rare",
    ["_hitEffectPotOfGold"] = "Epic",
    ["_hitEffectPsychic"] = "Epic",
    ["_hitEffectPumpkinMoon"] = "Uncommon",
    ["_hitEffectPumpkinSplash"] = "Rare",
    ["_hitEffectPurpleRapture"] = "Legendary",
    ["_hitEffectPutridSpew"] = "Rare",
    ["_hitEffectRGB"] = "Epic",
    ["_hitEffectRIFF"] = "Epic",
    ["_hitEffectRUN"] = "Rare",
    ["_hitEffectRays"] = "Rare",
    ["_hitEffectRealisticEye"] = "Uncommon",
    ["_hitEffectRelude"] = "Mythical",
    ["_hitEffectRetro"] = "Legendary",
    ["_hitEffectRiftJumper"] = "Uncommon",
    ["_hitEffectRobux"] = "Rare",
    ["_hitEffectRocks"] = "Uncommon",
    ["_hitEffectRockyPrison"] = "Uncommon",
    ["_hitEffectRoses"] = "Uncommon",
    ["_hitEffectRunes"] = "Epic",
    ["_hitEffectSacred"] = "Epic",
    ["_hitEffectSaintMarked"] = "Mythical",
    ["_hitEffectSandTornado"] = "Epic",
    ["_hitEffectSandy"] = "Uncommon",
    ["_hitEffectSeal"] = "Rare",
    ["_hitEffectShackled"] = "Epic",
    ["_hitEffectShadowBite"] = "Rare",
    ["_hitEffectSlashes"] = "Legendary",
    ["_hitEffectSlime"] = "Uncommon",
    ["_hitEffectSmartCat"] = "Rare",
    ["_hitEffectSmokeBomb"] = "Uncommon",
    ["_hitEffectSmoked"] = "Rare",
    ["_hitEffectSmugChud"] = "Uncommon",
    ["_hitEffectSnoobExplosion"] = "Rare",
    ["_hitEffectSnow"] = "Uncommon",
    ["_hitEffectSnowPeep"] = "Rare",
    ["_hitEffectSnowball"] = "Epic",
    ["_hitEffectSnowballFall"] = "Rare",
    ["_hitEffectSodaDelight"] = "Rare",
    ["_hitEffectSpiderInfestation"] = "Rare",
    ["_hitEffectSpiritSurge"] = "Legendary",
    ["_hitEffectStabbingDaggers"] = "Epic",
    ["_hitEffectStabbingNails"] = "Epic",
    ["_hitEffectStaffRave"] = "Special",
    ["_hitEffectKittyKatastrophe"] = "Special",
    ["_hitEffectStainedGlass"] = "Uncommon",
    ["_hitEffectStarfall"] = "Epic",
    ["_hitEffectStarryNight"] = "Epic",
    ["_hitEffectStellarGlow"] = "Legendary",
    ["_hitEffectStop"] = "Rare",
    ["_hitEffectSunBeams"] = "Rare",
    ["_hitEffectTheFall"] = "Legendary",
    ["_hitEffectTheParasite"] = "Legendary",
    ["_hitEffectThunderstorm"] = "Epic",
    ["_hitEffectTomeBurst"] = "Epic",
    ["_hitEffectToxicPuddle"] = "Epic",
    ["_hitEffectTrollRequiem"] = "Legendary",
    ["_hitEffectTrueTone"] = "Uncommon",
    ["_hitEffectValentinesButterflies"] = "Uncommon",
    ["_hitEffectVampireCat"] = "Rare",
    ["_hitEffectVibrantSupernova"] = "Epic",
    ["_hitEffectVinyl"] = "Uncommon",
    ["_hitEffectWarmUp"] = "Uncommon",
    ["_hitEffectWater"] = "Uncommon",
    ["_hitEffectWerewolfLaceration"] = "Legendary",
    ["_hitEffectWindTornado"] = "Rare",
    ["_hitEffectWindy"] = "Rare",
    ["_hitEffectWinterBlessed"] = "Rare",
    ["_hitEffectWitchesSpell"] = "Rare",
    ["_hitEffectWitchesTreats"] = "Uncommon",
    ["_hitEffectXmasGlow"] = "Rare",
    ["_hitEffectZombiePinata"] = "Epic",
    ["_spawnEffectAfterParty"] = "Epic",
    ["_spawnEffectArticBlast"] = "Legendary",
    ["_spawnEffectBoombox"] = "Mythical",
    ["_spawnEffectClassical"] = "Epic",
    ["_spawnEffectDefault"] = "Common",
    ["_spawnEffectDinoPhonk"] = "Rare",
    ["_spawnEffectDreamcore"] = "Legendary",
    ["_spawnEffectDrumBeatdown"] = "Rare",
    ["_spawnEffectGalacticDisco"] = "Rare",
    ["_spawnEffectGlow"] = "Rare",
    ["_spawnEffectHarmony"] = "Uncommon",
    ["_spawnEffectIceFlash"] = "Epic",
    ["_spawnEffectJingleBell"] = "Epic",
    ["_spawnEffectOperaGXFirewall"] = "Legendary",
    ["_spawnEffectPOP!"] = "Uncommon",
    ["_spawnEffectPaparazzi"] = "Uncommon",
    ["_spawnEffectPartyCat"] = "Rare",
    ["_spawnEffectRIFF"] = "Epic",
    ["_spawnEffectSnowballFall"] = "Rare",
    ["_spawnEffectStaffRave"] = "Special",
    ["_spawnEffectStarfall"] = "Epic",
    ["_spawnEffectStellarGlow"] = "Legendary",
    ["_spawnEffectTrueTone"] = "Uncommon",
    ["_spawnEffectWinterBlessed"] = "Mythical",
    ["_spawnEffectXmasGlow"] = "Rare",
}

local EFFECT_TEXTURE_MAP = {
    ["_hitEffectAbyss"] = "rbxassetid://16997086012",
    ["_hitEffectAngryCat"] = "rbxassetid://12159555294",
    ["_hitEffectAquaticGateway"] = "rbxassetid://9117822163",
    ["_hitEffectBabyNuke"] = "rbxassetid://70615070864895",
    ["_hitEffectBarzilBlackhole"] = "rbxassetid://127353288690632",
    ["_hitEffectBarzilCoins"] = "rbxassetid://18653044880",
    ["_hitEffectBarzilPortalVortex"] = "rbxassetid://18653044880",
    ["_hitEffectBasketballExplosion"] = "rbxassetid://116326437773913",
    ["_hitEffectBatty"] = "rbxassetid://17006081258",
    ["_hitEffectBinary"] = "rbxassetid://1053548563",
    ["_hitEffectBirdz"] = "rbxassetid://1053548563",
    ["_hitEffectBlackFeatherBurst"] = "rbxassetid://10849912178",
    ["_hitEffectBlizzard"] = "rbxassetid://16867460128",
    ["_hitEffectBlossom"] = "rbxassetid://1053548563",
    ["_hitEffectBloxyCharms"] = "rbxassetid://9119482207",
    ["_hitEffectBlueExplosion"] = "rbxassetid://1053548563",
    ["_hitEffectBlueNova"] = "rbxassetid://18653044880",
    ["_hitEffectBluePortal"] = "rbxassetid://10849912178",
    ["_hitEffectBoombox"] = "rbxassetid://16950679789",
    ["_hitEffectBootsAndHats"] = "rbxassetid://10849912178",
    ["_hitEffectBrainFog"] = "rbxassetid://10849912178",
    ["_hitEffectBread"] = "rbxassetid://16782021847",
    ["_hitEffectBrokenHeart"] = "rbxassetid://1053548563",
    ["_hitEffectBugsInfestation"] = "rbxassetid://72884735821985",
    ["_hitEffectButterflies"] = "rbxassetid://1053548563",
    ["_hitEffectButterflyAscend"] = "rbxassetid://10849912178",
    ["_hitEffectCarrotBlast"] = "rbxassetid://83413105302041",
    ["_hitEffectCartoonyWater"] = "rbxassetid://1053548563",
    ["_hitEffectCauldronBubbles"] = "rbxassetid://17006147619",
    ["_hitEffectChillingFog"] = "rbxassetid://16877839414",
    ["_hitEffectChip"] = "rbxassetid://15972621234",
    ["_hitEffectChocolate"] = "rbxassetid://1053548563",
    ["_hitEffectClassical"] = "rbxassetid://10198434999",
    ["_hitEffectClockExplosion"] = "rbxassetid://72889825953477",
    ["_hitEffectClovers"] = "rbxassetid://133895671684169",
    ["_hitEffectConfetti"] = "rbxassetid://12159555294",
    ["_hitEffectConjuringInk"] = "rbxassetid://15011468690",
    ["_hitEffectCookies&Milk"] = "rbxassetid://15972621234",
    ["_hitEffectCorruptingMark"] = "rbxassetid://10849912178",
    ["_hitEffectCosmicGlitter"] = "rbxassetid://10849912178",
    ["_hitEffectCozyMoon"] = "rbxassetid://10849912178",
    ["_hitEffectCrimsonSplash"] = "rbxassetid://16865903588",
    ["_hitEffectCrimsonUproar"] = "rbxassetid://10849912178",
    ["_hitEffectCroakingContamination"] = "rbxassetid://10849912178",
    ["_hitEffectCrows"] = "rbxassetid://15972621234",
    ["_hitEffectCupidsArrow"] = "rbxassetid://16813013655",
    ["_hitEffectCuriousCat"] = "rbxassetid://12159555294",
    ["_hitEffectCursed"] = "rbxassetid://438666196",
    ["_hitEffectDamned"] = "rbxassetid://17551525124",
    ["_hitEffectDarkness"] = "rbxassetid://16782021847",
    ["_hitEffectDaveGoldenSlamdown"] = "rbxassetid://18653044880",
    ["_hitEffectDaveHit"] = "rbxassetid://18653044880",
    ["_hitEffectDaveSlamdown"] = "rbxassetid://10849912178",
    ["_hitEffectDefault"] = "rbxassetid://5755091589",
    ["_hitEffectDefaultReworked"] = "rbxassetid://10849912178",
    ["_hitEffectDemonicFireRing"] = "rbxassetid://87790026409442",
    ["_hitEffectDemonicHex"] = "rbxassetid://15011468690",
    ["_hitEffectDiamonds"] = "rbxassetid://11845281419",
    ["_hitEffectDiceTornado"] = "rbxassetid://105792907048598",
    ["_hitEffectDiceToss"] = "rbxassetid://18653044880",
    ["_hitEffectDivergent"] = "rbxassetid://129315544336728",
    ["_hitEffectDreamcore"] = "rbxassetid://15011468690",
    ["_hitEffectDrumBeatdown"] = "rbxassetid://10849912178",
    ["_hitEffectDuckie"] = "rbxassetid://12371709421",
    ["_hitEffectDumbCat"] = "rbxassetid://15972621234",
    ["_hitEffectEasterEggDetonation"] = "rbxassetid://10849912178",
    ["_hitEffectEerieFog"] = "rbxassetid://17551525124",
    ["_hitEffectElectricField"] = "rbxassetid://15011468690",
    ["_hitEffectEnchanted"] = "rbxassetid://16866193510",
    ["_hitEffectEnergized"] = "rbxassetid://18653344777",
    ["_hitEffectEruptingBricks"] = "rbxassetid://15553173363",
    ["_hitEffectEvil"] = "rbxassetid://16782021847",
    ["_hitEffectEvilCat"] = "rbxassetid://73364452208985",
    ["_hitEffectExplosion"] = "rbxassetid://1053548563",
    ["_hitEffectExplosives"] = "rbxassetid://18653044880",
    ["_hitEffectEye"] = "rbxassetid://12371709421",
    ["_hitEffectFallingBoulder"] = "rbxassetid://136958347751674",
    ["_hitEffectFeathersBurst"] = "rbxassetid://10849912178",
    ["_hitEffectFireworks"] = "rbxassetid://1053548563",
    ["_hitEffectFishy"] = "rbxassetid://1053548563",
    ["_hitEffectFlameBurst"] = "rbxassetid://10849912178",
    ["_hitEffectFlameThrower"] = "rbxassetid://10849912178",
    ["_hitEffectFlamingPandemonium"] = "rbxassetid://10849912178",
    ["_hitEffectFloatingCandles"] = "rbxassetid://11627083142",
    ["_hitEffectFloralOutburst"] = "rbxassetid://10849912178",
    ["_hitEffectForcefield"] = "rbxassetid://1053548563",
    ["_hitEffectFractal"] = "rbxassetid://11845281419",
    ["_hitEffectGalacticDisco"] = "rbxassetid://77750034720199",
    ["_hitEffectGarbage"] = "rbxassetid://15972621234",
    ["_hitEffectGhostlyCleavers"] = "rbxassetid://120239526945712",
    ["_hitEffectGlass"] = "rbxassetid://14163287554",
    ["_hitEffectGlassBreaking"] = "rbxassetid://18653044880",
    ["_hitEffectGlitched"] = "rbxassetid://1053548563",
    ["_hitEffectGlitter"] = "rbxassetid://15972621234",
    ["_hitEffectGloomingRunes"] = "rbxassetid://10849912178",
    ["_hitEffectGlow"] = "rbxassetid://12159555294",
    ["_hitEffectGold"] = "rbxassetid://1053548563",
    ["_hitEffectGoldenClovers"] = "rbxassetid://133895671684169",
    ["_hitEffectGoldenCoins"] = "rbxassetid://108582915350738",
    ["_hitEffectGoldenHorseshoe"] = "rbxassetid://8545868378",
    ["_hitEffectGoldenMoai"] = "rbxassetid://18653044880",
    ["_hitEffectGoldenSparkles"] = "rbxassetid://15949207212",
    ["_hitEffectGrassAndFireflies"] = "rbxassetid://10849912178",
    ["_hitEffectGravity"] = "rbxassetid://11845281419",
    ["_hitEffectGroggy"] = "rbxassetid://9125639449",
    ["_hitEffectHarmony"] = "rbxassetid://16950679789",
    ["_hitEffectHeart"] = "rbxassetid://12371709421",
    ["_hitEffectHelloCat"] = "rbxassetid://93182124218516",
    ["_hitEffectHitman"] = "rbxassetid://8889430523",
    ["_hitEffectHoly"] = "rbxassetid://12385813444",
    ["_hitEffectIceFlash"] = "rbxassetid://16940423887",
    ["_hitEffectIceShards"] = "rbxassetid://1053548563",
    ["_hitEffectIceStab"] = "rbxassetid://10849912178",
    ["_hitEffectInk"] = "rbxassetid://16782021847",
    ["_hitEffectJackOLantern"] = "rbxassetid://17551525124",
    ["_hitEffectJobApplication"] = "rbxassetid://127730898098779",
    ["_hitEffectKiteTakeOff"] = "rbxassetid://10849912178",
    ["_hitEffectLandmineExplosion"] = "rbxassetid://12159555294",
    ["_hitEffectLavaSkulls"] = "rbxassetid://15972621234",
    ["_hitEffectLeaves"] = "rbxassetid://1053548563",
    ["_hitEffectLetsTakeALook"] = "rbxassetid://10849912178",
    ["_hitEffectLight"] = "rbxassetid://1053548563",
    ["_hitEffectLightning"] = "rbxassetid://12385813444",
    ["_hitEffectLightningStrike"] = "rbxassetid://10849912178",
    ["_hitEffectLoomingFog"] = "rbxassetid://10849912178",
    ["_hitEffectLoveBite"] = "rbxassetid://113535603287272",
    ["_hitEffectLucky"] = "rbxassetid://12371709421",
    ["_hitEffectMarshmallowCritters"] = "rbxassetid://10849912178",
    ["_hitEffectMiniCrit"] = "rbxassetid://15972621234",
    ["_hitEffectMoonBeams"] = "rbxassetid://10849912178",
    ["_hitEffectMortisFan"] = "rbxassetid://10849912178",
    ["_hitEffectMoyai"] = "rbxassetid://12371709421",
    ["_hitEffectMulticoloredDetonation"] = "rbxassetid://12159555294",
    ["_hitEffectMushroomOutburst"] = "rbxassetid://10849912178",
    ["_hitEffectMusic"] = "rbxassetid://1053548563",
    ["_hitEffectNecrobloxicon"] = "rbxassetid://10849912178",
    ["_hitEffectNoob"] = "rbxassetid://12371709421",
    ["_hitEffectNorthernStar"] = "rbxassetid://17062451848",
    ["_hitEffectObjectTornado"] = "rbxassetid://10849912178",
    ["_hitEffectOogsDamnation"] = "rbxassetid://10849912178",
    ["_hitEffectOperaGXFirewall"] = "rbxassetid://12159555294",
    ["_hitEffectOperaGXShield"] = "rbxassetid://12159555294",
    ["_hitEffectOrnament"] = "rbxassetid://1053548563",
    ["_hitEffectPablosClownery"] = "rbxassetid://9046173030",
    ["_hitEffectPainted"] = "rbxassetid://18653346227",
    ["_hitEffectPaparazzi"] = "rbxassetid://7015983157",
    ["_hitEffectPartyCat"] = "rbxassetid://10849912178",
    ["_hitEffectPastelConfetti"] = "rbxassetid://10849912178",
    ["_hitEffectPeppermint"] = "rbxassetid://16867460128",
    ["_hitEffectPhoenix"] = "rbxassetid://1621170406",
    ["_hitEffectPinched"] = "rbxassetid://2428506580",
    ["_hitEffectPixelBubbles"] = "rbxassetid://18653043886",
    ["_hitEffectPixelExplosion"] = "rbxassetid://12159555294",
    ["_hitEffectPixelSparkles"] = "rbxassetid://15527262676",
    ["_hitEffectPixelatedExplosion"] = "rbxassetid://1053548563",
    ["_hitEffectPixelatedLightning"] = "rbxassetid://1053548563",
    ["_hitEffectPixelatedSnow"] = "rbxassetid://1053548563",
    ["_hitEffectPlasmaBlast"] = "rbxassetid://1053548563",
    ["_hitEffectPobsLightSnack"] = "rbxassetid://10849912178",
    ["_hitEffectPoisonous"] = "rbxassetid://15320345984",
    ["_hitEffectPonderingORB"] = "rbxassetid://12159555294",
    ["_hitEffectPopstarSpectacle"] = "rbxassetid://9116394756",
    ["_hitEffectPortal"] = "rbxassetid://16784245301",
    ["_hitEffectPortalFog"] = "rbxassetid://129714262563660",
    ["_hitEffectPotOfGold"] = "rbxassetid://3199239299",
    ["_hitEffectPsychic"] = "rbxassetid://9116385087",
    ["_hitEffectPumpkinMoon"] = "rbxassetid://10849912178",
    ["_hitEffectPumpkinSplash"] = "rbxassetid://18653044880",
    ["_hitEffectPurpleRapture"] = "rbxassetid://9113444620",
    ["_hitEffectPutridSpew"] = "rbxassetid://10849912178",
    ["_hitEffectRGB"] = "rbxassetid://8748921125",
    ["_hitEffectRIFF"] = "rbxassetid://10198434999",
    ["_hitEffectRUN"] = "rbxassetid://8889430523",
    ["_hitEffectRays"] = "rbxassetid://1053548563",
    ["_hitEffectRealisticEye"] = "rbxassetid://74338368667966",
    ["_hitEffectRelude"] = "rbxassetid://9042306864",
    ["_hitEffectRetro"] = "rbxassetid://12371709421",
    ["_hitEffectRiftJumper"] = "rbxassetid://10849912178",
    ["_hitEffectRobux"] = "rbxassetid://1053548563",
    ["_hitEffectRocks"] = "rbxassetid://16782021847",
    ["_hitEffectRockyPrison"] = "rbxassetid://10849912178",
    ["_hitEffectRoses"] = "rbxassetid://1053548563",
    ["_hitEffectRunes"] = "rbxassetid://15972621234",
    ["_hitEffectSacred"] = "rbxassetid://15972621234",
    ["_hitEffectSaintMarked"] = "rbxassetid://10849912178",
    ["_hitEffectSandTornado"] = "rbxassetid://16877839414",
    ["_hitEffectSandy"] = "rbxassetid://16782021847",
    ["_hitEffectSeal"] = "rbxassetid://10849912178",
    ["_hitEffectShackled"] = "rbxassetid://133502662302093",
    ["_hitEffectShadowBite"] = "rbxassetid://1053548563",
    ["_hitEffectSlashes"] = "rbxassetid://11845281419",
    ["_hitEffectSlime"] = "rbxassetid://16782021847",
    ["_hitEffectSmartCat"] = "rbxassetid://15972621234",
    ["_hitEffectSmokeBomb"] = "rbxassetid://10849912178",
    ["_hitEffectSmoked"] = "rbxassetid://2699594712",
    ["_hitEffectSmugChud"] = "rbxassetid://122664806424217",
    ["_hitEffectSnoobExplosion"] = "rbxassetid://113280516831926",
    ["_hitEffectSnow"] = "rbxassetid://1053548563",
    ["_hitEffectSnowPeep"] = "rbxassetid://1053548563",
    ["_hitEffectSnowball"] = "rbxassetid://16813013655",
    ["_hitEffectSnowballFall"] = "rbxassetid://12159555294",
    ["_hitEffectSodaDelight"] = "rbxassetid://241576804",
    ["_hitEffectSpiderInfestation"] = "rbxassetid://10849912178",
    ["_hitEffectSpiritSurge"] = "rbxassetid://12159555294",
    ["_hitEffectStabbingDaggers"] = "rbxassetid://125513147876451",
    ["_hitEffectStabbingNails"] = "rbxassetid://10849912178",
    ["_hitEffectStaffRave"] = "rbxassetid://134110202576558",
    ["_hitEffectKittyKatastrophe"] = "rbxassetid://12528455353",
    ["_hitEffectStainedGlass"] = "rbxassetid://15972621234",
    ["_hitEffectStarfall"] = "rbxassetid://10849912178",
    ["_hitEffectStarryNight"] = "rbxassetid://17062452122",
    ["_hitEffectStellarGlow"] = "rbxassetid://9114620542",
    ["_hitEffectStop"] = "rbxassetid://16782021847",
    ["_hitEffectSunBeams"] = "rbxassetid://10849912178",
    ["_hitEffectTheFall"] = "rbxassetid://10843704382",
    ["_hitEffectTheParasite"] = "rbxassetid://10849912178",
    ["_hitEffectThunderstorm"] = "rbxassetid://8089207589",
    ["_hitEffectTomeBurst"] = "rbxassetid://10849912178",
    ["_hitEffectToxicPuddle"] = "rbxassetid://10849912178",
    ["_hitEffectTrollRequiem"] = "rbxassetid://131644922592212",
    ["_hitEffectTrueTone"] = "rbxassetid://10849912178",
    ["_hitEffectValentinesButterflies"] = "rbxassetid://12584765400",
    ["_hitEffectVampireCat"] = "rbxassetid://96793976976487",
    ["_hitEffectVibrantSupernova"] = "rbxassetid://12159555294",
    ["_hitEffectVinyl"] = "rbxassetid://16937107174",
    ["_hitEffectWarmUp"] = "rbxassetid://10849912178",
    ["_hitEffectWater"] = "rbxassetid://14747705274",
    ["_hitEffectWerewolfLaceration"] = "rbxassetid://11799607237",
    ["_hitEffectWindTornado"] = "rbxassetid://10849912178",
    ["_hitEffectWindy"] = "rbxassetid://7123907538",
    ["_hitEffectWinterBlessed"] = "rbxassetid://10849912178",
    ["_hitEffectWitchesSpell"] = "rbxassetid://1053548563",
    ["_hitEffectWitchesTreats"] = "rbxassetid://18653044880",
    ["_hitEffectXmasGlow"] = "rbxassetid://12159555294",
    ["_hitEffectZombiePinata"] = "rbxassetid://18653044880",
    ["_spawnEffectAfterParty"] = "rbxassetid://12363860111",
    ["_spawnEffectArticBlast"] = "rbxassetid://12865656309",
    ["_spawnEffectBoombox"] = "rbxassetid://12713358298",
    ["_spawnEffectClassical"] = "rbxassetid://16937107174",
    ["_spawnEffectDefault"] = "rbxassetid://10849912178",
    ["_spawnEffectDinoPhonk"] = "rbxassetid://18653044880",
    ["_spawnEffectDreamcore"] = "rbxassetid://117945572498547",
    ["_spawnEffectDrumBeatdown"] = "rbxassetid://108495251341280",
    ["_spawnEffectGalacticDisco"] = "rbxassetid://13903581452",
    ["_spawnEffectGlow"] = "rbxassetid://74264745598634",
    ["_spawnEffectHarmony"] = "rbxassetid://18653044880",
    ["_spawnEffectIceFlash"] = "rbxassetid://16940423887",
    ["_spawnEffectJingleBell"] = "rbxassetid://74264745598634",
    ["_spawnEffectOperaGXFirewall"] = "rbxassetid://97469250414473",
    ["_spawnEffectPOP!"] = "rbxassetid://12363676005",
    ["_spawnEffectPaparazzi"] = "rbxassetid://16937107174",
    ["_spawnEffectPartyCat"] = "rbxassetid://10849912178",
    ["_spawnEffectRIFF"] = "rbxassetid://77033732339018",
    ["_spawnEffectSnowballFall"] = "rbxassetid://74264745598634",
    ["_spawnEffectStaffRave"] = "rbxassetid://134110202576558",
    ["_spawnEffectStarfall"] = "rbxassetid://10849912178",
    ["_spawnEffectStellarGlow"] = "rbxassetid://10849912178",
    ["_spawnEffectTrueTone"] = "rbxassetid://8905832887",
    ["_spawnEffectWinterBlessed"] = "rbxassetid://74264745598634",
    ["_spawnEffectXmasGlow"] = "rbxassetid://74264745598634",
}

local EXACT_EFFECT_METADATA = {
    ["_hitEffectDemonicFireRing"] = { Rarity = "Mythical", DisplayName = "Hellfire Sigil" },
    ["_hitEffectFlamingPandemonium"] = { Rarity = "Mythical", DisplayName = "Pandecrownium" },
    ["_hitEffectBarzilBlackhole"] = { Rarity = "Mythical", DisplayName = "Barzilian Nexus" },
    ["_hitEffectDamned"] = { Rarity = "Mythical", DisplayName = "Damned" },
    ["_hitEffectEnergized"] = { Rarity = "Mythical", DisplayName = "Energized" },
    ["_hitEffectHaloHeart"] = { Rarity = "Mythical", DisplayName = "Halo Heart" },
    ["_hitEffectNecrobloxicon"] = { Rarity = "Mythical", DisplayName = "Necrobloxicon" },
    ["_hitEffectDiceTornado"] = { Rarity = "Mythical", DisplayName = "Dodecanado" },
    ["_hitEffectPortal"] = { Rarity = "Mythical", DisplayName = "Portal" },
    ["_hitEffectRelude"] = { Rarity = "Mythical", DisplayName = "Relude" },
    ["_hitEffectSaintMarked"] = { Rarity = "Mythical", DisplayName = "Saint Marked" },
}

-- Embedded fallback templates for the 11 confirmed Mythicals.
-- These make them playable even when the current server does not contain the template
-- and Gemini/GitHub forgot to publish effects_CORRECTED_MYTHICS.txt.
-- Mythical payloads are hosted in effect_master/effects and loaded on demand.
local function serializedFromRawValue(rawVal)
    if type(rawVal) == "table" then
        return rawVal.Serialized or rawVal.Data or rawVal.Effect
    elseif type(rawVal) == "string" then
        return rawVal
    end
    return nil
end

function Module.cleanEffectName(rawName)
    local exact = EXACT_EFFECT_METADATA[rawName]
    if exact and exact.DisplayName then
        return exact.DisplayName
    end

    local name = rawName:gsub("^_hitEffect", ""):gsub("^_spawnEffect", ""):gsub("^_killEffect", ""):gsub("^SpawnEffect", ""):gsub("^HitEffect", "")
    name = name:gsub("(%l)(%u)", "%1 %2")
    return name
end

function Module.getEffectRarity(rawName)
    local exact = EXACT_EFFECT_METADATA[rawName]
    if exact then
        return "Mythical"
    end
    return RARITY_MAP[rawName] or "Rare"
end

function Module.getRarityHex(rarity)
    local r = RARITY[rarity] or RARITY.Unknown
    return r.Hex
end

function Module.getEffectImage(id)
    return EFFECT_TEXTURE_MAP[id] or "rbxassetid://10849912178"
end

local function sortCatalog(list)
    table_sort(list, function(a, b)
        local rankA = (RARITY[a.Rarity] or RARITY.Unknown).Rank
        local rankB = (RARITY[b.Rarity] or RARITY.Unknown).Rank
        if rankA ~= rankB then
            return rankA < rankB
        end
        return a.Name < b.Name
    end)
end

local function addDisplayEntry(entry, displayStrings, lookup)
    local hex = Module.getRarityHex(entry.Rarity)
    local displayStr = string.format("<font color=\"%s\">[%s]</font> %s", hex, entry.Rarity, entry.Name)
    local plainStr = string.format("[%s] %s", entry.Rarity, entry.Name)
    entry.DisplayString = displayStr
    entry.Image = Module.getEffectImage(entry.ItemID)
    table_insert(displayStrings, displayStr)
    lookup[displayStr] = entry
    lookup[plainStr] = entry
    lookup[entry.Name] = entry
    lookup[entry.ItemID] = entry
    Controller.DisplayToEntryMap[displayStr] = entry
    Controller.DisplayToEntryMap[plainStr] = entry
    Controller.DisplayToEntryMap[entry.Name] = entry
    Controller.DisplayToEntryMap[entry.ItemID] = entry
end

function Module.rebuildDisplayStrings(force)
    if not force and not displayDirty then
        return false
    end

    if force then
        dirtyCategories.Hit = true
        dirtyCategories.Spawn = true
        dirtyCategories.Kill = true
    end

    if dirtyCategories.Hit then
        sortCatalog(Controller.CatalogHit)
        table.clear(Controller.HitDisplayStrings)
        table.clear(Controller.HitDisplayLookup)
        for _, entry in ipairs(Controller.CatalogHit) do
            addDisplayEntry(entry, Controller.HitDisplayStrings, Controller.HitDisplayLookup)
        end
        Controller.HitDisplayRevision = Controller.HitDisplayRevision + 1
    end

    if dirtyCategories.Spawn then
        sortCatalog(Controller.CatalogSpawn)
        table.clear(Controller.SpawnDisplayStrings)
        table.clear(Controller.SpawnDisplayLookup)
        for _, entry in ipairs(Controller.CatalogSpawn) do
            addDisplayEntry(entry, Controller.SpawnDisplayStrings, Controller.SpawnDisplayLookup)
        end
        Controller.SpawnDisplayRevision = Controller.SpawnDisplayRevision + 1
    end

    if dirtyCategories.Kill then
        sortCatalog(Controller.CatalogKill)
        table.clear(Controller.KillDisplayStrings)
        table.clear(Controller.KillDisplayLookup)
        for _, entry in ipairs(Controller.CatalogKill) do
            addDisplayEntry(entry, Controller.KillDisplayStrings, Controller.KillDisplayLookup)
        end
        Controller.KillDisplayRevision = Controller.KillDisplayRevision + 1
    end

    local defaultHit = Controller.CatalogByID["_hitEffectDefault"]
        or Controller.CatalogByID["_hitEffectDefaultReworked"]
    local defaultSpawn = Controller.CatalogByID["_spawnEffectDefault"]

    if not Controller.SelectedHitEffect and defaultHit then
        Controller.SelectedHitEffect = defaultHit
    end
    if not Controller.SelectedDeathEffect and defaultHit then
        Controller.SelectedDeathEffect = defaultHit
    end
    if not Controller.SelectedKillVisualEffect and defaultHit then
        Controller.SelectedKillVisualEffect = defaultHit
    end
    if not Controller.SelectedSpawnEffect and defaultSpawn then
        Controller.SelectedSpawnEffect = defaultSpawn
    end
    displayDirty = false
    dirtyCategories.Hit = false
    dirtyCategories.Spawn = false
    dirtyCategories.Kill = false
    Controller.CatalogRevision = Controller.CatalogRevision + 1
    return true
end

function Module.isDisplayDirty()
    return displayDirty
end

local function shouldReplaceSerialized(existing, candidate)
    if type(candidate) ~= "string" or candidate == "" or candidate == "nil" then return false end
    if type(existing) ~= "string" or existing == "" or existing == "nil" then return true end
    local candidateIsV2 = candidate:sub(1, 5) == "FXS2:"
    local existingIsV2 = existing:sub(1, 5) == "FXS2:"
    if candidateIsV2 and not existingIsV2 then return true end
    if not candidateIsV2 then return false end

    local function getVersion(value)
        local ok, document = pcall(HttpService.JSONDecode, HttpService, value:sub(6))
        return ok and type(document) == "table" and tonumber(document.Version) or 0
    end
    return getVersion(candidate) > getVersion(existing)
end

function Module.registerCatalogItem(category, id, name, rarity, instance, serialized)
    if category == "KillEffect" and not isAllowedSpecialKill(id) then
        return nil
    end

    if Controller.CatalogByID[id] then
        local entry = Controller.CatalogByID[id]
        local metadataChanged = false

        local exact = EXACT_EFFECT_METADATA[id]
        if exact then
            name = exact.DisplayName
            rarity = "Mythical"
        end

        if type(name) == "string" and name ~= "" and entry.Name ~= name then
            if Controller.CatalogByName[entry.Name] == entry then
                Controller.CatalogByName[entry.Name] = nil
            end
            entry.Name = name
            Controller.CatalogByName[name] = entry
            metadataChanged = true
        end

        if type(rarity) == "string" and rarity ~= "" and entry.Rarity ~= rarity then
            entry.Rarity = rarity
            entry.Rank = (RARITY[rarity] or RARITY.Unknown).Rank
            metadataChanged = true
        end

        mergeRouteSupport(entry, serialized, instance, category)
        if shouldReplaceSerialized(Controller.CloudCache[id], serialized) then
            Controller.CloudCache[id] = serialized
        end
        if instance then
            Controller.InstanceCache[id] = instance
        end

        if metadataChanged then
            displayDirty = true
            if entry.Category == "SpawnEffect" then
                dirtyCategories.Spawn = true
            elseif entry.Category == "KillEffect" then
                dirtyCategories.Kill = true
            else
                dirtyCategories.Hit = true
            end
        end
        return entry
    end

    local exact = EXACT_EFFECT_METADATA[id]
    if exact then
        name = exact.DisplayName
        rarity = "Mythical"
    end

    local entry = {
        Category = category,
        ItemID = id,
        Name = name,
        Rarity = rarity,
        Rank = (RARITY[rarity] or RARITY.Unknown).Rank,
        DisplayString = "",
        Image = Module.getEffectImage(id),
    }
    mergeRouteSupport(entry, serialized, instance, category)

    if category == "HitEffect" then
        table_insert(Controller.CatalogHit, entry)
    elseif category == "SpawnEffect" then
        table_insert(Controller.CatalogSpawn, entry)
    elseif category == "KillEffect" then
        table_insert(Controller.CatalogKill, entry)
    end

    Controller.CatalogByID[id] = entry
    Controller.CatalogByName[name] = entry

    if instance then
        Controller.InstanceCache[id] = instance
    end

    if shouldReplaceSerialized(Controller.CloudCache[id], serialized) then
        Controller.CloudCache[id] = serialized
    end

    displayDirty = true
    if category == "SpawnEffect" then
        dirtyCategories.Spawn = true
    elseif category == "KillEffect" then
        dirtyCategories.Kill = true
    else
        dirtyCategories.Hit = true
    end
    return entry
end

function Module.loadMasterDatabase()
    -- Local special implementations remain registered even if both databases fail.
    Module.registerCatalogItem("HitEffect", "_hitEffectTestingHack", "TestingHack", "Special")
    Module.registerCatalogItem("HitEffect", "_hitEffectTheParasite", "The Parasite", "Legendary")
    Module.registerCatalogItem("HitEffect", "_hitEffectBarzilPortalVortex", "Brazil Portal", "Rare")
    Module.registerCatalogItem("HitEffect", "_hitEffectBrainFog", "Brain Fog", "Rare")
    Module.registerCatalogItem("KillEffect", "_hitEffectStaffRave", "Staff Rave", "Special")
    Module.registerCatalogItem("KillEffect", "_hitEffectKittyKatastrophe", "Kitty Katastrophe", "Special")

    local function fetchText(url)
        if type(url) ~= "string" or url == "" then return nil end
        local separator = url:find("?", 1, true) and "&" or "?"
        local finalURL = url .. separator .. "v=20260823v16_" .. tostring(os.time())
        local ok, body = pcall(function()
            return game:HttpGet(finalURL)
        end)
        if ok and type(body) == "string" and body ~= "" then
            return body
        end
        return nil
    end

    local function decodeJSON(raw)
        if type(raw) ~= "string" or raw == "" then return nil end
        local ok, parsed = pcall(HttpService.JSONDecode, HttpService, raw)
        return ok and type(parsed) == "table" and parsed or nil
    end

    -- bebebe/secret remains the private/fresh master source.
    local secretDB = decodeJSON(fetchText(GITHUB_SECRET_URL)) or {}
    local hitEffects = secretDB.HitEffects or {}
    local spawnEffects = secretDB.SpawnEffects or {}
    local killEffects = secretDB.KillEffects or {}
    local metadata = secretDB.EffectMetadata or {}
    local rarityMap = secretDB.RarityMap or {}
    local displayNames = secretDB.DisplayNames or {}

    local function unpackEffect(id, rawVal)
        local serialized = serializedFromRawValue(rawVal)
        local name
        local rarity

        if type(rawVal) == "table" then
            name = rawVal.DisplayName or rawVal.Name
            rarity = rawVal.Rarity
        end

        local meta = metadata[id]
        if type(meta) == "table" then
            name = meta.DisplayName or meta.Name or name
            rarity = meta.Rarity or rarity
        end

        name = displayNames[id] or name or Module.cleanEffectName(id)
        rarity = rarityMap[id] or rarity or Module.getEffectRarity(id)

        local exact = EXACT_EFFECT_METADATA[id]
        if exact then
            name = exact.DisplayName
            rarity = "Mythical"
        end

        return serialized, name, rarity
    end

    -- Register whatever secret already contains first. FXS2 from secret therefore
    -- remains the preferred payload whenever it exists.
    for id, rawVal in pairs(hitEffects) do
        local isStaff = (id == "_hitEffectStaffRave")
        local isKitty = (id == "_hitEffectKittyKatastrophe")
        local serialized, rName, rRarity = unpackEffect(id, rawVal)
        if isStaff or isKitty then
            Module.registerCatalogItem(
                "KillEffect",
                id,
                isStaff and "Staff Rave" or "Kitty Katastrophe",
                "Special",
                nil,
                serialized
            )
        else
            Module.registerCatalogItem("HitEffect", id, rName, rRarity, nil, serialized)
        end
    end

    for id, rawVal in pairs(spawnEffects) do
        if not id:lower():find("staffrave", 1, true) then
            local serialized, rName, rRarity = unpackEffect(id, rawVal)
            Module.registerCatalogItem("SpawnEffect", id, rName, rRarity, nil, serialized)
        end
    end

    for id, rawVal in pairs(killEffects) do
        if isAllowedSpecialKill(id) then
            local serialized = serializedFromRawValue(rawVal)
            local normalized = id:lower():gsub("[^%w]", "")
            local isStaff = normalized:find("staffrave", 1, true) ~= nil
            Module.registerCatalogItem(
                "KillEffect",
                id,
                isStaff and "Staff Rave" or "Kitty Katastrophe",
                "Special",
                nil,
                serialized
            )
        end
    end

    -- Public index contains no giant payload strings. It maps every collected effect
    -- to a small server-side file which Storage downloads only when that effect is used.
    local publicIndex = decodeJSON(fetchText(PUBLIC_EFFECT_INDEX_URL))
    if publicIndex and type(publicIndex.Effects) == "table" then
        Controller.PublicEffectIndexLoaded = true
        Controller.PublicEffectIndexBuild = publicIndex.Build

        for id, info in pairs(publicIndex.Effects) do
            if type(info) == "table" and type(info.Path) == "string" and info.Path ~= "" then
                local category = info.Category == "SpawnEffect" and "SpawnEffect" or "HitEffect"
                local name = info.Name or Module.cleanEffectName(id)
                local rarity = info.Rarity or Module.getEffectRarity(id)

                local exact = EXACT_EFFECT_METADATA[id]
                if exact then
                    category = "HitEffect"
                    name = exact.DisplayName
                    rarity = "Mythical"
                end

                local entry = Module.registerCatalogItem(category, id, name, rarity, nil, nil)
                if entry then
                    entry.RemotePath = info.Path
                    entry.RemoteBytes = tonumber(info.Bytes) or 0
                    entry.RemoteSHA256 = info.SHA256
                    entry.RemoteFormat = info.Format
                    entry.RouteSupport = entry.RouteSupport or {}
                    if category == "HitEffect" then
                        entry.RouteSupport.Hit = true
                    elseif category == "SpawnEffect" then
                        entry.RouteSupport.Spawn = true
                    end
                end
            end
        end
    else
        Controller.PublicEffectIndexLoaded = false
    end

    -- Exact metadata wins even when an old secret/index contains stale Rare/Epic labels.
    for id, exact in pairs(EXACT_EFFECT_METADATA) do
        local entry = Controller.CatalogByID[id]
        if entry then
            Module.registerCatalogItem("HitEffect", id, exact.DisplayName, "Mythical", nil, nil)
        end
    end

    Module.rebuildDisplayStrings(true)
    return (#Controller.CatalogHit + #Controller.CatalogSpawn + #Controller.CatalogKill) > 0
end
return Module
