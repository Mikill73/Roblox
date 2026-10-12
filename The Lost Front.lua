local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Environment = getgenv and getgenv() or shared

-- =========================================================================
-- CONSTANTS
-- =========================================================================
local CONST = {
    SILENT_UPDATE_INTERVAL = 0.05,
    ESP_UPDATE_INTERVAL = 1 / 30,
    VISIBILITY_CACHE_TTL = 0.1,
    TEAM_REGISTRY_SEARCH_COOLDOWN = 2,
    BOUNDS_CACHE_MOVE_THRESHOLD = 1.5,
    MAX_ESP_TARGETS = 60,
    DRONE_RESCAN_INTERVAL = 1.5,
    DRONE_REGISTER_DELAY = 0.35,
    MIN_ESP_BOX_SIZE = 2,
    WEAPON_SCAN_INTERVAL = 0.1,
    MINE_SCAN_INTERVAL = 0.1,
    MINE_POLL_INTERVAL = 0.5,
}

if Environment.LostFrontDrawingESP and type(Environment.LostFrontDrawingESP.Unload) == "function" then
    pcall(Environment.LostFrontDrawingESP.Unload)
end

if not Drawing or type(Drawing.new) ~= "function" then
    error("Drawing library is not supported by this executor")
end

local Repository = "https://raw.githubusercontent.com/Ali-lov3/Obsidian-UiLibs/refs/heads/main/"
local Library = loadstring(game:HttpGet(Repository .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(Repository .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(Repository .. "addons/SaveManager.lua"))()
local Options = Library.Options
local Toggles = Library.Toggles

-- =========================================================================
-- CONTROLLER
-- =========================================================================
local Controller = {
    Unloaded = false,
    TeamRegistryFound = false,
    LocalTeam = "unknown",
    SilentTarget = nil,
    SilentTargetKind = nil,
    FastCastHookInstalled = false,
    FastCastCalls = 0,
    SilentRedirects = 0,
    LastSilentTarget = "",
    Connections = {},
    PlayerEntries = {},
    DroneEntries = {},
    WeaponEntries = {},
    MineEntries = {},
    MineStats = { detonated = 0, registered = 0, failed = 0 },
    LastMineAction = "",
    LastMineActionTime = 0,
    IgnoreSet = {},
    VisibilityCache = setmetatable({}, { __mode = "k" }),
    BoundsCache = setmetatable({}, { __mode = "k" }),
    Settings = {
        -- Silent Aim
        SilentAimEnabled = true,
        SilentAimTeamCheck = true,
        SilentAimVisibilityCheck = true,
        SilentAimPrediction = true,
        SilentAimHitChance = 100,
        SilentAimTargetType = "Players and Drones",
        SilentAimTargetPart = "Head",
        SilentAimTargetPriority = "Closest to crosshair",
        SilentAimMaxDistance = 2500,
        SilentAimFOV = 150,
        SilentAimFOVShape = "Circle",
        SilentAimShowFOV = true,
        SilentAimFOVColor = Color3.fromRGB(255, 255, 255),
        SilentAimLockedFOVColor = Color3.fromRGB(80, 255, 140),
        SilentAimFOVThickness = 1,
        SilentAimFOVOpacity = 0.8,
        SilentAimGravityDivisor = 8,
        SilentAimIgnoreList = "",

        -- Player ESP
        PlayerEnabled = true,
        PlayerBoxes = true,
        PlayerBoxStyle = "Full",
        PlayerNames = true,
        PlayerDistance = true,
        PlayerTracers = false,
        PlayerHealthBar = false,
        PlayerSkeleton = false,
        PlayerChams = false,
        ShowTeammates = false,
        PlayerMaxDistance = 2500,
        EnemyColor = Color3.fromRGB(255, 80, 80),
        TeammateColor = Color3.fromRGB(80, 180, 255),
        ChamsColor = Color3.fromRGB(255, 80, 80),

        -- Drone ESP
        DroneEnabled = true,
        DroneBoxes = true,
        DroneNames = true,
        DroneTeams = true,
        DroneDistance = true,
        DroneTracers = false,
        DroneRearArrows = true,
        DroneTeamCheck = true,
        ShowOwnDrone = false,
        DroneMaxDistance = 2500,
        FriendlyDroneColor = Color3.fromRGB(80, 180, 255),
        EnemyDroneColor = Color3.fromRGB(255, 90, 70),
        UnknownDroneColor = Color3.fromRGB(255, 210, 70),
        RearArrowRadius = 70,
        RearArrowSize = 11,

        -- Weapon ESP + Auto-collect
        WeaponEnabled = true,
        WeaponHighlight = true,
        WeaponText = true,
        WeaponNames = true,
        WeaponDistance = true,
        WeaponAutoCollect = true,
        WeaponTeleport = false,
        WeaponMaxDistance = 500,
        WeaponCollectDistance = 10,
        WeaponCooldown = 0.15,
        WeaponRateLimit = 20,
        WeaponTeleportOffset = Vector3.new(0, 2.5, 0),
        WeaponTeleportDelay = 0.06,
        WeaponHighlightColor = Color3.fromRGB(255, 220, 80),

        -- SISTEMA DE MINAS
        MinesEnabled = true,
        MinesAutoTrigger = true,
        MinesTriggerRadius = 25,
        MinesTeamCheck = true,
        MinesCooldown = 0.5,
        MinesMaxActive = 5,
        MinesShowESP = true,
        MinesESPColor = Color3.fromRGB(255, 100, 60),
        MinesESPText = true,
        MinesFPVSlot = 1,
        MinesAutoPlace = false,
        MinesPlaceDistance = 6,
        MinesKeyDetonateAll = "B",
        MinesKeyPlace = "Z",
        MinesKeyToggleMode = "N",

        -- Visuals
        BoxThickness = 1,
        TextSize = 13,
        Opacity = 1,
        WatermarkEnabled = true,
    }
}

Environment.LostFrontDrawingESP = Controller

-- =========================================================================
-- HELPERS
-- =========================================================================
local function addConnection(connection)
    table.insert(Controller.Connections, connection)
    return connection
end

local function safeDrawing(kind, properties)
    local ok, object = pcall(Drawing.new, kind)
    if not ok or not object then return nil end
    for property, value in pairs(properties or {}) do
        pcall(function() object[property] = value end)
    end
    return object
end

local function setProperty(object, property, value)
    if not object then return end
    pcall(function() object[property] = value end)
end

local function removeDrawing(object)
    if not object then return end
    pcall(function() object.Visible = false end)
    pcall(function()
        if object.Remove then object:Remove()
        elseif object.Destroy then object:Destroy() end
    end)
end

local function setMineStatus(txt)
    Controller.LastMineAction = txt
    Controller.LastMineActionTime = os.clock()
end

local function rebuildIgnoreList()
    table.clear(Controller.IgnoreSet)
    local text = Controller.Settings.SilentAimIgnoreList or ""
    for name in text:gmatch("[^,]+") do
        local trimmed = name:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            Controller.IgnoreSet[trimmed:lower()] = true
        end
    end
end

local function isIgnored(player)
    if not player then return false end
    local set = Controller.IgnoreSet
    return set[player.Name:lower()] == true
        or set[player.DisplayName:lower()] == true
end

-- =========================================================================
-- FOV INDICATOR
-- =========================================================================
local SilentFOVCircle = safeDrawing("Circle", {
    Visible = false, Filled = false,
    Color = Controller.Settings.SilentAimFOVColor,
    NumSides = 72,
    Radius = Controller.Settings.SilentAimFOV,
    Thickness = Controller.Settings.SilentAimFOVThickness,
    Transparency = Controller.Settings.SilentAimFOVOpacity,
    ZIndex = 5,
})
local SilentFOVSquare = safeDrawing("Square", {
    Visible = false, Filled = false,
    Color = Controller.Settings.SilentAimFOVColor,
    Size = Vector2.new(300, 300),
    Thickness = Controller.Settings.SilentAimFOVThickness,
    Transparency = Controller.Settings.SilentAimFOVOpacity,
    ZIndex = 5,
})
Controller.SilentFOVCircle = SilentFOVCircle
Controller.SilentFOVSquare = SilentFOVSquare

-- =========================================================================
-- WATERMARK
-- =========================================================================
local Watermark = safeDrawing("Text", {
    Visible = false, Center = false, Outline = true,
    OutlineColor = Color3.new(0, 0, 0),
    Color = Color3.fromRGB(80, 255, 140),
    Size = 14, Font = 2, Transparency = 1,
    Position = Vector2.new(12, 12), ZIndex = 20,
    Text = "The Lost Front | ESP",
})

-- =========================================================================
-- VISUALS
-- =========================================================================
local function createVisual(includeRearArrow)
    local font = Drawing.Fonts and (Drawing.Fonts.Plex or Drawing.Fonts.UI) or 2
    local visual = {
        Outline = safeDrawing("Square", {
            Visible = false, Filled = false, Color = Color3.new(0, 0, 0),
            Thickness = 3, Transparency = 1, ZIndex = 1,
        }),
        Box = safeDrawing("Square", {
            Visible = false, Filled = false, Color = Color3.new(1, 1, 1),
            Thickness = 1, Transparency = 1, ZIndex = 2,
        }),
        Text = safeDrawing("Text", {
            Visible = false, Center = true, Outline = true,
            OutlineColor = Color3.new(0, 0, 0), Color = Color3.new(1, 1, 1),
            Size = 13, Font = font, Transparency = 1, ZIndex = 3,
        }),
        Tracer = safeDrawing("Line", {
            Visible = false, Color = Color3.new(1, 1, 1),
            Thickness = 1, Transparency = 1, ZIndex = 2,
        }),
        HealthBG = safeDrawing("Square", {
            Visible = false, Filled = true, Color = Color3.new(0, 0, 0),
            Size = Vector2.new(3, 20), Transparency = 0.4, ZIndex = 2,
        }),
        HealthFill = safeDrawing("Square", {
            Visible = false, Filled = true, Color = Color3.fromRGB(80, 255, 100),
            Size = Vector2.new(3, 20), Transparency = 0.15, ZIndex = 3,
        }),
        Corners = {},
        Skeleton = {},
    }
    for i = 1, 8 do
        visual.Corners[i] = safeDrawing("Line", {
            Visible = false, Color = Color3.new(1, 1, 1),
            Thickness = 1, Transparency = 1, ZIndex = 2,
        })
    end
    for i = 1, 6 do
        visual.Skeleton[i] = safeDrawing("Line", {
            Visible = false, Color = Color3.new(1, 1, 1),
            Thickness = 1, Transparency = 1, ZIndex = 2,
        })
    end
    if includeRearArrow then
        visual.ArrowTop = safeDrawing("Line", {
            Visible = false, Color = Color3.new(1, 1, 1),
            Thickness = 2, Transparency = 1, ZIndex = 4,
        })
        visual.ArrowBottom = safeDrawing("Line", {
            Visible = false, Color = Color3.new(1, 1, 1),
            Thickness = 2, Transparency = 1, ZIndex = 4,
        })
    end
    return visual
end

local function hideVisual(visual)
    if not visual then return end
    setProperty(visual.Outline, "Visible", false)
    setProperty(visual.Box, "Visible", false)
    setProperty(visual.Text, "Visible", false)
    setProperty(visual.Tracer, "Visible", false)
    setProperty(visual.HealthBG, "Visible", false)
    setProperty(visual.HealthFill, "Visible", false)
    if visual.ArrowTop then
        setProperty(visual.ArrowTop, "Visible", false)
        setProperty(visual.ArrowBottom, "Visible", false)
    end
    if visual.Corners then
        for _, line in ipairs(visual.Corners) do setProperty(line, "Visible", false) end
    end
    if visual.Skeleton then
        for _, line in ipairs(visual.Skeleton) do setProperty(line, "Visible", false) end
    end
end

local function removeVisual(visual)
    if not visual then return end
    removeDrawing(visual.Outline)
    removeDrawing(visual.Box)
    removeDrawing(visual.Text)
    removeDrawing(visual.Tracer)
    removeDrawing(visual.HealthBG)
    removeDrawing(visual.HealthFill)
    removeDrawing(visual.ArrowTop)
    removeDrawing(visual.ArrowBottom)
    if visual.Corners then for _, l in ipairs(visual.Corners) do removeDrawing(l) end end
    if visual.Skeleton then for _, l in ipairs(visual.Skeleton) do removeDrawing(l) end end
end

-- =========================================================================
-- CHAMS
-- =========================================================================
local function getChamsInstance(character)
    if not character then return nil end
    local existing = character:FindFirstChild("LostFrontESPChams")
    if existing and existing:IsA("Highlight") then return existing end
    local hl = Instance.new("Highlight")
    hl.Name = "LostFrontESPChams"
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency = 0.55
    hl.OutlineTransparency = 0.1
    hl.Adornee = character
    hl.Enabled = false
    hl.Parent = character
    return hl
end

local function setChams(character, enabled, color)
    if not character then return end
    local chams = getChamsInstance(character)
    if not chams then return end
    chams.Enabled = enabled
    if enabled and color then
        chams.FillColor = color
        chams.OutlineColor = color
    end
end

-- =========================================================================
-- ANCHOR / BOUNDS
-- =========================================================================
local function getAnchor(model)
    if not model or not model:IsA("Model") then
        if model and model:IsA("BasePart") then return model end
        return nil
    end
    return model.PrimaryPart
        or model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Head")
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getBounds(model, camera)
    if not model or not camera then return nil end
    if not model:IsA("Model") then
        local sp, on = camera:WorldToViewportPoint(model.Position)
        if not on or sp.Z <= 0 then return nil end
        return Vector2.new(sp.X - 15, sp.Y - 15), Vector2.new(30, 30)
    end

    local cache = Controller.BoundsCache[model]
    local anchor = getAnchor(model)
    local now = os.clock()

    if cache and anchor and now - cache.t < 0.033 then
        if (anchor.Position - cache.pos).Magnitude < CONST.BOUNDS_CACHE_MOVE_THRESHOLD then
            return cache.min, cache.size
        end
    end

    local success, boxCFrame, boxSize = pcall(model.GetBoundingBox, model)
    if not success or boxSize.Magnitude <= 0 then return nil end

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local wp = boxCFrame:PointToWorldSpace(Vector3.new(
                    boxSize.X * x * 0.5, boxSize.Y * y * 0.5, boxSize.Z * z * 0.5))
                local sp = camera:WorldToViewportPoint(wp)
                if sp.Z <= 0 then return nil end
                minX = math.min(minX, sp.X); minY = math.min(minY, sp.Y)
                maxX = math.max(maxX, sp.X); maxY = math.max(maxY, sp.Y)
            end
        end
    end

    local vp = camera.ViewportSize
    if maxX < 0 or maxY < 0 or minX > vp.X or minY > vp.Y then return nil end

    minX = math.clamp(minX, 0, vp.X); minY = math.clamp(minY, 0, vp.Y)
    maxX = math.clamp(maxX, 0, vp.X); maxY = math.clamp(maxY, 0, vp.Y)

    local width = maxX - minX
    local height = maxY - minY
    if width < CONST.MIN_ESP_BOX_SIZE or height < CONST.MIN_ESP_BOX_SIZE then return nil end

    local minPoint = Vector2.new(minX, minY)
    local sizePoint = Vector2.new(width, height)

    if anchor then
        Controller.BoundsCache[model] = {
            t = now, pos = anchor.Position, min = minPoint, size = sizePoint,
        }
    end
    return minPoint, sizePoint
end

local function getDistanceOrigin(camera)
    local character = LocalPlayer.Character
    local anchor = getAnchor(character)
    return anchor and anchor.Position or camera.CFrame.Position
end

-- =========================================================================
-- TEAM REGISTRY
-- =========================================================================
local TeamRegistry
local LastTeamRegistrySearch = 0

local function getTeamRegistry()
    if TeamRegistry and type(TeamRegistry.players) == "table" and TeamRegistry.players[LocalPlayer] then
        return TeamRegistry
    end
    if os.clock() - LastTeamRegistrySearch < CONST.TEAM_REGISTRY_SEARCH_COOLDOWN then
        return nil
    end
    LastTeamRegistrySearch = os.clock()
    if type(filtergc) ~= "function" then return nil end

    local success, registry = pcall(filtergc, "table", {
        Keys = { "isFriendly", "getclient", "getEnemyTeam", "getPlayer", "players" }
    }, true)
    if not success or type(registry) ~= "table" or type(registry.players) ~= "table" then
        return nil
    end
    if not registry.players[LocalPlayer] then return nil end

    TeamRegistry = registry
    Controller.TeamRegistryFound = true
    local clientData = registry.players[LocalPlayer]
    Controller.LocalTeam = clientData and clientData.team or "unknown"
    return registry
end

local function getPlayerTeamState(player)
    if not player then return nil, "unknown" end
    local registry = getTeamRegistry()
    if registry then
        local clientData = registry.players[LocalPlayer]
        local playerData = registry.players[player]
        if clientData and playerData and clientData.team and playerData.team then
            return clientData.team == playerData.team, tostring(playerData.team)
        end
    end
    if player == LocalPlayer then return true, "ally" end
    if LocalPlayer.Team and player.Team then
        return LocalPlayer.Team == player.Team, player.Team.Name
    end
    local lc = LocalPlayer.Character
    local c = player.Character
    if not lc or not c then return nil, "unknown" end
    local lcont = lc.Parent
    local tcont = c.Parent
    if not lcont or not tcont or lcont == Workspace or tcont == Workspace then
        return nil, "unknown"
    end
    local friendly = lcont == tcont
    return friendly, friendly and "ally" or "enemy"
end

local function isTeammate(player)
    local friendly = getPlayerTeamState(player)
    return friendly == true
end

local function isHostile(player)
    if not player or player == LocalPlayer then return false end
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return false end
    if not Controller.Settings.MinesTeamCheck then return true end
    local state = getPlayerTeamState(player)
    return state == false
end

-- =========================================================================
-- SILENT AIM TARGETING
-- =========================================================================
local SilentAimRandom = Random.new()
local LastSilentTargetUpdate = 0

local function getSilentTargetPart(player, randomize)
    local character = player and player.Character
    if not character then return nil end
    local selected = Controller.Settings.SilentAimTargetPart
    local names
    if selected == "Random" then
        names = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" }
        if randomize then
            for index = #names, 2, -1 do
                local other = SilentAimRandom:NextInteger(1, index)
                names[index], names[other] = names[other], names[index]
            end
        end
    else
        names = { selected, "Head", "UpperTorso", "Torso", "HumanoidRootPart" }
    end
    for _, name in ipairs(names) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return getAnchor(character)
end

local function getSilentDronePart(model)
    if not model or not model:IsA("Model") then return nil end
    local hitbox = model:FindFirstChild("hitbox")
    if hitbox and hitbox:IsA("BasePart") then return hitbox end
    local ap = model:FindFirstChild("AimPoint")
    if ap and ap:IsA("BasePart") then return ap end
    return getAnchor(model)
end

local function isSilentTargetVisible(container, part, camera)
    if not Controller.Settings.SilentAimVisibilityCheck then return true end
    if not container or not part or not camera then return false end
    local now = os.clock()
    local cached = Controller.VisibilityCache[container]
    if cached and now - cached.t < CONST.VISIBILITY_CACHE_TTL then return cached.v end

    local exclusions = { camera }
    if LocalPlayer.Character then table.insert(exclusions, LocalPlayer.Character) end
    local ignore = Workspace:FindFirstChild("ignore")
    if ignore then table.insert(exclusions, ignore) end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = true

    local origin = camera.CFrame.Position
    local result = Workspace:Raycast(origin, part.Position - origin, params)
    local visible = result == nil or result.Instance:IsDescendantOf(container)
    Controller.VisibilityCache[container] = { t = now, v = visible }
    return visible
end

local function isSilentPlayerEligible(player, part, camera)
    if not player or player == LocalPlayer or not part then return false end
    if isIgnored(player) then return false end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not character:IsDescendantOf(Workspace)
        or (humanoid and humanoid.Health <= 0)
        or (Controller.Settings.SilentAimTeamCheck and isTeammate(player)) then
        return false
    end
    local distance = (part.Position - camera.CFrame.Position).Magnitude
    return distance <= Controller.Settings.SilentAimMaxDistance
        and isSilentTargetVisible(character, part, camera)
end

local function isSilentDroneEligible(model, part, camera)
    if not model or not model:IsA("Model") or not part or not model:IsDescendantOf(Workspace) then
        return false
    end
    local ownerName = model:GetAttribute("player")
    local throttle = model:GetAttribute("throttle")
    if type(ownerName) ~= "string" or ownerName == "" or throttle == nil then return false end
    local ownerPlayer = Players:FindFirstChild(ownerName)
    if ownerPlayer == LocalPlayer then return false end
    if ownerPlayer and isIgnored(ownerPlayer) then return false end
    if Controller.Settings.SilentAimTeamCheck and ownerPlayer and isTeammate(ownerPlayer) then
        return false
    end
    local distance = (part.Position - camera.CFrame.Position).Magnitude
    return distance <= Controller.Settings.SilentAimMaxDistance
        and isSilentTargetVisible(model, part, camera)
end

local function getPriorityScore(kind, target, part, camera, center)
    local priority = Controller.Settings.SilentAimTargetPriority
    if priority == "Closest distance" then
        return (part.Position - camera.CFrame.Position).Magnitude
    elseif priority == "Lowest health" then
        if kind == "Player" then
            local hum = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
            return hum and hum.Health or math.huge
        end
        return math.huge
    end
    local sp = camera:WorldToViewportPoint(part.Position)
    return (Vector2.new(sp.X, sp.Y) - center).Magnitude
end

local function updateSilentAimTarget(camera)
    local settings = Controller.Settings
    local center = camera.ViewportSize * 0.5

    local fovVisible = settings.SilentAimEnabled and settings.SilentAimShowFOV
    local useSquare = settings.SilentAimFOVShape == "Square"

    if SilentFOVCircle then
        SilentFOVCircle.Position = center
        SilentFOVCircle.Radius = settings.SilentAimFOV
        SilentFOVCircle.Thickness = settings.SilentAimFOVThickness
        SilentFOVCircle.Transparency = settings.SilentAimFOVOpacity
        SilentFOVCircle.Visible = fovVisible and not useSquare
    end
    if SilentFOVSquare then
        SilentFOVSquare.Position = Vector2.new(center.X - settings.SilentAimFOV, center.Y - settings.SilentAimFOV)
        SilentFOVSquare.Size = Vector2.new(settings.SilentAimFOV * 2, settings.SilentAimFOV * 2)
        SilentFOVSquare.Thickness = settings.SilentAimFOVThickness
        SilentFOVSquare.Transparency = settings.SilentAimFOVOpacity
        SilentFOVSquare.Visible = fovVisible and useSquare
    end

    if not settings.SilentAimEnabled then
        Controller.SilentTarget = nil
        Controller.SilentTargetKind = nil
        if SilentFOVCircle then SilentFOVCircle.Color = settings.SilentAimFOVColor end
        if SilentFOVSquare then SilentFOVSquare.Color = settings.SilentAimFOVColor end
        return
    end

    local now = os.clock()
    if now - LastSilentTargetUpdate < CONST.SILENT_UPDATE_INTERVAL then
        local col = Controller.SilentTarget and settings.SilentAimLockedFOVColor or settings.SilentAimFOVColor
        if SilentFOVCircle then SilentFOVCircle.Color = col end
        if SilentFOVSquare then SilentFOVSquare.Color = col end
        return
    end

    LastSilentTargetUpdate = now
    local bestTarget, bestKind
    local bestScore = settings.SilentAimFOV
    local targetType = settings.SilentAimTargetType

    if targetType ~= "Drones" then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local part = getSilentTargetPart(player, false)
                if part then
                    local sp, on = camera:WorldToViewportPoint(part.Position)
                    if on and sp.Z > 0 then
                        local sd = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if sd <= settings.SilentAimFOV and sd <= bestScore
                            and isSilentPlayerEligible(player, part, camera) then
                            local score = getPriorityScore("Player", player, part, camera, center)
                            if not bestTarget or score < bestScore or bestKind ~= "Player" then
                                bestScore = score
                                bestTarget = player
                                bestKind = "Player"
                            end
                        end
                    end
                end
            end
        end
    end

    if targetType ~= "Players" then
        for model in pairs(Controller.DroneEntries) do
            local part = getSilentDronePart(model)
            if part then
                local sp, on = camera:WorldToViewportPoint(part.Position)
                if on and sp.Z > 0 then
                    local sd = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if sd <= settings.SilentAimFOV and isSilentDroneEligible(model, part, camera) then
                        local score = getPriorityScore("Drone", model, part, camera, center)
                        if not bestTarget or score < bestScore or bestKind == "Drone" then
                            bestScore = score
                            bestTarget = model
                            bestKind = "Drone"
                        end
                    end
                end
            end
        end
    end

    Controller.SilentTarget = bestTarget
    Controller.SilentTargetKind = bestKind
    local col = bestTarget and settings.SilentAimLockedFOVColor or settings.SilentAimFOVColor
    if SilentFOVCircle then SilentFOVCircle.Color = col end
    if SilentFOVSquare then SilentFOVSquare.Color = col end
end

-- =========================================================================
-- SILENT AIM HOOK
-- =========================================================================
local ProjectileModule
local CalculateDirectionTarget
local OriginalCalculateDirection
local HookedCalculateDirection

local function getSilentAimPoint(origin, speed, acceleration)
    local settings = Controller.Settings
    local target = Controller.SilentTarget
    local targetKind = Controller.SilentTargetKind
    local camera = Workspace.CurrentCamera
    local part, velocityPart
    local eligible = false

    if targetKind == "Drone" then
        part = getSilentDronePart(target)
        velocityPart = target and (target.PrimaryPart or part)
        eligible = camera and isSilentDroneEligible(target, part, camera) or false
    elseif targetKind == "Player" then
        part = getSilentTargetPart(target, true)
        velocityPart = part
        eligible = camera and isSilentPlayerEligible(target, part, camera) or false
    end

    if not eligible then return nil end
    if settings.SilentAimHitChance < 100
        and SilentAimRandom:NextNumber(0, 100) > settings.SilentAimHitChance then
        return nil
    end

    local aimPoint = part.Position
    if settings.SilentAimPrediction then
        local pspeed = type(speed) == "number" and math.abs(speed) or 0
        if pspeed > 0 then
            local travelTime = (aimPoint - origin).Magnitude / pspeed
            if velocityPart and velocityPart.AssemblyLinearVelocity then
                aimPoint = aimPoint + velocityPart.AssemblyLinearVelocity * travelTime
            end
            if typeof(acceleration) == "Vector3" then
                aimPoint = aimPoint - acceleration * travelTime * travelTime * 0.5
            end
        end
    end
    return aimPoint
end

local function getSilentTargetLabel()
    local target = Controller.SilentTarget
    if Controller.SilentTargetKind == "Drone" and target then
        return "Drone: " .. tostring(target:GetAttribute("player") or "unknown")
    end
    if Controller.SilentTargetKind == "Player" and target then
        return target.Name
    end
    return ""
end

local function installSilentAimHook()
    if Controller.FastCastHookInstalled then return true end
    if type(filtergc) ~= "function" then return false end
    local success, projectile = pcall(filtergc, "table", {
        Keys = { "object", "raycast", "calculateDirection", "makeSpread", "init", "providers", "new" }
    }, true)
    if not success or type(projectile) ~= "table"
        or type(projectile.calculateDirection) ~= "function" then
        return false
    end
    if type(hookfunction) ~= "function" then return false end

    ProjectileModule = projectile
    CalculateDirectionTarget = projectile.calculateDirection

    local function replacement(origin, cameraCFrame, ...)
        local result = OriginalCalculateDirection(origin, cameraCFrame, ...)
        Controller.FastCastCalls = Controller.FastCastCalls + 1
        local settings = Controller.Settings
        if not Controller.Unloaded
            and settings.SilentAimEnabled
            and typeof(origin) == "Vector3"
            and typeof(cameraCFrame) == "CFrame"
            and type(result) == "table" then
            local camera = Workspace.CurrentCamera
            local la = getAnchor(LocalPlayer.Character)
            local nearCam = camera and (origin - camera.CFrame.Position).Magnitude <= 25
            local nearChar = la and (origin - la.Position).Magnitude <= 30
            if nearCam or nearChar then
                local speed
                if typeof(result.castDirection) == "Vector3" then
                    speed = result.castDirection.Magnitude
                end
                if type(speed) ~= "number" or speed <= 0 then speed = 1000 end
                local divisor = math.max(1, settings.SilentAimGravityDivisor)
                local accel = Vector3.new(0, -Workspace.Gravity / divisor, 0)
                local ok, aimPoint = pcall(getSilentAimPoint, origin, speed, accel)
                if ok and aimPoint then
                    local md = aimPoint - origin
                    local cd = aimPoint - cameraCFrame.Position
                    if md.Magnitude > 0 and cd.Magnitude > 0 then
                        local cm = typeof(result.castDirection) == "Vector3"
                            and result.castDirection.Magnitude or speed
                        result.position = aimPoint
                        result.direction = md.Unit
                        result.rayDirection = cd.Unit
                        result.castDirection = result.rayDirection * cm
                        Controller.SilentRedirects = Controller.SilentRedirects + 1
                        Controller.LastSilentTarget = getSilentTargetLabel()
                    end
                end
            end
        end
        return result
    end

    HookedCalculateDirection = type(newcclosure) == "function"
        and newcclosure(replacement) or replacement

    local ok, original = pcall(hookfunction, CalculateDirectionTarget, HookedCalculateDirection)
    if not ok or type(original) ~= "function" then
        ProjectileModule = nil
        CalculateDirectionTarget = nil
        HookedCalculateDirection = nil
        return false
    end
    OriginalCalculateDirection = original
    Controller.FastCastHookInstalled = true
    return true
end

-- =========================================================================
-- RENDER HELPERS
-- =========================================================================
local function renderRearArrow(visual, anchor, color, camera)
    if not visual.ArrowTop then return end
    local settings = Controller.Settings
    local relative = camera.CFrame:PointToObjectSpace(anchor.Position)
    if not settings.DroneRearArrows or relative.Z <= 0 then
        setProperty(visual.ArrowTop, "Visible", false)
        setProperty(visual.ArrowBottom, "Visible", false)
        return
    end
    local dir = Vector2.new(relative.X, -relative.Y)
    if dir.Magnitude < 0.001 then dir = Vector2.new(1, 0) else dir = dir.Unit end
    local perp = Vector2.new(-dir.Y, dir.X)
    local center = camera.ViewportSize * 0.5
    local ac = center + dir * settings.RearArrowRadius
    local tip = ac + dir * settings.RearArrowSize
    local back = ac - dir * settings.RearArrowSize * 0.65
    local wing = settings.RearArrowSize * 0.8
    local upper = back + perp * wing
    local lower = back - perp * wing
    local th = math.max(2, settings.BoxThickness)

    setProperty(visual.ArrowTop, "From", upper)
    setProperty(visual.ArrowTop, "To", tip)
    setProperty(visual.ArrowTop, "Color", color)
    setProperty(visual.ArrowTop, "Thickness", th)
    setProperty(visual.ArrowTop, "Transparency", settings.Opacity)
    setProperty(visual.ArrowTop, "Visible", true)

    setProperty(visual.ArrowBottom, "From", lower)
    setProperty(visual.ArrowBottom, "To", tip)
    setProperty(visual.ArrowBottom, "Color", color)
    setProperty(visual.ArrowBottom, "Thickness", th)
    setProperty(visual.ArrowBottom, "Transparency", settings.Opacity)
    setProperty(visual.ArrowBottom, "Visible", true)
end

local function renderCorners(visual, position, size, color, transparency, thickness)
    if not visual.Corners then return end
    local cl = math.min(size.X, size.Y) * 0.25
    local x1, y1 = position.X, position.Y
    local x2, y2 = position.X + size.X, position.Y + size.Y
    local segments = {
        { Vector2.new(x1, y1), Vector2.new(x1 + cl, y1) },
        { Vector2.new(x1, y1), Vector2.new(x1, y1 + cl) },
        { Vector2.new(x2, y1), Vector2.new(x2 - cl, y1) },
        { Vector2.new(x2, y1), Vector2.new(x2, y1 + cl) },
        { Vector2.new(x1, y2), Vector2.new(x1 + cl, y2) },
        { Vector2.new(x1, y2), Vector2.new(x1, y2 - cl) },
        { Vector2.new(x2, y2), Vector2.new(x2 - cl, y2) },
        { Vector2.new(x2, y2), Vector2.new(x2, y2 - cl) },
    }
    for i, seg in ipairs(segments) do
        local line = visual.Corners[i]
        if line then
            setProperty(line, "From", seg[1])
            setProperty(line, "To", seg[2])
            setProperty(line, "Color", color)
            setProperty(line, "Thickness", thickness)
            setProperty(line, "Transparency", transparency)
            setProperty(line, "Visible", true)
        end
    end
end

local function renderHealthBar(visual, position, size, humanoid, transparency)
    if not visual.HealthBG or not humanoid then return end
    local maxH = math.max(1, humanoid.MaxHealth)
    local ratio = math.clamp(humanoid.Health / maxH, 0, 1)
    local bw = 3
    local bx = position.X - bw - 3
    local by = position.Y

    setProperty(visual.HealthBG, "Position", Vector2.new(bx, by))
    setProperty(visual.HealthBG, "Size", Vector2.new(bw, size.Y))
    setProperty(visual.HealthBG, "Transparency", math.clamp(transparency * 0.5, 0, 1))
    setProperty(visual.HealthBG, "Visible", true)

    local fh = size.Y * ratio
    local fy = by + (size.Y - fh)
    local barColor = Color3.fromHSV(ratio * 0.33, 0.85, 1)

    setProperty(visual.HealthFill, "Position", Vector2.new(bx, fy))
    setProperty(visual.HealthFill, "Size", Vector2.new(bw, fh))
    setProperty(visual.HealthFill, "Color", barColor)
    setProperty(visual.HealthFill, "Transparency", math.clamp(transparency * 0.15, 0, 1))
    setProperty(visual.HealthFill, "Visible", true)
end

local function renderSkeleton(visual, character, color, camera, transparency)
    if not visual.Skeleton or not character then return end
    local function screen(name)
        local part = character:FindFirstChild(name)
        if not part or not part:IsA("BasePart") then return nil end
        local sp, on = camera:WorldToViewportPoint(part.Position)
        if not on or sp.Z <= 0 then return nil end
        return Vector2.new(sp.X, sp.Y)
    end
    local head = screen("Head")
    local upper = screen("UpperTorso") or screen("Torso")
    local lower = screen("LowerTorso") or screen("HumanoidRootPart")
    local lua_ = screen("LeftUpperArm") or screen("Left Arm")
    local rua = screen("RightUpperArm") or screen("Right Arm")
    local lul = screen("LeftUpperLeg") or screen("Left Leg")
    local rul = screen("RightUpperLeg") or screen("Right Leg")
    local segments = {
        { head, upper }, { upper, lower },
        { upper, lua_ }, { upper, rua },
        { lower, lul }, { lower, rul },
    }
    for i, seg in ipairs(segments) do
        local line = visual.Skeleton[i]
        if line then
            if seg[1] and seg[2] then
                setProperty(line, "From", seg[1])
                setProperty(line, "To", seg[2])
                setProperty(line, "Color", color)
                setProperty(line, "Thickness", 1)
                setProperty(line, "Transparency", transparency)
                setProperty(line, "Visible", true)
            else
                setProperty(line, "Visible", false)
            end
        end
    end
end

local function renderVisual(visual, model, label, color, showBox, showText, showTracer, camera, humanoid)
    local position, size = getBounds(model, camera)
    if not position then
        hideVisual(visual)
        return
    end
    local settings = Controller.Settings
    local t = settings.Opacity

    if settings.PlayerBoxStyle == "Corners" and showBox and visual.Corners then
        setProperty(visual.Outline, "Visible", false)
        setProperty(visual.Box, "Visible", false)
        renderCorners(visual, position, size, color, t, math.max(1, settings.BoxThickness))
    else
        if visual.Corners then
            for _, l in ipairs(visual.Corners) do setProperty(l, "Visible", false) end
        end
        setProperty(visual.Outline, "Position", position)
        setProperty(visual.Outline, "Size", size)
        setProperty(visual.Outline, "Thickness", settings.BoxThickness + 2)
        setProperty(visual.Outline, "Transparency", t)
        setProperty(visual.Outline, "Visible", showBox)

        setProperty(visual.Box, "Position", position)
        setProperty(visual.Box, "Size", size)
        setProperty(visual.Box, "Color", color)
        setProperty(visual.Box, "Thickness", settings.BoxThickness)
        setProperty(visual.Box, "Transparency", t)
        setProperty(visual.Box, "Visible", showBox)
    end

    setProperty(visual.Text, "Text", label)
    setProperty(visual.Text, "Position", Vector2.new(position.X + size.X * 0.5, math.max(0, position.Y - settings.TextSize - 3)))
    setProperty(visual.Text, "Color", color)
    setProperty(visual.Text, "Size", settings.TextSize)
    setProperty(visual.Text, "Transparency", t)
    setProperty(visual.Text, "Visible", showText and label ~= "")

    setProperty(visual.Tracer, "From", Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y - 2))
    setProperty(visual.Tracer, "To", Vector2.new(position.X + size.X * 0.5, position.Y + size.Y))
    setProperty(visual.Tracer, "Color", color)
    setProperty(visual.Tracer, "Thickness", settings.BoxThickness)
    setProperty(visual.Tracer, "Transparency", t)
    setProperty(visual.Tracer, "Visible", showTracer)

    if settings.PlayerHealthBar and humanoid then
        renderHealthBar(visual, position, size, humanoid, t)
    else
        setProperty(visual.HealthBG, "Visible", false)
        setProperty(visual.HealthFill, "Visible", false)
    end
end

-- =========================================================================
-- PLAYER ESP
-- =========================================================================
local function getPlayerVisual(player)
    local v = Controller.PlayerEntries[player]
    if not v then
        v = createVisual(false)
        Controller.PlayerEntries[player] = v
    end
    return v
end

local function removePlayer(player)
    local v = Controller.PlayerEntries[player]
    if v then removeVisual(v); Controller.PlayerEntries[player] = nil end

    local c = player and player.Character
    if c then
        local chams = c:FindFirstChild("LostFrontESPChams")
        if chams then chams:Destroy() end
    end

    for model in pairs(Controller.DroneEntries) do
        if model:GetAttribute("player") == player.Name then
            local dv = Controller.DroneEntries[model]
            if dv then removeVisual(dv) end
            Controller.DroneEntries[model] = nil
        end
    end
end

local function updatePlayers(camera, origin)
    local s = Controller.Settings
    local present = {}
    local rendered = 0

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            present[player] = true
            local visual = getPlayerVisual(player)
            local character = player.Character
            local anchor = getAnchor(character)
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local teammate = isTeammate(player)

            local hide = not s.PlayerEnabled or not character
                or not character:IsDescendantOf(Workspace) or not anchor
                or (humanoid and humanoid.Health <= 0)
                or (teammate and not s.ShowTeammates)
                or isIgnored(player)

            if hide then
                hideVisual(visual)
                setChams(character, false)
            else
                local distance = (anchor.Position - origin).Magnitude
                if distance > s.PlayerMaxDistance or rendered >= CONST.MAX_ESP_TARGETS then
                    hideVisual(visual)
                    setChams(character, false)
                else
                    rendered = rendered + 1
                    local pieces = {}
                    if s.PlayerNames then
                        table.insert(pieces, player.DisplayName ~= player.Name
                            and player.DisplayName .. " (@" .. player.Name .. ")"
                            or player.Name)
                    end
                    if s.PlayerDistance then
                        table.insert(pieces, string.format("[%ds]", math.floor(distance + 0.5)))
                    end
                    local color = teammate and s.TeammateColor or s.EnemyColor
                    renderVisual(visual, character, table.concat(pieces, " "), color,
                        s.PlayerBoxes, s.PlayerNames or s.PlayerDistance, s.PlayerTracers, camera, humanoid)

                    if s.PlayerSkeleton then
                        renderSkeleton(visual, character, color, camera, s.Opacity)
                    else
                        for _, l in ipairs(visual.Skeleton or {}) do setProperty(l, "Visible", false) end
                    end

                    if s.PlayerChams then
                        setChams(character, true, s.ChamsColor)
                    else
                        setChams(character, false)
                    end
                end
            end
        end
    end

    for player in pairs(Controller.PlayerEntries) do
        if not present[player] then removePlayer(player) end
    end
end

-- =========================================================================
-- DRONE ESP
-- =========================================================================
local function looksLikeDrone(model)
    if not model or not model:IsA("Model") then return false end
    local owner = model:GetAttribute("player")
    local throttle = model:GetAttribute("throttle")
    if type(owner) ~= "string" or owner == "" or throttle == nil then return false end
    local propellers = model:FindFirstChild("propellers")
    local pp = model.PrimaryPart
    local ra = pp and pp:FindFirstChild("RootAttachment")
    return propellers ~= nil or ra ~= nil
end

local function registerDrone(model)
    if Controller.DroneEntries[model] or not looksLikeDrone(model) then return end
    Controller.DroneEntries[model] = createVisual(true)
end

local function removeDrone(model)
    local v = Controller.DroneEntries[model]
    if v then removeVisual(v); Controller.DroneEntries[model] = nil end
end

local function discoverDrones()
    local candidates = {}
    local ok, result = pcall(function()
        return Workspace:QueryDescendants("Model[$player], Model[$throttle], Model:has(#propellers)")
    end)
    if ok and type(result) == "table" then
        candidates = result
    else
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("Model") and looksLikeDrone(d) then
                table.insert(candidates, d)
            end
        end
    end
    for _, c in ipairs(candidates) do registerDrone(c) end
end

local function updateDrones(camera, origin)
    local s = Controller.Settings
    for model, visual in pairs(Controller.DroneEntries) do
        if not model.Parent or not model:IsDescendantOf(Workspace) or not looksLikeDrone(model) then
            removeDrone(model)
        else
            local anchor = getAnchor(model)
            local ownerName = model:GetAttribute("player")
            local isOwn = ownerName == LocalPlayer.Name
            local hide = not s.DroneEnabled or not anchor or (isOwn and not s.ShowOwnDrone)

            if hide then
                hideVisual(visual)
            else
                local distance = (anchor.Position - origin).Magnitude
                if distance > s.DroneMaxDistance then
                    hideVisual(visual)
                else
                    local ownerPlayer = Players:FindFirstChild(ownerName)
                    local friendly, teamName = getPlayerTeamState(ownerPlayer)
                    local color
                    if friendly == true then color = s.FriendlyDroneColor
                    elseif friendly == false then color = s.EnemyDroneColor
                    else color = s.UnknownDroneColor end

                    if s.DroneTeamCheck and friendly == true and not isOwn then
                        hideVisual(visual)
                    else
                        local pieces = {}
                        if s.DroneNames then table.insert(pieces, "Drone: " .. ownerName) end
                        if s.DroneTeams then table.insert(pieces, "[" .. string.upper(teamName) .. "]") end
                        if s.DroneDistance then table.insert(pieces, string.format("[%ds]", math.floor(distance + 0.5))) end
                        renderVisual(visual, model, table.concat(pieces, " "), color,
                            s.DroneBoxes, s.DroneNames or s.DroneTeams or s.DroneDistance,
                            s.DroneTracers, camera, nil)
                        renderRearArrow(visual, anchor, color, camera)
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- WEAPON ESP + AUTO-COLLECT
-- =========================================================================
local WeaponState = {
    collected = 0,
    failed = 0,
    windowStart = os.clock(),
    windowCount = 0,
    lastAttempt = setmetatable({}, { __mode = "k" }),
}

local CollectRemote = nil
do
    local ok, remote = pcall(function()
        return game.ReplicatedStorage.network.pickup.collect
    end)
    if ok and remote then CollectRemote = remote end
end

local function getDroppedFolder()
    local debris = Workspace:FindFirstChild("debris")
    return debris and debris:FindFirstChild("dropped")
end

local function weaponRateLimitOk()
    local now = os.clock()
    if now - WeaponState.windowStart >= 1 then
        WeaponState.windowStart = now
        WeaponState.windowCount = 0
    end
    if WeaponState.windowCount >= Controller.Settings.WeaponRateLimit then return false end
    WeaponState.windowCount = WeaponState.windowCount + 1
    return true
end

local function tryCollectWeapon(item)
    if not CollectRemote then return end
    local s = Controller.Settings
    local now = os.clock()
    if WeaponState.lastAttempt[item] and now - WeaponState.lastAttempt[item] < s.WeaponCooldown then
        return
    end
    if not weaponRateLimitOk() then return end
    WeaponState.lastAttempt[item] = now

    local ok = pcall(function() CollectRemote:FireServer(item) end)
    if ok then WeaponState.collected = WeaponState.collected + 1
    else WeaponState.failed = WeaponState.failed + 1 end
end

local function scanAndCollectWeapons()
    if not Controller.Settings.WeaponAutoCollect or not CollectRemote then return end
    local folder = getDroppedFolder()
    if not folder then return end
    local root = LocalPlayer.Character
        and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character.PrimaryPart)
    if not root then return end

    local s = Controller.Settings
    for _, item in ipairs(folder:GetChildren()) do
        local anchor = getAnchor(item)
        if anchor then
            local dist = (anchor.Position - root.Position).Magnitude
            if dist <= s.WeaponCollectDistance then
                tryCollectWeapon(item)
            elseif s.WeaponTeleport then
                local original = root.CFrame
                root.CFrame = CFrame.new(anchor.Position + s.WeaponTeleportOffset)
                task.wait(s.WeaponTeleportDelay)
                tryCollectWeapon(item)
                root.CFrame = original
                task.wait(s.WeaponTeleportDelay)
            end
        end
    end
