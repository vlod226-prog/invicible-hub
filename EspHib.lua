-- Solara V3: INVINCIBLE ESP PRO (Custom Rig/NPC Engine + 2-Page Spring UI)
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Config = {
    Enabled = true,
    Box = true,
    BoxColor = Color3.fromRGB(255, 204, 0),
    Skeleton = true,
    SkeletonColor = Color3.fromRGB(0, 140, 255),
    HealthBar = true,
    WeaponTag = true,
    MovementTracker = true,
    MovementColor = Color3.fromRGB(220, 25, 35),
    PredictionTime = 0.28,
    ShowNPCs = true,
    HideTeammates = false,
    SelectedTeamName = nil,
    NoFog = true,
    Rainbow = false,
    RainbowSpeed = 1.2,
    Thickness = 1.5,
    MinDist = 50,
    MaxDist = 2500,
    RenderDistance = 1200
}

local function getGuiParent()
    if gethui then return gethui() end
    if cloneref and CoreGui then return cloneref(CoreGui) end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- [[ СОХРАНЕНИЕ И ОТКЛЮЧЕНИЕ ТУМАНА ]]
local SavedLighting = {
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    Atmospheres = {}
}

for _, child in pairs(Lighting:GetChildren()) do
    if child:IsA("Atmosphere") then
        SavedLighting.Atmospheres[child] = {
            Density = child.Density,
            Haze = child.Haze,
            Glare = child.Glare
        }
    end
end

local function restoreFog()
    Lighting.FogEnd = SavedLighting.FogEnd
    Lighting.FogStart = SavedLighting.FogStart
    for atm, props in pairs(SavedLighting.Atmospheres) do
        if atm and atm.Parent then
            atm.Density = props.Density
            atm.Haze = props.Haze
            atm.Glare = props.Glare
        end
    end
end

-- [[ ЗВУКИ НА INSERT ]]
local SoundOpen = Instance.new("Sound")
SoundOpen.SoundId = "rbxassetid://122687228704103"
SoundOpen.Volume = 1.5
SoundOpen.Parent = getGuiParent()

local SoundClose = Instance.new("Sound")
SoundClose.SoundId = "rbxassetid://117524609401946"
SoundClose.Volume = 1.5
SoundClose.Parent = getGuiParent()

-- [[ УНИВЕРСАЛЬНЫЙ АНАЛИЗАТОР КОМАНД И КАСТОМНЫХ МОДЕЛЕЙ ]]
local TEAM_KEYS = {"Team", "team", "TEAM", "Side", "side", "Faction", "faction", "Squad", "Role", "TeamName"}
local IGNORED_FOLDERS = {
    ["Camera"] = true, ["Terrain"] = true, ["Debris"] = true,
    ["Viewmodel"] = true, ["ViewModel"] = true, ["Arms"] = true,
    ["Ray_Ignore"] = true, ["Bullets"] = true, ["Map"] = true
}

local function getPlayerFromCharacterModel(model)
    local plr = Players:GetPlayerFromCharacter(model)
    if plr then return plr end
    local found = Players:FindFirstChild(model.Name)
    if found and found:IsA("Player") then return found end
    return nil
end

local function getEntityTeamInfo(model, player)
    if player then
        if player.Team then
            return player.Team.Name, player.Team.TeamColor.Color
        end
        for _, key in ipairs(TEAM_KEYS) do
            local attr = player:GetAttribute(key)
            if attr ~= nil and tostring(attr) ~= "" then
                return tostring(attr), player.TeamColor.Color
            end
        end
        for _, desc in ipairs(player:GetDescendants()) do
            if desc:IsA("ValueBase") then
                for _, key in ipairs(TEAM_KEYS) do
                    if desc.Name == key and desc.Value ~= nil and tostring(desc.Value) ~= "" then
                        return tostring(desc.Value), player.TeamColor.Color
                    end
                end
            end
        end
        if not player.Neutral and player.TeamColor then
            return player.TeamColor.Name, player.TeamColor.Color
        end
    end

    if model then
        for _, key in ipairs(TEAM_KEYS) do
            local attr = model:GetAttribute(key)
            if attr ~= nil and tostring(attr) ~= "" then
                return tostring(attr), Color3.fromRGB(255, 204, 0)
            end
        end
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("ValueBase") then
                for _, key in ipairs(TEAM_KEYS) do
                    if child.Name == key and child.Value ~= nil and tostring(child.Value) ~= "" then
                        return tostring(child.Value), Color3.fromRGB(255, 204, 0)
                    end
                end
            end
        end
        -- В Counter-Blox / Kontra модели часто лежат в папках команд (например workspace.Players.Terrorists)
        if model.Parent and model.Parent ~= workspace then
            local pName = model.Parent.Name
            if pName ~= "Players" and pName ~= "Characters" and pName ~= "Entities" and pName ~= "Bots" and pName ~= "NPCs" then
                return pName, Color3.fromRGB(255, 204, 0)
            end
        end
    end

    return nil, Color3.fromRGB(200, 200, 200)
end

-- Определение корневой части, головы и здоровья у кастомных ригов (Kontra / CB / Blox Strike)
local function extractRigData(model)
    if not model or not model:IsA("Model") then return nil end
    if model:IsDescendantOf(Camera) then return nil end

    local head = model:FindFirstChild("Head") or model:FindFirstChild("head") or model:FindFirstChild("FakeHead")
    local root = model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("LowerTorso")
        or model.PrimaryPart

    if not head or not root or not head:IsA("BasePart") or not root:IsA("BasePart") then
        return nil
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    local health, maxHealth = 100, 100

    if hum then
        health = hum.Health
        maxHealth = math.max(1, hum.MaxHealth)
    else
        local hAttr = model:GetAttribute("Health") or model:GetAttribute("health") or model:GetAttribute("HP")
        local mhAttr = model:GetAttribute("MaxHealth") or model:GetAttribute("maxhealth") or 100
        if type(hAttr) == "number" then
            health = hAttr
            maxHealth = math.max(1, tonumber(mhAttr) or 100)
        else
            local hVal = model:FindFirstChild("Health") or model:FindFirstChild("HP")
            if hVal and hVal:IsA("ValueBase") and type(hVal.Value) == "number" then
                health = hVal.Value
            end
        end
    end

    if health <= 0 then return nil end

    -- Определение оружия в руках
    local weaponName = nil
    local tool = model:FindFirstChildOfClass("Tool")
    if tool then
        weaponName = tool.Name
    else
        local wVal = model:GetAttribute("Weapon") or model:GetAttribute("Equipped") or model:GetAttribute("Gun")
        if wVal and tostring(wVal) ~= "" then
            weaponName = tostring(wVal)
        else
            for _, ch in ipairs(model:GetChildren()) do
                if ch:IsA("Model") and not ch:FindFirstChildOfClass("Humanoid") and ch.Name ~= "Hair" then
                    weaponName = ch.Name
                    break
                end
            end
        end
    end

    return {
        Model = model,
        Head = head,
        Root = root,
        Humanoid = hum,
        Health = health,
        MaxHealth = maxHealth,
        Weapon = weaponName
    }
