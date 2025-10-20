-- All-in-one Client-only Admin (LocalScript)
-- Place this LocalScript in StarterPlayer > StarterPlayerScripts
-- Fully client-side: visuals, local fly, local noclip, local teleport, Hollow Purple visual projectile + camera shake, TSB-like dash, Infinity visual barrier
-- DOES NOT create server-side damage or affect other players. Safe for "everyone" as visuals/local movement only.

-- Services
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

-- Helper: wait for character + parts
local function getCharacter()
	return player.Character or player.CharacterAdded:Wait()
end

local Character = getCharacter()
local Humanoid = Character:WaitForChild("Humanoid")
local HRP = Character:WaitForChild("HumanoidRootPart")
local Camera = workspace.CurrentCamera

-- Keep references updated on respawn
player.CharacterAdded:Connect(function(chr)
	Character = chr
	Humanoid = Character:WaitForChild("Humanoid")
	HRP = Character:WaitForChild("HumanoidRootPart")
	Camera = workspace.CurrentCamera
end)

-- -------------------------
-- Inline Modules (client-only)
-- -------------------------
local Modules = {}

-- Fly Module (improved for smooth, TSB-like control)
Modules.FlyModule = (function()
	local M = {}
	local active = false
	local bg, bv
	local speed = 80
	local maxPitchAngle = math.rad(80) -- Limit pitch for smoother control

	local function createControllers()
		if bg then bg:Destroy() end
		if bv then bv:Destroy() end
		bg = Instance.new("BodyGyro")
		bg.P = 1e5 -- Increased power for snappier response
		bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
		bg.CFrame = HRP.CFrame
		bg.Parent = HRP

		bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
		bv.Velocity = Vector3.new(0, 0, 0)
		bv.Parent = HRP
	end

	function M.Toggle()
		if not HRP then return false end
		active = not active
		if active then
			createControllers()
			Humanoid.PlatformStand = true
		else
			if bg then bg:Destroy(); bg = nil end
			if bv then bv:Destroy(); bv = nil end
			Humanoid.PlatformStand = false
		end
		return active
	end

	function M.Update(dt)
		if not active or not bg or not bv or not Camera then return end
		-- Align gyro with camera, limit pitch for smoother TSB-like control
		local cameraCF = Camera.CFrame
		local lookVector = cameraCF.LookVector
		local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
		local upVector = Vector3.new(0, 1, 0)
		local rightVector = flatLook:Cross(upVector)
		local pitchAngle = math.asin(lookVector.Y)
		if math.abs(pitchAngle) > maxPitchAngle then
			lookVector = (CFrame.new(Vector3.new(0, 0, 0), flatLook) * CFrame.Angles(math.sign(pitchAngle) * maxPitchAngle, 0, 0)).LookVector
		end
		bg.CFrame = CFrame.new(HRP.Position, HRP.Position + lookVector)

		local move = Vector3.new(0, 0, 0)
		if UIS:IsKeyDown(Enum.KeyCode.W) then move = move + Camera.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) then move = move - Camera.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) then move = move - Camera.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then move = move + Camera.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then move = move - Vector3.new(0, 1, 0) end

		local vel = Vector3.zero
		if move.Magnitude > 0.001 then
			vel = move.Unit * speed
		end
		bv.Velocity = vel -- Smooth velocity application
	end

	function M.SetSpeed(v) speed = math.max(0, v or speed) end
	function M.IsActive() return active end

	function M.Cleanup()
		if bg then bg:Destroy(); bg = nil end
		if bv then bv:Destroy(); bv = nil end
		active = false
		if Humanoid then Humanoid.PlatformStand = false end
	end

	return M
end)()

-- Noclip Module (local-only)
Modules.NoclipModule = (function()
	local M = {}
	local active = false
	local conn

	local function apply(state)
		local ch = player.Character
		if not ch then return end
		for _, part in ipairs(ch:GetDescendants()) do
			if part:IsA("BasePart") then
				pcall(function() part.CanCollide = not state end)
			end
		end
	end

	function M.Toggle()
		active = not active
		apply(active)
		return active
	end

	function M.Cleanup()
		active = false
		apply(false)
	end

	function M.IsActive() return active end

	return M
end)()

-- Speed Module (local)
Modules.SpeedModule = (function()
	local M = {}
	local default = Humanoid and Humanoid.WalkSpeed or 16
	local value = default

	function M.Set(v)
		value = math.max(0, v or value)
		if Humanoid then Humanoid.WalkSpeed = value end
	end

	function M.Get() return value end
	function M.Reset()
		value = default
		if Humanoid then Humanoid.WalkSpeed = value end
	end

	function M.Init(hum)
		Humanoid = hum or Humanoid
		default = Humanoid and Humanoid.WalkSpeed or default
		value = default
	end

	return M
end)()

-- Jump Module (local)
Modules.JumpModule = (function()
	local M = {}
	local default = Humanoid and Humanoid.JumpPower or 50
	local value = default

	function M.Set(v)
		value = math.max(0, v or value)
		if Humanoid then Humanoid.JumpPower = value end
	end

	function M.Get() return value end
	function M.Reset()
		value = default
		if Humanoid then Humanoid.JumpPower = value end
	end

	function M.Init(hum)
		Humanoid = hum or Humanoid
		default = Humanoid and Humanoid.JumpPower or default
		value = default
	end

	return M
end)()

