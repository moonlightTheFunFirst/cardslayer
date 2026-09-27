class_name BattleEngine
extends RefCounted

## Actor fields that count as bad statuses (cured by e.g. 万能薬).
const BAD_STATUSES: Array[String] = ["poison"]

var definitions: Dictionary
var models: DefinitionModels
var cards: Dictionary
var formulas: Dictionary
var rules: Dictionary
var player: Dictionary
var enemies: Array[Dictionary] = []
var deck: Array = []
var hand: Array = []
var resolving: String = ""
var ap: int = 0
var turn: int = 1
var outcome: String = ""
var fault: String = ""
var log: Array[String] = []
var rng := RandomNumberGenerator.new()
var busy: bool = false
# Presentation-only record of what the last action did, in order. The battle
# view replays it as animations; game logic never reads it.
var events: Array[Dictionary] = []
var effect_group: int = 0
## Carried consumable ids by belt slot; "" once used.
var items: Array = []
var used_items: Array[String] = []
var consumables: Dictionary = {}
## Separate stream so item rolls never shift the deck shuffle.
var item_rng := RandomNumberGenerator.new()

func setup(snapshot: Dictionary, stats: Dictionary, current_hp: int, deck_ids: Array, enemy_ids: Array, seed_value: int, carried: Array = []) -> void:
	definitions = snapshot.duplicate(true)
	models = DefinitionModels.new(definitions)
	var repo := DefinitionRepository.new()
	consumables = repo.indexed("consumables", definitions)
	items = carried.duplicate()
	item_rng.seed = seed_value + 7919
	cards = repo.indexed("cards", definitions)
	formulas = repo.indexed("formulas", definitions)
	rules = repo.indexed("rules", definitions).combat
	player = actor("player", "英雄", stats, current_hp)
	var enemy_defs := repo.indexed("enemies", definitions)
	for id: String in enemy_ids:
		var definition: Dictionary = enemy_defs[id]
		var enemy := actor(id, definition.name, {"max_hp": definition.hp, "max_mp": 0, "strength": definition.strength, "wisdom": definition.wisdom, "agility": 0, "luck": 0}, int(definition.hp))
		enemy["definition"] = definition
		enemy["action"] = 0
		enemies.append(enemy)
	rng.seed = seed_value
	deck = deck_ids.duplicate()
	for i: int in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = deck[i]
		deck[i] = deck[j]
		deck[j] = swap
	ap = int(rules.ap)
	draw(int(rules.initial_hand))
	log.append("戦闘開始 / seed %d" % seed_value)
	check_outcome()

func actor(id: String, actor_name: String, stats: Dictionary, hp: int) -> Dictionary:
	return {"id": id, "name": actor_name, "stats": stats.duplicate(true), "buffs": {}, "hp": clampi(hp, 0, int(stats.max_hp)), "mp": int(stats.max_mp), "block": 0, "poison": 0, "reduction": 0}

func effective(who: Dictionary) -> Dictionary:
	var result: Dictionary = who.stats.duplicate()
	for stat: String in who.buffs:
		result[stat] = result.get(stat, 0) + who.buffs[stat]
	return result

func draw(count: int) -> void:
	var drawn: Array = []
	for i: int in count:
		if deck.is_empty() or hand.size() >= int(rules.hand_limit):
			break
		drawn.append(deck.front())
		hand.append(deck.pop_front())
	if not drawn.is_empty():
		record("draw", {"ids": drawn})

func record(kind: String, data: Dictionary = {}) -> void:
	data["kind"] = kind
	events.append(data)

func actor_index(who: Dictionary) -> int:
	if is_same(who, player):
		return -1
	for i: int in enemies.size():
		if is_same(enemies[i], who):
			return i
	return -2

func state_of(who: Dictionary) -> Dictionary:
	return {"hp": who.hp, "max_hp": int(effective(who).max_hp), "block": who.block, "poison": who.poison, "reduction": int(who.get("reduction", 0)), "buffs": who.buffs.duplicate(), "mp": who.mp}

func needs_target(card: Dictionary) -> bool:
	for effect: Dictionary in card.effects:
		if effect.target == "selected_enemy":
			return true
	return false