end

-- Реестр всех целей (обновляется в фоне без просадок FPS)
local TrackedEntities = {} -- [Model] = {Player = Player?, IsNPC = bool}

local function scanWorkspaceForEntities()
    local newSet = {}
    local myChar = LocalPlayer.Character

    -- 1. Стандартные персонажи игроков
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            newSet[plr.Character] = {Player = plr, IsNPC = false}
        end
    end

    -- 2. Глубокий обход папок Workspace для кастомных спавнов (Kontra, CB, Blox Strike) и NPC
    local function inspectContainer(container, depth)
        if depth > 3 then return end
        for _, child in ipairs(container:GetChildren()) do
            if not IGNORED_FOLDERS[child.Name] then
                if child:IsA("Model") and child ~= myChar then
                    if not newSet[child] then
                        local head = child:FindFirstChild("Head") or child:FindFirstChild("head") or child:FindFirstChild("FakeHead")
                        local root = child:FindFirstChild("HumanoidRootPart") or child:FindFirstChild("Torso") or child:FindFirstChild("UpperTorso")
                        if head and root and head:IsA("BasePart") and root:IsA("BasePart") then
                            local linkedPlr = getPlayerFromCharacterModel(child)
                            if linkedPlr ~= LocalPlayer then
                                newSet[child] = {
                                    Player = linkedPlr,
                                    IsNPC = (linkedPlr == nil)
                                }
                            end
                        else
                            inspectContainer(child, depth + 1)
                        end
                    end
                elseif child:IsA("Folder") then
                    inspectContainer(child, depth + 1)
                end
            end
        end
    end

    inspectContainer(workspace, 1)
    TrackedEntities = newSet
end

-- [[ ДВУХСТРАНИЧНЫЙ GUI С ПРУЖИННОЙ ФИЗИКОЙ ]]
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "InvincibleESP_Pro"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = getGuiParent()

local Holder = Instance.new("Frame")
Holder.Size = UDim2.new(0, 345, 0, 410)
Holder.Position = UDim2.new(0.06, 0, 0.22, 0)
Holder.BackgroundTransparency = 1
Holder.Parent = ScreenGui

local HolderScale = Instance.new("UIScale", Holder)
HolderScale.Scale = 1

local OuterStroke = Instance.new("UIStroke", Holder)
OuterStroke.Color = Color3.fromRGB(255, 204, 0)
OuterStroke.Thickness = 2

Instance.new("UICorner", Holder).CornerRadius = UDim.new(0, 14)

local MainCanvas = Instance.new("Frame")
MainCanvas.Size = UDim2.new(1, 0, 1, 0)
MainCanvas.BackgroundColor3 = Color3.fromRGB(11, 13, 20)
MainCanvas.BorderSizePixel = 0
MainCanvas.ClipsDescendants = true
MainCanvas.Parent = Holder
Instance.new("UICorner", MainCanvas).CornerRadius = UDim.new(0, 14)

-- Слой крови строго внутри рамок
local BloodLayer = Instance.new("Frame")
BloodLayer.Size = UDim2.new(1, 0, 1, 0)
BloodLayer.BackgroundTransparency = 1
BloodLayer.ZIndex = 1
BloodLayer.Parent = MainCanvas

local BloodPoolBack = Instance.new("Frame")
BloodPoolBack.Size = UDim2.new(1.2, 0, 0, 18)
BloodPoolBack.Position = UDim2.new(-0.1, 0, 1, -14)
BloodPoolBack.BackgroundColor3 = Color3.fromRGB(130, 8, 15)
BloodPoolBack.BackgroundTransparency = 0.25
BloodPoolBack.BorderSizePixel = 0
BloodPoolBack.ZIndex = 1
BloodPoolBack.Parent = BloodLayer
Instance.new("UICorner", BloodPoolBack).CornerRadius = UDim.new(0, 14)

local BloodPoolFront = Instance.new("Frame")
BloodPoolFront.Size = UDim2.new(1.2, 0, 0, 14)
BloodPoolFront.Position = UDim2.new(-0.1, 0, 1, -10)
BloodPoolFront.BackgroundColor3 = Color3.fromRGB(190, 12, 22)
BloodPoolFront.BackgroundTransparency = 0.1
BloodPoolFront.BorderSizePixel = 0
BloodPoolFront.ZIndex = 2
BloodPoolFront.Parent = BloodLayer
Instance.new("UICorner", BloodPoolFront).CornerRadius = UDim.new(0, 14)

local function createSplash(xScale)
    local splash = Instance.new("Frame")
    splash.AnchorPoint = Vector2.new(0.5, 0.5)
    splash.Size = UDim2.new(0, 4, 0, 2)
    splash.Position = UDim2.new(xScale, 0, 1, -10)
    splash.BackgroundColor3 = Color3.fromRGB(230, 30, 40)
    splash.BorderSizePixel = 0
    splash.ZIndex = 2
    splash.Parent = BloodLayer
    Instance.new("UICorner", splash).CornerRadius = UDim.new(1, 0)

    local tw = TweenService:Create(splash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 28, 0, 4),
        BackgroundTransparency = 1
    })
    tw:Play()
    tw.Completed:Connect(function() splash:Destroy() end)
end

local Drops = {}
for i = 1, 14 do
    local d = Instance.new("Frame")
    d.AnchorPoint = Vector2.new(0.5, 1)
    local w = math.random(3, 4)
    local h = math.random(12, 24)
    d.Size = UDim2.new(0, w, 0, h)
    local startX = math.random(8, 92) / 100
    local startY = math.random(-50, 90) / 100
    d.Position = UDim2.new(startX, 0, startY, 0)
    d.BackgroundColor3 = Color3.fromRGB(200, 15, 25)
    d.BackgroundTransparency = 0.2
    d.BorderSizePixel = 0
    d.ZIndex = 1
    d.Parent = BloodLayer
    Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)

    local grad = Instance.new("UIGradient", d)
    grad.Rotation = 90
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.6, 0.3),
        NumberSequenceKeypoint.new(1, 0)
    })

    table.insert(Drops, {
        Obj = d,
        X = startX,
        Y = startY,
        Vel = math.random(25, 45) / 100
    })
end