-- Teleport Module (local)
Modules.TeleportModule = (function()
	local M = {}
	function M.TeleportToXYZ(x, y, z)
		if not x or not y or not z then return end
		local char = player.Character
		if char and char.PrimaryPart then
			char:SetPrimaryPartCFrame(CFrame.new(x, y + 3, z))
		elseif char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = CFrame.new(x, y + 3, z)
		end
	end

	function M.ClickTeleportTo(pos)
		if not pos then return end
		local char = player.Character
		if char and char.PrimaryPart then
			char:SetPrimaryPartCFrame(CFrame.new(pos + Vector3.new(0, 3, 0)))
		elseif char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
		end
	end

	return M
end)()

-- Hollow Purple (visual-only, enhanced for more TSB-like flair)
Modules.HollowPurpleModule = (function()
	local M = {}
	local charging = false
	local chargeStart = 0
	local redOrb, blueOrb, mergedOrb, aura
	local followConnection

	local function cameraShake(duration, magnitude)
		local cam = workspace.CurrentCamera
		if not cam then return end
		local t0 = tick()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local now = tick()
			local elapsed = now - t0
			if elapsed > duration then
				conn:Disconnect()
				return
			end
			local damper = 1 - (elapsed / duration)
			local x = (math.noise(now * 20, 1) - 0.5) * 2 * magnitude * damper
			local y = (math.noise(now * 20, 2) - 0.5) * 2 * magnitude * damper
			local z = (math.noise(now * 20, 3) - 0.5) * 2 * magnitude * damper
			local cf = cam.CFrame
			cam.CFrame = CFrame.new(cf.Position) * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
		end)
	end

	local function cleanupOrbs()
		if redOrb then pcall(function() redOrb:Destroy() end); redOrb = nil end
		if blueOrb then pcall(function() blueOrb:Destroy() end); blueOrb = nil end
		if mergedOrb then pcall(function() mergedOrb:Destroy() end); mergedOrb = nil end
		if aura then pcall(function() aura:Destroy() end); aura = nil end
		if followConnection then followConnection:Disconnect(); followConnection = nil end
	end

	local function spawnOrbPart(size, color, parent)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(size, size, size)
		p.CanCollide = false
		p.Anchored = true
		p.Material = Enum.Material.Neon
		p.Color = color
		p.CastShadow = false
		p.Parent = parent or workspace
		return p
	end

	function M.StartCharge()
		if charging then return end
		charging = true
		chargeStart = tick()
		cleanupOrbs()

		redOrb = spawnOrbPart(1, Color3.fromRGB(255, 80, 80))
		blueOrb = spawnOrbPart(1, Color3.fromRGB(80, 140, 255))
		aura = spawnOrbPart(2, Color3.fromRGB(220, 100, 255))
		aura.Transparency = 0.6

		local emitter = Instance.new("ParticleEmitter", aura)
		emitter.Rate = 50
		emitter.Lifetime = NumberRange.new(0.3, 0.8)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0)})
		emitter.Color = ColorSequence.new(Color3.fromRGB(220, 100, 255))
		emitter.Transparency = NumberSequence.new(0.4)

		followConnection = RunService.RenderStepped:Connect(function()
			if not charging then return end
			local char = player.Character
			if not char or not char:FindFirstChild("HumanoidRootPart") then return end
			local hrp = char.HumanoidRootPart
			local followCF = hrp.CFrame * CFrame.new(0, 0.8, -1.5)
			local t = (tick() - chargeStart) * 2.5
			local r = 1.5 + math.sin((tick() - chargeStart) * 1.6) * 0.15
			if redOrb then redOrb.CFrame = followCF * CFrame.new(math.cos(t) * r, math.sin(t * 1.3) * 0.3, math.sin(t) * r) end
			if blueOrb then blueOrb.CFrame = followCF * CFrame.new(math.cos(t + math.pi) * r, math.sin((t + math.pi) * 1.3) * 0.3, math.sin(t + math.pi) * r) end
			if aura then aura.CFrame = followCF end

			local chargeDur = math.clamp((tick() - chargeStart) / 1.2, 0, 1)
			if aura then aura.Size = Vector3.new(2 + chargeDur * 8, 2 + chargeDur * 8, 2 + chargeDur * 8) end
		end)
	end

	function M.Release()
		if not charging then return end
		charging = false

		local originCF = HRP and (HRP.CFrame * CFrame.new(0, 0.8, -1.5)) or Camera.CFrame
		cleanupOrbs()

		mergedOrb = spawnOrbPart(2, Color3.fromRGB(160, 0, 220))
		mergedOrb.CFrame = originCF
		mergedOrb.Transparency = 0
		mergedOrb.CanCollide = false

		local mergedAura = spawnOrbPart(4, Color3.fromRGB(180, 60, 255))
		mergedAura.Transparency = 0.5
		mergedAura.CFrame = originCF

		local buildTween = TweenService:Create(mergedOrb, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(6, 6, 6)})
		local auraTween = TweenService:Create(mergedAura, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(14, 14, 14), Transparency = 0.4})
		buildTween:Play(); auraTween:Play()

		local emitter = Instance.new("ParticleEmitter", mergedOrb)
		emitter.Rate = 100
		emitter.Lifetime = NumberRange.new(0.3, 1)
		emitter.Speed = NumberRange.new(0, 8)
		emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0)})
		emitter.Color = ColorSequence.new(Color3.fromRGB(220, 140, 255), Color3.fromRGB(160, 0, 220))
		emitter.Transparency = NumberSequence.new(0.3)

		delay(0.9, function()
			cameraShake(0.6, 1.5)
			local dir = Camera.CFrame.LookVector
			local speed = 160
			local bv = Instance.new("BodyVelocity")
			bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			bv.Velocity = dir * speed
			bv.Parent = mergedOrb
			mergedOrb.Anchored = false

			local follow = RunService.RenderStepped:Connect(function()
				if mergedOrb and mergedOrb.Parent then
					mergedAura.CFrame = mergedOrb.CFrame
				else
					if follow then follow:Disconnect() end
				end
			end)

			Debris:AddItem(mergedAura, 2.5)
			Debris:AddItem(mergedOrb, 2.5)

			delay(1.2, function()
				if mergedOrb and mergedOrb.Parent then
					local burst = Instance.new("ParticleEmitter")
					burst.Parent = mergedOrb
					burst.Rate = 400
					burst.Lifetime = NumberRange.new(0.4, 1)
					burst.Speed = NumberRange.new(8, 30)
					burst.Size = NumberSequence.new(2)
					burst.Color = ColorSequence.new(Color3.fromRGB(255, 180, 255), Color3.fromRGB(160, 0, 220))
					Debris:AddItem(burst, 0.7)

					local flash = Instance.new("Part")
					flash.Anchored = true
					flash.CanCollide = false
					flash.Size = Vector3.new(10, 10, 10)
					flash.Material = Enum.Material.Neon
					flash.Color = Color3.fromRGB(255, 220, 255)
					flash.Transparency = 0.6
					flash.CFrame = mergedOrb.CFrame
					flash.Parent = workspace
					Debris:AddItem(flash, 0.4)
				end
			end)

			delay(2.5, function()
				if bv then bv:Destroy() end
				if follow then follow:Disconnect() end
			end)
		end)
	end

	function M.IsCharging() return charging end
	function M.Cleanup() cleanupOrbs(); charging = false end

	return M
