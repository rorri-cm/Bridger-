--!native
--!optimize 2

-- ═══════════════════════════════════════════════════════════
-- BRIDGER: WESTERN — Full Automation Script (Matcha)
-- Drawing-based UI | [Z] Menu | [K] Fishing
-- APIs: iskeypressed, iskeydown, ismouse1pressed,
--       memory_read, Drawing.new, keypress/keyrelease,
--       fireproximityprompt, notify, RunService.RenderStepped
-- ═══════════════════════════════════════════════════════════

if not math.clamp then
    math.clamp = function(val, min, max)
        return math.min(math.max(val, min), max)
    end
end

-- ─── Services ───
local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local RS      = game:GetService("RunService")
local LP      = Players.LocalPlayer
local PG      = LP.PlayerGui
local Cam     = workspace.CurrentCamera
local LocalMouse = LP and LP:GetMouse() or nil

-- ─── State ───
local S = {
    fishingEnabled          = false,
    autoCorpseTPEnabled     = false,
    proximityEnabled        = false,
    proximityDistance        = 75,
    safePlaces              = {},
    autoPickupEnabled       = true,
    pickupRange             = 20,
    autoChestEnabled        = true,
    chestHoldTime           = 2.5,
    noclipEnabled           = false,
    horseTweenBypassEnabled = false,
    horseTweenSpeed         = 120,
    afterCorpseWaitMinutes  = 5,
}

local mashing, corpse, cDist, pNear, lastProxTp = false, nil, 0, false, 0
local bypassState = {
    stage = "idle", corpsePosition = nil, fishingPosition = nil,
    corpseFoundTime = 0, lastSafePlaceCheck = 0,
    occupiedSafePlaces = {}, proximityWaitStart = 0,
}

_G.fc, _G.ps = true, false
_G.sx, _G.sy, _G.sz = nil, nil, nil
_G.camCF = nil

local TXT_OFF = 0xDC0
local KM = {A=0x41,B=0x42,C=0x43,D=0x44,E=0x45,F=0x46,G=0x47,H=0x48,I=0x49,J=0x4A,K=0x4B,L=0x4C,M=0x4D,N=0x4E,O=0x4F,P=0x50,Q=0x51,R=0x52,S=0x53,T=0x54,U=0x55,V=0x56,W=0x57,X=0x58,Y=0x59,Z=0x5A}
local dynamiteEquipped = false
local autoCorpseRunning, bypassRunning = false, false
local pickedUpItems, processedChests = {}, {}
local noclipConn = nil

-- ─── HUD (forward declaration — populated later) ───
local hud = {}
local function uf()
    if not hud[1] then return end
    hud[1].Text = S.fishingEnabled and "Fishing: ON" or "Fishing: OFF"
    hud[1].Color = S.fishingEnabled and Color3.fromRGB(100,255,100) or Color3.fromRGB(255,100,100)
end

-- ═══════════════════════════════════════════════════════════
-- SAFE PLACES
-- ═══════════════════════════════════════════════════════════
local function saveSafePlaces()
    local data = ""
    for _, safe in pairs(S.safePlaces) do
        data = data .. safe.x .. "," .. safe.y .. "," .. safe.z .. "\n"
    end
    pcall(writefile, "fishing_safe_places.txt", data)
end

