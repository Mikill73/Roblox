local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Environment = getgenv and getgenv() or shared

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
    MINE_POLL_INTERVAL = 0.4,
    MINE_CHECK_INTERVAL = 0.1,
    MINE_ACTIVATE_DELAY = 0.08,
}

if Environment.LostFrontDrawingESP and type(Environment.LostFrontDrawingESP.Unload) == "function" then
    pcall(Environment.LostFrontDrawingESP.Unload)
end
if not Drawing or type(Drawing.new) ~= "function" then error("Drawing library is not supported") end

local Repository = "https://raw.githubusercontent.com/Ali-lov3/Obsidian-UiLibs/refs/heads/main/"
local Library = loadstring(game:HttpGet(Repository .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(Repository .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(Repository .. "addons/SaveManager.lua"))()
local Options = Library.Options
local Toggles = Library.Toggles

local function getGuiParent()
    if gethui then local ok, h = pcall(gethui); if ok and h then return h end end
    if LocalPlayer:FindFirstChild("PlayerGui") then return LocalPlayer.PlayerGui end
    return game:GetService("CoreGui")
end

local Controller = {
    Unloaded = false, TeamRegistryFound = false, LocalTeam = "unknown",
    SilentTarget = nil, SilentTargetKind = nil,
    FastCastHookInstalled = false, FastCastCalls = 0, SilentRedirects = 0,
    LastSilentTarget = "", Connections = {},
    PlayerEntries = {}, DroneEntries = {}, WeaponEntries = {},
    IgnoreSet = {},
    VisibilityCache = setmetatable({}, { __mode = "k" }),
    BoundsCache = setmetatable({}, { __mode = "k" }),
    Settings = {
        SilentAimEnabled = true, SilentAimTeamCheck = true,
        SilentAimVisibilityCheck = true, SilentAimPrediction = true,
        SilentAimHitChance = 100, SilentAimTargetType = "Players and Drones",
        SilentAimTargetPart = "Head", SilentAimTargetPriority = "Closest to crosshair",
        SilentAimMaxDistance = 2500, SilentAimFOV = 150,
        SilentAimFOVShape = "Circle", SilentAimShowFOV = true,
        SilentAimFOVColor = Color3.fromRGB(255, 255, 255),
        SilentAimLockedFOVColor = Color3.fromRGB(80, 255, 140),
        SilentAimFOVThickness = 1, SilentAimFOVOpacity = 0.8,
        SilentAimGravityDivisor = 8, SilentAimIgnoreList = "",
        PlayerEnabled = true, PlayerBoxes = true, PlayerBoxStyle = "Full",
        PlayerNames = true, PlayerDistance = true, PlayerTracers = false,
        PlayerHealthBar = false, PlayerSkeleton = false, PlayerChams = false,
        ShowTeammates = false, PlayerMaxDistance = 2500,
        EnemyColor = Color3.fromRGB(255, 80, 80),
        TeammateColor = Color3.fromRGB(80, 180, 255),
        ChamsColor = Color3.fromRGB(255, 80, 80),
        DroneEnabled = true, DroneBoxes = true, DroneNames = true,
        DroneTeams = true, DroneDistance = true, DroneTracers = false,
        DroneRearArrows = true, DroneTeamCheck = true, ShowOwnDrone = false,
        DroneMaxDistance = 2500,
        FriendlyDroneColor = Color3.fromRGB(80, 180, 255),
        EnemyDroneColor = Color3.fromRGB(255, 90, 70),
        UnknownDroneColor = Color3.fromRGB(255, 210, 70),
        RearArrowRadius = 70, RearArrowSize = 11,
        WeaponEnabled = true, WeaponHighlight = true, WeaponText = true,
        WeaponNames = true, WeaponDistance = true,
        WeaponAutoCollect = true, WeaponTeleport = false,
        WeaponMaxDistance = 500, WeaponCollectDistance = 10,
        WeaponCooldown = 0.15, WeaponRateLimit = 20,
        WeaponTeleportOffset = Vector3.new(0, 2.5, 0), WeaponTeleportDelay = 0.06,
        WeaponHighlightColor = Color3.fromRGB(255, 220, 80),

        -- MINAS
        MineEnabled = true,
        MineHighlight = true,
        MineAlert = true,
        MineAutoDetonate = false,          -- auto-detonar quando inimigo perto
        MineAutoDetonateDelay = 0,         -- delay extra antes de auto-detonar (segundos)
        MineAlertRadius = 30,              -- raio de detecção de inimigo
        MineBKeyEnabled = true,
        MineHighlightColor = Color3.fromRGB(255, 100, 100),
        MinePlayerSafeDistance = 40,       -- distância MÍNIMA de você até o drone pra poder explodir
        MineMaxDistanceFromPlayer = 600,   -- distância MÁXIMA (sinal do controller)

        BoxThickness = 1, TextSize = 13, Opacity = 1, WatermarkEnabled = true,
    }
}
Environment.LostFrontDrawingESP = Controller

local function addConnection(c) table.insert(Controller.Connections, c); return c end
local function safeDrawing(kind, props)
    local ok, obj = pcall(Drawing.new, kind)
    if not ok or not obj then return nil end
    for p, v in pairs(props or {}) do pcall(function() obj[p] = v end) end
    return obj
end
local function setProp(o, p, v) if o then pcall(function() o[p] = v end) end end
local function removeDrawing(o)
    if not o then return end
    pcall(function() o.Visible = false end)
    pcall(function() if o.Remove then o:Remove() elseif o.Destroy then o:Destroy() end end)
end
local function rebuildIgnoreList()
    table.clear(Controller.IgnoreSet)
    for name in (Controller.Settings.SilentAimIgnoreList or ""):gmatch("[^,]+") do
        local t = name:match("^%s*(.-)%s*$")
        if t ~= "" then Controller.IgnoreSet[t:lower()] = true end
    end
end
local function isIgnored(p)
    if not p then return false end
    local s = Controller.IgnoreSet
    return s[p.Name:lower()] or s[p.DisplayName:lower()]
end

local SilentFOVCircle = safeDrawing("Circle", {
    Visible = false, Filled = false, Color = Controller.Settings.SilentAimFOVColor,
    NumSides = 72, Radius = Controller.Settings.SilentAimFOV,
    Thickness = Controller.Settings.SilentAimFOVThickness,
    Transparency = Controller.Settings.SilentAimFOVOpacity, ZIndex = 5,
})
local SilentFOVSquare = safeDrawing("Square", {
    Visible = false, Filled = false, Color = Controller.Settings.SilentAimFOVColor,
    Size = Vector2.new(300, 300),
    Thickness = Controller.Settings.SilentAimFOVThickness,
    Transparency = Controller.Settings.SilentAimFOVOpacity, ZIndex = 5,
})
local Watermark = safeDrawing("Text", {
    Visible = false, Center = false, Outline = true,
    OutlineColor = Color3.new(0, 0, 0), Color = Color3.fromRGB(80, 255, 140),
    Size = 14, Font = 2, Transparency = 1,
    Position = Vector2.new(12, 12), ZIndex = 20, Text = "The Lost Front",
})

local function createVisual(rear)
    local font = Drawing.Fonts and (Drawing.Fonts.Plex or Drawing.Fonts.UI) or 2
    local v = {
        Outline = safeDrawing("Square", { Visible = false, Filled = false, Color = Color3.new(0,0,0), Thickness = 3, Transparency = 1, ZIndex = 1 }),
        Box = safeDrawing("Square", { Visible = false, Filled = false, Color = Color3.new(1,1,1), Thickness = 1, Transparency = 1, ZIndex = 2 }),
        Text = safeDrawing("Text", { Visible = false, Center = true, Outline = true, OutlineColor = Color3.new(0,0,0), Color = Color3.new(1,1,1), Size = 13, Font = font, Transparency = 1, ZIndex = 3 }),
        Tracer = safeDrawing("Line", { Visible = false, Color = Color3.new(1,1,1), Thickness = 1, Transparency = 1, ZIndex = 2 }),
        HealthBG = safeDrawing("Square", { Visible = false, Filled = true, Color = Color3.new(0,0,0), Size = Vector2.new(3,20), Transparency = 0.4, ZIndex = 2 }),
        HealthFill = safeDrawing("Square", { Visible = false, Filled = true, Color = Color3.fromRGB(80,255,100), Size = Vector2.new(3,20), Transparency = 0.15, ZIndex = 3 }),
        Corners = {}, Skeleton = {},
    }
    for i = 1, 8 do v.Corners[i] = safeDrawing("Line", { Visible = false, Color = Color3.new(1,1,1), Thickness = 1, Transparency = 1, ZIndex = 2 }) end
    for i = 1, 6 do v.Skeleton[i] = safeDrawing("Line", { Visible = false, Color = Color3.new(1,1,1), Thickness = 1, Transparency = 1, ZIndex = 2 }) end
    if rear then
        v.ArrowTop = safeDrawing("Line", { Visible = false, Color = Color3.new(1,1,1), Thickness = 2, Transparency = 1, ZIndex = 4 })
        v.ArrowBottom = safeDrawing("Line", { Visible = false, Color = Color3.new(1,1,1), Thickness = 2, Transparency = 1, ZIndex = 4 })
    end
    return v
end
local function hideVisual(v)
    if not v then return end
    for _, k in ipairs({ "Outline", "Box", "Text", "Tracer", "HealthBG", "HealthFill" }) do setProp(v[k], "Visible", false) end
    if v.ArrowTop then setProp(v.ArrowTop, "Visible", false); setProp(v.ArrowBottom, "Visible", false) end
    if v.Corners then for _, l in ipairs(v.Corners) do setProp(l, "Visible", false) end end
    if v.Skeleton then for _, l in ipairs(v.Skeleton) do setProp(l, "Visible", false) end end
end
local function removeVisual(v)
    if not v then return end
    for _, k in ipairs({ "Outline", "Box", "Text", "Tracer", "HealthBG", "HealthFill", "ArrowTop", "ArrowBottom" }) do removeDrawing(v[k]) end
    if v.Corners then for _, l in ipairs(v.Corners) do removeDrawing(l) end end
    if v.Skeleton then for _, l in ipairs(v.Skeleton) do removeDrawing(l) end end
end

local function getChams(c)
    if not c then return nil end
    local e = c:FindFirstChild("LostFrontESPChams")
    if e and e:IsA("Highlight") then return e end
    local hl = Instance.new("Highlight")
    hl.Name = "LostFrontESPChams"
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency = 0.55; hl.OutlineTransparency = 0.1
    hl.Adornee = c; hl.Enabled = false; hl.Parent = c
    return hl
end
local function setChams(c, on, color)
    if not c then return end
    local ch = getChams(c); if not ch then return end
    ch.Enabled = on
    if on and color then ch.FillColor = color; ch.OutlineColor = color end
end

local function getAnchor(m)
    if not m then return nil end
    if m:IsA("BasePart") then return m end
    if m:IsA("Model") then
        return m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head") or m:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function getBounds(m, cam)
    if not m or not cam then return nil end
    if not m:IsA("Model") then
        local sp, on = cam:WorldToViewportPoint(m.Position)
        if not on or sp.Z <= 0 then return nil end
        return Vector2.new(sp.X - 15, sp.Y - 15), Vector2.new(30, 30)
    end
    local cache = Controller.BoundsCache[m]
    local a = getAnchor(m)
    local now = os.clock()
    if cache and a and now - cache.t < 0.033 and (a.Position - cache.pos).Magnitude < CONST.BOUNDS_CACHE_MOVE_THRESHOLD then
        return cache.min, cache.size
    end
    local ok, cf, sz = pcall(m.GetBoundingBox, m)
    if not ok or sz.Magnitude <= 0 then return nil end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
        local wp = cf:PointToWorldSpace(Vector3.new(sz.X*x*0.5, sz.Y*y*0.5, sz.Z*z*0.5))
        local sp = cam:WorldToViewportPoint(wp)
        if sp.Z <= 0 then return nil end
        minX = math.min(minX, sp.X); minY = math.min(minY, sp.Y)
        maxX = math.max(maxX, sp.X); maxY = math.max(maxY, sp.Y)
    end end end
    local vp = cam.ViewportSize
    if maxX < 0 or maxY < 0 or minX > vp.X or minY > vp.Y then return nil end
    minX = math.clamp(minX, 0, vp.X); minY = math.clamp(minY, 0, vp.Y)
    maxX = math.clamp(maxX, 0, vp.X); maxY = math.clamp(maxY, 0, vp.Y)
    local w, h = maxX - minX, maxY - minY
    if w < CONST.MIN_ESP_BOX_SIZE or h < CONST.MIN_ESP_BOX_SIZE then return nil end
    local mp, s = Vector2.new(minX, minY), Vector2.new(w, h)
    if a then Controller.BoundsCache[m] = { t = now, pos = a.Position, min = mp, size = s } end
    return mp, s
end

local function getDistanceOrigin(cam)
    local c = LocalPlayer.Character
    local a = getAnchor(c)
    return a and a.Position or cam.CFrame.Position
end

local TeamRegistry, LastSearch = nil, 0
local function getTeamRegistry()
    if TeamRegistry and type(TeamRegistry.players) == "table" and TeamRegistry.players[LocalPlayer] then return TeamRegistry end
    if os.clock() - LastSearch < CONST.TEAM_REGISTRY_SEARCH_COOLDOWN then return nil end
    LastSearch = os.clock()
    if type(filtergc) ~= "function" then return nil end
    local ok, reg = pcall(filtergc, "table", { Keys = { "isFriendly", "getclient", "getEnemyTeam", "getPlayer", "players" } }, true)
    if not ok or type(reg) ~= "table" or type(reg.players) ~= "table" or not reg.players[LocalPlayer] then return nil end
    TeamRegistry = reg
    Controller.TeamRegistryFound = true
    local cd = reg.players[LocalPlayer]
    Controller.LocalTeam = cd and cd.team or "unknown"
    return reg
end
local function getTeamState(p)
    if not p then return nil, "unknown" end
    local reg = getTeamRegistry()
    if reg then
        local cd = reg.players[LocalPlayer]
        local pd = reg.players[p]
        if cd and pd and cd.team and pd.team then return cd.team == pd.team, tostring(pd.team) end
    end
    if p == LocalPlayer then return true, "ally" end
    if LocalPlayer.Team and p.Team then return LocalPlayer.Team == p.Team, p.Team.Name end
    local lc, c = LocalPlayer.Character, p.Character
    if not lc or not c then return nil, "unknown" end
    local lcont, tcont = lc.Parent, c.Parent
    if not lcont or not tcont or lcont == Workspace or tcont == Workspace then return nil, "unknown" end
    local f = lcont == tcont
    return f, f and "ally" or "enemy"
end
local function isTeammate(p) return getTeamState(p) == true end

local SilentRandom = Random.new()
local LastSilentUpdate = 0
local function getSilentTargetPart(p, rnd)
    local c = p and p.Character
    if not c then return nil end
    local sel = Controller.Settings.SilentAimTargetPart
    local names
    if sel == "Random" then
        names = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" }
        if rnd then for i = #names, 2, -1 do local j = SilentRandom:NextInteger(1, i); names[i], names[j] = names[j], names[i] end end
    else
        names = { sel, "Head", "UpperTorso", "Torso", "HumanoidRootPart" }
    end
    for _, n in ipairs(names) do local p2 = c:FindFirstChild(n); if p2 and p2:IsA("BasePart") then return p2 end end
    return getAnchor(c)
end
local function getSilentDronePart(m)
    if not m or not m:IsA("Model") then return nil end
    local hb = m:FindFirstChild("hitbox"); if hb and hb:IsA("BasePart") then return hb end
    local ap = m:FindFirstChild("AimPoint"); if ap and ap:IsA("BasePart") then return ap end
    return getAnchor(m)
end
local function isSilentVisible(cont, part, cam)
    if not Controller.Settings.SilentAimVisibilityCheck then return true end
    if not cont or not part or not cam then return false end
    local now = os.clock()
    local cached = Controller.VisibilityCache[cont]
    if cached and now - cached.t < CONST.VISIBILITY_CACHE_TTL then return cached.v end
    local exc = { cam }
    if LocalPlayer.Character then table.insert(exc, LocalPlayer.Character) end
    local ig = Workspace:FindFirstChild("ignore"); if ig then table.insert(exc, ig) end
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Exclude
    p.FilterDescendantsInstances = exc; p.IgnoreWater = true
    local r = Workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, p)
    local v = r == nil or r.Instance:IsDescendantOf(cont)
    Controller.VisibilityCache[cont] = { t = now, v = v }
    return v
end
local function isSilentPlayerEligible(p, part, cam)
    if not p or p == LocalPlayer or not part or isIgnored(p) then return false end
    local c = p.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if not c or not c:IsDescendantOf(Workspace) or (h and h.Health <= 0) then return false end
    if Controller.Settings.SilentAimTeamCheck and isTeammate(p) then return false end
    return (part.Position - cam.CFrame.Position).Magnitude <= Controller.Settings.SilentAimMaxDistance
        and isSilentVisible(c, part, cam)
end
local function isSilentDroneEligible(m, part, cam)
    if not m or not m:IsA("Model") or not part or not m:IsDescendantOf(Workspace) then return false end
    local on = m:GetAttribute("player")
    local th = m:GetAttribute("throttle")
    if type(on) ~= "string" or on == "" or th == nil then return false end
    local op = Players:FindFirstChild(on)
    if op == LocalPlayer or (op and isIgnored(op)) then return false end
    if Controller.Settings.SilentAimTeamCheck and op and isTeammate(op) then return false end
    return (part.Position - cam.CFrame.Position).Magnitude <= Controller.Settings.SilentAimMaxDistance
        and isSilentVisible(m, part, cam)
end
local function getPriority(kind, tgt, part, cam, center)
    local p = Controller.Settings.SilentAimTargetPriority
    if p == "Closest distance" then return (part.Position - cam.CFrame.Position).Magnitude end
    if p == "Lowest health" and kind == "Player" then
        local h = tgt.Character and tgt.Character:FindFirstChildOfClass("Humanoid")
        return h and h.Health or math.huge
    end
    local sp = cam:WorldToViewportPoint(part.Position)
    return (Vector2.new(sp.X, sp.Y) - center).Magnitude
end

local function updateSilentAimTarget(cam)
    local s = Controller.Settings
    local center = cam.ViewportSize * 0.5
    local fovVis = s.SilentAimEnabled and s.SilentAimShowFOV
    local useSq = s.SilentAimFOVShape == "Square"
    if SilentFOVCircle then
        SilentFOVCircle.Position = center; SilentFOVCircle.Radius = s.SilentAimFOV
        SilentFOVCircle.Thickness = s.SilentAimFOVThickness; SilentFOVCircle.Transparency = s.SilentAimFOVOpacity
        SilentFOVCircle.Visible = fovVis and not useSq
    end
    if SilentFOVSquare then
        SilentFOVSquare.Position = Vector2.new(center.X - s.SilentAimFOV, center.Y - s.SilentAimFOV)
        SilentFOVSquare.Size = Vector2.new(s.SilentAimFOV*2, s.SilentAimFOV*2)
        SilentFOVSquare.Thickness = s.SilentAimFOVThickness; SilentFOVSquare.Transparency = s.SilentAimFOVOpacity
        SilentFOVSquare.Visible = fovVis and useSq
    end
    if not s.SilentAimEnabled then
        Controller.SilentTarget = nil; Controller.SilentTargetKind = nil
        if SilentFOVCircle then SilentFOVCircle.Color = s.SilentAimFOVColor end
        if SilentFOVSquare then SilentFOVSquare.Color = s.SilentAimFOVColor end
        return
    end
    local now = os.clock()
    if now - LastSilentUpdate < CONST.SILENT_UPDATE_INTERVAL then
        local col = Controller.SilentTarget and s.SilentAimLockedFOVColor or s.SilentAimFOVColor
        if SilentFOVCircle then SilentFOVCircle.Color = col end
        if SilentFOVSquare then SilentFOVSquare.Color = col end
        return
    end
    LastSilentUpdate = now
    local best, kind = nil, nil
    local bestScore = s.SilentAimFOV
    if s.SilentAimTargetType ~= "Drones" then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local part = getSilentTargetPart(p, false)
                if part then
                    local sp, on = cam:WorldToViewportPoint(part.Position)
                    if on and sp.Z > 0 then
                        local sd = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if sd <= s.SilentAimFOV and sd <= bestScore and isSilentPlayerEligible(p, part, cam) then
                            local sc = getPriority("Player", p, part, cam, center)
                            if not best or sc < bestScore or kind ~= "Player" then bestScore, best, kind = sc, p, "Player" end
                        end
                    end
                end
            end
        end
    end
    if s.SilentAimTargetType ~= "Players" then
        for m in pairs(Controller.DroneEntries) do
            local part = getSilentDronePart(m)
            if part then
                local sp, on = cam:WorldToViewportPoint(part.Position)
                if on and sp.Z > 0 then
                    local sd = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if sd <= s.SilentAimFOV and isSilentDroneEligible(m, part, cam) then
                        local sc = getPriority("Drone", m, part, cam, center)
                        if not best or sc < bestScore or kind == "Drone" then bestScore, best, kind = sc, m, "Drone" end
                    end
                end
            end
        end
    end
    Controller.SilentTarget = best; Controller.SilentTargetKind = kind
    local col = best and s.SilentAimLockedFOVColor or s.SilentAimFOVColor
    if SilentFOVCircle then SilentFOVCircle.Color = col end
    if SilentFOVSquare then SilentFOVSquare.Color = col end
end

local CalculateDirTarget, OriginalCalcDir, HookedCalcDir
local function getSilentAimPoint(origin, speed, accel)
    local s = Controller.Settings
    local tgt = Controller.SilentTarget; local kind = Controller.SilentTargetKind
    local cam = Workspace.CurrentCamera
    local part, velPart, ok2 = nil, nil, false
    if kind == "Drone" then
        part = getSilentDronePart(tgt); velPart = tgt and (tgt.PrimaryPart or part)
        ok2 = cam and isSilentDroneEligible(tgt, part, cam) or false
    elseif kind == "Player" then
        part = getSilentTargetPart(tgt, true); velPart = part
        ok2 = cam and isSilentPlayerEligible(tgt, part, cam) or false
    end
    if not ok2 then return nil end
    if s.SilentAimHitChance < 100 and SilentRandom:NextNumber(0, 100) > s.SilentAimHitChance then return nil end
    local aim = part.Position
    if s.SilentAimPrediction then
        local ps = type(speed) == "number" and math.abs(speed) or 0
        if ps > 0 then
            local tt = (aim - origin).Magnitude / ps
            if velPart and velPart.AssemblyLinearVelocity then aim = aim + velPart.AssemblyLinearVelocity * tt end
            if typeof(accel) == "Vector3" then aim = aim - accel * tt * tt * 0.5 end
        end
    end
    return aim
end
local function getSilentLabel()
    local t = Controller.SilentTarget
    if Controller.SilentTargetKind == "Drone" and t then return "Drone: " .. tostring(t:GetAttribute("player") or "?") end
    if Controller.SilentTargetKind == "Player" and t then return t.Name end
    return ""
end
local function installSilentAimHook()
    if Controller.FastCastHookInstalled then return true end
    if type(filtergc) ~= "function" then return false end
    local ok, proj = pcall(filtergc, "table", { Keys = { "object", "raycast", "calculateDirection", "makeSpread", "init", "providers", "new" } }, true)
    if not ok or type(proj) ~= "table" or type(proj.calculateDirection) ~= "function" then return false end
    if type(hookfunction) ~= "function" then return false end
    CalculateDirTarget = proj.calculateDirection
    local function repl(origin, camCF, ...)
        local r = OriginalCalcDir(origin, camCF, ...)
        Controller.FastCastCalls = Controller.FastCastCalls + 1
        local s = Controller.Settings
        if not Controller.Unloaded and s.SilentAimEnabled and typeof(origin) == "Vector3" and typeof(camCF) == "CFrame" and type(r) == "table" then
            local cam = Workspace.CurrentCamera
            local la = getAnchor(LocalPlayer.Character)
            local nearCam = cam and (origin - cam.CFrame.Position).Magnitude <= 25
            local nearChar = la and (origin - la.Position).Magnitude <= 30
            if nearCam or nearChar then
                local sp = typeof(r.castDirection) == "Vector3" and r.castDirection.Magnitude or nil
                if type(sp) ~= "number" or sp <= 0 then sp = 1000 end
                local accel = Vector3.new(0, -Workspace.Gravity / math.max(1, s.SilentAimGravityDivisor), 0)
                local ok2, aim = pcall(getSilentAimPoint, origin, sp, accel)
                if ok2 and aim then
                    local md, cd = aim - origin, aim - camCF.Position
                    if md.Magnitude > 0 and cd.Magnitude > 0 then
                        local cm = typeof(r.castDirection) == "Vector3" and r.castDirection.Magnitude or sp
                        r.position = aim; r.direction = md.Unit; r.rayDirection = cd.Unit
                        r.castDirection = r.rayDirection * cm
                        Controller.SilentRedirects = Controller.SilentRedirects + 1
                        Controller.LastSilentTarget = getSilentLabel()
                    end
                end
            end
        end
        return r
    end
    HookedCalcDir = type(newcclosure) == "function" and newcclosure(repl) or repl
    local ok2, orig = pcall(hookfunction, CalculateDirTarget, HookedCalcDir)
    if not ok2 or type(orig) ~= "function" then CalculateDirTarget, HookedCalcDir = nil, nil; return false end
    OriginalCalcDir = orig
    Controller.FastCastHookInstalled = true
    return true
end

local function renderRearArrow(v, a, color, cam)
    if not v.ArrowTop then return end
    local s = Controller.Settings
    local rel = cam.CFrame:PointToObjectSpace(a.Position)
    if not s.DroneRearArrows or rel.Z <= 0 then setProp(v.ArrowTop, "Visible", false); setProp(v.ArrowBottom, "Visible", false); return end
    local dir = Vector2.new(rel.X, -rel.Y)
    if dir.Magnitude < 0.001 then dir = Vector2.new(1, 0) else dir = dir.Unit end
    local perp = Vector2.new(-dir.Y, dir.X)
    local center = cam.ViewportSize * 0.5
    local ac = center + dir * s.RearArrowRadius
    local tip = ac + dir * s.RearArrowSize
    local back = ac - dir * s.RearArrowSize * 0.65
    local wing = s.RearArrowSize * 0.8
    local th = math.max(2, s.BoxThickness)
    setProp(v.ArrowTop, "From", back + perp * wing); setProp(v.ArrowTop, "To", tip)
    setProp(v.ArrowTop, "Color", color); setProp(v.ArrowTop, "Thickness", th)
    setProp(v.ArrowTop, "Transparency", s.Opacity); setProp(v.ArrowTop, "Visible", true)
    setProp(v.ArrowBottom, "From", back - perp * wing); setProp(v.ArrowBottom, "To", tip)
    setProp(v.ArrowBottom, "Color", color); setProp(v.ArrowBottom, "Thickness", th)
    setProp(v.ArrowBottom, "Transparency", s.Opacity); setProp(v.ArrowBottom, "Visible", true)
end
local function renderCorners(v, pos, sz, color, tr, th)
    if not v.Corners then return end
    local cl = math.min(sz.X, sz.Y) * 0.25
    local x1, y1 = pos.X, pos.Y; local x2, y2 = pos.X + sz.X, pos.Y + sz.Y
    local segs = {
        { Vector2.new(x1,y1), Vector2.new(x1+cl,y1) }, { Vector2.new(x1,y1), Vector2.new(x1,y1+cl) },
        { Vector2.new(x2,y1), Vector2.new(x2-cl,y1) }, { Vector2.new(x2,y1), Vector2.new(x2,y1+cl) },
        { Vector2.new(x1,y2), Vector2.new(x1+cl,y2) }, { Vector2.new(x1,y2), Vector2.new(x1,y2-cl) },
        { Vector2.new(x2,y2), Vector2.new(x2-cl,y2) }, { Vector2.new(x2,y2), Vector2.new(x2,y2-cl) },
    }
    for i, s in ipairs(segs) do
        local l = v.Corners[i]
        if l then setProp(l, "From", s[1]); setProp(l, "To", s[2])
            setProp(l, "Color", color); setProp(l, "Thickness", th)
            setProp(l, "Transparency", tr); setProp(l, "Visible", true) end
    end
end
local function renderHealthBar(v, pos, sz, h, tr)
    if not v.HealthBG or not h then return end
    local mh = math.max(1, h.MaxHealth)
    local ratio = math.clamp(h.Health / mh, 0, 1)
    local bw, bx, by = 3, pos.X - 6, pos.Y
    setProp(v.HealthBG, "Position", Vector2.new(bx, by)); setProp(v.HealthBG, "Size", Vector2.new(bw, sz.Y))
    setProp(v.HealthBG, "Transparency", math.clamp(tr * 0.5, 0, 1)); setProp(v.HealthBG, "Visible", true)
    local fh = sz.Y * ratio; local fy = by + (sz.Y - fh)
    setProp(v.HealthFill, "Position", Vector2.new(bx, fy)); setProp(v.HealthFill, "Size", Vector2.new(bw, fh))
    setProp(v.HealthFill, "Color", Color3.fromHSV(ratio * 0.33, 0.85, 1))
    setProp(v.HealthFill, "Transparency", math.clamp(tr * 0.15, 0, 1)); setProp(v.HealthFill, "Visible", true)
end
local function renderSkeleton(v, c, color, cam, tr)
    if not v.Skeleton or not c then return end
    local function screen(n)
        local p = c:FindFirstChild(n); if not p or not p:IsA("BasePart") then return nil end
        local sp, on = cam:WorldToViewportPoint(p.Position); if not on or sp.Z <= 0 then return nil end
        return Vector2.new(sp.X, sp.Y)
    end
    local segs = {
        { screen("Head"), screen("UpperTorso") or screen("Torso") },
        { screen("UpperTorso") or screen("Torso"), screen("LowerTorso") or screen("HumanoidRootPart") },
        { screen("UpperTorso") or screen("Torso"), screen("LeftUpperArm") or screen("Left Arm") },
        { screen("UpperTorso") or screen("Torso"), screen("RightUpperArm") or screen("Right Arm") },
        { screen("LowerTorso") or screen("HumanoidRootPart"), screen("LeftUpperLeg") or screen("Left Leg") },
        { screen("LowerTorso") or screen("HumanoidRootPart"), screen("RightUpperLeg") or screen("Right Leg") },
    }
    for i, s in ipairs(segs) do
        local l = v.Skeleton[i]
        if l then
            if s[1] and s[2] then setProp(l, "From", s[1]); setProp(l, "To", s[2])
                setProp(l, "Color", color); setProp(l, "Thickness", 1)
                setProp(l, "Transparency", tr); setProp(l, "Visible", true)
            else setProp(l, "Visible", false) end
        end
    end
end
local function renderVisual(v, m, label, color, sBox, sText, sTracer, cam, hum)
    local pos, sz = getBounds(m, cam)
    if not pos then hideVisual(v); return end
    local s = Controller.Settings; local t = s.Opacity
    if s.PlayerBoxStyle == "Corners" and sBox and v.Corners then
        setProp(v.Outline, "Visible", false); setProp(v.Box, "Visible", false)
        renderCorners(v, pos, sz, color, t, math.max(1, s.BoxThickness))
    else
        if v.Corners then for _, l in ipairs(v.Corners) do setProp(l, "Visible", false) end end
        setProp(v.Outline, "Position", pos); setProp(v.Outline, "Size", sz)
        setProp(v.Outline, "Thickness", s.BoxThickness + 2); setProp(v.Outline, "Transparency", t)
        setProp(v.Outline, "Visible", sBox)
        setProp(v.Box, "Position", pos); setProp(v.Box, "Size", sz); setProp(v.Box, "Color", color)
        setProp(v.Box, "Thickness", s.BoxThickness); setProp(v.Box, "Transparency", t); setProp(v.Box, "Visible", sBox)
    end
    setProp(v.Text, "Text", label)
    setProp(v.Text, "Position", Vector2.new(pos.X + sz.X*0.5, math.max(0, pos.Y - s.TextSize - 3)))
    setProp(v.Text, "Color", color); setProp(v.Text, "Size", s.TextSize)
    setProp(v.Text, "Transparency", t); setProp(v.Text, "Visible", sText and label ~= "")
    setProp(v.Tracer, "From", Vector2.new(cam.ViewportSize.X*0.5, cam.ViewportSize.Y - 2))
    setProp(v.Tracer, "To", Vector2.new(pos.X + sz.X*0.5, pos.Y + sz.Y))
    setProp(v.Tracer, "Color", color); setProp(v.Tracer, "Thickness", s.BoxThickness)
    setProp(v.Tracer, "Transparency", t); setProp(v.Tracer, "Visible", sTracer)
    if s.PlayerHealthBar and hum then renderHealthBar(v, pos, sz, hum, t)
    else setProp(v.HealthBG, "Visible", false); setProp(v.HealthFill, "Visible", false) end
end

local function getPlayerVisual(p)
    local v = Controller.PlayerEntries[p]
    if not v then v = createVisual(false); Controller.PlayerEntries[p] = v end
    return v
end
local function removePlayer(p)
    local v = Controller.PlayerEntries[p]
    if v then removeVisual(v); Controller.PlayerEntries[p] = nil end
    local c = p and p.Character
    if c then local ch = c:FindFirstChild("LostFrontESPChams"); if ch then ch:Destroy() end end
end
local function updatePlayers(cam, origin)
    local s = Controller.Settings; local present = {}; local rendered = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            present[p] = true
            local v = getPlayerVisual(p)
            local c = p.Character; local a = getAnchor(c)
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local tm = isTeammate(p)
            local hide = not s.PlayerEnabled or not c or not c:IsDescendantOf(Workspace) or not a
                or (h and h.Health <= 0) or (tm and not s.ShowTeammates) or isIgnored(p)
            if hide then hideVisual(v); setChams(c, false)
            else
                local d = (a.Position - origin).Magnitude
                if d > s.PlayerMaxDistance or rendered >= CONST.MAX_ESP_TARGETS then
                    hideVisual(v); setChams(c, false)
                else
                    rendered = rendered + 1
                    local pieces = {}
                    if s.PlayerNames then
                        table.insert(pieces, p.DisplayName ~= p.Name and (p.DisplayName .. " (@" .. p.Name .. ")") or p.Name)
                    end
                    if s.PlayerDistance then table.insert(pieces, string.format("[%ds]", math.floor(d + 0.5))) end
                    local color = tm and s.TeammateColor or s.EnemyColor
                    renderVisual(v, c, table.concat(pieces, " "), color, s.PlayerBoxes, s.PlayerNames or s.PlayerDistance, s.PlayerTracers, cam, h)
                    if s.PlayerSkeleton then renderSkeleton(v, c, color, cam, s.Opacity)
                    else for _, l in ipairs(v.Skeleton or {}) do setProp(l, "Visible", false) end end
                    if s.PlayerChams then setChams(c, true, s.ChamsColor) else setChams(c, false) end
                end
            end
        end
    end
    for p in pairs(Controller.PlayerEntries) do if not present[p] then removePlayer(p) end end
end

local function looksLikeDrone(m)
    if not m or not m:IsA("Model") then return false end
    local o = m:GetAttribute("player"); local t = m:GetAttribute("throttle")
    if type(o) ~= "string" or o == "" or t == nil then return false end
    local pr = m:FindFirstChild("propellers")
    local pp = m.PrimaryPart; local ra = pp and pp:FindFirstChild("RootAttachment")
    return pr ~= nil or ra ~= nil
end
local function registerDrone(m)
    if Controller.DroneEntries[m] or not looksLikeDrone(m) then return end
    Controller.DroneEntries[m] = createVisual(true)
end
local function removeDrone(m)
    local v = Controller.DroneEntries[m]
    if v then removeVisual(v); Controller.DroneEntries[m] = nil end
end
local function discoverDrones()
    local cands = {}
    local ok, res = pcall(function() return Workspace:QueryDescendants("Model[$player], Model[$throttle], Model:has(#propellers)") end)
    if ok and type(res) == "table" then cands = res
    else
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("Model") and looksLikeDrone(d) then table.insert(cands, d) end
        end
    end
    for _, c in ipairs(cands) do registerDrone(c) end
end
local function updateDrones(cam, origin)
    local s = Controller.Settings
    for m, v in pairs(Controller.DroneEntries) do
        if not m.Parent or not m:IsDescendantOf(Workspace) or not looksLikeDrone(m) then removeDrone(m)
        else
            local a = getAnchor(m); local on = m:GetAttribute("player"); local isOwn = on == LocalPlayer.Name
            local hide = not s.DroneEnabled or not a or (isOwn and not s.ShowOwnDrone)
            if hide then hideVisual(v)
            else
                local d = (a.Position - origin).Magnitude
                if d > s.DroneMaxDistance then hideVisual(v)
                else
                    local op = Players:FindFirstChild(on)
                    local fr, tn = getTeamState(op)
                    local color = fr == true and s.FriendlyDroneColor or fr == false and s.EnemyDroneColor or s.UnknownDroneColor
                    if s.DroneTeamCheck and fr == true and not isOwn then hideVisual(v)
                    else
                        local pieces = {}
                        if s.DroneNames then table.insert(pieces, "Drone: " .. on) end
                        if s.DroneTeams then table.insert(pieces, "[" .. string.upper(tn) .. "]") end
                        if s.DroneDistance then table.insert(pieces, string.format("[%ds]", math.floor(d + 0.5))) end
                        renderVisual(v, m, table.concat(pieces, " "), color, s.DroneBoxes,
                            s.DroneNames or s.DroneTeams or s.DroneDistance, s.DroneTracers, cam, nil)
                        renderRearArrow(v, a, color, cam)
                    end
                end
            end
        end
    end
end

local WeaponState = { collected = 0, failed = 0, windowStart = os.clock(), windowCount = 0, lastAttempt = setmetatable({}, { __mode = "k" }) }
local CollectRemote = nil
do local ok, r = pcall(function() return game.ReplicatedStorage.network.pickup.collect end); if ok then CollectRemote = r end end
local function getDroppedFolder()
    local d = Workspace:FindFirstChild("debris"); return d and d:FindFirstChild("dropped")
end
local function weaponRateLimitOk()
    local now = os.clock()
    if now - WeaponState.windowStart >= 1 then WeaponState.windowStart, WeaponState.windowCount = now, 0 end
    if WeaponState.windowCount >= Controller.Settings.WeaponRateLimit then return false end
    WeaponState.windowCount = WeaponState.windowCount + 1
    return true
end
local function tryCollectWeapon(item)
    if not CollectRemote then return end
    local s = Controller.Settings; local now = os.clock()
    if WeaponState.lastAttempt[item] and now - WeaponState.lastAttempt[item] < s.WeaponCooldown then return end
    if not weaponRateLimitOk() then return end
    WeaponState.lastAttempt[item] = now
    local ok = pcall(function() CollectRemote:FireServer(item) end)
    if ok then WeaponState.collected = WeaponState.collected + 1 else WeaponState.failed = WeaponState.failed + 1 end
end
local function scanAndCollectWeapons()
    if not Controller.Settings.WeaponAutoCollect or not CollectRemote then return end
    local folder = getDroppedFolder(); if not folder then return end
    local root = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character.PrimaryPart)
    if not root then return end
    local s = Controller.Settings
    for _, item in ipairs(folder:GetChildren()) do
        local a = getAnchor(item)
        if a then
            local d = (a.Position - root.Position).Magnitude
            if d <= s.WeaponCollectDistance then tryCollectWeapon(item)
            elseif s.WeaponTeleport then
                local o = root.CFrame
                root.CFrame = CFrame.new(a.Position + s.WeaponTeleportOffset)
                task.wait(s.WeaponTeleportDelay)
                tryCollectWeapon(item)
                root.CFrame = o
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
            text = safeDrawing("Text", { Visible = false, Center = true, Outline = true,
                OutlineColor = Color3.new(0,0,0), Color = Controller.Settings.WeaponHighlightColor,
                Size = 14, Font = Drawing.Fonts and (Drawing.Fonts.Plex or Drawing.Fonts.UI) or 2,
                Transparency = 1, ZIndex = 10 }),
        }
        Controller.WeaponEntries[item] = v
    end
    return v