end)()

-- Infinity Module (visual-only barrier)
Modules.InfinityModule = (function()
	local M = {}
	local active = false
	local barrier, aura, emitter
	local connection

	local function cleanup()
		if barrier then pcall(function() barrier:Destroy() end); barrier = nil end
		if aura then pcall(function() aura:Destroy() end); aura = nil end
		if emitter then pcall(function() emitter:Destroy() end); emitter = nil end
		if connection then connection:Disconnect(); connection = nil end
		active = false
	end

	function M.Toggle()
		if not HRP then return false end
		active = not active
		if active then
			cleanup()
			barrier = Instance.new("Part")
			barrier.Shape = Enum.PartType.Ball
			barrier.Size = Vector3.new(8, 8, 8)
			barrier.Material = Enum.Material.ForceField
			barrier.Color = Color3.fromRGB(100, 150, 255)
			barrier.Transparency = 0.4
			barrier.CanCollide = false
			barrier.Anchored = true
			barrier.CastShadow = false
			barrier.Parent = workspace

			aura = Instance.new("Part")
			aura.Shape = Enum.PartType.Ball
			aura.Size = Vector3.new(8.5, 8.5, 8.5)
			aura.Material = Enum.Material.Neon
			aura.Color = Color3.fromRGB(120, 180, 255)
			aura.Transparency = 0.7
			aura.CanCollide = false
			aura.Anchored = true
			aura.CastShadow = false
			aura.Parent = workspace

			emitter = Instance.new("ParticleEmitter", aura)
			emitter.Rate = 60
			emitter.Lifetime = NumberRange.new(0.5, 1.2)
			emitter.Speed = NumberRange.new(1, 3)
			emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0)})
			emitter.Color = ColorSequence.new(Color3.fromRGB(150, 200, 255))
			emitter.Transparency = NumberSequence.new(0.5)

			local t = 0
			connection = RunService.RenderStepped:Connect(function(dt)
				if not active or not HRP then cleanup(); return end
				t = t + dt
				local cf = HRP.CFrame
				if barrier then
					barrier.CFrame = cf
					barrier.Transparency = 0.4 + math.sin(t * 2) * 0.1
				end
				if aura then
					aura.CFrame = cf
					aura.Size = Vector3.new(8.5 + math.sin(t * 1.5) * 0.3, 8.5 + math.sin(t * 1.5) * 0.3, 8.5 + math.sin(t * 1.5) * 0.3)
				end
			end)
		else
			cleanup()
		end
		return active
	end

	function M.IsActive() return active end
	function M.Cleanup() cleanup() end

	return M
