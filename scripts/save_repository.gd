class_name SaveRepository
extends RefCounted

var path: String = "user://saves/profile.json"
var error: String = ""
var write_blocked: bool = false

func validate(profile: Variant, definitions: Dictionary) -> String:
	if not profile is Dictionary or profile.get("save_version") != 2:
		return "セーブ形式／save_versionが不正です"
	for key: String in ["level", "xp", "gold"]:
		if not (profile.get(key) is float or profile.get(key) is int) or profile[key] < (1 if key == "level" else 0) or floor(float(profile[key])) != float(profile[key]):
			return key + "が不正です"
	if not profile.get("base") is Dictionary or not profile.get("inventory") is Array or not profile.get("equipped") is Dictionary or not profile.get("deck") is Array or not profile.get("cleared") is Array:
		return "基礎値・装備・デッキ・クリア履歴の形式が不正です"
	for stat: String in DefinitionRepository.STATS:
		if not (profile.base.get(stat) is float or profile.base.get(stat) is int) or not is_finite(float(profile.base[stat])) or floor(float(profile.base[stat])) != float(profile.base[stat]) or profile.base[stat] < (1 if stat == "max_hp" else 0) or profile.base[stat] > 1000000000:
			return "基礎能力が不正: " + stat
	var repo := DefinitionRepository.new()
	var cards := repo.indexed("cards", definitions)
	if profile.deck.size() < 20 or profile.deck.size() > 30:
		return "デッキは20～30枚必要です"
	for id: Variant in profile.deck:
		if not id is String or not cards.has(id) or profile.deck.count(id) > 10:
			return "デッキの欠落ID／枚数違反: " + str(id)
	var bases := repo.indexed("items", definitions)
	var affixes := repo.indexed("affixes", definitions)
	var instances: Dictionary = {}
	for item: Variant in profile.inventory:
		if not item is Dictionary or not item.get("instance_id") is String or item.instance_id.is_empty() or instances.has(item.instance_id) or not bases.has(item.get("base_id")) or not item.get("affixes") is Array or item.get("rarity") not in EquipmentGenerator.RARITIES:
			return "装備個体の形式／基底IDが不正です"
		instances[item.instance_id] = item
		if item.has("name") and (not item.name is String or item.name.strip_edges().is_empty() or item.name.length() > 160):
			return "装備品の名前が不正です"
		if item.get("generation_version") != 1 and item.get("generation_version") != 2:
			return "装備生成バージョンが不正です"
		var counts: Array = EquipmentGenerator.COUNTS[item.rarity] if item.generation_version == 2 else [["common", "magic", "rare"].find(item.rarity)]
		if item.affixes.size() not in counts:
			return "装備等級とアフィックス個数が一致しません"
		if item.generation_version == 2:
			if not EquipmentGenerator.valid_number(item.get("item_level"), 1, 999) or float(item.item_level) != floor(float(item.item_level)) or not item.get("base_bonuses") is Dictionary:
				return "装備レベル／基礎値が不正です"
			for stat: Variant in item.base_bonuses:
				if stat not in DefinitionRepository.STATS or not EquipmentGenerator.valid_number(item.base_bonuses[stat], 0, 1000000000) or float(item.base_bonuses[stat]) != floor(float(item.base_bonuses[stat])):
					return "装備基礎値が不正です"
		var seen_affixes: Dictionary = {}
		for affix: Variant in item.affixes:
			if not affix is Dictionary or not affixes.has(affix.get("id")) or affix.get("stat") not in DefinitionRepository.STATS or not (affix.get("value") is int or affix.get("value") is float):
				return "装備アフィックスが不正です"
			if seen_affixes.has(affix.id) or not is_finite(float(affix.value)) or affix.value < 0 or affix.value > 1000000000 or floor(float(affix.value)) != float(affix.value):
				return "アフィックスの重複／値が不正です"
			seen_affixes[affix.id] = true
	for slot: Variant in profile.equipped:
		if slot not in EquipmentGenerator.SLOTS or not instances.has(profile.equipped[slot]):
			return "装備中instance_idが不正です"
		var base: Dictionary = bases[instances[profile.equipped[slot]].base_id]
		if base.slot != slot or not Progression.can_equip_instance(profile, instances[profile.equipped[slot]], base):
			return "装備条件を満たしていません"
	if profile.equipped.has("two_handed") and (profile.equipped.has("right_hand") or profile.equipped.has("left_hand")):
		return "両手武器と左右の装備は同時に装備できません"
	var areas := repo.indexed("areas", definitions)
	for id: Variant in profile.cleared:
		if not areas.has(id):
			return "クリア履歴のエリアIDがありません: " + str(id)
	return ""

