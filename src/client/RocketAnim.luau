-- RocketAnim.luau - кинокамера стрелка следует за СЕРВЕРНОЙ ракетой; взрыв с
-- настоящим чёрным дымом при прилёте. ЛКМ во время полёта пропускает анимацию
-- (камера сразу возвращается к персонажу, ракета долетает сама).
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Config            = require(sharedFolder:WaitForChild("Config"))

local player = Players.LocalPlayer

local RocketAnim = {}

local SMOKE_TEXTURE = "rbxassetid://241594419"

local function spawnExplosion(pos)
	-- Настоящий Explosion (без урона игрокам) + вспышка и ударное кольцо.
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

	-- НАСТОЯЩИЙ чёрный дым: клубящиеся частицы вместо серых шаров-«кругов».
	local smokeHolder = Instance.new("Part")
	smokeHolder.Size = Vector3.new(1, 1, 1)
	smokeHolder.Position = pos + Vector3.new(0, 2, 0)
	smokeHolder.Anchored = true
	smokeHolder.CanCollide = false
	smokeHolder.Transparency = 1
	smokeHolder.Parent = workspace

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ImpactSmoke"
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 28, 30)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(52, 52, 55)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(96, 96, 100)),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 5),
		NumberSequenceKeypoint.new(0.35, 10),
		NumberSequenceKeypoint.new(1, 16),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.4, 2.6)
	smoke.Speed = NumberRange.new(10, 20)
	smoke.SpreadAngle = Vector2.new(85, 85)
	smoke.Acceleration = Vector3.new(0, 7, 0)
	smoke.Drag = 1.2
	smoke.Rotation = NumberRange.new(-180, 180)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Rate = 0
	smoke.Parent = smokeHolder

	-- Короткая огненная вспышка внутри дыма.
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "ImpactFire"
	fire.Texture = SMOKE_TEXTURE
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 150, 40), Color3.fromRGB(200, 60, 20))
	fire.LightEmission = 0.9
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 7),
	})
	fire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	fire.Lifetime = NumberRange.new(0.3, 0.6)
	fire.Speed = NumberRange.new(14, 26)
	fire.SpreadAngle = Vector2.new(70, 70)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.Rate = 0
	fire.Parent = smokeHolder

	smoke:Emit(45)
	fire:Emit(25)
	Debris:AddItem(smokeHolder, 4.5)
end

-- Камера стрелка ведёт СЕРВЕРНУЮ ракету (её инстанс приходит по RocketFollow),
-- пока сервер её не уничтожит; затем плавно возвращает управление игроку.
-- Клик ЛКМ (или тап) в любой момент ПРОПУСКАЕТ анимацию: камера сразу к игроку.
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
		local skipped = false
		local skipConn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				skipped = true
			end
		end)

		local lastPos = root.Position
		local startT = os.clock()
		-- Летящая ракета крупнее прежней — камера чуть дальше и выше.
		while rocketModel.Parent and root.Parent and not skipped and (os.clock() - startT) < (Config.ROCKET_ANIM_TIME + 3) do
			local pos = root.Position
			local look = root.CFrame.LookVector
			if look.Magnitude < 0.001 then look = Vector3.new(0, 0, -1) end
			local side = look:Cross(Vector3.new(0, 1, 0))
			local camPos = pos - look * 30 + Vector3.new(0, 12, 0) + side * 7
			camera.CFrame = CFrame.lookAt(camPos, pos + look * 6)
			lastPos = pos
			RunService.RenderStepped:Wait()
		end

		skipConn:Disconnect()

		if skipped then
			-- Пропуск: мгновенно возвращаем обычную камеру (ракета долетит сама).
			camera.CameraType = prevType or Enum.CameraType.Custom
			if prevSubject then camera.CameraSubject = prevSubject end
			return
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

-- Прилёт: взрыв + дым + звук в точке удара (без текстовых уведомлений).
function RocketAnim.Impact(data)
	if not data or not data.pos then return end
	spawnExplosion(data.pos)
end

return RocketAnim
