local Module = { VERSION = 9 }

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local table_insert = table.insert
local table_concat = table.concat
local table_unpack = table.unpack
local string_byte = string.byte
local string_format = string.format
local task_wait = task.wait

-- Large legacy/FXS2 effects can contain hundreds of Instances.
-- Yielding every few nodes prevents a 100-200 KB effect from freezing Roblox for seconds.
local cooperativeCounter = 0
local function cooperativeYield(weight)
    cooperativeCounter += (weight or 1)
    if cooperativeCounter < 18 then return end
    cooperativeCounter = 0

    local canYield = true
    if coroutine and type(coroutine.isyieldable) == "function" then
        canYield = coroutine.isyieldable()
    end
    if canYield then
        task_wait()
    end
end

local properties = {
    ParticleEmitter = {
        {"FlipbookSizeY", "number"}, {"LockedToPart", "boolean"}, {"Size", "NumberSequence"},
        {"Rate", "number"}, {"Color", "ColorSequence"}, {"LightEmission", "number"},
        {"RotSpeed", "NumberRange"}, {"TimeScale", "number"}, {"ShapeInOut", "EnumItem"},
        {"FlipbookLayout", "EnumItem"}, {"Acceleration", "Vector3"}, {"SpreadAngle", "Vector2"},
        {"ZOffset", "number"}, {"Enabled", "boolean"}, {"ShapeStyle", "EnumItem"},
        {"FlipbookMode", "EnumItem"}, {"ShapePartial", "number"}, {"Orientation", "EnumItem"},
        {"Rotation", "NumberRange"}, {"EmissionDirection", "EnumItem"}, {"WindAffectsDrag", "boolean"},
        {"FlipbookStartRandom", "boolean"}, {"Speed", "NumberRange"}, {"Texture", "string"},
        {"Brightness", "number"}, {"Transparency", "NumberSequence"}, {"Name", "string"},
        {"FlipbookSizeX", "number"}, {"Shape", "EnumItem"}, {"FlipbookBlendFrames", "boolean"},
        {"LightInfluence", "number"}, {"Lifetime", "NumberRange"}, {"FlipbookFramerate", "NumberRange"},
        {"Drag", "number"}, {"Squash", "NumberSequence"}, {"VelocityInheritance", "number"},
        {"Parent", "string"},
    },
    Part = {
        {"Name", "string"}, {"CFrame", "CFrame"}, {"Size", "Vector3"}, {"Color", "Color3"},
        {"Material", "EnumItem"}, {"Transparency", "number"}, {"Reflectance", "number"},
        {"Anchored", "boolean"}, {"CanCollide", "boolean"}, {"CanTouch", "boolean"},
        {"CanQuery", "boolean"}, {"Massless", "boolean"}, {"Shape", "EnumItem"}, {"Parent", "string"},
    },
    Model = {
        {"Name", "string"}, {"PrimaryPart", "PrimaryPartRef"}, {"Parent", "string"},
    },
    Attachment = {
        {"Name", "string"}, {"CFrame", "CFrame"}, {"Axis", "Vector3"},
        {"SecondaryAxis", "Vector3"}, {"Visible", "boolean"}, {"Parent", "string"},
    },
    Sound = {
        {"Name", "string"}, {"SoundId", "string"}, {"Volume", "number"},
        {"PlaybackSpeed", "number"}, {"Looped", "boolean"}, {"Playing", "boolean"},
        {"RollOffMode", "EnumItem"}, {"RollOffMinDistance", "number"},
        {"RollOffMaxDistance", "number"}, {"TimePosition", "number"}, {"Parent", "string"},
    },
    Beam = {
        {"Name", "string"}, {"Color", "ColorSequence"}, {"Transparency", "NumberSequence"},
        {"Width0", "number"}, {"Width1", "number"}, {"CurveSize0", "number"}, {"CurveSize1", "number"},
        {"FaceCamera", "boolean"}, {"LightEmission", "number"}, {"LightInfluence", "number"},
        {"Texture", "string"}, {"TextureLength", "number"}, {"TextureMode", "EnumItem"},
        {"TextureSpeed", "number"}, {"Segments", "number"}, {"Enabled", "boolean"}, {"Parent", "string"},
    },
    Trail = {
        {"Name", "string"}, {"Color", "ColorSequence"}, {"Transparency", "NumberSequence"},
        {"Lifetime", "number"}, {"MinLength", "number"}, {"FaceCamera", "boolean"},
        {"LightEmission", "number"}, {"LightInfluence", "number"}, {"Texture", "string"},
        {"TextureLength", "number"}, {"TextureMode", "EnumItem"}, {"Enabled", "boolean"}, {"Parent", "string"},
    },
    Highlight = {
        {"Name", "string"}, {"FillColor", "Color3"}, {"OutlineColor", "Color3"},
        {"FillTransparency", "number"}, {"OutlineTransparency", "number"},
        {"DepthMode", "EnumItem"}, {"Enabled", "boolean"}, {"Parent", "string"},
    },
    PointLight = {
        {"Name", "string"}, {"Color", "Color3"}, {"Brightness", "number"},
        {"Range", "number"}, {"Shadows", "boolean"}, {"Enabled", "boolean"}, {"Parent", "string"},
    },
}