local poolFill = 0
RunService.RenderStepped:Connect(function(dt)
    if not Holder.Visible then return end
    local t = tick()
    local wave1 = math.sin(t * 2.2) * 3
    local wave2 = math.cos(t * 1.8) * 3
    BloodPoolBack.Position = UDim2.new(-0.1, wave1, 1, -12 - poolFill)
    BloodPoolBack.Size = UDim2.new(1.2, 0, 0, 24 + poolFill)
    BloodPoolFront.Position = UDim2.new(-0.1, wave2, 1, -8 - poolFill)
    BloodPoolFront.Size = UDim2.new(1.2, 0, 0, 20 + poolFill)

    for _, d in ipairs(Drops) do
        d.Vel = d.Vel + dt * 0.45
        d.Y = d.Y + d.Vel * dt
        if d.Y >= 0.96 then
            createSplash(d.X)
            poolFill = (poolFill + 0.15) % 8
            d.Y = -0.05
            d.X = math.random(8, 92) / 100
            d.Vel = math.random(20, 35) / 100
        end
        d.Obj.Position = UDim2.new(d.X, 0, d.Y, 0)
    end
end)

-- Шапка
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 44)
Header.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
Header.BorderSizePixel = 0
Header.ZIndex = 10
Header.Parent = MainCanvas

local HeaderLine = Instance.new("Frame")
HeaderLine.Size = UDim2.new(1, 0, 0, 2)
HeaderLine.Position = UDim2.new(0, 0, 1, -2)
HeaderLine.BackgroundColor3 = Color3.fromRGB(255, 204, 0)
HeaderLine.BorderSizePixel = 0
HeaderLine.ZIndex = 10
HeaderLine.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -90, 1, 0)
Title.Position = UDim2.new(0, 16, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "INVINCIBLE // ESP PRO"
Title.TextColor3 = Color3.fromRGB(255, 204, 0)
Title.Font = Enum.Font.GothamBlack
Title.TextSize = 15
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.ZIndex = 11
Title.Parent = Header

local SettingsBtn = Instance.new("TextButton")
SettingsBtn.AnchorPoint = Vector2.new(0.5, 0.5)
SettingsBtn.Size = UDim2.new(0, 30, 0, 30)
SettingsBtn.Position = UDim2.new(1, -26, 0.5, 0)
SettingsBtn.BackgroundColor3 = Color3.fromRGB(26, 32, 48)
SettingsBtn.Text = "⚙"
SettingsBtn.TextColor3 = Color3.fromRGB(255, 204, 0)
SettingsBtn.Font = Enum.Font.GothamBold
SettingsBtn.TextSize = 17
SettingsBtn.AutoButtonColor = false
SettingsBtn.ZIndex = 11
SettingsBtn.Parent = Header
Instance.new("UICorner", SettingsBtn).CornerRadius = UDim.new(0, 8)

local SettingsBtnStroke = Instance.new("UIStroke", SettingsBtn)
SettingsBtnStroke.Color = Color3.fromRGB(255, 204, 0)
SettingsBtnStroke.Thickness = 1.2
SettingsBtnStroke.Transparency = 0.4

-- Плавный Drag окна за шапку
do
    local dragging, dragStart, startPos
    Header.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = inp.Position
            startPos = Holder.Position
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            TweenService:Create(Holder, TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            }):Play()
        end
    end)
end

-- Функция создания страницы с кастомным неоновым скроллбаром
local function createScrolledPage(defaultPos)
    local page = Instance.new("Frame")
    page.Size = UDim2.new(1, 0, 1, -44)
    page.Position = defaultPos
    page.BackgroundTransparency = 1
    page.ZIndex = 5
    page.Parent = MainCanvas

    local box = Instance.new("ScrollingFrame")
    box.Size = UDim2.new(1, -26, 1, -18)
    box.Position = UDim2.new(0, 12, 0, 8)
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.ScrollBarThickness = 0
    box.CanvasSize = UDim2.new(0, 0, 0, 0)
    box.ZIndex = 5
    box.Parent = page

    local layout = Instance.new("UIListLayout", box)
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local pad = Instance.new("UIPadding", box)
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 18)
    pad.PaddingLeft = UDim.new(0, 2)
    pad.PaddingRight = UDim.new(0, 2)

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0.5, 0)
    track.Size = UDim2.new(0, 5, 1, -30)
    track.Position = UDim2.new(1, -8, 0, 12)
    track.BackgroundColor3 = Color3.fromRGB(22, 27, 42)
    track.BorderSizePixel = 0
    track.ZIndex = 6
    track.Parent = page
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local thumb = Instance.new("Frame")
    thumb.AnchorPoint = Vector2.new(0.5, 0)
    thumb.Size = UDim2.new(1, 0, 0.35, 0)
    thumb.Position = UDim2.new(0.5, 0, 0, 0)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 204, 0)
    thumb.BorderSizePixel = 0
    thumb.ZIndex = 7
    thumb.Parent = track
    Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)

    local function syncScroll()
        local canvasH = layout.AbsoluteContentSize.Y + 24
        box.CanvasSize = UDim2.new(0, 0, 0, canvasH)
        local viewH = box.AbsoluteWindowSize.Y
        local ratio = math.clamp(viewH / math.max(1, canvasH), 0.15, 1)
        local maxScroll = math.max(1, canvasH - viewH)
        local progress = math.clamp(box.CanvasPosition.Y / maxScroll, 0, 1)

        TweenService:Create(thumb, TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, 0, ratio, 0),
            Position = UDim2.new(0.5, 0, progress * (1 - ratio), 0)
        }):Play()
    end

    box:GetPropertyChangedSignal("CanvasPosition"):Connect(syncScroll)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncScroll)

    track.MouseEnter:Connect(function()
        TweenService:Create(track, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 8, 1, -30)}):Play()
        TweenService:Create(thumb, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(0, 170, 255)}):Play()
    end)
    track.MouseLeave:Connect(function()
        TweenService:Create(track, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 5, 1, -30)}):Play()
        TweenService:Create(thumb, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(255, 204, 0)}):Play()
    end)

    return page, box
end

local MainPage, MainScroll = createScrolledPage(UDim2.new(0, 0, 0, 44))
local SettingsPage, SettingsScroll = createScrolledPage(UDim2.new(1, 0, 0, 44))

