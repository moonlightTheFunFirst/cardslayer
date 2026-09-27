class_name ItemContext
extends RefCounted

## The API an item script (and the basic effects) may use. In battle every
## change goes through BattleEngine so it is logged and animated; in the field
## (map) only HP/MP exist and battle-only calls do nothing.

var engine: BattleEngine
var profile: Dictionary
var snapshot: Dictionary
var rng: RandomNumberGenerator
var target_index: int = -1
var definition: Dictionary = {}
## Field-use results for UI popups: {"type", "amount"} / {"type": "message", "text"}.
var results: Array[Dictionary] = []

static func for_battle(battle: BattleEngine, item: Dictionary, target: int) -> ItemContext:
	var ctx := ItemContext.new()
	ctx.engine = battle
	ctx.rng = battle.item_rng
	ctx.target_index = target
	ctx.definition = item
	return ctx

static func for_field(player_profile: Dictionary, definitions: Dictionary, item: Dictionary, random: RandomNumberGenerator) -> ItemContext:
	var ctx := ItemContext.new()
	ctx.profile = player_profile
	ctx.snapshot = definitions
	ctx.rng = random
	ctx.definition = item
	return ctx

# ------------------------------------------------------------------ queries

func in_battle() -> bool:
	return engine != null

func stats() -> Dictionary:
	return engine.effective(engine.player) if in_battle() else Progression.stats(profile, snapshot)

func hp() -> int:
	return int(engine.player.hp) if in_battle() else int(profile.hp)

func max_hp() -> int:
	return int(stats().max_hp)

func mp() -> int:
	return int(engine.player.mp) if in_battle() else int(profile.mp)

func max_mp() -> int:
	return int(stats().max_mp)

func stat(name: String) -> int:
	return int(stats().get(name, 0))

func bad_statuses() -> Array[String]:
	var found: Array[String] = []
	if in_battle():
		for status: String in BattleEngine.BAD_STATUSES:
			if int(engine.player.get(status, 0)) > 0:
				found.append(status)
	return found

func has_target() -> bool:
	return in_battle() and target_index >= 0 and target_index < engine.enemies.size() and int(engine.enemies[target_index].hp) > 0

func target_hp() -> int:
	return int(engine.enemies[target_index].hp) if has_target() else 0

func rand_int(low: int, high: int) -> int:
	return rng.randi_range(mini(low, high), maxi(low, high))

# ------------------------------------------------------------------ basic effects

## Reason from the item's selected conditions; "" when usable.
func basic_reason() -> String:
	for condition: String in definition.get("conditions", []):
		match condition:
			"hp_not_full":
				if hp() >= max_hp():
					return "HPが満タンです"
			"mp_not_full":
				if mp() >= max_mp():
					return "MPが満タンです"
			"has_bad_status":
				if bad_statuses().is_empty():
					return "解除できるバッドステータスがありません"
	return ""

func apply_basic() -> void:
	for effect: Dictionary in definition.get("basic_effects", []):
		var amount := rand_int(int(effect.min), int(effect.max))
		match str(effect.kind):
			"heal": heal(amount)
			"restore_mp": restore_mp(amount)
			"block": add_block(amount)
			"modify_stat": add_stat(str(effect.stat), amount)
			"reduce_damage": reduce_damage(amount)
			"cure_bad_status":
				for i: int in maxi(1, amount):
					cure_random()
			"damage": damage_target(amount)
			"damage_all": damage_all(amount)
			"draw": draw(amount)

# ------------------------------------------------------------------ actions

func heal(amount: int) -> int:
	var before := hp()
	if in_battle():
		engine.item_effect("heal", amount, engine.player)
	else:
		profile.hp = mini(max_hp(), int(profile.hp) + amount)
		results.append({"type": "heal", "amount": hp() - before})
	return hp() - before

func restore_mp(amount: int) -> int:
	var before := mp()
	if in_battle():
		engine.item_effect("restore_mp", amount, engine.player)
	else:
		profile.mp = mini(max_mp(), int(profile.mp) + amount)
		results.append({"type": "restore_mp", "amount": mp() - before})
	return mp() - before

func add_block(amount: int) -> void:
	if in_battle():
		engine.item_effect("block", amount, engine.player)

func add_stat(name: String, amount: int) -> void:
	if in_battle() and name in DefinitionRepository.STATS:
		engine.item_effect("modify_stat", amount, engine.player, name)

func reduce_damage(amount: int) -> void:
	if in_battle():
		engine.item_effect("reduce_damage", amount, engine.player)

func cure(status: String) -> bool:
	if not status in bad_statuses():
		return false
	engine.item_effect("cure", 0, engine.player, status)
	return true

## Removes one random bad status; returns its id or "".
func cure_random() -> String:
	var found := bad_statuses()
	if found.is_empty():
		return ""
	var status: String = found[rng.randi_range(0, found.size() - 1)]
	cure(status)
	return status

func damage_target(amount: int) -> void:
	if has_target():
		engine.item_effect("damage", amount, engine.enemies[target_index])

func damage_all(amount: int) -> void:
	if not in_battle():
		return
	engine.effect_group += 1
	for enemy: Dictionary in engine.enemies:
		if int(enemy.hp) > 0:
			engine.item_effect("damage", amount, enemy, "", false)

func draw(amount: int) -> void:
	if in_battle():
		engine.draw(amount)

func message(text: String) -> void:
	if in_battle():
		engine.log.append(text)
		engine.record("message", {"text": text})
	else:
		results.append({"type": "message", "text": text})