end)()

-- -------------------------
-- GUI (self-contained Rayfield-like)
-- -------------------------
local UI = {}
do
	local screen = Instance.new("ScreenGui")
	screen.Name = "AdminMenuGUI_ClientOnly"
	screen.ResetOnSpawn = false
	screen.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "RayfieldPanel"
	panel.Size = UDim2.new(0, 380, 0, 360) -- Slightly taller for new button
	panel.Position = UDim2.new(0.5, -190, -1, 0)
	panel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ClipsDescendants = true
	panel.Parent = screen
	local panelCorner = Instance.new("UICorner", panel); panelCorner.CornerRadius = UDim.new(0, 12)

	local title = Instance.new("Frame", panel)
	title.Size = UDim2.new(1, 0, 0, 38)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	title.BorderSizePixel = 0
	local titleCorner = Instance.new("UICorner", title); titleCorner.CornerRadius = UDim.new(0, 12)
	local titleLabel = Instance.new("TextLabel", title)
	titleLabel.Size = UDim2.new(1, -100, 1, 0)
	titleLabel.Position = UDim2.new(0, 12, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = "Control Panel (Client Only)"

	local closeBtn = Instance.new("TextButton", title)
	closeBtn.Size = UDim2.new(0, 70, 0, 26)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(165, 35, 35)
	closeBtn.Text = "Close"
	closeBtn.Font = Enum.Font.Gotham
	closeBtn.TextSize = 13
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.BorderSizePixel = 0
	local closeCorner = Instance.new("UICorner", closeBtn); closeCorner.CornerRadius = UDim.new(0, 6)

	local scrollFrame = Instance.new("ScrollingFrame", panel)
	scrollFrame.Size = UDim2.new(1, -16, 1, -52)
	scrollFrame.Position = UDim2.new(0, 8, 0, 44)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)

	local contentLayout = Instance.new("UIListLayout", scrollFrame)
	contentLayout.Padding = UDim.new(0, 8)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder

	contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 10)
	end)

	local resizeHandle = Instance.new("ImageButton", panel)
	resizeHandle.Size = UDim2.new(0, 20, 0, 20)
	resizeHandle.AnchorPoint = Vector2.new(1, 1)
	resizeHandle.Position = UDim2.new(1, -4, 1, -4)
	resizeHandle.BackgroundTransparency = 1
	resizeHandle.Image = "rbxasset://textures/ui/ResizeIcon.png"
	resizeHandle.ImageColor3 = Color3.fromRGB(150, 150, 150)

	local function createCard(h)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, -8, 0, h or 70)
		f.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
		f.BorderSizePixel = 0
		local c = Instance.new("UICorner", f); c.CornerRadius = UDim.new(0, 8)
		f.Parent = scrollFrame
		return f
	end

	local function makeButton(parent, text)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.45, -6, 0, 32)
		b.Position = UDim2.new(0, 8, 0, 8)
		b.BackgroundColor3 = Color3.fromRGB(44, 44, 44)
		b.BorderSizePixel = 0
		b.Font = Enum.Font.Gotham
		b.TextSize = 13
		b.TextColor3 = Color3.fromRGB(240, 240, 240)
		b.Text = text
		local cc = Instance.new("UICorner", b); cc.CornerRadius = UDim.new(0, 6)
		b.Parent = parent
		return b
	end

	local function makeLabel(parent, text)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(0.52, -6, 0, 18)
		l.Position = UDim2.new(0.47, 4, 0, 8)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextSize = 12
		l.TextColor3 = Color3.fromRGB(210, 210, 210)
		l.Text = text
		l.TextWrapped = true
		l.Parent = parent
		return l
	end

	-- Fly card
	local flyCard = createCard(70)
	local flyBtn = makeButton(flyCard, "Toggle Fly (B)")
	local flyLbl = makeLabel(flyCard, "Local fly (W/A/S/D + Space/Shift). Client-only.")

	flyBtn.MouseButton1Click:Connect(function()
		local active = Modules.FlyModule.Toggle()
		flyBtn.Text = active and "Fly: ON (B)" or "Toggle Fly (B)"
	end)

	-- Noclip card
	local noclipCard = createCard(70)
	local noclipBtn = makeButton(noclipCard, "Toggle No-Clip")
	local noclipLbl = makeLabel(noclipCard, "Local No-Clip (parts lose collisions locally)")

	noclipBtn.MouseButton1Click:Connect(function()
		local active = Modules.NoclipModule.Toggle()
		noclipBtn.Text = active and "No-Clip: ON" or "Toggle No-Clip"
	end)

	-- Speed card (slider)
	local speedCard = createCard(90)
	local speedLabel = Instance.new("TextLabel", speedCard)
	speedLabel.Size = UDim2.new(1, -16, 0, 18)
	speedLabel.Position = UDim2.new(0, 8, 0, 8)
	speedLabel.BackgroundTransparency = 1
	speedLabel.Font = Enum.Font.Gotham
	speedLabel.TextSize = 12
	speedLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	speedLabel.Text = "Speed: " .. tostring(Modules.SpeedModule.Get() or Humanoid.WalkSpeed)

	local speedTrack = Instance.new("Frame", speedCard)
	speedTrack.Size = UDim2.new(1, -16, 0, 8)
	speedTrack.Position = UDim2.new(0, 8, 0, 38)
	speedTrack.BackgroundColor3 = Color3.fromRGB(64, 64, 64)
	local stCorner = Instance.new("UICorner", speedTrack); stCorner.CornerRadius = UDim.new(0, 5)
	local speedKnob = Instance.new("ImageButton", speedCard)
	speedKnob.Size = UDim2.new(0, 14, 0, 14)
	speedKnob.AnchorPoint = Vector2.new(0, 0.5)
	local initSpeed = Modules.SpeedModule.Get() or Humanoid.WalkSpeed
	local minSpeed, maxSpeed = 10, 500
	local speedNorm = (initSpeed - minSpeed) / (maxSpeed - minSpeed)
	speedKnob.Position = UDim2.new(math.clamp(speedNorm, 0, 1), -7, 0, 45)
	speedKnob.Image = "rbxassetid://3570695787"
	speedKnob.BackgroundTransparency = 1

	-- Jump card (slider)
	local jumpCard = createCard(90)
	local jumpLabel = Instance.new("TextLabel", jumpCard)
	jumpLabel.Size = UDim2.new(1, -16, 0, 18)
	jumpLabel.Position = UDim2.new(0, 8, 0, 8)
	jumpLabel.BackgroundTransparency = 1
	jumpLabel.Font = Enum.Font.Gotham
	jumpLabel.TextSize = 12
	jumpLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	jumpLabel.Text = "Jump: " .. tostring(Modules.JumpModule.Get() or Humanoid.JumpPower)

	local jumpTrack = Instance.new("Frame", jumpCard)
	jumpTrack.Size = UDim2.new(1, -16, 0, 8)
	jumpTrack.Position = UDim2.new(0, 8, 0, 38)
	jumpTrack.BackgroundColor3 = Color3.fromRGB(64, 64, 64)
	local jtCorner = Instance.new("UICorner", jumpTrack); jtCorner.CornerRadius = UDim.new(0, 5)
	local jumpKnob = Instance.new("ImageButton", jumpCard)
	jumpKnob.Size = UDim2.new(0, 14, 0, 14)
	jumpKnob.AnchorPoint = Vector2.new(0, 0.5)
	local initJump = Modules.JumpModule.Get() or Humanoid.JumpPower
	local minJump, maxJump = 10, 500
	local jumpNorm = (initJump - minJump) / (maxJump - minJump)
	jumpKnob.Position = UDim2.new(math.clamp(jumpNorm, 0, 1), -7, 0, 45)
	jumpKnob.Image = "rbxassetid://3570695787"
	jumpKnob.BackgroundTransparency = 1

	-- Teleport card
	local tpCard = createCard(100)
	local tpX = Instance.new("TextBox", tpCard)
	tpX.Size = UDim2.new(0.3, -4, 0, 26)
	tpX.Position = UDim2.new(0, 8, 0, 8)
	tpX.PlaceholderText = "X"
	tpX.ClearTextOnFocus = false
	tpX.BackgroundColor3 = Color3.fromRGB(36, 36, 36)
	tpX.TextColor3 = Color3.fromRGB(245, 245, 245)
	tpX.Font = Enum.Font.Gotham
	tpX.TextSize = 13

	local tpY = tpX:Clone(); tpY.Parent = tpCard; tpY.Position = UDim2.new(0.35, 0, 0, 8); tpY.PlaceholderText = "Y"
	local tpZ = tpX:Clone(); tpZ.Parent = tpCard; tpZ.Position = UDim2.new(0.7, 0, 0, 8); tpZ.PlaceholderText = "Z"

	local tpBtn = Instance.new("TextButton", tpCard)
	tpBtn.Size = UDim2.new(1, -16, 0, 32)
	tpBtn.Position = UDim2.new(0, 8, 0, 44)
	tpBtn.Text = "Teleport (Local)"
	tpBtn.Font = Enum.Font.Gotham
	tpBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
	tpBtn.TextSize = 13
	tpBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	tpBtn.BorderSizePixel = 0
	local tpCorner = Instance.new("UICorner", tpBtn); tpCorner.CornerRadius = UDim.new(0, 6)

	tpBtn.MouseButton1Click:Connect(function()
		local x = tonumber(tpX.Text)
		local y = tonumber(tpY.Text)
		local z = tonumber(tpZ.Text)
		if x and y and z then
			Modules.TeleportModule.TeleportToXYZ(x, y, z)
		end
	end)

	-- Click TP card
	local clickCard = createCard(70)
	local clickBtn = makeButton(clickCard, "Toggle Click TP")
	local clickLabel = makeLabel(clickCard, "Click ground to teleport locally")
	local clickTPEnabled = false
	clickBtn.MouseButton1Click:Connect(function()
		clickTPEnabled = not clickTPEnabled
		clickBtn.Text = clickTPEnabled and "Click TP: ON" or "Toggle Click TP"
	end)

	-- Hollow Purple card
	local hollowCard = createCard(90)
	local hollowBtn = makeButton(hollowCard, "Hollow Purple (Z)")
	hollowBtn.Size = UDim2.new(0.45, -6, 0, 32)
	local hollowLabel = makeLabel(hollowCard, "Charge with Z, release to fire (visual only)")
	hollowBtn.MouseButton1Click:Connect(function()
		if not Modules.HollowPurpleModule.IsCharging() then
			Modules.HollowPurpleModule.StartCharge()
			delay(1.2, function()
				if Modules.HollowPurpleModule.IsCharging() then
					Modules.HollowPurpleModule.Release()
				end
			end)
		end
	end)

	-- Infinity card
	local infinityCard = createCard(70)
	local infinityBtn = makeButton(infinityCard, "Toggle Infinity (X)")
	local infinityLabel = makeLabel(infinityCard, "Visual barrier effect (client-side only)")
	infinityBtn.MouseButton1Click:Connect(function()
		local active = Modules.InfinityModule.Toggle()
		infinityBtn.Text = active and "Infinity: ON (X)" or "Toggle Infinity (X)"
	end)

	-- Window dragging
	local dragging = false
	local dragStart = nil
	local startPos = nil

	title.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = panel.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	UIS.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)

	-- Resize handle
	local resizing = false
	local resizeStart = nil
	local startSize = nil

	resizeHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = true
			resizeStart = input.Position
			startSize = panel.Size
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
				end
			end)
		end
	end)

	UIS.InputChanged:Connect(function(input)
		if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - resizeStart
			local newWidth = math.max(300, startSize.X.Offset + delta.X)
			local newHeight = math.max(250, startSize.Y.Offset + delta.Y)
			panel.Size = UDim2.new(0, newWidth, 0, newHeight)
		end
	end)

	-- Close button
	closeBtn.MouseButton1Click:Connect(function()
		local closeTween = TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Position = UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, -1, 0)
		})
		closeTween:Play()
		closeTween.Completed:Connect(function()
			panel.Visible = false
		end)
	end)

	-- Toggle button
	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "MenuToggle"
	toggleButton.Size = UDim2.new(0, 120, 0, 34)
	toggleButton.Position = UDim2.new(0.5, -60, 0.03, 0)
	toggleButton.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	toggleButton.Text = "Menu"
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 15
	toggleButton.TextColor3 = Color3.new(1, 1, 1)
	local toggleCorner = Instance.new("UICorner", toggleButton); toggleCorner.CornerRadius = UDim.new(0, 10)
	toggleButton.Parent = screen

	-- Make toggle draggable
	local toggleDragging = false
	local toggleDragStart = nil
	local toggleStartPos = nil

	toggleButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			toggleDragging = true
			toggleDragStart = input.Position
			toggleStartPos = toggleButton.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					toggleDragging = false
				end
			end)
		end
	end)

	UIS.InputChanged:Connect(function(input)
		if toggleDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - toggleDragStart
			toggleButton.Position = UDim2.new(toggleStartPos.X.Scale, toggleStartPos.X.Offset + delta.X, toggleStartPos.Y.Scale, toggleStartPos.Y.Offset + delta.Y)
		end
	end)

	toggleButton.MouseButton1Click:Connect(function()
		if panel.Visible then
			local slideOut = TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Position = UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, -1, 0)
			})
			slideOut:Play()
			slideOut.Completed:Connect(function()
				panel.Visible = false
			end)
		else
			panel.Visible = true
			local slideIn = TweenService:Create(panel, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, -190, 0.18, 0)
			})
			slideIn:Play()
		end
	end)

	-- Click outside to close
	UIS.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and panel.Visible then
			local mpos = UIS:GetMouseLocation()
			local absPos = panel.AbsolutePosition
			local absSize = panel.AbsoluteSize
			if not (mpos.X >= absPos.X and mpos.X <= absPos.X + absSize.X and mpos.Y >= absPos.Y and mpos.Y <= absPos.Y + absSize.Y) then
				local slideOut = TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
					Position = UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, -1, 0)
				})
				slideOut:Play()
				slideOut.Completed:Connect(function()
					panel.Visible = false
				end)
			end
		end
	end)

	UI.Panel = panel
	UI.ToggleButton = toggleButton
	UI.SpeedKnob = speedKnob
	UI.SpeedTrack = speedTrack
	UI.SpeedLabel = speedLabel
	UI.JumpKnob = jumpKnob
	UI.JumpTrack = jumpTrack
	UI.JumpLabel = jumpLabel
	UI.ClickTPEnabled = function() return clickTPEnabled end
	UI.PanelVisible = function() return panel.Visible end
	UI.Close = function()
		local closeTween = TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Position = UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, -1, 0)
		})
		closeTween:Play()
		closeTween.Completed:Connect(function() panel.Visible = false end)
	end