end
local function ensureWeaponHighlight(item, v)
    if not Controller.Settings.WeaponHighlight then if v.highlight then v.highlight.Enabled = false end; return end
    if not v.highlight and item.Parent then
        local ok, hl = pcall(function()
            local h = Instance.new("Highlight")
            h.Name = "ItemESP"; h.Adornee = item
            h.FillColor = Controller.Settings.WeaponHighlightColor
            h.OutlineColor = Controller.Settings.WeaponHighlightColor
            h.FillTransparency = 0.6; h.OutlineTransparency = 0
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; h.Parent = item
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
    local v = Controller.WeaponEntries[item]; if not v then return end
    if v.highlight then pcall(function() v.highlight:Destroy() end) end
    if v.text then removeDrawing(v.text) end
    Controller.WeaponEntries[item] = nil
end
local function updateWeapons(cam, origin)
    local s = Controller.Settings
    local folder = getDroppedFolder()
    if folder then
        for _, item in ipairs(folder:GetChildren()) do
            local v = getWeaponVisual(item); local a = getAnchor(item)
            if a and s.WeaponEnabled then
                local d = (a.Position - origin).Magnitude
                if d <= s.WeaponMaxDistance then
                    ensureWeaponHighlight(item, v)
                    if v.highlight then v.highlight.Enabled = s.WeaponHighlight end
                    local t = v.text
                    if t then
                        if s.WeaponText then
                            local sp, on = cam:WorldToViewportPoint(a.Position)
                            if on and sp.Z > 0 then
                                local pieces = {}
                                if s.WeaponNames then table.insert(pieces, item.Name) end
                                if s.WeaponDistance then table.insert(pieces, string.format("[%dm]", math.floor(d + 0.5))) end
                                t.Text = table.concat(pieces, " "); t.Position = Vector2.new(sp.X, sp.Y - 20)
                                t.Color = s.WeaponHighlightColor; t.Visible = true
                            else t.Visible = false end
                        else t.Visible = false end
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
        for item in pairs(Controller.WeaponEntries) do
            if not item.Parent or not item:IsDescendantOf(folder) then removeWeaponEntry(item) end
        end
    end
end

-- =========================================================================
-- MINAS — ativação via createDrone + explodeDrone + auto-detonate
-- =========================================================================
local Mines = {}
local MineStats = { detonated = 0, planted = 0, activated = 0, failed = 0 }
local network = game.ReplicatedStorage:FindFirstChild("network")
local createDrone = network and network:FindFirstChild("createDrone")
local explodeDrone = network and network:FindFirstChild("explodeDrone")

local function getPlaceables() return Workspace:FindFirstChild("placeables") end
local function isMyDrone(m)
    if not m or not m:IsA("Model") then return false end
    local o = m:GetAttribute("player")
    if o then return tostring(o) == LocalPlayer.Name end
    return m.Name:find(tostring(LocalPlayer.UserId), 1, true) ~= nil
end
local function getMineAnchor(m)
    local pp = m.PrimaryPart
    if pp then return pp end
    return m:FindFirstChildWhichIsA("BasePart", true)
end
local function getMyRoot()
    local c = LocalPlayer.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

local function createMineVisual(mine)
    local visual = { highlight = nil }
    if not Controller.Settings.MineHighlight or not mine.Parent then return visual end
    local ok, hl = pcall(function()
        local h = Instance.new("Highlight")
        h.Name = "MineESP"; h.Adornee = mine
        h.FillColor = Controller.Settings.MineHighlightColor
        h.OutlineColor = Color3.fromRGB(255, 255, 255)
        h.FillTransparency = 0.6; h.OutlineTransparency = 0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = mine
        return h
    end)
    if ok then visual.highlight = hl end
    return visual
end
local function removeMineVisual(v)
    if v and v.highlight then pcall(function() v.highlight:Destroy() end) end
end
local function removeMine(mine)
    local e = Mines[mine]; if not e then return end
    removeMineVisual(e.visual); Mines[mine] = nil
end

-- Detona com ativação correta: createDrone → explodeDrone
local function detonateMine(mine, source)
    if not mine or not mine.Parent then return false end
    if not createDrone or not explodeDrone then
        warn("[Mine] createDrone ou explodeDrone não existe")
        MineStats.failed = MineStats.failed + 1
        return false
    end

    -- 1) ATIVA via createDrone
    local ok1 = pcall(function()
        createDrone:InvokeServer(mine.Name)
    end)
    if ok1 then MineStats.activated = MineStats.activated + 1 end

    -- 2) delay pro servidor registrar
    task.wait(CONST.MINE_ACTIVATE_DELAY)

    -- 3) verifica se ainda existe
    if not mine.Parent then
        -- já explodiu só com ativação (raro)
        MineStats.detonated = MineStats.detonated + 1
        removeMine(mine)
        return true
    end

    -- 4) EXPLODE
    pcall(function()
        explodeDrone:FireServer(mine.Name)
    end)

    MineStats.detonated = MineStats.detonated + 1
    removeMine(mine)
    if source then
        print(string.format("[Mine] Detonou %s (via %s)", mine.Name:match("[^%-]+$") or mine.Name, source))
    end
    return true