func read_profile(definitions: Dictionary) -> Dictionary:
	error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "セーブを開けません"
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		error = "セーブJSONが不正: " + parser.get_error_message()
	else:
		var migrated := migrate(parser.data, definitions)
		if not migrated.ok:
			error = migrated.error
		else:
			parser.data = migrated.profile
			error = validate(parser.data, definitions)
	if not error.is_empty():
		write_blocked = true
		return {}
	var profile: Dictionary = parser.data
	# JSON numbers are floats; restore validated integral runtime fields without rerolling.
	for key: String in ["save_version", "level", "xp", "gold"]:
		profile[key] = int(profile[key])
	for stat: String in profile.base:
		profile.base[stat] = int(profile.base[stat])
	for item: Dictionary in profile.inventory:
		item.generation_version = int(item.generation_version)
		if item.has("item_level"):
			item.item_level = int(item.item_level)
		for stat: String in item.get("base_bonuses", {}):
			item.base_bonuses[stat] = int(item.base_bonuses[stat])
		for affix: Dictionary in item.affixes:
			affix.value = int(affix.value)
	var effective := Progression.stats(profile, definitions)
	profile["hp"] = int(effective.max_hp)
	profile["mp"] = int(effective.max_mp)
	return profile

func migrate(raw: Variant, definitions: Dictionary) -> Dictionary:
	if not raw is Dictionary or (raw.get("save_version") != 1 and raw.get("save_version") != 2):
		return {"ok": false, "error": "セーブ形式／save_versionが不正です"}
	var profile: Dictionary = raw.duplicate(true)
	if profile.save_version == 2:
		return {"ok": true, "profile": profile}
	if not profile.get("inventory") is Array or not profile.get("equipped") is Dictionary:
		return {"ok": false, "error": "旧セーブの装備形式が不正です"}
	var bases := DefinitionRepository.new().indexed("items", definitions)
	var instances: Dictionary = {}
	for item: Variant in profile.inventory:
		if not item is Dictionary or not item.get("instance_id") is String or instances.has(item.instance_id) or not bases.has(item.get("base_id")):
			return {"ok": false, "error": "旧セーブの装備IDが不正です"}
		# Existing affix rolls are deliberately preserved, including common items with zero affixes.
		item["generation_version"] = 1
		instances[item.instance_id] = item
	var equipment: Dictionary = {}
	for old_slot: Variant in profile.equipped:
		var id: Variant = profile.equipped[old_slot]
		if old_slot not in ["weapon", "armor", "accessory"] or not instances.has(id):
			return {"ok": false, "error": "旧セーブの装備枠が不正です"}
		var slot: String = bases[instances[id].base_id].slot
		if equipment.has(slot):
			return {"ok": false, "error": "旧セーブの装備枠移行が競合しています"}
		equipment[slot] = id
	profile.equipped = equipment
	profile.save_version = 2
	return {"ok": true, "profile": profile}

func save(profile: Dictionary, definitions: Dictionary) -> bool:
	if write_blocked:
		error = "破損セーブの保護中です。元ファイルを退避して再起動してください。"
		return false
	error = validate(profile, definitions)
	if not error.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "セーブ用一時ファイルを作成できません"
		return false
	file.store_string(JSON.stringify(profile, "\t"))
	file.flush()
	if file.get_error() != OK:
		error = "セーブの書き込みに失敗"
		return false
	file.close()
	if FileAccess.file_exists(path) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		error = "セーブのバックアップに失敗"
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "セーブの置換に失敗"
		return false
	return true