end

local function getWeaponVisual(item)
    local v = Controller.WeaponEntries[item]
    if not v then
        v = {
            highlight = nil,
            text = safeDrawing("Text", {
                Visible = false, Center = true, Outline = true,
                OutlineColor = Color3.new(0, 0, 0),
                Color = Controller.Settings.WeaponHighlightColor,
                Size = 14,
                Font = Drawing.Fonts and (Drawing.Fonts.Plex or Drawing.Fonts.UI) or 2,
                Transparency = 1, ZIndex = 10,
            })
        }
        Controller.WeaponEntries[item] = v
    end
    return v
end

local function ensureWeaponHighlight(item, v)
    if not Controller.Settings.WeaponHighlight then
        if v.highlight then v.highlight.Enabled = false end
        return
    end
    if not v.highlight and item.Parent then
        local ok, hl = pcall(function()
            local h = Instance.new("Highlight")
            h.Name = "ItemESP"
            h.Adornee = item
            h.FillColor = Controller.Settings.WeaponHighlightColor
            h.OutlineColor = Controller.Settings.WeaponHighlightColor
            h.FillTransparency = 0.6
            h.OutlineTransparency = 0
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = item
            return h
        end)
        if ok then v.highlight = hl end
    elseif v.highlight then
        v.highlight.Enabled = true
        v.highlight.FillColor = Controller.Settings.WeaponHighlightColor
        v.highlight.OutlineColor = Controller.Settings.WeaponHighlightColor
    end
