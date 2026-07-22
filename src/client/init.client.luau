-- init.client.luau - Rojo client entry point
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Remotes    = require(sharedFolder:WaitForChild("Remotes"))
local HudManager = require(script:WaitForChild("HudManager"))
local RocketAnim = require(script:WaitForChild("RocketAnim"))
local VisualFX   = require(script:WaitForChild("VisualFX"))

-- Получение настроек анимации
local getAnimFn = Remotes.Get("GetAnimSetting")
local animEnabled = true
pcall(function()
	animEnabled = getAnimFn:InvokeServer()
end)

-- Инициализация HUD
HudManager.Init(animEnabled)

-- Слушатели сетевых событий
local rocketFired = Remotes.Get("RocketFired")
rocketFired.OnClientEvent:Connect(function(data)
	RocketAnim.Play(data, HudManager.IsAnimEnabled())
end)

local updateData = Remotes.Get("UpdateData")
updateData.OnClientEvent:Connect(function(data)
	HudManager.UpdateData(data)
end)

local rocketState = Remotes.Get("RocketStateChanged")
rocketState.OnClientEvent:Connect(function(data)
	HudManager.UpdateRocketState(data)
end)

local notify = Remotes.Get("Notify")
notify.OnClientEvent:Connect(function(message, kind)
	local colors = {
		success = Color3.fromRGB(98, 220, 144),
		error = Color3.fromRGB(239, 117, 91),
		info = Color3.fromRGB(235, 239, 241),
	}
	HudManager.ShowNotification(message, colors[kind] or colors.info)
end)

local spawnIncomeFX = Remotes.Get("SpawnIncomeFX")
spawnIncomeFX.OnClientEvent:Connect(function(pos, amount)
	VisualFX.SpawnIncome(pos, amount)
end)

print("[Client] Rocket Islands client connected")
