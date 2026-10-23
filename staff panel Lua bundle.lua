-- b16_staff_panel.lua  v1.0
-- Staff utilities for the better16 web client, ported from Sans's
-- Infinite Yield fork feature list and rewritten against 2016-client
-- APIs (the fork's code targets modern Roblox: task.*, PivotTo,
-- GetPivot, RequestStreamAroundAsync -- none of which exist in 2016).
-- Client-side only: every feature acts on the LOCAL player's own
-- character, camera, or lighting. Nothing here calls
-- LogService:ExecuteScript or touches another player's state.
--
-- Entry point for the panel buttons (one line, via local console):
--   B16('fly')            B16('speed', 32)      B16('goto', 'Name')
--   B16('view', 'Name')   B16('chat', 'hello')  B16('chatlog')
--
-- Features: fly (+up/down), speed, jpower, infjump, fullbright,
-- noclip, float, freecam, view/unview, goto, walkto/stop,
-- setwaypoint/waypoint, chat (say), chatlog (minimal, native).
-- NOT included: dex explorer / audiologger -- in the fork those are
-- one-line loadstring stubs that download unreviewed third-party
-- code at runtime; there is no local code to port.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UIS = game:GetService('UserInputService')
local Lighting = game:GetService('Lighting')
local speaker = Players.LocalPlayer

local function root()
	local c = speaker.Character
	return c and c:FindFirstChild('HumanoidRootPart')
end
local function hum()
	local c = speaker.Character
	return c and c:FindFirstChildOfClass('Humanoid')
end
local function findPlayer(name)
	if not name then return nil end
	name = tostring(name):lower()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower() == name or p.Name:lower():sub(1, #name) == name then
			return p
		end
	end
	return nil
end
local function notify(msg) print('[b16staff] ' .. tostring(msg)) end

local S = {
	fly = false, flyUp = false, flyDown = false, flySpeed = 2,
	noclip = false, float = false, infjump = false,
	freecam = false, bright = false, walking = false,
	wp = nil, chatlog = {},
}
local conns = {}
local function on(key, conn) if conns[key] then conns[key]:Disconnect() end conns[key] = conn end
local function off(key) if conns[key] then conns[key]:Disconnect() conns[key] = nil end end

-- ===== fly (BodyVelocity/BodyGyro, camera-relative, MoveDirection driven)
local flyBV, flyBG
local function flyStart()
	local hrp = root() if not hrp then return end
	flyStop()
	S.fly = true
	flyBG = Instance.new('BodyGyro', hrp)
	flyBG.P = 9e4 flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	flyBV = Instance.new('BodyVelocity', hrp)
	flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	on('fly', RunService.RenderStepped:Connect(function()
		local h, r = hum(), root()
		if not S.fly or not h or not r or not flyBV or not flyBG then return end
		local cam = workspace.CurrentCamera
		flyBG.CFrame = cam.CFrame
		-- MoveDirection is already the camera-relative world direction
		-- the control module computed from the player's input.
		local md = h.MoveDirection
		local y = 0
		if S.flyUp then y = 24 * S.flySpeed end
		if S.flyDown then y = -24 * S.flySpeed end
		local v = md * (16 * S.flySpeed)
		flyBV.Velocity = Vector3.new(v.X, y, v.Z)
	end))
	notify('fly on')
end
function flyStop()
	S.fly = false off('fly')
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
end

-- ===== noclip
local function noclipSet(enabled)
	S.noclip = enabled
	if enabled then
		on('noclip', RunService.Stepped:Connect(function()
			local c = speaker.Character
			if c then
				for _, p in ipairs(c:GetDescendants()) do
					if p:IsA('BasePart') then p.CanCollide = false end
				end
			end
		end))
	else
		off('noclip')
		local c = speaker.Character
		if c then
			for _, p in ipairs(c:GetDescendants()) do
				if p:IsA('BasePart') then p.CanCollide = true end
			end
		end
	end
	notify('noclip ' .. (enabled and 'on' or 'off'))
end

-- ===== float (invisible pad under the character)
local floatPad
local function floatSet(enabled)
	S.float = enabled
	if enabled then
		floatPad = Instance.new('Part', workspace)
		floatPad.Name = 'b16float' floatPad.Anchored = true
		floatPad.CanCollide = true floatPad.Transparency = 1
		floatPad.Size = Vector3.new(6, 1, 6)
		on('float', RunService.RenderStepped:Connect(function()
			local r = root()
			if r and floatPad then
				floatPad.CFrame = CFrame.new(r.Position - Vector3.new(0, 3.6, 0))
			end
		end))
	else
		off('float')
		if floatPad then floatPad:Destroy() floatPad = nil end
	end
	notify('float ' .. (enabled and 'on' or 'off'))
end

-- ===== freecam (Scriptable camera; look = mouse movement, move = MoveDirection + up/down flags)
local fcYaw, fcPitch, fcPos
local function freecamSet(enabled)
	local cam = workspace.CurrentCamera
	S.freecam = enabled
	if enabled then
		fcPos = cam.CFrame.Position
		local rx, ry = cam.CFrame:ToEulerAnglesXYZ()
		fcPitch, fcYaw = rx, ry
		cam.CameraType = Enum.CameraType.Scriptable
		on('fcInput', UIS.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				fcYaw = fcYaw - input.Delta.X * 0.003
				fcPitch = math.clamp(fcPitch - input.Delta.Y * 0.003, -1.5, 1.5)
			end
		end))
		on('fcStep', RunService.RenderStepped:Connect(function()
			local cf = CFrame.new(fcPos) * CFrame.Angles(fcPitch, fcYaw, 0)
			local h = hum()
			local md = h and h.MoveDirection or Vector3.new()
			local sp = 40
			local move = (cf.LookVector * -md.Z + cf.RightVector * md.X) * sp * 0.016
			if S.flyUp then move = move + Vector3.new(0, sp * 0.016, 0) end
			if S.flyDown then move = move - Vector3.new(0, sp * 0.016, 0) end
			fcPos = fcPos + move
			cam.CFrame = CFrame.new(fcPos) * CFrame.Angles(fcPitch, fcYaw, 0)
		end))
	else
		off('fcInput') off('fcStep')
		cam.CameraType = Enum.CameraType.Custom
		local h = hum() if h then cam.CameraSubject = h end
	end
	notify('freecam ' .. (enabled and 'on' or 'off'))
