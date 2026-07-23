-- init.client.luau - Rojo client entry point
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Remotes    = require(sharedFolder:WaitForChild("Remotes"))
local HudManager = require(script:WaitForChild("HudManager"))
local RocketAnim = require(script:WaitForChild("RocketAnim"))
local VisualFX   = require(script:WaitForChild("VisualFX"))
local PriceTags  = require(script:WaitForChild("PriceTags"))
local Sprint     = require(script:WaitForChild("Sprint"))

-- Получение настроек анимации
local getAnimFn = Remotes.Get("GetAnimSetting")
local animEnabled = true
pcall(function()
	animEnabled = getAnimFn:InvokeServer()
end)

-- Инициализация HUD и ценников (видны только на своём острове)
HudManager.Init(animEnabled)
PriceTags.Init()

-- Спринт на Shift: персонаж бежит немного быстрее
Sprint.Init()

-- Камера стрелка следует за запущенной сервером ракетой
local rocketFollow = Remotes.Get("RocketFollow")
rocketFollow.OnClientEvent:Connect(function(rocketModel)
	RocketAnim.Follow(rocketModel, HudManager.IsAnimEnabled())
end)

-- Прилёт ракеты: взрыв + звук + уведомление (у всех игроков)
local rocketImpact = Remotes.Get("RocketImpact")
rocketImpact.OnClientEvent:Connect(function(data)
	RocketAnim.Impact(data)
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
