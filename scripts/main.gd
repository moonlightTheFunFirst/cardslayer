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
var selected_card: int = -1
var page: VBoxContainer
var editor: DefinitionEditor
var is_test: bool = false
var paused: Dictionary = {}
var test_config: Dictionary = {}
var test_area: bool = false
var notice: String = ""

func _ready() -> void:
	get_tree().auto_accept_quit = false
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
	if not repository.initialize():
		label("定義データを読み込めません。元ファイルは保持しています。\n" + "\n".join(repository.errors))
		return
	snapshot = repository.data.duplicate(true)
	show_screen("title")
	if "--smoke" in OS.get_cmdline_user_args() and ProjectSettings.get_setting("cardslayer/development_enabled", true):
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
	if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		if screen == "battle" and selected_card >= 0:
			selected_card = -1
			show_screen("battle")

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
	match screen:
		"title": title_screen()
		"hub": hub_screen()
		"deck": deck_screen()
		"equipment": equipment_screen()
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
			show_screen("hub"), page, not FileAccess.file_exists(saves.path))
	if ProjectSettings.get_setting("cardslayer/development_enabled", true):
		button("総合エディタ", open_editor)
	button("終了", confirm_quit)

func new_game() -> void:
	if FileAccess.file_exists(saves.path) and saves.read_profile(repository.data).is_empty():
		notice = saves.error
		show_screen("title")
		return
	snapshot = repository.data.duplicate(true)
	profile = Progression.new_player(snapshot)
	notice = ""
	persist()
	show_screen("hub")

func persist() -> void:
	if not is_test and not saves.save(profile, snapshot):
		notice = saves.error

func stats_text(values: Dictionary) -> String:
	return "HP %d / MP %d / 力 %d / 知恵 %d / 敏捷 %d / 運 %d" % [values.max_hp, values.max_mp, values.strength, values.wisdom, values.agility, values.luck]

func hub_screen() -> void:
	label("拠点 — 探索者のアジト", page, 32)
	label("Lv %d  EXP %d / %d  Gold %d" % [profile.level, profile.xp, profile.level * 30, profile.gold])
	label("基礎: " + stats_text(profile.base))
	label("装備込み: " + stats_text(Progression.stats(profile, snapshot)))
	label("初クリア済み: " + ", ".join(profile.cleared))
	var controls := row()
	button("デッキ編集 (%d枚)" % profile.deck.size(), func() -> void: show_screen("deck"), controls)
	button("装備編集", func() -> void: show_screen("equipment"), controls)
	button("出撃", depart, controls)
	if not is_test and ProjectSettings.get_setting("cardslayer/development_enabled", true):
		button("開発メニュー／総合エディタ", open_editor, controls)
	if not is_test:
		button("タイトル", func() -> void: show_screen("title"), controls)
	label("敏捷・運は表示と装備条件のみ。戦闘ボーナス・抽選補正は未実装。")

func deck_screen() -> void:
	label("デッキ編集 — %d / 20～30枚（各種類10枚まで）" % profile.deck.size(), page, 28)
	button("拠点へ戻る", func() -> void: persist(); show_screen("hub"), page, profile.deck.size() < 20)
	var list := scroll_column()
	for card: Dictionary in repository.records("cards", snapshot):
		var line := row(list)
		var preview := CardView.new()
		preview.configure(card)
		line.add_child(preview)
		label("%d 枚" % profile.deck.count(card.id), line)
		button("＋", func() -> void:
			profile.deck.append(card.id)
			persist(); show_screen("deck"), line, profile.deck.size() >= 30 or profile.deck.count(card.id) >= 10)
		button("−", func() -> void:
			profile.deck.erase(card.id)
			persist(); show_screen("deck"), line, profile.deck.count(card.id) == 0 or profile.deck.size() <= 20)

func item_text(item: Dictionary) -> String:
	var base: Dictionary = repository.indexed("items", snapshot)[item.base_id]
	var parts: Array[String] = []
	for affix: Dictionary in item.affixes:
		parts.append("%s +%d" % [UiText.name_for(affix.stat), affix.value])
	return "%s [%s] %s\n基礎補正: %s / 追加: %s" % [base.name, UiText.name_for(item.rarity), UiText.name_for(base.slot), UiText.bonuses(base.bonuses), "、".join(parts) if not parts.is_empty() else "なし"]

func equipment_screen() -> void:
	label("装備 — 基礎能力で装備条件を判定", page, 28)
	label("現在: " + stats_text(Progression.stats(profile, snapshot)))
	var controls := row()
	button("拠点へ戻る", func() -> void: show_screen("hub"), controls)
	for slot: String in ["weapon", "armor", "accessory"]:
		button(UiText.name_for(slot) + " を外す", func() -> void:
			profile.equipped.erase(slot)
			clamp_profile(); persist(); show_screen("equipment"), controls, not profile.equipped.has(slot))
	var list := scroll_column()
	if profile.inventory.is_empty():
		label("戦闘に勝つと装備が1個手に入ります。", list)
	for item: Dictionary in profile.inventory:
		var base: Dictionary = repository.indexed("items", snapshot)[item.base_id]
		label(item_text(item), list)
		var comparison := profile.duplicate(true)
		comparison.equipped[base.slot] = item.instance_id
		label("装備後: " + stats_text(Progression.stats(comparison, snapshot)) + " / 必要Lv %s %s" % [base.level, UiText.bonuses(base.requirements)], list)
		button("装備中" if item.instance_id in profile.equipped.values() else "装備する", func() -> void:
			profile.equipped[base.slot] = item.instance_id
			clamp_profile(); persist(); show_screen("equipment"), list, not Progression.can_equip(profile, base) or item.instance_id in profile.equipped.values())

