local Module = { VERSION = 16 }

local Controller
local Storage
local LocalPlayer
local Players
local Workspace
local TweenService
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local task_spawn = task.spawn
local task_wait = task.wait
local task_delay = task.delay
local table_insert = table.insert
local CFrame_new = CFrame.new
local Vector3_new = Vector3.new
local Color3_fromRGB = Color3.fromRGB
local Color3_fromHSV = Color3.fromHSV
local HARD_EFFECT_LIFETIME = 16
local MAX_AUTHORED_DURATION = 12
local MAX_MEANINGFUL_PARTICLE_TAIL = 6
local MAX_MEANINGFUL_TRAIL_TAIL = 5

local RAVE_COLORS = {
    Color3_fromRGB(160, 255, 26),
    Color3_fromRGB(79, 138, 255),
    Color3_fromRGB(208, 88, 255),
}

local STAFF_RAVE_AUDIO = {
    Kills = {
        [1] = "rbxassetid://71299190773673",
        [2] = "rbxassetid://137825396009934",
        [3] = "rbxassetid://120820616945192",
        [4] = "rbxassetid://95009362757592",
        [5] = "rbxassetid://100993421621893",
        [6] = "rbxassetid://81377095433373",
        [7] = "rbxassetid://112780995166130",
        [8] = "rbxassetid://71379539331952",
        [9] = "rbxassetid://119064918414337",
        [10] = "rbxassetid://106294560037046",
    },
    FinalRaveMusic = "rbxassetid://72723731837645",
    SpotlightOn = "rbxassetid://75412878528921",
    ElectricTalk = "rbxassetid://137199078646953",
    Trigger = "rbxassetid://138158608",
}

local KITTY_AUDIO = {
    Theme = "rbxassetid://97457082554006",
    KillDing = "rbxassetid://5650647283",
    KillBase = "rbxassetid://140479190682021",
}

local StaffRave = {
    Streak = 0,
    LastKill = 0,
    ResetGeneration = 0,
    BGM = nil,
    FinalSound = nil,
    RaveActive = false,
    LightingSnapshot = nil,
    ActiveConnections = {},
}

local Kitty = {
    Streak = 0,
    LastKill = 0,
    ResetGeneration = 0,
    BGM = nil,
    FadeTween = nil,
}
local ActiveSpecialSounds = {}

local function untrackSpecialSound(sound)
    for index = #ActiveSpecialSounds, 1, -1 do
        if ActiveSpecialSounds[index] == sound or not ActiveSpecialSounds[index].Parent then
            table.remove(ActiveSpecialSounds, index)
        end
    end
end

local function ensureSpawnFolder()
    local folder = Controller and Controller.SpawnFolder
    if folder and folder.Parent then
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = "__SBEffectVisuals"
    folder.Parent = Workspace
    Controller.SpawnFolder = folder
    return folder
end

local function play2DSound(soundId, volume, name, speed)
    if not soundId or soundId == "" then
        return nil
    end

    local sound = Instance.new("Sound")
    sound.Name = name or "__StaffRaveSound"
    sound.SoundId = soundId
    sound.Volume = volume or 1
    sound.PlaybackSpeed = speed or 1
    sound.Looped = false
    sound.Parent = SoundService
    table_insert(ActiveSpecialSounds, sound)

    pcall(function()
        sound.TimePosition = 0
        sound:Play()
    end)

    local endedConnection
    endedConnection = sound.Ended:Connect(function()
        if endedConnection then endedConnection:Disconnect() end
        untrackSpecialSound(sound)
        if sound.Parent and not sound.Looped then
            pcall(sound.Destroy, sound)
        end
    end)

    task_delay(35, function()
        if sound and sound.Parent and not sound.Looped then
            pcall(sound.Destroy, sound)
        end
        untrackSpecialSound(sound)
    end)

    return sound
end

local function stopStaffRaveBGM()
    if StaffRave.BGM then
        pcall(function()
            StaffRave.BGM:Stop()
            StaffRave.BGM:Destroy()
        end)
        StaffRave.BGM = nil
    end
end

local function saveLighting()
    return {
        ClockTime = Lighting.ClockTime,
        Brightness = Lighting.Brightness,
        OutdoorAmbient = Lighting.OutdoorAmbient,
    }
end

local function restoreLighting(snapshot)
    if not snapshot then return end
    pcall(function()
        Lighting.ClockTime = snapshot.ClockTime
        Lighting.Brightness = snapshot.Brightness
        Lighting.OutdoorAmbient = snapshot.OutdoorAmbient
    end)
end

local function resetStaffRave(restoreImmediately)
    StaffRave.ResetGeneration = StaffRave.ResetGeneration + 1
    StaffRave.Streak = 0
    StaffRave.LastKill = 0
    StaffRave.RaveActive = false
    stopStaffRaveBGM()

    for _, conn in ipairs(StaffRave.ActiveConnections) do
        pcall(conn.Disconnect, conn)
    end
    table.clear(StaffRave.ActiveConnections)

    if StaffRave.FinalSound then
        pcall(function()
            StaffRave.FinalSound:Stop()
            StaffRave.FinalSound:Destroy()
        end)
        StaffRave.FinalSound = nil
    end

    local snapshot = StaffRave.LightingSnapshot
    StaffRave.LightingSnapshot = nil
    if snapshot then
        if restoreImmediately == false then
            pcall(function()
                TweenService:Create(
                    Lighting,
                    TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    snapshot
                ):Play()
            end)
        else
            restoreLighting(snapshot)
        end
    end
end

local function resetKitty(immediate)
    Kitty.ResetGeneration = Kitty.ResetGeneration + 1
    Kitty.Streak = 0
    Kitty.LastKill = 0

    if Kitty.FadeTween then
        pcall(Kitty.FadeTween.Cancel, Kitty.FadeTween)
        Kitty.FadeTween = nil
    end

    if Kitty.BGM then
        local bgm = Kitty.BGM
        Kitty.BGM = nil
        if immediate == false and bgm.Parent then
            local tween = TweenService:Create(
                bgm,
                TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { Volume = 0, PlaybackSpeed = 0.5 }
            )
            Kitty.FadeTween = tween
            tween:Play()
            task_delay(2.05, function()
                if bgm.Parent then pcall(bgm.Destroy, bgm) end
                if Kitty.FadeTween == tween then Kitty.FadeTween = nil end
            end)
        else
            pcall(bgm.Destroy, bgm)
        end
    end

    if LocalPlayer then
        pcall(LocalPlayer.SetAttribute, LocalPlayer, "BobaKills", 0)
    end
end

local function makeNumberSequence(points)
    local keypoints = {}
    for _, point in ipairs(points) do
        table_insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2], point[3] or 0))
    end
    return NumberSequence.new(keypoints)
end

local function makeColorSequence(points)
    local keypoints = {}
    for _, point in ipairs(points) do
        table_insert(keypoints, ColorSequenceKeypoint.new(point[1], point[2]))
    end
    return ColorSequence.new(keypoints)
end

local function makeKittyEmitter(parent, spec)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = spec.Name
    emitter.Texture = spec.Texture
    emitter.Color = makeColorSequence(spec.Color)
    emitter.Size = makeNumberSequence(spec.Size)
    emitter.Transparency = makeNumberSequence({ { 0, 0 }, { 0.82, 0.12 }, { 1, 1 } })
    emitter.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
    emitter.SpreadAngle = Vector2.new(spec.Spread, spec.Spread)
    emitter.Lifetime = NumberRange.new(spec.Lifetime[1], spec.Lifetime[2])
    emitter.Drag = spec.Drag or 0
    emitter.Brightness = spec.Brightness or 5
    emitter.Rate = (spec.Rate or 0) * (Controller.ParticleDensity or 1)
    emitter.TimeScale = Controller.ParticleSpeed or 1
    emitter.LockedToPart = false
    emitter.Enabled = spec.Enabled == true

    if spec.Layout then
        pcall(function()
            emitter.FlipbookLayout = Enum.ParticleFlipbookLayout[spec.Layout]
            emitter.FlipbookMode = Enum.ParticleFlipbookMode[spec.Mode or "OneShot"]
            emitter.FlipbookFramerate = NumberRange.new(spec.Framerate[1], spec.Framerate[2])
            emitter.FlipbookBlendFrames = true
            emitter.FlipbookStartRandom = false
        end)
    end

    -- Parent only after flipbook configuration. An enabled emitter can release a
    -- full, uncropped sprite sheet in the single frame before these properties apply.
    emitter.Parent = parent

    if spec.Emit then
        emitter:Emit(math.max(1, math.floor(spec.Emit * (Controller.ParticleDensity or 1) + 0.5)))
    end
    return emitter
end

