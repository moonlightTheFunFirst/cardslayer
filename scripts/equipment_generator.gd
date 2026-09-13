class_name EquipmentGenerator
extends RefCounted

const SLOTS: Array[String] = ["head", "body", "arms", "right_hand", "left_hand", "two_handed", "feet"]
const RARITIES: Array[String] = ["common", "magic", "rare", "legendary", "unique"]
const COUNTS: Dictionary = {"common": [1], "magic": [1, 2], "rare": [3, 4, 5, 6, 7], "legendary": [1, 2], "unique": [1, 2]}
const COLORS: Dictionary = {"common": Color("ffffff"), "magic": Color("69adff"), "rare": Color("ffe36a"), "legendary": Color("c88b57"), "unique": Color("cd8dff")}
const NAME_LEFT: Array[String] = ["月影", "暁星", "白銀", "紅蓮", "深緑", "星霜", "夜凪", "薄明", "雷鳴", "常闇", "霜月", "黎明", "蒼穹", "残光", "静寂", "永劫"]
const NAME_LINKS: Array[String] = ["を纏う", "を宿す", "に輝く", "を継ぐ", "に眠る", "を秘めた", "に染まる", "を映す"]
const NAME_RIGHT: Dictionary = {
	"head": ["銀冠", "星の兜", "黒曜の冠", "守護の額輪", "王者の兜", "蒼玉の冠"],
	"body": ["守護の鎧", "黒鉄の胸甲", "白夜の衣", "誓約の鎧", "銀糸の法衣", "霧の外套"],
	"arms": ["獅子の籠手", "銀の手甲", "守人の腕甲", "誓いの籠手", "黒曜の腕輪", "星の手袋"],
	"right_hand": ["蒼刃", "月牙", "雷光剣", "宵の牙", "誓約の剣", "銀狼の刃"],
	"left_hand": ["守護の翼", "黒鉄の護り", "守人の誓い", "銀月の護り", "不屈の誓い", "宵の守り"],
	"two_handed": ["覇者の杖", "星砕き", "竜の咆哮", "断罪の大刃", "巡礼の大杖", "天空の牙"],
	"feet": ["旅人の足跡", "銀の長靴", "風渡り", "巡礼の靴", "夜歩き", "流星の靴"]
}

var bases: Dictionary
var affixes: Dictionary
var rarities: Dictionary = {}
var rules: Dictionary

func _init(snapshot: Dictionary) -> void:
	var repo := DefinitionRepository.new()
	bases = repo.indexed("items", snapshot).duplicate(true)
	affixes = repo.indexed("affixes", snapshot).duplicate(true)
	rules = repo.indexed("rules", snapshot).combat.duplicate(true)
	for entry: Dictionary in repo.indexed("rules", snapshot).loot.rarities:
		rarities[entry.id] = entry.duplicate(true)

func generate(rng: RandomNumberGenerator, level: int, rarity_id: String = "", base_id: String = "", slot: String = "") -> Dictionary:
	if level < 1 or level > 999:
		return {"ok": false, "error": "装備レベルは1～999で指定してください"}
	if not slot.is_empty() and slot not in SLOTS:
		return {"ok": false, "error": "部位が不正です"}
	var pool: Array = []
	for id: String in rules.loot_bases:
		if (slot.is_empty() or bases[id].slot == slot) and (base_id.is_empty() or id == base_id):
			pool.append(id)
	if pool.is_empty():
		return {"ok": false, "error": "指定条件の装備候補がありません"}
	if not rarity_id.is_empty() and rarity_id not in RARITIES:
		return {"ok": false, "error": "等級が不正です"}
	var selected_base: String = pool[rng.randi_range(0, pool.size() - 1)]
	if rarity_id.is_empty():
		var weights: Array = []
		for id: String in RARITIES:
			weights.append(rules.rarity_weights[id])
		rarity_id = Progression.weighted(RARITIES, weights, rng)
	var policy: Dictionary = rarities[rarity_id]
	var counts: Array = policy.count_weights.keys()
	var weights: Array = policy.count_weights.values()
	var count: int = int(Progression.weighted(counts, weights, rng))
	var base: Dictionary = bases[selected_base]
	var bonuses: Dictionary = {}
	for stat: String in DefinitionRepository.STATS:
		bonuses[stat] = int(floor(float(base.bonuses.get(stat, 0)) + float(base.level_growth.get(stat, 0)) * (level - 1)))
	var candidates: Array = []
	for id: String in base.affixes:
		if float(policy.affix_weights.get(id, 0)) > 0:
			candidates.append(id)
	if candidates.size() < count:
		return {"ok": false, "error": "重複なし抽選に必要なアフィックス候補が不足しています"}
	var rolled: Array = []
	for i: int in count:
		weights = []
		for id: String in candidates:
			weights.append(policy.affix_weights[id])
		var id: String = Progression.weighted(candidates, weights, rng)
		var limits: Dictionary = policy.value_ranges[id]
		var roll: float = rng.randf() * 100.0
		var exceptional: bool = float(limits.exception_chance) >= 100.0 or roll < float(limits.exception_chance)
		var minimum: int = int(limits.exception_min if exceptional else limits.min)
		var maximum: int = int(limits.exception_max if exceptional else limits.max)
		rolled.append({"id": id, "stat": affixes[id].stat, "value": rng.randi_range(minimum, maximum), "exceptional": exceptional})
		candidates.erase(id)
	return {"ok": true, "item": {"generation_version": 2, "name": random_name(base.slot, rng.state), "base_id": selected_base, "rarity": rarity_id, "item_level": level, "base_bonuses": bonuses, "affixes": rolled}}