end

local function removeWeaponEntry(item)
    local v = Controller.WeaponEntries[item]
    if not v then return end
    if v.highlight then pcall(function() v.highlight:Destroy() end) end
    if v.text then removeDrawing(v.text) end
    Controller.WeaponEntries[item] = nil
end

local function updateWeapons(camera, origin)
    local s = Controller.Settings
    local folder = getDroppedFolder()

    if folder then
        for _, item in ipairs(folder:GetChildren()) do
            local v = getWeaponVisual(item)
            local anchor = getAnchor(item)
            if anchor and s.WeaponEnabled then
                local distance = (anchor.Position - origin).Magnitude
                if distance <= s.WeaponMaxDistance then
                    ensureWeaponHighlight(item, v)
                    if v.highlight then v.highlight.Enabled = s.WeaponHighlight end

                    local t = v.text
                    if t then
                        if s.WeaponText then
                            local sp, on = camera:WorldToViewportPoint(anchor.Position)
                            if on and sp.Z > 0 then
                                local pieces = {}
                                if s.WeaponNames then table.insert(pieces, item.Name) end
                                if s.WeaponDistance then
                                    table.insert(pieces, string.format("[%dm]", math.floor(distance + 0.5)))
                                end
                                t.Text = table.concat(pieces, " ")
                                t.Position = Vector2.new(sp.X, sp.Y - 20)
                                t.Color = s.WeaponHighlightColor
                                t.Visible = true
                            else
                                t.Visible = false
                            end
                        else
                            t.Visible = false
                        end
                    end
                else
                    if v.highlight then v.highlight.Enabled = false end
                    if v.text then v.text.Visible = false end
                end
            else
                if v.highlight then v.highlight.Enabled = false end
                if v.text then v.text.Visible = false end
            end
        end

        for item, _ in pairs(Controller.WeaponEntries) do
            if not item.Parent or not item:IsDescendantOf(folder) then
                removeWeaponEntry(item)
            end
        end
    end
