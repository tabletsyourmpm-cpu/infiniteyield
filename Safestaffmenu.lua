-- b16_staff_panel.lua  v2.0 — CORE BUILD integration version
-- Staff utilities for better16, curated by Sans (2026-10-23) to the
-- set that is safe to ship in the client itself:
--   spectate (view/unview), fullbright, loop fullbright, spin, sit, reset
-- Everything here is within what a normal player can already do:
-- camera subject changes, Lighting on the local client, Humanoid.Sit,
-- spinning your own character, and the stock reset. NO movement
-- enhancement (no fly/noclip/speed/teleport), nothing that touches
-- another player, nothing server-side. Because of that, this panel
-- needs no server enforcement — gate its visibility on the server's
-- staff flag as a perk if desired; the features are harmless if seen.
--
-- Dispatcher (for testing / future bindings): B16('view','Name') etc.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local Lighting = game:GetService('Lighting')
local speaker = Players.LocalPlayer

local function hum()
	local c = speaker.Character
	return c and c:FindFirstChildOfClass('Humanoid')
end
local function root()
	local c = speaker.Character
	return c and c:FindFirstChild('HumanoidRootPart')
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

local S = { bright = false, loopBright = false, spin = false, spinSpeed = 540 } -- deg/sec
local conns = {}
local function on(key, conn) if conns[key] then conns[key]:Disconnect() end conns[key] = conn end
local function off(key) if conns[key] then conns[key]:Disconnect() conns[key] = nil end end

-- ===== spectate
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

-- ===== fullbright (one-shot set + restore) and loop fullbright
local savedLighting
local function applyBright()
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.new(1, 1, 1)
	Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
	Lighting.FogEnd = 100000
end
local function brightSet(enabled)
	if enabled and not S.bright then
		savedLighting = { Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd }
	end
	S.bright = enabled
	if enabled then applyBright()
	elseif savedLighting then
		for k, v in pairs(savedLighting) do Lighting[k] = v end
		savedLighting = nil
	end
	notify('fullbright ' .. (enabled and 'on' or 'off'))
end
local function loopBrightSet(enabled)
	S.loopBright = enabled
	if enabled then
		brightSet(true)
		-- some places run their own day/night cycle and overwrite
		-- Lighting; the loop simply re-asserts the same values.
		on('loopBright', RunService.RenderStepped:Connect(function()
			if S.loopBright then applyBright() end
		end))
	else
		off('loopBright')
	end
	notify('loop fullbright ' .. (enabled and 'on' or 'off'))
end

-- ===== spin (rotate your own character; jump/macro equivalent)
local function spinSet(enabled)
	S.spin = enabled
	if enabled then
		on('spin', RunService.RenderStepped:Connect(function(dt)
			local r = root()
			if r and S.spin then
				r.CFrame = r.CFrame * CFrame.Angles(0, math.rad(S.spinSpeed) * dt, 0)
			end
		end))
	else
		off('spin')
	end
	notify('spin ' .. (enabled and 'on' or 'off'))
end

-- ===== sit (Humanoid.Sit — not anchored; jumping stands you back up)
local function sitToggle()
	local h = hum()
	if h then
		h.Sit = not h.Sit
		notify('sit ' .. (h.Sit and 'on' or 'off'))
	end
end

-- ===== reset (the stock reset character)
local function resetChar()
	local c = speaker.Character
	if c then
		pcall(function() c:BreakJoints() end)
		notify('resetting')
	end
end

-- ===== dispatcher
local cmds = {}
cmds.view = viewPlayer
cmds.unview = unview
cmds.fullbright = function() brightSet(not S.bright) end
cmds.loopfullbright = function() loopBrightSet(not S.loopBright) end
cmds.spin = function() spinSet(not S.spin) end
cmds.sit = sitToggle
cmds.reset = resetChar
cmds.stopall = function()
	if S.spin then spinSet(false) end
	if S.loopBright then loopBrightSet(false) end
	if S.bright then brightSet(false) end
	notify('all off')
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
	if S.spin then spinSet(false) end
