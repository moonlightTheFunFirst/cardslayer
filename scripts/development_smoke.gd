class_name DevelopmentSmoke
extends Node

func run(app: Control) -> void:
	var results: Dictionary = {"data_root": app.repository.root, "editor_build": OS.has_feature("editor"), "checks": {}}
	var original: Dictionary = app.repository.data.duplicate(true)
	var draft: Dictionary = original.duplicate(true)
	draft.cards.entries[0].effects[0].value = 7
	results.checks["save"] = app.repository.save_draft(draft)
	results.checks["reload"] = app.repository.reload() and app.repository.data.cards.entries[0].effects[0].value == 7
	results.checks["restore"] = app.repository.save_draft(original)
	# Use a distinct save path, never the player's normal save.
	app.saves.path = "user://smoke/profile.json"
	app.new_game()
	results.checks["new_game_save"] = FileAccess.file_exists(app.saves.path)
	app.depart()
	app.node_id = "a"
	app.start_battle(["mossling"])
	app.battle.hand = ["strike", "strike", "strike", "guard", "heal"]
	app.use_card(0, 0)
	app.use_card(0, 0)
	app.use_card(0, 0)
	results.checks["battle_reward"] = app.screen == "reward" and app.profile.inventory.size() == 1
	app.return_hub()
	var inventory: Array = app.profile.inventory.duplicate(true)
	var restored: Dictionary = app.saves.read_profile(app.snapshot)
	results.checks["save_load"] = not restored.is_empty() and JSON.stringify(restored.inventory) == JSON.stringify(inventory)
	app.open_editor()
	await get_tree().process_frame
	app.editor.group = "generator"
	app.editor.refresh()
	var panel: GeneratorPanel = app.editor.generator_panel
	panel.amount = 10
	panel.filter_rarity = "rare"
	results.checks["generator"] = panel.generate_items(false) and panel.results.size() == 10 and panel.section == "results" and not str(panel.results[0].get("name", "")).is_empty()
	var loot_policy: Dictionary = app.repository.indexed("rules", app.editor.draft).loot
	loot_policy.rarities[2].count_weights = {"7": 100}
	results.checks["generator_settings_save"] = app.editor.save()
	var random := RandomNumberGenerator.new()
	random.seed = 222
	results.checks["generator_settings_reload"] = EquipmentGenerator.new(app.repository.data).generate(random, 1, "rare").item.affixes.size() == 7
	results.checks["generator_settings_restore"] = app.repository.save_draft(original)
	app.editor.reload_draft()
	app.start_test(app.editor.test_settings, false)
	app.return_editor()
	app.close_editor()
	results.checks["editor_roundtrip"] = app.screen == "hub" and not app.is_test
	DirAccess.make_dir_recursive_absolute("user://smoke")
	var file := FileAccess.open("user://smoke/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	var success: bool = true
	for value: bool in results.checks.values():
		success = success and value
	print(JSON.stringify(results))
	get_tree().quit(0 if success else 1)