end

-- =========================================================================
-- SISTEMA DE MINAS
-- =========================================================================
local network = game.ReplicatedStorage:WaitForChild("network")
local buildItem  = network:FindFirstChild("buildItem")
local explodeRemote = network:FindFirstChild("explodeDrone")

-- tenta achar o remote de input do drone (vários nomes)
local droneInputRemote = nil
do
    for _, name in ipairs({
        "droneInput", "droneControl", "controlDrone",
        "drone", "controller", "input", "drone_input",
        "control", "cmdDrone", "sendInput"
    }) do
        local r = network:FindFirstChild(name)
        if r then
            droneInputRemote = r
            break
        end
    end
end

local function getPlaceables() return Workspace:FindFirstChild("placeables") end

local function getDronePos(d)
    local pp = d.PrimaryPart
    if pp then return pp.Position end
    local bp = d:FindFirstChildWhichIsA("BasePart", true)
    return bp and bp.Position
end

local function isMyDrone(m)
    if not m or not m:IsA("Model") then return false end
    local o = m:GetAttribute("player")
    if o then return tostring(o) == LocalPlayer.Name end
    return m.Name:find(tostring(LocalPlayer.UserId), 1, true) ~= nil
end

local function getGroundCFrame()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local s = Controller.Settings
    local origin = root.Position + root.CFrame.LookVector * s.MinesPlaceDistance + Vector3.new(0, 10, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char, Workspace:FindFirstChild("buildables") }
    params.IgnoreWater = true
    local hit = Workspace:Raycast(origin, Vector3.new(0, -50, 0), params)
    if not hit or hit.Normal:Dot(Vector3.new(0,1,0)) < 0.93 then return nil end
    local _, yaw = Workspace.CurrentCamera.CFrame:ToOrientation()
    return CFrame.new(hit.Position) * CFrame.Angles(0, yaw, 0)
