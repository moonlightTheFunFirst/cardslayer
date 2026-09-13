class_name GeneratorPanel
extends VBoxContainer

var editor: DefinitionEditor
var section: String = "generate"
var rarity: String = "rare"
var level: int = 1
var seed_value: int = 12345
var amount: int = 20
var filter_rarity: String = ""
var filter_slot: String = ""
var filter_base: String = ""
var body: VBoxContainer
var results: Array[Dictionary] = []
var last_config: Dictionary = {}
var summary: String = ""
var result_heading: Label

func message(text: String) -> void:
	var label := editor.label_at(body, text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func setup(owner_editor: DefinitionEditor) -> void:
	editor = owner_editor
	editor.label_at(self, "ランダム装備品ジェネレーター")
	editor.label_at(self, "戦利品と同じ生成処理を使用。生成品はメモリー内のプレビューのみ。")
	var tabs := HBoxContainer.new()
	add_child(tabs)
	for entry: Array in [["generate", "生成条件"], ["results", "生成結果"], ["rarity", "等級・確率・値範囲"]]:
		var key: String = entry[0]
		editor.button_at(tabs, entry[1], func() -> void: section = key; refresh(); scroll_to_top())
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	refresh()

func refresh() -> void:
	editor.clear_children(body)
	if section == "generate":
		generation_form()
	elif section == "results":
		results_view()
	else:
		policy_form()

func number(parent: Node, title: String, value: float, minimum: float, maximum: float, setter: Callable, step: float = 1) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := editor.label_at(row, title)
	caption.custom_minimum_size.x = 210
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	spin.value_changed.connect(setter)
	return spin

func choice(parent: Node, title: String, choices: Array, value: String, setter: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := editor.label_at(row, title)
	caption.custom_minimum_size.x = 210
	editor.choice_control(row, choices, value, setter)

func generation_form() -> void:
	number(body, "装備レベル", level, 1, 999, func(value: float) -> void: level = int(value))
	number(body, "シード", seed_value, 0, 2147483647, func(value: float) -> void: seed_value = int(value))
	number(body, "生成数", amount, 1, 200, func(value: float) -> void: amount = int(value))
	choice(body, "等級（未指定は重み抽選）", [""] + EquipmentGenerator.RARITIES, filter_rarity, func(value: String) -> void: filter_rarity = value)
	choice(body, "部位（未指定は全候補）", [""] + EquipmentGenerator.SLOTS, filter_slot, func(value: String) -> void: filter_slot = value)
	choice(body, "基底ID（未指定は全候補）", [""] + editor.repository.indexed("items", editor.draft).keys(), filter_base, func(value: String) -> void: filter_base = value)
	message("基礎値 = Lv.1の補正 + 1レベルごとの成長 × (装備レベル − 1)、小数点以下切り捨て。")
	message("基底値・成長・部位は「装備」タブで編集します。確率設定は保存すると戦利品にも反映されます。")
	var actions := HBoxContainer.new()
	body.add_child(actions)
	editor.button_at(actions, "装備を生成", func() -> void: generate_items(false))
	editor.button_at(actions, "新シードで生成", func() -> void: generate_items(true))
	message("生成すると「生成結果」画面に切り替わります。保存ボタンを押す必要はありません。")

func results_view() -> void:
	result_heading = editor.label_at(body, "%d個の装備を生成しました" % results.size() if not results.is_empty() else "生成結果はまだありません")
	result_heading.add_theme_font_size_override("font_size", 24)
	var actions := HFlowContainer.new()
	body.add_child(actions)
	editor.button_at(actions, "条件を変更", func() -> void: section = "generate"; refresh(); scroll_to_top())
	editor.button_at(actions, "同じ条件で再生成", func() -> void: generate_items(false))
	editor.button_at(actions, "新シードで再生成", func() -> void: generate_items(true))
	editor.button_at(actions, "結果をクリア", func() -> void: results.clear(); summary = ""; refresh(); scroll_to_top())
	if not summary.is_empty():
		message(summary)
	for item: Dictionary in results:
		var panel := PanelContainer.new()
		body.add_child(panel)
		var text := Label.new()
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.text = item.display_text
		text.add_theme_color_override("font_color", EquipmentGenerator.COLORS[item.rarity])
		panel.add_child(text)

func scroll_to_top() -> void:
	editor.saved_scroll = 0
	editor.detail_scroll.set_deferred("scroll_vertical", 0)

func show_generation_error(reason: String) -> void:
	editor.status.text = "生成できませんでした。入力条件を確認してください。"
	var dialog := AcceptDialog.new()
	dialog.title = "装備を生成できませんでした"
	dialog.dialog_text = reason
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(640, 240))

func generate_items(new_seed: bool) -> bool:
	var issues := editor.repository.validate(editor.draft)
	if not issues.is_empty():
		show_generation_error("\n".join(issues))
		return false
	if new_seed:
		seed_value = int(randi() % 2147483647)
	var engine := EquipmentGenerator.new(editor.draft)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var generated: Array[Dictionary] = []
	var totals: Dictionary = {}
	for i: int in amount:
		var response := engine.generate(rng, level, filter_rarity, filter_base, filter_slot)
		if not response.ok:
			show_generation_error(response.error)
			return false
		var item: Dictionary = response.item
		var base: Dictionary = engine.bases[item.base_id]
		var text := "%s　[%s]\nLv.%d　%s / 基底: %s\n基礎値: %s\nアフィックス %d個" % [item.name, UiText.name_for(item.rarity), item.item_level, UiText.name_for(base.slot), base.name, UiText.bonuses(item.base_bonuses), item.affixes.size()]
		for affix: Dictionary in item.affixes:
			text += "\n  %s：%s +%d%s" % [engine.affixes[affix.id].name, UiText.name_for(affix.stat), affix.value, " ★特別ロール" if affix.exceptional else ""]
		item["display_text"] = text
		generated.append(item)
		totals[item.rarity] = int(totals.get(item.rarity, 0)) + 1
	results = generated
	last_config = {"level": level, "seed": seed_value, "amount": amount, "rarity": filter_rarity, "slot": filter_slot, "base": filter_base}
	var parts: Array[String] = []
	for id: String in EquipmentGenerator.RARITIES:
		parts.append("%s %d個" % [UiText.name_for(id), totals.get(id, 0)])
	summary = "前回生成: seed %d / Lv.%d / %d個 / 編集内容 %s\n%s" % [seed_value, level, amount, JSON.stringify(editor.draft).sha256_text().substr(0, 8), "、".join(parts)]
	editor.status.text = "%d個生成しました。生成品は保存・所持品追加されません。" % results.size()
	section = "results"
	refresh()
	scroll_to_top()
	return true

func policy_form() -> void:
	var definitions := editor.repository.indexed("rules", editor.draft)
	var combat: Dictionary = definitions.combat
	editor.label_at(body, "通常戦利品と等級未指定の生成に使う等級重み（0で抽選対象外）")
	for id: String in EquipmentGenerator.RARITIES:
		number(body, UiText.name_for(id), combat.rarity_weights[id], 0, 1000000, func(value: float) -> void: combat.rarity_weights[id] = int(value); editor.changed())
	choice(body, "編集する等級", EquipmentGenerator.RARITIES, rarity, func(value: String) -> void: rarity = value; refresh())
	var policy: Dictionary = {}
	for entry: Dictionary in definitions.loot.rarities:
		if entry.id == rarity:
			policy = entry
	editor.label_at(body, "アフィックス数の重み（合計で正規化。0でその個数を無効化）")
	var probability := editor.label_at(body, "")
	var update := func() -> void:
		var total: float = 0
		for value: Variant in policy.count_weights.values():
			total += float(value)
		var parts: Array[String] = []
		for key: String in policy.count_weights:
			parts.append("%s個: %.3f%%" % [key, 100 * float(policy.count_weights[key]) / total if total > 0 else 0])
		probability.text = " / ".join(parts)
	for count: int in EquipmentGenerator.COUNTS[rarity]:
		var key := str(count)
		number(body, "%d個の重み" % count, policy.count_weights.get(key, 0), 0, 1000000, func(value: float) -> void: policy.count_weights[key] = value; editor.changed(); update.call(), 0.01)
	update.call()
	message("アフィックスを重複なしで重み抽選します。候補重み0は出現しません。")
	message("特別ロール確率は通常値範囲の代わりに特別値範囲を使用する確率（%）です。")
	var all_affixes := editor.repository.indexed("affixes", editor.draft)
	for id: String in policy.affix_weights.keys():
		if not all_affixes.has(id):
			editor.label_at(body, "参照切れ: " + id)
		else:
			editor.label_at(body, all_affixes[id].name + " / " + UiText.name_for(all_affixes[id].stat))
		number(body, "候補の重み: " + id, policy.affix_weights[id], 0, 1000000, func(value: float) -> void: policy.affix_weights[id] = value; editor.changed(), 0.01)
		if policy.value_ranges.has(id):
			var limits: Dictionary = policy.value_ranges[id]
			for field: String in ["min", "max", "exception_chance", "exception_min", "exception_max"]:
				number(body, UiText.name_for(field), limits[field], 0, 100 if field == "exception_chance" else 100000, func(value: float) -> void: limits[field] = value; editor.changed(), 0.01 if field == "exception_chance" else 1)
		editor.button_at(body, id + " の候補設定を削除", func() -> void: policy.affix_weights.erase(id); policy.value_ranges.erase(id); editor.changed(); refresh())
	var missing: Array = []
	for id: String in all_affixes:
		if not policy.affix_weights.has(id):
			missing.append(id)
	if not missing.is_empty():
		var selected: Array = [missing[0]]
		choice(body, "追加する候補", missing, str(selected[0]), func(value: String) -> void: selected[0] = value)
		editor.button_at(body, "候補を追加（初期重み0）", func() -> void:
			var id: String = selected[0]
			policy.affix_weights[id] = 0
			policy.value_ranges[id] = {"min": all_affixes[id].min, "max": all_affixes[id].max, "exception_chance": 0, "exception_min": all_affixes[id].min, "exception_max": all_affixes[id].max}
			editor.changed(); refresh())
