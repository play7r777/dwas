-- init.server.luau — точка входа сервера
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes       = require(ReplicatedStorage.Shared.Remotes)
local DataManager   = require(script.Parent.DataManager)
local PlotManager   = require(script.Parent.PlotManager)
local FarmManager   = require(script.Parent.FarmManager)
local RocketManager = require(script.Parent.RocketManager)

-- 1. Создаём все RemoteEvents / RemoteFunctions
Remotes.Init()

-- 2. Инициализируем менеджеры по порядку
DataManager.Init()
PlotManager.Init()
FarmManager.Init()
RocketManager.Init()

print("[Server] Tycoon Rocket Battle — сервер запущен!")