end

local function tryAutoPlace()
    if not buildItem then
        setMineStatus("❌ buildItem não existe")
        return
    end
    local cf = getGroundCFrame()
    if not cf then
        setMineStatus("❌ Chão inválido")
        Controller.MineStats.failed += 1
        return
    end
    local ok, res, err = pcall(function() return buildItem:InvokeServer(Controller.Settings.MinesFPVSlot, cf) end)
    if ok and res then
        setMineStatus("✅ Plantado")
    else
        Controller.MineStats.failed += 1
        setMineStatus("❌ " .. tostring(err or res or "erro"))
    end
end

local function detonateMine(drone)
    if not drone or not drone.Parent then return end

    if droneInputRemote then
        pcall(function() droneInputRemote:FireServer(drone.Name, "detonate") end)
    end
    if explodeRemote then
        pcall(function() explodeRemote:FireServer(drone.Name) end)
    end
    -- fallback: procura qualquer remote com "explode" ou "detonat"
    for _, c in ipairs(network:GetChildren()) do
        if c:IsA("RemoteEvent") then
            local n = c.Name:lower()
            if n:find("explode") or n:find("detonat") then
                pcall(function() c:FireServer(drone.Name) end)
            end
        end
    end

    Controller.MineEntries[drone] = nil
    Controller.MineStats.detonated += 1
    setMineStatus("💥 Detonou")
