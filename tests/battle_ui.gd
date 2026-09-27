extends SceneTree

## Drives the animated battle screen with real mouse / keyboard events.

var failures: int = 0
var app: Control

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _initialize() -> void:
	call_deferred("run")

func settle(done: Callable, limit: float = 12.0) -> void:
	var waited: float = 0.0
	while not done.call() and waited < limit:
		await create_timer(0.05).timeout
		waited += 0.05

func idle() -> void:
	await settle(func() -> bool: return app.battle_view == null or (not app.battle_view.playing and not app.battle_view.finishing))

func move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)
	await process_frame

func button(position: Vector2, pressed: bool, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.position = position
	event.global_position = position
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func drag(from: Vector2, to: Vector2) -> void:
	await move(from)
	await button(from, true)
	for step: int in 6:
		await move(from.lerp(to, (step + 1) / 6.0))
	await button(to, false)

func card_point(index: int) -> Vector2:
	var view: BattleView = app.battle_view
	return view.rest_center(index, view.cards.size()) + Vector2(0, 40)

func enemy_point(index: int) -> Vector2:
	var foe: BattleActor = app.battle_view.foes[index]
	return foe.position + foe.size / 2

func set_hand(ids: Array) -> void:
	app.battle.hand = ids
	app.battle_view.sync()
	await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.saves.path = "res://.godot/tests/battle-ui-profile.json"
	app.new_game()
	app.depart()
	app.node_id = "a"
	app.start_battle(["mossling"])
	check(app.battle_view != null and app.battle_view.engine == app.battle, "battle screen uses the animated view")
	await idle()
	check(app.battle_view.cards.size() == app.battle.hand.size(), "initial hand is dealt into view")
	await set_hand(["strike", "guard", "strike", "heal", "insight"])
	var mossling: Dictionary = app.battle.enemies[0]

	await drag(card_point(0), enemy_point(0))
	await idle()
	check(mossling.hp == 12 and app.battle.ap == 2, "dragging strike onto enemy deals 8 damage and spends AP")
	check(app.battle_view.cards.size() == 4 and app.battle.hand[0] == "guard", "played card leaves the hand view")

	await drag(card_point(1), Vector2(900, 690))
	await idle()
	check(app.battle.hand.size() == 4 and mossling.hp == 12, "dropping an attack outside an enemy cancels it")

	await move(card_point(0))
	await button(card_point(0), true)
	await button(card_point(0), false)
	check(app.battle_view.held == 0, "clicking a card selects it")
	await button(Vector2(640, 300), true, MOUSE_BUTTON_RIGHT)
	check(app.battle_view.held == -1 and app.battle.hand.size() == 4, "right click cancels the selection")

	await move(card_point(0))
	await button(card_point(0), true)
	await button(card_point(0), false)
	await move(Vector2(640, 300))
	await button(Vector2(640, 300), true)
	await button(Vector2(640, 300), false)
	await idle()
	check(app.battle.player.block == 8 and app.battle.ap == 1, "click-select then click above the hand plays a self card")

	await key(KEY_E)
	await idle()
	check(app.battle.turn == 2 and app.battle.player.block == 0 and app.battle.ap == 3, "E key ends the turn and enemy phase resolves")
	check(app.screen == "battle" and app.battle_view.cards.size() == app.battle.hand.size(), "hand view matches engine after enemy turn")

	var before := JSON.stringify([app.battle.player, app.battle.enemies, app.battle.hand])
	await key(KEY_F1)
	check(app.editor != null and app.battle_view == null, "F1 opens the editor from battle")
	app.close_editor()
	await process_frame
	check(app.battle_view != null and JSON.stringify([app.battle.player, app.battle.enemies, app.battle.hand]) == before, "closing the editor restores the same battle")
	await idle()

	await set_hand(["strike", "guard"])
	mossling.hp = 3
	mossling.block = 0
	await drag(card_point(0), enemy_point(0))
	await settle(func() -> bool: return app.screen == "reward")
	check(app.screen == "reward" and app.battle_view == null, "victory animation hands over to the reward screen")

	app.open_editor()
	await process_frame
	app.start_test(app.editor.test_settings, false)
	check(app.is_test and app.battle_view != null and app.battle_view.info.test, "editor test battle opens the animated view")
	await key(KEY_F1)
	check(not app.is_test and app.editor.visible and app.battle_view == null, "F1 in a test battle returns to the editor")
	app.close_editor()
	await process_frame

	print("BATTLE UI: failures=", failures)
	app.queue_free()
	await create_timer(0.2).timeout  # let the audio server drop released playbacks
	await process_frame
	quit(0 if failures == 0 else 1)
