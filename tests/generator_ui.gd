extends SceneTree

var failures: int = 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption:
		return node
	for child: Node in node.get_children():
		var found := find_button(child, caption)
		if found != null:
			return found
	return null

func click(button: Button) -> void:
	var position := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await click(find_button(app, "装備品ジェネレーター"))
	await process_frame
	var panel: GeneratorPanel = app.editor.generator_panel
	await click(find_button(panel, "装備を生成"))
	await process_frame
	await process_frame
	check(panel.results.size() == 20 and panel.section == "results", "mouse click generates batch and opens results")
	check(app.editor.detail_scroll.scroll_vertical == 0, "generation scrolls to top")
	check(app.editor.detail_scroll.get_global_rect().encloses(panel.result_heading.get_global_rect()), "result count is visible without scrolling")
	var first_batch := JSON.stringify(panel.results)
	await click(find_button(panel, "同じ条件で再生成"))
	check(JSON.stringify(panel.results) == first_batch, "same seed preserves generated names and stats")
	await click(find_button(panel, "新シードで再生成"))
	check(JSON.stringify(panel.results) != first_batch, "new seed generates new batch")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/tests/generator-click.png")
	await click(find_button(panel, "条件を変更"))
	check(panel.section == "generate", "return to generation conditions")
	panel.filter_base = "sword"
	panel.filter_slot = "feet"
	panel.refresh()
	await process_frame
	await process_frame
	await click(find_button(panel, "装備を生成"))
	var error_visible: bool = false
	for child: Node in panel.get_children():
		if child is AcceptDialog and child.visible:
			error_visible = true
	check(error_visible, "invalid conditions show a visible error dialog")
	print("GENERATOR MOUSE UI: failures=", failures)
	app.queue_free()
	await create_timer(0.2).timeout  # let the audio server drop released playbacks
	await process_frame
	quit(0 if failures == 0 else 1)
