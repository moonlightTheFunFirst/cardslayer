extends SceneTree

var app: Control

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/tests/" + name + ".png")

func run() -> void:
	root.size = Vector2i(1280, 720)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.saves.path = "res://.godot/tests/visual-profile.json"
	await shot("title")
	app.new_game()
	await shot("hub")
	app.depart()
	await shot("map")
	app.node_id = "a"
	app.start_battle(["thorn", "mossling"])
	app.battle.draw(10)
	app.show_screen("battle")
	await shot("battle")
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
	app.queue_free()
	await process_frame
	print("VISUAL SMOKE COMPLETE")
	quit()
