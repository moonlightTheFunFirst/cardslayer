extends SceneTree

## Home base (spec ch.21): shop, save v3, shared actions, and real / debug screens.

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
	if node is Button and node.is_visible_in_tree() and (node.text == caption or node.text.begins_with(caption)):
		return node
	for child: Node in node.get_children():
		var found := find_button(child, caption)
		if found != null:
			return found
	return null

func click(button: Button) -> void:
	if button == null:
		check(false, "button exists")
		return
	await process_frame
	var position := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame

func click_text(caption: String) -> void:
	await click(find_button(root, caption))

func saved_profile() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(app.saves.path))

func run() -> void:
	root.size = Vector2i(1280, 720)
	var repo := DefinitionRepository.new()
	check(repo.reload(), "definitions with rules/shop load")
	var defs: Dictionary = repo.data
	await check_logic(defs)
	await check_screens()
	print("HUB CHECKS: %d; FAILURES: %d" % [checks, failures])
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)

func check_logic(defs: Dictionary) -> void:
	var config := Shop.settings(defs)
	var profile := Progression.new_player(defs)
	check(profile.save_version == SaveRepository.VERSION and profile.hub_background == "camp", "new hero starts on save v3 at the campsite")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	Shop.restock(profile, defs, rng)
	var first := JSON.stringify(profile.shop)
	rng.seed = 77
	Shop.restock(profile, defs, rng)
	check(JSON.stringify(profile.shop) == first, "same seed gives the same shop stock")
	check(Shop.stock(profile).size() == int(config.equipment_count), "stock has the configured number of goods")
	var offer: Dictionary = Shop.stock(profile)[0]
	check(offer.price == Shop.price(offer.item, config) and offer.price > 0, "price follows level and rarity")
	check(SaveRepository.new().validate(profile, defs).is_empty(), "profile with shop stock is a valid save")
	profile.gold = offer.price - 1
	check(Shop.buy_reason(profile, 0) == "ゴールド不足" and not Shop.buy(profile, 0), "cannot buy without enough gold")
	profile.gold = offer.price + 5
	check(Shop.buy(profile, 0) and profile.gold == 5 and profile.inventory.size() == 1 and Shop.stock(profile)[0].sold, "buying pays gold and adds the item")
	check(Shop.buy_reason(profile, 0) == "売り切れ" and not Shop.buy(profile, 0), "sold goods cannot be bought twice")
	check(HubActions.equip(profile, profile.inventory[0], defs) or not HubActions.equip_reason(profile, profile.inventory[0], defs).is_empty(), "bought item can be equipped when requirements allow")

	check(not HubActions.remove_card(profile, "strike") and profile.deck.size() == 20, "deck cannot drop below 20")
	check(HubActions.add_card(profile, "fireball") and HubActions.remove_card(profile, "strike") and profile.deck.size() == 20, "add then remove swaps a card")
	for i: int in 10:
		HubActions.add_card(profile, "heal")
	check(profile.deck.size() == 29 and profile.deck.count("heal") == 10 and not HubActions.add_card_reason(profile, "heal").is_empty(), "same card is capped at 10")
	HubActions.add_card(profile, "guard")
	check(not HubActions.add_card_reason(profile, "focus").is_empty(), "deck is capped at 30")
	check(HubActions.next_background(profile) == "hall" and HubActions.next_background(profile) == "tower" and HubActions.next_background(profile) == "camp", "background cycles through three sets")
	check(not HubActions.set_background(profile, "missing"), "unknown background is rejected")

	var saver := SaveRepository.new()
	saver.path = "res://.godot/tests/hub-logic-profile.json"
	profile.hub_background = "tower"
	check(saver.save(profile, defs), "v3 save writes")
	var loaded := saver.read_profile(defs)
	check(loaded.hub_background == "tower" and JSON.stringify(loaded.shop) == JSON.stringify(profile.shop), "background and shop stock survive save/load")
	var v2 := profile.duplicate(true)
	v2.save_version = 2
	v2.erase("hub_background")
	v2.erase("shop")
	var migrated := saver.migrate(v2, defs)
	check(migrated.ok and migrated.profile.save_version == SaveRepository.VERSION and migrated.profile.hub_background == "camp" and Shop.stock(migrated.profile).is_empty() and saver.validate(migrated.profile, defs).is_empty(), "version 2 save migrates to v3")
	var broken := profile.duplicate(true)
	broken.shop.stock[1].price = -3
	check(not saver.validate(broken, defs).is_empty(), "invalid shop price is rejected")
	var bad_rules := {"equipment_count": 99, "rarity_weights": {"common": 0, "magic": 0, "rare": 0, "legendary": 0, "unique": 0}}
	check(Shop.validate(bad_rules).size() >= 2, "shop settings are validated")

