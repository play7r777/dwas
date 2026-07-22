-- RocketAnim.luau - кинокамера стрелка следует за СЕРВЕРНОЙ ракетой; взрыв + звук при прилёте
local Players           = game:GetService("Players")
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

	-- Звук взрыва в точке удара.
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://5801257793"
	sound.Volume = 1
	sound.RollOffMaxDistance = 400
	sound.RollOffMinDistance = 20
	sound.Parent = ball
	sound:Play()

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

-- Камера стрелка ведёт СЕРВЕРНУЮ ракету (её инстанс приходит по RocketFollow),
-- пока сервер её не уничтожит; затем плавно возвращает управление игроку.
function RocketAnim.Follow(rocketModel, animEnabled)
	if not animEnabled then return end
	if typeof(rocketModel) ~= "Instance" then return end
	local root = rocketModel.PrimaryPart or rocketModel:FindFirstChild("Root")
	if not root then return end

	local camera = workspace.CurrentCamera
	if not camera then return end
	local prevType = camera.CameraType
	local prevSubject = camera.CameraSubject
	camera.CameraType = Enum.CameraType.Scriptable

	task.spawn(function()
		local lastPos = root.Position
		local startT = os.clock()
		while rocketModel.Parent and root.Parent and (os.clock() - startT) < (Config.ROCKET_ANIM_TIME + 3) do
			local pos = root.Position
			local look = root.CFrame.LookVector
			if look.Magnitude < 0.001 then look = Vector3.new(0, 0, -1) end
			local side = look:Cross(Vector3.new(0, 1, 0))
			local camPos = pos - look * 24 + Vector3.new(0, 10, 0) + side * 6
			camera.CFrame = CFrame.lookAt(camPos, pos + look * 6)
			lastPos = pos
			RunService.RenderStepped:Wait()
		end

		-- Вид сверху на точку взрыва, затем плавный возврат к персонажу.
		local topView = CFrame.lookAt(lastPos + Vector3.new(0, 95, 0.05), lastPos)
		camera.CFrame = topView
		task.wait(0.8)

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local endCF = CFrame.lookAt(hrp.Position + Vector3.new(0, 6, 14), hrp.Position)
			for s = 1, 14 do
				if camera.CameraType ~= Enum.CameraType.Scriptable then break end
				camera.CFrame = topView:Lerp(endCF, s / 14)
				RunService.RenderStepped:Wait()
			end
		end

		camera.CameraType = prevType or Enum.CameraType.Custom
		if prevSubject then camera.CameraSubject = prevSubject end
	end)
end

-- Прилёт: взрыв + звук в точке удара и уведомление о результате.
function RocketAnim.Impact(data)
	if not data or not data.pos then return end
	spawnExplosion(data.pos)

	local msg
	if data.destroyed then
		msg = string.format("%s уничтожил цель на острове %d", data.shooterName or "Игрок", data.targetPlotId or 0)
	else
		msg = string.format("%s атаковал остров %d", data.shooterName or "Игрок", data.targetPlotId or 0)
	end
	local ok, HudManager = pcall(require, script.Parent:WaitForChild("HudManager"))
	if ok and HudManager then
		HudManager.ShowNotification(msg, data.destroyed and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 180, 40))
	end
end

return RocketAnim