end

-- Checa se pode detonar: precisa inimigo perto + você longe do drone
local function canDetonate(mine, entry)
    local s = Controller.Settings

    -- 1) Inimigo próximo?
    local enemyNear = entry.lastEnemyDist and entry.lastEnemyDist <= s.MineAlertRadius
    if not enemyNear then return false, "sem inimigo" end

    -- 2) Você longe o suficiente do drone? (safety)
    local root = getMyRoot()
    if root then
        local anchor = getMineAnchor(mine)
        if anchor then
            local myDist = (root.Position - anchor.Position).Magnitude
            if myDist < s.MinePlayerSafeDistance then
                return false, string.format("você está a %.0f studs (mín %d)", myDist, s.MinePlayerSafeDistance)
            end
            if myDist > s.MineMaxDistanceFromPlayer then
                return false, string.format("fora de alcance (%.0f)", myDist)
            end
        end
    end

    return true
end

-- =========================================================================
-- ALERTA CENTRAL
-- =========================================================================
local AlertLabel, AlertState = nil, { phase = 0 }
do
    local ok = pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "MineAlertHUD"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 998
        gui.Parent = getGuiParent()

        AlertLabel = Instance.new("TextLabel")
        AlertLabel.Size = UDim2.new(0, 700, 0, 80)
        AlertLabel.Position = UDim2.new(0.5, 0, 0.42, 0)
        AlertLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        AlertLabel.BackgroundTransparency = 1
        AlertLabel.Text = "INIMIGO NA MINA"
        AlertLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
        AlertLabel.TextSize = 46
        AlertLabel.Font = Enum.Font.GothamBold
        AlertLabel.TextStrokeTransparency = 0.4
        AlertLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        AlertLabel.TextTransparency = 1
        AlertLabel.Visible = false
        AlertLabel.ZIndex = 10
        AlertLabel.Parent = gui
    end)
    if not ok then warn("[Mine] Falha ao criar alerta") end