end

local function detonateAllMines()
    local n = 0
    for d in pairs(Controller.MineEntries) do
        detonateMine(d)
        n += 1
    end
    if n > 0 then setMineStatus("💥 Detonou " .. n) end
end

-- Cria visual (texto) pra cada mina
local function createMineVisual(drone)
    if not Controller.Settings.MinesShowESP then return nil end
    return {
        text = safeDrawing("Text", {
            Visible = false, Center = true, Outline = true,
            OutlineColor = Color3.new(0, 0, 0),
            Color = Controller.Settings.MinesESPColor,
            Size = 14,
            Font = Drawing.Fonts and (Drawing.Fonts.Plex or Drawing.Fonts.UI) or 2,
            Transparency = 1, ZIndex = 10,
        })
    }
end

local function removeMineVisual(v)
    if v and v.text then removeDrawing(v.text) end
end

-- poll pra descobrir drones novos
task.spawn(function()
    while true do
        if not Controller.Unloaded then
            local folder = getPlaceables()
            if folder then
                for _, d in ipairs(folder:GetChildren()) do
                    if isMyDrone(d) and not Controller.MineEntries[d] then
                        local pos = getDronePos(d)
                        if pos then
                            local v = createMineVisual(d)
                            Controller.MineEntries[d] = {
                                pos = pos,
                                plantedAt = os.clock(),
                                lastDist = math.huge,
                                visual = v,
                            }
                            Controller.MineStats.registered += 1
                            setMineStatus("💣 Mina registrada")
                        end
                    end
                end
            end
            -- limpa órfãos
            for d, data in pairs(Controller.MineEntries) do
                if not d.Parent then
                    removeMineVisual(data.visual)
                    Controller.MineEntries[d] = nil
                end
            end
        end
        task.wait(CONST.MINE_POLL_INTERVAL)
    end
end)

-- loop de detecção + render das minas
task.spawn(function()
    while true do
        if not Controller.Unloaded then
            local s = Controller.Settings
            local camera = Workspace.CurrentCamera
            for drone, data in pairs(Controller.MineEntries) do
                if not drone.Parent then
                    removeMineVisual(data.visual)
                    Controller.MineEntries[drone] = nil
                else
                    local pos = getDronePos(drone)
                    if pos then
                        data.pos = pos

                        if s.MinesEnabled and s.MinesAutoTrigger then
                            local cd = math.huge
                            for _, p in ipairs(Players:GetPlayers()) do
                                if isHostile(p) then
                                    local c = p.Character
                                    local r = c and c:FindFirstChild("HumanoidRootPart")
                                    if r then
                                        local d = (r.Position - pos).Magnitude
                                        if d < cd then cd = d end
                                        if d <= s.MinesTriggerRadius then
                                            detonateMine(drone)
                                            break
                                        end
                                    end
                                end
                            end
                            data.lastDist = cd
                        end

                        -- render
                        local v = data.visual
                        if v and v.text and camera then
                            if s.MinesShowESP and s.MinesESPText then
                                local sp, on = camera:WorldToViewportPoint(pos)
                                if on and sp.Z > 0 then
                                    local myPos = getDistanceOrigin(camera)
                                    local d = (pos - myPos).Magnitude
                                    v.text.Text = string.format("💣 [%dm]", math.floor(d + 0.5))
                                    v.text.Position = Vector2.new(sp.X, sp.Y - 20)
                                    v.text.Color = s.MinesESPColor
                                    v.text.Visible = true
                                else
                                    v.text.Visible = false
                                end
                            else
                                v.text.Visible = false
                            end
                        end
                    end
                end
            end
        end
        task.wait(CONST.MINE_SCAN_INTERVAL)
    end
end)

-- =========================================================================
-- WATERMARK UPDATE
-- =========================================================================
local FPS_Frames = 0
local FPS_Accum = 0
local FPS_Value = 60

local function updateWatermark(dt)
    if not Watermark then return end
    if not Controller.Settings.WatermarkEnabled then
        Watermark.Visible = false
        return
    end
    FPS_Frames = FPS_Frames + 1
    FPS_Accum = FPS_Accum + dt
    if FPS_Accum >= 0.5 then
        FPS_Value = math.floor(FPS_Frames / FPS_Accum + 0.5)
        FPS_Frames = 0
        FPS_Accum = 0
    end
    local tlabel = Controller.LastSilentTarget ~= "" and (" | Target: " .. Controller.LastSilentTarget) or ""
    Watermark.Text = string.format(
        "Lost Front | FPS: %d | Silent: %d | Mines: %d%s",
        FPS_Value, Controller.SilentRedirects, Controller.MineStats.detonated, tlabel
    )
    Watermark.Visible = true
end

-- =========================================================================
-- INITIAL HOOK
-- =========================================================================
installSilentAimHook()

