class_name DefinitionEditor
extends VBoxContainer

signal exit_requested
signal test_requested(settings: Dictionary, area_test: bool)
var repository: DefinitionRepository
var draft: Dictionary
var group: String = "cards"
var selected_id: String = "strike"
var dirty: bool = false
var detail_scroll: ScrollContainer
var list_box: VBoxContainer
var detail: VBoxContainer
var status: Label
var search: String = ""
var saved_scroll: int = 0
var test_settings: Dictionary = {}
var generator_panel: GeneratorPanel
var record_buttons: Array[Button] = []

func setup(repo: DefinitionRepository) -> void:
	repository = repo
	draft = repo.data.duplicate(true)
	var profile := Progression.new_player(draft)
	test_settings = {"seed": 12345, "hp": 60, "base": profile.base, "deck": profile.deck, "enemies": [repo.records("enemies")[0].id], "equipment": [], "area": repo.records("areas")[0].id, "consumables": ItemRunner.settings(draft).starter.duplicate(), "cleared": []}
	build()

func label_at(parent: Node, value: String) -> Label:
	var label := Label.new()
	label.text = value
	parent.add_child(label)
	return label

func button_at(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func build() -> void:
	add_theme_constant_override("separation", 8)
	label_at(self, "総合エディタ — " + repository.root)
	status = label_at(self, "改訂 " + repository.revision())
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var toolbar := HFlowContainer.new()
	add_child(toolbar)
	button_at(toolbar, "保存", save)
	button_at(toolbar, "再読込", func() -> void: guard_change(reload_draft))
	record_buttons.append(button_at(toolbar, "新規", func() -> void: create_record(false)))
	record_buttons.append(button_at(toolbar, "複製", func() -> void: create_record(true)))
	record_buttons.append(button_at(toolbar, "削除", delete_record))
	button_at(toolbar, "保存して戦闘テスト", func() -> void: launch_test(false))
	button_at(toolbar, "保存してエリア試遊", func() -> void: launch_test(true))
	button_at(toolbar, "書き出し", export_data)
	button_at(toolbar, "編集終了", func() -> void: guard_change(func() -> void: exit_requested.emit()))
	var tabs := HFlowContainer.new()
	add_child(tabs)
	var names := ["カード", "敵", "装備", "アフィックス", "エリア", "計算式", "ルール", "消費アイテム", "テスト設定", "装備ジェネレーター"]
	var groups: Array = DefinitionRepository.GROUPS.duplicate()
	groups.append("test")
	groups.append("generator")
	for i: int in groups.size():
		var next_group: String = groups[i]
		button_at(tabs, names[i], func() -> void:
			group = next_group
			selected_id = "" if group in ["test", "generator"] else str(repository.records(group, draft)[0].id)
			saved_scroll = 0
			refresh())
	var content := HSplitContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(content)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 210
	content.add_child(sidebar)
	var search_field := LineEdit.new()
	search_field.placeholder_text = "名前・IDを検索"
	sidebar.add_child(search_field)
	search_field.text_changed.connect(func(value: String) -> void: search = value; refresh_list())
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list_box)
	detail_scroll = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(detail)
	refresh()

func current_record() -> Dictionary:
	for record: Dictionary in repository.records(group, draft):
		if record.id == selected_id:
			return record
	return {}

func refresh_list() -> void:
	clear_children(list_box)
	if group in ["test", "generator"]:
		return
	for record: Dictionary in repository.records(group, draft):
		if not search.is_empty() and search.to_lower() not in (record.id + str(record.get("name", ""))).to_lower():
			continue
		var id: String = record.id
		button_at(list_box, str(record.get("name", id)) + "\n" + id, func() -> void:
			selected_id = id
			saved_scroll = 0
			refresh())

