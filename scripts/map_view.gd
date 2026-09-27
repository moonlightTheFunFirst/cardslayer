class_name MapView
extends Control

## Real (pixel-art) area map: nodes laid out by depth on a parchment map, the
## hero's route, next reachable nodes, carried items usable outside battle,
## and the way home. The debug menu's form map (main.gd) uses the same data
## and the same HubActions item use.

signal node_selected(id: String)
signal home_requested
signal editor_requested
signal debug_requested

const SCREEN := Vector2(1280, 720)
const NODE_SIZE := Vector2(48, 48)
const BOSS_SIZE := Vector2(72, 72)
const INK := Color("4a3624")

var profile: Dictionary
var snapshot: Dictionary
var sound: Sound
var info: Dictionary = {}
var area: Dictionary = {}
var current: String = ""
var passed: Array = []
var item_rng: RandomNumberGenerator
var positions: Dictionary = {}
var node_buttons: Dictionary = {}
var item_buttons: Array[Button] = []
var paths: Control
var tip_panel: PanelContainer
var tip_label: Label
var toast: Label
var hp_label: Label
var belt: HBoxContainer

func setup(player_profile: Dictionary, definitions: Dictionary, audio: Sound, context: Dictionary) -> void:
	profile = player_profile
	snapshot = definitions
	sound = audio
	info = context
	item_rng = context.get("item_rng", RandomNumberGenerator.new())
	position = Vector2.ZERO
	size = SCREEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## area_id's map with the hero at current_id having visited visited_ids.
func show_area(area_id: String, current_id: String, visited_ids: Array) -> void:
	area = DefinitionRepository.new().indexed("areas", snapshot)[area_id]
	current = current_id
	passed = visited_ids.duplicate()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	node_buttons.clear()
	add_child(BattleCard.pixel_rect(PixelUi.texture("res://assets/backgrounds/map_parchment.png"), Vector2.ZERO, 4))
	layout_nodes()
	paths = Control.new()
	paths.size = SCREEN
	paths.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paths.draw.connect(draw_paths)
	add_child(paths)
	for node: Dictionary in area.nodes:
		build_node(node)
	build_top_bar()
	build_status()
	tip_panel = PixelUi.panel(self)
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.visible = false
	tip_label = PixelUi.label("", 15)
	tip_panel.add_child(tip_label)
	toast = BattleCard.text_label("", 20, Color("fff0c0"), 6)
	toast.position = Vector2(240, 600)
	toast.size = Vector2(800, 40)
	toast.modulate.a = 0.0
	add_child(toast)

# ------------------------------------------------------------------ layout

## Column = longest distance from the start node; rows spread evenly per column.
func layout_nodes() -> void:
	var depth: Dictionary = {area.start: 0}
	var order: Array = [area.start]
	var index := 0
	var nodes := nodes_by_id()
	while index < order.size():
		var id: String = order[index]
		index += 1
		for next: String in nodes[id].next:
			if int(depth.get(next, -1)) < int(depth[id]) + 1:
				depth[next] = int(depth[id]) + 1
				order.append(next)
	var columns: Dictionary = {}
	var deepest: int = 1
	for id: String in depth:
		deepest = maxi(deepest, int(depth[id]))
		if not columns.has(depth[id]):
			columns[depth[id]] = []
		columns[depth[id]].append(id)
	positions.clear()
	for column: int in columns:
		var ids: Array = columns[column]
		ids.sort()
		for row: int in ids.size():
			var x: float = 150.0 + (SCREEN.x - 300.0) * column / deepest
			var y: float = 390.0 + (row - (ids.size() - 1) / 2.0) * 170.0
			positions[ids[row]] = Vector2(x, y)

func nodes_by_id() -> Dictionary:
	var result: Dictionary = {}
	for node: Dictionary in area.nodes:
		result[node.id] = node
	return result

func reachable(id: String) -> bool:
	return id in nodes_by_id().get(current, {}).get("next", []) and id not in passed

