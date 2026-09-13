class_name DefinitionRepository
extends RefCounted

const GROUPS: Array[String] = ["cards", "enemies", "items", "affixes", "areas", "formulas", "rules"]
const STATS: Array[String] = ["max_hp", "max_mp", "strength", "wisdom", "agility", "luck"]
const EFFECTS: Array[String] = ["damage", "block", "heal", "draw", "restore_mp", "apply_poison", "modify_stat"]
var root: String = "res://data"
var data: Dictionary = {}
var errors: Array[String] = []
var models: DefinitionModels
var last_backup_path: String = ""

func initialize(override_root: String = "") -> bool:
	if not override_root.is_empty() or not OS.has_feature("editor"):
		root = override_root if not override_root.is_empty() else "user://editor_workspace/data"
		if not DirAccess.dir_exists_absolute(root):
			DirAccess.make_dir_recursive_absolute(root)
			for group: String in GROUPS:
				var result := DirAccess.copy_absolute("res://data/" + group + ".json", root + "/" + group + ".json")
				if result != OK:
					errors.assign(["データ初期コピー失敗: " + group])
					return false
	return reload()

func install_bundled() -> bool:
	# Called only after explicit UI confirmation; retain a durable copy of edited files.
	if root == "res://data":
		errors.assign(["プロジェクトの定義は自動置換しません。Gitまたはバックアップから修復してください。"])
		return false
	var bundled := DefinitionRepository.new()
	if not bundled.reload():
		errors = bundled.errors
		return false
	var backup := root.get_base_dir().path_join("backup_" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(Time.get_ticks_usec()))
	if DirAccess.make_dir_recursive_absolute(backup) != OK:
		errors.assign(["定義データのバックアップ作成に失敗しました"])
		return false
	for group: String in GROUPS:
		if DirAccess.copy_absolute(root + "/" + group + ".json", backup + "/" + group + ".json") != OK:
			errors.assign(["旧データの退避に失敗しました: " + group])
			return false
	last_backup_path = backup
	return save_draft(bundled.data)

func reload() -> bool:
	var incoming: Dictionary = {}
	errors.clear()
	for group: String in GROUPS:
		var file := FileAccess.open(root + "/" + group + ".json", FileAccess.READ)
		if file == null:
			errors.append(group + ": ファイルを開けません")
			continue
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK:
			errors.append(group + ": JSONエラー " + parser.get_error_message())
			continue
		incoming[group] = parser.data
	if not errors.is_empty():
		return false
	errors = validate(incoming)
	if not errors.is_empty():
		return false
	data = incoming
	models = DefinitionModels.new(data)
	return true

func records(group: String, source: Dictionary = data) -> Array:
	return source.get(group, {}).get("entries", [])

func indexed(group: String, source: Dictionary = data) -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in records(group, source):
		result[entry.id] = entry
	return result

func revision() -> String:
	return JSON.stringify(data).sha256_text().substr(0, 12)