func refresh() -> void:
	for button: Button in record_buttons:
		button.disabled = group in ["test", "generator"]
	refresh_list()
	if is_instance_valid(generator_panel) and generator_panel.get_parent() == detail:
		detail.remove_child(generator_panel)
	clear_children(detail)
	if group == "generator" or (group == "rules" and selected_id == "loot"):
		if not is_instance_valid(generator_panel):
			generator_panel = GeneratorPanel.new()
			detail.add_child(generator_panel)
			generator_panel.setup(self)
		else:
			detail.add_child(generator_panel)
			generator_panel.refresh()
	elif group == "test":
		label_at(detail, "通常セーブと独立したテスト条件。装備は基底ID（コモン個体）。")
		form(detail, test_settings, "test")
	else:
		var record := current_record()
		if record.is_empty():
			return
		form(detail, record, group)
		if group == "cards":
			button_at(detail, "カードプレビュー更新", refresh_preserving_scroll)
			var preview := CardView.new()
			preview.configure(record)
			detail.add_child(preview)
		if group == "enemies":
			button_at(detail, "この敵をテスト対象に設定", func() -> void:
				test_settings.enemies = [selected_id]
				status.text = "テスト対象: " + selected_id)
		if group == "areas":
			label_at(detail, "接続図")
			for node: Dictionary in record.nodes:
				label_at(detail, "%s → %s" % [node.id, ", ".join(node.next)])
			button_at(detail, "このエリアを試遊対象に設定", func() -> void: test_settings.area = selected_id)
			var cleared_toggle := CheckBox.new()
			cleared_toggle.text = "テストプレイでクリア済みとして扱う"
			cleared_toggle.button_pressed = selected_id in test_settings.cleared
			var area_id := selected_id
			cleared_toggle.toggled.connect(func(on: bool) -> void:
				if on and area_id not in test_settings.cleared:
					test_settings.cleared.append(area_id)
				elif not on:
					test_settings.cleared.erase(area_id))
			detail.add_child(cleared_toggle)
		if group == "consumables":
			consumable_tools(record)
		if group == "formulas":
			var inputs: Dictionary = {"base": 6, "scaling": 0.5, "strength": 5, "wisdom": 5, "agility": 5, "luck": 5, "max_hp": 60, "max_mp": 10}
			label_at(detail, "サンプル入力")
			form(detail, inputs, "sample")
			var result := label_at(detail, "")
			button_at(detail, "評価", func() -> void:
				var evaluation := FormulaEvaluator.new().evaluate(record.expression, inputs)
				result.text = "結果: %s（整数化 %s）" % [evaluation.value, floor(maxf(0, evaluation.value))] if evaluation.ok else evaluation.error)
	detail_scroll.set_deferred("scroll_vertical", saved_scroll)

func changed() -> void:
	dirty = true
	status.text = "未保存の変更あり / 改訂 " + repository.revision()

func refresh_preserving_scroll() -> void:
	saved_scroll = detail_scroll.scroll_vertical
	refresh()

func options_for(key: String) -> Array:
	match key:
		"type": return DefinitionRepository.EFFECTS
		"target": return ItemRunner.TARGETS if group == "consumables" else ["self", "selected_enemy", "all_enemies", "player"]
		"category": return ["attack", "support", "buff"]
		"slot": return EquipmentGenerator.SLOTS
		"stat": return DefinitionRepository.STATS
		"formula_id": return [""] + repository.indexed("formulas", draft).keys()
		"enemies": return repository.indexed("enemies", draft).keys()
		"affixes": return repository.indexed("affixes", draft).keys()
		"deck", "starter_deck": return repository.indexed("cards", draft).keys()
		"equipment", "loot_bases": return repository.indexed("items", draft).keys()
		"area": return repository.indexed("areas", draft).keys()
		"consumables", "starter": return repository.indexed("consumables", draft).keys()
		"kind": return ItemRunner.KINDS
		"conditions": return ItemRunner.CONDITIONS
		"scene": return ItemRunner.SCENES
		"icon": return ItemRunner.ICONS
		"sound": return ItemRunner.SOUNDS
		"animation": return ItemRunner.ANIMATIONS
		"start", "boss", "next":
			var result: Array = []
			for node: Dictionary in current_record().get("nodes", []):
				result.append(node.id)
			return result
	return []