func check_screens() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.saves.path = "res://.godot/tests/hub-ui-profile.json"
	app.new_game()
	await process_frame
	check(app.screen == "hub" and app.hub_view != null and app.hub_view.page == "hub", "new game opens the real home base")
	check(not Shop.stock(app.profile).is_empty(), "new game stocks the shop")
	var background: String = app.profile.hub_background
	await click_text("背景:")
	check(app.profile.hub_background != background and saved_profile().hub_background == app.profile.hub_background, "background button switches and saves")

	await click_text("ショップ")
	check(app.screen == "shop" and app.hub_view.page == "shop", "menu opens the shop")
	app.profile.gold = 100000
	app.hub_view.refresh()
	await process_frame
	var gold_before: int = app.profile.gold
	var price: int = Shop.stock(app.profile)[0].price
	await click_text("購入")
	check(app.profile.gold == gold_before - price and app.profile.inventory.size() == 1 and Shop.stock(app.profile)[0].sold, "clicking buy purchases the first offer")
	check(int(saved_profile().gold) == app.profile.gold, "purchase is saved")
	await click_text("◀ 本拠地へ帰還")
	check(app.screen == "hub", "shop returns to the home base")

	await click_text("デッキ編集")
	check(app.screen == "deck", "menu opens deck editing")
	await click_text("＋")
	check(app.profile.deck.size() == 21, "plus button adds a card")
	await click_text("−")
	check(app.profile.deck.size() == 20, "minus button removes a card")
	await click_text("◀ 本拠地へ戻る")

	for entry: Array in [["装備", "equipment"], ["カード一覧", "cards"], ["主人公の状態", "status"]]:
		await click_text(entry[0])
		check(app.screen == entry[1] and app.hub_view.page == entry[1], "menu opens " + entry[1])
		await click_text("◀ 本拠地へ戻る")
	await click_text("装備")
	await click_text("装備する")
	check(app.profile.equipped.size() == 1, "equip button equips the bought item")
	await click_text("◀ 本拠地へ戻る")

	await click_text("デバッグメニュー")
	check(app.screen == "debug_hub" and app.hub_view == null, "debug menu opens from the real hub")
	await click_text("ショップ")
	check(app.screen == "debug_shop", "debug menu reaches the shop")
	await click_text("実画面で表示")
	check(app.screen == "shop" and app.hub_view != null, "debug page links back to the real screen")

	# Both UIs must perform the identical purchase.
	var base_profile: Dictionary = app.profile.duplicate(true)
	var index: int = -1
	for i: int in Shop.stock(base_profile).size():
		if not Shop.stock(base_profile)[i].sold:
			index = i
			break
	app.profile = base_profile.duplicate(true)
	app.show_screen("debug_shop")
	await process_frame
	await click_text("購入")
	var via_debug := JSON.stringify(app.profile)
	app.profile = base_profile.duplicate(true)
	app.clear_hub_view()
	app.show_screen("shop")
	await process_frame
	await click_text("購入")
	check(index >= 0 and JSON.stringify(app.profile) == via_debug, "debug and real shop buy produce the same result")

	app.show_screen("hub")
	var stock_before := JSON.stringify(app.profile.shop)
	await click_text("出撃")
	check(app.screen == "map", "depart opens the map")
	await click_text("本拠地へ帰還")
	var dialog: ConfirmationDialog = app.get_child(app.get_child_count() - 1)
	dialog.confirmed.emit()
	await process_frame
	check(app.screen == "hub" and JSON.stringify(app.profile.shop) != stock_before, "returning from the map restocks the shop")

	app.open_editor()
	await process_frame
	check(app.hub_view == null and app.editor.visible, "editor replaces the home base view")
	app.close_editor()
	await process_frame
	check(app.screen == "hub" and app.hub_view != null, "closing the editor restores the home base")
	app.queue_free()
	await process_frame
