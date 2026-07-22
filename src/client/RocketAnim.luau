-- RocketAnim.luau - arcing missile and impact effects
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Config            = require(sharedFolder:WaitForChild("Config"))

local RocketAnim = {}

local function spawnExplosion(pos)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(2, 2, 2)
	ball.Position = pos
	ball.Anchored = true
	ball.CanCollide = false
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 140, 20)
	ball.Parent = workspace

	local ballTween = TweenService:Create(ball,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(22, 22, 22), Transparency = 1 })
	ballTween:Play()
	Debris:AddItem(ball, 0.5)

	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.6, 2, 2)
	ring.Position = pos
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 60, 20)
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Parent = workspace

	local ringTween = TweenService:Create(ring,
		TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.6, 30, 30), Transparency = 1 })
	ringTween:Play()
	Debris:AddItem(ring, 0.6)

	for i = 1, 8 do
		task.spawn(function()
			local smoke = Instance.new("Part")
			smoke.Shape = Enum.PartType.Ball
			smoke.Size = Vector3.new(3, 3, 3)
			smoke.Position = pos + Vector3.new(
				(math.random() - 0.5) * 10,
				math.random() * 6,
				(math.random() - 0.5) * 10
			)
			smoke.Anchored = true
			smoke.CanCollide = false
			smoke.Material = Enum.Material.SmoothPlastic
			smoke.Color = Color3.fromRGB(60 + math.random(30), 60 + math.random(30), 65)
			smoke.Parent = workspace

			local st = TweenService:Create(smoke,
				TweenInfo.new(0.9, Enum.EasingStyle.Quad),
				{ Size = Vector3.new(9, 9, 9), Transparency = 1, Position = smoke.Position + Vector3.new(0, 10, 0) })
			st:Play()
			Debris:AddItem(smoke, 1)
		end)
	end
end

local function arcPos(origin, target, t)
	local arc = Config.ROCKET_ARC
	local straight = origin:Lerp(target, t)
	local height = math.sin(t * math.pi) * arc
	return Vector3.new(straight.X, straight.Y + height, straight.Z)
end

function RocketAnim.Play(data, animEnabled)
	local origin = data.originPos
	local target = data.targetPos

	if not animEnabled then
		spawnExplosion(target)
		return
	end

	local rocket = Instance.new("Part")
	rocket.Name = "Rocket"
	rocket.Size = Vector3.new(1.5, 1.5, 5)
	rocket.Position = origin
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.Material = Enum.Material.Metal
	rocket.Color = Color3.fromRGB(225, 230, 232)
	rocket.Parent = workspace

	local front = Instance.new("Attachment")
	front.Position = Vector3.new(0, 0, -2)
	front.Parent = rocket
	local back = Instance.new("Attachment")
	back.Position = Vector3.new(0, 0, 2.5)
	back.Parent = rocket
	local trail = Instance.new("Trail")
	trail.Attachment0 = front
	trail.Attachment1 = back
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 205, 70), Color3.fromRGB(235, 75, 35))
	trail.Lifetime = 0.3
	trail.MinLength = 0.4
	trail.Parent = rocket

	local light = Instance.new("PointLight")
	light.Brightness = 8
	light.Range = 20
	light.Color = Color3.fromRGB(255, 120, 20)
	light.Parent = rocket

	local skipped = false
	local skipConn
	skipConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			skipped = true
		end
	end)

	local dist = (target - origin).Magnitude
	local duration = math.clamp(dist / Config.ROCKET_SPEED, 0.8, Config.ROCKET_ANIM_TIME)
	local steps = math.ceil(duration / 0.03)

	for i = 1, steps do
		if skipped then break end
		local t = i / steps
		local pos = arcPos(origin, target, t)

		local nextT = math.min(t + 0.04, 1)
		local nextPos = arcPos(origin, target, nextT)
		local dir = (nextPos - pos)
		if dir.Magnitude > 0.001 then
			rocket.CFrame = CFrame.lookAt(pos, pos + dir)
		end

		task.wait(0.03)
	end

	skipConn:Disconnect()
	rocket:Destroy()

	spawnExplosion(target)

	local msg
	if data.destroyed then
		msg = string.format("%s уничтожил цель #%d", data.shooterName, data.targetSlotIndex or 1)
	else
		msg = string.format("%s атаковал остров %d", data.shooterName, data.targetPlotId or 1)
	end

	local ok, HudManager = pcall(require, script.Parent:WaitForChild("HudManager"))
	if ok and HudManager then
		HudManager.ShowNotification(msg, data.destroyed and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 180, 40))
	end
end

return RocketAnim