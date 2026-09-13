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

func setup(repo: DefinitionRepository) -> void:
	repository = repo
	draft = repo.data.duplicate(true)
	var profile := Progression.new_player(draft)
	test_settings = {"seed": 12345, "hp": 60, "base": profile.base, "deck": profile.deck, "enemies": [repo.records("enemies")[0].id], "equipment": [], "area": repo.records("areas")[0].id}
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
	button_at(toolbar, "新規", func() -> void: create_record(false))
	button_at(toolbar, "複製", func() -> void: create_record(true))
	button_at(toolbar, "削除", delete_record)
	button_at(toolbar, "保存して戦闘テスト", func() -> void: launch_test(false))
	button_at(toolbar, "保存してエリア試遊", func() -> void: launch_test(true))
	button_at(toolbar, "書き出し", export_data)
	button_at(toolbar, "編集終了", func() -> void: guard_change(func() -> void: exit_requested.emit()))
	var tabs := HFlowContainer.new()
	add_child(tabs)
	var names := ["カード", "敵", "装備", "アフィックス", "エリア", "計算式", "ルール", "テスト設定"]
	var groups: Array = DefinitionRepository.GROUPS.duplicate()
	groups.append("test")
	for i: int in groups.size():
		var next_group: String = groups[i]
		button_at(tabs, names[i], func() -> void:
			group = next_group
			selected_id = "" if group == "test" else str(repository.records(group, draft)[0].id)
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
	if group == "test":
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
	refresh_list()
	clear_children(detail)
	if group == "test":
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
		"target": return ["self", "selected_enemy", "all_enemies", "player"]
		"category": return ["attack", "support", "buff"]
		"slot": return ["weapon", "armor", "accessory"]
		"stat": return DefinitionRepository.STATS
		"formula_id": return [""] + repository.indexed("formulas", draft).keys()
		"enemies": return repository.indexed("enemies", draft).keys()
		"affixes": return repository.indexed("affixes", draft).keys()
		"deck", "starter_deck": return repository.indexed("cards", draft).keys()
		"equipment", "loot_bases": return repository.indexed("items", draft).keys()
		"area": return repository.indexed("areas", draft).keys()
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
		elif value is Array:
			array_form(parent, value, key, path)
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
				number.step = 0.1 if key == "scaling" else 1.0
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
	if group == "test":
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
	if group == "test":
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
