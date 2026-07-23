-- PriceTags.luau — ценники (BillboardGui "PriceTag") видны ТОЛЬКО на своём острове
-- и ТОЛЬКО когда игрок стоит рядом с кнопкой (меньше текста на экране: подошёл —
-- цена появилась, отошёл — исчезла). Сервер выставляет атрибут Unlocked и держит
-- Enabled = false для всех; клиент включает Enabled по владению + дистанции.
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local PriceTags = {}

local SHOW_DISTANCE = 22

-- Кэш ценников: { gui, part, plotId }. Пересобираем редко, дистанцию чекаем часто.
local cache = {}

local function rebuildCache()
	local found = {}
	for _, folder in ipairs(workspace:GetChildren()) do
		local pid = folder:GetAttribute("PlotId")
		if pid ~= nil then
			for _, gui in ipairs(folder:GetDescendants()) do
				if gui:IsA("BillboardGui") and gui.Name == "PriceTag" then
					local part = gui.Parent
					if part and part:IsA("BasePart") then
						table.insert(found, { gui = gui, part = part, plotId = pid })
					end
				end
			end
		end
	end
	cache = found
end

local function refresh()
	local myId = player:GetAttribute("PlotId")
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	for _, entry in ipairs(cache) do
		if entry.gui.Parent then
			local show = false
			if myId ~= nil and entry.plotId == myId and hrp and entry.gui:GetAttribute("Unlocked") == true then
				show = (entry.part.Position - hrp.Position).Magnitude < SHOW_DISTANCE
			end
			entry.gui.Enabled = show
		end
	end
end

function PriceTags.Init()
	rebuildCache()
	player:GetAttributeChangedSignal("PlotId"):Connect(refresh)

	-- Новые ценники появляются при покупках — кэш пересобираем раз в 2с.
	task.spawn(function()
		while true do
			task.wait(2)
			rebuildCache()
		end
	end)

	-- Дистанцию проверяем часто — ценник «зажигается», когда подходишь вплотную.
	task.spawn(function()
		while true do
			refresh()
			task.wait(0.15)
		end
	end)
end

return PriceTags
