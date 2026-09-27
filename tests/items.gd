extends SceneTree

## Consumable items (spec ch.20): definitions, scripts, battle / map use,
## save v4, loadout, shop, editor simulation and the real / debug screens.

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

func run() -> void:
	root.size = Vector2i(1280, 720)
	var repo := DefinitionRepository.new()
	check(repo.reload(), "definitions with consumables load")
	var defs: Dictionary = repo.data
	check_definitions(defs)
	check_battle(defs)
	check_profile(defs)
	await check_screens()
	print("ITEM CHECKS: %d; FAILURES: %d" % [checks, failures])
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)

func item(defs: Dictionary, id: String) -> Dictionary:
	return DefinitionRepository.new().indexed("consumables", defs)[id].duplicate(true)

func check_definitions(defs: Dictionary) -> void:
	for entry: Dictionary in DefinitionRepository.new().records("consumables", defs):
		check(ItemRunner.validate(entry).is_empty(), "sample item is valid: " + entry.id)
	var bad := item(defs, "herb")
	bad.script = "func use(ctx):\n\tOS.execute(\"cmd\", [])\n"
	check(not ItemRunner.validate(bad).is_empty(), "script using OS is rejected")
	bad.script = "func use(ctx)\n\tctx.heal(1)\n"
	check(not ItemRunner.validate(bad).is_empty(), "script syntax error is rejected")
	bad.script = "func can_use(ctx):\n\treturn \"\"\n"
	check(not ItemRunner.validate(bad).is_empty(), "script without use(ctx) is rejected")
	bad = item(defs, "power_pill")
	bad.scene = "anywhere"
	check(not ItemRunner.validate(bad).is_empty(), "battle-only effect outside battle is rejected")
	bad = item(defs, "thunder_vial")
	bad.target = "self"
	check(not ItemRunner.validate(bad).is_empty(), "single-target damage needs an enemy target")
	var copy := defs.duplicate(true)
	for entry: Dictionary in copy.rules.entries:
		if entry.id == "items":
			entry.starter = ["missing"]
	check(not DefinitionRepository.new().validate(copy).is_empty(), "unknown starter item is rejected")

func battle_with(defs: Dictionary, carried: Array, enemies: Array = ["mossling"]) -> BattleEngine:
	var engine := BattleEngine.new()
	var stats := {"max_hp": 60, "max_mp": 10, "strength": 5, "wisdom": 5, "agility": 5, "luck": 5}
	engine.setup(defs, stats, 60, Progression.new_player(defs).deck, enemies, 4242, carried)
	return engine

func check_battle(defs: Dictionary) -> void:
	var engine := battle_with(defs, ["herb", "panacea", "power_pill", "defense_pill", "thunder_vial", "fate_dice"])
	check(engine.item_reason(0) == "HPが満タンです" and not engine.use_item(0), "herb is greyed out at full HP")
	engine.player.hp = 30
	check(engine.use_item(0) and engine.player.hp >= 37 and engine.player.hp <= 50 and engine.items[0] == "" and engine.used_items == ["herb"], "herb heals 7-20 and is used up")
	check(not engine.use_item(0), "used slot cannot be used again")
	check(engine.item_reason(1) != "", "panacea needs a bad status")
	engine.player.poison = 4
	check(engine.use_item(1) and engine.player.poison == 0, "panacea cures poison")
	var before: int = int(engine.effect_value(engine.cards.strike.effects[0], engine.player).value)
	check(engine.use_item(2) and engine.player.buffs.strength == 3 and int(engine.effect_value(engine.cards.strike.effects[0], engine.player).value) > before, "power pill raises strength for card damage")
	check(engine.use_item(3) and engine.player.reduction == 3, "defense pill sets damage reduction")
	var hp_before: int = engine.player.hp
	var incoming: int = int(engine.effect_value(engine.enemies[0].definition.actions[0].effects[0], engine.enemies[0]).value)
	engine.end_turn()
	check(hp_before - int(engine.player.hp) == maxi(0, incoming - 3), "damage taken is reduced by 3")
	check(engine.item_reason(4, -1) == "対象の敵を選択してください" and engine.item_reason(4, -1, false).is_empty(), "thunder vial waits for an enemy target")
	var enemy_hp: int = engine.enemies[0].hp
	check(engine.use_item(4, 0) and enemy_hp - int(engine.enemies[0].hp) >= 9 and enemy_hp - int(engine.enemies[0].hp) <= 18, "thunder vial damages the chosen enemy")
	var log_size := engine.log.size()
	check(engine.use_item(5), "scripted fate dice runs")
	check(engine.log.slice(log_size).any(func(line: String) -> bool: return line.begins_with("出目")), "script message is logged")
	check(engine.events.any(func(ev: Dictionary) -> bool: return ev.kind == "item"), "item use is recorded for the battle view")
	var again := battle_with(defs, ["fate_dice"])
	var twin := battle_with(defs, ["fate_dice"])
	again.use_item(0)
	twin.use_item(0)
	check(JSON.stringify(again.player) == JSON.stringify(twin.player) and JSON.stringify(again.enemies) == JSON.stringify(twin.enemies), "item rolls follow the battle seed")
	var shuffled := battle_with(defs, [])
	check(shuffled.hand == battle_with(defs, ["herb"]).hand, "carrying items never changes the deck shuffle")
	var custom := item(defs, "herb")
	custom.script = "func can_use(ctx):\n\tif ctx.bad_statuses().is_empty():\n\t\treturn \"毒がない\"\n\treturn \"\"\n\nfunc use(ctx):\n\tctx.cure_random()\n\tctx.damage_all(3)\n"
	custom.scene = "battle"
	check(ItemRunner.validate(custom).is_empty(), "custom script validates")
	var scripted := battle_with(defs, ["herb"], ["mossling", "thorn"])
	scripted.consumables.herb = custom
	check(scripted.item_reason(0) == "毒がない", "script can_use reason is shown")
	scripted.player.poison = 2
	var hp_total: int = scripted.enemies[0].hp + scripted.enemies[1].hp
	check(scripted.use_item(0) and scripted.player.poison == 0 and hp_total - int(scripted.enemies[0].hp) - int(scripted.enemies[1].hp) == 6, "custom script cures and hits all enemies")