func can_play(index: int, target: int = -1, check_target: bool = true) -> String:
	if busy or not outcome.is_empty() or not fault.is_empty():
		return "現在は操作できません"
	if index < 0 or index >= hand.size():
		return "手札がありません"
	var card: DefinitionModels.Card = models.cards[hand[index]]
	if ap < card.ap:
		return "AP不足"
	if player.mp < int(card.mp):
		return "MP不足"
	if check_target and needs_target(cards[card.id]) and (target < 0 or target >= enemies.size() or enemies[target].hp <= 0):
		return "生存する敵を選択してください"
	return ""

func play(index: int, target: int = -1) -> bool:
	if not can_play(index, target).is_empty():
		return false
	busy = true
	events.clear()
	var card: Dictionary = cards[hand[index]]
	ap -= int(card.ap)
	player.mp -= int(card.mp)
	resolving = hand.pop_at(index)
	record("card", {"card": resolving, "index": index, "target": target, "ap": ap, "mp": player.mp})
	log.append("%s / AP %d MP %d" % [card.name, card.ap, card.mp])
	resolve(card.effects, player, target)
	deck.append(resolving)
	resolving = ""
	check_outcome()
	busy = false
	return true

func resolve(effects: Array, source: Dictionary, selected: int) -> void:
	for effect: Dictionary in effects:
		effect_group += 1
		var targets: Array[Dictionary] = []
		match effect.target:
			"self": targets.append(source)
			"player": targets.append(player)
			"selected_enemy":
				if selected >= 0 and selected < enemies.size():
					targets.append(enemies[selected])
			"all_enemies":
				for enemy: Dictionary in enemies:
					if enemy.hp > 0:
						targets.append(enemy)
		for target: Dictionary in targets:
			if target.hp <= 0:
				continue
			var evaluated := effect_value(effect, source)
			if not evaluated.ok:
				fault = evaluated.error
				log.append("数式エラー: " + fault)
				return
			var amount: int = int(evaluated.value)
			if not str(effect.get("formula_id", "")).is_empty():
				log.append("式 %s inputs=%s → %d" % [effect.formula_id, str(evaluated.inputs), amount])
			apply_effect(effect.type, amount, source, target, str(effect.get("stat", "")), str(effect.get("formula_id", "")).contains("magic"))

## Applies one resolved effect and records it for the battle view. Shared by
## cards, enemy actions and consumables.
func apply_effect(type: String, amount: int, source: Dictionary, target: Dictionary, stat: String = "", magic: bool = false) -> void:
	var absorbed: int = 0
	match type:
		"damage":
			amount = maxi(0, amount - int(target.get("reduction", 0)))
			absorbed = mini(int(target.block), amount)
			target.block -= absorbed
			target.hp = maxi(0, int(target.hp) - amount + absorbed)
		"block": target.block += amount
		"heal": target.hp = mini(int(effective(target).max_hp), int(target.hp) + amount)
		"restore_mp": target.mp = mini(int(effective(target).max_mp), int(target.mp) + amount)
		"draw":
			if is_same(target, player):
				draw(amount)
		"apply_poison": target.poison += amount
		"modify_stat": target.buffs[stat] = target.buffs.get(stat, 0) + amount
		"reduce_damage": target.reduction = int(target.get("reduction", 0)) + amount
		"cure":
			amount = int(target.get(stat, 0))
			target[stat] = 0
	var label: String = UiText.name_for(stat) + " " + UiText.name_for(type) if type == "cure" else UiText.name_for(type)
	log.append("%s → %s %s %d" % [source.name, target.name, label, amount])
	record("effect", {"type": type, "source": actor_index(source), "target": actor_index(target), "amount": amount, "absorbed": absorbed, "group": effect_group, "stat": stat, "magic": magic, "state": state_of(target)})

## Consumable effect on target, attributed to the player.
func item_effect(type: String, amount: int, target: Dictionary, stat: String = "", new_group: bool = true) -> void:
	if new_group:
		effect_group += 1
	apply_effect(type, amount, player, target, stat)

# ------------------------------------------------------------------ consumables

func item_definition(slot: int) -> Dictionary:
	if slot < 0 or slot >= items.size() or str(items[slot]).is_empty():
		return {}
	return consumables.get(items[slot], {})

func item_needs_target(slot: int) -> bool:
	return item_definition(slot).get("target", "self") == "selected_enemy"

