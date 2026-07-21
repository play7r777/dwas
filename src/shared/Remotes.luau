-- Remotes.luau — единая точка создания/получения RemoteEvents
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

-- Список всех событий
local EVENT_NAMES = {
	"BuyRocket",        -- клиент → сервер: купить ракету
	"LaunchRocket",     -- клиент → сервер: атаковать участок targetPlotId
	"RocketFired",      -- сервер → все клиенты: воспроизвести анимацию
	"UpdateData",       -- сервер → клиент: обновить деньги иракеты
	"UpgradeFarm",      -- клиент → сервер: улучшить своюферму
	"FarmHit",          -- сервер → все клиенты: ферма получила урон
	"FarmDestroyed",    -- сервер → все клиенты: ферма уничтожена
	"FarmRebuilt",      -- сервер → все клиенты: ферма восстановлена
	"SetAnimSetting",   -- клиент → сервер: сохранить настройку анимации
	"GetAnimSetting",   -- клиент → сервер (RemoteFunction): получить настройку
}

local FUNCTION_NAMES = {
	"GetAnimSetting",   -- RemoteFunction: вернуть текущую настройку анимации
	"GetPlotInfo",      -- RemoteFunction: вернуть данные участка по ID
}

-- Инициализация (вызывается на СЕРВЕРЕ)
function Remotes.Init()
	local folder = Instance.new("Folder")
	folder.Name = "GameRemotes"
	folder.Parent = ReplicatedStorage

	for _, name in ipairs(EVENT_NAMES) do
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = folderend

	for _, name in ipairs(FUNCTION_NAMES) do
		local rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = folder
	end
end

-- Получение события (вызывается на клиенте и сервере после Init)
function Remotes.Get(name)
	local folder = ReplicatedStorage:WaitForChild("GameRemotes",10)
	if not folder then
		error("[Remotes] GameRemotes folder not found!")
	end
	return folder:WaitForChild(name, 10)
end

return Remotes