class_name HubActions
extends RefCounted

## Home-base operations shared by the debug menu (main.gd form pages) and the
## real pixel-art screens (HubView). Change behaviour here, not in either UI.

const BACKGROUNDS: Array[Dictionary] = [
	{"id": "camp", "name": "森の野営地"},
	{"id": "hall", "name": "石造りのアジト"},
	{"id": "tower", "name": "夕暮れの見張り塔"},
]
const DECK_MIN: int = 20
const DECK_MAX: int = 30
const COPIES_MAX: int = 10

static func background_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in BACKGROUNDS:
		ids.append(entry.id)
	return ids

static func background_name(id: String) -> String:
	for entry: Dictionary in BACKGROUNDS:
		if entry.id == id:
			return entry.name
	return id

static func set_background(profile: Dictionary, id: String) -> bool:
	if id not in background_ids():
		return false
	profile.hub_background = id
	return true

static func next_background(profile: Dictionary) -> String:
	var ids := background_ids()
	var next: String = ids[(ids.find(str(profile.get("hub_background", ids[0]))) + 1) % ids.size()]
	set_background(profile, next)
	return next

# ---------------------------------------------------------------- deck

static func add_card_reason(profile: Dictionary, card_id: String) -> String:
	if profile.deck.size() >= DECK_MAX:
		return "デッキは%d枚までです" % DECK_MAX
	if profile.deck.count(card_id) >= COPIES_MAX:
		return "同じカードは%d枚までです" % COPIES_MAX
	return ""

static func remove_card_reason(profile: Dictionary, card_id: String) -> String:
	if profile.deck.count(card_id) == 0:
		return "デッキに入っていません"
	if profile.deck.size() <= DECK_MIN:
		return "デッキは%d枚以上必要です（先に追加してから減らしてください）" % DECK_MIN
	return ""

static func add_card(profile: Dictionary, card_id: String) -> bool:
	if not add_card_reason(profile, card_id).is_empty():
		return false
	profile.deck.append(card_id)
	return true

static func remove_card(profile: Dictionary, card_id: String) -> bool:
	if not remove_card_reason(profile, card_id).is_empty():
		return false
	profile.deck.erase(card_id)
	return true

# ---------------------------------------------------------------- equipment

static func clamp_profile(profile: Dictionary, snapshot: Dictionary) -> void:
	var values := Progression.stats(profile, snapshot)
	profile.hp = mini(int(profile.hp), int(values.max_hp))
	profile.mp = mini(int(profile.mp), int(values.max_mp))

static func equip(profile: Dictionary, item: Dictionary, snapshot: Dictionary) -> bool:
	if not Progression.equip(profile, item, snapshot):
		return false
	clamp_profile(profile, snapshot)
	return true

static func unequip(profile: Dictionary, slot: String, snapshot: Dictionary) -> bool:
	if not profile.equipped.has(slot):
		return false
	profile.equipped.erase(slot)
	clamp_profile(profile, snapshot)
	return true

static func is_equipped(profile: Dictionary, item: Dictionary) -> bool:
	return item.instance_id in profile.equipped.values()

static func equip_reason(profile: Dictionary, item: Dictionary, snapshot: Dictionary) -> String:
	if is_equipped(profile, item):
		return "装備中"
	var base: Dictionary = DefinitionRepository.new().indexed("items", snapshot)[item.base_id]
	if not Progression.can_equip_instance(profile, item, base):
		return "装備条件を満たしていません"
	return ""

static func equipped_item(profile: Dictionary, slot: String) -> Dictionary:
	var id: Variant = profile.equipped.get(slot)
	for item: Dictionary in profile.inventory:
		if item.instance_id == id:
			return item
	return {}

# ---------------------------------------------------------------- consumables

const ITEM_STACK_MAX: int = 99

static func owned(profile: Dictionary, id: String) -> int:
	return int(profile.get("consumables", {}).get(id, 0))

static func gain_item(profile: Dictionary, id: String, amount: int = 1) -> void:
	profile.consumables[id] = mini(ITEM_STACK_MAX, owned(profile, id) + amount)

## Removes one used item from both the stock and the carried loadout.
static func consume_item(profile: Dictionary, id: String) -> void:
	if owned(profile, id) <= 0:
		return
	profile.consumables[id] = owned(profile, id) - 1
	if profile.consumables[id] <= 0:
		profile.consumables.erase(id)
	profile.loadout.erase(id)

static func load_reason(profile: Dictionary, snapshot: Dictionary, id: String) -> String:
	var limit := ItemRunner.carry_limit(snapshot)
	if profile.loadout.size() >= limit:
		return "持ち込みは%d個までです" % limit
	if profile.loadout.count(id) >= owned(profile, id):
		return "所持数が足りません"
	return ""

static func load_item(profile: Dictionary, snapshot: Dictionary, id: String) -> bool:
	if not load_reason(profile, snapshot, id).is_empty():
		return false
	profile.loadout.append(id)
	return true