local function spawnKittyVisual(character)
    if not character then return end
    local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
    if not root or not root:IsA("BasePart") then return end

    local attachment = Instance.new("Attachment")
    attachment.Name = "__KittyKatastropheTrail"
    attachment.Parent = root

    local bodyFog = makeKittyEmitter(attachment, {
        Name = "BodyFog",
        Texture = "rbxassetid://12528455353",
        Layout = "Grid8x8",
        Mode = "Loop",
        Framerate = { 20, 24 },
        Color = {
            { 0, Color3_fromRGB(255, 120, 220) },
            { 1, Color3_fromRGB(255, 200, 240) },
        },
        Size = { { 0, 0.4 }, { 0.5, 2.0 }, { 1, 0 } },
        Speed = { 2, 6 },
        Spread = 180,
        Lifetime = { 1.2, 2.5 },
        Rate = 24,
        Enabled = true,
    })
    makeKittyEmitter(attachment, {
        Name = "Fire1",
        Texture = "rbxassetid://132537238667080",
        Layout = "Grid8x8",
        Mode = "OneShot",
        Framerate = { 24, 30 },
        Color = {
            { 0, Color3_fromRGB(255, 100, 210) },
            { 1, Color3_fromRGB(255, 50, 150) },
        },
        Size = { { 0, 0.5 }, { 0.4, 2.5 }, { 1, 0 } },
        Speed = { 4, 10 },
        Spread = 360,
        Lifetime = { 0.5, 0.9 },
        Drag = 2,
        Emit = 25,
    })
    makeKittyEmitter(attachment, {
        Name = "Triangle",
        Texture = "rbxassetid://13973317169",
        Layout = "Grid4x4",
        Mode = "OneShot",
        Framerate = { 20, 24 },
        Color = {
            { 0, Color3_fromRGB(255, 230, 130) },
            { 1, Color3_fromRGB(255, 180, 50) },
        },
        Size = { { 0, 0.3 }, { 0.3, 1.8 }, { 1, 0 } },
        Speed = { 10, 22 },
        Spread = 360,
        Lifetime = { 0.7, 1.2 },
        Drag = 3,
        Emit = 20,
    })
    makeKittyEmitter(attachment, {
        Name = "Squiggle",
        Texture = "rbxassetid://8733731095",
        Layout = "Grid4x4",
        Mode = "OneShot",
        Framerate = { 20, 24 },
        Color = {
            { 0, Color3_fromRGB(130, 230, 255) },
            { 1, Color3_fromRGB(50, 150, 255) },
        },
        Size = { { 0, 0.2 }, { 0.4, 1.5 }, { 1, 0 } },
        Speed = { 8, 18 },
        Spread = 360,
        Lifetime = { 0.6, 1.1 },
        Drag = 2.5,
        Emit = 15,
    })
    makeKittyEmitter(attachment, {
        Name = "Stars",
        Texture = "rbxassetid://1847258023",
        Color = {
            { 0, Color3_fromRGB(255, 120, 220) },
            { 0.5, Color3_fromRGB(255, 240, 150) },
            { 1, Color3_fromRGB(180, 255, 255) },
        },
        Size = { { 0, 0.2 }, { 0.4, 1.4 }, { 1, 0 } },
        Speed = { 12, 28 },
        Spread = 360,
        Lifetime = { 0.8, 1.5 },
        Drag = 3.5,
        Brightness = 15,
        Emit = 35,
    })

    local highlight = Instance.new("Highlight")
    highlight.Name = "__KittyKatastropheHighlight"
    highlight.FillColor = Color3_fromRGB(40, 40, 40)
    highlight.OutlineColor = Color3_fromRGB(255, 78, 225)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.Adornee = character
    highlight.Parent = character

    pcall(function()
        TweenService:Create(
            highlight,
            TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { FillTransparency = 1, OutlineTransparency = 1 }
        ):Play()
    end)

    task_delay(2.0, function()
        if bodyFog.Parent then bodyFog.Enabled = false end
    end)
    task_delay(4.55, function()
        if attachment.Parent then pcall(attachment.Destroy, attachment) end
        if highlight.Parent then pcall(highlight.Destroy, highlight) end
    end)
end

local function triggerKittyKill()
    local now = os.clock()
    if now - Kitty.LastKill > 20 then
        resetKitty(true)
    end
    Kitty.LastKill = now
    Kitty.Streak = math.clamp(Kitty.Streak + 1, 1, 10)
    Kitty.ResetGeneration = Kitty.ResetGeneration + 1
    local generation = Kitty.ResetGeneration

    if Kitty.FadeTween then
        pcall(Kitty.FadeTween.Cancel, Kitty.FadeTween)
        Kitty.FadeTween = nil
    end

    if not Kitty.BGM or not Kitty.BGM.Parent then
        local bgm = Instance.new("Sound")
        bgm.Name = "__KittyKillstreakBGM"
        bgm.SoundId = KITTY_AUDIO.Theme
        bgm.Looped = true
        bgm.Volume = 0
        bgm.Parent = SoundService
        pcall(bgm.Play, bgm)
        Kitty.BGM = bgm
    end

    local targetVolume = math.clamp(Kitty.Streak / 10, 0.1, 0.5) * (Controller.VFXVolume or 1)
    if Kitty.BGM and Kitty.BGM.Parent then
        pcall(function()
            TweenService:Create(Kitty.BGM, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
                Volume = targetVolume,
                PlaybackSpeed = 1,
            }):Play()
        end)
    end

    pcall(LocalPlayer.SetAttribute, LocalPlayer, "BobaKills", Kitty.Streak)
    play2DSound(KITTY_AUDIO.KillDing, 1.0 * (Controller.VFXVolume or 1), "__KittyKillDing")
    play2DSound(KITTY_AUDIO.KillBase, 0.85 * (Controller.VFXVolume or 1), "__KittyKillBase")
    spawnKittyVisual(LocalPlayer.Character)

    task_delay(20, function()
        if Kitty.ResetGeneration == generation and os.clock() - Kitty.LastKill >= 19.9 then
            resetKitty(false)
        end
    end)
end

local function attachRaveTrail(character)
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local center = Instance.new("Attachment")
    center.Name = "__StaffRaveTrail"
    center.Parent = hrp

    local aura = Instance.new("ParticleEmitter")
    aura.Name = "Aura"
    aura.Texture = "rbxassetid://15011468690"
    aura.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3_fromRGB(160, 255, 26)),
        ColorSequenceKeypoint.new(0.1, Color3_fromRGB(79, 138, 255)),
        ColorSequenceKeypoint.new(0.2, Color3_fromRGB(208, 88, 255)),
        ColorSequenceKeypoint.new(0.3, Color3_fromRGB(0, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3_fromRGB(0, 0, 0)),
    })
    aura.Rate = 15 * (Controller.ParticleDensity or 1)
    aura.Speed = NumberRange.new(0.002, 0.002)
    aura.Lifetime = NumberRange.new(0.5, 0.8)
    aura.Brightness = 10
    aura.EmissionDirection = Enum.NormalId.Top
    aura.Parent = center
    aura:Emit(15)

    local stars = Instance.new("ParticleEmitter")
    stars.Name = "Stars"
    stars.Texture = "rbxassetid://96999011872088"
    stars.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3_fromRGB(160, 255, 26)),
        ColorSequenceKeypoint.new(0.5, Color3_fromRGB(79, 138, 255)),
        ColorSequenceKeypoint.new(1, Color3_fromRGB(208, 88, 255)),
    })
    stars.Rate = 25 * (Controller.ParticleDensity or 1)
    stars.Speed = NumberRange.new(20, 50)
    stars.Lifetime = NumberRange.new(0.4, 0.7)
    stars.SpreadAngle = Vector2.new(360, 360)
    stars.Brightness = 30
    stars.Parent = center
    stars:Emit(25)

    task_delay(2.0, function()
        if aura and aura.Parent then aura.Enabled = false end
        if stars and stars.Parent then stars.Enabled = false end
        task_delay(0.8, function()
            if center.Parent then pcall(center.Destroy, center) end
        end)
    end)
end

local function applyRaveHighlight(character)
    if not character then return end
    local hl = Instance.new("Highlight")
    hl.Name = "__StaffRaveHL"
    hl.DepthMode = Enum.HighlightDepthMode.Occluded
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    local c = Color3_fromHSV(math.random(1, 10) / 10, 0.8, 1)
    hl.FillColor = c
    hl.OutlineColor = c
    hl.Adornee = character
    hl.Parent = character

    local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    task_spawn(function()
        for _ = 1, 6 do
            if not hl.Parent then break end
            local nextCol = Color3_fromHSV(math.random(1, 10) / 10, 0.8, 1)
            pcall(function()
                TweenService:Create(hl, tweenInfo, { FillColor = nextCol, OutlineColor = nextCol }):Play()
            end)
            task_wait(0.25)
        end
        if hl.Parent then
            local fade = TweenService:Create(hl, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
                FillTransparency = 1,
                OutlineTransparency = 1
            })
            fade:Play()
            fade.Completed:Wait()
            pcall(hl.Destroy, hl)
        end
    end)
end

local function spawnStaffRaveLightingBurst(targetCF)
    local pos = targetCF and targetCF.Position or Vector3_new(0, 10, 0)
    local folder = Controller.SpawnFolder
    if not folder or not folder.Parent then
        folder = Instance.new("Folder")
        folder.Name = "__SBEffectVisuals"
        folder.Parent = Workspace
        Controller.SpawnFolder = folder
    end

    local p = Instance.new("Part")
    p.Name = "__StaffRaveFlash"
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.Transparency = 1
    p.Size = Vector3_new(1, 1, 1)
    p.CFrame = CFrame_new(pos + Vector3_new(0, 3, 0))
    p.Parent = folder

    local light = Instance.new("PointLight")
    light.Color = RAVE_COLORS[math.random(1, #RAVE_COLORS)]
    light.Range = 80 * (Controller.VFXScale or 1)
    light.Brightness = 12 * (Controller.LightIntensity or 1)
    light.Shadows = false
    light.Parent = p

    TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Brightness = 0,
        Range = 0
    }):Play()

    task_delay(0.7, function()
        pcall(p.Destroy, p)
    end)
end

local function spawnStaffRaveFinalBurst(targetCF)
    local anchor = Instance.new("Part")
    anchor.Name = "__StaffRaveFinalBurst"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanTouch = false
    anchor.CanQuery = false
    anchor.Transparency = 1
    anchor.Size = Vector3_new(0.2, 0.2, 0.2)
    anchor.CFrame = targetCF or CFrame_new(0, 10, 0)
    anchor.Parent = ensureSpawnFolder()

    local attachment = Instance.new("Attachment")
    attachment.Parent = anchor

    local shockwave = Instance.new("ParticleEmitter")
    shockwave.Name = "FlatAura_ExpandingShockwave"
    shockwave.Texture = "rbxassetid://15011468690"
    shockwave.Color = makeColorSequence({
        { 0, RAVE_COLORS[1] },
        { 0.5, RAVE_COLORS[2] },
        { 1, RAVE_COLORS[3] },
    })
    shockwave.Size = makeNumberSequence({ { 0, 1 }, { 0.5, 12 }, { 1, 20 } })
    shockwave.Transparency = makeNumberSequence({ { 0, 0 }, { 0.6, 0.4 }, { 1, 1 } })
    shockwave.Lifetime = NumberRange.new(0.8, 1.2)
    shockwave.Speed = NumberRange.new(0)
    shockwave.Brightness = 10
    shockwave.Orientation = Enum.ParticleOrientation.FacingCamera
    shockwave.Parent = attachment
    pcall(function()
        shockwave.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
        shockwave.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
        shockwave.FlipbookFramerate = NumberRange.new(20, 24)
    end)
    shockwave:Emit(math.max(1, math.floor(3 * (Controller.ParticleDensity or 1) + 0.5)))

    local stars = Instance.new("ParticleEmitter")
    stars.Name = "RaveStars_Burst"
    stars.Texture = "rbxassetid://96999011872088"
    stars.Color = shockwave.Color
    stars.Size = makeNumberSequence({ { 0, 0.5 }, { 0.3, 2.5 }, { 1, 0 } })
    stars.Transparency = makeNumberSequence({ { 0, 0 }, { 0.8, 0.3 }, { 1, 1 } })
    stars.Speed = NumberRange.new(20, 50)
    stars.SpreadAngle = Vector2.new(360, 360)
    stars.Drag = 3
    stars.Lifetime = NumberRange.new(1.0, 1.6)
    stars.Brightness = 25
    stars.Parent = attachment
    stars:Emit(math.max(1, math.floor(60 * (Controller.ParticleDensity or 1) + 0.5)))

    local laugh = Instance.new("ParticleEmitter")
    laugh.Name = "LastLaughingDecal"
    laugh.Texture = "rbxassetid://119846436641484"
    laugh.Size = makeNumberSequence({ { 0, 2 }, { 0.5, 6 }, { 1, 0 } })
    laugh.Transparency = makeNumberSequence({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } })
    laugh.Speed = NumberRange.new(0)
    laugh.Lifetime = NumberRange.new(0.6, 0.8)
    laugh.Brightness = 15
    laugh.Parent = attachment
    pcall(function()
        laugh.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
        laugh.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
        laugh.FlipbookFramerate = NumberRange.new(16, 20)
    end)
    laugh:Emit(1)

    task_delay(1.8, function()
        if anchor.Parent then pcall(anchor.Destroy, anchor) end
    end)