end

-- -------------------------
-- Interaction & Knob logic
-- -------------------------
do
	local draggingSpeed = false
	local minSpeed, maxSpeed = 10, 1000
	local speedTrack = UI.SpeedTrack
	local speedKnob = UI.SpeedKnob
	local speedLabel = UI.SpeedLabel

	speedKnob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			draggingSpeed = true
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then draggingSpeed = false end
			end)
		end
	end)

	UIS.InputChanged:Connect(function(input)
		if draggingSpeed and input.UserInputType == Enum.UserInputType.MouseMovement then
			local absX = speedTrack.AbsolutePosition.X
			local width = math.max(1, speedTrack.AbsoluteSize.X)
			local mx = UIS:GetMouseLocation().X
			local norm = (mx - absX) / width
			norm = math.clamp(norm, 0, 1)
			speedKnob.Position = UDim2.new(norm, -7, 0, 45)
			local val = math.floor(minSpeed + (maxSpeed - minSpeed) * norm + 0.5)
			Modules.SpeedModule.Set(val)
			speedLabel.Text = "Speed: " .. tostring(val)
			Modules.FlyModule.SetSpeed(val)
		end
	end)

	local draggingJump = false
	local jumpTrack = UI.JumpTrack
	local jumpKnob = UI.JumpKnob
	local jumpLabel = UI.JumpLabel
	local minJump, maxJump = 10, 1000

	jumpKnob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			draggingJump = true
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then draggingJump = false end
			end)
		end
	end)

	UIS.InputChanged:Connect(function(input)
		if draggingJump and input.UserInputType == Enum.UserInputType.MouseMovement then
			local absX = jumpTrack.AbsolutePosition.X
			local width = math.max(1, jumpTrack.AbsoluteSize.X)
			local mx = UIS:GetMouseLocation().X
			local norm = (mx - absX) / width
			norm = math.clamp(norm, 0, 1)
			jumpKnob.Position = UDim2.new(norm, -7, 0, 45)
			local val = math.floor(minJump + (maxJump - minJump) * norm + 0.5)
			Modules.JumpModule.Set(val)
			jumpLabel.Text = "Jump: " .. tostring(val)
		end
	end)
