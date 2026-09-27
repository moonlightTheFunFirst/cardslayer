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