end

-- ===== fullbright (stores and restores Lighting)
local savedLighting
local function brightSet(enabled)
	S.bright = enabled
	if enabled then
		savedLighting = { Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd, ClockTime = Lighting.ClockTime }
		Lighting.Brightness = 2 Lighting.Ambient = Color3.new(1, 1, 1)
		Lighting.OutdoorAmbient = Color3.new(1, 1, 1) Lighting.FogEnd = 100000
	else
		if savedLighting then
			for k, v in pairs(savedLighting) do Lighting[k] = v end
			savedLighting = nil
		end
	end
	notify('fullbright ' .. (enabled and 'on' or 'off'))
end

-- ===== view / goto / walkto (self movement and camera only)
local function viewPlayer(name)
	local p = findPlayer(name)
	local cam = workspace.CurrentCamera
	if p and p.Character and p.Character:FindFirstChildOfClass('Humanoid') then
		cam.CameraSubject = p.Character:FindFirstChildOfClass('Humanoid')
		notify('viewing ' .. p.Name)
	else
		notify('view: player not found')
	end
end
local function unview()
	local cam = workspace.CurrentCamera
	local h = hum() if h then cam.CameraSubject = h end
	notify('view reset')
end
local function gotoPlayer(name)
	local p = findPlayer(name)
	local r = root()
	if p and p.Character and p.Character:FindFirstChild('HumanoidRootPart') and r then
		local t = p.Character.HumanoidRootPart
		r.CFrame = t.CFrame * CFrame.new(0, 0, 3)
		notify('goto ' .. p.Name)
	else
		notify('goto: target unavailable')
	end