local function tabletonumber(tab)
    local res = {}
    for i, v in next, tab do
        res[i] = tonumber(v)
    end
    return res
end

local serializeInstance
local serialize = {}

function serialize:auto(value)
    local encoder = self[typeof(value)]
    return encoder and encoder(self, value) or "nil"
end

function serialize:number(value)
    if value ~= value or value == math.huge or value == -math.huge then
        return "0"
    end
    local result = string_format("%.9g", value)
    return result == "-0" and "0" or result
end

function serialize:string(value) return value end
function serialize:boolean(value) return value and "1" or "0" end
serialize["nil"] = function() return "nil" end

function serialize:table(values)
    local output = { "{" }
    for index, value in ipairs(values) do
        if index > 1 then table_insert(output, ",") end
        table_insert(output, self:auto(value))
    end
    table_insert(output, "}")
    return table_concat(output)
end

function serialize:Vector3(value) return self:auto({ value.X, value.Y, value.Z }) end
function serialize:Vector2(value) return self:auto({ value.X, value.Y }) end
function serialize:Color3(value) return value:ToHex() end
function serialize:CFrame(value) return self:auto({ value:GetComponents() }) end
function serialize:EnumItem(value) return tostring(value):sub(6) end
function serialize:NumberRange(value) return self:auto({ value.Min, value.Max }) end

function serialize:ColorSequence(value)
    local keypoints = {}
    for _, keypoint in ipairs(value.Keypoints) do
        table_insert(keypoints, { keypoint.Time, keypoint.Value:ToHex() })
    end
    return self:auto(keypoints)
end

function serialize:NumberSequence(value)
    local keypoints = {}
    for _, keypoint in ipairs(value.Keypoints) do
        table_insert(keypoints, { keypoint.Time, keypoint.Value, keypoint.Envelope })
    end
    return self:auto(keypoints)
end

function serialize:Instance(instance)
    return serializeInstance(instance) or "nil"
end

local deserialize = {}
function deserialize:number(str) return tonumber(str) end
function deserialize:string(str) return str end
function deserialize:boolean(str) return str == "1" and true or false end
deserialize["nil"] = function() return nil end

function deserialize:table(str)
    local len = #str
    if len <= 2 then return {} end
    local res = {}
    local depth, start = 0, 2
    for i = 2, len - 1 do
        local b = string_byte(str, i)
        if b == 123 then
            depth = depth + 1
        elseif b == 125 then
            depth = depth - 1
        elseif b == 44 and depth == 0 then
            table_insert(res, str:sub(start, i - 1))
            start = i + 1
        end
    end
    table_insert(res, str:sub(start, len - 1))
    return res
end

function deserialize:Vector3(str)
    local res = tabletonumber(self:table(str))
    return Vector3.new(res[1] or 0, res[2] or 0, res[3] or 0)
end
function deserialize:Vector2(str)
    local res = tabletonumber(self:table(str))
    return Vector2.new(res[1] or 0, res[2] or 0)
end
function deserialize:Color3(str)
    local ok, c = pcall(Color3.fromHex, str)
    return ok and c or Color3.new(1, 1, 1)
end
function deserialize:CFrame(str)
    local res = tabletonumber(self:table(str))
    return CFrame.new(table_unpack(res))
end
function deserialize:EnumItem(str)
    local iter = str:gmatch("[^%.]+")
    local enumType = iter()
    local enumItem = iter()
    if enumType and enumItem and Enum[enumType] and Enum[enumType][enumItem] then
        return Enum[enumType][enumItem]
    end
    return nil
end
function deserialize:NumberRange(str)
    local res = tabletonumber(self:table(str))
    return NumberRange.new(res[1] or 0, res[2] or res[1] or 0)
end
function deserialize:ColorSequence(str)
    local res = self:table(str)
    local kps = {}
    for _, kpStr in ipairs(res) do
        local kp = self:table(kpStr)
        table_insert(kps, ColorSequenceKeypoint.new(
            self:number(kp[1]) or 0,
            self:Color3(kp[2]) or Color3.new(1, 1, 1)
        ))
    end
    if #kps == 0 then return ColorSequence.new(Color3.new(1, 1, 1)) end
    return ColorSequence.new(kps)
end
function deserialize:NumberSequence(str)
    local res = self:table(str)
    local kps = {}
    for _, kpStr in ipairs(res) do
        local kp = self:table(kpStr)
        table_insert(kps, NumberSequenceKeypoint.new(
            self:number(kp[1]) or 0,
            self:number(kp[2]) or 0,
            kp[3] and self:number(kp[3]) or 0
        ))
    end
    if #kps == 0 then return NumberSequence.new(1) end
    return NumberSequence.new(kps)