func form(parent: Node, object: Dictionary, path: String) -> void:
	for key: String in object.keys():
		var value: Variant = object[key]
		if value is Dictionary:
			label_at(parent, UiText.name_for(key))
			if key in ["bonuses", "requirements"]:
				for stat: String in DefinitionRepository.STATS:
					if not value.has(stat):
						value[stat] = 0
			form(parent, value, path + "/" + key)
		elif key == "cleared" and path == "test":
			cleared_form(parent, value)
		elif value is Array:
			array_form(parent, value, key, path)
		elif key == "script" and group == "consumables":
			script_form(parent, object)
		elif key == "effect_color" and group == "consumables":
			var row := HBoxContainer.new()
			parent.add_child(row)
			label_at(row, UiText.name_for(key)).custom_minimum_size.x = 140
			var picker := ColorPickerButton.new()
			picker.color = Color.html(str(value)) if Color.html_is_valid(str(value)) else Color.WHITE
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(120, 32)
			row.add_child(picker)
			picker.color_changed.connect(func(color: Color) -> void: object[key] = color.to_html(false); changed())
		else:
			var row := HBoxContainer.new()
			parent.add_child(row)
			var caption := label_at(row, UiText.name_for(key))
			caption.custom_minimum_size.x = 140
			var setter := func(new_value: Variant) -> void: object[key] = new_value; changed()
			if value is int or value is float:
				var number := SpinBox.new()
				number.min_value = -100000
				number.max_value = 1000000000
				number.step = 0.01 if key == "scaling" or path.ends_with("/level_growth") else 1.0
				number.value = float(value)
				number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(number)
				number.value_changed.connect(setter)
			else:
				var choices := options_for(key)
				if not choices.is_empty():
					choice_control(row, choices, str(value), setter)
				else:
					var field := LineEdit.new()
					field.text = str(value)
					field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					field.editable = key != "id" or "/" in path
					row.add_child(field)
					field.text_changed.connect(setter)

func choice_control(parent: Node, choices: Array, value: String, setter: Callable) -> void:
	var dropdown := OptionButton.new()
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(dropdown)
	var available := choices.duplicate()
	if value not in available:
		available.append(value)
	for choice: Variant in available:
		dropdown.add_item(UiText.name_for(str(choice)) if str(choice) != "" else "（なし）")
	dropdown.select(available.find(value))
	dropdown.item_selected.connect(func(index: int) -> void: setter.call(available[index]))

func array_form(parent: Node, values: Array, key: String, path: String) -> void:
	label_at(parent, "%s (%d)" % [UiText.name_for(key), values.size()])
	for i: int in values.size():
		var box := VBoxContainer.new()
		parent.add_child(box)
		var row := HBoxContainer.new()
		box.add_child(row)
		label_at(row, "#%d" % (i + 1))
		button_at(row, "↑", func() -> void:
			if i > 0:
				var previous: Variant = values[i - 1]
				values[i - 1] = values[i]
				values[i] = previous
				changed(); refresh_preserving_scroll())
		button_at(row, "↓", func() -> void:
			if i < values.size() - 1:
				var next: Variant = values[i + 1]
				values[i + 1] = values[i]
				values[i] = next
				changed(); refresh_preserving_scroll())
		button_at(row, "削除", func() -> void: values.remove_at(i); changed(); refresh_preserving_scroll())
		if values[i] is Dictionary:
			form(box, values[i], path + "/" + key)
		else:
			choice_control(row, options_for(key), str(values[i]), func(value: Variant) -> void: values[i] = value; changed())
	button_at(parent, UiText.name_for(key) + " を追加", func() -> void:
		match key:
			"effects": values.append({"type": "damage", "target": "selected_enemy", "value": 1, "scaling": 0.0, "formula_id": "", "stat": "strength"})
			"actions": values.append({"name": "新しい行動", "effects": [{"type": "damage", "target": "player", "value": 1, "scaling": 0.0, "formula_id": "", "stat": "strength"}]})
			"nodes": values.append({"id": "node_" + str(values.size()), "enemies": [], "next": []})
			"basic_effects": values.append({"kind": "heal", "min": 1, "max": 1, "stat": "strength"})
			_:
				var choices := options_for(key)
				if not choices.is_empty():
					values.append(choices[0])
		changed(); refresh_preserving_scroll())

func save() -> bool:
	if not repository.save_draft(draft):
		status.text = "\n".join(repository.errors)
		return false
	dirty = false
	status.text = "保存済み / 改訂 " + repository.revision()
	return true

func reload_draft() -> void:
	if repository.reload():
		draft = repository.data.duplicate(true)
		dirty = false
		refresh()
	else:
		status.text = "\n".join(repository.errors)

