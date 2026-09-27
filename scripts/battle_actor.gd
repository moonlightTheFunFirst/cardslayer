class_name BattleActor
extends Control

## Hero or enemy on the battle stage: pixel sprite, HP bar, block, statuses and
## (for enemies) the next-action intent. Origin is the sprite's top-left.

const ICONS: Dictionary = {
	"damage": "attack", "block": "block", "heal": "heal", "restore_mp": "mp", "draw": "draw",
	"apply_poison": "poison", "modify_stat": "buff",
}

var index: int = -1
var display_name: String = ""
var body: Control
var sprite: TextureRect
var bar: HpBar
var bar_label: Label
var block_badge: Control
var block_label: Label
var status_row: HBoxContainer
var intent_row: HBoxContainer
var action_label: Label
var state: Dictionary = {}
var dead: bool = false
var targeted: bool = false
var idle: Tween

static func icon(name: String) -> Texture2D:
	var path := "res://assets/ui/icon_%s.png" % name
	return load(path) if ResourceLoader.exists(path) else null

func setup(texture: Texture2D, actor_index: int, actor_name: String, pixel_scale: int) -> void:
	index = actor_index
	display_name = actor_name
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sprite_size: Vector2 = texture.get_size() * pixel_scale if texture != null else Vector2(96, 96)
	size = sprite_size
	body = Control.new()
	body.size = sprite_size
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	sprite = BattleCard.pixel_rect(texture, Vector2.ZERO, pixel_scale)
	sprite.size = sprite_size
	sprite.pivot_offset = Vector2(sprite_size.x / 2, sprite_size.y)
	body.add_child(sprite)
	var bar_width: float = clampf(sprite_size.x, 130, 190)
	bar = HpBar.new()
	bar.position = Vector2((sprite_size.x - bar_width) / 2, sprite_size.y + 10)
	bar.size = Vector2(bar_width, 18)
	add_child(bar)
	bar_label = BattleCard.text_label("", 14, Color.WHITE, 4)
	bar_label.size = bar.size
	bar.add_child(bar_label)
	block_badge = Control.new()
	block_badge.position = bar.position + Vector2(-26, -7)
	block_badge.size = Vector2(32, 32)
	block_badge.add_child(BattleCard.pixel_rect(icon("block"), Vector2.ZERO, 2))
	block_label = BattleCard.text_label("", 15, Color.WHITE, 4)
	block_label.size = Vector2(32, 30)
	block_badge.add_child(block_label)
	add_child(block_badge)
	var name_label := BattleCard.text_label(actor_name, 14, Color("e8dcc8"), 4)
	name_label.position = bar.position + Vector2(0, 18)
	name_label.size = Vector2(bar_width, 22)
	add_child(name_label)
	status_row = HBoxContainer.new()
	status_row.position = bar.position + Vector2(0, 40)
	status_row.add_theme_constant_override("separation", 4)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_row)
	intent_row = HBoxContainer.new()
	intent_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intent_row.add_theme_constant_override("separation", 2)
	add_child(intent_row)
	action_label = BattleCard.text_label("", 18, Color("ffe8b0"), 5)
	action_label.size = Vector2(sprite_size.x + 120, 28)
	action_label.position = Vector2(-60, -76)
	action_label.modulate.a = 0.0
	add_child(action_label)
	idle = create_tween().set_loops()
	idle.tween_interval(randf() * 0.6)
	idle.tween_property(sprite, "scale", Vector2(1.0, 1.035), 0.9).set_trans(Tween.TRANS_SINE)
	idle.tween_property(sprite, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)

func _draw() -> void:
	if dead:
		return
	var feet := Vector2(size.x / 2, size.y)
	for i: int in 3:
		var half: float = size.x * (0.42 - i * 0.1)
		draw_rect(Rect2(feet.x - half, feet.y - 6 + i * 2, half * 2, 12 - i * 4), Color(0, 0, 0, 0.18))
	if targeted:
		# Pixel-style corner brackets around the targeted actor.
		var box := Rect2(Vector2(-12, -12), size + Vector2(24, 24))
		var arm: float = 24.0
		var thick: float = 6.0
		for corner: int in 4:
			var flip := Vector2(1 if corner % 2 == 0 else -1, 1 if corner < 2 else -1)
			var at := Vector2(box.position.x if flip.x > 0 else box.end.x, box.position.y if flip.y > 0 else box.end.y)
			for pass_index: int in 2:
				var grow: float = 3.0 if pass_index == 0 else 0.0
				var color := Color("140c18") if pass_index == 0 else Color("ffd84a")
				var horizontal := Rect2(at - Vector2(grow, grow), Vector2(arm, thick) + Vector2(grow, grow) * 2)
				var vertical := Rect2(at - Vector2(grow, grow), Vector2(thick, arm) + Vector2(grow, grow) * 2)
				if flip.x < 0:
					horizontal.position.x -= arm - thick
				if flip.y < 0:
					vertical.position.y -= arm - thick
				draw_rect(horizontal, color)
				draw_rect(vertical, color)

func set_targeted(value: bool) -> void:
	if targeted != value:
		targeted = value
		queue_redraw()

func hit_rect() -> Rect2:
	return get_global_rect().grow(10)