## "" when the item in slot can be used now, otherwise the reason.
func item_reason(slot: int, target: int = -1, check_target: bool = true) -> String:
	if busy or not outcome.is_empty() or not fault.is_empty():
		return "現在は使用できません"
	var item := item_definition(slot)
	if item.is_empty():
		return "アイテムがありません"
	if item_needs_target(slot) and not check_target:
		# Aiming happens after picking the item; only check the target-free conditions.
		for i: int in enemies.size():
			if int(enemies[i].hp) > 0:
				return ItemRunner.can_use(item, ItemContext.for_battle(self, item, i))
		return "対象の敵がいません"
	return ItemRunner.can_use(item, ItemContext.for_battle(self, item, target))

func use_item(slot: int, target: int = -1) -> bool:
	if not item_reason(slot, target).is_empty():
		return false
	busy = true
	events.clear()
	var item := item_definition(slot)
	var id: String = items[slot]
	items[slot] = ""
	used_items.append(id)
	record("item", {"id": id, "slot": slot, "target": target})
	log.append("アイテム: " + str(item.name))
	ItemRunner.use(item, ItemContext.for_battle(self, item, target))
	check_outcome()
	busy = false
	return true

func effect_value(effect: Dictionary, source: Dictionary) -> Dictionary:
	return BattleEngine.evaluate_effect(effect, effective(source), formulas)

## Effect amount for a stat block; also used to preview cards outside battle.
static func evaluate_effect(effect: Dictionary, stats: Dictionary, formula_index: Dictionary) -> Dictionary:
	var inputs := stats.duplicate()
	inputs["base"] = effect.value
	inputs["scaling"] = effect.get("scaling", 0)
	var result: Dictionary = {"ok": true, "value": float(effect.value)}
	if not str(effect.get("formula_id", "")).is_empty():
		result = FormulaEvaluator.new().evaluate(formula_index[effect.formula_id].expression, inputs)
	if result.ok:
		if float(result.value) > 2147483647.0:
			return {"ok": false, "error": "数式結果が処理可能範囲を超えています", "inputs": inputs}
		result.value = int(floor(maxf(0, float(result.value))))
	result["inputs"] = inputs
	return result

func begin_phase(who: Dictionary) -> void:
	who.block = 0
	var poisoned: int = int(who.poison)
	if who.poison > 0:
		log.append("%s 毒 %d" % [who.name, who.poison])
		who.hp = maxi(0, int(who.hp) - int(who.poison))
		who.poison -= 1
	record("phase", {"target": actor_index(who), "poison": poisoned, "state": state_of(who)})

func end_turn() -> void:
	if busy or not outcome.is_empty() or not fault.is_empty():
		return
	busy = true
	events.clear()
	record("enemy_turn")
	for enemy: Dictionary in enemies:
		if enemy.hp <= 0:
			continue
		begin_phase(enemy)
		check_outcome()
		if not outcome.is_empty():
			break
		if enemy.hp <= 0:
			continue
		var actions: Array = enemy.definition.actions
		var action: Dictionary = actions[int(enemy.action) % actions.size()]
		log.append(enemy.name + " / " + action.name)
		record("act", {"source": actor_index(enemy), "name": action.name})
		resolve(action.effects, enemy, -1)
		enemy.action += 1
		check_outcome()
		if not outcome.is_empty() or not fault.is_empty():
			break
	if outcome.is_empty() and fault.is_empty():
		begin_phase(player)
		check_outcome()
		if outcome.is_empty():
			turn += 1
			ap = int(rules.ap)
			player.mp = mini(int(effective(player).max_mp), int(player.mp) + int(rules.mp_regen))
			record("turn", {"turn": turn, "ap": ap, "mp": player.mp})
			draw(int(rules.draw))
			check_outcome()
	busy = false

func check_outcome() -> void:
	if player.hp <= 0 or (hand.is_empty() and deck.is_empty() and resolving.is_empty()):
		outcome = "defeat"
		return
	for enemy: Dictionary in enemies:
		if enemy.hp > 0:
			return
	outcome = "victory"

func intent(enemy: Dictionary) -> String:
	if enemy.hp <= 0:
		return "撃破"
	var actions: Array = enemy.definition.actions
	var action: Dictionary = actions[int(enemy.action) % actions.size()]
	var parts: Array[String] = []
	for effect: Dictionary in action.effects:
		var result := effect_value(effect, enemy)
		parts.append("%s → %s : %s" % [UiText.name_for(effect.type), UiText.name_for(effect.target), str(result.value) if result.ok else result.error])
	return action.name + "\n" + "\n".join(parts)
