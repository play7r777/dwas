-- init.client.luau — точка входа клиента
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players= game:GetService("Players")
local player            = Players.LocalPlayer

-- Подождём пока сервер создаст RemoteEvents
local Remotes    = require(ReplicatedStorage.Shared.Remotes)
local HudManager = require(script.Parent.HudManager)
local RocketAnim = require(script.Parent.RocketAnim)

-- Получаем начальную настройку анимации от сервера
local getAnimFn  = Remotes.Get("GetAnimSetting")
local animEnabled = getAnimFn:InvokeServer()

-- Инициализируем HUD (передаём animEnabled)
HudManager.Init(animEnabled)

-- Слушаем входящие события
local rocketFired = Remotes.Get("RocketFired")
rocketFired.OnClientEvent:Connect(function(data)
	RocketAnim.Play(data, HudManager.IsAnimEnabled())
end)

local updateData = Remotes.Get("UpdateData")
updateData.OnClientEvent:Connect(function(data)
	HudManager.UpdateData(data)
end)

local farmHit = Remotes.Get("FarmHit")
farmHit.OnClientEvent:Connect(function(plotId, hp, maxHp)
	-- Можно добавить эффект попадания
end)

local farmDestroyed = Remotes.Get("FarmDestroyed")
farmDestroyed.OnClientEvent:Connect(function(plotId)
	HudManager.ShowNotification("💥 Ферма на участке " .. plotId .. " уничтожена!", Color3.fromRGB(220,80,80))
end)

local farmRebuilt = Remotes.Get("FarmRebuilt")
farmRebuilt.OnClientEvent:Connect(function(plotId)
	HudManager.ShowNotification("🏗️ Ферма на участке " .. plotId .. " восстановлена!", Color3.fromRGB(80,220,80))
end)
print("Hello world, from client!")
