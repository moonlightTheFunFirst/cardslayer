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
	expect(not loaded.is_empty() and JSON.stringify(loaded.inventory) == JSON.stringify(profile.inventory), "rolled item values survive load")
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