-- Компонент анимированного тумблера
local function createAnimatedToggle(parentScroll, name, defaultState, order, callback)
    local card = Instance.new("TextButton")
    card.Size = UDim2.new(1, 0, 0, 44)
    card.LayoutOrder = order
    card.BackgroundColor3 = Color3.fromRGB(18, 23, 36)
    card.Text = ""
    card.AutoButtonColor = false
    card.ZIndex = 6
    card.Parent = parentScroll
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

    local cardScale = Instance.new("UIScale", card)
    cardScale.Scale = 1

    local stroke = Instance.new("UIStroke", card)
    stroke.Color = defaultState and Color3.fromRGB(255, 204, 0) or Color3.fromRGB(36, 45, 68)
    stroke.Thickness = 1.3

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -76, 1, 0)
    title.Position = UDim2.new(0, 14, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = name
    title.TextColor3 = Color3.fromRGB(240, 245, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 7
    title.Parent = card

    local pill = Instance.new("Frame")
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Size = UDim2.new(0, 48, 0, 24)
    pill.Position = UDim2.new(1, -12, 0.5, 0)
    pill.BackgroundColor3 = defaultState and Color3.fromRGB(0, 115, 240) or Color3.fromRGB(11, 14, 22)
    pill.BorderSizePixel = 0
    pill.ZIndex = 7
    pill.Parent = card
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local dot = Instance.new("Frame")
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Size = UDim2.new(0, 16, 0, 16)
    dot.Position = defaultState and UDim2.new(0, 35, 0.5, 0) or UDim2.new(0, 13, 0.5, 0)
    dot.BackgroundColor3 = defaultState and Color3.fromRGB(255, 204, 0) or Color3.fromRGB(130, 145, 175)
    dot.BorderSizePixel = 0
    dot.ZIndex = 8
    dot.Parent = pill
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local state = defaultState

    card.MouseEnter:Connect(function()
        TweenService:Create(cardScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.015}):Play()
    end)
    card.MouseLeave:Connect(function()
        TweenService:Create(cardScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
    end)

    card.MouseButton1Click:Connect(function()
        state = not state
        cardScale.Scale = 0.96
        TweenService:Create(cardScale, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Scale = 1.015}):Play()

        dot.Size = UDim2.new(0, 24, 0, 14)
        TweenService:Create(dot, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 16, 0, 16),
            Position = state and UDim2.new(0, 35, 0.5, 0) or UDim2.new(0, 13, 0.5, 0),
            BackgroundColor3 = state and Color3.fromRGB(255, 204, 0) or Color3.fromRGB(130, 145, 175)
        }):Play()

        TweenService:Create(pill, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            BackgroundColor3 = state and Color3.fromRGB(0, 115, 240) or Color3.fromRGB(11, 14, 22)
        }):Play()

        TweenService:Create(stroke, TweenInfo.new(0.25), {
            Color = state and Color3.fromRGB(255, 204, 0) or Color3.fromRGB(36, 45, 68)
        }):Play()

        callback(state)
    end)
end

-- Универсальный слайдер с кружочком, пузырьком и ударной волной
local function createKnobSlider(parentScroll, titleText, minGetter, maxGetter, defaultVal, decimals, order, hintText, callback)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, hintText and 90 or 76)
    card.LayoutOrder = order
    card.BackgroundColor3 = Color3.fromRGB(18, 23, 36)
    card.BorderSizePixel = 0
    card.ZIndex = 6
    card.Parent = parentScroll
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

    local cardStroke = Instance.new("UIStroke", card)
    cardStroke.Color = Color3.fromRGB(36, 45, 68)
    cardStroke.Thickness = 1.3

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.6, 0, 0, 22)
    title.Position = UDim2.new(0, 14, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = Color3.fromRGB(240, 245, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 7
    title.Parent = card

    local badge = Instance.new("TextLabel")
    badge.AnchorPoint = Vector2.new(1, 0)
    badge.Size = UDim2.new(0, 74, 0, 22)
    badge.Position = UDim2.new(1, -14, 0, 8)
    badge.BackgroundColor3 = Color3.fromRGB(11, 14, 22)
    badge.Text = tostring(defaultVal)
    badge.TextColor3 = Color3.fromRGB(255, 204, 0)
    badge.Font = Enum.Font.GothamBlack
    badge.TextSize = 13
    badge.ZIndex = 7
    badge.Parent = card
    Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 6)

    local badgeScale = Instance.new("UIScale", badge)
    badgeScale.Scale = 1

    local hintLabel
    if hintText then
        hintLabel = Instance.new("TextLabel")
        hintLabel.Size = UDim2.new(1, -28, 0, 14)
        hintLabel.Position = UDim2.new(0, 14, 0, 70)
        hintLabel.BackgroundTransparency = 1
        hintLabel.Text = hintText
        hintLabel.TextColor3 = Color3.fromRGB(130, 145, 175)
        hintLabel.Font = Enum.Font.GothamMedium
        hintLabel.TextSize = 11
        hintLabel.TextXAlignment = Enum.TextXAlignment.Left
        hintLabel.ZIndex = 7
        hintLabel.Parent = card
    end

    local hitbox = Instance.new("TextButton")
    hitbox.Size = UDim2.new(1, -36, 0, 28)
    hitbox.Position = UDim2.new(0, 18, 0, 38)
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""
    hitbox.AutoButtonColor = false
    hitbox.ZIndex = 8
    hitbox.Parent = card

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0, 0.5)
    track.Size = UDim2.new(1, 0, 0, 8)
    track.Position = UDim2.new(0, 0, 0.5, 0)
    track.BackgroundColor3 = Color3.fromRGB(11, 14, 22)
    track.BorderSizePixel = 0
    track.ZIndex = 7
    track.Parent = hitbox
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local minV, maxV = minGetter(), maxGetter()
    local initPct = math.clamp((defaultVal - minV) / math.max(0.001, maxV - minV), 0, 1)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(initPct, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    fill.BorderSizePixel = 0
    fill.ZIndex = 8
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local grab = Instance.new("Frame")
    grab.AnchorPoint = Vector2.new(0.5, 0.5)
    grab.Size = UDim2.new(0, 20, 0, 20)
    grab.Position = UDim2.new(initPct, 0, 0.5, 0)
    grab.BackgroundColor3 = Color3.fromRGB(255, 204, 0)
    grab.BorderSizePixel = 0
    grab.ZIndex = 10
    grab.Parent = track
    Instance.new("UICorner", grab).CornerRadius = UDim.new(1, 0)

    local grabStroke = Instance.new("UIStroke", grab)
    grabStroke.Color = Color3.fromRGB(255, 255, 255)
    grabStroke.Thickness = 2.5

    local core = Instance.new("Frame")
    core.AnchorPoint = Vector2.new(0.5, 0.5)
    core.Size = UDim2.new(0, 6, 0, 6)
    core.Position = UDim2.new(0.5, 0, 0.5, 0)
    core.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
    core.BorderSizePixel = 0
    core.ZIndex = 11
    core.Parent = grab
    Instance.new("UICorner", core).CornerRadius = UDim.new(1, 0)

    local bubble = Instance.new("TextLabel")
    bubble.AnchorPoint = Vector2.new(0.5, 1)
    bubble.Size = UDim2.new(0, 48, 0, 22)
    bubble.Position = UDim2.new(0.5, 0, 0, -8)
    bubble.BackgroundColor3 = Color3.fromRGB(255, 204, 0)
    bubble.Text = tostring(defaultVal)
    bubble.TextColor3 = Color3.fromRGB(12, 15, 22)
    bubble.Font = Enum.Font.GothamBlack
    bubble.TextSize = 12
    bubble.ZIndex = 15
    bubble.Parent = grab
    Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, 6)

    local bubbleScale = Instance.new("UIScale", bubble)
    bubbleScale.Scale = 0

    local shock = Instance.new("Frame")
    shock.AnchorPoint = Vector2.new(0.5, 0.5)
    shock.Size = UDim2.new(0, 20, 0, 20)
    shock.Position = UDim2.new(0.5, 0, 0.5, 0)
    shock.BackgroundTransparency = 1
    shock.ZIndex = 9
    shock.Parent = grab
    Instance.new("UICorner", shock).CornerRadius = UDim.new(1, 0)

    local waveStroke = Instance.new("UIStroke", shock)
    waveStroke.Color = Color3.fromRGB(255, 204, 0)
    waveStroke.Thickness = 3
    waveStroke.Transparency = 1

    local function setPct(pct)
        pct = math.clamp(pct, 0, 1)
        local lo, hi = minGetter(), maxGetter()
        local raw = lo + (hi - lo) * pct
        local mult = 10 ^ decimals
        local val = math.floor(raw * mult + 0.5) / mult
        badge.Text = tostring(val)
        bubble.Text = tostring(val)
        callback(val)

        TweenService:Create(fill, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(pct, 0, 1, 0)}):Play()
        TweenService:Create(grab, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(pct, 0, 0.5, 0)}):Play()
    end

    local dragging = false
    hitbox.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            setPct((inp.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
            TweenService:Create(grab, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 28, 0, 28),
                BackgroundColor3 = Color3.fromRGB(255, 235, 90)
            }):Play()
            TweenService:Create(core, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 10, 0, 10)}):Play()
            TweenService:Create(bubbleScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
            TweenService:Create(cardStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(255, 204, 0)}):Play()
        end
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            setPct((inp.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false
            grab.Size = UDim2.new(0, 34, 0, 34)
            TweenService:Create(grab, TweenInfo.new(0.65, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 20, 0, 20),
                BackgroundColor3 = Color3.fromRGB(255, 204, 0)
            }):Play()
            TweenService:Create(core, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Size = UDim2.new(0, 6, 0, 6)}):Play()
            TweenService:Create(bubbleScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0}):Play()

            badgeScale.Scale = 1.35
            TweenService:Create(badgeScale, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Scale = 1}):Play()

            shock.Size = UDim2.new(0, 20, 0, 20)
            waveStroke.Transparency = 0
            TweenService:Create(shock, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0, 62, 0, 62)}):Play()
            TweenService:Create(waveStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Transparency = 1}):Play()
            TweenService:Create(cardStroke, TweenInfo.new(0.3), {Color = Color3.fromRGB(36, 45, 68)}):Play()
        end
    end)

    return {
        SetPct = setPct,
        HintLabel = hintLabel
    }