local function loadSafePlaces()
    local ok, data = pcall(readfile, "fishing_safe_places.txt")
    if not ok or not data then return end
    S.safePlaces = {}
    for line in data:gmatch("[^\n]+") do
        local coords = {}
        for num in line:gmatch("[^,]+") do table.insert(coords, tonumber(num)) end
        if #coords == 3 then table.insert(S.safePlaces, {x=coords[1], y=coords[2], z=coords[3]}) end
    end
    pcall(notify, "Loaded " .. #S.safePlaces .. " places", "Safe Places", 2)
end

-- ═══════════════════════════════════════════════════════════
-- POSITION HELPERS
-- ═══════════════════════════════════════════════════════════
local function gp(p)
    if not p then return nil, nil, nil end
    local ok, x = pcall(function() return p.Position.X end)
    local ok2, y = pcall(function() return p.Position.Y end)
    local ok3, z = pcall(function() return p.Position.Z end)
    return (ok and ok2 and ok3) and x, y, z or nil, nil, nil
end

local function gd(p)
    if not p then return 999999 end
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return 999999 end
    local px, py, pz = gp(h)
    local cx, cy, cz = gp(p)
    if not px or not cx then return 999999 end
    local dx, dy, dz = px-cx, py-cy, pz-cz
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function sp()
    if _G.ps then return end
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return end
    local ok1, x = pcall(function() return h.Position.X end)
    local ok2, y = pcall(function() return h.Position.Y end)
    local ok3, z = pcall(function() return h.Position.Z end)
    if ok1 and ok2 and ok3 then
        _G.sx, _G.sy, _G.sz = x, y, z
        _G.camCF = Cam.CFrame
        _G.ps = true
    end
end

local function rs()
    if not _G.ps then return end
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return end
    pcall(function()
        h.CFrame = CFrame.new(_G.sx, _G.sy, _G.sz)
        if _G.camCF then Cam.CFrame = _G.camCF end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- HORSE HELPERS
-- ═══════════════════════════════════════════════════════════
local function getHorseYoureOn()
    local char = LP.Character
    if not char then return nil end
    
    -- Game-specific value check
    local ridingHorse = char:FindFirstChild("RidingHorse")
    if ridingHorse and ridingHorse:IsA("ObjectValue") and ridingHorse.Value then
        return ridingHorse.Value
    end
    
    -- Native Roblox seated check
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart then
        local p = hum.SeatPart.Parent
        while p and p ~= workspace do
            if p:IsA("Model") then
                local n = p.Name:lower()
                if n:find("horse") or n:find("mule") or n:find("onyx") or n:find("silver") then
                    return p
                end
            end
            p = p.Parent
        end
    end
    
    return nil
end

local function isHorseNearby(maxDist)
    maxDist = maxDist or 100
    local char = LP.Character
    if not char then return false, nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false, nil end
    local riding = getHorseYoureOn()
    if riding then return true, riding end
    
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Model") then
            local n = obj.Name:lower()
            if n:find("horse") or n:find("mule") or n:find("onyx") or n:find("silver") then
                local owner = obj:FindFirstChild("Owner")
                if owner and owner:IsA("ObjectValue") and owner.Value == LP then
                    local hp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or obj.PrimaryPart
                    if not hp then
                        for _, c in pairs(obj:GetChildren()) do
                            if c:IsA("BasePart") then hp = c break end
                        end
                    end
                    if hp then
                        local dx = hp.Position.X - root.Position.X
                        local dy = hp.Position.Y - root.Position.Y
                        local dz = hp.Position.Z - root.Position.Z
                        if math.sqrt(dx*dx + dy*dy + dz*dz) <= maxDist then return true, obj end
                    end
                end
            end
        end
    end
    return false, nil
end

local function callHorse()
    keypress(0x48) task.wait(0.1) keyrelease(0x48) task.wait(5)
    local nearby = isHorseNearby(100)
    if nearby then return true end
    task.wait(5)
    return isHorseNearby(100)
end

local function mountHorse()
    keypress(0x4E) task.wait(4) keyrelease(0x4E) task.wait(1)
end

local function ensureOnHorse()
    local horse = getHorseYoureOn()
    if horse then return true end
    local nearby = isHorseNearby(100)
    if not nearby then
        local success = callHorse()
        if not success then return false end
    end
    mountHorse()
    return getHorseYoureOn() ~= nil
end

local function tweenHorse(horse, targetPos, speed)
    if not horse then return false end
    local horsePart = horse:FindFirstChild("HumanoidRootPart")
    if not horsePart then return false end
    local startPos = horsePart.Position
    local dx = targetPos.X - startPos.X
    local dy = targetPos.Y - startPos.Y
    local dz = targetPos.Z - startPos.Z
    local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
    local duration = distance / speed
    local startTime = tick()
    local endTime = startTime + duration
    while tick() < endTime do
        local alpha = math.min(1, (tick() - startTime) / duration)
        pcall(function()
            horsePart.CFrame = CFrame.new(startPos.X+(dx*alpha), startPos.Y+(dy*alpha), startPos.Z+(dz*alpha))
            horsePart.Velocity = Vector3.new(0, 0, 0)
            horsePart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        end)
        task.wait(0.03)
    end
    pcall(function()
        horsePart.CFrame = CFrame.new(targetPos)
        horsePart.Velocity = Vector3.new(0, 0, 0)
        horsePart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end)
    return true
end

local function horseTweenTo(targetPos)
    if not ensureOnHorse() then return false end
    local horse = getHorseYoureOn()
    if not horse then return false end
    return tweenHorse(horse, targetPos, S.horseTweenSpeed)
end

-- ═══════════════════════════════════════════════════════════
-- DOWNED / CORPSE HELPERS
-- ═══════════════════════════════════════════════════════════
local function isInDownedState()
    local char = LP.Character
    if not char then return false end
    local markers = {"Downed","IsDowned","Down","Ragdoll","Recovering","RecoveringLegs","DownedState","Incapacitated","Knocked","KnockedDown"}
    for _, marker in pairs(markers) do
        local attr = nil
        pcall(function() attr = char:GetAttribute(marker) end)
        if attr == true then return true end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        local h, mh = 0, 100
        pcall(function() h = hum.Health; mh = hum.MaxHealth end)
        if h > 0 and h <= mh * 0.25 then return true end
    end
    return false
end

local function teleportDowned(targetPos)
    if not isInDownedState() then return false end
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    pcall(function()
        root.CFrame = CFrame.new(targetPos)
        root.Velocity = Vector3.new(0, 0, 0)
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.RotVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end)
    return true
end

local function hasCorpsePart()
    local char = LP.Character
    if not char then return false end
    for _, obj in pairs(char:GetChildren()) do
        local has = false
        pcall(function()
            local n = obj.Name:lower()
            if n:find("corpse") or n:find("saint") or n:find("part") or n:find("body") then has = true end
        end)
        if has then return true end
    end
    local bp = LP.Backpack
    if bp then
        for _, obj in pairs(bp:GetChildren()) do
            local has = false
            pcall(function()
                local n = obj.Name:lower()
                if n:find("corpse") or n:find("saint") or n:find("part") then has = true end
            end)
            if has then return true end
        end
    end
    return false
end

-- ═══════════════════════════════════════════════════════════
-- SAFE PLACE ACTIONS
-- ═══════════════════════════════════════════════════════════
local function addSafe()
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return end
    local ok1, x = pcall(function() return h.Position.X end)
    local ok2, y = pcall(function() return h.Position.Y end)
    local ok3, z = pcall(function() return h.Position.Z end)
    if ok1 and ok2 and ok3 then
        table.insert(S.safePlaces, {x=x, y=y, z=z})
        saveSafePlaces()
        pcall(notify, "Added #" .. #S.safePlaces, "Safe Place", 2)
    end
end

local function clearSafes()
    S.safePlaces = {}
    saveSafePlaces()
    pcall(notify, "Cleared", "Safe Places", 2)
end

local function tpToSafe1()
    if #S.safePlaces == 0 then pcall(notify, "No safe places!", "Error", 2) return end
    task.spawn(function()
        local safe1 = S.safePlaces[1]
        horseTweenTo(Vector3.new(safe1.x, safe1.y, safe1.z))
    end)
end

local function tpToCorpse()
    if not corpse or cDist >= 999999 then pcall(notify, "No corpse!", "Error", 2) return end
    task.spawn(function()
        local x, y, z = gp(corpse)
        if not x then pcall(notify, "Invalid corpse!", "Error", 2) return end
        horseTweenTo(Vector3.new(x, y+5, z))
    end)
end

local function checkSafePlacesForPlayers()
    if tick() - bypassState.lastSafePlaceCheck < 10 then return end
    bypassState.lastSafePlaceCheck = tick()
    bypassState.occupiedSafePlaces = {}
    for idx, safePlace in pairs(S.safePlaces) do
        local safePos = Vector3.new(safePlace.x, safePlace.y, safePlace.z)
        for _, p in pairs(Players:GetChildren()) do
            if p ~= LP and p.Character then
                local th = p.Character:FindFirstChild("HumanoidRootPart")
                if th then
                    local dx = th.Position.X - safePos.X
                    local dy = th.Position.Y - safePos.Y
                    local dz = th.Position.Z - safePos.Z
                    if math.sqrt(dx*dx + dy*dy + dz*dz) <= S.proximityDistance then
                        bypassState.occupiedSafePlaces[idx] = true
                    end
                end
            end
        end
    end
end

local function findNearestSafeSafePlace()
    checkSafePlacesForPlayers()
    local nearestDist = math.huge
    local nearestSafe = nil
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return nil end
    for idx, safePlace in pairs(S.safePlaces) do
        if not bypassState.occupiedSafePlaces[idx] then
            local safePos = Vector3.new(safePlace.x, safePlace.y, safePlace.z)
            local dx = h.Position.X - safePos.X
            local dy = h.Position.Y - safePos.Y
            local dz = h.Position.Z - safePos.Z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist < nearestDist then nearestDist = dist; nearestSafe = safePlace end
        end
    end
    return nearestSafe
end

-- ═══════════════════════════════════════════════════════════
-- PROXIMITY CHECK
-- ═══════════════════════════════════════════════════════════
local function cp()
    if not S.proximityEnabled then pNear = false return end
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return end
    local mx, my, mz = gp(h)
    if not mx then return end
    pNear = false
    for _, p in pairs(Players:GetChildren()) do
        if p ~= LP and p.Character then
            local th = p.Character:FindFirstChild("HumanoidRootPart")
            if th then
                local tx, ty, tz = gp(th)
                if tx then
                    local dx, dy, dz = mx-tx, my-ty, mz-tz
                    if math.sqrt(dx*dx + dy*dy + dz*dz) <= S.proximityDistance then
                        pNear = true
                        if #S.safePlaces > 0 and tick() - lastProxTp > 10 then
                            task.spawn(function()
                                local wasFishing = S.fishingEnabled
                                if wasFishing then S.fishingEnabled = false; uf() end
                                local safe1 = S.safePlaces[1]
                                local s1Pos = Vector3.new(safe1.x, safe1.y, safe1.z)
                                local dxs = mx - s1Pos.X
                                local dys = my - s1Pos.Y
                                local dzs = mz - s1Pos.Z
                                local distToSafe1 = math.sqrt(dxs*dxs + dys*dys + dzs*dzs)
                                if distToSafe1 < 150 and #S.safePlaces >= 2 then
                                    local safe2 = S.safePlaces[2]
                                    horseTweenTo(Vector3.new(safe2.x, safe2.y, safe2.z))
                                    bypassState.proximityWaitStart = tick()
                                    while tick() - bypassState.proximityWaitStart < 120 do
                                        task.wait(1)
                                        if tick() - bypassState.proximityWaitStart >= 60 then
                                            local stillOccupied = false
                                            for _, p2 in pairs(Players:GetChildren()) do
                                                if p2 ~= LP and p2.Character then
                                                    local th2 = p2.Character:FindFirstChild("HumanoidRootPart")
                                                    if th2 then
                                                        local dx2 = s1Pos.X - th2.Position.X
                                                        local dy2 = s1Pos.Y - th2.Position.Y
                                                        local dz2 = s1Pos.Z - th2.Position.Z
                                                        if math.sqrt(dx2*dx2 + dy2*dy2 + dz2*dz2) <= S.proximityDistance then
                                                            stillOccupied = true; break
                                                        end
                                                    end
                                                end
                                            end
                                            if not stillOccupied then horseTweenTo(s1Pos); break end
                                        end
                                    end
                                else
                                    local safeSafe = findNearestSafeSafePlace()
                                    if safeSafe then horseTweenTo(Vector3.new(safeSafe.x, safeSafe.y, safeSafe.z)) end
                                end
                                if wasFishing then S.fishingEnabled = true; uf() end
                            end)
                            lastProxTp = tick()
                        end
                        break
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- PICKUP / CHEST
-- ═══════════════════════════════════════════════════════════
local function autoPickup()
    if not S.autoPickupEnabled then return end
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return end
    local hx, hy, hz = gp(h)
    if not hx then return end
    for _, obj in pairs(workspace:GetChildren()) do
        pcall(function()
            if obj:IsA("Model") or obj:IsA("Part") or obj:IsA("MeshPart") then
                local n = obj.Name:lower()
                if n:find("corpse") or n:find("saint") or n:find("part") or n:find("body") then
                    if not pickedUpItems[obj] then
                        local tp = nil
                        if obj:IsA("BasePart") then tp = obj
                        elseif obj:IsA("Model") then
                            tp = obj:FindFirstChild("HumanoidRootPart")
                            if not tp then
                                for _, c in pairs(obj:GetChildren()) do
                                    if c:IsA("BasePart") then tp = c; break end
                                end
                            end
                        end
                        if tp then
                            local ox, oy, oz = gp(tp)
                            if ox then
                                local dx, dy, dz = hx-ox, hy-oy, hz-oz
                                if math.sqrt(dx*dx + dy*dy + dz*dz) <= S.pickupRange then
                                    local prompt = obj:FindFirstChildOfClass("ProximityPrompt", true)
                                    if prompt then
                                        pcall(fireproximityprompt, prompt)
                                    else
                                        keypress(0x45) task.wait(1.5) keyrelease(0x45)
                                    end
                                    pickedUpItems[obj] = true
                                    task.delay(5, function() pickedUpItems[obj] = nil end)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end

local function kb()
    local c = LP.Character
    if not c then return false end
    return c:GetAttribute("IsRecoveringLegs") == true
end

local function ws()
    if not kb() then return end
    local to = tick() + 8
    while tick() < to do
        task.wait(0.1)
        if not kb() then return end
    end
end

local function findChest()
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return nil end
    local chests = workspace:FindFirstChild("Chests")
    if not chests then return nil end
    local lookDir = h.CFrame.LookVector
    local bestChest, bestScore = nil, -math.huge
    for _, chest in pairs(chests:GetChildren()) do
        if chest.Name == "ChestBox" then
            local chestBox = chest:FindFirstChild("ChestBox")
            if chestBox then
                local dx = chestBox.Position.X - h.Position.X
                local dy = chestBox.Position.Y - h.Position.Y
                local dz = chestBox.Position.Z - h.Position.Z
                local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                if dist <= 40 then
                    local dot = lookDir.X*(dx/dist) + lookDir.Y*(dy/dist) + lookDir.Z*(dz/dist)
                    local score = dot - (dist * 0.05)
                    if score > bestScore then bestScore = score; bestChest = chestBox end
                end
            end
        end
    end
    return bestChest
end

local function tpToChest()
    local chest = findChest()
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return end
    if chest then
        local offset = h.CFrame.LookVector * (-1.5)
        pcall(function()
            h.CFrame = CFrame.new(chest.Position.X + offset.X, chest.Position.Y, chest.Position.Z + offset.Z)
        end)
    else
        rs()
    end
end

local function pm()
    ws()
    task.wait(1)
    tpToChest()
    task.wait(0.5)
    if S.autoChestEnabled then
        keypress(0x45)
        task.wait(S.chestHoldTime)
        keyrelease(0x45)
        task.wait(0.5)
    end
end

-- ═══════════════════════════════════════════════════════════
-- QTE / FISHING
-- ═══════════════════════════════════════════════════════════
local MS = PG:WaitForChild("MashingSystem", 10)
local QS = PG:WaitForChild("QTESystem", 10)
local lbs = {}
if MS then for _, v in pairs(MS:GetDescendants()) do if v.ClassName == "TextLabel" then table.insert(lbs, v) end end end
if QS then for _, v in pairs(QS:GetDescendants()) do if v.ClassName == "TextLabel" then table.insert(lbs, v) end end end

local function gk()
    for _, l in pairs(lbs) do
        local ok, t = pcall(function() return memory_read("string", l.Address + TXT_OFF) end)
        if ok and t and #t == 1 and t ~= "Y" and t ~= "Z" then return t end
    end
end

local function fb()
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not h then return nil end
    local ok, hx = pcall(function() return h.Position.X end)
    local ok2, hy = pcall(function() return h.Position.Y end)
    local ok3, hz = pcall(function() return h.Position.Z end)
    if not (ok and ok2 and ok3) then return nil end
    for _, v in pairs(workspace:GetChildren()) do
        if v.ClassName == "Part" and v:FindFirstChild("WaterSplash") then
            local ok4, vx = pcall(function() return v.Position.X end)
            local ok5, vy = pcall(function() return v.Position.Y end)
            local ok6, vz = pcall(function() return v.Position.Z end)
            if ok4 and ok5 and ok6 then
                local dx, dy, dz = hx-vx, hy-vy, hz-vz
                if dx*dx + dy*dy + dz*dz < 2500 then return v end
            end
        end
    end
end

local function fca()
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    return h and h:FindFirstChild("FishCatch") ~= nil
end

local function fe()
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    return h and h:FindFirstChild("FishEscape") ~= nil
end

local function dm()
    mashing = true
    local et, lk, lpt = tick() + 10, nil, 0
    while tick() < et and not fca() and not fe() do
        task.wait(0.02)
        local k = gk()
        if k then
            local kc = KM[k]
            if kc and (k ~= lk or tick() - lpt > 0.15) then
                keypress(kc) task.wait(0.04) keyrelease(kc)
                lk, lpt = k, tick()
            end
        end
    end
    mashing = false
    if fca() then pm(); return true end
    return false
end

local function re()
    if not LP.Character then return false end
    for _, i in pairs(LP.Character:GetChildren()) do
        if i.Name == "FishingRod" then return true end
    end
    return false
end

local function wb()
    local bobber, timeout = nil, tick() + 10
    while tick() < timeout do
        task.wait(0.02)
        bobber = fb()
        if bobber then break end
    end
    if not bobber then return false end
    local biteTimeout = tick() + 60
    while tick() < biteTimeout do
        task.wait(0.02)
        if not S.fishingEnabled then return false end
        if not bobber.Parent then return false end
        if fe() then return false end
        if kb() then ws(); task.wait(0.3); rs(); return false end
        if bobber:FindFirstChild("FishBite") then
            mouse1click()
            local ct = tick() + 1
            while tick() < ct do
                task.wait(0.05)
                if fca() then return true end
            end
            dm()
            return true
        end
    end
    mouse1click()
    return false
end

-- ═══════════════════════════════════════════════════════════
-- NOCLIP
-- ═══════════════════════════════════════════════════════════
local function noclipOn()
    if noclipConn then return end
    noclipConn = RS.RenderStepped:Connect(function()
        pcall(function()
            local char = LP.Character
            if not char then return end
            for _, p in pairs(char:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
            end
        end)
    end)
    S.noclipEnabled = true
    pcall(notify, "Enabled", "Noclip", 2)
end

local function noclipOff()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    pcall(function()
        local char = LP.Character
        if char then
            for _, p in pairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
    end)
    S.noclipEnabled = false
    pcall(notify, "Disabled", "Noclip", 2)
end

-- ═══════════════════════════════════════════════════════════
-- CORPSE SCAN
-- ═══════════════════════════════════════════════════════════
local function sc()
    corpse, cDist = nil, 0
    local searchAreas = {workspace}
    local corpseFolder = workspace:FindFirstChild("Corpses") or workspace:FindFirstChild("Bodies")
    if corpseFolder then table.insert(searchAreas, corpseFolder) end
    for _, area in pairs(searchAreas) do
        pcall(function()
            for _, v in pairs(area:GetChildren()) do
                local ok, ic = pcall(function() return v:GetAttribute("IsCorpsePart") end)
                if ok and ic == true then
                    local dist = gd(v)
                    if dist < 999999 then corpse, cDist = v, dist; return end
                end
                pcall(function()
                    local name = tostring(v.Name):lower()
                    if name:find("corpse") or name:find("saint") or name:find("body") then
                        local dist = gd(v)
                        if dist < 999999 then corpse, cDist = v, dist end
                    end
                end)
                if corpse then return end
            end
        end)
        if corpse then return end
    end
end

-- ═══════════════════════════════════════════════════════════
-- DYNAMITE / AUTO CORPSE TP
-- ═══════════════════════════════════════════════════════════
local function throwDynamite()
    if not dynamiteEquipped then
        local char = LP.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local root = char.HumanoidRootPart
            Cam.CFrame = CFrame.new(Cam.CFrame.Position, root.Position + Vector3.new(0, -10, 0))
        end
        task.wait(0.3)
        keypress(0x37) task.wait(0.1) keyrelease(0x37) task.wait(0.3)
        dynamiteEquipped = true
    end
    local attempts = 0
    while not isInDownedState() and attempts < 25 do
        mouse2click() task.wait(0.1) attempts = attempts + 1
    end
    return isInDownedState()
end

local function checkPlayersNearCorpse(corpsePos)
    if not S.proximityEnabled then return false end
    for _, p in pairs(Players:GetChildren()) do
        if p ~= LP and p.Character then
            local th = p.Character:FindFirstChild("HumanoidRootPart")
            if th then
                local dx = th.Position.X - corpsePos.X
                local dy = th.Position.Y - corpsePos.Y
                local dz = th.Position.Z - corpsePos.Z
                if math.sqrt(dx*dx + dy*dy + dz*dz) <= S.proximityDistance then return true end
            end
        end
    end
    return false
end

local function runAutoCorpseTP()
    if autoCorpseRunning then return end
    autoCorpseRunning = true
    task.spawn(function()
        while S.autoCorpseTPEnabled do
            task.wait(1)
            if bypassState.stage == "idle" then
                sc()
                if corpse and cDist < 999999 then
                    local x, y, z = gp(corpse)
                    if x then
                        bypassState.corpsePosition = Vector3.new(x, y+5, z)
                        if checkPlayersNearCorpse(bypassState.corpsePosition) then
                            if #S.safePlaces > 0 then
                                S.fishingEnabled = false; uf()
                                local safe1 = S.safePlaces[1]
                                horseTweenTo(Vector3.new(safe1.x, safe1.y, safe1.z))
                                task.wait(5)
                                S.fishingEnabled = true; uf()
                            end
                            bypassState.stage = "idle"
                        else
                            local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                            if root then bypassState.fishingPosition = root.Position end
                            S.fishingEnabled = false; uf()
                            bypassState.stage = "stepping_back"
                        end
                    end
                end
            end
            if bypassState.stage == "stepping_back" then
                local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local backPos = root.Position - root.CFrame.LookVector * 5
                    pcall(function() root.CFrame = CFrame.new(backPos) end)
                end
                task.wait(1)
                bypassState.stage = "throwing"
            end
            if bypassState.stage == "throwing" then
                if throwDynamite() then bypassState.stage = "teleporting_to_corpse"
                else task.wait(2) end
            end
            if bypassState.stage == "teleporting_to_corpse" then
                if not isInDownedState() then bypassState.stage = "throwing"
                elseif bypassState.corpsePosition then
                    task.wait(0.5)
                    teleportDowned(bypassState.corpsePosition)
                    bypassState.stage = "waiting_getup"
                end
            end
            if bypassState.stage == "waiting_getup" then
                local ws2 = tick()
                while tick() - ws2 < 6 do task.wait(0.5); if not isInDownedState() then break end end
                bypassState.stage = "looting"
            end
            if bypassState.stage == "looting" then
                local ws2 = tick()
                while isInDownedState() and tick() - ws2 < 10 do task.wait(0.5) end
                if isInDownedState() then
                    bypassState.stage = "idle"; S.fishingEnabled = true; uf()
                else
                    local ls = tick()
                    local att = 0
                    while tick() - ls < 5 and att < 3 do autoPickup(); att = att + 1; task.wait(1) end
                    bypassState.stage = "waiting_for_horse"
                end
            end
            if bypassState.stage == "waiting_for_horse" then
                local nearby, _ = isHorseNearby(100)
                if not nearby then callHorse() end
                local ws2 = tick()
                while tick() - ws2 < 15 do
                    nearby, _ = isHorseNearby(100)
                    if nearby then bypassState.stage = "mounting_horse"; break end
                    task.wait(1)
                end
                if tick() - ws2 >= 15 then bypassState.stage = "mounting_horse" end
            end
            if bypassState.stage == "mounting_horse" then
                mountHorse() task.wait(2)
                bypassState.stage = "tweening_to_safe"
            end
            if bypassState.stage == "tweening_to_safe" then
                if #S.safePlaces > 0 then
                    local safe1 = S.safePlaces[1]
                    horseTweenTo(Vector3.new(safe1.x, safe1.y, safe1.z))
                    task.wait(5)
                end
                dynamiteEquipped = false
                bypassState.stage = "idle"
                S.fishingEnabled = true; uf()
            end
        end
        autoCorpseRunning = false
    end)
end

local function runHorseTweenBypass()
    if bypassRunning then return end
    bypassRunning = true
    task.spawn(function()
        while S.horseTweenBypassEnabled do
            task.wait(1)
            if bypassState.stage == "idle" then
                sc()
                if corpse and cDist > 200 and cDist < 999999 then
                    local x, y, z = gp(corpse)
                    if x then
                        bypassState.corpsePosition = Vector3.new(x, y+5, z)
                        bypassState.corpseFoundTime = tick()
                        if checkPlayersNearCorpse(bypassState.corpsePosition) then
                            if #S.safePlaces > 0 then
                                local safe1 = S.safePlaces[1]
                                horseTweenTo(Vector3.new(safe1.x, safe1.y, safe1.z))
                                task.wait(5)
                            end
                            bypassState.stage = "idle"
                        else
                            local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                            if root then bypassState.fishingPosition = root.Position end
                            S.fishingEnabled = false; uf()
                            bypassState.stage = "stepping_back"
                        end
                    end
                end
            end
            if bypassState.stage == "stepping_back" then
                local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if root then pcall(function() root.CFrame = CFrame.new(root.Position - root.CFrame.LookVector * 5) end) end
                task.wait(1); bypassState.stage = "throwing"
            end
            if bypassState.stage == "throwing" then
                if throwDynamite() then bypassState.stage = "teleporting_to_corpse"
                else task.wait(2) end
            end
            if bypassState.stage == "teleporting_to_corpse" then
                if not isInDownedState() then bypassState.stage = "throwing"
                elseif bypassState.corpsePosition then
                    task.wait(0.5); teleportDowned(bypassState.corpsePosition)
                    bypassState.stage = "waiting_getup"
                end
            end
            if bypassState.stage == "waiting_getup" then
                local ws2 = tick()
                while tick() - ws2 < 6 do task.wait(0.5); if not isInDownedState() then break end end
                bypassState.stage = "looting"
            end
            if bypassState.stage == "looting" then
                task.wait(2.5)
                local ls = tick()
                while tick() - ls < 3 do task.wait(0.5); autoPickup() end
                bypassState.stage = "waiting_for_horse"
            end
            if bypassState.stage == "waiting_for_horse" then
                local nearby, _ = isHorseNearby(100)
                if not nearby then callHorse() end
                local ws2 = tick()
                while tick() - ws2 < 15 do
                    nearby, _ = isHorseNearby(100)
                    if nearby then bypassState.stage = "mounting_horse"; break end
                    task.wait(1)
                end
                if tick() - ws2 >= 15 then bypassState.stage = "mounting_horse" end
            end
            if bypassState.stage == "mounting_horse" then
                mountHorse() task.wait(2); bypassState.stage = "tweening_to_safe"
            end
            if bypassState.stage == "tweening_to_safe" then
                local safeSafe = findNearestSafeSafePlace()
                if safeSafe then
                    horseTweenTo(Vector3.new(safeSafe.x, safeSafe.y, safeSafe.z))
                    task.wait(5)
                    if hasCorpsePart() then bypassState.stage = "waiting_at_safe"
                    else bypassState.stage = "idle"; S.fishingEnabled = true; uf() end
                else
                    task.wait(10)
                end
            end
            if bypassState.stage == "waiting_at_safe" then
                local elapsed = (tick() - bypassState.corpseFoundTime) / 60
                if elapsed >= S.afterCorpseWaitMinutes then bypassState.stage = "returning_to_safe1" end
            end
            if bypassState.stage == "returning_to_safe1" then
                if #S.safePlaces > 0 then
                    local safe1 = S.safePlaces[1]
                    horseTweenTo(Vector3.new(safe1.x, safe1.y, safe1.z))
                    task.wait(5)
                end
                bypassState.stage = "idle"; S.fishingEnabled = true; uf()
            end
        end
        bypassRunning = false
    end)
end

-- ═══════════════════════════════════════════════════════════
-- HUD STATUS TEXT (top-left overlay)
-- ═══════════════════════════════════════════════════════════
for i, v in ipairs({
    {10, 10,  "Fishing: OFF",       Color3.fromRGB(255, 100, 100)},
    {10, 26,  "Corpse: NONE",       Color3.fromRGB(255, 100, 100)},
    {10, 42,  "Proximity: OFF",     Color3.fromRGB(255, 100, 100)},
    {10, 58,  "Auto Corpse: OFF",   Color3.fromRGB(255, 100, 100)},
    {10, 74,  "Mount: ?",           Color3.fromRGB(255, 100, 100)},
    {10, 90,  "Bypass: OFF",        Color3.fromRGB(255, 100, 100)},
}) do
    hud[i] = Drawing.new("Text")
    hud[i].Size = 13
    hud[i].Position = Vector2.new(v[1], v[2])
    hud[i].Outline = true
    hud[i].Visible = true
    hud[i].Text = v[3]
    hud[i].Color = v[4]
end

local hudKey = Drawing.new("Text")
hudKey.Size = 12
hudKey.Position = Vector2.new(10, 108)
hudKey.Outline = true
hudKey.Visible = true
hudKey.Color = Color3.fromRGB(200, 200, 200)
hudKey.Text = "[Z] Menu | [K] Fishing"

-- ═══════════════════════════════════════════════════════════
-- DRAWING UI SYSTEM
-- ═══════════════════════════════════════════════════════════
local menuOpen = true
local selectedTab = 1
local lastToggleTick = 0
local lastFishToggleTick = 0
local lastMouseDown = false
local dragging = false
local dragOffX, dragOffY = 0, 0
local sliderDragging = false
local activeSlider = nil

-- ─── Theme ───
local C = {
    bg       = Color3.fromRGB(18, 19, 24),
    sidebar  = Color3.fromRGB(24, 26, 32),
    border   = Color3.fromRGB(45, 48, 56),
    header   = Color3.fromRGB(22, 23, 28),
    accent   = Color3.fromRGB(0, 140, 255),
    text     = Color3.fromRGB(230, 232, 238),
    subtext  = Color3.fromRGB(130, 134, 142),
    toggleOn = Color3.fromRGB(0, 140, 255),
    toggleOff= Color3.fromRGB(55, 58, 66),
    btnBg    = Color3.fromRGB(35, 37, 44),
    btnHover = Color3.fromRGB(50, 52, 60),
    sliderBg = Color3.fromRGB(40, 42, 50),
    tabHl    = Color3.fromRGB(0, 140, 255),
    tabSel   = Color3.fromRGB(255, 255, 255),
}

-- ─── Layout ───
local menuX, menuY = 160, 140
local menuW, menuH = 420, 380
local sidebarW = 125
local headerH = 32

local tabNames = {"FISHING", "CORPSE", "MOUNT", "SETTINGS"}

-- ─── Controls Definition ───
local controls = {
    -- Tab 1: Fishing
    {tab=1, type="toggle", label="Fishing [K]", key="fishingEnabled",
        callback=function(v) uf(); if v then _G.fc, _G.ps = true, false end end},
    {tab=1, type="toggle", label="Auto Chest", key="autoChestEnabled"},
    {tab=1, type="slider", label="Chest Hold (s)", key="chestHoldTime", min=1.0, max=5.0, step=0.1, fmt="%.1f"},

    -- Tab 2: Corpse
    {tab=2, type="toggle", label="Auto Corpse TP", key="autoCorpseTPEnabled"},
    {tab=2, type="button", label="TP TO CORPSE", action=tpToCorpse},

    -- Tab 3: Mount
    {tab=3, type="toggle", label="Mount Bypass", key="horseTweenBypassEnabled",
        callback=function(v) pcall(notify, v and "ENABLED!" or "Disabled", "BYPASS", v and 3 or 2) end},
    {tab=3, type="slider", label="Mount Speed", key="horseTweenSpeed", min=60, max=200, step=5},
    {tab=3, type="slider", label="Wait at Safe (min)", key="afterCorpseWaitMinutes", min=1, max=10, step=1},

    -- Tab 4: Settings
    {tab=4, type="toggle", label="Proximity Alert", key="proximityEnabled"},
    {tab=4, type="slider", label="Prox Distance", key="proximityDistance", min=25, max=150, step=5},
    {tab=4, type="toggle", label="Auto Pickup", key="autoPickupEnabled"},
    {tab=4, type="slider", label="Pickup Range", key="pickupRange", min=5, max=50, step=5},
    {tab=4, type="toggle", label="Noclip", key="noclipEnabled",
        callback=function(v) if v then noclipOn() else noclipOff() end end},
    {tab=4, type="button", label="ADD SAFE PLACE", action=addSafe},
    {tab=4, type="button", label="TP TO SAFE #1", action=tpToSafe1},
    {tab=4, type="button", label="CLEAR ALL SAFES", action=clearSafes},
}

-- ─── Create Shell Drawing Objects FIRST (bottom layer) ───
local shell = {}
shell.bgBorder   = Drawing.new("Square"); shell.bgBorder.Filled = false; shell.bgBorder.Visible = false
shell.bgFill     = Drawing.new("Square"); shell.bgFill.Filled = true; shell.bgFill.Visible = false
shell.sidebarFill = Drawing.new("Square"); shell.sidebarFill.Filled = true; shell.sidebarFill.Visible = false
shell.sidebarLine = Drawing.new("Line"); shell.sidebarLine.Thickness = 1; shell.sidebarLine.Visible = false
shell.headerText = Drawing.new("Text"); shell.headerText.Size = 14; shell.headerText.Outline = true; shell.headerText.Visible = false
shell.accentLine = Drawing.new("Line"); shell.accentLine.Thickness = 2; shell.accentLine.Visible = false
shell.tabHighlight = Drawing.new("Square"); shell.tabHighlight.Filled = true; shell.tabHighlight.Visible = false
shell.footerText = Drawing.new("Text"); shell.footerText.Size = 11; shell.footerText.Outline = true; shell.footerText.Visible = false
shell.tabLabels = {}
for i = 1, #tabNames do
    shell.tabLabels[i] = Drawing.new("Text"); shell.tabLabels[i].Size = 13; shell.tabLabels[i].Outline = true; shell.tabLabels[i].Visible = false
end

-- ─── Create Drawing Objects for Controls AFTER shell (top layer) ───
for _, ctrl in ipairs(controls) do
    if ctrl.type == "toggle" then
        ctrl._border = Drawing.new("Square"); ctrl._border.Filled = false; ctrl._border.Visible = false
        ctrl._fill   = Drawing.new("Square"); ctrl._fill.Filled = true; ctrl._fill.Visible = false
        ctrl._label_d = Drawing.new("Text"); ctrl._label_d.Size = 13; ctrl._label_d.Outline = true; ctrl._label_d.Visible = false
    elseif ctrl.type == "slider" then
        ctrl._label_d = Drawing.new("Text"); ctrl._label_d.Size = 13; ctrl._label_d.Outline = true; ctrl._label_d.Visible = false
        ctrl._track  = Drawing.new("Square"); ctrl._track.Filled = true; ctrl._track.Visible = false
        ctrl._sfill  = Drawing.new("Square"); ctrl._sfill.Filled = true; ctrl._sfill.Visible = false
        ctrl._value_d = Drawing.new("Text"); ctrl._value_d.Size = 12; ctrl._value_d.Outline = true; ctrl._value_d.Visible = false
    elseif ctrl.type == "button" then
        ctrl._bg     = Drawing.new("Square"); ctrl._bg.Filled = true; ctrl._bg.Visible = false
        ctrl._label_d = Drawing.new("Text"); ctrl._label_d.Size = 13; ctrl._label_d.Outline = true; ctrl._label_d.Center = true; ctrl._label_d.Visible = false
    end
end

-- ─── Input Helpers ───
local function getMousePos()
    local ok, pos = pcall(function() return UIS:GetMouseLocation() end)
    if ok and pos then return pos end
    if LocalMouse then return Vector2.new(LocalMouse.X or 0, LocalMouse.Y or 0) end
    return Vector2.new(0, 0)
end

local function isMousePressed()
    if type(ismouse1pressed) == "function" then
        local ok, result = pcall(ismouse1pressed)
        if ok then return result == true end
    end
    return false
end

local function isMouseInRect(rx, ry, rw, rh)
    local m = getMousePos()
    return m.X >= rx and m.X <= rx + rw and m.Y >= ry and m.Y <= ry + rh
end

-- ─── Hide Helpers ───
local function hideControl(ctrl)
    if ctrl.type == "toggle" then
        ctrl._border.Visible = false; ctrl._fill.Visible = false; ctrl._label_d.Visible = false
    elseif ctrl.type == "slider" then
        ctrl._label_d.Visible = false; ctrl._track.Visible = false; ctrl._sfill.Visible = false; ctrl._value_d.Visible = false
    elseif ctrl.type == "button" then
        ctrl._bg.Visible = false; ctrl._label_d.Visible = false
    end
end

local function hideShell()
    shell.bgBorder.Visible = false; shell.bgFill.Visible = false
    shell.sidebarFill.Visible = false; shell.sidebarLine.Visible = false
    shell.headerText.Visible = false; shell.accentLine.Visible = false
    shell.tabHighlight.Visible = false; shell.footerText.Visible = false
    for i = 1, #tabNames do shell.tabLabels[i].Visible = false end
end

-- ─── Render Functions ───
local function renderShell()
    shell.bgBorder.Position = Vector2.new(menuX - 1, menuY - 1)
    shell.bgBorder.Size = Vector2.new(menuW + 2, menuH + 2)
    shell.bgBorder.Color = C.accent
    shell.bgBorder.Visible = true

    shell.bgFill.Position = Vector2.new(menuX, menuY)
    shell.bgFill.Size = Vector2.new(menuW, menuH)
    shell.bgFill.Color = C.bg
    shell.bgFill.Visible = true

    shell.sidebarFill.Position = Vector2.new(menuX + 1, menuY + 1)
    shell.sidebarFill.Size = Vector2.new(sidebarW - 1, menuH - 2)
    shell.sidebarFill.Color = C.sidebar
    shell.sidebarFill.Visible = true

    shell.sidebarLine.From = Vector2.new(menuX + sidebarW, menuY + 2)
    shell.sidebarLine.To = Vector2.new(menuX + sidebarW, menuY + menuH - 2)
    shell.sidebarLine.Color = C.border
    shell.sidebarLine.Visible = true

    shell.headerText.Position = Vector2.new(menuX + 14, menuY + 9)
    shell.headerText.Text = "BRIDGER: WESTERN"
    shell.headerText.Color = C.text
    shell.headerText.Visible = true

    shell.accentLine.From = Vector2.new(menuX, menuY + headerH)
    shell.accentLine.To = Vector2.new(menuX + menuW, menuY + headerH)
    shell.accentLine.Color = C.accent
    shell.accentLine.Visible = true

    for i = 1, #tabNames do
        local tabY = menuY + headerH + 16 + (i - 1) * 32
        if i == selectedTab then
            shell.tabHighlight.Position = Vector2.new(menuX + 8, tabY)
            shell.tabHighlight.Size = Vector2.new(sidebarW - 16, 26)
            shell.tabHighlight.Color = C.tabHl
            shell.tabHighlight.Visible = true
        end
        shell.tabLabels[i].Position = Vector2.new(menuX + 20, tabY + 6)
        shell.tabLabels[i].Text = tabNames[i]
        shell.tabLabels[i].Color = (i == selectedTab) and C.tabSel or C.subtext
        shell.tabLabels[i].Visible = true
    end

    shell.footerText.Position = Vector2.new(menuX + sidebarW + 14, menuY + menuH - 18)
    shell.footerText.Text = "[Z] Toggle | [K] Fishing"
    shell.footerText.Color = C.subtext
    shell.footerText.Visible = true
end

local function renderToggle(ctrl, x, y, w)
    local val = S[ctrl.key]
    local ts = 14
    ctrl._border.Position = Vector2.new(x, y + 4)
    ctrl._border.Size = Vector2.new(ts, ts)
    ctrl._border.Color = C.border
    ctrl._border.Visible = true

    ctrl._fill.Position = Vector2.new(x + 2, y + 6)
    ctrl._fill.Size = Vector2.new(ts - 4, ts - 4)
    ctrl._fill.Color = val and C.toggleOn or C.toggleOff
    ctrl._fill.Visible = true

    ctrl._label_d.Position = Vector2.new(x + ts + 8, y + 4)
    ctrl._label_d.Text = ctrl.label .. ": " .. (val and "ON" or "OFF")
    ctrl._label_d.Color = val and C.text or C.subtext
    ctrl._label_d.Visible = true
end

local function renderSlider(ctrl, x, y, w)
    local val = S[ctrl.key]
    local fmt = ctrl.fmt or "%d"
    ctrl._label_d.Position = Vector2.new(x, y)
    ctrl._label_d.Text = ctrl.label
    ctrl._label_d.Color = C.text
    ctrl._label_d.Visible = true

    local trackX = x + 4
    local trackW = w - 55
    local trackY = y + 20
    local trackH = 6

    ctrl._trackX = trackX
    ctrl._trackW = trackW
    ctrl._trackY = trackY

    ctrl._track.Position = Vector2.new(trackX, trackY)
    ctrl._track.Size = Vector2.new(trackW, trackH)
    ctrl._track.Color = C.sliderBg
    ctrl._track.Visible = true

    local pct = math.clamp((val - ctrl.min) / (ctrl.max - ctrl.min), 0, 1)
    local fillW = math.max(1, pct * trackW)
    ctrl._sfill.Position = Vector2.new(trackX, trackY)
    ctrl._sfill.Size = Vector2.new(fillW, trackH)
    ctrl._sfill.Color = C.accent
    ctrl._sfill.Visible = true

    ctrl._value_d.Position = Vector2.new(trackX + trackW + 8, trackY - 3)
    ctrl._value_d.Text = string.format(fmt, val)
    ctrl._value_d.Color = C.text
    ctrl._value_d.Visible = true
end

local function renderButton(ctrl, x, y, w, mp)
    local bh = 28
    local hovering = isMouseInRect(x, y, w, bh)
    ctrl._bg.Position = Vector2.new(x, y)
    ctrl._bg.Size = Vector2.new(w, bh)
    ctrl._bg.Color = hovering and C.btnHover or C.btnBg
    ctrl._bg.Visible = true

    ctrl._label_d.Position = Vector2.new(x + w / 2, y + 8)
    ctrl._label_d.Text = ctrl.label
    ctrl._label_d.Color = C.text
    ctrl._label_d.Visible = true
end

-- ─── Main Render ───
local function renderMenu()
    if not menuOpen then
        hideShell()
        for _, ctrl in ipairs(controls) do hideControl(ctrl) end
        return
    end

    local mouseDown = isMousePressed()
    local clicked = mouseDown and not lastMouseDown
    local mp = getMousePos()

    -- Handle active drags
    if dragging then
        if mouseDown then
            menuX = mp.X - dragOffX
            menuY = mp.Y - dragOffY
        else
            dragging = false
        end
    end

    if sliderDragging and activeSlider then
        if mouseDown then
            local pct = math.clamp((mp.X - activeSlider._trackX) / activeSlider._trackW, 0, 1)
            local range = activeSlider.max - activeSlider.min
            local raw = activeSlider.min + range * pct
            local stepped = activeSlider.min + math.floor((raw - activeSlider.min) / activeSlider.step + 0.5) * activeSlider.step
            S[activeSlider.key] = math.clamp(stepped, activeSlider.min, activeSlider.max)
        else
            sliderDragging = false
            activeSlider = nil
        end
    end

    -- Render shell
    renderShell()

    -- Content area
    local cx = menuX + sidebarW + 14
    local cy = menuY + headerH + 14
    local cw = menuW - sidebarW - 28
    local clickConsumed = false

    -- Render controls for selected tab
    for _, ctrl in ipairs(controls) do
        if ctrl.tab == selectedTab then
            if ctrl.type == "toggle" then
                renderToggle(ctrl, cx, cy, cw)
                if clicked and not clickConsumed and isMouseInRect(cx, cy, cw, 24) then
                    S[ctrl.key] = not S[ctrl.key]
                    if ctrl.callback then ctrl.callback(S[ctrl.key]) end
                    clickConsumed = true
                end
                cy = cy + 30
            elseif ctrl.type == "slider" then
                renderSlider(ctrl, cx, cy, cw)
                if clicked and not clickConsumed and ctrl._trackX then
                    if isMouseInRect(ctrl._trackX - 4, ctrl._trackY - 4, ctrl._trackW + 8, 14) then
                        sliderDragging = true
                        activeSlider = ctrl
                        local pct = math.clamp((mp.X - ctrl._trackX) / ctrl._trackW, 0, 1)
                        local range = ctrl.max - ctrl.min
                        local raw = ctrl.min + range * pct
                        local stepped = ctrl.min + math.floor((raw - ctrl.min) / ctrl.step + 0.5) * ctrl.step
                        S[ctrl.key] = math.clamp(stepped, ctrl.min, ctrl.max)
                        clickConsumed = true
                    end
                end
                cy = cy + 38
            elseif ctrl.type == "button" then
                renderButton(ctrl, cx, cy, cw, mp)
                if clicked and not clickConsumed and isMouseInRect(cx, cy, cw, 28) then
                    if ctrl.action then ctrl.action() end
                    ctrl._bg.Color = C.accent
                    clickConsumed = true
                end
                cy = cy + 34
            end
        else
            hideControl(ctrl)
        end
    end

    -- Tab clicks
    if clicked and not clickConsumed then
        for i = 1, #tabNames do
            local tabY = menuY + headerH + 16 + (i - 1) * 32
            if isMouseInRect(menuX + 8, tabY, sidebarW - 16, 26) then
                selectedTab = i
                clickConsumed = true
                break
            end
        end
    end

    -- Header drag
    if clicked and not clickConsumed and not sliderDragging then
        if isMouseInRect(menuX, menuY, menuW, headerH) then
            dragging = true
            dragOffX = mp.X - menuX
            dragOffY = mp.Y - menuY
        end
    end

    lastMouseDown = mouseDown
end

-- ═══════════════════════════════════════════════════════════
-- BACKGROUND GAME LOOPS
-- ═══════════════════════════════════════════════════════════

-- Auto corpse + bypass monitor
task.spawn(function()
    while true do
        task.wait(1)
        if S.autoCorpseTPEnabled and not autoCorpseRunning then runAutoCorpseTP() end
        if S.horseTweenBypassEnabled and not bypassRunning then runHorseTweenBypass() end
    end
end)

-- Mount status
task.spawn(function()
    while true do
        task.wait(1)
        if hud[5] then
            local horse = getHorseYoureOn()
            local nearby = isHorseNearby(100)
            if horse then
                hud[5].Text = "Mount: RIDING"; hud[5].Color = Color3.fromRGB(100, 255, 100)
            elseif nearby then
                hud[5].Text = "Mount: NEARBY"; hud[5].Color = Color3.fromRGB(255, 255, 100)
            else
                hud[5].Text = "Mount: FAR"; hud[5].Color = Color3.fromRGB(255, 100, 100)
            end
        end
    end
end)

-- Corpse scan + proximity + HUD update
task.spawn(function()
    while true do
        task.wait(2)
        sc()
        cp()
        if hud[2] then
            if corpse and cDist < 999999 then
                hud[2].Text = string.format("Corpse: %.0f studs", cDist)
                hud[2].Color = Color3.fromRGB(100, 255, 100)
            else
                hud[2].Text = "Corpse: NONE"
                hud[2].Color = Color3.fromRGB(255, 100, 100)
            end
        end
        if hud[3] then
            if S.proximityEnabled then
                hud[3].Text = pNear and "Proximity: NEARBY!" or "Proximity: Clear"
                hud[3].Color = pNear and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(100, 255, 100)
            else
                hud[3].Text = "Proximity: OFF"
                hud[3].Color = Color3.fromRGB(255, 100, 100)
            end
        end
        if hud[4] then
            hud[4].Text = "Auto Corpse: " .. (S.autoCorpseTPEnabled and "ON (" .. bypassState.stage .. ")" or "OFF")
            hud[4].Color = S.autoCorpseTPEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
        end
        if hud[6] then
            hud[6].Text = "Bypass: " .. (S.horseTweenBypassEnabled and "ON (" .. bypassState.stage .. ")" or "OFF")
            hud[6].Color = S.horseTweenBypassEnabled and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
        end
    end
end)

-- Auto pickup
task.spawn(function()
    while true do task.wait(1.5); autoPickup() end
end)

-- Fishing loop
task.spawn(function()
    while true do
        task.wait(0.1)
        if not S.fishingEnabled then
            task.wait(0.5)
        else
            pcall(function()
                task.wait(0.3)
                if kb() then ws(); task.wait(0.3); rs(); task.wait(1); return end
                if fb() then wb(); task.wait(2); return end
                if _G.fc then sp(); _G.fc = false end
                keypress(0x36) task.wait(0.15) keyrelease(0x36)
                task.wait(0.3)
                mouse1click()
                task.wait(0.4)
                keypress(0x39) task.wait(0.15) keyrelease(0x39)
                task.wait(0.6)
                if not re() then task.wait(2); return end
                mouse1click()
                task.wait(1.2)
                wb()
                task.wait(2)
            end)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
-- MAIN RENDER LOOP
-- ═══════════════════════════════════════════════════════════
loadSafePlaces()

RS.RenderStepped:Connect(function(dt)
    -- Z key: toggle menu
    if type(iskeypressed) == "function" then
        local now = tick()
        if now - lastToggleTick >= 0.2 then
            local ok, pressed = pcall(iskeypressed, 0x5A)
            if ok and pressed then
                menuOpen = not menuOpen
                lastToggleTick = now
            end
        end
    end

    -- K key: toggle fishing
    if type(iskeypressed) == "function" and not mashing then
        local now = tick()
        if now - lastFishToggleTick >= 0.2 then
            local ok, pressed = pcall(iskeypressed, 0x4B)
            if ok and pressed then
                S.fishingEnabled = not S.fishingEnabled
                uf()
                if S.fishingEnabled then _G.fc, _G.ps = true, false end
                lastFishToggleTick = now
                pcall(notify, S.fishingEnabled and "Fishing ON" or "Fishing OFF", "Auto Fishing", 2)
            end
        end
    end

    renderMenu()
end)

print("=== BRIDGER: WESTERN LOADED ===")
print("[Z] Toggle Menu | [K] Toggle Fishing")
pcall(notify, "LOADED — [Z] Menu | [K] Fishing", "Bridger", 3)
