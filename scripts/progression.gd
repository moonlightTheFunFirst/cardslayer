class_name Progression
extends RefCounted

static func new_player(snapshot: Dictionary) -> Dictionary:
	var rules: Dictionary = DefinitionRepository.new().indexed("rules", snapshot).combat
	return {"save_version": 2, "level": 1, "xp": 0, "gold": 0, "base": {"max_hp": 60, "max_mp": 10, "strength": 5, "wisdom": 5, "agility": 5, "luck": 5}, "inventory": [], "equipped": {}, "deck": rules.starter_deck.duplicate(), "cleared": [], "hp": 60, "mp": 10}

static func stats(profile: Dictionary, snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = profile.base.duplicate()
	var bases := DefinitionRepository.new().indexed("items", snapshot)
	for instance: Dictionary in profile.inventory:
		if instance.instance_id not in profile.equipped.values():
			continue
		var bonuses: Dictionary = instance.get("base_bonuses", bases[instance.base_id].bonuses)
		for stat: String in bonuses:
			result[stat] += bonuses[stat]
		for affix: Dictionary in instance.affixes:
			result[affix.stat] += affix.value
	return result

static func can_equip(profile: Dictionary, base: Dictionary) -> bool:
	if profile.level < base.level:
		return false
	for stat: String in base.requirements:
		if profile.base[stat] < base.requirements[stat]:
			return false
	return true

static func can_equip_instance(profile: Dictionary, item: Dictionary, base: Dictionary) -> bool:
	return profile.level >= int(item.get("item_level", base.level)) and can_equip(profile, base)

static func equip(profile: Dictionary, item: Dictionary, snapshot: Dictionary) -> bool:
	var base: Dictionary = DefinitionRepository.new().indexed("items", snapshot)[item.base_id]
	if not can_equip_instance(profile, item, base):
		return false
	if base.slot == "two_handed":
		profile.equipped.erase("right_hand")
		profile.equipped.erase("left_hand")
	elif base.slot in ["right_hand", "left_hand"]:
		profile.equipped.erase("two_handed")
	profile.equipped[base.slot] = item.instance_id
	return true

static func weighted(candidates: Array, weights: Array, rng: RandomNumberGenerator) -> Variant:
	var total: float = 0
	for weight: Variant in weights:
		total += float(weight)
	var roll := rng.randf() * total
	var fallback: Variant = candidates[0]
	for i: int in candidates.size():
		if float(weights[i]) <= 0:
			continue
		fallback = candidates[i]
		roll -= float(weights[i])
		if roll < 0:
			return candidates[i]
	return fallback

static func loot(snapshot: Dictionary, rng: RandomNumberGenerator, level: int = 1) -> Dictionary:
	var generated := EquipmentGenerator.new(snapshot).generate(rng, level)
	assert(generated.ok, "検証済みの戦利品定義が必要です")
	var result: Dictionary = generated.item
	result["instance_id"] = "%x_%x_%x" % [Time.get_ticks_usec(), rng.randi(), rng.randi()]
	return result

static func reward(profile: Dictionary, battle: BattleEngine, claim: Dictionary, rng: RandomNumberGenerator, area_id: String = "", boss: bool = false) -> Dictionary:
	if claim.get("claimed", false) or battle.outcome != "victory":
		return {}
	claim["claimed"] = true
	var xp: int = 0
	var gold: int = 0
	for enemy: Dictionary in battle.enemies:
		xp += int(enemy.definition.xp)
		gold += int(enemy.definition.gold)
	if boss and area_id not in profile.cleared:
		profile.cleared.append(area_id)
		gold += 100
	profile.xp += xp
	profile.gold += gold
	var levels: int = 0
	while profile.xp >= profile.level * 30:
		profile.xp -= profile.level * 30
		profile.level += 1
		profile.base.max_hp += 5
		profile.base.strength += 1
		profile.base.wisdom += 1
		levels += 1
	profile.hp = mini(int(battle.player.hp), int(stats(profile, battle.definitions).max_hp))
	var item := loot(battle.definitions, rng, mini(int(profile.level), 999))
	profile.inventory.append(item)
	return {"xp": xp, "gold": gold, "levels": levels, "item": item}