end
local function walktoPlayer(name)
	local p = findPlayer(name)
	if not (p and p.Character) then notify('walkto: player not found') return end
	S.walking = true
	spawn(function()
		while S.walking do
			local h, tc = hum(), p.Character
			if not h or not tc or not tc:FindFirstChild('HumanoidRootPart') then break end
			h:MoveTo(tc.HumanoidRootPart.Position)
			wait(0.4)
		end
	end)
	notify('walking to ' .. p.Name)
end

-- ===== chat logger (native, minimal: records chat you can already see)
local function hookChat(p)
	on('chat_' .. p.Name, p.Chatted:Connect(function(msg)
		table.insert(S.chatlog, string.format('[%s] %s: %s', os.date('%H:%M:%S'), p.Name, msg))
		while #S.chatlog > 100 do table.remove(S.chatlog, 1) end
	end))
end
for _, p in ipairs(Players:GetPlayers()) do hookChat(p) end
on('chatJoin', Players.PlayerAdded:Connect(hookChat))

-- ===== dispatcher: B16('cmd', arg) — one line per panel button
local cmds = {}
cmds.fly = function() if S.fly then flyStop() notify('fly off') else flyStart() end end
cmds.flyup = function(a) S.flyUp = (a == 1 or a == '1' or a == nil) if a == 0 or a == '0' then S.flyUp = false end end
cmds.flydown = function(a) S.flyDown = (a == 1 or a == '1' or a == nil) if a == 0 or a == '0' then S.flyDown = false end end
cmds.flyspeed = function(a) S.flySpeed = tonumber(a) or 2 notify('fly speed ' .. S.flySpeed) end
cmds.noclip = function() noclipSet(not S.noclip) end
cmds.float = function() floatSet(not S.float) end
cmds.freecam = function() freecamSet(not S.freecam) end
cmds.fullbright = function() brightSet(not S.bright) end
cmds.speed = function(a) local h = hum() if h then h.WalkSpeed = tonumber(a) or 16 end end
cmds.jpower = function(a) local h = hum() if h then h.JumpPower = tonumber(a) or 50 end end
cmds.infjump = function()
	S.infjump = not S.infjump
	if S.infjump then
		on('infjump', UIS.JumpRequest:Connect(function()
			local h = hum() if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
		end))
	else off('infjump') end
	notify('infjump ' .. (S.infjump and 'on' or 'off'))
end
cmds.view = viewPlayer
cmds.unview = unview
cmds['goto'] = gotoPlayer
cmds.walkto = walktoPlayer
cmds.stopwalk = function() S.walking = false end
cmds.setwaypoint = function() local r = root() if r then S.wp = r.CFrame notify('waypoint set') end end
cmds.waypoint = function() local r = root() if r and S.wp then r.CFrame = S.wp notify('at waypoint') end end
cmds.chat = function(a)
	-- 2016-era chat: bubble over your own character via the Chat service.
	local c = speaker.Character
	if c and c:FindFirstChild('Head') then
		pcall(function()
			game:GetService('Chat'):Chat(c.Head, tostring(a), Enum.ChatColor.White)
		end)
	end
end
cmds.chatlog = function()
	for _, line in ipairs(S.chatlog) do print(line) end
	notify(#S.chatlog .. ' lines (printed above)')
end
cmds.stopall = function()
	flyStop() noclipSet(false) floatSet(false)
	if S.freecam then freecamSet(false) end
	S.walking = false
	notify('all staff features off')
end

function B16(cmd, a)
	local f = cmds[tostring(cmd):lower()]
	if f then
		local ok, err = pcall(f, a)
		if not ok then notify('error in ' .. tostring(cmd) .. ': ' .. tostring(err)) end
	else
		notify('unknown command: ' .. tostring(cmd))
	end
end

speaker.CharacterAdded:Connect(function()
	flyStop() off('noclip') off('float') S.walking = false
end)

notify('staff panel loaded — ' .. 'B16(\'fly\'), B16(\'noclip\'), B16(\'goto\',\'name\') ...')