end

-- Click TP behavior
player:GetMouse().Button1Down:Connect(function()
	local mouse = player:GetMouse()
	if UI.ClickTPEnabled() and UI.PanelVisible() and not Modules.HollowPurpleModule.IsCharging() then
		if mouse.Target and mouse.Hit then
			Modules.TeleportModule.ClickTeleportTo(mouse.Hit.Position)
		end
	end
end)

-- Keybinds: Z for Hollow Purple, B for Fly, X for Infinity, Q for Dash
do
	UIS.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Z then
			if not Modules.HollowPurpleModule.IsCharging() then
				Modules.HollowPurpleModule.StartCharge()
			end
		elseif input.KeyCode == Enum.KeyCode.B then
			local active = Modules.FlyModule.Toggle()
		elseif input.KeyCode == Enum.KeyCode.X then
			local active = Modules.InfinityModule.Toggle()
		elseif input.KeyCode == Enum.KeyCode.Q then
			_G.PerformDash(100) -- Dash with default distance
		end
	end)

	UIS.InputEnded:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Z then
			if Modules.HollowPurpleModule.IsCharging() then
				Modules.HollowPurpleModule.Release()
			end
		end
	end)
end

-- Update loop for modules
RunService.RenderStepped:Connect(function(dt)
	Modules.FlyModule.Update(dt)
end)