end)

-- ===== panel GUI (drawn by the panel itself; touchpad-clickable) =====
local statusLabel
local function guiNotify(msg)
	notify(msg)
	if statusLabel then statusLabel.Text = tostring(msg) end
end

local function buildGui()
	local gui = Instance.new('ScreenGui')
	gui.Name = 'B16Staff'
	local frame = Instance.new('Frame', gui)
	frame.Name = 'Main'
	frame.Position = UDim2.new(0, 8, 0, 90)
	frame.Size = UDim2.new(0, 172, 0, 190)
	frame.BackgroundColor3 = Color3.new(0.08, 0.08, 0.1)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Draggable = true

	local title = Instance.new('TextButton', frame)
	title.Name = 'Title'
	title.Size = UDim2.new(1, 0, 0, 22)
	title.BackgroundColor3 = Color3.new(0.15, 0.15, 0.2)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.FontSize = Enum.FontSize.Size14
	title.Text = 'B16 STAFF  (tap to fold)'
	local body = Instance.new('Frame', frame)
	body.Name = 'Body'
	body.Position = UDim2.new(0, 0, 0, 22)
	body.Size = UDim2.new(1, 0, 1, -22)
	body.BackgroundTransparency = 1
	local folded = false
	title.MouseButton1Click:Connect(function()
		folded = not folded
		body.Visible = not folded
		frame.Size = folded and UDim2.new(0, 172, 0, 22) or UDim2.new(0, 172, 0, 190)
	end)

	statusLabel = Instance.new('TextLabel', body)
	statusLabel.Name = 'Status'
	statusLabel.Position = UDim2.new(0, 4, 1, -20)
	statusLabel.Size = UDim2.new(1, -8, 0, 16)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = Color3.new(0.6, 1, 0.6)
	statusLabel.FontSize = Enum.FontSize.Size12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = 'ready'

	local nameBox = Instance.new('TextBox', body)
	nameBox.Name = 'TargetName'
	nameBox.Position = UDim2.new(0, 4, 0, 2)
	nameBox.Size = UDim2.new(1, -8, 0, 20)
	nameBox.BackgroundColor3 = Color3.new(0.2, 0.2, 0.25)
	nameBox.TextColor3 = Color3.new(1, 1, 1)
	nameBox.FontSize = Enum.FontSize.Size14
	nameBox.PlaceholderText = 'player name'
	nameBox.Text = ''
	nameBox.ClearTextOnFocus = false

	local defs = {
		{ 'View', function() B16('view', nameBox.Text) guiNotify('view: ' .. nameBox.Text) end },
		{ 'Unview', function() B16('unview') end },
		{ 'Bright', function() B16('fullbright') end },
		{ 'LoopBright', function() B16('loopfullbright') end },
		{ 'Spin', function() B16('spin') end },
		{ 'Sit', function() B16('sit') end },
		{ 'Reset', function() B16('reset') end },
		{ 'ALL OFF', function() B16('stopall') end },
	}
	local bw, bh = 80, 24
	for i, d in ipairs(defs) do
		local b = Instance.new('TextButton', body)
		local ix = (i - 1) % 2 local iy = math.floor((i - 1) / 2)
		b.Name = 'Btn' .. i
		b.Position = UDim2.new(0, 4 + ix * (bw + 4), 0, 26 + iy * (bh + 3))
		b.Size = UDim2.new(0, bw, 0, bh)
		b.BackgroundColor3 = Color3.new(0.22, 0.22, 0.3)
		b.TextColor3 = Color3.new(1, 1, 1)
		b.FontSize = Enum.FontSize.Size14
		b.Text = d[1]
		b.MouseButton1Click:Connect(d[2])
	end

	local parent = nil
	pcall(function() parent = game:GetService('CoreGui') end)
	gui.Parent = parent or speaker:WaitForChild('PlayerGui')
	guiNotify('staff panel ready')
end

pcall(buildGui)
notify('staff panel v2 loaded (spectate / bright / loopbright / spin / sit / reset)')
