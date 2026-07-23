-- RocketFactory.luau — единая геометрия ракеты.
--
-- И стенд на базе (PlotManager), и летящая ракета (RocketManager) собираются
-- ЭТОЙ функцией — поэтому ракета в полёте выглядит ТОЧНО так же, как на базе:
-- то же поколение (Mark I..IV), тот же цвет команды, те же детали.
local RocketFactory = {}

local GOLD = Color3.fromRGB(255, 199, 70)

-- Поколения ракет: внешний вид меняется каждые 5 уровней прокачки.
RocketFactory.MARK_SPECS = {
	[1] = { -- классическая белая ракета
		dia = 4.6, bodyH = 15, noseH = 4.5, finH = 6.4, boosters = 0, rings = 0,
		bodyColor = Color3.fromRGB(236, 239, 241), bodyMat = Enum.Material.SmoothPlastic,
	},
	[2] = { -- с двумя боковыми ускорителями
		dia = 5.0, bodyH = 18, noseH = 5.2, finH = 7.2, boosters = 2, rings = 1,
		bodyColor = Color3.fromRGB(240, 243, 244), bodyMat = Enum.Material.SmoothPlastic,
	},
	[3] = { -- тяжёлая тёмная с неоновыми кольцами
		dia = 5.6, bodyH = 21, noseH = 5.8, finH = 8, boosters = 0, rings = 3,
		bodyColor = Color3.fromRGB(60, 64, 72), bodyMat = Enum.Material.Metal, dark = true,
	},
	[4] = { -- флагман: три ускорителя, золотой нос и неоновое гало
		dia = 6.0, bodyH = 23, noseH = 6.4, finH = 9, boosters = 3, rings = 2,
		bodyColor = Color3.fromRGB(245, 246, 248), bodyMat = Enum.Material.SmoothPlastic,
		goldAccent = true, halo = true,
	},
}

function RocketFactory.GetSpec(mark)
	return RocketFactory.MARK_SPECS[mark] or RocketFactory.MARK_SPECS[1]
end

-- Полная высота ракеты (от низа сопла до кончика шпиля) с учётом масштаба.
function RocketFactory.GetHeight(mark, scale)
	local spec = RocketFactory.GetSpec(mark)
	return (3.4 + spec.bodyH + spec.noseH + 2.0) * (scale or 1)
end