end

installSilentAimHook()

local function cleanup()
    if Controller.Unloaded then return end
    Controller.Unloaded = true
    Controller.SilentTarget = nil; Controller.SilentTargetKind = nil
    setProp(SilentFOVCircle, "Visible", false); setProp(SilentFOVSquare, "Visible", false)
    setProp(Watermark, "Visible", false)
    for _, c in ipairs(Controller.Connections) do pcall(function() c:Disconnect() end) end
    table.clear(Controller.Connections)
    for p, v in pairs(Controller.PlayerEntries) do removeVisual(v); Controller.PlayerEntries[p] = nil end
    for m, v in pairs(Controller.DroneEntries) do removeVisual(v); Controller.DroneEntries[m] = nil end
    for item in pairs(Controller.WeaponEntries) do removeWeaponEntry(item) end
    for mine in pairs(Mines) do removeMine(mine) end
    for _, p in ipairs(Players:GetPlayers()) do
        local c = p.Character
        if c then local ch = c:FindFirstChild("LostFrontESPChams"); if ch then ch:Destroy() end end
    end
    removeDrawing(SilentFOVCircle); removeDrawing(SilentFOVSquare); removeDrawing(Watermark)
    if AlertLabel then pcall(function() AlertLabel.Parent:Destroy() end) end
    if CalculateDirTarget then
        if type(restorefunction) == "function" then pcall(restorefunction, CalculateDirTarget)
        elseif type(hookfunction) == "function" and OriginalCalcDir then pcall(hookfunction, CalculateDirTarget, OriginalCalcDir) end
    end
    Controller.FastCastHookInstalled = false
    if Environment.LostFrontDrawingESP == Controller then Environment.LostFrontDrawingESP = nil end
