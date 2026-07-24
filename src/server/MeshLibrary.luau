-- MeshLibrary.luau — поиск импортированных Blender-мешей БЕЗ переименований.
--
-- Studio → Import 3D называет результат ИМЕНЕМ ФАЙЛА (cafe_lvl1, palm_a,
-- main_island, air_defense_base, ...). Раньше код требовал красивые имена
-- (Level1, PalmA, MainIsland) и отдельную папку под каждый ассет — теперь
-- ничего переименовывать не нужно: ищем по СПИСКУ имён-кандидатов (и красивое,
-- и имя файла, без учёта регистра) в трёх местах по порядку:
--   1) «родная» папка ассета (CafeMeshes, IslandMeshes, ...) — старый способ;
--   2) ОБЩАЯ папка ReplicatedStorage/Meshes — кидай всё импортированное туда;
--   3) прямо в ReplicatedStorage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshLibrary = {}

local COMMON_FOLDER = "Meshes"

local function findIn(container, candidates)
	if not container then return nil end
	-- Точное совпадение
	for _, name in ipairs(candidates) do
		local inst = container:FindFirstChild(name)
		if inst then return inst end
	end
	-- Без учёта регистра (Import 3D/юзер могли поменять регистр)
	local wanted = {}
	for _, name in ipairs(candidates) do
		wanted[string.lower(name)] = true
	end
	for _, child in ipairs(container:GetChildren()) do
		if wanted[string.lower(child.Name)] then
			return child
		end
	end
	return nil
end

-- Ищет инстанс по списку имён: сначала в папке folderName, потом в общей
-- папке Meshes, потом прямо в ReplicatedStorage. Возвращает Instance или nil.
function MeshLibrary.Find(folderName, candidates)
	local inst = findIn(ReplicatedStorage:FindFirstChild(folderName or ""), candidates)
	if inst then return inst end
	inst = findIn(ReplicatedStorage:FindFirstChild(COMMON_FOLDER), candidates)
	if inst then return inst end
	return findIn(ReplicatedStorage, candidates)
end

-- Достаёт BasePart из найденного (Import 3D мог создать голый MeshPart или
-- Model-обёртку). Для мульти-материальных моделей отдаёт КЛОН всей модели —
-- вызывающий сам решает, что с ней делать.
function MeshLibrary.FindPart(folderName, candidates)
	local template = MeshLibrary.Find(folderName, candidates)
	if not template then return nil end
	if template:IsA("BasePart") then
		return template:Clone()
	end
	if template:IsA("Model") then
		local inner = template:FindFirstChildWhichIsA("MeshPart", true)
			or template:FindFirstChildWhichIsA("BasePart", true)
		if inner then return inner:Clone() end
	end
	return nil
end

-- === Страховка по текстурам ===
-- Если меш импортировали БЕЗ текстур (PNG не были раскодированы из .b64 на
-- момент Import 3D), MeshPart.TextureID пуст и остров стоит белым. Красим
-- такие парты запасными цветами по ИМЕНИ материала (Import 3D разбивает
-- мульти-материальный OBJ на парты с именами материалов: M_grass, M_sand...).
-- С настоящими текстурами функция ничего не трогает.
local FALLBACK_COLORS = {
	{ "yellow",   Color3.fromRGB(247, 200, 20) },
	{ "black",    Color3.fromRGB(26, 27, 29) },
	{ "asphalt",  Color3.fromRGB(62, 64, 68) },
	{ "sidewalk", Color3.fromRGB(206, 208, 204) },
	{ "concrete", Color3.fromRGB(148, 150, 149) },
	{ "grass",    Color3.fromRGB(86, 165, 54) },
	{ "green",    Color3.fromRGB(58, 122, 38) },
	{ "sand2",    Color3.fromRGB(226, 176, 88) },
	{ "cliff",    Color3.fromRGB(196, 148, 70) },
	{ "sand",     Color3.fromRGB(222, 176, 92) },
	{ "rock",     Color3.fromRGB(88, 90, 94) },
	{ "gray",     Color3.fromRGB(168, 170, 168) },
}

function MeshLibrary.ApplyFallbackColors(root)
	local function paint(part)
		if not part:IsA("MeshPart") then return end
		if part.TextureID ~= nil and part.TextureID ~= "" then return end
		local name = string.lower(part.Name)
		for _, entry in ipairs(FALLBACK_COLORS) do
			if string.find(name, entry[1], 1, true) then
				part.Color = entry[2]
				part.Material = Enum.Material.SmoothPlastic
				return
			end
		end
	end
	if root:IsA("BasePart") then
		paint(root)
	else
		for _, part in ipairs(root:GetDescendants()) do
			paint(part)
		end
	end
end

return MeshLibrary