end

local function triggerStaffRaveKill(targetCF)
    if StaffRave.RaveActive then return end

    local now = os.clock()
    if now - StaffRave.LastKill > 20 then
        StaffRave.Streak = 0
    end
    StaffRave.LastKill = now
    StaffRave.Streak = StaffRave.Streak + 1

    local currentStreak = math.clamp(StaffRave.Streak, 1, 10)
    StaffRave.ResetGeneration = StaffRave.ResetGeneration + 1
    local currentGen = StaffRave.ResetGeneration

    spawnStaffRaveLightingBurst(targetCF)

    if LocalPlayer.Character then
        applyRaveHighlight(LocalPlayer.Character)
        attachRaveTrail(LocalPlayer.Character)
    end

    local killSoundId = STAFF_RAVE_AUDIO.Kills[currentStreak]
    if killSoundId and killSoundId ~= "" then
        local vol = (currentStreak == 10 and 3.0 or 2.0) * (Controller.VFXVolume or 1)
        local sfx = play2DSound(killSoundId, vol, "__StaffRaveKillSFX_" .. tostring(currentStreak), 1)
        if sfx then
            task_delay(4.0, function()
                if sfx and sfx.Parent then pcall(sfx.Destroy, sfx) end
            end)
        end
    end

    if currentStreak < 10 then
        task_delay(20, function()
            if StaffRave.ResetGeneration == currentGen and not StaffRave.RaveActive then
                resetStaffRave()
            end
        end)
    else
        StaffRave.RaveActive = true
        stopStaffRaveBGM()

        if not StaffRave.LightingSnapshot then
            StaffRave.LightingSnapshot = saveLighting()
        end

        play2DSound(STAFF_RAVE_AUDIO.Trigger, 2.5 * (Controller.VFXVolume or 1), "__RaveTrigger", 0.8)
        play2DSound(STAFF_RAVE_AUDIO.ElectricTalk, 2.0 * (Controller.VFXVolume or 1), "__RaveElectricTalk")
        task_delay(1.2, function()
            if StaffRave.ResetGeneration == currentGen and StaffRave.RaveActive then
                play2DSound(STAFF_RAVE_AUDIO.SpotlightOn, 2.0 * (Controller.VFXVolume or 1), "__RaveSpotlightOn")
            end
        end)

        local finalSound = play2DSound(STAFF_RAVE_AUDIO.FinalRaveMusic, 1.8 * (Controller.VFXVolume or 1), "__StaffRaveFinal")
        StaffRave.FinalSound = finalSound
        spawnStaffRaveFinalBurst(targetCF)

        local duration = 21.728
        local startTime = os.clock()

        pcall(function()
            TweenService:Create(Lighting, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                ClockTime = 4,
                Brightness = 2.5,
            }):Play()
        end)

        local conn = RunService.RenderStepped:Connect(function()
            if StaffRave.ResetGeneration ~= currentGen then return end
            local elapsed = os.clock() - startTime
            if elapsed >= duration then return end

            local loudness = (finalSound and finalSound.Parent and finalSound.PlaybackLoudness) or 0
            local pulse = math.clamp(loudness / 450, 0, 1)
            local t = (elapsed / 0.5) + pulse
            local idx = (math.floor(t) % #RAVE_COLORS) + 1
            local nextIdx = (idx % #RAVE_COLORS) + 1
            local alpha = t % 1
            local smoothAlpha = alpha * alpha * (3 - 2 * alpha)
            local ambientCol = RAVE_COLORS[idx]:Lerp(RAVE_COLORS[nextIdx], smoothAlpha)
            ambientCol = ambientCol:Lerp(Color3.new(1, 1, 1), pulse * 0.08)

            pcall(function()
                Lighting.OutdoorAmbient = ambientCol
            end)
        end)
        table_insert(StaffRave.ActiveConnections, conn)

        task_delay(duration, function()
            if StaffRave.ResetGeneration == currentGen then
                resetStaffRave(false)
            end
        end)
    end
end

function Module.Init(deps)
    assert(type(deps) == "table", "VFX.Init: deps table required")
    Controller = assert(deps.Controller, "VFX.Init: Controller required")
    Storage = assert(deps.Storage, "VFX.Init: Storage required")
    LocalPlayer = assert(deps.LocalPlayer, "VFX.Init: LocalPlayer required")
    Players = deps.Players or game:GetService("Players")
    Workspace = deps.Workspace or game:GetService("Workspace")
    TweenService = deps.TweenService or game:GetService("TweenService")
    return Module
end

function Module.buildColorSequence(originalSequence)
    local mode = Controller.ColorMode
    local function sequence(c1, c2, c3)
        return ColorSequence.new({
            ColorSequenceKeypoint.new(0, c1),
            ColorSequenceKeypoint.new(0.5, c2),
            ColorSequenceKeypoint.new(1, c3),
        })
    end

    if mode == "Original" then
        return originalSequence
    elseif mode == "Static Custom Color" then
        local c = Controller.PrimaryColor
        return sequence(
            c:Lerp(Color3_fromRGB(255, 255, 255), 0.3),
            c,
            c:Lerp(Color3_fromRGB(0, 0, 0), 0.2)
        )
    elseif mode == "Dual Custom Gradient" then
        local c1 = Controller.PrimaryColor
        local c2 = Controller.SecondaryColor
        return sequence(c1, c1:Lerp(c2, 0.5), c2)
    elseif mode == "Animated Custom Gradient" then
        local t = (os.clock() * Controller.ShiftSpeed * 0.5) % 1
        local c1 = Controller.PrimaryColor
        local c2 = Controller.SecondaryColor
        local c3 = Controller.TertiaryColor
        local cur1 = c1:Lerp(c2, (math.sin(t * math.pi * 2) + 1) / 2)
        local cur2 = c2:Lerp(c3, (math.sin((t + 0.33) * math.pi * 2) + 1) / 2)
        local cur3 = c3:Lerp(c1, (math.sin((t + 0.66) * math.pi * 2) + 1) / 2)
        return sequence(cur1, cur2, cur3)
    elseif mode == "Rainbow Chroma Wave" then
        local hue = (os.clock() * Controller.ShiftSpeed * 0.5) % 1
        return sequence(
            Color3_fromHSV(hue, 0.85, 1),
            Color3_fromHSV((hue + 0.33) % 1, 0.9, 1),
            Color3_fromHSV((hue + 0.66) % 1, 0.9, 1)
        )
    elseif mode == "Random Burst" then
        local hue = math.random()
        return sequence(
            Color3_fromHSV(hue, 0.85, 1),
            Color3_fromHSV((hue + math.random(12, 42) / 100) % 1, 0.9, 1),
            Color3_fromHSV((hue + math.random(48, 82) / 100) % 1, 0.8, 1)
        )
    elseif mode == "Inferno" then
        return sequence(Color3_fromRGB(255, 235, 90), Color3_fromRGB(255, 80, 12), Color3_fromRGB(75, 0, 0))
    elseif mode == "Arctic" then
        return sequence(Color3_fromRGB(240, 255, 255), Color3_fromRGB(55, 195, 255), Color3_fromRGB(45, 65, 255))
    elseif mode == "Toxic" then
        return sequence(Color3_fromRGB(230, 255, 70), Color3_fromRGB(55, 255, 65), Color3_fromRGB(20, 85, 35))
    elseif mode == "Void" then
        return sequence(Color3_fromRGB(255, 80, 245), Color3_fromRGB(105, 30, 210), Color3_fromRGB(8, 0, 25))
    elseif mode == "Pastel Dream" then
        return sequence(Color3_fromRGB(255, 175, 220), Color3_fromRGB(165, 220, 255), Color3_fromRGB(205, 175, 255))
    end
    return originalSequence
end

local BRANCH_BY_MODE = {
    Hit = "_HIT_EFFECT",
    Kill = "_KILL_EFFECT",
    Death = "_DEATH_EFFECT",
    Spawn = "_SPAWN_EFFECT",
}

local MODE_BY_BRANCH = {}
for mode, branchName in pairs(BRANCH_BY_MODE) do
    MODE_BY_BRANCH[branchName] = mode
end

local function routeModeFromName(name)
    local direct = MODE_BY_BRANCH[name]
    if direct then return direct, true end

    local upper = tostring(name or ""):upper()
    for mode, marker in pairs(BRANCH_BY_MODE) do
        -- Covers captures such as _HIT_EFFECT_RANDOM without confusing
        -- normal effect IDs like _hitEffectPortal.
        if upper:sub(1, #marker) == marker then
            return mode, false
        end
    end
    return nil, false
end

local BranchCache = setmetatable({}, { __mode = "k" })

local DEFAULT_ACTIVE_DURATION = {
    Hit = 0.55,
    Kill = 0.75,
    Death = 0.75,
    Spawn = 1.00,
}

local KNOWN_FLIPBOOK_LAYOUTS = {
    ["119846436641484"] = Enum.ParticleFlipbookLayout.Grid2x2,
    ["13973317169"] = Enum.ParticleFlipbookLayout.Grid4x4,
    ["8733731095"] = Enum.ParticleFlipbookLayout.Grid4x4,
    ["84080826165670"] = Enum.ParticleFlipbookLayout.Grid4x4,
    ["134005434290423"] = Enum.ParticleFlipbookLayout.Grid4x4,
    ["89985994741496"] = Enum.ParticleFlipbookLayout.Grid4x4,
    ["15011468690"] = Enum.ParticleFlipbookLayout.Grid4x4,
    ["12528455353"] = Enum.ParticleFlipbookLayout.Grid8x8,
    ["132537238667080"] = Enum.ParticleFlipbookLayout.Grid8x8,
    ["16867460128"] = Enum.ParticleFlipbookLayout.Grid8x8,
    ["77936528168048"] = Enum.ParticleFlipbookLayout.Grid8x8,
}

local WAVE_TEXTURE_IDS = {
    ["15011468690"] = true,
}

local FLIPBOOK_NAME_HINTS = {
    { "lastlaugh", Enum.ParticleFlipbookLayout.Grid2x2 },
    { "bodyfog", Enum.ParticleFlipbookLayout.Grid8x8 },
    { "fire1", Enum.ParticleFlipbookLayout.Grid8x8 },
    { "firetrail", Enum.ParticleFlipbookLayout.Grid8x8 },
    { "smoke circle", Enum.ParticleFlipbookLayout.Grid8x8 },
    { "triangle", Enum.ParticleFlipbookLayout.Grid4x4 },
    { "squiggle", Enum.ParticleFlipbookLayout.Grid4x4 },
    { "flataura", Enum.ParticleFlipbookLayout.Grid4x4 },
    { "vortex", Enum.ParticleFlipbookLayout.Grid4x4 },
    { "pulsing star", Enum.ParticleFlipbookLayout.Grid4x4 },
    { "kitty", Enum.ParticleFlipbookLayout.Grid4x4 },
    { "cat", Enum.ParticleFlipbookLayout.Grid4x4 },
}

local FLIPBOOK_FRAME_COUNTS = {
    [Enum.ParticleFlipbookLayout.Grid2x2] = 4,
    [Enum.ParticleFlipbookLayout.Grid4x4] = 16,
    [Enum.ParticleFlipbookLayout.Grid8x8] = 64,
}

local WAVE_NAME_HINTS = {
    "wave", "shock", "ripple", "ring", "ground", "floor", "flataura",
    "flat aura", "circle", "vortex", "pulse", "blast",
}

local function normalizeFlipbook(emitter)
    local layout = emitter.FlipbookLayout
    if layout == Enum.ParticleFlipbookLayout.None then
        local size = (emitter.FlipbookSizeX == emitter.FlipbookSizeY) and emitter.FlipbookSizeX or nil
        local inferred = size == 2 and Enum.ParticleFlipbookLayout.Grid2x2
            or size == 4 and Enum.ParticleFlipbookLayout.Grid4x4
            or size == 8 and Enum.ParticleFlipbookLayout.Grid8x8
            or KNOWN_FLIPBOOK_LAYOUTS[tostring(emitter.Texture):match("%d+") or ""]
        if not inferred then
            local lowerName = emitter.Name:lower()
            for _, hint in ipairs(FLIPBOOK_NAME_HINTS) do
                if lowerName:find(hint[1], 1, true) then
                    inferred = hint[2]
                    break
                end
            end
        end
        if inferred then
            pcall(function() emitter.FlipbookLayout = inferred end)
            layout = emitter.FlipbookLayout
        end
    end

    local frameCount = FLIPBOOK_FRAME_COUNTS[layout]
    if not frameCount then return false, 0, 0 end

    local framerate = emitter.FlipbookFramerate
    if framerate.Max < 1 then
        local fallback = frameCount >= 64 and 24 or 20
        pcall(function() emitter.FlipbookFramerate = NumberRange.new(fallback, fallback + 4) end)
        framerate = emitter.FlipbookFramerate
    end
    pcall(function()
        emitter.FlipbookBlendFrames = true
        emitter.FlipbookStartRandom = false
    end)

    local slowestRate = math.max(1, framerate.Min)
    local cycleDuration = frameCount / slowestRate
    local lifetime = emitter.Lifetime
    if lifetime.Min < cycleDuration or lifetime.Max < cycleDuration then
        pcall(function()
            emitter.Lifetime = NumberRange.new(
                math.max(lifetime.Min, cycleDuration),
                math.max(lifetime.Max, cycleDuration)
            )
        end)
    end
    return true, cycleDuration, frameCount
end

local function indexEffectTree(root)
    local cached = BranchCache[root]
    if cached then return cached end

    local index = {
        Branches = {},
        Depths = {},
        Priorities = {},
        HasNamedBranch = false,
        Tree = { root },
    }

    local function consider(instance, depth)
        local mode, exactName = routeModeFromName(instance.Name)
        if not mode then return end

        index.HasNamedBranch = true
        local priority = exactName and 0 or 1
        local oldPriority = index.Priorities[mode]
        local oldDepth = index.Depths[mode]

        if oldPriority == nil
            or priority < oldPriority
            or (priority == oldPriority and (oldDepth == nil or depth < oldDepth))
        then
            index.Branches[mode] = instance
            index.Depths[mode] = depth
            index.Priorities[mode] = priority
        end
    end

    consider(root, 0)
    for _, descendant in ipairs(root:GetDescendants()) do
        table_insert(index.Tree, descendant)
        local mode = routeModeFromName(descendant.Name)
        if mode then
            local depth = 0
            local current = descendant
            while current and current ~= root do
                depth += 1
                current = current.Parent
            end
            consider(descendant, depth)
        end
    end

    BranchCache[root] = index
    return index
end

local function findEffectBranch(root, mode)
    if not root or not BRANCH_BY_MODE[mode] then return nil end
    return indexEffectTree(root).Branches[mode]
end

local function resolveEffectBranch(root, mode, exactOnly)
    local exact = findEffectBranch(root, mode)
    if exact then return exact, true end

    if exactOnly then return nil, false end

    -- IMPORTANT: many real HitEffect packages keep the hit visuals directly
    -- under the package root while only Death/Kill have named containers.
    -- Old code rejected those packages completely, causing "Effect unavailable".
    if mode == "Hit" then
        return root, false
    end

    -- Spawn captures without a _SPAWN_EFFECT wrapper are also valid root packages.
    if mode == "Spawn" and not indexEffectTree(root).HasNamedBranch then
        return root, false
    end

    -- Death/Kill inherit the exact hit branch when one exists.
    if mode == "Death" or mode == "Kill" then
        local hitFallback = findEffectBranch(root, "Hit")
        if hitFallback then return hitFallback, false end

        -- Legacy package with no named route at all: reuse root.
        if not indexEffectTree(root).HasNamedBranch then
            return root, false
        end
    end

    return nil, false
end

local function resolveCharacter(target)
    if typeof(target) ~= "Instance" then return nil end
    if target:IsA("Player") then return target.Character end
    if target:IsA("Model") then return target end
    return target:FindFirstAncestorOfClass("Model")
end

local function createSpecialAnchor(targetCF, name)
    local anchor = Instance.new("Part")
    anchor.Name = name
    anchor.Size = Vector3_new(0.2, 0.2, 0.2)
    anchor.CFrame = targetCF
    anchor.Transparency = 1
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanTouch = false
    anchor.CanQuery = false
    anchor.CastShadow = false
    anchor.Parent = ensureSpawnFolder()
    return anchor
end

local function makeSpecialEmitter(parent, spec)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = spec.Name or "LegacyEmitter"
    emitter.Texture = spec.Texture
    emitter.Color = spec.Color or ColorSequence.new(Color3.new(1, 1, 1))
    emitter.Size = makeNumberSequence(spec.Size or { { 0, 0.3 }, { 0.4, 1.8 }, { 1, 0 } })
    emitter.Transparency = makeNumberSequence(spec.Transparency or { { 0, 0 }, { 0.82, 0.12 }, { 1, 1 } })
    emitter.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
    emitter.SpreadAngle = Vector2.new(spec.Spread or 360, spec.Spread or 360)
    emitter.Lifetime = NumberRange.new(spec.Lifetime[1], spec.Lifetime[2])
    emitter.Drag = spec.Drag or 0
    emitter.Brightness = spec.Brightness or 5
    emitter.Rate = (spec.Rate or 0) * (Controller.ParticleDensity or 1)
    emitter.TimeScale = math.max(0.05, Controller.ParticleSpeed or 1)
    emitter.Enabled = true

    if spec.Layout then
        pcall(function()
            emitter.FlipbookLayout = Enum.ParticleFlipbookLayout[spec.Layout]
            emitter.FlipbookMode = Enum.ParticleFlipbookMode[spec.Mode or "Loop"]
            emitter.FlipbookFramerate = NumberRange.new(spec.Framerate[1], spec.Framerate[2])
            emitter.FlipbookBlendFrames = true
            emitter.FlipbookStartRandom = false
        end)
    end

    emitter.Parent = parent

    emitter:Emit(math.max(1, math.floor((spec.Emit or spec.Rate or 1) * (Controller.ParticleDensity or 1) + 0.5)))
    return emitter
end

local function finishSpecialAnchor(anchor, activeDuration)
    local maxTail = 0.1
    local emitters = {}
    for _, descendant in ipairs(anchor:GetDescendants()) do
        if descendant:IsA("ParticleEmitter") then
            table_insert(emitters, descendant)
            maxTail = math.max(maxTail, descendant.Lifetime.Max / math.max(descendant.TimeScale, 0.05))
        end
    end
    task_delay(activeDuration, function()
        if not anchor.Parent then return end
        for _, emitter in ipairs(emitters) do
            if emitter.Parent then emitter.Enabled = false end
        end
        task_delay(maxTail + 0.1, function()
            if anchor.Parent then pcall(anchor.Destroy, anchor) end
        end)
    end)
end

local function playSpecialEnergized(targetCF)
    play2DSound("rbxassetid://1079408535", 1.8 * (Controller.VFXVolume or 1), "__EnergizedSFX")
    local anchor = createSpecialAnchor(targetCF, "__EnergizedBeam")
    local origin = Instance.new("Attachment")
    origin.Parent = anchor
    local high = Instance.new("Attachment")
    high.Position = Vector3_new(0, 50, 0)
    high.Parent = anchor
    local near = Instance.new("Attachment")
    near.Position = Vector3_new(0, 20, 0)
    near.Parent = anchor

    local function makeBeam(target, color, speed)
        local beam = Instance.new("Beam")
        beam.Texture = "rbxassetid://114861309026850"
        beam.TextureSpeed = speed
        beam.Color = ColorSequence.new(color)
        beam.LightEmission = 1
        beam.Brightness = 5
        beam.Width0 = 0
        beam.Width1 = 0
        beam.Attachment0 = origin
        beam.Attachment1 = target
        beam.Parent = origin
        return beam
    end

    local scale = Controller.VFXScale or 1
    local longBeam = makeBeam(high, Color3_fromRGB(0, 240, 255), 4)
    local shortBeam = makeBeam(near, Color3.new(1, 1, 1), 5)
    local function animate(beam, wide0, wide1)
        local grow = TweenService:Create(beam, TweenInfo.new(0.066), { Width0 = wide0 * scale, Width1 = wide1 * scale })
        grow:Play()
        grow.Completed:Once(function()
            local settle = TweenService:Create(beam, TweenInfo.new(0.183), { Width0 = wide0 * 0.1891 * scale, Width1 = wide1 * 0.1891 * scale })
            settle:Play()
            settle.Completed:Once(function()
                TweenService:Create(beam, TweenInfo.new(0.366), { Width0 = 0, Width1 = 0, Brightness = 0 }):Play()
            end)
        end)
    end
    animate(longBeam, 10, 20)
    animate(shortBeam, 20, 60)
    task_delay(0.7, function()
        if anchor.Parent then pcall(anchor.Destroy, anchor) end
    end)
end

local function playSpecialRelude(targetCF)
    play2DSound("rbxassetid://136680544819732", 1.8 * (Controller.VFXVolume or 1), "__ReludeSFX")
    local anchor = createSpecialAnchor(targetCF, "__ReludeGhost")
    local bottom = Instance.new("Attachment")
    bottom.Position = Vector3_new(0, -2.5, 0)
    bottom.Parent = anchor
    local top = Instance.new("Attachment")
    top.Position = Vector3_new(0, 2.5, 0)
    top.Parent = anchor
    local beam = Instance.new("Beam")
    beam.Texture = "rbxassetid://134005434290423"
    beam.Color = ColorSequence.new(Color3_fromRGB(200, 80, 255))
    beam.Width0 = 5 * (Controller.VFXScale or 1)
    beam.Width1 = beam.Width0
    beam.Attachment0 = bottom
    beam.Attachment1 = top
    beam.LightEmission = 1
    beam.Parent = anchor
    local fade = TweenService:Create(beam, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut), { Width0 = 0, Width1 = 0 })
    fade:Play()
    fade.Completed:Once(function()
        if anchor.Parent then pcall(anchor.Destroy, anchor) end
    end)
end

local function playSpecialDamned(targetCF)
    play2DSound("rbxassetid://165970390", 2 * (Controller.VFXVolume or 1), "__DamnedMeteorSFX")
    local basePos = targetCF.Position
    for index = 1, 3 do
        local angle = index * math.pi * 2 / 3
        local offset = Vector3_new(math.cos(angle) * 15, 20 + index * 3, math.sin(angle) * 15)
        local meteor = createSpecialAnchor(CFrame_new(basePos + offset), "__DamnedMeteor")
        meteor.Transparency = 0
        meteor.Size = Vector3_new(1.2, 1.2, 1.2) * (Controller.VFXScale or 1)
        meteor.Material = Enum.Material.Neon
        meteor.Color = Color3_fromRGB(255, 120, 30)
        makeSpecialEmitter(meteor, {
            Name = "FireTrail", Texture = "rbxassetid://132537238667080", Layout = "Grid8x8", Mode = "Loop",
            Framerate = { 24, 30 }, Color = makeColorSequence({ { 0, Color3_fromRGB(255, 230, 80) }, { 1, Color3_fromRGB(255, 40, 0) } }),
            Size = { { 0, 0.4 }, { 0.5, 2 }, { 1, 0 } }, Speed = { 2, 6 }, Spread = 45,
            Lifetime = { 0.4, 0.7 }, Rate = 20, Emit = 12,
        })
        TweenService:Create(meteor, TweenInfo.new(1), {
            Position = basePos + Vector3_new(math.random(-10, 10), 10, math.random(-10, 10)),
        }):Play()
        finishSpecialAnchor(meteor, 1)
    end
end

local function playSpecialRadial(targetCF, spec)
    play2DSound(spec.Sound, (spec.Volume or 1.8) * (Controller.VFXVolume or 1), "__" .. spec.Name .. "SFX")
    local anchor = createSpecialAnchor(targetCF, "__" .. spec.Name)
    for _, emitterSpec in ipairs(spec.Emitters) do
        makeSpecialEmitter(anchor, emitterSpec)
    end
    finishSpecialAnchor(anchor, spec.Duration or 2)
end

local function playSpecialTestingHack(targetCF, character)
    playSpecialRadial(targetCF, {
        Name = "TestingHack", Sound = "rbxassetid://137199078646953", Duration = 2,
        Emitters = {
            { Name = "Numbers", Texture = "rbxassetid://84080826165670", Layout = "Grid4x4", Mode = "Loop", Framerate = { 20, 24 }, Color = ColorSequence.new(Color3_fromRGB(0, 255, 180)), Size = { { 0, 0.3 }, { 0.4, 1.8 }, { 1, 0 } }, Speed = { 8, 20 }, Lifetime = { 0.8, 1.5 }, Drag = 3, Rate = 25, Emit = 30, Brightness = 8 },
            { Name = "Glitch", Texture = "rbxassetid://134005434290423", Layout = "Grid4x4", Mode = "Loop", Framerate = { 20, 24 }, Color = ColorSequence.new(Color3_fromRGB(0, 200, 255)), Size = { { 0, 0.3 }, { 0.4, 1.8 }, { 1, 0 } }, Speed = { 6, 16 }, Lifetime = { 0.7, 1.3 }, Drag = 2.5, Rate = 20, Emit = 20, Brightness = 4 },
        },
    })
    if character then
        local highlight = Instance.new("Highlight")
        highlight.Name = "__TestingHackHighlight"
        highlight.FillTransparency = 0.4
        highlight.OutlineTransparency = 0
        highlight.Adornee = character
        highlight.Parent = character
        task_spawn(function()
            for _ = 1, 5 do
                if not highlight.Parent then return end
                local color = Color3_fromHSV(math.random(150, 190) / 360, 0.9, 1)
                highlight.FillColor = color
                highlight.OutlineColor = color
                task_wait(0.2)
            end
            if highlight.Parent then
                local fade = TweenService:Create(highlight, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { FillTransparency = 1, OutlineTransparency = 1 })
                fade:Play()
                fade.Completed:Once(function()
                    if highlight.Parent then pcall(highlight.Destroy, highlight) end
                end)
            end
        end)
    end
end

local function playSpecialParasite(targetCF)
    playSpecialRadial(targetCF, {
        Name = "Parasite", Sound = "rbxassetid://2846734837", Duration = 2,
        Emitters = {
            { Name = "ScribbledX", Texture = "rbxassetid://89985994741496", Layout = "Grid4x4", Mode = "Loop", Framerate = { 20, 24 }, Color = ColorSequence.new(Color3_fromRGB(50, 255, 80)), Size = { { 0, 0.3 }, { 0.4, 2 }, { 1, 0 } }, Speed = { 10, 24 }, Lifetime = { 0.8, 1.4 }, Drag = 3, Rate = 20, Emit = 20, Brightness = 8 },
            { Name = "Spores", Texture = "rbxassetid://16867460128", Layout = "Grid8x8", Mode = "Loop", Framerate = { 24, 30 }, Color = ColorSequence.new(Color3_fromRGB(20, 200, 40)), Size = { { 0, 0.5 }, { 0.4, 3 }, { 1, 0 } }, Speed = { 8, 18 }, Lifetime = { 0.8, 1.4 }, Drag = 2.5, Rate = 20, Emit = 15, Brightness = 4 },
        },
    })
end

local function playSpecialBrazil(targetCF)
    playSpecialRadial(targetCF, {
        Name = "BrazilPortal", Sound = "rbxassetid://74611801200322", Volume = 2, Duration = 2,
        Emitters = {
            { Name = "PixelSmoke", Texture = "rbxassetid://77936528168048", Layout = "Grid8x8", Mode = "Loop", Framerate = { 20, 24 }, Color = makeColorSequence({ { 0, Color3_fromRGB(0, 255, 120) }, { 1, Color3_fromRGB(0, 150, 255) } }), Size = { { 0, 0.4 }, { 0.4, 2.5 }, { 1, 0 } }, Speed = { 10, 24 }, Lifetime = { 0.8, 1.5 }, Drag = 3, Rate = 25, Emit = 25, Brightness = 6 },
        },
    })
end

local function playSpecialBrainFog(targetCF)
    playSpecialRadial(targetCF, {
        Name = "BrainFog", Sound = "rbxassetid://9125440171", Duration = 2,
        Emitters = {
            { Name = "PsychicFog", Texture = "rbxassetid://16867460128", Layout = "Grid8x8", Mode = "Loop", Framerate = { 24, 30 }, Color = makeColorSequence({ { 0, Color3_fromRGB(220, 120, 255) }, { 1, Color3_fromRGB(120, 30, 255) } }), Size = { { 0, 0.5 }, { 0.4, 3 }, { 1, 0 } }, Speed = { 8, 20 }, Lifetime = { 0.8, 1.5 }, Drag = 2.5, Rate = 25, Emit = 25, Brightness = 6 },
        },
    })
end

local function playSpecialDiceTornado(targetCF)
    playSpecialRadial(targetCF, {
        Name = "DiceTornado", Sound = "rbxassetid://5799870105", Volume = 2, Duration = 2,
        Emitters = {
            { Name = "Vortex", Texture = "rbxassetid://15011468690", Layout = "Grid4x4", Mode = "Loop", Framerate = { 24, 30 }, Color = makeColorSequence({ { 0, Color3_fromRGB(0, 220, 255) }, { 0.5, Color3_fromRGB(255, 120, 255) }, { 1, Color3.new(1, 1, 1) } }), Size = { { 0, 1 }, { 0.5, 8 }, { 1, 0 } }, Speed = { 15, 30 }, Lifetime = { 0.8, 1.5 }, Drag = 3, Rate = 25, Emit = 30, Brightness = 8 },
        },
    })
end

local LEGACY_HIT_EFFECTS = {
    ["_hitEffectTestingHack"] = playSpecialTestingHack,
    ["_hitEffectTheParasite"] = playSpecialParasite,
    ["_hitEffectBarzilPortalVortex"] = playSpecialBrazil,
    ["_hitEffectBrainFog"] = playSpecialBrainFog,
}

-- Special killstreak routing is intentionally limited to Kitty Katastrophe
-- and Staff Rave. Normal kill visuals use the selected package's _KILL_EFFECT.
local LEGACY_KILL_EFFECTS = {}

local function belongsToBranch(instance, branch)
    if not branch then return true end
    return instance == branch or instance:IsDescendantOf(branch)
end

-- True for:
--   1) the selected route container and its descendants;
--   2) shared/root-level components which are not under ANY route container.
-- False for siblings belonging to Death/Kill/Spawn/Random route containers.
--
-- This fixes two opposite bugs from the old player:
--   * exact _HIT_EFFECT played but shared particles were silently skipped;
--   * using the whole root would also play _DEATH_EFFECT/_KILL_EFFECT together.
local function isPlaybackActive(instance, root, branch)
    if not instance or not root or not branch then return false end
    if instance == root then return true end

    local current = instance
    while current and current ~= root do
        local routeMode = routeModeFromName(current.Name)
        if routeMode then
            return current == branch
        end
        current = current.Parent
    end

    local rootRoute = routeModeFromName(root.Name)
    if rootRoute then
        return root == branch
    end

    -- No route ancestor => shared package content.
    return true