end
Controller.Unload = function()
    if Controller.Unloaded then return end
    if Library and not Library.Unloaded then Library:Unload() else cleanup() end
end

-- POLL de minas
task.spawn(function()
    while true do
        if not Controller.Unloaded then
            local folder = getPlaceables()
            if folder then
                for _, m in ipairs(folder:GetChildren()) do
                    if isMyDrone(m) and not Mines[m] then
                        Mines[m] = {
                            visual = createMineVisual(m),
                            plantedAt = os.clock(),
                            lastEnemyDist = math.huge,
                            lastEnemy = nil,
                            autoArmed = false,  -- auto-detonate pronto?
                        }
                        MineStats.planted = MineStats.planted + 1
                    end
                end
            end
            for m in pairs(Mines) do if not m.Parent then removeMine(m) end end
        end
        task.wait(CONST.MINE_POLL_INTERVAL)
    end
end)

-- CHECK de inimigo + auto-detonate
task.spawn(function()
    while true do
        if not Controller.Unloaded then
            for mine, entry in pairs(Mines) do
                if mine.Parent then
                    local a = getMineAnchor(mine)
                    if a then
                        -- acha inimigo mais próximo
                        local closest, closestD = nil, math.huge
                        for _, p in ipairs(Players:GetPlayers()) do
                            if p ~= LocalPlayer then
                                local isEnemy = true
                                if Controller.Settings.SilentAimTeamCheck then isEnemy = not isTeammate(p) end
                                if isEnemy then
                                    local c = p.Character
                                    local r = c and c:FindFirstChild("HumanoidRootPart")
                                    local h = c and c:FindFirstChildOfClass("Humanoid")
                                    if r and h and h.Health > 0 then
                                        local d = (r.Position - a.Position).Magnitude
                                        if d < closestD then closest, closestD = p, d end
                                    end
                                end
                            end
                        end
                        entry.lastEnemyDist = closestD
                        entry.lastEnemy = closest

                        -- AUTO-DETONATE
                        if Controller.Settings.MineAutoDetonate and closest then
                            local ok, reason = canDetonate(mine, entry)
                            if ok then
                                if Controller.Settings.MineAutoDetonateDelay > 0 then
                                    task.wait(Controller.Settings.MineAutoDetonateDelay)
                                end
                                task.spawn(function()
                                    detonateMine(mine, "auto")
                                end)
                                break  -- evita iterar mais nesse loop
                            else
                                entry.lastBlockReason = reason
                            end
                        end
                    end
                end
            end
        end
        task.wait(CONST.MINE_CHECK_INTERVAL)
    end
end)