func guard_change(action: Callable) -> void:
	if not dirty:
		action.call()
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "未保存の変更があります。保存／破棄／キャンセルを選んでください。"
	dialog.ok_button_text = "保存"
	dialog.cancel_button_text = "キャンセル"
	dialog.add_button("破棄", true, "discard")
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		if save():
			action.call()
		dialog.queue_free())
	dialog.custom_action.connect(func(_action: StringName) -> void:
		draft = repository.data.duplicate(true)
		dirty = false
		dialog.queue_free()
		action.call())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func create_record(duplicate: bool) -> void:
	if group in ["test", "generator"]:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "複製" if duplicate else "新規（現在の項目を雛形に作成）"
	var field := LineEdit.new()
	field.placeholder_text = "新しいID（英数字・アンダースコア）"
	field.custom_minimum_size = Vector2(420, 48)
	dialog.add_child(field)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var id := field.text.strip_edges()
		if id.is_empty() or not id.is_valid_identifier() or repository.indexed(group, draft).has(id):
			status.text = "IDが不正または重複しています"
		else:
			var record := current_record().duplicate(true)
			record.id = id
			if record.has("name") and not duplicate:
				record.name = "新しい定義"
			draft[group].entries.append(record)
			selected_id = id
			changed(); refresh()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func delete_record() -> void:
	if group in ["test", "generator"]:
		return
	var candidate := draft.duplicate(true)
	var records: Array = candidate[group].entries
	for i: int in range(records.size() - 1, -1, -1):
		if records[i].id == selected_id:
			records.remove_at(i)
	var errors := repository.validate(candidate)
	if not errors.is_empty():
		status.text = "削除できません（参照元／必須制約）:\n" + "\n".join(errors)
		return
	draft = candidate
	selected_id = records[0].id
	changed(); refresh()

func launch_test(area_test: bool) -> void:
	if not save():
		return
	var settings := test_settings.duplicate(true)
	var profile := Progression.new_player(repository.data)
	profile.base = settings.base
	profile.deck = settings.deck
	var error := SaveRepository.new().validate(profile, repository.data)
	if not error.is_empty():
		status.text = "テスト設定: " + error
		return
	var issues: Array[String] = []
	repository.check_refs(settings.enemies, repository.indexed("enemies"), "test/enemies", issues)
	repository.check_refs(settings.equipment, repository.indexed("items"), "test/equipment", issues)
	repository.check_refs(settings.get("consumables", []), repository.indexed("consumables"), "test/consumables", issues)
	repository.check_refs(settings.get("cleared", []), repository.indexed("areas"), "test/cleared", issues)
	var used_slots: Dictionary = {}
	for id: String in settings.equipment:
		if not repository.indexed("items").has(id):
			continue
		var base: Dictionary = repository.indexed("items")[id]
		if used_slots.has(base.slot):
			issues.append("テスト装備の部位重複: " + UiText.name_for(base.slot))
		if not Progression.can_equip(profile, base):
			issues.append("テスト装備の条件不足: " + id)
		used_slots[base.slot] = true
	if used_slots.has("two_handed") and (used_slots.has("right_hand") or used_slots.has("left_hand")):
		issues.append("両手武器と左右の装備は同時に指定できません")
	if settings.enemies.size() < 1 or settings.enemies.size() > 3:
		issues.append("テストの敵は1～3体必要")
	if not repository.indexed("areas").has(settings.area):
		issues.append("テストエリアがありません")
	if settings.hp <= 0 or settings.hp > settings.base.max_hp:
		issues.append("テストHPは1～基礎最大HP")
	if not issues.is_empty():
		status.text = "\n".join(issues)
		return
	saved_scroll = detail_scroll.scroll_vertical
	test_requested.emit(settings, area_test)

func export_data() -> void:
	if not save():
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	add_child(dialog)
	dialog.dir_selected.connect(func(directory: String) -> void:
		for name: String in DefinitionRepository.GROUPS:
			if DirAccess.copy_absolute(repository.root + "/" + name + ".json", directory.path_join(name + ".json")) != OK:
				status.text = "書き出し失敗: " + name
				return
		status.text = "書き出し完了: " + directory
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.75)

func _exit_tree() -> void:
	if is_instance_valid(generator_panel) and generator_panel.get_parent() == null:
		generator_panel.free()

# ------------------------------------------------------------------ consumables