-- Character respawn handling
player.CharacterAdded:Connect(function(chr)
	Character = chr
	Humanoid = Character:WaitForChild("Humanoid")
	HRP = Character:WaitForChild("HumanoidRootPart")
	Camera = workspace.CurrentCamera
	Modules.FlyModule.Cleanup()
	Modules.NoclipModule.Cleanup()
	Modules.SpeedModule.Init(Humanoid)
	Modules.JumpModule.Init(Humanoid)
	Modules.HollowPurpleModule.Cleanup()
	Modules.InfinityModule.Cleanup()
end)

-- Coordinates UI
local CoordsUI = Instance.new("ScreenGui")
CoordsUI.Name = "CoordsUI"
CoordsUI.ResetOnSpawn = false
CoordsUI.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 220, 0, 60)
frame.Position = UDim2.new(1, -230, 1, -70)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BackgroundTransparency = 0.25
frame.BorderSizePixel = 0
frame.Parent = CoordsUI

local corner = Instance.new("UICorner", frame)
corner.CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", frame)
stroke.Thickness = 1
stroke.Color = Color3.fromRGB(90, 90, 90)
stroke.Transparency = 0.3

local coordLabel = Instance.new("TextLabel")
coordLabel.Size = UDim2.new(1, -10, 1, -10)
coordLabel.Position = UDim2.new(0, 5, 0, 5)
coordLabel.BackgroundTransparency = 1
coordLabel.Text = "X: 0\nY: 0\nZ: 0"
coordLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
coordLabel.TextStrokeTransparency = 0.7
coordLabel.TextSize = 16
coordLabel.Font = Enum.Font.GothamMedium
coordLabel.TextXAlignment = Enum.TextXAlignment.Left
coordLabel.TextYAlignment = Enum.TextYAlignment.Top
coordLabel.Parent = frame