local LastESPUpdate, LastWeaponScan = 0, 0
addConnection(RunService.RenderStepped:Connect(function(dt)
    if Controller.Unloaded then return end
    local cam = Workspace.CurrentCamera; if not cam then return end
    updateSilentAimTarget(cam)

    LastESPUpdate = LastESPUpdate + dt
    if LastESPUpdate >= CONST.ESP_UPDATE_INTERVAL then
        LastESPUpdate = 0
        local origin = getDistanceOrigin(cam)
        updatePlayers(cam, origin); updateDrones(cam, origin); updateWeapons(cam, origin)
    end

    if Controller.Settings.MineEnabled then
        for mine, entry in pairs(Mines) do
            if mine.Parent and entry.visual and entry.visual.highlight then
                local enemyNear = entry.lastEnemyDist and entry.lastEnemyDist <= Controller.Settings.MineAlertRadius
                entry.visual.highlight.Enabled = Controller.Settings.MineHighlight
                entry.visual.highlight.FillColor = enemyNear and Color3.fromRGB(255, 60, 60) or Controller.Settings.MineHighlightColor
            end
        end
    end

    local anyAlert = false
    if Controller.Settings.MineEnabled and Controller.Settings.MineAlert then
        for mine, entry in pairs(Mines) do
            if mine.Parent and entry.lastEnemyDist and entry.lastEnemyDist <= Controller.Settings.MineAlertRadius then
                anyAlert = true; break
            end
        end
    end
    if AlertLabel then
        if anyAlert then
            AlertState.phase = AlertState.phase + dt * 5
            local pulse = (math.sin(AlertState.phase) + 1) * 0.5
            AlertLabel.Visible = true
            AlertLabel.TextTransparency = 0.25 + (1 - pulse) * 0.5
            AlertLabel.TextStrokeTransparency = 0.3 + (1 - pulse) * 0.4
        elseif AlertLabel.Visible then
            AlertLabel.Visible = false
        end
    end

    LastWeaponScan = LastWeaponScan + dt
    if LastWeaponScan >= CONST.WEAPON_SCAN_INTERVAL then
        LastWeaponScan = 0
        pcall(scanAndCollectWeapons)
    end

    if Watermark then
        if Controller.Settings.WatermarkEnabled then
            Watermark.Text = string.format(
                "The Lost Front | Silent: %d | Redirects: %d | Itens: %d | Minas: %d/%d",
                Controller.FastCastCalls, Controller.SilentRedirects,
                WeaponState.collected, MineStats.detonated, MineStats.planted)
            Watermark.Visible = true
        else Watermark.Visible = false end
    end
end))

task.spawn(function()
    while not Controller.Unloaded do discoverDrones(); task.wait(CONST.DRONE_RESCAN_INTERVAL) end
end)

-- [B] detona todas (com ativação correta)
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.B and Controller.Settings.MineBKeyEnabled then
        task.spawn(function()
            local snapshot = {}
            for mine in pairs(Mines) do table.insert(snapshot, mine) end
            local n = 0
            for _, mine in ipairs(snapshot) do
                if mine.Parent then
                    detonateMine(mine, "B")
                    n = n + 1
                    task.wait(0.12)   -- espaçamento entre detonações
                end
            end
            print("[Mine] [B] detonou " .. n .. " minas")
        end)
    end
end)

-- UI
Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local GameTitle = "The Lost Front"
local WindowIconTitle = "Lost Front"
local CommunityText = "t.me/arceusxcommunity"
pcall(function()
    local r = game:HttpGet("https://raw.githubusercontent.com/Bac0nHck/Something/refs/heads/main/telegram")
    local t = r:match("^%s*(.-)%s*$")
    if t ~= "" then CommunityText = t end
end)

