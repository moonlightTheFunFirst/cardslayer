extends SceneTree

## Area map: real screen, debug map, departure area and first-clear toggles.

var failures: int = 0
var checks: int = 0
var app: Control

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.is_visible_in_tree() and not node.disabled and (node.text == caption or node.text.begins_with(caption)):
		return node
	for child: Node in node.get_children():
		var found := find_button(child, caption)
		if found != null:
			return found
	return null

func click(control: Control) -> void:
	if control == null:
		check(false, "control exists")
		return
	await process_frame
	var position := control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame

func win_battle() -> void:
	for enemy: Dictionary in app.battle.enemies:
		enemy.hp = 0
	app.battle.check_outcome()
	app.after_action()
	await process_frame

## Project data plus a second area so departure selection can be exercised.
func prepare_data() -> String:
	var root_path := "res://.godot/tests/map_data"
	DirAccess.make_dir_recursive_absolute(root_path)
	for group: String in DefinitionRepository.GROUPS:
		DirAccess.copy_absolute("res://data/" + group + ".json", root_path + "/" + group + ".json")
	var areas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root_path + "/areas.json"))
	var second: Dictionary = areas.entries[0].duplicate(true)
	second.id = "forest_deep"
	second.name = "朽ち森の深部"
	areas.entries.append(second)
	var file := FileAccess.open(root_path + "/areas.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(areas, "\t"))
	file.close()
	return root_path

func run() -> void:
	root.size = Vector2i(1280, 720)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.repository.root = prepare_data()
	check(app.repository.reload(), "test data with two areas loads")
	app.saves.path = "res://.godot/tests/map-profile.json"
	app.new_game()
	await process_frame

	await click(find_button(app, "出撃"))
	var view: MapView = app.map_view
	check(app.screen == "map" and view != null and app.area_id == "forest", "normal play departs to the first area on the real map")
	check(not view.node_buttons.a.disabled and not view.node_buttons.b.disabled and view.node_buttons.c.disabled and view.node_buttons.boss.disabled, "only nodes connected to the start are selectable")
	check(view.positions.start.x < view.positions.a.x and view.positions.a.x < view.positions.c.x and view.positions.c.x < view.positions.boss.x, "nodes are laid out left to right by depth")
	await click(view.node_buttons.a)
	check(app.screen == "battle" and app.node_id == "a" and app.battle.enemies[0].id == "mossling", "clicking a node starts its battle")
	await win_battle()
	await click(find_button(app, "次へ"))
	view = app.map_view
	check(app.screen == "map" and "a" in view.passed and not view.node_buttons.c.disabled and view.node_buttons.b.disabled, "after winning, the next node opens and the other branch closes")

	await click(find_button(app, "デバッグメニュー"))
	check(app.screen == "debug_map", "real map links to the debug map")
	await click(find_button(app, "実画面で表示"))
	check(app.screen == "map" and app.map_view != null, "debug map links back to the real map")
	await click(find_button(app, "本拠地へ帰還"))
	var dialog: ConfirmationDialog = app.get_child(app.get_child_count() - 1)
	dialog.confirmed.emit()
	await process_frame
	check(app.screen == "hub", "map returns home")

	app.show_screen("debug_hub")
	await process_frame
	await click(find_button(app, "朽ち森: OFF"))
	check("forest" in app.profile.cleared and "forest" in JSON.parse_string(FileAccess.get_file_as_string(app.saves.path)).cleared, "debug menu marks an area cleared and saves")
	await click(find_button(app, "朽ち森: ON"))
	check("forest" not in app.profile.cleared, "debug menu clears the flag again")
	await click(find_button(app, "朽ち森の深部"))
	check(app.departure_area == "forest_deep", "debug menu picks the departure area")
	await click(find_button(app, "出撃"))
	check(app.screen == "map" and app.area_id == "forest_deep", "departure goes to the chosen area")
	app.return_hub()

	app.open_editor()
	await process_frame
	app.editor.group = "test"
	app.editor.refresh()
	await process_frame
	var boxes: Array = app.editor.detail.find_children("*", "CheckBox", true, false)
	check(boxes.any(func(box: CheckBox) -> bool: return box.text.begins_with("朽ち森の深部")), "test settings show a cleared checkbox per area")
	app.editor.test_settings.area = "forest_deep"
	app.editor.test_settings.cleared = ["forest_deep"]
	app.start_test(app.editor.test_settings, true)
	await process_frame
	check(app.is_test and app.screen == "map" and app.area_id == "forest_deep" and app.profile.cleared == ["forest_deep"], "area test uses the chosen area and cleared flags")
	check(app.map_view != null and app.map_view.info.test, "area test opens the real map in test mode")
	app.return_editor()
	app.close_editor()
	await process_frame
	print("MAP CHECKS: %d; FAILURES: %d" % [checks, failures])
	app.queue_free()
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)