-- =========================================================================
-- CLEANUP
-- =========================================================================
local function cleanup()
    if Controller.Unloaded then return end
    Controller.Unloaded = true
    Controller.SilentTarget = nil
    Controller.SilentTargetKind = nil

    setProperty(SilentFOVCircle, "Visible", false)
    setProperty(SilentFOVSquare, "Visible", false)
    setProperty(Watermark, "Visible", false)

    for _, c in ipairs(Controller.Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(Controller.Connections)

    for player, v in pairs(Controller.PlayerEntries) do removeVisual(v); Controller.PlayerEntries[player] = nil end
    for model, v in pairs(Controller.DroneEntries) do removeVisual(v); Controller.DroneEntries[model] = nil end
    for item, _ in pairs(Controller.WeaponEntries) do removeWeaponEntry(item) end
    for drone, data in pairs(Controller.MineEntries) do removeMineVisual(data.visual) end
    table.clear(Controller.MineEntries)

    for _, player in ipairs(Players:GetPlayers()) do
        local c = player.Character
        if c then
            local chams = c:FindFirstChild("LostFrontESPChams")
            if chams then chams:Destroy() end
        end
    end

    removeDrawing(SilentFOVCircle)
    removeDrawing(SilentFOVSquare)
    removeDrawing(Watermark)

    if CalculateDirectionTarget then
        if type(restorefunction) == "function" then
            pcall(restorefunction, CalculateDirectionTarget)
        elseif type(hookfunction) == "function" and OriginalCalculateDirection then
            pcall(hookfunction, CalculateDirectionTarget, OriginalCalculateDirection)
        end
    end
    Controller.FastCastHookInstalled = false

    if Environment.LostFrontDrawingESP == Controller then
        Environment.LostFrontDrawingESP = nil
    end
end

Controller.Unload = function()
    if Controller.Unloaded then return end
    if Library and not Library.Unloaded then Library:Unload()
    else cleanup() end
end

-- =========================================================================
-- UI
-- =========================================================================
Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local GameTitle = "The Lost Front"
local WindowIconTitle = "Lost Front"
local CommunityText = "t.me/arceusxcommunity"

pcall(function()
    local response = game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
    local text = response:match("^%s*(.-)%s*$")
    if text ~= "" then CommunityText = text end
end)

local Window = Library:CreateWindow({
    Title = WindowIconTitle,
    Footer = GameTitle .. " | " .. CommunityText,
    NotifySide = "Right",
    ShowCustomCursor = not Library.IsMobile,
    ShowMobileButtons = true,
    MobileButtonsSide = "Left",
    AutoShow = true,
    Center = true,
    Resizable = true,
    Size = UDim2.fromOffset(620, 520),
    ToggleKeybind = Enum.KeyCode.F1
})

Window:ChangeTitle(GameTitle)

local Tabs = {}
Tabs.SilentAim = Window:AddTab("Silent Aim", "crosshair", "")
Tabs.ESP = Window:AddTab("ESP", "scan-eye", "")
Tabs.Itens = Window:AddTab("Itens", "package", "")
Tabs.Minas = Window:AddTab("Minas", "bomb", "")
Tabs.Settings = Window:AddTab("UI Settings", "settings", "")

-- =========================================================================
-- ABA SILENT AIM
-- =========================================================================
local SilentMainGroup = Tabs.SilentAim:AddLeftGroupbox("Silent Aim", "crosshair")
local SilentTargetGroup = Tabs.SilentAim:AddRightGroupbox("Targeting", "scan-search")
local SilentVisualGroup = Tabs.SilentAim:AddLeftGroupbox("FOV", "circle-dot")

SilentMainGroup:AddToggle("SilentAimEnabled", {
    Text = "Enabled", Default = true,
    Callback = function(v)
        Controller.Settings.SilentAimEnabled = v
        if not v then Controller.SilentTarget = nil; Controller.SilentTargetKind = nil end
    end
})
SilentMainGroup:AddToggle("SilentAimTeamCheck", {
    Text = "Team check", Default = true,
    Callback = function(v) Controller.Settings.SilentAimTeamCheck = v end
})
SilentMainGroup:AddToggle("SilentAimVisibilityCheck", {
    Text = "Visibility check", Default = true,
    Callback = function(v) Controller.Settings.SilentAimVisibilityCheck = v end
})
SilentMainGroup:AddToggle("SilentAimPrediction", {
    Text = "Movement and drop prediction", Default = true,
    Callback = function(v) Controller.Settings.SilentAimPrediction = v end
})
SilentMainGroup:AddSlider("SilentAimHitChance", {
    Text = "Hit chance", Default = 100, Min = 0, Max = 100, Rounding = 0, Suffix = "%",
    Callback = function(v) Controller.Settings.SilentAimHitChance = v end
})
SilentMainGroup:AddSlider("SilentAimGravityDivisor", {
    Text = "Gravity divisor (prediction)", Default = 8, Min = 1, Max = 30, Rounding = 0,
    Callback = function(v) Controller.Settings.SilentAimGravityDivisor = v end
})
SilentMainGroup:AddInput("SilentAimIgnoreList", {
    Default = "",
    Text = "Ignore list (nomes separados por vírgula)",
    Placeholder = "Player1, Player2, ...",
    Callback = function(v) Controller.Settings.SilentAimIgnoreList = v; rebuildIgnoreList() end
})

SilentTargetGroup:AddDropdown("SilentAimTargetType", {
    Values = { "Players and Drones", "Players", "Drones" },
    Default = "Players and Drones", Multi = false, Text = "Target type",
    Callback = function(v)
        Controller.Settings.SilentAimTargetType = v
        Controller.SilentTarget = nil; Controller.SilentTargetKind = nil
    end
})
SilentTargetGroup:AddDropdown("SilentAimTargetPart", {
    Values = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Random" },
    Default = "Head", Multi = false, Text = "Player target part",
    Callback = function(v) Controller.Settings.SilentAimTargetPart = v end
})
SilentTargetGroup:AddDropdown("SilentAimTargetPriority", {
    Values = { "Closest to crosshair", "Closest distance", "Lowest health" },
    Default = "Closest to crosshair", Multi = false, Text = "Target priority",
    Callback = function(v) Controller.Settings.SilentAimTargetPriority = v end
})
SilentTargetGroup:AddSlider("SilentAimFOV", {
    Text = "FOV radius", Default = 150, Min = 20, Max = 500, Rounding = 0, Suffix = " px",
    Callback = function(v) Controller.Settings.SilentAimFOV = v end
})
SilentTargetGroup:AddSlider("SilentAimMaxDistance", {
    Text = "Max distance", Default = 2500, Min = 100, Max = 5000, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.SilentAimMaxDistance = v end
})

SilentVisualGroup:AddDropdown("SilentAimFOVShape", {
    Values = { "Circle", "Square" }, Default = "Circle", Multi = false, Text = "FOV shape",
    Callback = function(v) Controller.Settings.SilentAimFOVShape = v end
})
SilentVisualGroup:AddToggle("SilentAimShowFOV", {
    Text = "Show FOV", Default = true,
    Callback = function(v) Controller.Settings.SilentAimShowFOV = v end
})
SilentVisualGroup:AddSlider("SilentAimFOVThickness", {
    Text = "FOV thickness", Default = 1, Min = 1, Max = 4, Rounding = 0,
    Callback = function(v) Controller.Settings.SilentAimFOVThickness = v end
})
SilentVisualGroup:AddSlider("SilentAimFOVOpacity", {
    Text = "FOV opacity", Default = 80, Min = 10, Max = 100, Rounding = 0, Suffix = "%",
    Callback = function(v) Controller.Settings.SilentAimFOVOpacity = v / 100 end
})
SilentVisualGroup:AddLabel("FOV color"):AddColorPicker("SilentAimFOVColor", {
    Default = Controller.Settings.SilentAimFOVColor, Title = "FOV color",
    Callback = function(v) Controller.Settings.SilentAimFOVColor = v end
})
SilentVisualGroup:AddLabel("Locked FOV color"):AddColorPicker("SilentAimLockedFOVColor", {
    Default = Controller.Settings.SilentAimLockedFOVColor, Title = "Locked FOV color",
    Callback = function(v) Controller.Settings.SilentAimLockedFOVColor = v end
})

-- =========================================================================
-- ABA ESP
-- =========================================================================
local PlayerGroup = Tabs.ESP:AddLeftGroupbox("Players", "users")
local DroneGroup = Tabs.ESP:AddRightGroupbox("Drones", "plane")
local VisualGroup = Tabs.ESP:AddLeftGroupbox("Visuals", "palette")

PlayerGroup:AddToggle("PlayerESP", {
    Text = "Player ESP", Default = true,
    Callback = function(v) Controller.Settings.PlayerEnabled = v end
})
PlayerGroup:AddToggle("PlayerBoxes", {
    Text = "Boxes", Default = true,
    Callback = function(v) Controller.Settings.PlayerBoxes = v end
})
PlayerGroup:AddDropdown("PlayerBoxStyle", {
    Values = { "Full", "Corners" }, Default = "Full", Multi = false, Text = "Box style",
    Callback = function(v) Controller.Settings.PlayerBoxStyle = v end
})
PlayerGroup:AddToggle("PlayerNames", {
    Text = "Names", Default = true,
    Callback = function(v) Controller.Settings.PlayerNames = v end
})
PlayerGroup:AddToggle("PlayerDistance", {
    Text = "Distance", Default = true,
    Callback = function(v) Controller.Settings.PlayerDistance = v end
})
PlayerGroup:AddToggle("PlayerHealthBar", {
    Text = "Health bar", Default = false,
    Callback = function(v) Controller.Settings.PlayerHealthBar = v end
})
PlayerGroup:AddToggle("PlayerSkeleton", {
    Text = "Skeleton", Default = false,
    Callback = function(v) Controller.Settings.PlayerSkeleton = v end
})
PlayerGroup:AddToggle("PlayerChams", {
    Text = "Chams (Highlight)", Default = false,
    Callback = function(v) Controller.Settings.PlayerChams = v end
})
PlayerGroup:AddToggle("PlayerTracers", {
    Text = "Tracers", Default = false,
    Callback = function(v) Controller.Settings.PlayerTracers = v end
})
PlayerGroup:AddToggle("ShowTeammates", {
    Text = "Show teammates", Default = false,
    Callback = function(v) Controller.Settings.ShowTeammates = v end
})
PlayerGroup:AddSlider("PlayerMaxDistance", {
    Text = "Max distance", Default = 2500, Min = 100, Max = 5000, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.PlayerMaxDistance = v end
})

DroneGroup:AddToggle("DroneESP", {
    Text = "Drone ESP", Default = true,
    Callback = function(v) Controller.Settings.DroneEnabled = v end
})
DroneGroup:AddToggle("DroneBoxes", {
    Text = "Boxes", Default = true,
    Callback = function(v) Controller.Settings.DroneBoxes = v end
})
DroneGroup:AddToggle("DroneNames", {
    Text = "Owner names", Default = true,
    Callback = function(v) Controller.Settings.DroneNames = v end
})
DroneGroup:AddToggle("DroneTeams", {
    Text = "Team labels", Default = true,
    Callback = function(v) Controller.Settings.DroneTeams = v end
})
DroneGroup:AddToggle("DroneDistance", {
    Text = "Distance", Default = true,
    Callback = function(v) Controller.Settings.DroneDistance = v end
})
DroneGroup:AddToggle("DroneTracers", {
    Text = "Tracers", Default = false,
    Callback = function(v) Controller.Settings.DroneTracers = v end
})
DroneGroup:AddToggle("DroneRearArrows", {
    Text = "Rear drone arrows", Default = true,
    Callback = function(v) Controller.Settings.DroneRearArrows = v end
})
DroneGroup:AddToggle("DroneTeamCheck", {
    Text = "Team check", Default = true,
    Callback = function(v) Controller.Settings.DroneTeamCheck = v end
})
DroneGroup:AddToggle("ShowOwnDrone", {
    Text = "Show own drone", Default = false,
    Callback = function(v) Controller.Settings.ShowOwnDrone = v end
})
DroneGroup:AddSlider("DroneMaxDistance", {
    Text = "Max distance", Default = 2500, Min = 100, Max = 5000, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.DroneMaxDistance = v end
})
DroneGroup:AddButton({ Text = "Rescan drones", Func = discoverDrones })

VisualGroup:AddLabel("Enemy color"):AddColorPicker("EnemyColor", {
    Default = Controller.Settings.EnemyColor, Title = "Enemy color",
    Callback = function(v) Controller.Settings.EnemyColor = v end
})
VisualGroup:AddLabel("Teammate color"):AddColorPicker("TeammateColor", {
    Default = Controller.Settings.TeammateColor, Title = "Teammate color",
    Callback = function(v) Controller.Settings.TeammateColor = v end
})
VisualGroup:AddLabel("Chams color"):AddColorPicker("ChamsColor", {
    Default = Controller.Settings.ChamsColor, Title = "Chams color",
    Callback = function(v) Controller.Settings.ChamsColor = v end
})
VisualGroup:AddSlider("BoxThickness", {
    Text = "Box thickness", Default = 1, Min = 1, Max = 4, Rounding = 0,
    Callback = function(v) Controller.Settings.BoxThickness = v end
})
VisualGroup:AddSlider("TextSize", {
    Text = "Text size", Default = 13, Min = 10, Max = 24, Rounding = 0,
    Callback = function(v) Controller.Settings.TextSize = v end
})
VisualGroup:AddSlider("Opacity", {
    Text = "Opacity", Default = 100, Min = 20, Max = 100, Rounding = 0, Suffix = "%",
    Callback = function(v) Controller.Settings.Opacity = v / 100 end
})
VisualGroup:AddToggle("WatermarkEnabled", {
    Text = "Watermark", Default = true,
    Callback = function(v) Controller.Settings.WatermarkEnabled = v end
})

-- =========================================================================
-- ABA ITENS
-- =========================================================================
local WeaponESPToggleGroup = Tabs.Itens:AddLeftGroupbox("ESP de Itens", "scan-eye")
local WeaponCollectGroup = Tabs.Itens:AddRightGroupbox("Auto-Collect", "package-open")
local WeaponVisualGroup = Tabs.Itens:AddLeftGroupbox("Visual", "palette")

WeaponESPToggleGroup:AddToggle("WeaponEnabled", {
    Text = "Item ESP", Default = true,
    Callback = function(v) Controller.Settings.WeaponEnabled = v end
})
WeaponESPToggleGroup:AddToggle("WeaponHighlight", {
    Text = "Highlight (contorno)", Default = true,
    Callback = function(v) Controller.Settings.WeaponHighlight = v end
})
WeaponESPToggleGroup:AddToggle("WeaponText", {
    Text = "Texto flutuante", Default = true,
    Callback = function(v) Controller.Settings.WeaponText = v end
})
WeaponESPToggleGroup:AddToggle("WeaponNames", {
    Text = "Mostrar nome", Default = true,
    Callback = function(v) Controller.Settings.WeaponNames = v end
})
WeaponESPToggleGroup:AddToggle("WeaponDistance", {
    Text = "Mostrar distância", Default = true,
    Callback = function(v) Controller.Settings.WeaponDistance = v end
})
WeaponESPToggleGroup:AddSlider("WeaponMaxDistance", {
    Text = "Distância máxima (ESP)", Default = 500, Min = 50, Max = 3000, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.WeaponMaxDistance = v end
})

WeaponCollectGroup:AddToggle("WeaponAutoCollect", {
    Text = "Auto-Collect", Default = true,
    Callback = function(v) Controller.Settings.WeaponAutoCollect = v end
})
WeaponCollectGroup:AddToggle("WeaponTeleport", {
    Text = "Teleporte até o item", Default = false,
    Callback = function(v) Controller.Settings.WeaponTeleport = v end
})
WeaponCollectGroup:AddSlider("WeaponCollectDistance", {
    Text = "Distância de coleta", Default = 10, Min = 5, Max = 30, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.WeaponCollectDistance = v end
})
WeaponCollectGroup:AddSlider("WeaponCooldown", {
    Text = "Cooldown por item", Default = 15, Min = 5, Max = 100, Rounding = 0, Suffix = " (x10ms)",
    Callback = function(v) Controller.Settings.WeaponCooldown = v / 100 end
})
WeaponCollectGroup:AddSlider("WeaponRateLimit", {
    Text = "Rate limit (FireServer/s)", Default = 20, Min = 5, Max = 60, Rounding = 0,
    Callback = function(v) Controller.Settings.WeaponRateLimit = v end
})

WeaponVisualGroup:AddLabel("Cor do item"):AddColorPicker("WeaponHighlightColor", {
    Default = Controller.Settings.WeaponHighlightColor, Title = "Cor do item",
    Callback = function(v) Controller.Settings.WeaponHighlightColor = v end
})

-- =========================================================================
-- ABA MINAS
-- =========================================================================
local MineMainGroup = Tabs.Minas:AddLeftGroupbox("Sistema de Minas", "bomb")
local MineConfigGroup = Tabs.Minas:AddRightGroupbox("Configurações", "settings")
local MineInfoGroup = Tabs.Minas:AddLeftGroupbox("Info & Teclas", "keyboard")

MineMainGroup:AddToggle("MinesEnabled", {
    Text = "Ativado", Default = true,
    Callback = function(v) Controller.Settings.MinesEnabled = v end
})
MineMainGroup:AddToggle("MinesAutoTrigger", {
    Text = "Detonar automático (inimigo perto)", Default = true,
    Callback = function(v) Controller.Settings.MinesAutoTrigger = v end
})
MineMainGroup:AddSlider("MinesTriggerRadius", {
    Text = "Raio de detecção", Default = 25, Min = 5, Max = 100, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.MinesTriggerRadius = v end
})
MineMainGroup:AddToggle("MinesTeamCheck", {
    Text = "Team check", Default = true,
    Callback = function(v) Controller.Settings.MinesTeamCheck = v end
})
MineMainGroup:AddToggle("MinesAutoPlace", {
    Text = "Auto-place (planta sozinho)", Default = false,
    Callback = function(v) Controller.Settings.MinesAutoPlace = v end
})
MineMainGroup:AddButton({
    Text = "💥 DETONAR TODAS AGORA",
    Func = detonateAllMines
})

MineConfigGroup:AddSlider("MinesCooldown", {
    Text = "Cooldown por drone", Default = 50, Min = 10, Max = 300, Rounding = 0, Suffix = " (x10ms)",
    Callback = function(v) Controller.Settings.MinesCooldown = v / 100 end
})
MineConfigGroup:AddSlider("MinesMaxActive", {
    Text = "Máximo de minas ativas", Default = 5, Min = 1, Max = 15, Rounding = 0,
    Callback = function(v) Controller.Settings.MinesMaxActive = v end
})
MineConfigGroup:AddSlider("MinesFPVSlot", {
    Text = "Slot do FPV (hotbar)", Default = 1, Min = 1, Max = 9, Rounding = 0,
    Callback = function(v) Controller.Settings.MinesFPVSlot = v end
})
MineConfigGroup:AddSlider("MinesPlaceDistance", {
    Text = "Distância à frente (auto-place)", Default = 6, Min = 3, Max = 15, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.MinesPlaceDistance = v end
})
MineConfigGroup:AddToggle("MinesShowESP", {
    Text = "Mostrar ESP das minas", Default = true,
    Callback = function(v) Controller.Settings.MinesShowESP = v end
})
MineConfigGroup:AddToggle("MinesESPText", {
    Text = "Texto da mina (nome + dist)", Default = true,
    Callback = function(v) Controller.Settings.MinesESPText = v end
})
MineConfigGroup:AddLabel("Cor do ESP"):AddColorPicker("MinesESPColor", {
    Default = Controller.Settings.MinesESPColor, Title = "Cor do ESP",
    Callback = function(v) Controller.Settings.MinesESPColor = v end
})

MineInfoGroup:AddLabel("Tecla — Detonar todas"):AddKeyPicker("MinesKeyDetonateAll", {
    Default = "B", Text = "Detonar todas", NoUI = false,
    Callback = function(v)
        Controller.Settings.MinesKeyDetonateAll = v
    end
})
MineInfoGroup:AddLabel("Tecla — Plantar (auto)"):AddKeyPicker("MinesKeyPlace", {
    Default = "Z", Text = "Plantar",
    Callback = function(v)
        Controller.Settings.MinesKeyPlace = v
    end
})
MineInfoGroup:AddLabel("Status:"):AddLabel("Status inicial", true)

-- label dinâmico (atualizado no loop)
local StatusLabel = MineInfoGroup:AddLabel("Aguardando...", true)

-- =========================================================================
-- ABA UI SETTINGS
-- =========================================================================
local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu", "wrench")
MenuGroup:AddDropdown("DPIScale", {
    Values = { "50%", "75%", "100%", "125%", "150%" },
    Default = Library.IsMobile and "75%" or "100%",
    Text = "DPI scale",
    Callback = function(value)
        Library:SetDPIScale(tonumber(value:gsub("%%", "")))
    end
})
MenuGroup:AddLabel("Menu keybind"):AddKeyPicker("MenuKeybind", {
    Default = "F1", NoUI = true, Text = "Menu keybind"
})
MenuGroup:AddLabel("The built-in mobile menu button is enabled.", true)
MenuGroup:AddButton({ Text = "Unload", Func = Controller.Unload })

Library.ToggleKeybind = Options.MenuKeybind
Library:OnUnload(cleanup)

-- =========================================================================
-- THEME + SAVE MANAGER (de volta)
-- =========================================================================
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("LostFrontESP")
SaveManager:SetFolder("LostFrontESP")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)