end

-- Наполнение Страницы 1 (Главные переключатели)
createAnimatedToggle(MainScroll, "Главный ESP (Master)", Config.Enabled, 1, function(v) Config.Enabled = v end)
createAnimatedToggle(MainScroll, "Боксы (2D Box)", Config.Box, 2, function(v) Config.Box = v end)
createAnimatedToggle(MainScroll, "Кости (Skeleton R6/R15/Custom)", Config.Skeleton, 3, function(v) Config.Skeleton = v end)
createAnimatedToggle(MainScroll, "Шкала ХП и Оружие в руках", Config.HealthBar, 4, function(v)
    Config.HealthBar = v
    Config.WeaponTag = v
end)
createAnimatedToggle(MainScroll, "Маркер упреждения бега", Config.MovementTracker, 5, function(v) Config.MovementTracker = v end)
createAnimatedToggle(MainScroll, "Видеть кастомных NPC и Ботов", Config.ShowNPCs, 6, function(v) Config.ShowNPCs = v end)
createAnimatedToggle(MainScroll, "Скрыть союзников (Team Check)", Config.HideTeammates, 7, function(v) Config.HideTeammates = v end)
createAnimatedToggle(MainScroll, "Убрать туман (No Fog)", Config.NoFog, 8, function(v)
    Config.NoFog = v
    if not v then restoreFog() end
end)
createAnimatedToggle(MainScroll, "RGB Перелив (Rainbow)", Config.Rainbow, 9, function(v) Config.Rainbow = v end)

local DistSliderObj = createKnobSlider(
    MainScroll,
    "Дистанция ESP (м)",
    function() return Config.MinDist end,
    function() return Config.MaxDist end,
    Config.RenderDistance,
    0,
    10,
    "Лимит: от " .. Config.MinDist .. " до " .. Config.MaxDist .. " (меняется в ⚙)",
    function(v) Config.RenderDistance = v end
)

createKnobSlider(
    MainScroll,
    "Толщина линий",
    function() return 1 end,
    function() return 3.5 end,
    Config.Thickness,
    1,
    11,
    nil,
    function(v) Config.Thickness = v end
)

-- [[ СТРАНИЦА 2: НАСТРОЙКИ ЛИМИТОВ И ФИЛЬТР КОМАНД ]]
local BoundsCard = Instance.new("Frame")
BoundsCard.Size = UDim2.new(1, 0, 0, 178)
BoundsCard.LayoutOrder = 1
BoundsCard.BackgroundColor3 = Color3.fromRGB(18, 23, 36)
BoundsCard.BorderSizePixel = 0
BoundsCard.ZIndex = 6
BoundsCard.Parent = SettingsScroll
Instance.new("UICorner", BoundsCard).CornerRadius = UDim.new(0, 10)

local BoundsStroke = Instance.new("UIStroke", BoundsCard)
BoundsStroke.Color = Color3.fromRGB(255, 204, 0)
BoundsStroke.Thickness = 1.2
BoundsStroke.Transparency = 0.4

local BoundsTitle = Instance.new("TextLabel")
BoundsTitle.Size = UDim2.new(1, -24, 0, 28)
BoundsTitle.Position = UDim2.new(0, 12, 0, 8)
BoundsTitle.BackgroundTransparency = 1
BoundsTitle.Text = "ЛИМИТ ДИСТАНЦИИ ПОЛЗУНКА (БЕЗ ОГРАНИЧЕНИЙ)"
BoundsTitle.TextColor3 = Color3.fromRGB(255, 204, 0)
BoundsTitle.Font = Enum.Font.GothamBlack
BoundsTitle.TextSize = 11
BoundsTitle.TextXAlignment = Enum.TextXAlignment.Left
BoundsTitle.ZIndex = 7
BoundsTitle.Parent = BoundsCard

