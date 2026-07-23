-- Sprint.luau — ускорение на Shift: персонаж бежит немного быстрее,
-- камера слегка расширяет FOV для ощущения скорости.
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Config = require(sharedFolder:WaitForChild("Config"))

local player = Players.LocalPlayer

local Sprint = {}

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function isShiftDown()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function apply()
	local hum = getHumanoid()
	if not hum or hum.Health <= 0 then return end
	-- WalkSpeed == 0 означает заморозку (режим прицеливания HudManager) — не трогаем.
	if hum.WalkSpeed == 0 then return end

	local sprinting = isShiftDown()
	hum.WalkSpeed = sprinting and Config.SPRINT_SPEED or Config.WALK_SPEED

	local camera = workspace.CurrentCamera
	if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
		TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = sprinting and 74 or 70,
		}):Play()
	end
end

function Sprint.Init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			apply()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			apply()
		end
	end)

	player.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 5)
		if hum then
			hum.WalkSpeed = Config.WALK_SPEED
		end
	end)
end

return Sprint
