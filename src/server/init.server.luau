-- init.server.luau — Точка входа сервера для Rojo
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Remotes       = require(sharedFolder:WaitForChild("Remotes"))
local DataManager   = require(script:WaitForChild("DataManager"))
local PlotManager   = require(script:WaitForChild("PlotManager"))
local FarmManager   = require(script:WaitForChild("FarmManager"))
local RocketManager = require(script:WaitForChild("RocketManager"))

-- 1. Инициализация сетевых событий
Remotes.Init()

-- 2. Инициализация менеджеров
DataManager.Init()
PlotManager.Init()
FarmManager.Init()
RocketManager.Init()

print("==================================================")
print("[Server] Tycoon Rocket Battle запущен через Rojo!")
print("==================================================")
