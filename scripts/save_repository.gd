class_name SaveRepository
extends RefCounted

var path: String = "user://saves/profile.json"
var error: String = ""
var write_blocked: bool = false

func validate(profile: Variant, definitions: Dictionary) -> String:
	if not profile is Dictionary or profile.get("save_version") != 1:
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
		if not item is Dictionary or not item.get("instance_id") is String or item.instance_id.is_empty() or instances.has(item.instance_id) or not bases.has(item.get("base_id")) or not item.get("affixes") is Array or item.get("rarity") not in ["common", "magic", "rare"]:
			return "装備個体の形式／基底IDが不正です"
		instances[item.instance_id] = item
		var count: int = ["common", "magic", "rare"].find(item.rarity)
		if item.affixes.size() != count:
			return "装備等級とアフィックス個数が一致しません"
		var seen_affixes: Dictionary = {}
		for affix: Variant in item.affixes:
			if not affix is Dictionary or not affixes.has(affix.get("id")) or affix.get("stat") not in DefinitionRepository.STATS or not (affix.get("value") is int or affix.get("value") is float):
				return "装備アフィックスが不正です"
			if seen_affixes.has(affix.id) or not is_finite(float(affix.value)) or affix.value < 0 or affix.value > 1000000000 or floor(float(affix.value)) != float(affix.value):
				return "アフィックスの重複／値が不正です"
			seen_affixes[affix.id] = true
	for slot: Variant in profile.equipped:
		if slot not in ["weapon", "armor", "accessory"] or not instances.has(profile.equipped[slot]):
			return "装備中instance_idが不正です"
		var base: Dictionary = bases[instances[profile.equipped[slot]].base_id]
		if base.slot != slot or not Progression.can_equip(profile, base):
			return "装備条件を満たしていません"
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
		error = validate(parser.data, definitions)
	if not error.is_empty():
		write_blocked = true
		return {}
	var profile: Dictionary = parser.data
	var effective := Progression.stats(profile, definitions)
	profile["hp"] = int(effective.max_hp)
	profile["mp"] = int(effective.max_mp)
	return profile

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