end

local function isWaveVisual(instance, branch)
    if instance:IsA("ParticleEmitter") then
        local textureID = tostring(instance.Texture):match("%d+")
        if textureID and WAVE_TEXTURE_IDS[textureID] then return true end
    end
    local current = instance
    while current do
        local lowerName = current.Name:lower()
        for _, hint in ipairs(WAVE_NAME_HINTS) do
            if lowerName:find(hint, 1, true) then return true end
        end
        if current == branch then break end
        current = current.Parent
    end
    return false
end

local function branchHasWorldWave(root, branch, tree)
    for _, instance in ipairs(tree) do
        if isPlaybackActive(instance, root, branch)
            and (instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail"))
            and isWaveVisual(instance, branch)
        then
            return true
        end
    end
    return false
end

local function isBranchStructure(instance, root, branch, active)
    if active then return true end
    if not branch or branch == root then return false end
    return branch:IsDescendantOf(instance)
end

local function readDurationHint(root, branch, mode, tree)
    local names = { "EmitDuration", "ActiveDuration", "EffectDuration", "Duration" }
    for _, source in ipairs({ branch, root }) do
        if source and isPlaybackActive(source, root, branch) then
            for _, name in ipairs(names) do
                local value = source:GetAttribute(name)
                if type(value) == "number" and value > 0 then
                    return math.clamp(value, 0.02, MAX_AUTHORED_DURATION)
                end
            end
        end
    end

    for _, descendant in ipairs(tree or indexEffectTree(root).Tree) do
        if isPlaybackActive(descendant, root, branch) and descendant:IsA("NumberValue") then
            local lowerName = descendant.Name:lower()
            if lowerName:find("duration", 1, true) and descendant.Value > 0 then
                return math.clamp(descendant.Value, 0.02, MAX_AUTHORED_DURATION)
            end
        end
    end

    return DEFAULT_ACTIVE_DURATION[mode] or 0.55
end

local function readTotalDurationHint(root, branch, tree)
    local names = {
        "TotalDuration", "PlaybackDuration", "CleanupDelay", "DestroyDelay",
        "DebrisTime", "TotalLifetime", "EffectLifetime",
    }
    local wanted = {}
    for _, name in ipairs(names) do wanted[name:lower()] = true end

    for _, source in ipairs({ branch, root }) do
        if source and isPlaybackActive(source, root, branch) then
            local okAttributes, attributes = pcall(source.GetAttributes, source)
            if okAttributes and type(attributes) == "table" then
                for name, value in pairs(attributes) do
                    if wanted[tostring(name):lower()] and type(value) == "number" and value > 0 then
                        return math.clamp(value, 0.05, HARD_EFFECT_LIFETIME - 0.25)
                    end
                end
            end
        end
    end

    for _, descendant in ipairs(tree or indexEffectTree(root).Tree) do
        if isPlaybackActive(descendant, root, branch)
            and (descendant:IsA("NumberValue") or descendant:IsA("IntValue"))
            and wanted[descendant.Name:lower()]
            and descendant.Value > 0
        then
            return math.clamp(descendant.Value, 0.05, HARD_EFFECT_LIFETIME - 0.25)
        end
    end

    return nil
end

local function readComponentNumber(instance, branch, names, fallback)
    local wanted = {}
    for _, name in ipairs(names) do wanted[name:lower()] = true end

    local current = instance
    while current do
        local okAttributes, attributes = pcall(current.GetAttributes, current)
        if okAttributes and type(attributes) == "table" then
            for name, value in pairs(attributes) do
                if wanted[tostring(name):lower()] and type(value) == "number" then
                    return value
                end
            end
        end
        for _, child in ipairs(current:GetChildren()) do
            if wanted[child.Name:lower()] and (child:IsA("NumberValue") or child:IsA("IntValue")) then
                return child.Value
            end
        end
        if current == branch then break end
        current = current.Parent
    end
    return fallback
end

local function repairLegacyAttachmentReferences(root, branch, tree)
    local attachments = {}
    for _, instance in ipairs(tree) do
        if instance:IsA("Attachment") and isPlaybackActive(instance, root, branch) then
            table_insert(attachments, instance)
        end
    end

    if #attachments < 2 then return end

    local function nearestAttachment(origin, excluded)
        local originPosition
        local okOrigin = pcall(function()
            originPosition = origin.WorldPosition
        end)
        if not okOrigin or not originPosition then return nil end

        local best
        local bestDistance = math.huge
        for _, candidate in ipairs(attachments) do
            if candidate ~= excluded and candidate ~= origin then
                local ok, position = pcall(function() return candidate.WorldPosition end)
                if ok and position then
                    local distance = (position - originPosition).Magnitude
                    if distance < bestDistance then
                        bestDistance = distance
                        best = candidate
                    end
                end
            end
        end
        return best
    end

    for _, instance in ipairs(tree) do
        if (instance:IsA("Beam") or instance:IsA("Trail"))
            and isPlaybackActive(instance, root, branch)
        then
            local attachment0 = instance.Attachment0
            local attachment1 = instance.Attachment1

            -- Legacy {Part,...} snapshots did not serialize Attachment0/1.
            -- Prefer the owning Attachment, then choose the closest other
            -- active Attachment as the opposite endpoint.
            if not attachment0 and instance.Parent and instance.Parent:IsA("Attachment") then
                attachment0 = instance.Parent
                pcall(function() instance.Attachment0 = attachment0 end)
            end

            if not attachment0 then
                attachment0 = attachments[1]
                pcall(function() instance.Attachment0 = attachment0 end)
            end

            if not attachment1 and attachment0 then
                attachment1 = nearestAttachment(attachment0, attachment0)
                if attachment1 then
                    pcall(function() instance.Attachment1 = attachment1 end)
                end
            end
        end
    end
end

function Module.spawnVisualCloneAt(template, targetCF, mode)
    Controller.LastVFXError = nil
    if not template or not targetCF then
        Controller.LastVFXError = "template or target CFrame is missing"
        return false
    end

    local templateBranch = resolveEffectBranch(template, mode, false)
    if not templateBranch then
        Controller.LastVFXError = "no compatible " .. tostring(mode) .. " route was found in the effect package"
        return false
    end
    local offsetY = Controller.VFXOffsetY or 0
    local rotationY = Controller.VFXRotationY or 0

    local ok, clone = pcall(template.Clone, template)
    if not ok or not clone then
        Controller.LastVFXError = "effect template could not be cloned"
        return false
    end

    local folder = ensureSpawnFolder()
    local branch, branchExact = resolveEffectBranch(clone, mode, false)
    if not branch then
        Controller.LastVFXError = "route disappeared after cloning"
        BranchCache[clone] = nil
        pcall(clone.Destroy, clone)
        return false
    end
    local indexedClone = indexEffectTree(clone)
    local tree = indexedClone.Tree
    local worldAligned = branchHasWorldWave(clone, branch, tree)
    if worldAligned then
        local position = targetCF.Position
        targetCF = CFrame_new(position.X, position.Y + offsetY, position.Z)
        if Controller.RandomOrientation then
            targetCF = targetCF * CFrame.Angles(0, math.rad(math.random(-180, 180)), 0)
        elseif rotationY ~= 0 then
            targetCF = targetCF * CFrame.Angles(0, math.rad(rotationY), 0)
        end
    else
        targetCF = targetCF * CFrame_new(0, offsetY, 0)
        if Controller.RandomOrientation then
            targetCF = targetCF * CFrame.Angles(
                math.rad(math.random(-180, 180)),
                math.rad(math.random(-180, 180)),
                math.rad(math.random(-180, 180))
            )
        elseif rotationY ~= 0 then
            targetCF = targetCF * CFrame.Angles(0, math.rad(rotationY), 0)
        end
    end
    local activeDuration = readDurationHint(clone, branch, mode, tree) * (Controller.EffectDurationScale or 1)
    activeDuration = math.clamp(activeDuration, 0.02, MAX_AUTHORED_DURATION)
    local totalDurationHint = readTotalDurationHint(clone, branch, tree)
    local visualParts = {}
    local activeEmitters = {}
    local activeBeams = {}
    local activeTrails = {}
    local activeLights = {}
    local activeHighlights = {}
    local activeAtmospherics = {}
    local activeSounds = {}
    local activeWaveEmitters = {}
    local externalInstances = {}
    local maxTail = 0.05
    local latestVisualEnd = math.max(activeDuration + maxTail, totalDurationHint or 0)
    local cleanupRoot = clone
    local flipbookInfo = {}
    -- Configure every emitter while the clone is still outside Workspace. This
    -- prevents enabled serialized emitters from releasing raw 2x2/4x4/8x8 sheets
    -- before the selected branch and flipbook mode have been resolved.
    for _, instance in ipairs(tree) do
        if instance:IsA("ParticleEmitter") then
            if instance:GetAttribute("__EffectOriginalEnabled") == nil then
                instance:SetAttribute("__EffectOriginalEnabled", instance.Enabled)
            end
            instance.Enabled = false
            local isFlipbook, cycleDuration, frameCount = normalizeFlipbook(instance)
            flipbookInfo[instance] = {
                IsFlipbook = isFlipbook,
                CycleDuration = cycleDuration,
                FrameCount = frameCount,
            }
        end
    end

    local function optimizePart(part, active)
        if not part:IsA("BasePart") then return end
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Massless = true
        part.CastShadow = false
        if not active then
            part.Transparency = 1
            return
        end
        if Controller.GeometryEnabled == false then
            part.Transparency = 1
        end
        if Controller.VFXScale ~= 1.0 then
            part.Size = part.Size * Controller.VFXScale
        end
        if part.Transparency < 1 then
            table_insert(visualParts, part)
        end
    end

    if clone:IsA("Model") then
        clone:PivotTo(targetCF)
        clone.Parent = folder
    elseif clone:IsA("BasePart") then
        -- Parenting Parts does not make child Parts inherit CFrame. Legacy effect
        -- packages often use a Part root with additional Part route containers.
        -- Preserve every child Part's transform relative to the captured root.
        local originalRootCF = clone.CFrame
        local relativeParts = {}
        for _, descendant in ipairs(tree) do
            if descendant ~= clone and descendant:IsA("BasePart") then
                local okRelative, relative = pcall(function()
                    return originalRootCF:ToObjectSpace(descendant.CFrame)
                end)
                if okRelative then
                    relativeParts[descendant] = relative
                end
            end
        end

        clone.CFrame = targetCF
        for part, relative in pairs(relativeParts) do
            pcall(function()
                part.CFrame = targetCF * relative
            end)
        end
        clone.Parent = folder
    else
        local anchor = Instance.new("Part")
        anchor.Name = "VFXAnchor"
        anchor.Size = Vector3_new(0.1, 0.1, 0.1)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanTouch = false
        anchor.CanQuery = false
        anchor.CFrame = targetCF
        anchor.Parent = folder
        clone.Parent = anchor
        cleanupRoot = anchor
    end

    -- Restore missing Beam/Trail endpoint references in old legacy dumps.
    repairLegacyAttachmentReferences(clone, branch, tree)

    local pendingSounds = 0
    local visualsFinished = false
    local destroyed = false

    local function destroyClone(force)
        if destroyed then return end
        if not force and (not visualsFinished or pendingSounds > 0) then return end
        destroyed = true
        BranchCache[clone] = nil
        for _, instance in ipairs(externalInstances) do
            if instance and instance.Parent then pcall(instance.Destroy, instance) end
        end
        if cleanupRoot and cleanupRoot.Parent then
            pcall(cleanupRoot.Destroy, cleanupRoot)
        end
    end

    -- A malformed asset or a looping sound must never leave a visual behind.
    task_delay(HARD_EFFECT_LIFETIME, function()
        destroyClone(true)
    end)

    local function enableForDuration(instance, delaySeconds, durationSeconds)
        instance.Enabled = false
        local function startComponent()
            if destroyed or not instance.Parent then return end
            instance.Enabled = true
            task_delay(durationSeconds, function()
                if instance.Parent then instance.Enabled = false end
            end)
        end
        if delaySeconds > 0 then
            task_delay(delaySeconds, startComponent)
        else
            startComponent()
        end
    end

    local function getComponentTiming(instance, tailSeconds)
        local delaySeconds = math.clamp(readComponentNumber(
            instance, branch, { "EmitDelay", "StartDelay", "PlayDelay", "Delay" }, 0
        ) or 0, 0, HARD_EFFECT_LIFETIME - 0.05)
        local durationHint = readComponentNumber(
            instance, branch, { "EmitDuration", "ActiveDuration", "EffectDuration", "Duration" }, nil
        )
        local durationSeconds
        if durationHint then
            durationSeconds = math.max(0.01, durationHint) * (Controller.EffectDurationScale or 1)
        else
            durationSeconds = activeDuration
        end
        durationSeconds = math.clamp(durationSeconds, 0.01, math.min(MAX_AUTHORED_DURATION, HARD_EFFECT_LIFETIME - delaySeconds))
        latestVisualEnd = math.max(latestVisualEnd, delaySeconds + durationSeconds + (tailSeconds or 0))
        return delaySeconds, durationSeconds
    end

    for _, instance in ipairs(tree) do
        local active = isPlaybackActive(instance, clone, branch)
        if active and instance:IsA("PostEffect") then
            instance.Enabled = false
            instance.Parent = Lighting
            table_insert(externalInstances, instance)
            local delaySeconds, durationSeconds = getComponentTiming(instance)
            enableForDuration(instance, delaySeconds, durationSeconds)
        elseif active and (instance:IsA("Sky") or instance:IsA("Atmosphere")) then
            instance.Parent = Lighting
            table_insert(externalInstances, instance)
            latestVisualEnd = math.max(latestVisualEnd, activeDuration)
        elseif active and instance:IsA("ScreenGui") then
            local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                instance.Enabled = true
                instance.Parent = playerGui
                table_insert(externalInstances, instance)
                latestVisualEnd = math.max(latestVisualEnd, activeDuration)
            end
        elseif active and instance:IsA("Explosion") then
            instance.Position = targetCF.Position
            latestVisualEnd = math.max(latestVisualEnd, 1)
        end
        if instance:IsA("BasePart") then
            optimizePart(instance, isBranchStructure(instance, clone, branch, active))
        end
        if instance:IsA("ParticleEmitter") then
            local originallyEnabled = instance:GetAttribute("__EffectOriginalEnabled")
            if originallyEnabled == nil then originallyEnabled = instance.Enabled end
            instance.Enabled = false

            if active and Controller.ParticlesEnabled ~= false then
                table_insert(activeEmitters, instance)
                if Controller.ColorMode ~= "Original" then
                    pcall(function() instance.Color = Module.buildColorSequence(instance.Color) end)
                end

                instance.TimeScale = math.max(0.05, instance.TimeScale * (Controller.ParticleSpeed or 1.0))
                local lifetimeScale = Controller.LifetimeScale or 1
                local velocityScale = Controller.VelocityScale or 1
                local rotationScale = Controller.RotationScale or 1
                local dragScale = Controller.DragScale or 1
                local spreadScale = Controller.SpreadScale or 1
                instance.Lifetime = NumberRange.new(
                    math.max(0.01, instance.Lifetime.Min * lifetimeScale),
                    math.max(0.01, instance.Lifetime.Max * lifetimeScale)
                )
                instance.Speed = NumberRange.new(instance.Speed.Min * velocityScale, instance.Speed.Max * velocityScale)
                instance.RotSpeed = NumberRange.new(instance.RotSpeed.Min * rotationScale, instance.RotSpeed.Max * rotationScale)
                instance.Drag = math.max(0, instance.Drag * dragScale)
                instance.SpreadAngle = instance.SpreadAngle * spreadScale
                local density = Controller.ParticleDensity or 1.0
                local authoredRate = math.max(0, instance.Rate)
                local oneShot = instance.FlipbookMode == Enum.ParticleFlipbookMode.OneShot
                local waveEmitter = isWaveVisual(instance, branch)
                local flipbook = flipbookInfo[instance]

                if waveEmitter and flipbook and flipbook.IsFlipbook and flipbook.CycleDuration > 0 then
                    latestVisualEnd = math.max(latestVisualEnd, math.min(
                        flipbook.CycleDuration + 0.05,
                        HARD_EFFECT_LIFETIME - 0.25
                    ))
                end

                local emitDelay = math.clamp(readComponentNumber(
                    instance, branch, { "EmitDelay", "StartDelay", "Delay" }, 0
                ) or 0, 0, HARD_EFFECT_LIFETIME - 0.05)
                local emitterDurationHint = readComponentNumber(
                    instance, branch, { "EmitDuration", "ActiveDuration", "EffectDuration", "Duration" }, nil
                )
                local emitterDuration = emitterDurationHint
                    and (math.max(0.01, emitterDurationHint) * (Controller.EffectDurationScale or 1))
                    or activeDuration
                emitterDuration = math.clamp(emitterDuration, 0.01, math.min(MAX_AUTHORED_DURATION, HARD_EFFECT_LIFETIME - emitDelay))
                local continuous = originallyEnabled and not oneShot and authoredRate > 0 and not waveEmitter
                local explicitCount = tonumber(readComponentNumber(
                    instance, branch, { "EmitCount", "ParticleCount", "BurstCount", "Amount", "Count" }, nil
                ))

                local function startEmitter()
                    if destroyed or not instance.Parent then return end
                    if continuous then
                        instance.Rate = authoredRate * density
                        instance.Enabled = true
                        if authoredRate * emitterDuration * density < 1 then
                            pcall(instance.Emit, instance, 1)
                        end
                        task_delay(emitterDuration, function()
                            if instance.Parent then instance.Enabled = false end
                        end)
                    else
                        local emitCount
                        if waveEmitter or oneShot then
                            emitCount = explicitCount or 1
                        elseif explicitCount then
                            emitCount = explicitCount
                        elseif authoredRate > 0 then
                            emitCount = math.max(1, math.floor(authoredRate * math.max(emitterDuration, 0.05) * density + 0.5))
                        else
                            emitCount = math.max(1, math.floor(8 * density + 0.5))
                        end
                        emitCount = math.clamp(math.floor(emitCount + 0.5), 1, waveEmitter and 1 or 120)
                        pcall(instance.Emit, instance, emitCount)
                    end
                end
                if emitDelay > 0 then task_delay(emitDelay, startEmitter) else startEmitter() end

                local rawParticleTail = instance.Lifetime.Max / math.max(instance.TimeScale, 0.05)
                local particleTail = math.min(rawParticleTail, MAX_MEANINGFUL_PARTICLE_TAIL)
                if flipbook and flipbook.IsFlipbook and flipbook.CycleDuration > 0 then
                    particleTail = math.max(
                        particleTail,
                        math.min(flipbook.CycleDuration + 0.05, MAX_MEANINGFUL_PARTICLE_TAIL)
                    )
                end
                maxTail = math.max(maxTail, particleTail)
                latestVisualEnd = math.max(
                    latestVisualEnd,
                    emitDelay + (continuous and emitterDuration or 0) + particleTail
                )
                if waveEmitter then
                    activeWaveEmitters[#activeWaveEmitters] = { Emitter = instance, Delay = emitDelay }
                end
            end
        elseif instance:IsA("Beam") then
            local componentActive = active and Controller.TrailsEnabled ~= false
            instance.Enabled = false
            if componentActive then
                table_insert(activeBeams, instance)
                if Controller.ColorMode ~= "Original" then
                    pcall(function() instance.Color = Module.buildColorSequence(instance.Color) end)
                end
                local delaySeconds, durationSeconds = getComponentTiming(instance)
                enableForDuration(instance, delaySeconds, durationSeconds)
            end
        elseif instance:IsA("Trail") then
            local componentActive = active and Controller.TrailsEnabled ~= false
            instance.Enabled = false
            if componentActive then
                table_insert(activeTrails, instance)
                local trailTail = math.min(math.max(0, instance.Lifetime), MAX_MEANINGFUL_TRAIL_TAIL)
                maxTail = math.max(maxTail, trailTail)
                if Controller.ColorMode ~= "Original" then
                    pcall(function() instance.Color = Module.buildColorSequence(instance.Color) end)
                end
                local delaySeconds, durationSeconds = getComponentTiming(instance, trailTail)
                enableForDuration(instance, delaySeconds, durationSeconds)
            end
        elseif instance:IsA("Light") then
            local componentActive = active and Controller.LightsEnabled ~= false and ((Controller.LightIntensity or 1.0) > 0)
            instance.Enabled = false
            if componentActive then
                table_insert(activeLights, instance)
                local targetBrightness = instance.Brightness * (Controller.LightIntensity or 1.0)
                instance.Brightness = 0
                if Controller.ColorMode ~= "Original" and Controller.PrimaryColor then
                    instance.Color = Controller.PrimaryColor
                end
                local delaySeconds, durationSeconds = getComponentTiming(instance)
                local function startLight()
                    if destroyed or not instance.Parent then return end
                    instance.Enabled = true
                    pcall(function()
                        TweenService:Create(instance, TweenInfo.new(math.min(0.15, durationSeconds), Enum.EasingStyle.Quad), {
                            Brightness = targetBrightness,
                        }):Play()
                    end)
                    task_delay(durationSeconds, function()
                        if instance.Parent then instance.Enabled = false end
                    end)
                end
                if delaySeconds > 0 then task_delay(delaySeconds, startLight) else startLight() end
            end
        elseif instance:IsA("Highlight") then
            local componentActive = active and Controller.HighlightsEnabled ~= false
            instance.Enabled = false
            if componentActive then
                table_insert(activeHighlights, instance)
                if Controller.ColorMode ~= "Original" then
                    instance.FillColor = Controller.PrimaryColor
                    instance.OutlineColor = Controller.SecondaryColor
                end
                local delaySeconds, durationSeconds = getComponentTiming(instance)
                enableForDuration(instance, delaySeconds, durationSeconds)
            end
        elseif instance:IsA("Smoke") or instance:IsA("Fire") or instance:IsA("Sparkles") then
            local componentActive = active and Controller.ParticlesEnabled ~= false
            instance.Enabled = false
            if componentActive then
                table_insert(activeAtmospherics, instance)
                if Controller.ColorMode ~= "Original" then
                    if instance:IsA("Smoke") then
                        instance.Color = Controller.PrimaryColor
                    elseif instance:IsA("Fire") then
                        instance.Color = Controller.PrimaryColor
                        instance.SecondaryColor = Controller.SecondaryColor
                    else
                        instance.SparkleColor = Controller.PrimaryColor
                    end
                end
                local delaySeconds, durationSeconds = getComponentTiming(instance, 0.5)
                enableForDuration(instance, delaySeconds, durationSeconds)
            end
        elseif instance:IsA("Sound") then
            pcall(instance.Stop, instance)
            if active and Controller.SoundsEnabled ~= false then
                table_insert(activeSounds, instance)
                instance.Volume = instance.Volume * (Controller.VFXVolume or 1.0)
                instance.PlaybackSpeed = math.clamp(instance.PlaybackSpeed * (Controller.SoundPitch or 1.0), 0.1, 4)
                local soundDelay = math.clamp(readComponentNumber(
                    instance, branch, { "SoundDelay", "PlayDelay", "EmitDelay", "StartDelay", "Delay" }, 0
                ) or 0, 0, HARD_EFFECT_LIFETIME - 0.05)
                local soundDuration = readComponentNumber(
                    instance, branch, { "SoundDuration", "PlayDuration", "EffectDuration", "Duration" }, nil
                )
                if soundDuration then
                    soundDuration = math.clamp(soundDuration, 0.05, HARD_EFFECT_LIFETIME - soundDelay)
                end
                pendingSounds = pendingSounds + 1
                local finished = false
                local connection
                local function finishSound()
                    if finished then return end
                    finished = true
                    if connection then connection:Disconnect() end
                    pcall(instance.Stop, instance)
                    pendingSounds = math.max(0, pendingSounds - 1)
                    destroyClone(false)
                end
                connection = instance.Ended:Connect(finishSound)
                local function startSound()
                    if destroyed or not instance.Parent then
                        finishSound()
                        return
                    end
                    pcall(instance.Play, instance)
                    if instance.Looped or soundDuration then
                        task_delay(soundDuration or math.max(0.05, HARD_EFFECT_LIFETIME - soundDelay), finishSound)
                    end
                end
                if soundDelay > 0 then task_delay(soundDelay, startSound) else startSound() end
                task_delay(HARD_EFFECT_LIFETIME, finishSound)
            end
        end
    end

    local visualEnd = math.clamp(latestVisualEnd, 0.05, HARD_EFFECT_LIFETIME - 0.05)
    local fadeDuration = math.clamp(maxTail * 0.25, 0.08, 0.3)
    local fadeStart = math.max(0, visualEnd - fadeDuration)
    task_delay(fadeStart, function()
        local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        for _, part in ipairs(visualParts) do
            if part.Parent then
                pcall(function() TweenService:Create(part, fadeInfo, { Transparency = 1 }):Play() end)
            end
        end
        for _, light in ipairs(activeLights) do
            if light.Parent then
                pcall(function() TweenService:Create(light, fadeInfo, { Brightness = 0 }):Play() end)
            end
        end
        for _, highlight in ipairs(activeHighlights) do
            if highlight.Parent then
                pcall(function()
                    TweenService:Create(highlight, fadeInfo, {
                        FillTransparency = 1,
                        OutlineTransparency = 1,
                    }):Play()
                end)
            end
        end
    end)

    task_delay(visualEnd + 0.05, function()
        for _, emitter in ipairs(activeEmitters) do
            if emitter and emitter.Parent then
                pcall(function()
                    emitter.Enabled = false
                    emitter:Clear()
                end)
            end
        end
        for _, trail in ipairs(activeTrails) do
            if trail and trail.Parent then
                pcall(function()
                    trail.Enabled = false
                    trail:Clear()
                end)
            end
        end
        for _, beam in ipairs(activeBeams) do
            if beam and beam.Parent then beam.Enabled = false end
        end
        for _, atmospheric in ipairs(activeAtmospherics) do
            if atmospheric and atmospheric.Parent then atmospheric.Enabled = false end
        end
        for _, light in ipairs(activeLights) do
            if light and light.Parent then light.Enabled = false end
        end
        for _, highlight in ipairs(activeHighlights) do
            if highlight and highlight.Parent then highlight.Enabled = false end
        end

        visualsFinished = true
        destroyClone(false)
    end)
    return true
end

function Module.getTargetCFrame(target)
    if not target then return nil end
    if typeof(target) == "CFrame" then return target end
    if typeof(target) == "Vector3" then return CFrame_new(target) end
    if typeof(target) == "Instance" then
        if target:IsA("Model") then
            local root = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head") or target:FindFirstChild("Torso") or target.PrimaryPart
            if root and root:IsA("BasePart") then return root.CFrame end
            return target:GetPivot()
        elseif target:IsA("BasePart") then
            return target.CFrame
        elseif target:IsA("Attachment") then
            return target.WorldCFrame
        elseif target:IsA("Player") and target.Character then
            return Module.getTargetCFrame(target.Character)
        end
    end
    return nil
end

function Module.playHitEffectOnCharacter(entry, victim, killer)
    if not entry then return false end
    local targetCF = Module.getTargetCFrame(victim)
    if not targetCF then return false end
    local special = LEGACY_HIT_EFFECTS[entry.ItemID]
    if special then
        special(targetCF, resolveCharacter(victim))
        return true
    end
    local template = Storage.ensureEffectInstanceLoaded(entry)
    if template then
        return Module.spawnVisualCloneAt(template, targetCF, "Hit")
    end
    return false
end

function Module.canPlayEffect(entry, mode, exactOnly)
    if not entry or not BRANCH_BY_MODE[mode] then return false end

    if LEGACY_HIT_EFFECTS[entry.ItemID] and mode ~= "Spawn" then
        return true
    end

    local template = Storage.ensureEffectInstanceLoaded(entry)
    if not template then return false end
    return resolveEffectBranch(template, mode, exactOnly == true) ~= nil
end

function Module.playKillDeathEffectOnCharacter(entry, victim, isKill)
    if not entry then return false end
    local targetCF = Module.getTargetCFrame(victim)
    if not targetCF then return false end
    local template = Storage.ensureEffectInstanceLoaded(entry)
    if template then
        return Module.spawnVisualCloneAt(template, targetCF, isKill and "Kill" or "Death")
    end
    local special = LEGACY_HIT_EFFECTS[entry.ItemID]
    if special then
        special(targetCF, resolveCharacter(victim))
        return true
    end
    return false
end

function Module.playSpawnEffectAction(entry, target)
    if not entry then return false end
    local targetCF = Module.getTargetCFrame(target or LocalPlayer.Character)
    if not targetCF then return false end
    local template = Storage.ensureEffectInstanceLoaded(entry)
    if template then
        return Module.spawnVisualCloneAt(template, targetCF, "Spawn")
    end
    return false
end

function Module.triggerPortalSpawnEffect()
    local now = os.clock()
    if now - Controller.LastPortalEnterTime < 1.5 then return end
    Controller.LastPortalEnterTime = now

    local chosen = Controller.SelectedSpawnEffect
    if chosen then
        Module.playSpawnEffectAction(chosen)
    end
end

function Module.playKillEffect(entry, victim, killer)
    if not Controller.KillEffectEnabled or not entry then return false end
    local isStaffRave = (entry.ItemID == "_hitEffectStaffRave" or entry.Name == "Staff Rave")
    local isKitty = (entry.ItemID == "_hitEffectKittyKatastrophe" or entry.Name == "Kitty Katastrophe")
    local targetCF = Module.getTargetCFrame(victim) or CFrame_new(0, 10, 0)
    if isStaffRave then
        triggerStaffRaveKill(targetCF)
        return true
    elseif isKitty then
        triggerKittyKill()
        return true
    elseif LEGACY_KILL_EFFECTS[entry.ItemID] then
        LEGACY_KILL_EFFECTS[entry.ItemID](targetCF, resolveCharacter(victim))
        return true
    else
        local template = Storage.ensureEffectInstanceLoaded(entry)
        if template then
            return Module.spawnVisualCloneAt(template, targetCF, "Kill")
        end
    end
    return false
end

Module.triggerStaffRaveKill = triggerStaffRaveKill
Module.resetStaffRave = resetStaffRave
Module.triggerKittyKill = triggerKittyKill
Module.resetKitty = resetKitty
Module.resetSpecialEffects = function()
    resetStaffRave(true)
    resetKitty(true)
    for _, sound in ipairs(ActiveSpecialSounds) do
        if sound.Parent then pcall(sound.Destroy, sound) end
    end
    table.clear(ActiveSpecialSounds)
    local character = LocalPlayer and LocalPlayer.Character
    if character then
        for _, descendant in ipairs(character:GetDescendants()) do
            local name = descendant.Name
            if name:find("__KittyKatastrophe", 1, true) or name:find("__StaffRave", 1, true) then
                pcall(descendant.Destroy, descendant)
            end
        end
    end
end
return Module