static func unload_item(profile: Dictionary, index: int) -> bool:
	if index < 0 or index >= profile.loadout.size():
		return false
	profile.loadout.remove_at(index)
	return true

## Items actually taken into battle (the loadout may exceed a lowered limit).
static func carried(profile: Dictionary, snapshot: Dictionary) -> Array:
	return profile.loadout.slice(0, ItemRunner.carry_limit(snapshot))

static func consumable(snapshot: Dictionary, id: String) -> Dictionary:
	return DefinitionRepository.new().indexed("consumables", snapshot).get(id, {})

## Out-of-battle use (map) of a carried item: "" when usable.
static func field_use_reason(profile: Dictionary, snapshot: Dictionary, id: String, rng: RandomNumberGenerator) -> String:
	if id not in carried(profile, snapshot):
		return "持ち込んでいません"
	var item := consumable(snapshot, id)
	return ItemRunner.can_use(item, ItemContext.for_field(profile, snapshot, item, rng))

## {"ok", "reason", "results"}; consumes the item on success.
static func use_field_item(profile: Dictionary, snapshot: Dictionary, id: String, rng: RandomNumberGenerator) -> Dictionary:
	var reason := field_use_reason(profile, snapshot, id, rng)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "results": []}
	var item := consumable(snapshot, id)
	var ctx := ItemContext.for_field(profile, snapshot, item, rng)
	ItemRunner.use(item, ctx)
	consume_item(profile, id)
	return {"ok": true, "reason": "", "results": ctx.results}

static func item_summary(results: Array) -> String:
	var parts: Array[String] = []
	for result: Dictionary in results:
		match str(result.type):
			"heal": parts.append("HP +%d" % int(result.amount))
			"restore_mp": parts.append("MP +%d" % int(result.amount))
			"message": parts.append(str(result.text))
	return "、".join(parts)

# ---------------------------------------------------------------- text

static func stats_text(values: Dictionary) -> String:
	return "HP %d / MP %d / 力 %d / 知恵 %d / 敏捷 %d / 運 %d" % [values.max_hp, values.max_mp, values.strength, values.wisdom, values.agility, values.luck]

static func item_title(item: Dictionary, snapshot: Dictionary) -> String:
	var base: Dictionary = DefinitionRepository.new().indexed("items", snapshot)[item.base_id]
	return "%s [%s] Lv.%d" % [item.get("name", base.name), UiText.name_for(item.rarity), item.get("item_level", base.level)]

static func item_details(item: Dictionary, snapshot: Dictionary) -> String:
	var base: Dictionary = DefinitionRepository.new().indexed("items", snapshot)[item.base_id]
	var parts: Array[String] = []
	for affix: Dictionary in item.affixes:
		parts.append("%s +%d" % [UiText.name_for(affix.stat), affix.value])
	return "%s / 基底: %s\n基礎補正: %s / 追加: %s" % [UiText.name_for(base.slot), base.name, UiText.bonuses(item.get("base_bonuses", base.bonuses)), "、".join(parts) if not parts.is_empty() else "なし"]

static func item_text(item: Dictionary, snapshot: Dictionary) -> String:
	return item_title(item, snapshot) + " " + item_details(item, snapshot)

static func requirement_text(item: Dictionary, snapshot: Dictionary) -> String:
	var base: Dictionary = DefinitionRepository.new().indexed("items", snapshot)[item.base_id]
	return "必要Lv %s %s" % [item.get("item_level", base.level), UiText.bonuses(base.requirements)]

## Stats after equipping item, for before/after comparison.
static func preview_equip(profile: Dictionary, item: Dictionary, snapshot: Dictionary) -> Dictionary:
	var comparison := profile.duplicate(true)
	if not comparison.inventory.any(func(entry: Dictionary) -> bool: return entry.instance_id == item.instance_id):
		comparison.inventory.append(item.duplicate(true))
	Progression.equip(comparison, item, snapshot)
	return Progression.stats(comparison, snapshot)

static func xp_needed(profile: Dictionary) -> int:
	return int(profile.level) * 30

static func status_lines(profile: Dictionary, snapshot: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append("レベル %d   EXP %d / %d   ゴールド %d" % [profile.level, profile.xp, xp_needed(profile), profile.gold])
	lines.append("基礎能力: " + stats_text(profile.base))
	lines.append("装備込み: " + stats_text(Progression.stats(profile, snapshot)))
	lines.append("デッキ %d枚 / 所持装備 %d個" % [profile.deck.size(), profile.inventory.size()])
	var cleared: Array[String] = []
	var areas := DefinitionRepository.new().indexed("areas", snapshot)
	for id: String in profile.cleared:
		cleared.append(str(areas[id].name) if areas.has(id) else id)
	lines.append("初クリア済み: " + ("、".join(cleared) if not cleared.is_empty() else "なし"))
	return lines