-- =========================================================================
-- CONNECTIONS
-- =========================================================================
addConnection(Players.PlayerRemoving:Connect(removePlayer))

addConnection(Workspace.DescendantAdded:Connect(function(descendant)
    if descendant:IsA("Model") then
        task.delay(CONST.DRONE_REGISTER_DELAY, function()
            if not Controller.Unloaded then registerDrone(descendant) end
        end)
    end
end))

-- detecta keybind pickers quando mudam
addConnection(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    local s = Controller.Settings

    -- detonar todas
    if Options.MinesKeyDetonateAll and Options.MinesKeyDetonateAll.Value then
        local keyStr = Options.MinesKeyDetonateAll.Value
        if keyStr and keyStr ~= "None" and input.KeyCode == Enum.KeyCode[keyStr] then
            detonateAllMines()
        end
    end

    -- plantar (auto-place)
    if Options.MinesKeyPlace and Options.MinesKeyPlace.Value then
        local keyStr = Options.MinesKeyPlace.Value
        if keyStr and keyStr ~= "None" and input.KeyCode == Enum.KeyCode[keyStr] then
            if s.MinesAutoPlace then
                tryAutoPlace()
            else
                setMineStatus("👀 Modo manual — plante no jogo")
            end
        end
    end
end))

local LastESPUpdate = 0
local LastWeaponScan = 0
local LastWeaponESPUpdate = 0

addConnection(RunService.RenderStepped:Connect(function(dt)
    if Controller.Unloaded then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end

    updateSilentAimTarget(camera)

    -- ESP (players/drones) a ~30 Hz
    LastESPUpdate = LastESPUpdate + dt
    if LastESPUpdate >= CONST.ESP_UPDATE_INTERVAL then
        LastESPUpdate = 0
        local origin = getDistanceOrigin(camera)
        updatePlayers(camera, origin)
        updateDrones(camera, origin)
    end

    -- Weapon ESP a ~30 Hz
    LastWeaponESPUpdate = LastWeaponESPUpdate + dt
    if LastWeaponESPUpdate >= 1 / 30 then
        LastWeaponESPUpdate = 0
        local origin = getDistanceOrigin(camera)
        updateWeapons(camera, origin)
    end

    -- Auto-collect a ~10 Hz
    LastWeaponScan = LastWeaponScan + dt
    if LastWeaponScan >= CONST.WEAPON_SCAN_INTERVAL then
        LastWeaponScan = 0
        pcall(scanAndCollectWeapons)
    end

    updateWatermark(dt)
end))

task.spawn(function()
    while not Controller.Unloaded do
        discoverDrones()
        task.wait(CONST.DRONE_RESCAN_INTERVAL)
    end
end)

-- atualiza o label de status das minas
task.spawn(function()
    while not Controller.Unloaded do
        if StatusLabel and StatusLabel.SetText then
            local s = Controller.Settings
            local mode = s.MinesAutoPlace and "AUTO" or "MANUAL"
            local txt = string.format("[%s] %s", mode, Controller.LastMineAction or "Pronto")
            pcall(function() StatusLabel:SetText(txt) end)
        end
        task.wait(0.5)
    end
end)

-- =========================================================================
-- INIT
-- =========================================================================
rebuildIgnoreList()

-- carrega config salva (autoload)
pcall(function() SaveManager:LoadAutoloadConfig() end)

if Toggles.SilentAimEnabled then
    Toggles.SilentAimEnabled:SetValue(true)
else
    Controller.Settings.SilentAimEnabled = true
end

print("[LostFront] Script carregado.")
print("[LostFront] Remotes:")
print("  buildItem:", buildItem and buildItem.ClassName or "nil")
print("  explodeDrone:", explodeRemote and explodeRemote.ClassName or "nil")
print("  droneInput:", droneInputRemote and droneInputRemote.Name or "NÃO ENCONTRADO")