func validate(source: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var indexes: Dictionary = {}
	for group: String in GROUPS:
		if not source.get(group) is Dictionary:
			issues.append(group + ": オブジェクトが必要")
			continue
		var document: Dictionary = source[group]
		if document.get("schema_version") != 1 or not document.get("entries") is Array:
			issues.append(group + ": schema_version=1 と entries配列が必要")
			continue
		indexes[group] = {}
		for entry: Variant in document.entries:
			if not entry is Dictionary or not entry.get("id") is String:
				issues.append(group + ": 文字列IDが必要")
				continue
			var id: String = entry.id
			if id.is_empty() or not id.is_valid_identifier():
				issues.append(group + ": IDは英数字とアンダースコアで指定: " + id)
			if indexes[group].has(id):
				issues.append(group + ": 重複ID " + id)
			indexes[group][id] = entry
	if not issues.is_empty():
		return issues
	for group: String in GROUPS:
		if records(group, source).is_empty():
			issues.append(group + ": 定義が1件以上必要")
	for entry: Dictionary in records("formulas", source):
		if not entry.get("expression") is String:
			issues.append("formulas/" + entry.id + ": expressionが必要")
			continue
		var sample: Dictionary = {"base": 6, "scaling": 0.5, "strength": 5, "wisdom": 5, "agility": 5, "luck": 5, "max_hp": 60, "max_mp": 10}
		var evaluated := FormulaEvaluator.new().evaluate(entry.expression, sample)
		if not evaluated.ok:
			issues.append("formulas/" + entry.id + ": " + evaluated.error)
	for group: String in ["cards", "enemies", "items", "affixes", "areas"]:
		for entry: Dictionary in records(group, source):
			if not entry.get("name") is String or str(entry.get("name", "")).strip_edges().is_empty():
				issues.append(group + "/" + entry.id + ": 名前が必要")
	for entry: Dictionary in records("cards", source):
		var path: String = "cards/" + entry.id
		check_number(entry, "ap", 1, 99, path, issues)
		check_number(entry, "mp", 0, 999, path, issues)
		if entry.get("target") not in ["self", "selected_enemy", "all_enemies"]:
			issues.append(path + ": targetが不正")
		if entry.get("category") not in ["attack", "support", "buff"]:
			issues.append(path + ": categoryが不正")
		for field: String in ["description", "image_path"]:
			if not entry.get(field) is String:
				issues.append(path + "/" + field + ": 文字列が必要")
		check_effects(entry.get("effects"), path, indexes, issues)
	for entry: Dictionary in records("enemies", source):
		var path: String = "enemies/" + entry.id
		for field: String in ["hp", "strength", "wisdom", "xp", "gold"]:
			check_number(entry, field, 1 if field == "hp" else 0, 100000, path, issues)
		if not entry.get("actions") is Array or entry.get("actions", []).is_empty():
			issues.append(path + ": actionsが必要")
		else:
			for action: Variant in entry.actions:
				if not action is Dictionary or not action.get("name") is String:
					issues.append(path + ": 行動名が必要")
					continue
				check_effects(action.get("effects"), path + "/actions", indexes, issues)
	for entry: Dictionary in records("items", source):
		var path: String = "items/" + entry.id
		if entry.get("slot") not in EquipmentGenerator.SLOTS:
			issues.append(path + ": 部位が不正")
		check_number(entry, "level", 1, 999, path, issues)
		for field: String in ["bonuses", "requirements"]:
			if not entry.get(field) is Dictionary:
				issues.append(path + ": " + field + "が必要")
			else:
				for stat: String in entry[field]:
					if stat not in STATS:
						issues.append(path + ": 未知の能力 " + stat)
					check_number(entry[field], stat, 0, 100000, path, issues)
		if not entry.get("level_growth") is Dictionary:
			issues.append(path + "/level_growth: レベル成長値が必要")
		else:
			for stat: Variant in entry.level_growth:
				if stat not in STATS or not EquipmentGenerator.valid_number(entry.level_growth[stat], 0, 100000):
					issues.append(path + "/level_growth: 能力名または0～100000の成長値が不正")
		check_refs(entry.get("affixes"), indexes.affixes, path + "/affixes", issues)
		if entry.get("affixes") is Array and entry.affixes.size() < 2:
			issues.append(path + ": レア抽選のためアフィックス候補2件以上が必要")
		if entry.get("affixes") is Array:
			var unique: Dictionary = {}
			for id: Variant in entry.affixes:
				unique[str(id)] = true
			if unique.size() != entry.affixes.size():
				issues.append(path + ": アフィックス候補の重複")
	for entry: Dictionary in records("affixes", source):
		var path: String = "affixes/" + entry.id
		if entry.get("stat") not in STATS:
			issues.append(path + ": statが不正")
		for field: String in ["min", "max", "weight"]:
			check_number(entry, field, 1 if field == "weight" else 0, 100000, path, issues)
		if is_number(entry.get("min")) and is_number(entry.get("max")) and entry.min > entry.max:
			issues.append(path + ": min > max")
	for entry: Dictionary in records("areas", source):
		check_area(entry, indexes, issues)
	if not indexes.rules.has("combat"):
		issues.append("rules: combatが必要")
	else:
		var rules: Dictionary = indexes.rules.combat
		for field: String in ["ap", "initial_hand", "draw", "hand_limit", "mp_regen"]:
			check_number(rules, field, 0 if field == "mp_regen" else 1, 30, "rules/combat", issues)
		check_refs(rules.get("starter_deck"), indexes.cards, "rules/starter_deck", issues)
		var deck: Array = rules.get("starter_deck", []) if rules.get("starter_deck") is Array else []
		if deck.size() < 20 or deck.size() > 30:
			issues.append("rules/starter_deck: 20～30枚が必要")
		for id: Variant in deck:
			if deck.count(id) > 10:
				issues.append("rules/starter_deck: 同一種類は10枚まで")
		check_refs(rules.get("loot_bases"), indexes.items, "rules/loot_bases", issues)
		if rules.get("loot_bases") is Array and rules.loot_bases.is_empty():
			issues.append("rules/loot_bases: 候補が必要")
		if not rules.get("rarity_weights") is Dictionary:
			issues.append("rules: rarity_weightsが必要")
		else:
			var total: float = 0
			for rarity: String in EquipmentGenerator.RARITIES:
				check_number(rules.rarity_weights, rarity, 0, 100000, "rules/rarity_weights", issues)
				if is_number(rules.rarity_weights.get(rarity)):
					total += rules.rarity_weights[rarity]
			if total <= 0:
				issues.append("rules/rarity_weights: 合計は正数が必要")
	if not indexes.rules.has("loot"):
		issues.append("rules/loot: 新装備抽選の設定がありません。新しい定義データ一式を導入してください。")
	else:
		issues.append_array(EquipmentGenerator.validate(indexes.rules.loot, indexes.items, indexes.affixes))
	return issues

func is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func check_number(entry: Dictionary, key: String, low: float, high: float, path: String, issues: Array[String]) -> void:
	var value: Variant = entry.get(key)
	if not is_number(value) or float(value) < low or float(value) > high or floor(float(value)) != float(value):
		issues.append(path + "/" + key + ": 整数 %s～%s が必要" % [low, high])

func check_refs(refs: Variant, index: Dictionary, path: String, issues: Array[String]) -> void:
	if not refs is Array:
		issues.append(path + ": ID配列が必要")
		return
	for id: Variant in refs:
		if not id is String or not index.has(id):
			issues.append(path + ": 参照先がありません " + str(id))

func check_effects(effects: Variant, path: String, indexes: Dictionary, issues: Array[String]) -> void:
	if not effects is Array or effects.is_empty():
		issues.append(path + ": effects配列が必要")
		return
	for effect: Variant in effects:
		if not effect is Dictionary:
			issues.append(path + ": 効果はオブジェクトが必要")
			continue
		if effect.get("type") not in EFFECTS:
			issues.append(path + ": 未知の効果 " + str(effect.get("type")))
		if effect.get("target") not in ["self", "selected_enemy", "all_enemies", "player"]:
			issues.append(path + ": 効果対象が不正")
		check_number(effect, "value", 0, 100000, path, issues)
		if not is_number(effect.get("scaling", 0)):
			issues.append(path + ": scalingは有限の数値が必要")
		if effect.get("formula_id", "") != "" and not indexes.formulas.has(effect.formula_id):
			issues.append(path + ": 数式参照切れ " + str(effect.formula_id))
		if effect.get("type") == "modify_stat" and effect.get("stat") not in STATS:
			issues.append(path + ": modify_statのstatが不正")
		if effect.get("type") == "draw" and effect.get("target") not in ["self", "player"]:
			issues.append(path + ": draw対象はselfまたはplayer")

func check_area(area: Dictionary, indexes: Dictionary, issues: Array[String]) -> void:
	var path: String = "areas/" + area.id
	if not area.get("nodes") is Array:
		issues.append(path + ": nodes配列が必要")
		return
	var nodes: Dictionary = {}
	for node: Variant in area.nodes:
		if not node is Dictionary or not node.get("id") is String:
			issues.append(path + ": ノードIDが必要")
			continue
		if nodes.has(node.id):
			issues.append(path + ": 重複ノード " + node.id)
		nodes[node.id] = node
		check_refs(node.get("enemies"), indexes.enemies, path + "/" + node.id, issues)
		if node.get("enemies") is Array and node.id != area.get("start") and (node.enemies.size() < 1 or node.enemies.size() > 3):
			issues.append(path + "/" + node.id + ": 敵は1～3体")
	if not nodes.has(area.get("start")) or not nodes.has(area.get("boss")):
		issues.append(path + ": 開始／ボス参照が不正")
		return
	if area.start == area.boss:
		issues.append(path + ": 開始とボスは別ノードが必要")
	if nodes[area.start].get("enemies") is Array and not nodes[area.start].enemies.is_empty():
		issues.append(path + ": 開始ノードには敵を配置できません")
	for node: Dictionary in nodes.values():
		check_refs(node.get("next"), nodes, path + "/" + node.id + "/next", issues)
		if node.get("next") is Array:
			if node.id != area.boss and node.next.is_empty():
				issues.append(path + ": ボス以外の行き止まり " + node.id)
			if node.id == area.boss and not node.next.is_empty():
				issues.append(path + ": ボスは終端ノードである必要があります")
	var visited: Dictionary = {}
	visit_area(str(area.start), nodes, {}, visited, path, issues)
	for id: String in nodes:
		if not visited.has(id):
			issues.append(path + ": 到達不能／孤立ノード " + id)

func visit_area(id: String, nodes: Dictionary, active: Dictionary, visited: Dictionary, path: String, issues: Array[String]) -> void:
	if active.has(id):
		issues.append(path + ": 循環 " + id)
		return
	if visited.has(id) or not nodes.has(id):
		return
	visited[id] = true
	active[id] = true
	if nodes[id].get("next") is Array:
		for next: Variant in nodes[id].next:
			if next is String:
				visit_area(next, nodes, active, visited, path, issues)
	active.erase(id)

func save_draft(draft: Dictionary) -> bool:
	errors = validate(draft)
	if not errors.is_empty():
		return false
	# Stage all documents before replacing any originals; preserve backups on failure.
	for group: String in GROUPS:
		var path := root + "/" + group + ".json"
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file == null:
			errors.append("書き込み失敗: " + path)
			return false
		file.store_string(JSON.stringify(draft[group], "\t"))
		file.flush()
		if file.get_error() != OK:
			errors.append("保存失敗: " + path)
			return false
		file.close()
	for group: String in GROUPS:
		var path := root + "/" + group + ".json"
		if DirAccess.copy_absolute(path, path + ".bak") != OK:
			errors.append("バックアップ失敗: " + path)
			return false
	for group: String in GROUPS:
		var path := root + "/" + group + ".json"
		if DirAccess.rename_absolute(path + ".tmp", path) != OK:
			for restore: String in GROUPS:
				DirAccess.copy_absolute(root + "/" + restore + ".json.bak", root + "/" + restore + ".json")
			errors.append("置換失敗。バックアップを復元: " + path)
			return false
	return reload()
