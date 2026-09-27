extends SceneTree

var app: Control

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/tests/" + name + ".png")

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func run() -> void:
	root.size = Vector2i(1280, 720)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.saves.path = "res://.godot/tests/visual-profile.json"
	await shot("title")
	app.new_game()
	app.profile.gold = 480
	await wait(0.3)
	await shot("hub")
	for background: String in ["hall", "tower"]:
		HubActions.set_background(app.profile, background)
		app.show_screen("hub")
		await wait(0.2)
		await shot("hub-" + background)
	HubActions.set_background(app.profile, "camp")
	for hub_page: String in ["status", "cards", "deck", "equipment", "shop"]:
		app.show_screen(hub_page)
		await wait(0.3)
		await shot("hub-" + hub_page)
	app.show_screen("debug_shop")
	await shot("debug-shop")
	app.show_screen("hub")
	app.depart()
	await shot("map")
	app.node_id = "a"
	app.start_battle(["thorn", "mossling"])
	app.battle.draw(10)
	app.show_screen("battle")
	await wait(2.2)
	await shot("battle")
	var view: BattleView = app.battle_view
	view.mouse = view.rest_center(3, view.cards.size())
	view.on_motion()
	await wait(0.4)
	await shot("battle-hover")
	var attack: int = -1
	for i: int in view.cards.size():
		if view.needs_target(i) and view.engine.can_play(i, 0).is_empty():
			attack = i
			break
	view.pick(attack)
	view.mouse = view.foes[0].position + view.foes[0].size / 2
	view.on_motion()
	await wait(0.4)
	await shot("battle-aim")
	view.cancel_held()
	view.play_card(attack, 0)
	await wait(0.3)
	await shot("battle-hit")
	await wait(1.5)
	view.end_turn()
	await wait(1.4)
	await shot("battle-enemy-turn")
	await wait(3.0)
	app.node_id = "boss"
	app.start_battle(["warden"])
	await wait(2.2)
	await shot("battle-boss")
	app.open_editor()
	await shot("editor")
	for group: String in DefinitionRepository.GROUPS:
		app.editor.group = group
		app.editor.selected_id = app.repository.records(group)[0].id
		app.editor.refresh()
		await process_frame
	app.editor.group = "test"
	app.editor.refresh()
	await shot("test-settings")
	app.editor.group = "generator"
	app.editor.refresh()
	var panel: GeneratorPanel = app.editor.generator_panel
	panel.level = 20
	panel.amount = 3
	panel.filter_rarity = "rare"
	await shot("generator")
	panel.generate_items(false)
	await shot("generator-results")
	panel.section = "rarity"
	panel.refresh()
	app.editor.detail_scroll.scroll_vertical = 0
	await shot("generator-settings")
	app.queue_free()
	await create_timer(0.2).timeout  # let the audio server drop released playbacks
	await process_frame
	print("VISUAL SMOKE COMPLETE")
	quit()
