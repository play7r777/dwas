-- PriceTags.luau — ценники (BillboardGui "PriceTag") видны ТОЛЬКО на своём острове
-- и ТОЛЬКО когда игрок стоит рядом с кнопкой. Появление и исчезновение ПЛАВНЫЕ:
-- подходишь — текст мягко проявляется, отходишь — мягко тает.
-- Сервер выставляет атрибут Unlocked и держит Enabled = false; клиент управляет
-- прозрачностью текста по владению + дистанции.
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local PriceTags = {}

local SHOW_DISTANCE = 22
local FADE_STEP = 0.22 -- доля пути к цели за тик (~0.45с на полный фейд)

-- Кэш ценников: { gui, part, label, plotId, alpha }. Пересобираем редко,
-- дистанцию и фейд обсчитываем часто.
local cache = {}

local function rebuildCache()
	local found = {}
	for _, folder in ipairs(workspace:GetChildren()) do
		local pid = folder:GetAttribute("PlotId")
		if pid ~= nil then
			for _, gui in ipairs(folder:GetDescendants()) do
				if gui:IsA("BillboardGui") and gui.Name == "PriceTag" then
					local part = gui.Parent
					local label = gui:FindFirstChild("PriceLabel")
					if part and part:IsA("BasePart") and label then
						-- Сохраняем прежний альфа-прогресс, если ценник уже был в кэше.
						local alpha = 1
						for _, old in ipairs(cache) do
							if old.gui == gui then
								alpha = old.alpha
								break
							end
						end
						table.insert(found, { gui = gui, part = part, label = label, plotId = pid, alpha = alpha })
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
			local wantVisible = false
			if myId ~= nil and entry.plotId == myId and hrp and entry.gui:GetAttribute("Unlocked") == true then
				wantVisible = (entry.part.Position - hrp.Position).Magnitude < SHOW_DISTANCE
			end

			-- Плавный фейд: alpha 0 = полностью виден, 1 = полностью скрыт.
			local target = wantVisible and 0 or 1
			entry.alpha += (target - entry.alpha) * FADE_STEP
			if math.abs(entry.alpha - target) < 0.02 then
				entry.alpha = target
			end

			entry.label.TextTransparency = entry.alpha
			entry.label.TextStrokeTransparency = 0.35 + 0.65 * entry.alpha
			entry.gui.Enabled = entry.alpha < 0.99
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

	-- Частый тик: дистанция + плавный фейд.
	task.spawn(function()
		while true do
			refresh()
			task.wait(0.08)
		end
	end)
end

return PriceTags