func script_form(parent: Node, object: Dictionary) -> void:
	label_at(parent, "効果スクリプト（空欄なら上の使用条件と基本効果をそのまま使用）")
	var code := CodeEdit.new()
	code.text = str(object.script)
	code.custom_minimum_size = Vector2(0, 220)
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.gutters_draw_line_numbers = true
	code.indent_use_spaces = false
	parent.add_child(code)
	code.text_changed.connect(func() -> void:
		object.script = code.text
		changed())

func consumable_tools(record: Dictionary) -> void:
	var api := label_at(detail, "スクリプトで使えるctx: in_battle() hp() max_hp() mp() max_mp() stat(名前) bad_statuses() has_target() target_hp() rand_int(a,b)\n  heal(n) restore_mp(n) add_block(n) add_stat(\"strength\",n) reduce_damage(n) cure(\"poison\") cure_random() damage_target(n) damage_all(n) draw(n) message(文字)\n  basic_reason()=選択した使用条件の判定 / apply_basic()=選択した基本効果の実行")
	api.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tools := HFlowContainer.new()
	detail.add_child(tools)
	var result := label_at(detail, "")
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button_at(tools, "テンプレートを挿入", func() -> void:
		if str(record.script).strip_edges().is_empty():
			record.script = ItemRunner.TEMPLATE
			changed()
			refresh_preserving_scroll())
	button_at(tools, "検証", func() -> void:
		var issues := ItemRunner.validate(record)
		result.text = "問題なし" if issues.is_empty() else "\n".join(issues))
	button_at(tools, "試用シミュレーション", func() -> void: result.text = simulate_consumable(record))

## Runs the item in a throwaway battle built from the test settings (hero at
## half HP and poisoned so recovery and cure items can be tried).
func simulate_consumable(record: Dictionary) -> String:
	var issues := ItemRunner.validate(record)
	if not issues.is_empty():
		return "検証エラー:\n" + "\n".join(issues)
	var engine := BattleEngine.new()
	var base: Dictionary = test_settings.base
	engine.setup(draft, base, int(base.max_hp) / 2, test_settings.deck, test_settings.enemies, int(test_settings.seed), [record.id])
	engine.player.poison = 3
	engine.player.mp = int(base.max_mp) / 2
	var before := "HP %d/%d MP %d 毒 %d / 敵HP %d" % [engine.player.hp, base.max_hp, engine.player.mp, engine.player.poison, engine.enemies[0].hp]
	var reason := engine.item_reason(0, 0)
	var lines: Array[String] = ["戦闘（英雄HP半分・毒3・敵1体目を対象）", "使用前: " + before]
	if not reason.is_empty():
		lines.append("使用不可: " + reason)
	else:
		var log_start := engine.log.size()
		engine.use_item(0, 0)
		lines.append_array(engine.log.slice(log_start))
		lines.append("使用後: HP %d MP %d 毒 %d ブロック %d 軽減 %d 強化 %s / 敵HP %d" % [engine.player.hp, engine.player.mp, engine.player.poison, engine.player.block, engine.player.reduction, UiText.bonuses(engine.player.buffs), engine.enemies[0].hp])
	var hero := Progression.new_player(draft)
	hero.base = base.duplicate(true)
	hero.hp = int(base.max_hp) / 2
	hero.consumables = {record.id: 1}
	hero.loadout = [record.id]
	var field_rng := RandomNumberGenerator.new()
	field_rng.seed = int(test_settings.seed)
	var field := HubActions.use_field_item(hero, draft, record.id, field_rng)
	lines.append("マップ（HP半分）: " + (HubActions.item_summary(field.results) if field.ok else "使用不可: " + field.reason))
	return "\n".join(lines)

## Test-play first-clear flags: one checkbox per area.
func cleared_form(parent: Node, cleared: Array) -> void:
	label_at(parent, "クリア済みエリア（テストプレイ用。初クリア報酬の有無に影響）")
	var boxes := HFlowContainer.new()
	parent.add_child(boxes)
	for area: Dictionary in repository.records("areas", draft):
		var id: String = area.id
		var box := CheckBox.new()
		box.text = "%s (%s)" % [area.name, id]
		box.button_pressed = id in cleared
		box.toggled.connect(func(on: bool) -> void:
			if on and id not in cleared:
				cleared.append(id)
			elif not on:
				cleared.erase(id))
		boxes.add_child(box)
