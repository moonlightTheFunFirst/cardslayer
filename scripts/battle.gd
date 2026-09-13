class_name BattleEngine
extends RefCounted

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

func setup(snapshot: Dictionary, stats: Dictionary, current_hp: int, deck_ids: Array, enemy_ids: Array, seed_value: int) -> void:
	definitions = snapshot.duplicate(true)
	models = DefinitionModels.new(definitions)
	var repo := DefinitionRepository.new()
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
	return {"id": id, "name": actor_name, "stats": stats.duplicate(true), "buffs": {}, "hp": clampi(hp, 0, int(stats.max_hp)), "mp": int(stats.max_mp), "block": 0, "poison": 0}

func effective(who: Dictionary) -> Dictionary:
	var result: Dictionary = who.stats.duplicate()
	for stat: String in who.buffs:
		result[stat] = result.get(stat, 0) + who.buffs[stat]
	return result

func draw(count: int) -> void:
	for i: int in count:
		if deck.is_empty() or hand.size() >= int(rules.hand_limit):
			break
		hand.append(deck.pop_front())

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
	var card: Dictionary = cards[hand[index]]
	ap -= int(card.ap)
	player.mp -= int(card.mp)
	resolving = hand.pop_at(index)
	log.append("%s / AP %d MP %d" % [card.name, card.ap, card.mp])
	resolve(card.effects, player, target)
	deck.append(resolving)
	resolving = ""
	check_outcome()
	busy = false
	return true

func resolve(effects: Array, source: Dictionary, selected: int) -> void:
	for effect: Dictionary in effects:
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
			match effect.type:
				"damage":
					var absorbed := mini(int(target.block), amount)
					target.block -= absorbed
					target.hp = maxi(0, int(target.hp) - amount + absorbed)
				"block": target.block += amount
				"heal": target.hp = mini(int(effective(target).max_hp), int(target.hp) + amount)
				"restore_mp": target.mp = mini(int(effective(target).max_mp), int(target.mp) + amount)
				"draw":
					if target == player:
						draw(amount)
				"apply_poison": target.poison += amount
				"modify_stat": target.buffs[effect.stat] = target.buffs.get(effect.stat, 0) + amount
			log.append("%s → %s %s %d" % [source.name, target.name, UiText.name_for(effect.type), amount])

func effect_value(effect: Dictionary, source: Dictionary) -> Dictionary:
	var inputs := effective(source)
	inputs["base"] = effect.value
	inputs["scaling"] = effect.get("scaling", 0)
	var result: Dictionary = {"ok": true, "value": float(effect.value)}
	if not str(effect.get("formula_id", "")).is_empty():
		result = FormulaEvaluator.new().evaluate(formulas[effect.formula_id].expression, inputs)
	if result.ok:
		if float(result.value) > 2147483647.0:
			return {"ok": false, "error": "数式結果が処理可能範囲を超えています", "inputs": inputs}
		result.value = int(floor(maxf(0, float(result.value))))
	result["inputs"] = inputs
	return result

func begin_phase(who: Dictionary) -> void:
	who.block = 0
	if who.poison > 0:
		log.append("%s 毒 %d" % [who.name, who.poison])
		who.hp = maxi(0, int(who.hp) - int(who.poison))
		who.poison -= 1

func end_turn() -> void:
	if busy or not outcome.is_empty() or not fault.is_empty():
		return
	busy = true
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