RunService.RenderStepped:Connect(function()
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		local pos = character.HumanoidRootPart.Position
		coordLabel.Text = string.format("X: %.1f\nY: %.1f\nZ: %.1f", pos.X, pos.Y, pos.Z)
	end
end)

-- Dash (TSB-like)
local lastLocalDashRequest = 0
local LOCAL_REQUEST_COOLDOWN = 0.2 -- Tighter cooldown for snappy TSB feel
local DASH_DISTANCE = 100 -- Matches TSB's long-range dash

local function cameraShake(duration, magnitude)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local t0 = tick()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = tick()
		local elapsed = now - t0
		if elapsed > duration then
			conn:Disconnect()
			return
		end
		local damper = 1 - (elapsed / duration)
		local x = (math.noise(now * 22, 1) - 0.5) * 2 * magnitude * damper
		local y = (math.noise(now * 22, 2) - 0.5) * 2 * magnitude * damper
		local z = (math.noise(now * 22, 3) - 0.5) * 2 * magnitude * damper
		local cf = cam.CFrame
		cam.CFrame = CFrame.new(cf.Position) * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	end)
end

local function spawnLightningBetween(a, b, color)
	local dir = (b - a)
	local len = dir.Magnitude
	if len <= 0 then return end
	local segments = math.clamp(math.floor(len / 1.5), 8, 60) -- More segments for TSB chaos
	local parent = Instance.new("Folder")
	parent.Name = "DashLightning"
	parent.Parent = workspace

	local prev = a
	for i = 1, segments do
		local t = i / segments
		local point = a + dir * t
		local jitter = Vector3.new((math.random() - 0.5) * 4, (math.random() - 0.5) * 4, (math.random() - 0.5) * 4)
		local segPos = point + jitter * (1 - math.abs(0.5 - t)) * 1.5

		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Neon
		part.Size = Vector3.new(0.08, 0.08, (segPos - prev).Magnitude)
		part.CFrame = CFrame.new((segPos + prev) / 2, segPos) * CFrame.Angles(math.pi / 2, 0, 0)
		part.Color = color or Color3.fromRGB(180, 80, 255)
		part.Parent = parent
		prev = segPos
		Debris:AddItem(part, 0.5)
	end
	Debris:AddItem(parent, 0.6)
end

local function spawnDashTrail(originCF)
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(4, 4, 4)
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(180, 80, 255)
	orb.Anchored = true
	orb.CanCollide = false
	orb.CFrame = originCF
	orb.Parent = workspace
	Debris:AddItem(orb, 0.8)
	local tween = TweenService:Create(orb, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {Size = Vector3.new(8, 8, 8), Transparency = 1})
	tween:Play()

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://243098098"
	emitter.Size = NumberSequence.new(1, 0)
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Rate = 200
	emitter.Speed = NumberRange.new(10, 25)
	emitter.Color = ColorSequence.new(Color3.fromRGB(180, 80, 255))
	emitter.Parent = orb
	task.delay(0.15, function() emitter.Enabled = false end)
end

local function playDashSound()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://911853195" -- TSB-like whoosh sound
	sound.Volume = 1.2
	sound.Parent = workspace
	sound:Play()
	Debris:AddItem(sound, 1.2)
end

local function performDash(distance)
	if tick() - lastLocalDashRequest < LOCAL_REQUEST_COOLDOWN then return end
	lastLocalDashRequest = tick()

	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local hum = char:FindFirstChild("Humanoid")
	if not hum then return end

	local cam = workspace.CurrentCamera
	if not cam then return end
	local lookDir = cam.CFrame.LookVector
	local origin = hrp.Position
	local target = origin + lookDir * distance

	-- Raycast to prevent dashing through walls
	local ray = Ray.new(origin, lookDir * distance)
	local hit, pos = workspace:FindPartOnRayWithIgnoreList(ray, {char})
	if hit then
		target = pos
	end

	hrp.CFrame = CFrame.new(target) * (hrp.CFrame - hrp.CFrame.Position)
	cameraShake(0.4, 2.5)
	spawnLightningBetween(origin, target, Color3.fromRGB(180, 80, 255))
	spawnDashTrail(CFrame.new(target))
	playDashSound()

	local gui = Instance.new("ScreenGui")
	gui.ResetOnSpawn = false
	gui.Name = "DashFlash"
	gui.Parent = player:WaitForChild("PlayerGui")
	local rect = Instance.new("Frame", gui)
	rect.AnchorPoint = Vector2.new(0.5, 0.5)
	rect.Size = UDim2.new(2, 0, 2, 0)
	rect.Position = UDim2.new(0.5, 0, 0.5, 0)
	rect.BackgroundColor3 = Color3.fromRGB(220, 140, 255)
	rect.BackgroundTransparency = 0.7
	rect.ZIndex = 99999
	Debris:AddItem(gui, 0.4)
	TweenService:Create(rect, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()
end

_G.PerformDash = performDash

-- Initial module init
Modules.SpeedModule.Init(Humanoid)
Modules.JumpModule.Init(Humanoid)

print("[ClientAdmin] Loaded: Client-only admin GUI (visuals & local movement). Hollow Purple and Infinity are visual-only. Press Q to dash, X for Infinity.")