local Window = Library:CreateWindow({
    Title = WindowIconTitle,
    Footer = GameTitle .. " | " .. CommunityText,
    NotifySide = "Right",
    ShowCustomCursor = not Library.IsMobile,
    ShowMobileButtons = true, MobileButtonsSide = "Left",
    AutoShow = true, Center = true, Resizable = true,
    Size = UDim2.fromOffset(600, 500),
    ToggleKeybind = Enum.KeyCode.F1,
})
Window:ChangeTitle(GameTitle)

local Tabs = {}
Tabs.SilentAim = Window:AddTab("Silent Aim", "crosshair", "")
Tabs.ESP = Window:AddTab("ESP", "scan-eye", "")
Tabs.Itens = Window:AddTab("Itens", "package", "")
Tabs.Minas = Window:AddTab("Minas", "bomb", "")
Tabs.Settings = Window:AddTab("UI Settings", "settings", "")

-- ABA SILENT AIM
local SilentMainGroup = Tabs.SilentAim:AddLeftGroupbox("Silent Aim", "crosshair")
local SilentTargetGroup = Tabs.SilentAim:AddRightGroupbox("Targeting", "scan-search")
local SilentVisualGroup = Tabs.SilentAim:AddLeftGroupbox("FOV", "circle-dot")

SilentMainGroup:AddToggle("SilentAimEnabled", { Text = "Enabled", Default = true,
    Callback = function(v) Controller.Settings.SilentAimEnabled = v
        if not v then Controller.SilentTarget = nil; Controller.SilentTargetKind = nil end end })
SilentMainGroup:AddToggle("SilentAimTeamCheck", { Text = "Team check", Default = true,
    Callback = function(v) Controller.Settings.SilentAimTeamCheck = v end })
SilentMainGroup:AddToggle("SilentAimVisibilityCheck", { Text = "Visibility check", Default = true,
    Callback = function(v) Controller.Settings.SilentAimVisibilityCheck = v end })
SilentMainGroup:AddToggle("SilentAimPrediction", { Text = "Prediction", Default = true,
    Callback = function(v) Controller.Settings.SilentAimPrediction = v end })
SilentMainGroup:AddSlider("SilentAimHitChance", { Text = "Hit chance", Default = 100, Min = 0, Max = 100, Rounding = 0, Suffix = "%",
    Callback = function(v) Controller.Settings.SilentAimHitChance = v end })
SilentMainGroup:AddSlider("SilentAimGravityDivisor", { Text = "Gravity divisor", Default = 8, Min = 1, Max = 30, Rounding = 0,
    Callback = function(v) Controller.Settings.SilentAimGravityDivisor = v end })
SilentMainGroup:AddInput("SilentAimIgnoreList", { Default = "", Text = "Ignore list (nomes, vírgula)",
    Placeholder = "Player1, Player2", Callback = function(v) Controller.Settings.SilentAimIgnoreList = v; rebuildIgnoreList() end })
SilentTargetGroup:AddDropdown("SilentAimTargetType", { Values = { "Players and Drones", "Players", "Drones" },
    Default = "Players and Drones", Multi = false, Text = "Target type",
    Callback = function(v) Controller.Settings.SilentAimTargetType = v; Controller.SilentTarget = nil; Controller.SilentTargetKind = nil end })
SilentTargetGroup:AddDropdown("SilentAimTargetPart", { Values = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "Random" },
    Default = "Head", Multi = false, Text = "Player target part",
    Callback = function(v) Controller.Settings.SilentAimTargetPart = v end })
SilentTargetGroup:AddDropdown("SilentAimTargetPriority", { Values = { "Closest to crosshair", "Closest distance", "Lowest health" },
    Default = "Closest to crosshair", Multi = false, Text = "Target priority",
    Callback = function(v) Controller.Settings.SilentAimTargetPriority = v end })
SilentTargetGroup:AddSlider("SilentAimFOV", { Text = "FOV radius", Default = 150, Min = 20, Max = 500, Rounding = 0, Suffix = " px",
    Callback = function(v) Controller.Settings.SilentAimFOV = v end })
SilentTargetGroup:AddSlider("SilentAimMaxDistance", { Text = "Max distance", Default = 2500, Min = 100, Max = 5000, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.SilentAimMaxDistance = v end })
SilentVisualGroup:AddDropdown("SilentAimFOVShape", { Values = { "Circle", "Square" }, Default = "Circle", Multi = false, Text = "FOV shape",
    Callback = function(v) Controller.Settings.SilentAimFOVShape = v end })
SilentVisualGroup:AddToggle("SilentAimShowFOV", { Text = "Show FOV", Default = true,
    Callback = function(v) Controller.Settings.SilentAimShowFOV = v end })
SilentVisualGroup:AddSlider("SilentAimFOVThickness", { Text = "FOV thickness", Default = 1, Min = 1, Max = 4, Rounding = 0,
    Callback = function(v) Controller.Settings.SilentAimFOVThickness = v end })
SilentVisualGroup:AddSlider("SilentAimFOVOpacity", { Text = "FOV opacity", Default = 80, Min = 10, Max = 100, Rounding = 0, Suffix = "%",
    Callback = function(v) Controller.Settings.SilentAimFOVOpacity = v / 100 end })
SilentVisualGroup:AddLabel("FOV color"):AddColorPicker("SilentAimFOVColor", { Default = Controller.Settings.SilentAimFOVColor,
    Title = "FOV color", Callback = function(v) Controller.Settings.SilentAimFOVColor = v end })
SilentVisualGroup:AddLabel("Locked FOV color"):AddColorPicker("SilentAimLockedFOVColor", { Default = Controller.Settings.SilentAimLockedFOVColor,
    Title = "Locked FOV color", Callback = function(v) Controller.Settings.SilentAimLockedFOVColor = v end })

-- ABA ESP
local PlayerGroup = Tabs.ESP:AddLeftGroupbox("Players", "users")
local DroneGroup = Tabs.ESP:AddRightGroupbox("Drones", "plane")
local VisualGroup = Tabs.ESP:AddLeftGroupbox("Visuals", "palette")

PlayerGroup:AddToggle("PlayerESP", { Text = "Player ESP", Default = true, Callback = function(v) Controller.Settings.PlayerEnabled = v end })
PlayerGroup:AddToggle("PlayerBoxes", { Text = "Boxes", Default = true, Callback = function(v) Controller.Settings.PlayerBoxes = v end })
PlayerGroup:AddDropdown("PlayerBoxStyle", { Values = { "Full", "Corners" }, Default = "Full", Multi = false, Text = "Box style",
    Callback = function(v) Controller.Settings.PlayerBoxStyle = v end })
PlayerGroup:AddToggle("PlayerNames", { Text = "Names", Default = true, Callback = function(v) Controller.Settings.PlayerNames = v end })
PlayerGroup:AddToggle("PlayerDistance", { Text = "Distance", Default = true, Callback = function(v) Controller.Settings.PlayerDistance = v end })
PlayerGroup:AddToggle("PlayerHealthBar", { Text = "Health bar", Default = false, Callback = function(v) Controller.Settings.PlayerHealthBar = v end })
PlayerGroup:AddToggle("PlayerSkeleton", { Text = "Skeleton", Default = false, Callback = function(v) Controller.Settings.PlayerSkeleton = v end })
PlayerGroup:AddToggle("PlayerChams", { Text = "Chams", Default = false, Callback = function(v) Controller.Settings.PlayerChams = v end })
PlayerGroup:AddToggle("PlayerTracers", { Text = "Tracers", Default = false, Callback = function(v) Controller.Settings.PlayerTracers = v end })
PlayerGroup:AddToggle("ShowTeammates", { Text = "Show teammates", Default = false, Callback = function(v) Controller.Settings.ShowTeammates = v end })
PlayerGroup:AddSlider("PlayerMaxDistance", { Text = "Max distance", Default = 2500, Min = 100, Max = 5000, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.PlayerMaxDistance = v end })

DroneGroup:AddToggle("DroneESP", { Text = "Drone ESP", Default = true, Callback = function(v) Controller.Settings.DroneEnabled = v end })
DroneGroup:AddToggle("DroneBoxes", { Text = "Boxes", Default = true, Callback = function(v) Controller.Settings.DroneBoxes = v end })
DroneGroup:AddToggle("DroneNames", { Text = "Owner names", Default = true, Callback = function(v) Controller.Settings.DroneNames = v end })
DroneGroup:AddToggle("DroneTeams", { Text = "Team labels", Default = true, Callback = function(v) Controller.Settings.DroneTeams = v end })
DroneGroup:AddToggle("DroneDistance", { Text = "Distance", Default = true, Callback = function(v) Controller.Settings.DroneDistance = v end })
DroneGroup:AddToggle("DroneTracers", { Text = "Tracers", Default = false, Callback = function(v) Controller.Settings.DroneTracers = v end })
DroneGroup:AddToggle("DroneRearArrows", { Text = "Rear drone arrows", Default = true, Callback = function(v) Controller.Settings.DroneRearArrows = v end })
DroneGroup:AddToggle("DroneTeamCheck", { Text = "Team check", Default = true, Callback = function(v) Controller.Settings.DroneTeamCheck = v end })
DroneGroup:AddToggle("ShowOwnDrone", { Text = "Show own drone", Default = false, Callback = function(v) Controller.Settings.ShowOwnDrone = v end })
DroneGroup:AddSlider("DroneMaxDistance", { Text = "Max distance", Default = 2500, Min = 100, Max = 5000, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.DroneMaxDistance = v end })
DroneGroup:AddButton({ Text = "Rescan drones", Func = discoverDrones })

