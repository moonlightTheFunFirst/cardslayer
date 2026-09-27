class_name Shop
extends RefCounted

## Shop stock and purchases. Shared by the debug menu and the real shop screen,
## so both always sell the same goods at the same prices.

const DEFAULTS: Dictionary = {
	"id": "shop",
	"equipment_count": 4,
	"level_offset": 0,
	"price_base": 20,
	"price_per_level": 6,
	"rarity_weights": {"common": 50, "magic": 32, "rare": 14, "legendary": 3, "unique": 1},
	"rarity_multipliers": {"common": 1, "magic": 2, "rare": 4, "legendary": 8, "unique": 10},
}

## rules/shop merged over DEFAULTS (older edit workspaces may lack the entry).
static func settings(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = DEFAULTS.duplicate(true)
	var rules := DefinitionRepository.new().indexed("rules", snapshot)
	if rules.has("shop"):
		for key: String in rules.shop:
			result[key] = rules.shop[key]
	return result

static func validate(entry: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var path := "rules/shop"
	for field: Array in [["equipment_count", 0, 12], ["level_offset", -50, 50], ["price_base", 0, 1000000], ["price_per_level", 0, 1000000]]:
		var value: Variant = entry.get(field[0], DEFAULTS[field[0]])
		if not EquipmentGenerator.valid_number(value, field[1], field[2]) or floor(float(value)) != float(value):
			issues.append("%s/%s: 整数 %d～%d が必要" % [path, field[0], field[1], field[2]])
	for key: String in ["rarity_weights", "rarity_multipliers"]:
		var table: Variant = entry.get(key, DEFAULTS[key])
		if not table is Dictionary:
			issues.append(path + "/" + key + ": 等級ごとの数値が必要")
			continue
		var total: float = 0
		for rarity: String in EquipmentGenerator.RARITIES:
			if not EquipmentGenerator.valid_number(table.get(rarity), 0, 100000):
				issues.append("%s/%s/%s: 0～100000の数値が必要" % [path, key, rarity])
			else:
				total += float(table[rarity])
		if key == "rarity_weights" and total <= 0:
			issues.append(path + "/rarity_weights: 合計は正数が必要")
	return issues

static func price(item: Dictionary, config: Dictionary) -> int:
	var multiplier: float = float(config.rarity_multipliers.get(item.rarity, 1))
	return maxi(1, int(round((float(config.price_base) + float(config.price_per_level) * int(item.get("item_level", 1))) * multiplier)))

## Replace the stock with freshly generated offers.
static func restock(profile: Dictionary, snapshot: Dictionary, rng: RandomNumberGenerator) -> void:
	var config := settings(snapshot)
	var level: int = clampi(int(profile.level) + int(config.level_offset), 1, 999)
	var rarities: Array = EquipmentGenerator.RARITIES.duplicate()
	var weights: Array = []
	for rarity: String in rarities:
		weights.append(float(config.rarity_weights.get(rarity, 0)))
	var generator := EquipmentGenerator.new(snapshot)
	var stock: Array = []
	for i: int in int(config.equipment_count):
		var rarity: String = Progression.weighted(rarities, weights, rng)
		var generated := generator.generate(rng, level, rarity)
		if not generated.ok:
			continue
		var item: Dictionary = generated.item
		item["instance_id"] = "shop_%x_%x_%d" % [rng.randi(), rng.randi(), i]
		stock.append({"kind": "equipment", "item": item, "price": price(item, config), "sold": false})
	profile["shop"] = {"stock": stock}

static func stock(profile: Dictionary) -> Array:
	return profile.get("shop", {}).get("stock", [])

## "" when the offer can be bought, otherwise the reason shown on a greyed-out button.
static func buy_reason(profile: Dictionary, index: int) -> String:
	var offers := stock(profile)
	if index < 0 or index >= offers.size():
		return "商品がありません"
	if offers[index].sold:
		return "売り切れ"
	if int(profile.gold) < int(offers[index].price):
		return "ゴールド不足"
	return ""

static func buy(profile: Dictionary, index: int) -> bool:
	if not buy_reason(profile, index).is_empty():
		return false
	var offer: Dictionary = stock(profile)[index]
	profile.gold = int(profile.gold) - int(offer.price)
	offer.sold = true
	profile.inventory.append(offer.item.duplicate(true))
	return true