end
function deserialize:auto(className, str)
    if not self[className] then return nil end
    return self[className](self, str)
end

local classConstructor = {
    Part = function() return Instance.new("Part") end,
    Attachment = function() return Instance.new("Attachment") end,
    Sound = function() return Instance.new("Sound") end,
    ParticleEmitter = function() return Instance.new("ParticleEmitter") end,
    Model = function() return Instance.new("Model") end,
    Beam = function() return Instance.new("Beam") end,
    Trail = function() return Instance.new("Trail") end,
    Highlight = function() return Instance.new("Highlight") end,
    PointLight = function() return Instance.new("PointLight") end,
}

serializeInstance = function(instance)
    if not instance or not properties[instance.ClassName] then return nil end

    local className = instance.ClassName
    local supportedChildren = {}
    for _, child in ipairs(instance:GetChildren()) do
        if properties[child.ClassName] then
            table_insert(supportedChildren, child)
        end
    end

    local output = { className, serialize:auto(supportedChildren) }
    for _, propertyInfo in ipairs(properties[className]) do
        local propertyName = propertyInfo[1]
        if propertyName == "Parent" then
            table_insert(output, tostring(instance.Parent))
        elseif propertyName == "PrimaryPart" then
            local primaryIndex = 0
            if instance:IsA("Model") and instance.PrimaryPart then
                for index, child in ipairs(supportedChildren) do
                    if child == instance.PrimaryPart then
                        primaryIndex = index
                        break
                    end
                end
            end
            table_insert(output, serialize:number(primaryIndex))
        else
            local ok, value = pcall(function() return instance[propertyName] end)
            table_insert(output, ok and value ~= nil and serialize:auto(value) or "nil")
        end
    end
    return serialize:auto(output)
end

local function deserializeInstance(str, parent)
    if type(str) ~= "string" or str == "" then return nil end
    local ok, raw = pcall(function() return deserialize:table(str) end)
    if not ok or not raw or not raw[1] or not classConstructor[raw[1]] then return nil end

    local className = raw[1]
    local instance = classConstructor[className]()
    cooperativeYield(1)
    local rawChildren = deserialize:table(raw[2])
    local childInstances = {}

    for _, childStr in ipairs(rawChildren) do
        local childInst = deserializeInstance(childStr, instance)
        if childInst then table_insert(childInstances, childInst) end
    end

    local propertyDefinitions = properties[className]
    if propertyDefinitions then
        for i, propertyInfo in ipairs(propertyDefinitions) do
            local propName = propertyInfo[1]
            local propType = propertyInfo[2]
            local rawValue = raw[i + 2]
            if rawValue and rawValue ~= "nil" then
                if propName == "Parent" then
                elseif propName == "PrimaryPart" then
                    local primaryIndex = deserialize:number(rawValue)
                    if primaryIndex and primaryIndex > 0 and childInstances[primaryIndex] then
                        pcall(function() instance.PrimaryPart = childInstances[primaryIndex] end)
                    end
                else
                    local val = deserialize:auto(propType, rawValue)
                    if val ~= nil then
                        pcall(function()
                            if propName == "Enabled" or propName == "Playing" then
                                instance:SetAttribute("__EffectOriginal" .. propName, val)
                            end
                            instance[propName] = val
                        end)
                    end
                end
            end
        end
    end

    -- Every child already passed through this function, so disabling the current
    -- node here avoids repeatedly walking complete subtrees during recursion.
    if instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail")
        or instance:IsA("PointLight") or instance:IsA("Highlight") then
        instance.Enabled = false
    end

    if parent then
        instance.Parent = parent
    end
    return instance
end

-- FXS2 keeps the full object tree and restores cross-object references. The
-- legacy reader above stays in place so the existing effect database remains
-- usable while effects are recollected with the new format.
local SERIALIZER_PREFIX = "FXS2:"