static func random_name(slot: String, state: int) -> String:
	# A separate stream keeps cosmetic naming from changing stat/rarity rolls.
	var names := RandomNumberGenerator.new()
	names.seed = state
	var left: String = NAME_LEFT[names.randi_range(0, NAME_LEFT.size() - 1)]
	var link: String = NAME_LINKS[names.randi_range(0, NAME_LINKS.size() - 1)]
	var pool: Array = NAME_RIGHT[slot]
	return left + link + str(pool[names.randi_range(0, pool.size() - 1)])

static func validate(config: Dictionary, bases: Dictionary, affixes: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if not config.get("rarities") is Array:
		return ["rules/loot: rarities配列が必要"]
	var found: Dictionary = {}
	for policy: Variant in config.rarities:
		if not policy is Dictionary or policy.get("id") not in RARITIES:
			issues.append("rules/loot: 未知の等級")
			continue
		var path: String = "rules/loot/" + policy.id
		if found.has(policy.id):
			issues.append(path + ": 等級重複")
		found[policy.id] = true
		if not policy.get("count_weights") is Dictionary or not policy.get("affix_weights") is Dictionary or not policy.get("value_ranges") is Dictionary:
			issues.append(path + ": 個数重み・候補重み・数値範囲が必要")
			continue
		var total: float = 0
		var maximum_count: int = 0
		for key: Variant in policy.count_weights:
			if not key is String or not key.is_valid_int() or int(key) not in COUNTS[policy.id]:
				issues.append(path + "/count_weights: 許可されない個数 " + str(key))
				continue
			if not valid_number(policy.count_weights[key], 0, 1000000):
				issues.append(path + "/count_weights: 重みは0～1000000の有限値")
				continue
			total += float(policy.count_weights[key])
			if policy.count_weights[key] > 0:
				maximum_count = maxi(maximum_count, int(key))
		if total <= 0:
			issues.append(path + "/count_weights: 重み合計は正数が必要")
		for id: Variant in policy.affix_weights:
			if not id is String or not affixes.has(id):
				issues.append(path + "/affix_weights: 参照先がありません " + str(id))
			elif not valid_number(policy.affix_weights[id], 0, 1000000):
				issues.append(path + "/affix_weights/" + id + ": 重みは0～1000000の有限値")
			elif float(policy.affix_weights[id]) > 0 and not policy.value_ranges.has(id):
				issues.append(path + "/value_ranges: 値範囲が必要 " + id)
		for id: Variant in policy.value_ranges:
			if not id is String or not affixes.has(id) or not policy.value_ranges[id] is Dictionary:
				issues.append(path + "/value_ranges: 参照先または形式が不正 " + str(id))
				continue
			var limits: Dictionary = policy.value_ranges[id]
			var valid: bool = true
			for field: String in ["min", "max", "exception_min", "exception_max"]:
				if not valid_number(limits.get(field), 0, 100000) or float(limits[field]) != floor(float(limits[field])):
					issues.append(path + "/" + id + "/" + field + ": 0～100000の整数が必要")
					valid = false
			if not valid_number(limits.get("exception_chance"), 0, 100):
				issues.append(path + "/" + id + ": 特別ロール確率は0～100%")
			if valid and (limits.min > limits.max or limits.exception_min > limits.exception_max):
				issues.append(path + "/" + id + ": 最小値が最大値を超えています")
		for base: Dictionary in bases.values():
			if not base.get("affixes") is Array:
				continue
			var eligible: int = 0
			for id: Variant in base.affixes:
				if id is String and valid_number(policy.affix_weights.get(id, 0), 0, 1000000) and float(policy.affix_weights.get(id, 0)) > 0:
					eligible += 1
			if eligible < maximum_count:
				issues.append(path + ": " + str(base.id) + " の候補不足（必要%d／有効%d）" % [maximum_count, eligible])
	for id: String in RARITIES:
		if not found.has(id):
			issues.append("rules/loot: 等級定義がありません " + id)
	return issues

static func valid_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
