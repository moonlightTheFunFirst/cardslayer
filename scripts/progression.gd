class_name Progression
extends RefCounted

static func new_player(snapshot: Dictionary) -> Dictionary:
	var rules: Dictionary = DefinitionRepository.new().indexed("rules", snapshot).combat
	return {"save_version": 1, "level": 1, "xp": 0, "gold": 0, "base": {"max_hp": 60, "max_mp": 10, "strength": 5, "wisdom": 5, "agility": 5, "luck": 5}, "inventory": [], "equipped": {}, "deck": rules.starter_deck.duplicate(), "cleared": [], "hp": 60, "mp": 10}

static func stats(profile: Dictionary, snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = profile.base.duplicate()
	var bases := DefinitionRepository.new().indexed("items", snapshot)
	for instance: Dictionary in profile.inventory:
		if instance.instance_id not in profile.equipped.values():
			continue
		for stat: String in bases[instance.base_id].bonuses:
			result[stat] += bases[instance.base_id].bonuses[stat]
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

static func weighted(candidates: Array, weights: Array, rng: RandomNumberGenerator) -> Variant:
	var total: float = 0
	for weight: Variant in weights:
		total += float(weight)
	var roll := rng.randf() * total
	for i: int in candidates.size():
		roll -= float(weights[i])
		if roll < 0:
			return candidates[i]
	return candidates.back()

static func loot(snapshot: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var repo := DefinitionRepository.new()
	var rules: Dictionary = repo.indexed("rules", snapshot).combat
	var bases := repo.indexed("items", snapshot)
	var affixes := repo.indexed("affixes", snapshot)
	var base_id: String = rules.loot_bases[rng.randi_range(0, rules.loot_bases.size() - 1)]
	var rarities: Array = ["common", "magic", "rare"]
	var rarity: String = weighted(rarities, [rules.rarity_weights.common, rules.rarity_weights.magic, rules.rarity_weights.rare], rng)
	var result: Dictionary = {"instance_id": "%x_%x_%x" % [Time.get_ticks_usec(), rng.randi(), rng.randi()], "base_id": base_id, "rarity": rarity, "affixes": []}
	var candidates: Array = bases[base_id].affixes.duplicate()
	for i: int in rarities.find(rarity):
		var weights: Array = []
		for id: String in candidates:
			weights.append(affixes[id].weight)
		var selected: String = weighted(candidates, weights, rng)
		var affix: Dictionary = affixes[selected]
		result.affixes.append({"id": selected, "stat": affix.stat, "value": rng.randi_range(int(affix.min), int(affix.max))})
		candidates.erase(selected)
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
	var item := loot(battle.definitions, rng)
	profile.inventory.append(item)
	return {"xp": xp, "gold": gold, "levels": levels, "item": item}