func clamp_profile() -> void:
	var stats := Progression.stats(profile, snapshot)
	profile.hp = mini(int(profile.hp), int(stats.max_hp))
	profile.mp = mini(int(profile.mp), int(stats.max_mp))

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
	clamp_profile()
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
	button("撤退", retreat)
	if not is_test and ProjectSettings.get_setting("cardslayer/development_enabled", true):
		button("開発メニュー", open_editor)

func start_battle(enemy_ids: Array) -> void:
	battle = BattleEngine.new()
	battle.setup(snapshot, Progression.stats(profile, snapshot), int(profile.hp), profile.deck, enemy_ids, battle_rng.randi())
	reward_claim = {}
	reward_result = {}
	selected_card = -1
	show_screen("battle")

func battle_screen() -> void:
	label("戦闘 / ターン %d / 山札 %d枚" % [battle.turn, battle.deck.size()], page, 25)
	var enemy_row := row()
	for i: int in battle.enemies.size():
		var enemy: Dictionary = battle.enemies[i]
		var text := "%s\nHP %d / %d  ブロック %d  毒 %d\n%s" % [enemy.name, enemy.hp, battle.effective(enemy).max_hp, enemy.block, enemy.poison, battle.intent(enemy)]
		var target := button(text, func() -> void:
			if selected_card >= 0:
				use_card(selected_card, i), enemy_row, enemy.hp <= 0)
		target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target.custom_minimum_size.y = 110
	label("英雄 HP %d / %d   MP %d / %d   AP %d   ブロック %d   毒 %d   強化 %s" % [battle.player.hp, battle.effective(battle.player).max_hp, battle.player.mp, battle.effective(battle.player).max_mp, battle.ap, battle.player.block, battle.player.poison, UiText.bonuses(battle.player.buffs)])
	var controls := row()
	button("ターン終了", func() -> void: battle.end_turn(); after_action(), controls, not battle.outcome.is_empty() or not battle.fault.is_empty())
	button("選択解除（右クリック / Esc）", func() -> void: selected_card = -1; show_screen("battle"), controls)
	if selected_card >= 0 and not battle.needs_target(battle.cards[battle.hand[selected_card]]):
		button("選択カードを使用", func() -> void: use_card(selected_card, -1), controls)
	button("撤退", retreat, controls)
	if not is_test and ProjectSettings.get_setting("cardslayer/development_enabled", true):
		button("開発メニュー", open_editor, controls)
	if not battle.fault.is_empty():
		label("停止: " + battle.fault)
	var log_view := RichTextLabel.new()
	log_view.custom_minimum_size.y = 70
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.text = "\n".join(battle.log.slice(maxi(0, battle.log.size() - 30)))
	log_view.scroll_following = true
	page.add_child(log_view)
	label("カードをクリック → 単体対象は敵をクリック。自己／全体対象は「選択カードを使用」。")
	var hand_scroll := ScrollContainer.new()
	hand_scroll.custom_minimum_size.y = 220
	page.add_child(hand_scroll)
	var hand_row := row(hand_scroll)
	for i: int in battle.hand.size():
		var card := CardView.new()
		card.configure(battle.cards[battle.hand[i]], battle.can_play(i, -1, false), selected_card == i, battle)
		card.pressed.connect(func() -> void: selected_card = i; show_screen("battle"))
		hand_row.add_child(card)

func use_card(index: int, target: int) -> void:
	if battle.play(index, target):
		selected_card = -1
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
	label(item_text(reward_result.item))
	button("次へ", func() -> void:
		if area_id.is_empty() or node_id == repository.indexed("areas", snapshot)[area_id].boss:
			return_hub()
		else:
			show_screen("map"))

func retreat() -> void:
	confirm("撤退して拠点へ戻りますか？確定済みの報酬は保持します。出撃進行は失われます。", return_hub)

func return_hub() -> void:
	area_id = ""
	node_id = ""
	passed.clear()
	var stats := Progression.stats(profile, snapshot)
	profile.hp = int(stats.max_hp)
	profile.mp = int(stats.max_mp)
	battle = null
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

func close_editor() -> void:
	editor.queue_free()
	editor = null
	profile = paused.profile
	snapshot = paused.snapshot
	battle = paused.battle
	selected_card = -1
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
	for id: String in settings.equipment:
		var base: Dictionary = repository.indexed("items", snapshot)[id]
		if not Progression.can_equip(profile, base):
			continue
		var item: Dictionary = {"instance_id": "test_" + id, "base_id": id, "rarity": "common", "affixes": []}
		profile.inventory.append(item)
		profile.equipped[base.slot] = item.instance_id
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
	battle = null
	page.hide()
	editor.show()
	editor.detail_scroll.scroll_vertical = editor.saved_scroll