func kind(node: Dictionary) -> String:
	if node.id == area.start:
		return "start"
	return "boss" if node.id == area.boss else "battle"

func build_node(node: Dictionary) -> void:
	var id: String = node.id
	var node_kind := kind(node)
	var icon_size := BOSS_SIZE if node_kind == "boss" else NODE_SIZE
	var button := TextureButton.new()
	button.texture_normal = PixelUi.texture("res://assets/map/node_%s.png" % node_kind)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.size = icon_size
	button.position = positions.get(id, Vector2.ZERO) - icon_size / 2
	button.pivot_offset = icon_size / 2
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not reachable(id)
	if id in passed and id != current:
		button.modulate = Color(0.6, 0.55, 0.5, 0.8)
	add_child(button)
	node_buttons[id] = button
	button.mouse_entered.connect(func() -> void: show_tip(node))
	button.mouse_exited.connect(func() -> void: tip_panel.visible = false)
	button.pressed.connect(func() -> void:
		if reachable(id):
			sound.play("card_play", 0.0)
			node_selected.emit(id))
	if reachable(id):
		var pulse := button.create_tween().set_loops()
		pulse.tween_property(button, "scale", Vector2.ONE * 1.15, 0.5).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(button, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	var caption := BattleCard.text_label("ボス" if node_kind == "boss" else ("出発" if node_kind == "start" else id.to_upper()), 14, INK)
	caption.size = Vector2(80, 20)
	caption.position = positions.get(id, Vector2.ZERO) + Vector2(-40, icon_size.y / 2 + 12)
	add_child(caption)

func draw_paths() -> void:
	var nodes := nodes_by_id()
	for node: Dictionary in area.nodes:
		for next: String in node.next:
			if not positions.has(node.id) or not positions.has(next):
				continue
			var from: Vector2 = positions[node.id]
			var to: Vector2 = positions[next]
			var walked: bool = node.id in passed and next in passed
			var open: bool = node.id == current and reachable(next)
			var color := Color("b03040") if walked else (Color("2a6a30") if open else INK)
			var steps: int = int(from.distance_to(to) / 14.0)
			for i: int in range(2, steps - 1):
				var point := from.lerp(to, float(i) / steps)
				var dot: float = 6.0 if walked or open else 4.0
				paths.draw_rect(Rect2(point - Vector2(dot, dot) / 2, Vector2(dot, dot)), color)
	if positions.has(current):
		var here: Vector2 = positions[current]
		var radius: float = (BOSS_SIZE.x if current == area.boss else NODE_SIZE.x) / 2 + 8
		for i: int in 16:
			var angle := TAU * i / 16.0
			paths.draw_rect(Rect2(here + Vector2(cos(angle), sin(angle)) * radius - Vector2(3, 3), Vector2(6, 6)), Color("b03040"))

func show_tip(node: Dictionary) -> void:
	var lines: Array[String] = []
	match kind(node):
		"start": lines.append("出発地点")
		"boss": lines.append("ボス")
		_: lines.append("戦闘 " + str(node.id).to_upper())
	var enemies := DefinitionRepository.new().indexed("enemies", snapshot)
	for id: String in node.enemies:
		var enemy: Dictionary = enemies.get(id, {})
		lines.append("・%s  HP %d" % [enemy.get("name", id), int(enemy.get("hp", 0))])
	if node.id in passed:
		lines.append("通過済み")
	elif reachable(node.id):
		lines.append("クリックで進む")
	else:
		lines.append("まだ進めません")
	tip_label.text = "\n".join(lines)
	tip_panel.reset_size()
	var at: Vector2 = positions.get(node.id, Vector2.ZERO) + Vector2(44, -30)
	if at.x + tip_panel.size.x > SCREEN.x - 10:
		at.x -= tip_panel.size.x + 88
	tip_panel.position = at
	tip_panel.visible = true

# ------------------------------------------------------------------ bars

func build_top_bar() -> void:
	var bar := PixelUi.panel(self, Rect2(Vector2.ZERO, Vector2(SCREEN.x, 44)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	var cleared: bool = area.id in profile.cleared
	var text := "%s — マップ   %s   %d G" % [area.name, "クリア済み" if cleared else "初クリアでボーナス 100G", profile.gold]
	if info.get("test", false):
		text = "● テストプレイ   " + text
	var title := PixelUi.label(text, 16, Color("f4ead8"), 4)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	belt = HBoxContainer.new()
	belt.add_theme_constant_override("separation", 2)
	row.add_child(belt)
	refresh_belt()
	if info.get("test", false):
		PixelUi.button("◀ 編集へ戻る (F1)", func() -> void: editor_requested.emit(), row, sound)
	elif info.get("dev", false):
		PixelUi.button("デバッグメニュー", func() -> void: debug_requested.emit(), row, sound)
		PixelUi.button("◀ エディタ (F1)", func() -> void: editor_requested.emit(), row, sound)
	PixelUi.button("本拠地へ帰還", func() -> void: home_requested.emit(), row, sound)

func build_status() -> void:
	var panel := PixelUi.panel(self, Rect2(20, 620, 460, 84))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var hero := BattleCard.pixel_rect(PixelUi.texture("res://assets/sprites/hero.png"), Vector2.ZERO, 1)
	hero.custom_minimum_size = Vector2(56, 72)
	row.add_child(hero)
	hp_label = PixelUi.label("", 17, Color("f4ead8"), 3)
	row.add_child(hp_label)
	update_status()

func update_status() -> void:
	var values := Progression.stats(profile, snapshot)
	hp_label.text = "英雄 Lv %d\nHP %d / %d   MP %d / %d\n戦闘間でHPを引き継ぎます" % [profile.level, profile.hp, values.max_hp, profile.mp, values.max_mp]

## Carried items; only those usable outside battle are enabled here.
func refresh_belt() -> void:
	for button: Button in item_buttons:
		button.queue_free()
	item_buttons.clear()
	for id: String in HubActions.carried(profile, snapshot):
		var item := HubActions.consumable(snapshot, id)
		var reason := HubActions.field_use_reason(profile, snapshot, id, item_rng)
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(40, 36)
		button.expand_icon = true
		button.icon = PixelUi.texture(ItemRunner.icon_path(item))
		button.add_theme_constant_override("icon_max_width", 32)
		button.add_theme_stylebox_override("normal", PixelUi.style("res://assets/ui/button.png"))
		button.add_theme_stylebox_override("hover", PixelUi.style("res://assets/ui/button_hover.png"))
		button.add_theme_stylebox_override("disabled", PixelUi.style("res://assets/ui/button_end_disabled.png"))
		button.disabled = not reason.is_empty()
		button.modulate = Color.WHITE if reason.is_empty() else Color(0.55, 0.55, 0.6)
		button.tooltip_text = "%s\n%s%s" % [item.name, item.description, "\n使用不可: " + reason if not reason.is_empty() else "\nクリックで使用"]
		button.pressed.connect(func() -> void: use_item(id))
		belt.add_child(button)
		item_buttons.append(button)

func use_item(id: String) -> void:
	var item := HubActions.consumable(snapshot, id)
	var result := HubActions.use_field_item(profile, snapshot, id, item_rng)
	if not result.ok:
		sound.play("denied", 0.0)
		notify(result.reason)
		return
	sound.play("item_use", 0.0)
	sound.play(str(item.get("sound", "item_use")))
	notify("%s を使用: %s" % [item.name, HubActions.item_summary(result.results)])
	update_status()
	refresh_belt()

func notify(message: String) -> void:
	toast.text = message
	toast.modulate.a = 1.0
	var tween := toast.create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(toast, "modulate:a", 0.0, 0.4)
