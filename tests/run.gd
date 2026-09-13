extends SceneTree

var failures: Array[String] = []
var checks: int = 0
var repo := DefinitionRepository.new()
var defs: Dictionary

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func fresh(enemy_ids: Array = ["mossling"], seed_value: int = 123) -> BattleEngine:
	var profile := Progression.new_player(defs)
	var engine := BattleEngine.new()
	engine.setup(defs, profile.base, 60, profile.deck, enemy_ids, seed_value)
	return engine

func state(engine: BattleEngine) -> String:
	return JSON.stringify([engine.player, engine.enemies, engine.deck, engine.hand, engine.ap, engine.turn, engine.outcome])

func autoplay(engine: BattleEngine) -> void:
	for step: int in 600:
		if not engine.outcome.is_empty() or not engine.fault.is_empty():
			return
		var target: int = -1
		for i: int in engine.enemies.size():
			if engine.enemies[i].hp > 0:
				target = i
				break
		var best: int = -1
		var score: float = -1
		for i: int in engine.hand.size():
			if not engine.can_play(i, target).is_empty():
				continue
			var card: Dictionary = engine.cards[engine.hand[i]]
			var value: float = 0
			for effect: Dictionary in card.effects:
				match effect.type:
					"damage": value += float(engine.effect_value(effect, engine.player).value) * (1.5 if effect.target == "all_enemies" else 1.0)
					"heal": value += minf(float(effect.value), float(engine.effective(engine.player).max_hp - engine.player.hp)) * 1.8
					"draw": value += 4 if engine.hand.size() < 3 else 0
					"block": value += maxf(0, 5.0 - engine.player.block)
					"apply_poison": value += 5
					"restore_mp": value += minf(4, float(engine.effective(engine.player).max_mp - engine.player.mp))
					"modify_stat": value += 2
			value /= float(card.ap)
			if value > score:
				score = value
				best = i
		if best >= 0:
			engine.play(best, target)
		else:
			engine.end_turn()