func check_profile(defs: Dictionary) -> void:
	var profile := Progression.new_player(defs)
	check(HubActions.owned(profile, "herb") == 2 and profile.loadout == ["herb", "herb"], "new hero starts with two carried herbs")
	check(not HubActions.load_item(profile, defs, "herb") and HubActions.load_reason(profile, defs, "herb") == "所持数が足りません", "cannot carry more than owned")
	HubActions.gain_item(profile, "power_pill", 2)
	check(HubActions.load_item(profile, defs, "power_pill") and not HubActions.load_item(profile, defs, "power_pill"), "carry limit of 3 is enforced")
	check(HubActions.unload_item(profile, 0) and profile.loadout == ["herb", "power_pill"], "unloading frees a slot")
	profile.hp = 20
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	check(HubActions.field_use_reason(profile, defs, "power_pill", rng) == "戦闘中のみ使用できます", "battle-only item is greyed out on the map")
	var result := HubActions.use_field_item(profile, defs, "herb", rng)
	check(result.ok and profile.hp >= 27 and HubActions.owned(profile, "herb") == 1 and profile.loadout == ["power_pill"], "herb heals on the map and is consumed")
	check(SaveRepository.new().validate(profile, defs).is_empty(), "profile with consumables is a valid v4 save")
	var saver := SaveRepository.new()
	saver.path = "res://.godot/tests/items-profile.json"
	check(saver.save(profile, defs), "v4 save writes")
	var loaded := saver.read_profile(defs)
	check(JSON.stringify(loaded.consumables) == JSON.stringify(profile.consumables) and loaded.loadout == profile.loadout, "items survive save/load")
	var broken := profile.duplicate(true)
	broken.loadout = ["herb", "herb"]
	check(not saver.validate(broken, defs).is_empty(), "loadout beyond owned count is rejected")
	var v3 := profile.duplicate(true)
	v3.save_version = 3
	v3.erase("consumables")
	v3.erase("loadout")
	var migrated := saver.migrate(v3, defs)
	check(migrated.ok and migrated.profile.save_version == SaveRepository.VERSION and migrated.profile.consumables.is_empty() and saver.validate(migrated.profile, defs).is_empty(), "version 3 save migrates to v4")
	var shop_profile := Progression.new_player(defs)
	shop_profile.gold = 1000
	var shop_rng := RandomNumberGenerator.new()
	shop_rng.seed = 11
	Shop.restock(shop_profile, defs, shop_rng)
	var index := -1
	for i: int in Shop.stock(shop_profile).size():
		if Shop.stock(shop_profile)[i].kind == "consumable":
			index = i
			break
	var good: String = Shop.stock(shop_profile)[index].id if index >= 0 else ""
	var owned_before := HubActions.owned(shop_profile, good)
	check(index >= 0 and Shop.buy(shop_profile, index) and HubActions.owned(shop_profile, good) == owned_before + 1, "shop sells consumables")
	var limited := defs.duplicate(true)
	for entry: Dictionary in limited.rules.entries:
		if entry.id == "items":
			entry.carry_limit = 1
	check(HubActions.carried(Progression.new_player(defs), limited).size() == 1, "lowering the carry limit takes fewer items")

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.is_visible_in_tree() and not node.disabled and (node.text == caption or node.text.begins_with(caption)):
		return node
	for child: Node in node.get_children():
		var found := find_button(child, caption)
		if found != null:
			return found
	return null

