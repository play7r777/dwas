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

return MeshLibrary
