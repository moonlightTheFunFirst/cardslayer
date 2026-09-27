extends Control

var repository := DefinitionRepository.new()
var saves := SaveRepository.new()
var snapshot: Dictionary = {}
var profile: Dictionary = {}
var battle: BattleEngine
var screen: String = "title"
var area_id: String = ""
var node_id: String = ""
var passed: Array[String] = []
var reward_claim: Dictionary = {}
var reward_result: Dictionary = {}
var loot_rng := RandomNumberGenerator.new()
var battle_rng := RandomNumberGenerator.new()
var shop_rng := RandomNumberGenerator.new()
var item_rng := RandomNumberGenerator.new()
var page: VBoxContainer
var battle_view: BattleView
var hub_view: HubView
var sound := Sound.new()
var editor: DefinitionEditor
var is_test: bool = false
var paused: Dictionary = {}
var test_config: Dictionary = {}
var test_area: bool = false
var notice: String = ""

func _ready() -> void:
	get_tree().auto_accept_quit = false
	# Let clicks on empty space fall through to the battle view's unhandled input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sound)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic", "Meiryo", "sans-serif"])
	var app_theme := Theme.new()
	app_theme.default_font = font
	app_theme.default_font_size = 18
	theme = app_theme
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)
	loot_rng.randomize()
	battle_rng.randomize()
	shop_rng.randomize()
	item_rng.randomize()
	var smoke_requested: bool = "--smoke" in OS.get_cmdline_user_args() and ProjectSettings.get_setting("cardslayer/development_enabled", true)
	if not repository.initialize("user://smoke/data_v2" if smoke_requested else ""):
		label("定義データを読み込めません。元ファイルは保持しています。")
		if repository.root != "res://data":
			button("新しい同梱定義を導入", func() -> void:
				confirm("現在の編集データ一式をバックアップした上で、新しい同梱定義に置き換えます。通常セーブは保持します。続行しますか？", func() -> void:
					if repository.install_bundled():
						snapshot = repository.data.duplicate(true)
						notice = "定義を更新しました。旧データの退避先: " + repository.last_backup_path
						show_screen("title")
					else:
						label("\n".join(repository.errors))))
		var error_list := scroll_column()
		label("\n".join(repository.errors), error_list)
		return
	snapshot = repository.data.duplicate(true)
	show_screen("title")
	if smoke_requested:
		var smoke := DevelopmentSmoke.new()
		add_child(smoke)
		smoke.call_deferred("run", self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(editor) and editor.visible:
			editor.guard_change(confirm_quit)
		else:
			confirm_quit()

func confirm_quit() -> void:
	confirm("終了しますか？戦闘途中とマップ位置は再開できません。次回は回復済みの拠点からです。", func() -> void: get_tree().quit())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		editor_shortcut()
		get_viewport().set_input_as_handled()

## F1 / battle-screen button: jump straight to the editor. From a test play
## this returns to the edited item; from normal play it pauses the session.
func editor_shortcut() -> void:
	if not ProjectSettings.get_setting("cardslayer/development_enabled", true):
		return
	if is_test:
		return_editor()
	elif not is_instance_valid(editor):
		open_editor()

func label(value: String, parent: Node = null, size: int = 18) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", size)
	(parent if parent != null else page).add_child(result)
	return result

func button(value: String, action: Callable, parent: Node = null, disabled: bool = false) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 36
	result.disabled = disabled
	result.pressed.connect(func() -> void:
		if result.is_inside_tree() and not result.disabled:
			action.call())
	(parent if parent != null else page).add_child(result)
	return result

func row(parent: Node = null) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation", 10)
	(parent if parent != null else page).add_child(result)
	return result

func scroll_column() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	return column

func show_screen(next: String) -> void:
	screen = next
	for child: Node in page.get_children():
		page.remove_child(child)
		child.queue_free()
	if next != "battle":
		clear_battle_view()
	if next not in HubView.PAGES:
		clear_hub_view()
	# Battle and home-base views cover the whole window; form pages live in the margin.
	(page.get_parent() as Control).visible = next != "battle" and next not in HubView.PAGES
	update_music()
	if not notice.is_empty():
		label(notice)
	if is_test:
		var bar := row()
		label("● テストプレイ / seed %s" % test_config.seed, bar)
		button("編集へ戻る", return_editor, bar)
		button("同じ条件で再試行", func() -> void: start_test(test_config, test_area), bar)
		button("新しいシードで再試行", func() -> void:
			test_config.seed = randi()
			start_test(test_config, test_area), bar)
	if next in HubView.PAGES:
		hub_screen(next)
		return
	match screen:
		"title": title_screen()
		"debug_hub": debug_hub_screen()
		"debug_status": debug_status_screen()
		"debug_cards": debug_cards_screen()
		"debug_deck": debug_deck_screen()
		"debug_equipment": debug_equipment_screen()
		"debug_shop": debug_shop_screen()
		"debug_items": debug_items_screen()
		"map": map_screen()
		"battle": battle_screen()
		"reward": reward_screen()

func title_screen() -> void:
	label("CARDSLAYER", page, 48)
	label("朽ち森の探索者 — カード戦闘と装備収集")
	button("ゲーム開始", func() -> void:
		if FileAccess.file_exists(saves.path):
			confirm("既存セーブを置き換えて新規開始しますか？", new_game)
		else:
			new_game())
	button("続きから", func() -> void:
		profile = saves.read_profile(repository.data)
		if profile.is_empty():
			notice = saves.error
			show_screen("title")
		else:
			snapshot = repository.data.duplicate(true)
			if Shop.stock(profile).is_empty():
				# Saves migrated from version 2 have no stock yet.
				Shop.restock(profile, snapshot, shop_rng)
				persist()
			show_screen("hub"), page, not FileAccess.file_exists(saves.path))
	if dev_enabled():
		button("総合エディタ", open_editor)
		button("装備品ジェネレーター", func() -> void:
			open_editor()
			editor.group = "generator"
			editor.refresh())
	button("終了", confirm_quit)

func new_game() -> void:
	if FileAccess.file_exists(saves.path) and saves.read_profile(repository.data).is_empty():
		notice = saves.error
		show_screen("title")
		return
	snapshot = repository.data.duplicate(true)
	profile = Progression.new_player(snapshot)
	Shop.restock(profile, snapshot, shop_rng)
	notice = ""
	persist()
	show_screen("hub")

func persist() -> void:
	if not is_test and not saves.save(profile, snapshot):
		notice = saves.error

func dev_enabled() -> bool:
	return ProjectSettings.get_setting("cardslayer/development_enabled", true)

# ------------------------------------------------------------------ home base (real screens)

func hub_screen(next: String) -> void:
	if hub_view == null:
		hub_view = HubView.new()
		add_child(hub_view)
		hub_view.setup(profile, snapshot, sound, {"test": is_test, "dev": dev_enabled()})
		hub_view.navigate.connect(show_screen)
		hub_view.depart_requested.connect(depart)
		hub_view.editor_requested.connect(editor_shortcut)
		hub_view.debug_requested.connect(func() -> void: show_screen("debug_" + hub_view.page))
		hub_view.title_requested.connect(func() -> void: show_screen("title"))
		hub_view.profile_changed.connect(persist)
	hub_view.show_page(next)
	if not notice.is_empty():
		hub_view.notify(notice)

func clear_hub_view() -> void:
	if hub_view != null:
		remove_child(hub_view)
		hub_view.queue_free()
		hub_view = null

# ------------------------------------------------------------------ home base (debug menu)
# Same actions as HubView via HubActions / Shop. Change both UIs together.

func debug_header(title: String, real_page: String) -> void:
	label("デバッグメニュー — " + title, page, 28)
	var bar := row()
	if real_page != "hub":
		button("◀ デバッグメニューへ", func() -> void: show_screen("debug_hub"), bar)
	button("実画面で表示", func() -> void: show_screen(real_page), bar)

func debug_hub_screen() -> void:
	debug_header("本拠地", "hub")
	for line: String in HubActions.status_lines(profile, snapshot):
		label(line)
	var controls := HFlowContainer.new()
	page.add_child(controls)
	button("主人公の状態", func() -> void: show_screen("debug_status"), controls)
	button("カード一覧", func() -> void: show_screen("debug_cards"), controls)
	button("デッキ編集 (%d枚)" % profile.deck.size(), func() -> void: show_screen("debug_deck"), controls)
	button("装備編集", func() -> void: show_screen("debug_equipment"), controls)
	button("持ち物", func() -> void: show_screen("debug_items"), controls)
	button("ショップ", func() -> void: show_screen("debug_shop"), controls)
	button("出撃", depart, controls)
	if not is_test and dev_enabled():
		button("総合エディタ", open_editor, controls)
	if not is_test:
		button("タイトル", func() -> void: show_screen("title"), controls)
	var backgrounds := row()
	label("背景: ", backgrounds)
	for entry: Dictionary in HubActions.BACKGROUNDS:
		var id: String = entry.id
		button(entry.name, func() -> void:
			HubActions.set_background(profile, id)
			persist()
			show_screen("debug_hub"), backgrounds, profile.hub_background == id)
	label("敏捷・運は表示と装備条件のみ。戦闘ボーナス・抽選補正は未実装。")

func debug_status_screen() -> void:
	debug_header("主人公の状態", "status")
	for line: String in HubActions.status_lines(profile, snapshot):
		label(line)
	for slot: String in EquipmentGenerator.SLOTS:
		var item := HubActions.equipped_item(profile, slot)
		var line := label("%s: %s" % [UiText.name_for(slot), HubActions.item_title(item, snapshot) if not item.is_empty() else "なし"])
		if not item.is_empty():
			line.add_theme_color_override("font_color", EquipmentGenerator.COLORS[item.rarity])

func debug_cards_screen() -> void:
	debug_header("カード一覧", "cards")
	var list := scroll_column()
	for card: Dictionary in repository.records("cards", snapshot):
		var line := row(list)
		var preview := CardView.new()
		preview.configure(card)
		line.add_child(preview)
		label("デッキ %d 枚" % profile.deck.count(card.id), line)

func debug_deck_screen() -> void:
	debug_header("デッキ編集 — %d / %d～%d枚（各種類%d枚まで）" % [profile.deck.size(), HubActions.DECK_MIN, HubActions.DECK_MAX, HubActions.COPIES_MAX], "deck")
	var list := scroll_column()
	for card: Dictionary in repository.records("cards", snapshot):
		var line := row(list)
		var preview := CardView.new()
		preview.configure(card)
		line.add_child(preview)
		var id: String = card.id
		label("%d 枚" % profile.deck.count(id), line)
		var add_reason := HubActions.add_card_reason(profile, id)
		button("＋", func() -> void:
			if HubActions.add_card(profile, id):
				persist()
			show_screen("debug_deck"), line, not add_reason.is_empty()).tooltip_text = add_reason
		var remove_reason := HubActions.remove_card_reason(profile, id)
		button("−", func() -> void:
			if HubActions.remove_card(profile, id):
				persist()
			show_screen("debug_deck"), line, not remove_reason.is_empty()).tooltip_text = remove_reason

func debug_equipment_screen() -> void:
	debug_header("装備 — 基礎能力で装備条件を判定", "equipment")
	label("現在: " + HubActions.stats_text(Progression.stats(profile, snapshot)))
	var controls := HFlowContainer.new()
	page.add_child(controls)
	for slot: String in EquipmentGenerator.SLOTS:
		button(UiText.name_for(slot) + " を外す", func() -> void:
			if HubActions.unequip(profile, slot, snapshot):
				persist()
			show_screen("debug_equipment"), controls, not profile.equipped.has(slot))
	var list := scroll_column()
	if profile.inventory.is_empty():
		label("戦闘に勝つかショップで購入すると装備が手に入ります。", list)
	for item: Dictionary in profile.inventory:
		label(HubActions.item_text(item, snapshot), list).add_theme_color_override("font_color", EquipmentGenerator.COLORS[item.rarity])
		label("装備後: " + HubActions.stats_text(HubActions.preview_equip(profile, item, snapshot)) + " / " + HubActions.requirement_text(item, snapshot), list)
		var reason := HubActions.equip_reason(profile, item, snapshot)
		button("装備中" if HubActions.is_equipped(profile, item) else "装備する", func() -> void:
			if HubActions.equip(profile, item, snapshot):
				persist()
			show_screen("debug_equipment"), list, not reason.is_empty()).tooltip_text = reason

func debug_shop_screen() -> void:
	debug_header("ショップ", "shop")
	label("所持金 %d G / 品揃えは出撃から帰還するたびに入れ替わります" % profile.gold)
	var list := scroll_column()
	var offers := Shop.stock(profile)
	if offers.is_empty():
		label("商品がありません。", list)
	for i: int in offers.size():
		var offer: Dictionary = offers[i]
		if offer.kind == "consumable":
			var good := HubActions.consumable(snapshot, offer.id)
			label("[消費アイテム] %s — %s（所持 %d）" % [good.name, good.description, HubActions.owned(profile, offer.id)], list)
		else:
			label(HubActions.item_text(offer.item, snapshot), list).add_theme_color_override("font_color", EquipmentGenerator.COLORS[offer.item.rarity])
			label("装備後: " + HubActions.stats_text(HubActions.preview_equip(profile, offer.item, snapshot)) + " / " + HubActions.requirement_text(offer.item, snapshot), list)
		var reason := Shop.buy_reason(profile, i)
		button("売り切れ" if offer.sold else "購入 %d G" % int(offer.price), func() -> void:
			if Shop.buy(profile, i):
				persist()
			show_screen("debug_shop"), list, not reason.is_empty()).tooltip_text = reason

func debug_items_screen() -> void:
	debug_header("持ち物（消費アイテム）", "items")
	label("持ち込み %d / %d個: %s" % [profile.loadout.size(), ItemRunner.carry_limit(snapshot), "、".join(profile.loadout.map(func(id: String) -> String: return HubActions.consumable(snapshot, id).get("name", id))) if not profile.loadout.is_empty() else "なし"])
	var carried := row()
	for i: int in profile.loadout.size():
		var slot := i
		button("外す: " + str(HubActions.consumable(snapshot, profile.loadout[i]).get("name", "")), func() -> void:
			if HubActions.unload_item(profile, slot):
				persist()
			show_screen("debug_items"), carried)
	var list := scroll_column()
	var owned_ids: Array = profile.consumables.keys()
	if owned_ids.is_empty():
		label("消費アイテムを持っていません。ショップで購入できます。", list)
	for id: String in owned_ids:
		var item := HubActions.consumable(snapshot, id)
		label("%s ×%d（持ち込み %d） — %s / %s" % [item.name, HubActions.owned(profile, id), profile.loadout.count(id), item.description, UiText.name_for(item.scene)], list)
		var reason := HubActions.load_reason(profile, snapshot, id)
		button("持ち込む", func() -> void:
			if HubActions.load_item(profile, snapshot, id):
				persist()
			show_screen("debug_items"), list, not reason.is_empty()).tooltip_text = reason

func depart() -> void:
	if not repository.reload():
		notice = "\n".join(repository.errors)
		show_screen("hub")
		return
	var validation := saves.validate(profile, repository.data)
	if not validation.is_empty():
		notice = validation
		show_screen("hub")
		return
	snapshot = repository.data.duplicate(true)
	area_id = repository.records("areas", snapshot)[0].id
	node_id = repository.indexed("areas", snapshot)[area_id].start
	passed.clear()
	passed.append(node_id)
	HubActions.clamp_profile(profile, snapshot)
	show_screen("map")

func area_node(id: String) -> Dictionary:
	for node: Dictionary in repository.indexed("areas", snapshot)[area_id].nodes:
		if node.id == id:
			return node
	return {}

func map_screen() -> void:
	var area: Dictionary = repository.indexed("areas", snapshot)[area_id]
	label(area.name + " — 分岐マップ", page, 32)
	label("現在HP %d / %d  現在地 %s" % [profile.hp, Progression.stats(profile, snapshot).max_hp, node_id])
	for node: Dictionary in area.nodes:
		label("%s %s → %s" % ["✓" if node.id in passed else "○", node.id, ", ".join(node.next)])
	var choices := row()
	for next: String in area_node(node_id).next:
		if next in passed:
			continue
		button("%s に進む / %s" % [next, ", ".join(area_node(next).enemies)], func() -> void:
			node_id = next
			passed.append(next)
			start_battle(area_node(next).enemies), choices)
	var carried: Array = HubActions.carried(profile, snapshot)
	if not carried.is_empty():
		var items := row()
		label("持ち込みアイテム:", items)
		for id: String in carried.duplicate():
			var item := HubActions.consumable(snapshot, id)
			var reason := HubActions.field_use_reason(profile, snapshot, id, item_rng)
			button("%s を使う" % item.name, func() -> void:
				var result := HubActions.use_field_item(profile, snapshot, id, item_rng)
				if result.ok:
					sound.play(str(item.get("sound", "item_use")))
					notice = "%s を使用: %s" % [item.name, HubActions.item_summary(result.results)]
				show_screen("map")
				notice = "", items, not reason.is_empty()).tooltip_text = item.description + ("\n使用不可: " + reason if not reason.is_empty() else "")
	button("本拠地へ帰還", retreat)
	if not is_test and dev_enabled():
		button("開発メニュー", open_editor)

func start_battle(enemy_ids: Array) -> void:
	battle = BattleEngine.new()
	battle.setup(snapshot, Progression.stats(profile, snapshot), int(profile.hp), profile.deck, enemy_ids, battle_rng.randi(), HubActions.carried(profile, snapshot))
	reward_claim = {}
	reward_result = {}
	show_screen("battle")

func battle_screen() -> void:
	if battle_view != null and battle_view.engine == battle:
		battle_view.sync()
		return
	clear_battle_view()
	battle_view = BattleView.new()
	add_child(battle_view)
	battle_view.setup(battle, sound, {
		"area": repository.indexed("areas", snapshot)[area_id].name if not area_id.is_empty() else "",
		"node": node_id,
		"boss": boss_battle(),
		"test": is_test,
		"seed": str(test_config.get("seed", "")) if is_test else "",
		"dev": ProjectSettings.get_setting("cardslayer/development_enabled", true),
		"notice": notice,
	})
	battle_view.action_finished.connect(after_action)
	battle_view.editor_requested.connect(editor_shortcut)
	battle_view.retreat_requested.connect(retreat)
	battle_view.item_used.connect(func(id: String) -> void: HubActions.consume_item(profile, id))
	battle_view.retry_requested.connect(func(new_seed: bool) -> void:
		if new_seed:
			test_config.seed = randi()
		start_test(test_config, test_area))

func clear_battle_view() -> void:
	if battle_view != null:
		remove_child(battle_view)
		battle_view.queue_free()
		battle_view = null

## Boss node of the current area, or (in a battle test) any enemy that guards an area boss node.
func boss_battle() -> bool:
	if battle == null:
		return false
	var areas: Dictionary = repository.indexed("areas", snapshot)
	if not area_id.is_empty():
		return node_id == areas[area_id].boss
	for area: Dictionary in areas.values():
		for node: Dictionary in area.nodes:
			if node.id == area.boss:
				for enemy: Dictionary in battle.enemies:
					if enemy.id in node.enemies:
						return true
	return false

func update_music() -> void:
	if is_instance_valid(editor) and editor.visible:
		sound.play_bgm("")
	elif screen == "battle":
		sound.play_bgm("boss" if boss_battle() else "battle")
	else:
		sound.play_bgm("hub")

## Direct (non-animated) play used by automated checks.
## Direct (non-animated) item use used by automated checks.
func use_item(slot: int, target: int) -> void:
	var id: String = battle.items[slot] if slot >= 0 and slot < battle.items.size() else ""
	if battle.use_item(slot, target):
		HubActions.consume_item(profile, id)
	after_action()

func use_card(index: int, target: int) -> void:
	battle.play(index, target)
	after_action()

func after_action() -> void:
	if battle.outcome == "victory":
		if reward_claim.get("claimed", false):
			return
		var is_boss: bool = not area_id.is_empty() and node_id == repository.indexed("areas", snapshot)[area_id].boss
		reward_result = Progression.reward(profile, battle, reward_claim, loot_rng, area_id, is_boss)
		persist()
		show_screen("reward")
	elif battle.outcome == "defeat":
		notice = "敗北しました。確定済みの報酬は保持されます。"
		return_hub()
	else:
		show_screen("battle")

func reward_screen() -> void:
	label("勝利 — 報酬確定", page, 36)
	label("EXP +%s  Gold +%s  レベルアップ +%s" % [reward_result.xp, reward_result.gold, reward_result.levels])
	label(HubActions.item_text(reward_result.item, snapshot)).add_theme_color_override("font_color", EquipmentGenerator.COLORS[reward_result.item.rarity])
	button("次へ", func() -> void:
		if area_id.is_empty() or node_id == repository.indexed("areas", snapshot)[area_id].boss:
			return_hub()
		else:
			show_screen("map"))

func retreat() -> void:
	confirm("本拠地へ帰還しますか？確定済みの報酬は保持します。出撃進行は失われます。", return_hub)

func return_hub() -> void:
	area_id = ""
	node_id = ""
	passed.clear()
	var stats := Progression.stats(profile, snapshot)
	profile.hp = int(stats.max_hp)
	profile.mp = int(stats.max_mp)
	battle = null
	# The shop gets new goods every time an expedition ends.
	Shop.restock(profile, snapshot, shop_rng)
	persist()
	show_screen("hub")

func confirm(text: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = text
	dialog.ok_button_text = "確認"
	dialog.cancel_button_text = "キャンセル"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void: dialog.queue_free(); action.call())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func open_editor() -> void:
	clear_battle_view()
	clear_hub_view()
	paused = {"profile": profile, "snapshot": snapshot, "battle": battle, "screen": screen, "area_id": area_id, "node_id": node_id, "passed": passed.duplicate(), "claim": reward_claim, "reward": reward_result, "loot_state": loot_rng.state, "battle_state": battle_rng.state, "notice": notice}
	page.hide()
	editor = DefinitionEditor.new()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.offset_left = 16
	editor.offset_top = 12
	editor.offset_right = -16
	editor.offset_bottom = -12
	add_child(editor)
	editor.setup(repository)
	editor.exit_requested.connect(close_editor)
	editor.test_requested.connect(start_test)
	update_music()

func close_editor() -> void:
	editor.queue_free()
	editor = null
	profile = paused.profile
	snapshot = paused.snapshot
	battle = paused.battle
	area_id = paused.area_id
	node_id = paused.node_id
	passed.assign(paused.passed)
	reward_claim = paused.claim
	reward_result = paused.reward
	loot_rng.state = paused.loot_state
	battle_rng.state = paused.battle_state
	notice = paused.notice
	is_test = false
	page.show()
	show_screen(paused.screen)

func start_test(settings: Dictionary, area_test: bool) -> void:
	if not repository.reload():
		editor.status.text = "\n".join(repository.errors)
		return
	is_test = true
	test_config = settings.duplicate(true)
	test_area = area_test
	snapshot = repository.data.duplicate(true)
	profile = Progression.new_player(snapshot)
	profile.base = settings.base.duplicate(true)
	profile.deck = settings.deck.duplicate()
	profile.hp = int(settings.hp)
	profile.consumables = {}
	profile.loadout = []
	for id: String in settings.get("consumables", []):
		HubActions.gain_item(profile, id)
		profile.loadout.append(id)
	var gear_rng := RandomNumberGenerator.new()
	gear_rng.seed = int(settings.seed) + 2
	for id: String in settings.equipment:
		var base: Dictionary = repository.indexed("items", snapshot)[id]
		if not Progression.can_equip(profile, base):
			continue
		var item: Dictionary = EquipmentGenerator.new(snapshot).generate(gear_rng, 1, "common", id).item
		item["instance_id"] = "test_" + id
		profile.inventory.append(item)
		Progression.equip(profile, item, snapshot)
	battle_rng.seed = int(settings.seed)
	loot_rng.seed = int(settings.seed) + 1
	area_id = settings.area if area_test else ""
	node_id = repository.indexed("areas", snapshot)[area_id].start if area_test else ""
	passed.assign([node_id] if area_test else [])
	notice = ""
	editor.hide()
	page.show()
	if area_test:
		show_screen("map")
	else:
		start_battle(settings.enemies)

func return_editor() -> void:
	is_test = false
	clear_battle_view()
	clear_hub_view()
	battle = null
	page.hide()
	editor.show()
	update_music()
	editor.detail_scroll.scroll_vertical = editor.saved_scroll