local PROPERTY_GROUPS_V2 = {
    { "Instance", { "Archivable" } },
    { "Model", { "WorldPivot", "LevelOfDetail" } },
    { "BasePart", {
        "CFrame", "Size", "Color", "Material", "MaterialVariant", "Transparency",
        "Reflectance", "Anchored", "CanCollide", "CanTouch", "CanQuery", "Massless",
        "CastShadow", "CollisionGroup", "PivotOffset", "LocalTransparencyModifier",
    } },
    { "Part", { "Shape" } },
    { "MeshPart", { "MeshId", "TextureID", "DoubleSided", "RenderFidelity", "CollisionFidelity" } },
    { "Attachment", { "CFrame", "Axis", "SecondaryAxis", "Visible" } },
    { "ParticleEmitter", {
        "Enabled", "Color", "Transparency", "Size", "Squash", "Texture", "Rate",
        "Lifetime", "Speed", "Rotation", "RotSpeed", "SpreadAngle", "Acceleration",
        "Drag", "VelocityInheritance", "EmissionDirection", "Orientation", "ZOffset",
        "LightEmission", "LightInfluence", "Brightness", "TimeScale", "WindAffectsDrag",
        "LockedToPart", "Shape", "ShapeStyle", "ShapeInOut", "ShapePartial",
        "FlipbookLayout", "FlipbookMode", "FlipbookFramerate", "FlipbookStartRandom",
        "FlipbookBlendFrames", "FlipbookSizeX", "FlipbookSizeY",
    } },
    { "Beam", {
        "Enabled", "Color", "Transparency", "Width0", "Width1", "CurveSize0",
        "CurveSize1", "FaceCamera", "LightEmission", "LightInfluence", "Brightness",
        "Texture", "TextureLength", "TextureMode", "TextureSpeed", "Segments", "ZOffset",
    } },
    { "Trail", {
        "Enabled", "Color", "Transparency", "Lifetime", "MinLength", "FaceCamera",
        "LightEmission", "LightInfluence", "Brightness", "Texture", "TextureLength",
        "TextureMode", "TextureSpeed", "WidthScale", "MaxLength",
    } },
    { "Sound", {
        "SoundId", "Volume", "PlaybackSpeed", "Looped", "Playing", "PlayOnRemove",
        "RollOffMode", "RollOffMinDistance", "RollOffMaxDistance", "EmitterSize",
        "TimePosition", "PlaybackRegionsEnabled", "PlaybackRegion", "LoopRegion",
    } },
    { "Highlight", {
        "Enabled", "FillColor", "OutlineColor", "FillTransparency", "OutlineTransparency",
        "DepthMode",
    } },
    { "Light", { "Enabled", "Color", "Brightness", "Shadows" } },
    { "PointLight", { "Range" } },
    { "SpotLight", { "Range", "Angle", "Face" } },
    { "SurfaceLight", { "Range", "Angle", "Face" } },
    { "TextureBase", { "Texture", "Color3", "Transparency", "Face", "ZIndex" } },
    { "Texture", { "StudsPerTileU", "StudsPerTileV", "OffsetStudsU", "OffsetStudsV" } },
    { "SpecialMesh", { "MeshId", "TextureId", "MeshType", "Scale", "Offset", "VertexColor" } },
    { "SurfaceAppearance", {
        "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap", "AlphaMode",
        "Color", "Metalness", "Roughness",
    } },
    { "Smoke", { "Enabled", "Color", "Opacity", "RiseVelocity", "Size", "TimeScale" } },
    { "Fire", { "Enabled", "Color", "SecondaryColor", "Heat", "Size", "TimeScale" } },
    { "Sparkles", { "Enabled", "SparkleColor", "TimeScale" } },
    { "Explosion", {
        "Position", "BlastPressure", "BlastRadius", "DestroyJointRadiusPercent",
        "ExplosionType", "Visible",
    } },
    { "GuiObject", {
        "Visible", "BackgroundColor3", "BackgroundTransparency", "BorderColor3",
        "BorderSizePixel", "Position", "Size", "Rotation", "AnchorPoint", "ZIndex",
        "AutomaticSize", "ClipsDescendants", "LayoutOrder", "Active", "Interactable",
        "Selectable", "SelectionOrder", "SizeConstraint",
    } },
    { "LayerCollector", { "Enabled", "ResetOnSpawn", "ZIndexBehavior" } },
    { "BillboardGui", {
        "Enabled", "AlwaysOnTop", "Brightness", "ClipsDescendants", "LightInfluence",
        "MaxDistance", "Size", "StudsOffset", "StudsOffsetWorldSpace", "ExtentsOffset",
        "ExtentsOffsetWorldSpace",
    } },
    { "SurfaceGui", {
        "Enabled", "AlwaysOnTop", "Brightness", "Face", "LightInfluence", "PixelsPerStud",
        "CanvasSize", "SizingMode", "ToolPunchThroughDistance", "ZOffset",
    } },
    { "CanvasGroup", { "GroupColor3", "GroupTransparency", "ResolutionScale" } },
    { "Frame", { "Style" } },
    { "ScrollingFrame", {
        "AutomaticCanvasSize", "BottomImage", "CanvasPosition", "CanvasSize", "ElasticBehavior",
        "HorizontalScrollBarInset", "MidImage", "ScrollBarImageColor3", "ScrollBarImageTransparency",
        "ScrollBarThickness", "ScrollingDirection", "ScrollingEnabled", "TopImage",
        "VerticalScrollBarInset", "VerticalScrollBarPosition",
    } },
    { "ImageLabel", {
        "Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter", "SliceScale",
        "TileSize", "ResampleMode",
    } },
    { "ImageButton", {
        "Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter", "SliceScale",
        "TileSize", "ResampleMode",
    } },
    { "TextLabel", {
        "Text", "TextColor3", "TextTransparency", "TextSize", "TextScaled", "TextWrapped",
        "Font", "FontFace", "TextXAlignment", "TextYAlignment", "TextStrokeColor3",
        "TextStrokeTransparency", "LineHeight", "RichText", "TextTruncate", "MaxVisibleGraphemes",
    } },
    { "TextButton", {
        "Text", "TextColor3", "TextTransparency", "TextSize", "TextScaled", "TextWrapped",
        "Font", "FontFace", "TextXAlignment", "TextYAlignment", "TextStrokeColor3",
        "TextStrokeTransparency", "LineHeight", "RichText", "TextTruncate", "MaxVisibleGraphemes",
    } },
    { "TextBox", {
        "Text", "PlaceholderText", "TextColor3", "PlaceholderColor3", "TextTransparency",
        "TextSize", "TextScaled", "TextWrapped", "Font", "FontFace", "TextXAlignment",
        "TextYAlignment", "TextStrokeColor3", "TextStrokeTransparency", "LineHeight",
        "RichText", "TextTruncate", "MaxVisibleGraphemes", "ClearTextOnFocus", "MultiLine",
    } },
    { "ViewportFrame", {
        "Ambient", "ImageColor3", "ImageTransparency", "LightColor", "LightDirection",
    } },
    { "VideoFrame", { "Video", "Looped", "Playing", "TimePosition", "Volume" } },
    { "UIGradient", { "Enabled", "Color", "Transparency", "Offset", "Rotation" } },
    { "UIStroke", { "Enabled", "ApplyStrokeMode", "Color", "LineJoinMode", "Thickness", "Transparency" } },
    { "UICorner", { "CornerRadius" } },
    { "UIScale", { "Scale" } },
    { "UIPadding", { "PaddingBottom", "PaddingLeft", "PaddingRight", "PaddingTop" } },
    { "UIGridStyleLayout", {
        "FillDirection", "HorizontalAlignment", "SortOrder", "VerticalAlignment",
    } },
    { "UIListLayout", { "Padding", "Wraps" } },
    { "UIGridLayout", { "CellPadding", "CellSize", "FillDirectionMaxCells", "StartCorner" } },
    { "UIPageLayout", {
        "Animated", "Circular", "CurrentPage", "EasingDirection", "EasingStyle",
        "GamepadInputEnabled", "Padding", "ScrollWheelInputEnabled", "TouchInputEnabled", "TweenTime",
    } },
    { "UIAspectRatioConstraint", { "AspectRatio", "AspectType", "DominantAxis" } },
    { "UISizeConstraint", { "MaxSize", "MinSize" } },
    { "UITextSizeConstraint", { "MaxTextSize", "MinTextSize" } },
    { "NumberValue", { "Value" } },
    { "IntValue", { "Value" } },
    { "BoolValue", { "Value" } },
    { "StringValue", { "Value" } },
    { "Color3Value", { "Value" } },
    { "Vector3Value", { "Value" } },
    { "CFrameValue", { "Value" } },
    { "ObjectValue", {} },
    { "Weld", { "C0", "C1", "Enabled" } },
    { "Motor6D", { "C0", "C1", "Enabled", "Transform" } },
    { "Constraint", { "Enabled", "Visible" } },
    { "VectorForce", { "Force", "RelativeTo", "ApplyAtCenterOfMass" } },
    { "LinearVelocity", { "VectorVelocity", "MaxForce", "RelativeTo", "VelocityConstraintMode" } },
    { "AngularVelocity", { "AngularVelocity", "MaxTorque", "RelativeTo" } },
    { "HandleAdornment", { "AlwaysOnTop", "Color3", "Transparency", "Visible", "ZIndex" } },
    { "SelectionBox", { "Color3", "LineThickness", "SurfaceColor3", "SurfaceTransparency", "Transparency", "Visible" } },
    { "BoxHandleAdornment", { "CFrame", "Size" } },
    { "SphereHandleAdornment", { "Radius" } },
    { "CylinderHandleAdornment", { "Angle", "Height", "Radius" } },
    { "ConeHandleAdornment", { "Height", "Radius" } },
    { "LineHandleAdornment", { "Length", "Thickness" } },
    { "Sky", {
        "CelestialBodiesShown", "MoonAngularSize", "MoonTextureId", "SkyboxBk", "SkyboxDn",
        "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "StarCount", "SunAngularSize", "SunTextureId",
    } },
    { "Atmosphere", { "Density", "Offset", "Color", "Decay", "Glare", "Haze" } },
    { "BlurEffect", { "Enabled", "Size" } },
    { "BloomEffect", { "Enabled", "Intensity", "Size", "Threshold" } },
    { "ColorCorrectionEffect", { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" } },
    { "SunRaysEffect", { "Enabled", "Intensity", "Spread" } },
    { "DepthOfFieldEffect", {
        "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity",
    } },
    { "SoundEffect", { "Enabled", "Priority" } },
    { "ChorusSoundEffect", { "Depth", "Mix", "Rate" } },
    { "CompressorSoundEffect", { "Attack", "GainMakeup", "Ratio", "Release", "SideChain", "Threshold" } },
    { "DistortionSoundEffect", { "Level" } },
    { "EchoSoundEffect", { "Delay", "DryLevel", "Feedback", "WetLevel" } },
    { "EqualizerSoundEffect", { "HighGain", "LowGain", "MidGain" } },
    { "FlangeSoundEffect", { "Depth", "Mix", "Rate" } },
    { "PitchShiftSoundEffect", { "Octave" } },
    { "ReverbSoundEffect", { "DecayTime", "Density", "Diffusion", "DryLevel", "WetLevel" } },
    { "TremoloSoundEffect", { "Depth", "Duty", "Frequency" } },
    { "Animation", { "AnimationId" } },
}

local REFERENCE_GROUPS_V2 = {
    { "Model", { "PrimaryPart" } },
    { "Beam", { "Attachment0", "Attachment1" } },
    { "Trail", { "Attachment0", "Attachment1" } },
    { "Constraint", { "Attachment0", "Attachment1" } },
    { "WeldConstraint", { "Part0", "Part1" } },
    { "Weld", { "Part0", "Part1" } },
    { "Motor6D", { "Part0", "Part1" } },
    { "ObjectValue", { "Value" } },
    { "BillboardGui", { "Adornee" } },
    { "SurfaceGui", { "Adornee" } },
    { "Highlight", { "Adornee" } },
    { "HandleAdornment", { "Adornee" } },
    { "SelectionBox", { "Adornee" } },
    { "ViewportFrame", { "CurrentCamera" } },
    { "VectorForce", { "Attachment0" } },
    { "LinearVelocity", { "Attachment0", "Attachment1" } },
    { "AngularVelocity", { "Attachment0" } },
}

local function finiteNumber(value)
    if value ~= value or value == math.huge or value == -math.huge then return 0 end
    return value
end

local function encodeValueV2(value)
    local valueType = typeof(value)
    if valueType == "string" or valueType == "boolean" then return value end
    if valueType == "number" then return finiteNumber(value) end
    if valueType == "Vector2" then
        return { T = "Vector2", V = { finiteNumber(value.X), finiteNumber(value.Y) } }
    elseif valueType == "Vector3" then
        return { T = "Vector3", V = { finiteNumber(value.X), finiteNumber(value.Y), finiteNumber(value.Z) } }
    elseif valueType == "Color3" then
        return { T = "Color3", V = { finiteNumber(value.R), finiteNumber(value.G), finiteNumber(value.B) } }
    elseif valueType == "CFrame" then
        local components = { value:GetComponents() }
        for index, component in ipairs(components) do components[index] = finiteNumber(component) end
        return { T = "CFrame", V = components }
    elseif valueType == "UDim" then
        return { T = "UDim", V = { finiteNumber(value.Scale), finiteNumber(value.Offset) } }
    elseif valueType == "UDim2" then
        return { T = "UDim2", V = {
            finiteNumber(value.X.Scale), finiteNumber(value.X.Offset),
            finiteNumber(value.Y.Scale), finiteNumber(value.Y.Offset),
        } }
    elseif valueType == "Rect" then
        return { T = "Rect", V = {
            finiteNumber(value.Min.X), finiteNumber(value.Min.Y),
            finiteNumber(value.Max.X), finiteNumber(value.Max.Y),
        } }
    elseif valueType == "NumberRange" then
        return { T = "NumberRange", V = { finiteNumber(value.Min), finiteNumber(value.Max) } }
    elseif valueType == "NumberSequence" then
        local keypoints = {}
        for _, keypoint in ipairs(value.Keypoints) do
            table_insert(keypoints, {
                finiteNumber(keypoint.Time), finiteNumber(keypoint.Value), finiteNumber(keypoint.Envelope),
            })
        end
        return { T = "NumberSequence", V = keypoints }
    elseif valueType == "ColorSequence" then
        local keypoints = {}
        for _, keypoint in ipairs(value.Keypoints) do
            table_insert(keypoints, {
                finiteNumber(keypoint.Time),
                finiteNumber(keypoint.Value.R), finiteNumber(keypoint.Value.G), finiteNumber(keypoint.Value.B),
            })
        end
        return { T = "ColorSequence", V = keypoints }
    elseif valueType == "EnumItem" then
        return { T = "EnumItem", V = tostring(value) }
    elseif valueType == "BrickColor" then
        return { T = "BrickColor", V = value.Number }
    elseif valueType == "Font" then
        return {
            T = "Font",
            V = {
                Family = value.Family,
                Weight = tostring(value.Weight),
                Style = tostring(value.Style),
            },
        }
    end
    return nil
end

local function decodeEnumV2(path)
    if type(path) ~= "string" then return nil end
    path = path:gsub("^Enum%.", "")
    local enumType, enumItem = path:match("^([%w_]+)%.([%w_]+)$")
    if not enumType or not enumItem or not Enum[enumType] then return nil end
    return Enum[enumType][enumItem]
end

local function decodeValueV2(encoded)
    if type(encoded) ~= "table" or not encoded.T then return encoded end
    local kind, values = encoded.T, encoded.V or {}
    if kind == "Vector2" then
        return Vector2.new(values[1] or 0, values[2] or 0)
    elseif kind == "Vector3" then
        return Vector3.new(values[1] or 0, values[2] or 0, values[3] or 0)
    elseif kind == "Color3" then
        return Color3.new(values[1] or 0, values[2] or 0, values[3] or 0)
    elseif kind == "CFrame" then
        return CFrame.new(table_unpack(values))
    elseif kind == "UDim" then
        return UDim.new(values[1] or 0, values[2] or 0)
    elseif kind == "UDim2" then
        return UDim2.new(values[1] or 0, values[2] or 0, values[3] or 0, values[4] or 0)
    elseif kind == "Rect" then
        return Rect.new(values[1] or 0, values[2] or 0, values[3] or 0, values[4] or 0)
    elseif kind == "NumberRange" then
        return NumberRange.new(values[1] or 0, values[2] or values[1] or 0)
    elseif kind == "NumberSequence" then
        local keypoints = {}
        for _, keypoint in ipairs(values) do
            table_insert(keypoints, NumberSequenceKeypoint.new(
                keypoint[1] or 0, keypoint[2] or 0, keypoint[3] or 0
            ))
        end
        return #keypoints > 0 and NumberSequence.new(keypoints) or NumberSequence.new(0)
    elseif kind == "ColorSequence" then
        local keypoints = {}
        for _, keypoint in ipairs(values) do
            table_insert(keypoints, ColorSequenceKeypoint.new(
                keypoint[1] or 0,
                Color3.new(keypoint[2] or 0, keypoint[3] or 0, keypoint[4] or 0)
            ))
        end
        return #keypoints > 0 and ColorSequence.new(keypoints) or ColorSequence.new(Color3.new(1, 1, 1))
    elseif kind == "EnumItem" then
        return decodeEnumV2(values)
    elseif kind == "BrickColor" then
        return BrickColor.new(values)
    elseif kind == "Font" then
        local ok, font = pcall(
            Font.new,
            values.Family or "rbxasset://fonts/families/SourceSansPro.json",
            decodeEnumV2(values.Weight) or Enum.FontWeight.Regular,
            decodeEnumV2(values.Style) or Enum.FontStyle.Normal
        )
        return ok and font or nil
    end
    return nil
end

local function gatherPropertyNamesV2(instance, groups)
    local result, seen = {}, {}
    for _, group in ipairs(groups) do
        if instance:IsA(group[1]) then
            for _, propertyName in ipairs(group[2]) do
                if not seen[propertyName] then
                    seen[propertyName] = true
                    table_insert(result, propertyName)
                end
            end
        end
    end
    return result
end

local function serializeInstanceV2(root)
    if typeof(root) ~= "Instance" then return nil end

    local nextID = 0
    local nodeByInstance = {}
    local idByInstance = {}
    local function buildSkeleton(instance)
        nextID = nextID + 1
        local node = {
            ID = nextID,
            ClassName = instance.ClassName,
            Name = instance.Name,
            Properties = {},
            References = {},
            Attributes = {},
            Tags = {},
            Children = {},
        }
        nodeByInstance[instance] = node
        idByInstance[instance] = nextID
        for _, child in ipairs(instance:GetChildren()) do
            table_insert(node.Children, buildSkeleton(child))
        end
        return node
    end

    local rootNode = buildSkeleton(root)
    for instance, node in pairs(nodeByInstance) do
        for _, propertyName in ipairs(gatherPropertyNamesV2(instance, PROPERTY_GROUPS_V2)) do
            local ok, value = pcall(function() return instance[propertyName] end)
            if ok then
                local encoded = encodeValueV2(value)
                if encoded ~= nil then node.Properties[propertyName] = encoded end
            end
        end
        for _, propertyName in ipairs(gatherPropertyNamesV2(instance, REFERENCE_GROUPS_V2)) do
            local ok, value = pcall(function() return instance[propertyName] end)
            if ok and typeof(value) == "Instance" and idByInstance[value] then
                node.References[propertyName] = idByInstance[value]
            end
        end
        local okAttributes, attributes = pcall(instance.GetAttributes, instance)
        if okAttributes and type(attributes) == "table" then
            for name, value in pairs(attributes) do
                if not tostring(name):find("^__EffectOriginal") then
                    local encoded = encodeValueV2(value)
                    if encoded ~= nil then node.Attributes[name] = encoded end
                end
            end
        end
        local okTags, tags = pcall(CollectionService.GetTags, CollectionService, instance)
        if okTags and type(tags) == "table" then
            for _, tag in ipairs(tags) do
                if type(tag) == "string" and tag ~= "" then table_insert(node.Tags, tag) end
            end
        end
    end

    local ok, json = pcall(HttpService.JSONEncode, HttpService, {
        Format = "FXS2",
        Version = 3,
        Root = rootNode,
    })
    return ok and (SERIALIZER_PREFIX .. json) or nil
end

local function createInstanceV2(className)
    if type(className) ~= "string" or className:find("Script", 1, true) then
        local folder = Instance.new("Folder")
        folder:SetAttribute("__EffectOriginalClass", tostring(className))
        return folder
    end
    local ok, instance = pcall(Instance.new, className)
    if ok and instance then return instance end
    local folder = Instance.new("Folder")
    folder:SetAttribute("__EffectOriginalClass", className)
    return folder
end

local function deserializeInstanceV2(str, parent)
    local payload = str:sub(#SERIALIZER_PREFIX + 1)
    local okDecode, document = pcall(HttpService.JSONDecode, HttpService, payload)
    if not okDecode or type(document) ~= "table" or type(document.Root) ~= "table" then return nil end

    local idToInstance = {}
    local created = {}
    local function createTree(node, internalParent)
        if type(node) ~= "table" then return nil end
        local instance = createInstanceV2(node.ClassName)
        instance.Name = type(node.Name) == "string" and node.Name or tostring(node.ClassName or "Effect")
        if internalParent then instance.Parent = internalParent end
        if node.ID ~= nil then idToInstance[tonumber(node.ID) or node.ID] = instance end
        table_insert(created, { Node = node, Instance = instance })
        cooperativeYield(1)
        for _, childNode in ipairs(type(node.Children) == "table" and node.Children or {}) do
            createTree(childNode, instance)
        end
        return instance
    end

    local root = createTree(document.Root, nil)
    if not root then return nil end

    for _, item in ipairs(created) do
        local node, instance = item.Node, item.Instance
        for name, encoded in pairs(type(node.Attributes) == "table" and node.Attributes or {}) do
            local decoded = decodeValueV2(encoded)
            if decoded ~= nil then pcall(instance.SetAttribute, instance, name, decoded) end
        end
        for _, tag in ipairs(type(node.Tags) == "table" and node.Tags or {}) do
            if type(tag) == "string" and tag ~= "" then
                pcall(CollectionService.AddTag, CollectionService, instance, tag)
            end
        end
        for propertyName, encoded in pairs(type(node.Properties) == "table" and node.Properties or {}) do
            local decoded = decodeValueV2(encoded)
            if decoded ~= nil then
                if propertyName == "Playing" then
                    pcall(instance.SetAttribute, instance, "__EffectOriginalPlaying", decoded == true)
                else
                    pcall(function() instance[propertyName] = decoded end)
                end
            end
        end
        cooperativeYield(2)
    end

    for _, item in ipairs(created) do
        local references = type(item.Node.References) == "table" and item.Node.References or {}
        for propertyName, referenceID in pairs(references) do
            local referenced = idToInstance[tonumber(referenceID) or referenceID]
            if referenced then pcall(function() item.Instance[propertyName] = referenced end) end
        end
        cooperativeYield(1)
    end

    for _, item in ipairs(created) do
        local instance = item.Instance
        if instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail")
            or instance:IsA("Light") or instance:IsA("Highlight") or instance:IsA("Smoke")
            or instance:IsA("Fire") or instance:IsA("Sparkles") then
            local originalEnabled = instance.Enabled
            pcall(instance.SetAttribute, instance, "__EffectOriginalEnabled", originalEnabled)
            instance.Enabled = false
        elseif instance:IsA("Sound") then
            if instance:GetAttribute("__EffectOriginalPlaying") == nil then
                pcall(instance.SetAttribute, instance, "__EffectOriginalPlaying", false)
            end
            pcall(instance.Stop, instance)
        end
    end

    if parent then root.Parent = parent end
    return root
end

function Module.deserializeInstance(str, parent)
    if type(str) == "string" and str:sub(1, #SERIALIZER_PREFIX) == SERIALIZER_PREFIX then
        return deserializeInstanceV2(str, parent)
    end
    return deserializeInstance(str, parent)
end

function Module.isCurrentFormat(str)
    if type(str) ~= "string" or str:sub(1, #SERIALIZER_PREFIX) ~= SERIALIZER_PREFIX then
        return false
    end
    local ok, document = pcall(HttpService.JSONDecode, HttpService, str:sub(#SERIALIZER_PREFIX + 1))
    return ok and type(document) == "table" and tonumber(document.Version) == 3
end

function Module.serializeInstance(instance)
    return serializeInstanceV2(instance)
end
return Module