VisualGroup:AddLabel("Enemy color"):AddColorPicker("EnemyColor", { Default = Controller.Settings.EnemyColor,
    Title = "Enemy color", Callback = function(v) Controller.Settings.EnemyColor = v end })
VisualGroup:AddLabel("Teammate color"):AddColorPicker("TeammateColor", { Default = Controller.Settings.TeammateColor,
    Title = "Teammate color", Callback = function(v) Controller.Settings.TeammateColor = v end })
VisualGroup:AddLabel("Chams color"):AddColorPicker("ChamsColor", { Default = Controller.Settings.ChamsColor,
    Title = "Chams color", Callback = function(v) Controller.Settings.ChamsColor = v end })
VisualGroup:AddSlider("BoxThickness", { Text = "Box thickness", Default = 1, Min = 1, Max = 4, Rounding = 0,
    Callback = function(v) Controller.Settings.BoxThickness = v end })
VisualGroup:AddSlider("TextSize", { Text = "Text size", Default = 13, Min = 10, Max = 24, Rounding = 0,
    Callback = function(v) Controller.Settings.TextSize = v end })
VisualGroup:AddSlider("Opacity", { Text = "Opacity", Default = 100, Min = 20, Max = 100, Rounding = 0, Suffix = "%",
    Callback = function(v) Controller.Settings.Opacity = v / 100 end })
VisualGroup:AddToggle("WatermarkEnabled", { Text = "Watermark", Default = true,
    Callback = function(v) Controller.Settings.WatermarkEnabled = v end })

-- ABA ITENS
local WeaponGroup = Tabs.Itens:AddLeftGroupbox("Itens no chão", "package")
local WeaponCollectGroup = Tabs.Itens:AddRightGroupbox("Auto-Collect", "package-open")
local WeaponColorGroup = Tabs.Itens:AddLeftGroupbox("Visual", "palette")

WeaponGroup:AddToggle("WeaponEnabled", { Text = "Item ESP", Default = true, Callback = function(v) Controller.Settings.WeaponEnabled = v end })
WeaponGroup:AddToggle("WeaponHighlight", { Text = "Highlight", Default = true, Callback = function(v) Controller.Settings.WeaponHighlight = v end })
WeaponGroup:AddToggle("WeaponText", { Text = "Texto flutuante", Default = true, Callback = function(v) Controller.Settings.WeaponText = v end })
WeaponGroup:AddToggle("WeaponNames", { Text = "Mostrar nome", Default = true, Callback = function(v) Controller.Settings.WeaponNames = v end })
WeaponGroup:AddToggle("WeaponDistance", { Text = "Mostrar distância", Default = true, Callback = function(v) Controller.Settings.WeaponDistance = v end })
WeaponGroup:AddSlider("WeaponMaxDistance", { Text = "Distância máx (ESP)", Default = 500, Min = 50, Max = 3000, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.WeaponMaxDistance = v end })
WeaponCollectGroup:AddToggle("WeaponAutoCollect", { Text = "Auto-Collect", Default = true, Callback = function(v) Controller.Settings.WeaponAutoCollect = v end })
WeaponCollectGroup:AddToggle("WeaponTeleport", { Text = "Teleporte", Default = false, Callback = function(v) Controller.Settings.WeaponTeleport = v end })
WeaponCollectGroup:AddSlider("WeaponCollectDistance", { Text = "Distância de coleta", Default = 10, Min = 5, Max = 30, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.WeaponCollectDistance = v end })
WeaponCollectGroup:AddSlider("WeaponCooldown", { Text = "Cooldown por item", Default = 15, Min = 5, Max = 100, Rounding = 0, Suffix = " (x10ms)",
    Callback = function(v) Controller.Settings.WeaponCooldown = v / 100 end })
WeaponCollectGroup:AddSlider("WeaponRateLimit", { Text = "Rate limit", Default = 20, Min = 5, Max = 60, Rounding = 0,
    Callback = function(v) Controller.Settings.WeaponRateLimit = v end })
WeaponColorGroup:AddLabel("Cor do item"):AddColorPicker("WeaponHighlightColor", { Default = Controller.Settings.WeaponHighlightColor,
    Title = "Cor do item", Callback = function(v) Controller.Settings.WeaponHighlightColor = v end })

-- ABA MINAS
local MineMainGroup = Tabs.Minas:AddLeftGroupbox("Minas", "bomb")
local MineAutoGroup = Tabs.Minas:AddRightGroupbox("Auto-Detonate", "zap")
local MineVisualGroup = Tabs.Minas:AddLeftGroupbox("Visual", "palette")

MineMainGroup:AddToggle("MineEnabled", { Text = "Ativar sistema", Default = true,
    Callback = function(v) Controller.Settings.MineEnabled = v end })
MineMainGroup:AddToggle("MineHighlight", { Text = "Highlight nas minas", Default = true,
    Callback = function(v)
        Controller.Settings.MineHighlight = v
        for _, e in pairs(Mines) do if e.visual and e.visual.highlight then e.visual.highlight.Enabled = v end end
    end })
MineMainGroup:AddToggle("MineAlert", { Text = "Alerta 'INIMIGO NA MINA'", Default = true,
    Callback = function(v) Controller.Settings.MineAlert = v end })
MineMainGroup:AddSlider("MineAlertRadius", { Text = "Raio de alerta (inimigo)", Default = 30, Min = 5, Max = 100, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.MineAlertRadius = v end })

MineAutoGroup:AddToggle("MineAutoDetonate", {
    Text = "Auto-Detonar quando inimigo perto", Default = false,
    Callback = function(v) Controller.Settings.MineAutoDetonate = v end })
MineAutoGroup:AddSlider("MineAutoDetonateDelay", {
    Text = "Delay antes de auto-detonar", Default = 0, Min = 0, Max = 300, Rounding = 0, Suffix = " (x10ms)",
    Callback = function(v) Controller.Settings.MineAutoDetonateDelay = v / 100 end })
MineAutoGroup:AddSlider("MinePlayerSafeDistance", {
    Text = "Distância MÍN de você (safety)", Default = 40, Min = 0, Max = 200, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.MinePlayerSafeDistance = v end })
MineAutoGroup:AddSlider("MineMaxDistanceFromPlayer", {
    Text = "Distância MÁX de você (sinal)", Default = 600, Min = 100, Max = 1000, Rounding = 0, Suffix = " studs",
    Callback = function(v) Controller.Settings.MineMaxDistanceFromPlayer = v end })
MineAutoGroup:AddToggle("MineBKeyEnabled", { Text = "Tecla [B] detona todas", Default = true,
    Callback = function(v) Controller.Settings.MineBKeyEnabled = v end })
MineAutoGroup:AddButton({ Text = "Detonar TODAS agora", Func = function()
    task.spawn(function()
        local snapshot = {}
        for mine in pairs(Mines) do table.insert(snapshot, mine) end
        local n = 0
        for _, mine in ipairs(snapshot) do
            if mine.Parent then detonateMine(mine, "manual"); n = n + 1; task.wait(0.12) end
        end
        print("[Mine] Detonou " .. n)
    end)
end })
MineAutoGroup:AddButton({ Text = "Detonar a mais próxima", Func = function()
    local root = getMyRoot(); if not root then return end
    local best, bd = nil, math.huge
    for mine in pairs(Mines) do
        local a = getMineAnchor(mine)
        if a then local d = (a.Position - root.Position).Magnitude; if d < bd then best, bd = mine, d end end
    end
    if best then detonateMine(best, "manual") end
end })

MineVisualGroup:AddLabel("Cor do highlight"):AddColorPicker("MineHighlightColor", { Default = Controller.Settings.MineHighlightColor,
    Title = "Cor do highlight", Callback = function(v) Controller.Settings.MineHighlightColor = v end })

local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu", "wrench")
MenuGroup:AddDropdown("DPIScale", { Values = { "50%", "75%", "100%", "125%", "150%" },
    Default = Library.IsMobile and "75%" or "100%", Text = "DPI scale",
    Callback = function(v) Library:SetDPIScale(tonumber(v:gsub("%%", ""))) end })
MenuGroup:AddLabel("Menu keybind (F1)"):AddKeyPicker("MenuKeybind", { Default = "F1", NoUI = true, Text = "Menu keybind" })
MenuGroup:AddButton({ Text = "Unload", Func = Controller.Unload })

Library.ToggleKeybind = Options.MenuKeybind
Library:OnUnload(cleanup)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("LostFrontESP")
SaveManager:SetFolder("LostFrontESP")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)

addConnection(Players.PlayerRemoving:Connect(removePlayer))
addConnection(Workspace.DescendantAdded:Connect(function(d)
    if d:IsA("Model") then
        task.delay(CONST.DRONE_REGISTER_DELAY, function()
            if not Controller.Unloaded then registerDrone(d) end
        end)
    end
end))

rebuildIgnoreList()
pcall(function() SaveManager:LoadAutoloadConfig() end)
if Toggles.SilentAimEnabled then Toggles.SilentAimEnabled:SetValue(true) end

print("[The Lost Front] Carregado. Menu: [F1] | Minas: [B]")
print("  Detona via: createDrone:InvokeServer(nome) -> explodeDrone:FireServer(nome)")
