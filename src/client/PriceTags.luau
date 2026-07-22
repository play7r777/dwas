-- PriceTags.luau - ценники (BillboardGui "PriceTag") видны ТОЛЬКО на своём острове.
-- Сервер выставляет на ценнике атрибут Unlocked (открыт ли слот) и держит его
-- Enabled = false для всех. Клиент включает Enabled лишь для ценников своего плота.
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local PriceTags = {}

local function refresh()
	local myId = player:GetAttribute("PlotId")
	for _, folder in ipairs(workspace:GetChildren()) do
		local pid = folder:GetAttribute("PlotId")
		if pid ~= nil then
			local mine = (myId ~= nil and pid == myId)
			for _, gui in ipairs(folder:GetDescendants()) do
				if gui:IsA("BillboardGui") and gui.Name == "PriceTag" then
					gui.Enabled = mine and (gui:GetAttribute("Unlocked") == true)
				end
			end
		end
	end
end

function PriceTags.Init()
	player:GetAttributeChangedSignal("PlotId"):Connect(refresh)
	-- Регулярно обновляем: атрибуты реплицируются, новые ценники появляются при покупке.
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
end

return PriceTags