-- Строит ракету вдоль +Y базового CFrame: низ сопла на локальном y = 0.
-- scale — общий масштаб (1 для стенда, ~0.5 для летящей).
-- collideBody = true делает корпус коллизионным (только для стенда).
-- Возвращает: parts (для скрытия при перезарядке), window, height.
function RocketFactory.Build(model, baseCF, teamColor, mark, scale, collideBody)
	local spec = RocketFactory.GetSpec(mark)
	local s = scale or 1
	local accent = spec.goldAccent and GOLD or teamColor
	local parts = {}

	local function newPart(name, size, cf, color, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.Size = size
		part.CFrame = cf
		part.Color = color
		part.Material = material
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end

	-- Вертикальный цилиндр в локальных координатах ракеты (ось = +Y базы).
	local function cyl(name, height, diameter, x, y, z, color, material)
		local part = newPart(name, Vector3.new(height * s, diameter * s, diameter * s), baseCF * CFrame.new(x * s, y * s, z * s) * CFrame.Angles(0, 0, math.rad(90)), color, material)
		part.Shape = Enum.PartType.Cylinder
		table.insert(parts, part)
		return part
	end

	-- Двигательный отсек: сопло, юбка и тёплое свечение
	cyl("Nozzle", 2.2, spec.dia * 0.62, 0, 1.1, 0, Color3.fromRGB(40, 42, 46), Enum.Material.Metal)
	cyl("Skirt", 1.6, spec.dia * 0.92, 0, 2.6, 0, Color3.fromRGB(70, 74, 80), Enum.Material.Metal)
	cyl("EngineGlow", 0.5, spec.dia * 0.5, 0, 0.35, 0, Color3.fromRGB(255, 170, 60), Enum.Material.Neon)

	-- Корпус
	local bodyCenterY = 3.4 + spec.bodyH / 2
	local body = cyl("Body", spec.bodyH, spec.dia, 0, bodyCenterY, 0, spec.bodyColor, spec.bodyMat)
	body.CanCollide = collideBody == true

	-- Полоса команды + неоновые кольца прокачанных версий
	cyl("Stripe", 2.0, spec.dia * 1.04, 0, bodyCenterY + spec.bodyH * 0.18, 0, accent, Enum.Material.SmoothPlastic)
	for r = 1, (spec.rings or 0) do
		cyl("Ring_" .. r, 0.7, spec.dia * 1.06, 0, 3.4 + spec.bodyH * r / (spec.rings + 1), 0, spec.dark and teamColor or accent, Enum.Material.Neon)
	end

	-- Иллюминатор (смотрит по локальному +Z)
	local window = newPart("Window", Vector3.new(0.5 * s, 1.6 * s, 1.6 * s), baseCF * CFrame.new(0, (bodyCenterY + spec.bodyH * 0.32) * s, (spec.dia / 2 + 0.05) * s) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(125, 214, 238), Enum.Material.Glass)
	window.Shape = Enum.PartType.Cylinder

	-- Конусообразный нос из сужающихся секций + шпиль
	local noseBottom = 3.4 + spec.bodyH
	local noseSegs = 5
	for i = 1, noseSegs do
		local d = spec.dia * (1 - (i / noseSegs) * 0.82)
		local segH = spec.noseH / noseSegs
		cyl("Nose_" .. i, segH, math.max(d, 0.6), 0, noseBottom + (i - 0.5) * segH, 0, accent, Enum.Material.SmoothPlastic)
	end
	local tipY = noseBottom + spec.noseH
	local tip = newPart("Tip", Vector3.new(0.5 * s, 2.2 * s, 0.5 * s), baseCF * CFrame.new(0, (tipY + 0.9) * s, 0), Color3.fromRGB(226, 228, 232), Enum.Material.Metal)
	table.insert(parts, tip)

	-- Неоновое гало флагмана
	if spec.halo then
		local halo = cyl("Halo", 0.4, spec.dia + 3, 0, tipY - 1, 0, accent, Enum.Material.Neon)
		halo.Transparency = 0.3
	end

	-- Боковые ускорители
	if (spec.boosters or 0) > 0 then
		local boosterD = spec.dia * 0.36
		local boosterH = spec.bodyH * 0.55
		for i = 1, spec.boosters do
			local a = math.rad(360 / spec.boosters * i + 90)
			local bx = math.cos(a) * (spec.dia / 2 + boosterD / 2 + 0.1)
			local bz = math.sin(a) * (spec.dia / 2 + boosterD / 2 + 0.1)
			cyl("Booster_" .. i, boosterH, boosterD, bx, 2.0 + boosterH / 2, bz, spec.bodyColor, spec.bodyMat)
			cyl("BoosterNose_" .. i, 1.4, boosterD * 0.55, bx, 2.0 + boosterH + 0.7, bz, accent, Enum.Material.SmoothPlastic)
		end
	end

	-- Стабилизаторы
	for i = 1, 4 do
		local a = math.rad(i * 90 + 45)
		local dist = spec.dia / 2 + 0.9
		local fin = Instance.new("WedgePart")
		fin.Name = "Fin_" .. i
		fin.Anchored = true
		fin.CanCollide = false
		fin.Size = Vector3.new(0.7 * s, spec.finH * s, 3.6 * s)
		fin.CFrame = baseCF * CFrame.new(math.cos(a) * dist * s, (spec.finH / 2 + 0.4) * s, math.sin(a) * dist * s) * CFrame.Angles(0, -a + math.rad(90), 0)
		fin.Color = accent
		fin.Material = Enum.Material.SmoothPlastic
		fin.TopSurface = Enum.SurfaceType.Smooth
		fin.BottomSurface = Enum.SurfaceType.Smooth
		fin.Parent = model
		table.insert(parts, fin)
	end

	return parts, window, RocketFactory.GetHeight(mark, s)
end

return RocketFactory