local function createSettingInput(labelTxt, defaultVal, yPos)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -24, 0, 36)
    row.Position = UDim2.new(0, 12, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(11, 14, 22)
    row.ZIndex = 7
    row.Parent = BoundsCard
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local rStroke = Instance.new("UIStroke", row)
    rStroke.Color = Color3.fromRGB(40, 50, 75)
    rStroke.Thickness = 1.2

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.55, 0, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelTxt
    lbl.TextColor3 = Color3.fromRGB(170, 185, 210)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 8
    lbl.Parent = row

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.4, -12, 1, 0)
    box.Position = UDim2.new(0.6, 0, 0, 0)
    box.BackgroundTransparency = 1
    box.Text = tostring(defaultVal)
    box.TextColor3 = Color3.fromRGB(255, 204, 0)
    box.Font = Enum.Font.GothamBlack
    box.TextSize = 14
    box.TextXAlignment = Enum.TextXAlignment.Right
    box.ClearTextOnFocus = false
    box.ZIndex = 8
    box.Parent = row

    box.Focused:Connect(function()
        TweenService:Create(rStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(255, 204, 0)}):Play()
    end)
    box.FocusLost:Connect(function()
        TweenService:Create(rStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(40, 50, 75)}):Play()
    end)

    return box
end

local MinDistBox = createSettingInput("Минимум (ОТ):", Config.MinDist, 40)
local MaxDistBox = createSettingInput("Максимум (ДО):", Config.MaxDist, 84)

local ApplyBoundsBtn = Instance.new("TextButton")
ApplyBoundsBtn.Size = UDim2.new(1, -24, 0, 34)
ApplyBoundsBtn.Position = UDim2.new(0, 12, 0, 130)
ApplyBoundsBtn.BackgroundColor3 = Color3.fromRGB(255, 204, 0)
ApplyBoundsBtn.Text = "ПРИМЕНИТЬ ЛИМИТЫ"
ApplyBoundsBtn.TextColor3 = Color3.fromRGB(12, 15, 22)
ApplyBoundsBtn.Font = Enum.Font.GothamBlack
ApplyBoundsBtn.TextSize = 12
ApplyBoundsBtn.AutoButtonColor = false
ApplyBoundsBtn.ZIndex = 8
ApplyBoundsBtn.Parent = BoundsCard
Instance.new("UICorner", ApplyBoundsBtn).CornerRadius = UDim.new(0, 8)

local ApplyScale = Instance.new("UIScale", ApplyBoundsBtn)

ApplyBoundsBtn.MouseButton1Click:Connect(function()
    local nMin = tonumber(MinDistBox.Text) or 10
    local nMax = tonumber(MaxDistBox.Text) or 5000
    if nMax <= nMin then
        nMax = nMin + 50
        MaxDistBox.Text = tostring(nMax)
    end
    Config.MinDist = nMin
    Config.MaxDist = nMax
    Config.RenderDistance = math.clamp(Config.RenderDistance, nMin, nMax)

    if DistSliderObj.HintLabel then
        DistSliderObj.HintLabel.Text = "Лимит: от " .. Config.MinDist .. " до " .. Config.MaxDist .. " (меняется в ⚙)"
    end
    local pct = (Config.RenderDistance - Config.MinDist) / math.max(1, Config.MaxDist - Config.MinDist)
    DistSliderObj.SetPct(pct)

    ApplyScale.Scale = 0.92
    TweenService:Create(ApplyScale, TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Scale = 1}):Play()
end)

createKnobSlider(
    SettingsScroll,
    "Скорость перелива RGB",
    function() return 0.1 end,
    function() return 5 end,
    Config.RainbowSpeed,
    1,
    2,
    nil,
    function(v) Config.RainbowSpeed = v end
)

-- Список команд во вкладке настроек
local TeamHeader = Instance.new("TextButton")
TeamHeader.Size = UDim2.new(1, 0, 0, 34)
TeamHeader.LayoutOrder = 3
TeamHeader.BackgroundColor3 = Color3.fromRGB(255, 204, 0)
TeamHeader.Text = "🎯 ФИЛЬТР КОМАНД (ОБНОВИТЬ 🔄)"
TeamHeader.TextColor3 = Color3.fromRGB(12, 15, 22)
TeamHeader.Font = Enum.Font.GothamBlack
TeamHeader.TextSize = 12
TeamHeader.ZIndex = 6
TeamHeader.Parent = SettingsScroll
Instance.new("UICorner", TeamHeader).CornerRadius = UDim.new(0, 8)

local TeamContainer = Instance.new("Frame")
TeamContainer.Size = UDim2.new(1, 0, 0, 30)
TeamContainer.LayoutOrder = 4
TeamContainer.BackgroundTransparency = 1
TeamContainer.ZIndex = 6
TeamContainer.Parent = SettingsScroll

local TeamListLayout = Instance.new("UIListLayout", TeamContainer)
TeamListLayout.Padding = UDim.new(0, 6)
TeamListLayout.SortOrder = Enum.SortOrder.LayoutOrder

TeamListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    TeamContainer.Size = UDim2.new(1, 0, 0, TeamListLayout.AbsoluteContentSize.Y)
end)

local function collectAllDiscoveredTeams()
    local discovered = {}
    for _, t in ipairs(Teams:GetTeams()) do
        discovered[t.Name] = t.TeamColor.Color
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        local tName, tColor = getEntityTeamInfo(plr.Character, plr)
        if tName and not discovered[tName] then
            discovered[tName] = tColor
        end
    end
    for model, info in pairs(TrackedEntities) do
        local tName, tColor = getEntityTeamInfo(model, info.Player)
        if tName and not discovered[tName] then
            discovered[tName] = tColor
        end
    end
    return discovered
end