func run() -> void:
	expect(repo.reload(), "sample definitions validate: " + str(repo.errors))
	defs = repo.data
	if defs.is_empty():
		quit(1)
		return
	check_generator()
	var b := fresh()
	expect(b.hand.size() == 5 and b.deck.size() == 15 and b.turn == 1, "initial five, no extra first draw")
	var held := b.hand.duplicate()
	b.end_turn()
	expect(b.hand.slice(0, 5) == held and b.hand.size() == 6, "retained hand and one subsequent draw")
	b.draw(30)
	var deck_count := b.deck.size()
	b.draw(2)
	expect(b.hand.size() == 10 and b.deck.size() == deck_count, "hand limit preserves deck")
	b = fresh()
	b.hand = ["insight"]
	b.deck = ["strike"]
	b.play(0)
	expect(b.hand == ["strike"] and b.deck == ["insight"], "resolving card cannot draw itself and returns to bottom")
	b = fresh()
	b.hand = ["strike"]
	b.deck = []
	b.play(0, 0)
	expect(b.outcome.is_empty() and b.deck == ["strike"], "temporary empty deck and hand is not defeat")
	b = fresh()
	b.hand = ["strike"]
	var before := state(b)
	expect(not b.play(0, -1) and state(b) == before, "invalid target does not mutate")
	b.ap = 0
	before = state(b)
	expect(not b.play(0, 0) and state(b) == before, "insufficient AP does not mutate")
	b.ap = 3
	b.hand = ["fireball"]
	b.player.mp = 0
	before = state(b)
	expect(not b.play(0, 0) and state(b) == before, "insufficient MP does not mutate")
	b = fresh()
	b.hand = ["strike"]
	var preview := b.effect_value(b.cards.strike.effects[0], b.player)
	b.play(0, 0)
	expect(preview.value == 8 and b.enemies[0].hp == 12, "formula preview and actual damage both 8")
	b = fresh()
	b.player.block = 8
	b.player.poison = 3
	b.enemies[0].block = 5
	b.enemies[0].poison = 20
	b.end_turn()
	expect(b.enemies[0].block == 0 and b.enemies[0].hp == 0 and b.player.hp == 60, "enemy block clears before poison, dead enemy does not act")
	b = fresh()
	b.player.block = 20
	b.player.poison = 3
	b.end_turn()
	expect(b.player.block == 0 and b.player.hp == 57 and b.player.poison == 2, "player block absorbs enemy attack then clears before poison")
	b = fresh()
	b.player.hp = 0
	b.enemies[0].hp = 0
	b.check_outcome()
	expect(b.outcome == "defeat", "simultaneous death prioritizes defeat")
	for expression: String in ["1/0", "unknown + 1", "max(1,2)", "self.free()", "1 +", "(1+2", "1;2"]:
		expect(not FormulaEvaluator.new().evaluate(expression, {}).ok, "reject bad formula: " + expression)
	var valid := FormulaEvaluator.new().evaluate("-(2 + 3) * 4 / 2", {})
	expect(valid.ok and valid.value == -10, "arithmetic precedence and unary minus")
	var invalid := defs.duplicate(true)
	invalid.cards.entries.append(invalid.cards.entries[0].duplicate(true))
	expect(not repo.validate(invalid).is_empty(), "duplicate ID rejected")
	invalid = defs.duplicate(true)
	invalid.cards.entries[0].effects[0].formula_id = "missing"
	expect(not repo.validate(invalid).is_empty(), "broken reference rejected")
	invalid = defs.duplicate(true)
	invalid.areas.entries[0].nodes[3].next = []
	expect(not repo.validate(invalid).is_empty(), "unreachable boss rejected")
	invalid = defs.duplicate(true)
	invalid.areas.entries[0].nodes[3].next.append("start")
	expect(not repo.validate(invalid).is_empty(), "cycles rejected")
	var a := fresh(["thorn", "mossling"], 9876)
	var c := fresh(["thorn", "mossling"], 9876)
	autoplay(a)
	autoplay(c)
	expect(state(a) == state(c), "same seed, state and commands reproduce battle")
	var profile := Progression.new_player(defs)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	b = fresh(["warden"])
	b.enemies[0].hp = 0
	b.check_outcome()
	var claim: Dictionary = {}
	var reward := Progression.reward(profile, b, claim, rng, "forest", true)
	var previous := JSON.stringify(profile)
	expect(Progression.reward(profile, b, claim, rng, "forest", true).is_empty() and JSON.stringify(profile) == previous, "reward claimed once")
	var repeat := Progression.reward(profile, b, {}, rng, "forest", true)
	expect(reward.gold == 130 and repeat.gold == 30 and profile.cleared.size() == 1, "first-clear bonus once")
	var saves := SaveRepository.new()
	saves.path = "res://.godot/tests/profile.json"
	expect(saves.save(profile, defs), "save succeeds: " + saves.error)
	var loaded := saves.read_profile(defs)
	expect(not loaded.is_empty() and JSON.stringify(loaded.inventory) == JSON.stringify(profile.inventory), "rolled item values survive load: " + saves.error)
	var original := FileAccess.get_file_as_string(saves.path)
	var corrupt := FileAccess.open(saves.path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	expect(saves.read_profile(defs).is_empty() and not saves.save(profile, defs) and FileAccess.get_file_as_string(saves.path) == "{broken", "corrupt save is preserved and writes blocked")
	corrupt = FileAccess.open(saves.path, FileAccess.WRITE)
	corrupt.store_string(original)
	corrupt.close()
	# Full sample area, both routes, with actual combat and progression.
	var wins: int = 0
	for seed_value: int in range(1, 21):
		profile = Progression.new_player(defs)
		for enemies: Array in [["mossling"] if seed_value % 2 else ["wisp"], ["thorn", "mossling"], ["warden"]]:
			b = BattleEngine.new()
			b.setup(defs, Progression.stats(profile, defs), int(profile.hp), profile.deck, enemies, seed_value)
			autoplay(b)
			if b.outcome != "victory":
				break
			Progression.reward(profile, b, {}, rng)
		if b.outcome == "victory":
			wins += 1
	expect(wins > 0, "sample area is winnable")
	print("Sample area autoplay wins: %d/20" % wins)
	# Exercise shared UI/session boundaries in the actual scene.
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.saves.path = "res://.godot/tests/ui-profile.json"
	main.new_game()
	main.depart()
	main.node_id = "a"
	main.start_battle(["mossling"])
	var preserved := state(main.battle)
	var disk_before := FileAccess.get_file_as_string(main.saves.path)
	main.open_editor()
	await process_frame
	main.editor.group = "generator"
	main.editor.refresh()
	var save_before_generator := FileAccess.get_file_as_string(main.saves.path)
	var generated_panel: GeneratorPanel = main.editor.generator_panel
	generated_panel.filter_rarity = "rare"
	generated_panel.amount = 5
	expect(generated_panel.generate_items(false) and generated_panel.results.size() == 5, "generator UI produces requested batch")
	expect(FileAccess.get_file_as_string(main.saves.path) == save_before_generator, "preview generator never writes normal save")
	generated_panel.section = "rarity"
	generated_panel.refresh()
	main.editor.group = "cards"
	main.editor.selected_id = "strike"
	main.editor.refresh()
	# Isolate editor writes from authored sample files.
	main.repository.root = "res://.godot/tests/editor_data"
	DirAccess.make_dir_recursive_absolute(main.repository.root)
	for group: String in DefinitionRepository.GROUPS:
		DirAccess.copy_absolute("res://data/" + group + ".json", main.repository.root + "/" + group + ".json")
	main.editor.draft.cards.entries[0].effects[0].value = 12
	main.editor.changed()
	expect(main.editor.save(), "editor saves valid draft")
	main.start_test(main.editor.test_settings, false)
	main.battle.hand = ["strike"]
	main.battle.play(0, 0)
	expect(main.battle.enemies[0].hp == 6, "saved card base 12 changes test damage to 14")
	var test_hand: Array = main.battle.deck.duplicate()
	main.start_test(main.test_config, false)
	var restart_hand: Array = main.battle.hand.duplicate()
	main.start_test(main.test_config, false)
	expect(main.battle.hand == restart_hand and not test_hand.is_empty(), "same-condition restart reuses initial seed")
	main.battle.enemies[0].hp = 0
	main.battle.check_outcome()
	main.after_action()
	expect(FileAccess.get_file_as_string(main.saves.path) == disk_before, "test rewards never touch normal save")
	main.return_editor()
	expect(main.editor.group == "cards" and main.editor.selected_id == "strike", "editor selection survives test")
	var valid_disk := FileAccess.get_file_as_string(main.repository.root + "/cards.json")
	main.editor.draft.cards.entries[0].effects[0].formula_id = "missing"
	expect(not main.editor.save() and FileAccess.get_file_as_string(main.repository.root + "/cards.json") == valid_disk, "invalid editor draft cannot overwrite disk")
	main.editor.reload_draft()
	main.editor.dirty = true
	main.editor.guard_change(func() -> void: failures.append("cancel unexpectedly ran guarded action"))
	var dialog: ConfirmationDialog = main.editor.get_child(main.editor.get_child_count() - 1)
	dialog.hide()
	dialog.canceled.emit()
	expect(main.editor.dirty, "unsaved dialog cancel preserves draft")
	main.close_editor()
	await process_frame
	expect(state(main.battle) == preserved and main.screen == "battle", "normal battle resumes unchanged after editor/test")
	main.battle.player.hp = 0
	main.battle.check_outcome()
	main.after_action()
	expect(main.screen == "hub" and main.profile.hp == Progression.stats(main.profile, main.snapshot).max_hp, "defeat returns to healed hub")
	main.depart()
	main.retreat()
	var retreat_dialog: ConfirmationDialog = main.get_child(main.get_child_count() - 1)
	retreat_dialog.confirmed.emit()
	expect(main.screen == "hub" and main.area_id.is_empty(), "confirmed retreat discards expedition")
	main.queue_free()
	await process_frame
	print("CHECKS: %d; FAILURES: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check_generator() -> void:
	var generator := EquipmentGenerator.new(defs)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9123
	for rarity: String in EquipmentGenerator.RARITIES:
		var valid: bool = true
		for i: int in 200:
			var item: Dictionary = generator.generate(rng, 10, rarity).item
			valid = valid and item.affixes.size() in EquipmentGenerator.COUNTS[rarity]
			var ids: Dictionary = {}
			for affix: Dictionary in item.affixes:
				ids[affix.id] = true
			valid = valid and ids.size() == item.affixes.size()
		expect(valid, "generator count range and no duplicate affixes: " + rarity)
	for slot: String in EquipmentGenerator.SLOTS:
		var item: Dictionary = generator.generate(rng, 1, "common", "", slot).item
		expect(generator.bases[item.base_id].slot == slot, "generator slot filter: " + slot)
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 1234
	b.seed = 1234
	expect(generator.generate(a, 15) == generator.generate(b, 15), "generator same seed is reproducible")
	var one: Dictionary = generator.generate(rng, 1, "rare", "sword").item
	expect(one.has("name") and not str(one.name).is_empty(), "generated items have a random name")
	var has_left: bool = false
	var has_link: bool = false
	var has_right: bool = false
	for part: String in EquipmentGenerator.NAME_LEFT:
		has_left = has_left or one.name.begins_with(part)
	for part: String in EquipmentGenerator.NAME_LINKS:
		has_link = has_link or part in one.name
	for part: String in EquipmentGenerator.NAME_RIGHT.right_hand:
		has_right = has_right or one.name.ends_with(part)
	expect(has_left and has_link and has_right, "equipment names combine left name, linking phrase and slot-appropriate right name")
	var eleven: Dictionary = generator.generate(rng, 11, "rare", "sword").item
	expect(one.base_bonuses.strength == 2 and eleven.base_bonuses.strength == 6, "level growth applies to rolled base stats")
	expect(not generator.generate(rng, 0).ok and not generator.generate(rng, 1, "invalid").ok and not generator.generate(rng, 1, "common", "sword", "feet").ok, "invalid generator requests rejected")
	var policies: Dictionary = repo.indexed("rules", defs).loot
	var forced := defs.duplicate(true)
	var forced_policies: Array = repo.indexed("rules", forced).loot.rarities
	for policy: Dictionary in forced_policies:
		if policy.id == "rare":
			policy.count_weights = {"7": 100}
		if policy.id == "common":
			for id: String in policy.value_ranges:
				policy.value_ranges[id].exception_chance = 100
		if policy.id == "magic":
			policy.count_weights = {"1": 100}
			for id: String in policy.affix_weights:
				policy.affix_weights[id] = 1 if id == "blue_star" else 0
	expect(repo.validate(forced).is_empty(), "forced boundary distributions validate")
	var forced_generator := EquipmentGenerator.new(forced)
	expect(forced_generator.generate(rng, 1, "rare").item.affixes.size() == 7, "editable weights can force seven affixes")
	var exceptional: Dictionary = forced_generator.generate(rng, 1, "common").item.affixes[0]
	expect(exceptional.exceptional and exceptional.value > generator.rarities.rare.value_ranges[exceptional.id].max, "common exceptional roll can exceed rare maximum")
	expect(forced_generator.generate(rng, 1, "magic").item.affixes[0].id == "blue_star", "magic-only affix can be enabled by rarity weight")
	var forbidden_seen: bool = false
	var high_counts: int = 0
	var rare_count: int = 0
	rng.seed = 556677
	for i: int in 10000:
		var item: Dictionary = generator.generate(rng, 1, "rare").item
		if item.affixes.size() >= 6:
			high_counts += 1
		for affix: Dictionary in item.affixes:
			forbidden_seen = forbidden_seen or affix.id == "blue_star"
		if item.rarity == "rare":
			rare_count += 1
	expect(not forbidden_seen, "zero-weight magic-only affix never appears on rare")
	expect(high_counts > 0 and high_counts < 50 and rare_count == 10000, "six/seven affixes are exceptionally rare for fixed sample seed")
	print("Rare six/seven affixes: %d/10000" % high_counts)
	var invalid := defs.duplicate(true)
	repo.indexed("rules", invalid).loot.rarities[0].count_weights = {"2": 100}
	expect(not repo.validate(invalid).is_empty(), "common two-affix configuration rejected")
	invalid = defs.duplicate(true)
	repo.indexed("rules", invalid).loot.rarities[2].affix_weights = {"vital": 100}
	expect(not repo.validate(invalid).is_empty(), "insufficient distinct affix candidates rejected")
	invalid = defs.duplicate(true)
	repo.indexed("rules", invalid).loot.rarities[0].value_ranges.vital.min = 999
	expect(not repo.validate(invalid).is_empty(), "inverted generator value range rejected")
	var profile := Progression.new_player(defs)
	profile.level = 20
	var right: Dictionary = generator.generate(rng, 1, "common", "sword").item
	var left: Dictionary = generator.generate(rng, 1, "common", "shield").item
	var both: Dictionary = generator.generate(rng, 1, "common", "staff").item
	right.instance_id = "right"
	left.instance_id = "left"
	both.instance_id = "both"
	profile.inventory = [right, left, both]
	Progression.equip(profile, right, defs)
	Progression.equip(profile, left, defs)
	expect(profile.equipped.size() == 2, "independent right and left slots")
	Progression.equip(profile, both, defs)
	expect(profile.equipped == {"two_handed": "both"}, "two-handed item replaces both hands")
	Progression.equip(profile, left, defs)
	expect(profile.equipped == {"left_hand": "left"}, "one-handed item removes two-handed item")
	profile.equipped.two_handed = "both"
	expect(not SaveRepository.new().validate(profile, defs).is_empty(), "invalid simultaneous hand equipment rejected on load")
	var legacy := Progression.new_player(defs)
	legacy.save_version = 1
	legacy.inventory = [{"instance_id": "old", "base_id": "staff", "rarity": "common", "affixes": []}]
	legacy.equipped = {"weapon": "old"}
	var saver := SaveRepository.new()
	var migrated := saver.migrate(legacy, defs)
	expect(migrated.ok and saver.validate(migrated.profile, defs).is_empty() and migrated.profile.equipped == {"two_handed": "old"} and migrated.profile.inventory[0].affixes.is_empty(), "old save migrates slots without rerolling existing equipment")
	expect(legacy.save_version == 1 and legacy.equipped == {"weapon": "old"}, "migration preserves original input")
	saver.path = "res://.godot/tests/legacy-profile.json"
	var file := FileAccess.open(saver.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var old_file := FileAccess.get_file_as_string(saver.path)
	var loaded := saver.read_profile(defs)
	expect(not loaded.is_empty() and loaded.save_version == 2 and loaded.inventory[0].affixes.is_empty() and FileAccess.get_file_as_string(saver.path) == old_file, "legacy file loads without overwriting or rerolling")
	var upgrade := DefinitionRepository.new()
	upgrade.root = "res://.godot/tests/legacy_data"
	DirAccess.make_dir_recursive_absolute(upgrade.root)
	for group: String in DefinitionRepository.GROUPS:
		var document: Dictionary = defs[group].duplicate(true)
		if group == "rules":
			document.entries.pop_back()
		file = FileAccess.open(upgrade.root + "/" + group + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify(document))
		file.close()
	expect(not upgrade.reload(), "old definition set is not silently mixed with new defaults")
	expect(upgrade.install_bundled() and FileAccess.file_exists(upgrade.last_backup_path + "/rules.json"), "explicit definition update preserves a durable backup")
	expect(EquipmentGenerator.COLORS.size() == 5 and policies.rarities.size() == 5, "five rarity colors and policies")