func press(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func click(button: Control) -> void:
	if button == null:
		check(false, "button exists")
		return
	await process_frame
	await press(button.get_global_rect().get_center())
	await process_frame

func idle() -> void:
	var waited: float = 0.0
	while app.battle_view != null and (app.battle_view.playing or app.battle_view.finishing) and waited < 12.0:
		await create_timer(0.05).timeout
		waited += 0.05

func check_screens() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.saves.path = "res://.godot/tests/items-ui-profile.json"
	app.new_game()
	app.depart()
	app.node_id = "a"
	app.start_battle(["mossling"])
	await idle()
	var view: BattleView = app.battle_view
	check(view.item_buttons.size() == 2 and view.item_buttons[0].disabled, "belt shows the carried herbs, greyed out at full HP")
	app.battle.player.hp = 25
	view.sync()
	await process_frame
	check(not view.item_buttons[0].disabled, "herb becomes usable after taking damage")
	await click(view.item_buttons[0])
	await idle()
	check(app.battle.player.hp > 25 and HubActions.owned(app.profile, "herb") == 1 and app.profile.loadout == ["herb"], "clicking the belt uses the herb and consumes it")

	app.return_hub()
	HubActions.gain_item(app.profile, "thunder_vial")
	app.profile.loadout = ["thunder_vial"]
	app.depart()
	app.node_id = "a"
	app.start_battle(["mossling"])
	await idle()
	view = app.battle_view
	var enemy_hp: int = app.battle.enemies[0].hp
	await click(view.item_buttons[0])
	check(view.held_item == 0, "enemy-targeted item waits for a target")
	var foe: BattleActor = view.foes[0]
	await press(foe.position + foe.size / 2)
	await idle()
	check(int(app.battle.enemies[0].hp) < enemy_hp and HubActions.owned(app.profile, "thunder_vial") == 0, "clicking the enemy throws the vial")

	app.return_hub()
	app.profile.loadout = ["herb"]
	app.profile.hp = 10
	app.depart()
	await process_frame
	await click(find_button(app, "薬草 を使う"))
	check(app.profile.hp > 10 and HubActions.owned(app.profile, "herb") == 0, "herb can be used from the map")

	app.return_hub()
	HubActions.gain_item(app.profile, "power_pill", 2)
	app.show_screen("hub")
	await click(find_button(app, "持ち物"))
	check(app.screen == "items" and app.hub_view.page == "items", "menu opens the item page")
	await click(find_button(app, "持ち込む"))
	check(app.profile.loadout == ["power_pill"], "real screen loads an item")
	await click(find_button(app, "外す"))
	check(app.profile.loadout.is_empty(), "real screen unloads an item")
	var base_profile: Dictionary = app.profile.duplicate(true)
	await click(find_button(app, "持ち込む"))
	var via_real := JSON.stringify(app.profile)
	app.profile = base_profile.duplicate(true)
	app.show_screen("debug_items")
	await process_frame
	await click(find_button(app, "持ち込む"))
	check(JSON.stringify(app.profile) == via_real, "debug and real item pages load items identically")

	app.open_editor()
	await process_frame
	app.editor.group = "consumables"
	app.editor.selected_id = "herb"
	app.editor.refresh()
	await process_frame
	check(app.editor.simulate_consumable(app.editor.current_record()).contains("使用後"), "editor simulation runs the item")
	var script_edit: CodeEdit = null
	for node: Node in app.editor.detail.find_children("*", "CodeEdit", true, false):
		script_edit = node
	check(script_edit != null, "editor shows a code editor for the item script")
	app.close_editor()
	await process_frame
	app.queue_free()
	await process_frame