local function refreshTeamsUI()
    for _, child in pairs(TeamContainer:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end

    local discovered = collectAllDiscoveredTeams()
    local count = 0
    for _ in pairs(discovered) do count = count + 1 end

    if count == 0 then
        Config.SelectedTeamName = nil
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 32)
        empty.BackgroundColor3 = Color3.fromRGB(18, 23, 36)
        empty.Text = "Команд не найдено (Работает на всех)"
        empty.TextColor3 = Color3.fromRGB(160, 175, 200)
        empty.Font = Enum.Font.GothamBold
        empty.TextSize = 12
        empty.ZIndex = 6
        empty.Parent = TeamContainer
        Instance.new("UICorner", empty).CornerRadius = UDim.new(0, 8)
        return
    end

    local allBtn = Instance.new("TextButton")
    allBtn.Size = UDim2.new(1, 0, 0, 32)
    allBtn.BackgroundColor3 = (Config.SelectedTeamName == nil) and Color3.fromRGB(0, 110, 230) or Color3.fromRGB(18, 23, 36)
    allBtn.Text = (Config.SelectedTeamName == nil) and "✓ Все команды [Активно]" or "Показать все команды (Сброс)"
    allBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    allBtn.Font = Enum.Font.GothamBold
    allBtn.TextSize = 12
    allBtn.ZIndex = 6
    allBtn.Parent = TeamContainer
    Instance.new("UICorner", allBtn).CornerRadius = UDim.new(0, 8)

    allBtn.MouseButton1Click:Connect(function()
        Config.SelectedTeamName = nil
        refreshTeamsUI()
    end)

    for teamName, teamColor in pairs(discovered) do
        local isSelected = (Config.SelectedTeamName == teamName)
        local tBtn = Instance.new("TextButton")
        tBtn.Size = UDim2.new(1, 0, 0, 32)
        tBtn.BackgroundColor3 = isSelected and Color3.fromRGB(0, 110, 230) or Color3.fromRGB(18, 23, 36)
        tBtn.Text = (isSelected and "✓ Только: " or "Команда: ") .. tostring(teamName)
        tBtn.TextColor3 = teamColor or Color3.fromRGB(255, 255, 255)
        tBtn.Font = Enum.Font.GothamBold
        tBtn.TextSize = 13
        tBtn.ZIndex = 6
        tBtn.Parent = TeamContainer
        Instance.new("UICorner", tBtn).CornerRadius = UDim.new(0, 8)

        local tStroke = Instance.new("UIStroke", tBtn)
        tStroke.Color = isSelected and Color3.fromRGB(255, 204, 0) or Color3.fromRGB(36, 45, 68)
        tStroke.Thickness = 1.2

        tBtn.MouseButton1Click:Connect(function()
            if Config.SelectedTeamName == teamName then
                Config.SelectedTeamName = nil
            else
                Config.SelectedTeamName = teamName
            end
            refreshTeamsUI()
        end)
    end
end

TeamHeader.MouseButton1Click:Connect(function()
    scanWorkspaceForEntities()
    refreshTeamsUI()
end)

-- Переключение между Главной и Настройками
local inSettings = false
SettingsBtn.MouseButton1Click:Connect(function()
    inSettings = not inSettings
    if inSettings then
        scanWorkspaceForEntities()
        refreshTeamsUI()
    end

    TweenService:Create(SettingsBtn, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Rotation = inSettings and 180 or 0,
        BackgroundColor3 = inSettings and Color3.fromRGB(255, 204, 0) or Color3.fromRGB(26, 32, 48),
        TextColor3 = inSettings and Color3.fromRGB(15, 20, 30) or Color3.fromRGB(255, 204, 0)
    }):Play()
    SettingsBtn.Text = inSettings and "◀" or "⚙"
    Title.Text = inSettings and "НАСТРОЙКИ И КОМАНДЫ" or "INVINCIBLE // ESP PRO"

    TweenService:Create(MainPage, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = inSettings and UDim2.new(-1, 0, 0, 44) or UDim2.new(0, 0, 0, 44)
    }):Play()
    TweenService:Create(SettingsPage, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = inSettings and UDim2.new(0, 0, 0, 44) or UDim2.new(1, 0, 0, 44)
    }):Play()
end)

-- Открытие / Закрытие на Insert
local guiVisible = true
UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.Insert then
        guiVisible = not guiVisible
        if guiVisible then
            SoundOpen:Play()
            Holder.Visible = true
            HolderScale.Scale = 0.75
            TweenService:Create(HolderScale, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Scale = 1}):Play()
        else
            SoundClose:Play()
            local closeTween = TweenService:Create(HolderScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.75})
            closeTween:Play()
            closeTween.Completed:Connect(function()
                if not guiVisible then Holder.Visible = false end
            end)
        end
    end
end)

-- [[ DRAWING РЕНДЕРИНГ (ИГРОКИ + КАСТОМНЫЕ РИГИ + NPC) ]]
local Cache = {}

local function cleanEntity(model)
    local c = Cache[model]
    if c then
        for _, l in pairs(c.Box) do l:Remove() end
        for _, l in pairs(c.MoveBox) do l:Remove() end
        for _, l in pairs(c.Skel) do l:Remove() end
        c.HealthBg:Remove()
        c.HealthFill:Remove()
        c.InfoTag:Remove()
        Cache[model] = nil
    end
end

local function createSquare()
    local t = {}
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Thickness = 1
        table.insert(t, l)
    end
    return t
end

local function drawSquare(square, pos, size, color, thick, visible)
    if not visible then
        for i = 1, 4 do square[i].Visible = false end
        return
    end
    local p1 = pos
    local p2 = pos + Vector2.new(size.X, 0)
    local p3 = pos + size
    local p4 = pos + Vector2.new(0, size.Y)
    local coords = {{p1, p2}, {p2, p3}, {p3, p4}, {p4, p1}}

    for i = 1, 4 do
        square[i].Visible = true
        square[i].From = coords[i][1]
        square[i].To = coords[i][2]
        square[i].Color = color
        square[i].Thickness = thick
    end
end

local R15_BONES = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
}

