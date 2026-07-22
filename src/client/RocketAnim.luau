-- RocketAnim.luau - настоящая ракета, дуговой полёт, кинокамера запустившего игрока
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Config            = require(sharedFolder:WaitForChild("Config"))

local player = Players.LocalPlayer

local RocketAnim = {}

local function spawnExplosion(pos)
	-- Настоящий Explosion (без урона игрокам) + вспышка/кольцо/дым.
	local explosion = Instance.new("Explosion")
	explosion.Position = pos
	explosion.BlastRadius = 24
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace

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

	for _ = 1, 8 do
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

-- Строит летящую ракету: невидимый корень (нос смотрит по локальной -Z), корпус,
-- конусный нос, полоса, стабилизаторы и дымный след.
local function buildFlyingRocket(origin)
	local model = Instance.new("Model")
	model.Name = "FlyingRocket"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CFrame = CFrame.new(origin)
	root.Parent = model
	model.PrimaryPart = root

	local function piece(name, size, localCF, color, material, shape)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = root.CFrame * localCF
		part.Color = color
		part.Material = material
		part.Anchored = true
		part.CanCollide = false
		if shape then part.Shape = shape end
		part.Parent = model
		return part
	end

	-- Корпус (длина вдоль локальной Z)
	piece("Body", Vector3.new(6, 1.8, 1.8), CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(232, 236, 238), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	piece("Stripe", Vector3.new(1.2, 1.85, 1.85), CFrame.new(0, 0, 0.6) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(220, 70, 60), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)

	-- Конусный нос спереди (-Z), сборка из сужающихся дисков
	for i = 1, 3 do
		local d = 1.8 * (1 - i * 0.28)
		piece("Nose_" .. i, Vector3.new(0.9, math.max(d, 0.3), math.max(d, 0.3)), CFrame.new(0, 0, -3 - (i - 0.5) * 0.9) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(210, 70, 60), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end

	-- Стабилизаторы сзади (+Z)
	for i = 1, 3 do
		local a = math.rad(i * 120)
		local fin = Instance.new("WedgePart")
		fin.Name = "Fin_" .. i
		fin.Size = Vector3.new(0.3, 1.6, 1.6)
		fin.Color = Color3.fromRGB(220, 70, 60)
		fin.Material = Enum.Material.SmoothPlastic
		fin.Anchored = true
		fin.CanCollide = false
		fin.CFrame = root.CFrame * CFrame.new(math.cos(a) * 1.1, math.sin(a) * 1.1, 2.4) * CFrame.Angles(0, 0, a)
		fin.Parent = model
	end

	-- Дымный след
	local front = Instance.new("Attachment")
	front.Position = Vector3.new(0, 0, -2)
	front.Parent = root
	local back = Instance.new("Attachment")
	back.Position = Vector3.new(0, 0, 3)
	back.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = front
	trail.Attachment1 = back
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 205, 70), Color3.fromRGB(235, 75, 35))
	trail.Lifetime = 0.35
	trail.MinLength = 0.4
	trail.Parent = root

	local light = Instance.new("PointLight")
	light.Brightness = 8
	light.Range = 20
	light.Color = Color3.fromRGB(255, 120, 20)
	light.Parent = root

	model.Parent = workspace
	return model
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
	local isShooter = data.shooterUserId ~= nil and data.shooterUserId == player.UserId

	local function notifyResult()
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

	if not animEnabled then
		spawnExplosion(target)
		notifyResult()
		return
	end

	local rocketModel = buildFlyingRocket(origin)

	-- Камера запустившего игрока летит вместе с ракетой.
	local camera = workspace.CurrentCamera
	local prevType, prevSubject
	if isShooter and camera then
		prevType = camera.CameraType
		prevSubject = camera.CameraSubject
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local skipped = false
	local skipConn
	skipConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			skipped = true
		end
	end)

	local dist = (target - origin).Magnitude
	local duration = math.clamp(dist / Config.ROCKET_SPEED, 0.9, Config.ROCKET_ANIM_TIME)
	local steps = math.ceil(duration / 0.03)

	for i = 1, steps do
		if skipped then break end
		local t = i / steps
		local pos = arcPos(origin, target, t)

		local nextT = math.min(t + 0.04, 1)
		local nextPos = arcPos(origin, target, nextT)
		local dir = (nextPos - pos)
		if dir.Magnitude > 0.001 then
			rocketModel:PivotTo(CFrame.lookAt(pos, pos + dir))
		end

		if isShooter and camera then
			local look = dir.Magnitude > 0.001 and dir.Unit or Vector3.new(0, 0, -1)
			if t < 0.72 then
				-- Погоня сзади-сбоку за ракетой
				local side = look:Cross(Vector3.new(0, 1, 0))
				local camPos = pos - look * 24 + Vector3.new(0, 10, 0) + side * 6
				camera.CFrame = CFrame.lookAt(camPos, pos + look * 6)
			else
				-- Камера отдаляется и переходит в вид СВЕРХУ на точку взрыва
				local a = (t - 0.72) / 0.28
				local height = 45 + a * 70
				local topPos = target + Vector3.new(0, height, 0.05)
				local chaseSide = look:Cross(Vector3.new(0, 1, 0))
				local chasePos = pos - look * 24 + Vector3.new(0, 10, 0) + chaseSide * 6
				local camPos = chasePos:Lerp(topPos, a)
				local lookTarget = (pos):Lerp(target, a)
				camera.CFrame = CFrame.lookAt(camPos, lookTarget)
			end
		end

		task.wait(0.03)
	end

	skipConn:Disconnect()
	rocketModel:Destroy()

	spawnExplosion(target)

	-- Держим вид сверху на взрыв, затем плавно возвращаем управление игроку.
	if isShooter and camera then
		local topView = CFrame.lookAt(target + Vector3.new(0, 110, 0.05), target)
		camera.CFrame = topView
		task.wait(0.9)

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local endCF = CFrame.lookAt(hrp.Position + Vector3.new(0, 6, 14), hrp.Position)
			local blendSteps = 14
			for s = 1, blendSteps do
				if camera.CameraType ~= Enum.CameraType.Scriptable then break end
				camera.CFrame = topView:Lerp(endCF, s / blendSteps)
				RunService.RenderStepped:Wait()
			end
		end

		camera.CameraType = prevType or Enum.CameraType.Custom
		if prevSubject then camera.CameraSubject = prevSubject end
	end

	notifyResult()
end

return RocketAnim
