-- Remotes.luau - shared RemoteEvent and RemoteFunction registry
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local EVENT_NAMES = {
	"BuyLauncher",
	"BuyBuildingSlot",
	"LaunchRocket",
	"RocketFired",
	"UpdateData",
	"RocketStateChanged",
	"BuildingStateChanged",
	"SpawnIncomeFX",
	"Notify",
	"SetAnimSetting",
}

local FUNCTION_NAMES = {
	"GetAnimSetting",      -- RemoteFunction: получить настройку анимации
	"GetGameInfo",         -- RemoteFunction: получить текущее состояние всех островов и зданий
}

function Remotes.Init()
	local folder = ReplicatedStorage:FindFirstChild("GameRemotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GameRemotes"
		folder.Parent = ReplicatedStorage
	end

	for _, name in ipairs(EVENT_NAMES) do
		if not folder:FindFirstChild(name) then
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = folder
		end
	end

	for _, name in ipairs(FUNCTION_NAMES) do
		if not folder:FindFirstChild(name) then
			local rf = Instance.new("RemoteFunction")
			rf.Name = name
			rf.Parent = folder
		end
	end
end

function Remotes.Get(name)
	local folder = ReplicatedStorage:WaitForChild("GameRemotes", 10)
	if not folder then
		error("[Remotes] GameRemotes folder not found!")
	end
	return folder:WaitForChild(name, 10)
end

return Remotes