local R6_BONES = {
    {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
    {"Torso", "Left Leg"}, {"Torso", "Right Leg"}
}

-- Фоновый цикл поиска кастомных NPC и нестандартных моделей
task.spawn(function()
    while ScreenGui.Parent do
        scanWorkspaceForEntities()
        task.wait(0.6)
    end
end)

RunService.RenderStepped:Connect(function()
    if Config.NoFog then
        Lighting.FogEnd = 9e9
        Lighting.FogStart = 9e9
        for _, v in pairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") then
                if not SavedLighting.Atmospheres[v] then
                    SavedLighting.Atmospheres[v] = {Density = v.Density, Haze = v.Haze, Glare = v.Glare}
                end
                v.Density = 0
                v.Haze = 0
                v.Glare = 0
            end
        end
    end

    local rainbow = Color3.fromHSV((tick() * Config.RainbowSpeed * 0.25) % 1, 1, 1)
    local myTeamName = getEntityTeamInfo(LocalPlayer.Character, LocalPlayer)
    local camPos = Camera.CFrame.Position

    -- Очистка устаревших моделей из кэша
    for model in pairs(Cache) do
        if not TrackedEntities[model] or not model:IsDescendantOf(workspace) then
            cleanEntity(model)
        end
    end

    for model, meta in pairs(TrackedEntities) do
        local rig = extractRigData(model)
        if Config.Enabled and rig then
            local distStuds = (camPos - rig.Root.Position).Magnitude
            local distMeters = math.floor(distStuds * 0.28)

            -- Игнорируем модели вплотную к камере (руки от 1-го лица) и за пределами лимита дистанции
            local validTarget = (distStuds > 2.2) and (distMeters <= Config.RenderDistance)

            if meta.IsNPC and not Config.ShowNPCs then
                validTarget = false
            end

            local entTeamName = getEntityTeamInfo(model, meta.Player)
            if Config.HideTeammates and myTeamName ~= nil and entTeamName == myTeamName then
                validTarget = false
            end
            if Config.SelectedTeamName ~= nil and entTeamName ~= Config.SelectedTeamName then
                validTarget = false
            end

            if validTarget then
                local _, rootOn = Camera:WorldToViewportPoint(rig.Root.Position)
                if rootOn then
                    if not Cache[model] then
                        local infoTxt = Drawing.new("Text")
                        infoTxt.Size = 13
                        infoTxt.Center = true
                        infoTxt.Outline = true
                        infoTxt.Color = Color3.fromRGB(240, 245, 255)

                        Cache[model] = {
                            Box = createSquare(),
                            MoveBox = createSquare(),
                            Skel = {},
                            HealthBg = Drawing.new("Line"),
                            HealthFill = Drawing.new("Line"),
                            InfoTag = infoTxt
                        }
                        for i = 1, 15 do table.insert(Cache[model].Skel, Drawing.new("Line")) end
                    end

                    local c = Cache[model]
                    local col = Config.Rainbow and rainbow or Config.BoxColor
                    local skelCol = Config.Rainbow and rainbow or Config.SkeletonColor

                    local topWorld = rig.Head.Position + Vector3.new(0, 0.75, 0)
                    local botWorld = rig.Root.Position - Vector3.new(0, 3.0, 0)
                    local top2D, tVis = Camera:WorldToViewportPoint(topWorld)
                    local bot2D, bVis = Camera:WorldToViewportPoint(botWorld)

                    if tVis and bVis then
                        local height = math.abs(bot2D.Y - top2D.Y)
                        local width = height * 0.62
                        local boxPos = Vector2.new(top2D.X - width / 2, top2D.Y)

                        -- 1. 2D Бокс
                        drawSquare(c.Box, boxPos, Vector2.new(width, height), col, Config.Thickness, Config.Box)

                        -- 2. Динамическая полоска ХП слева от бокса
                        if Config.HealthBar then
                            local hpPct = math.clamp(rig.Health / rig.MaxHealth, 0, 1)
                            local barX = boxPos.X - 5
                            c.HealthBg.Visible = true
                            c.HealthBg.From = Vector2.new(barX, boxPos.Y - 1)
                            c.HealthBg.To = Vector2.new(barX, boxPos.Y + height + 1)
                            c.HealthBg.Color = Color3.fromRGB(10, 10, 10)
                            c.HealthBg.Thickness = 4

                            c.HealthFill.Visible = true
                            c.HealthFill.From = Vector2.new(barX, boxPos.Y + height)
                            c.HealthFill.To = Vector2.new(barX, boxPos.Y + height - (height * hpPct))
                            c.HealthFill.Color = Color3.fromHSV(hpPct * 0.33, 0.9, 1)
                            c.HealthFill.Thickness = 2
                        else
                            c.HealthBg.Visible = false
                            c.HealthFill.Visible = false
                        end

                        -- 3. Подпись оружия в руках + Дистанция + метка [BOT]
                        if Config.WeaponTag then
                            local tagParts = {}
                            if meta.IsNPC then table.insert(tagParts, "[NPC]") end
                            if rig.Weapon then table.insert(tagParts, "[" .. rig.Weapon .. "]") end
                            table.insert(tagParts, distMeters .. "m")

                            c.InfoTag.Visible = true
                            c.InfoTag.Text = table.concat(tagParts, " ")
                            c.InfoTag.Position = Vector2.new(top2D.X, boxPos.Y + height + 3)
                        else
                            c.InfoTag.Visible = false
                        end
                    else
                        drawSquare(c.Box, Vector2.zero, Vector2.zero, col, 1, false)
                        c.HealthBg.Visible = false
                        c.HealthFill.Visible = false
                        c.InfoTag.Visible = false
                    end

                    -- 4. Универсальный скелет (R15 / R6 / Custom Rig)
                    if Config.Skeleton then
                        local isR15 = model:FindFirstChild("UpperTorso") ~= nil
                        local bones = isR15 and R15_BONES or R6_BONES
                        local idx = 1

                        for _, pair in ipairs(bones) do
                            local pA = model:FindFirstChild(pair[1])
                            local pB = model:FindFirstChild(pair[2])
                            local line = c.Skel[idx]
                            if pA and pB and pA:IsA("BasePart") and pB:IsA("BasePart") and line then
                                local a2D, aVis = Camera:WorldToViewportPoint(pA.Position)
                                local b2D, bVis = Camera:WorldToViewportPoint(pB.Position)
                                if aVis and bVis then
                                    line.Visible = true
                                    line.From = Vector2.new(a2D.X, a2D.Y)
                                    line.To = Vector2.new(b2D.X, b2D.Y)
                                    line.Color = skelCol
                                    line.Thickness = Config.Thickness
                                else
                                    line.Visible = false
                                end
                            elseif line then
                                line.Visible = false
                            end
                            idx = idx + 1
                        end

                        -- Если у кастомного NPC нестандартные имена костей — соединяем голову с центром тела
                        if idx == 1 or not c.Skel[1].Visible then
                            local a2D, aVis = Camera:WorldToViewportPoint(rig.Head.Position)
                            local b2D, bVis = Camera:WorldToViewportPoint(rig.Root.Position)
                            if aVis and bVis then
                                c.Skel[1].Visible = true
                                c.Skel[1].From = Vector2.new(a2D.X, a2D.Y)
                                c.Skel[1].To = Vector2.new(b2D.X, b2D.Y)
                                c.Skel[1].Color = skelCol
                                c.Skel[1].Thickness = Config.Thickness
                            end
                        end

                        for i = idx, #c.Skel do c.Skel[i].Visible = false end
                    else
                        for _, l in ipairs(c.Skel) do l.Visible = false end
                    end

                    -- 5. Маркер упреждения движения
                    if Config.MovementTracker then
                        local vel = rig.Root.AssemblyLinearVelocity
                        local flatVel = Vector3.new(vel.X, 0, vel.Z)
                        if flatVel.Magnitude > 1.5 then
                            local predWorld = (rig.Root.Position - Vector3.new(0, 2.9, 0)) + (flatVel * Config.PredictionTime)
                            local pred2D, pVis = Camera:WorldToViewportPoint(predWorld)
                            if pVis then
                                local sz = math.clamp(140 / pred2D.Z, 6, 16)
                                drawSquare(c.MoveBox, Vector2.new(pred2D.X - sz / 2, pred2D.Y - sz / 2), Vector2.new(sz, sz), Config.MovementColor, Config.Thickness, true)
                            else
                                drawSquare(c.MoveBox, Vector2.zero, Vector2.zero, Config.MovementColor, 1, false)
                            end
                        else
                            drawSquare(c.MoveBox, Vector2.zero, Vector2.zero, Config.MovementColor, 1, false)
                        end
                    else
                        drawSquare(c.MoveBox, Vector2.zero, Vector2.zero, Config.MovementColor, 1, false)
                    end
                else
                    cleanEntity(model)
                end
            else
                cleanEntity(model)
            end
        else
            cleanEntity(model)
        end
    end
end)