func apply_state(values: Dictionary) -> void:
	state = values.duplicate(true)
	bar.max_hp = maxi(1, int(values.max_hp))
	bar.block = int(values.block)
	bar.set_hp(int(values.hp))
	bar_label.text = "%d / %d" % [int(values.hp), int(values.max_hp)]
	block_badge.visible = int(values.block) > 0
	block_label.text = str(values.block)
	for child: Node in status_row.get_children():
		child.queue_free()
	if int(values.poison) > 0:
		status_row.add_child(status_chip("poison", str(values.poison), "毒: ターン開始時に%dダメージ" % int(values.poison)))
	if int(values.get("reduction", 0)) > 0:
		status_row.add_child(status_chip("block", "軽減%d" % int(values.reduction), "被ダメージ -%d（戦闘中）" % int(values.reduction)))
	var buffs: Dictionary = values.get("buffs", {})
	for stat: String in buffs:
		if int(buffs[stat]) != 0:
			status_row.add_child(status_chip("buff", "%s%+d" % [UiText.name_for(stat), int(buffs[stat])], "%s %+d（戦闘中）" % [UiText.name_for(stat), int(buffs[stat])]))
	if int(values.hp) <= 0 and not dead:
		die()

func status_chip(icon_name: String, value: String, tip: String) -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 0)
	chip.tooltip_text = tip
	var picture := BattleCard.pixel_rect(icon(icon_name), Vector2.ZERO, 2)
	picture.custom_minimum_size = Vector2(32, 32)
	chip.add_child(picture)
	var label := BattleCard.text_label(value, 14, Color.WHITE, 4)
	chip.add_child(label)
	return chip

func set_intent(parts: Array, tip: String) -> void:
	for child: Node in intent_row.get_children():
		child.queue_free()
	tooltip_text = display_name + ("\n" + tip if not tip.is_empty() else "")
	if dead:
		return
	var width: float = 0
	for item: Dictionary in parts:
		var rect := BattleCard.pixel_rect(icon(ICONS.get(item.type, "unknown")), Vector2.ZERO, 2)
		rect.custom_minimum_size = Vector2(32, 32)
		intent_row.add_child(rect)
		width += 34
		if not str(item.value).is_empty():
			var label := BattleCard.text_label(str(item.value), 22, Color("ffd8c0") if item.type == "damage" else Color.WHITE, 5)
			intent_row.add_child(label)
			width += 12 * str(item.value).length() + 8
	intent_row.position = Vector2((size.x - width) / 2, -44)

func announce(text: String) -> void:
	action_label.text = text
	var tween := create_tween()
	tween.tween_property(action_label, "modulate:a", 1.0, 0.1)
	tween.tween_interval(0.6)
	tween.tween_property(action_label, "modulate:a", 0.0, 0.25)

func lunge(direction: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_QUAD)
	tween.tween_property(body, "position:x", 36.0 * direction, 0.09).set_ease(Tween.EASE_OUT)
	tween.tween_property(body, "position:x", 0.0, 0.16).set_ease(Tween.EASE_IN_OUT)

func hurt(strength: float = 1.0) -> void:
	sprite.modulate = Color(2.2, 1.2, 1.2)
	var tween := create_tween()
	for i: int in 4:
		tween.tween_property(body, "position:x", (8.0 if i % 2 == 0 else -8.0) * strength, 0.035)
	tween.tween_property(body, "position:x", 0.0, 0.035)
	var flash := create_tween()
	flash.tween_property(sprite, "modulate", Color.WHITE, 0.25)

func pulse(color: Color) -> void:
	sprite.modulate = color
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.35)

func die() -> void:
	dead = true
	intent_row.visible = false
	if idle != null:
		idle.kill()
	queue_redraw()
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "modulate", Color(1.8, 0.4, 0.4, 0.0), 0.6)
	tween.tween_property(body, "position:y", 18.0, 0.6)
	tween.tween_property(bar, "modulate:a", 0.25, 0.6)

class HpBar extends Control:
	var max_hp: int = 1
	var block: int = 0
	var shown: float = 0.0
	var trail: float = 0.0
	var tween: Tween

	func set_hp(value: int) -> void:
		if tween != null and tween.is_valid():
			tween.kill()
		trail = maxf(trail, shown)
		shown = value
		tween = create_tween()
		tween.tween_interval(0.25)
		tween.tween_method(func(v: float) -> void:
			trail = v
			queue_redraw(), trail, float(value), 0.35)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("140c18"))
		var inner := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		draw_rect(inner, Color("3a1a24"))
		var width_for := func(value: float) -> float: return floorf(inner.size.x * clampf(value / max_hp, 0, 1))
		draw_rect(Rect2(inner.position, Vector2(width_for.call(trail), inner.size.y)), Color("f0d890"))
		var fill := Color("4a8ae0") if block > 0 else Color("d0384a")
		var width: float = width_for.call(shown)
		draw_rect(Rect2(inner.position, Vector2(width, inner.size.y)), fill)
		draw_rect(Rect2(inner.position, Vector2(width, 3)), fill.lightened(0.35))
		draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 3), Vector2(width, 3)), fill.darkened(0.3))
