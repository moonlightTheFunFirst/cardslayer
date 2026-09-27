class_name BattleCard
extends Control

## One card in the battle hand, drawn from the pixel frame at 2x.
## Hovering enlarges it to 1.5x so the pixels land on a 3x grid.

const SIZE := Vector2(160, 224)
const PIXEL: int = 2

var card: Dictionary = {}
var playable: bool = true
var glow: bool = false
var cost_label: Label
var mp_label: Label
var desc: RichTextLabel
var motion: Tween

static func art_texture(card_data: Dictionary) -> Texture2D:
	var paths: Array[String] = [str(card_data.get("image_path", "")), "res://assets/cards/art/%s.png" % card_data.id, "res://assets/cards/art/default_%s.png" % card_data.category]
	for path: String in paths:
		if not path.is_empty() and ResourceLoader.exists(path):
			var resource: Resource = load(path)
			if resource is Texture2D:
				return resource
	return null

static func pixel_rect(texture: Texture2D, at: Vector2, scale_by: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.position = at
	if texture != null:
		rect.size = texture.get_size() * scale_by
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

static func text_label(value: String, font_size: int, color: Color, outline: int = 0) -> Label:
	var label := Label.new()
	label.text = value
	var settings := LabelSettings.new()
	settings.font_size = font_size
	settings.font_color = color
	if outline > 0:
		settings.outline_size = outline
		settings.outline_color = Color("140c18")
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return label

func setup(card_data: Dictionary) -> void:
	card = card_data
	size = SIZE
	pivot_offset = SIZE / 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var category: String = card.get("category", "attack")
	var frame_path := "res://assets/cards/frame_%s.png" % category
	add_child(pixel_rect(load(frame_path) if ResourceLoader.exists(frame_path) else null, Vector2.ZERO, PIXEL))
	var art := pixel_rect(art_texture(card), Vector2(16, 36), PIXEL)
	art.size = Vector2(128, 88)
	add_child(art)
	cost_label = text_label(str(int(card.ap)), 22, Color.WHITE, 6)
	cost_label.position = Vector2(0, 0)
	cost_label.size = Vector2(36, 36)
	add_child(cost_label)
	var title := text_label(card.name, 15, Color("2a1a14"))
	title.position = Vector2(32, 8)
	title.size = Vector2(122, 22)
	title.clip_text = true
	add_child(title)
	var kind := text_label(UiText.name_for(category), 11, Color("f4e8d0"))
	kind.position = Vector2(52, 120)
	kind.size = Vector2(56, 18)
	add_child(kind)
	mp_label = text_label("MP%d" % int(card.mp), 12, Color("9ad0ff"), 4)
	mp_label.position = Vector2(0, 34)
	mp_label.size = Vector2(38, 16)
	mp_label.visible = int(card.mp) > 0
	add_child(mp_label)
	desc = RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = false
	desc.scroll_active = false
	desc.position = Vector2(14, 142)
	desc.size = Vector2(132, 70)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	desc.add_theme_font_size_override("normal_font_size", 13)
	desc.add_theme_color_override("default_color", Color("ece0d0"))
	desc.add_theme_constant_override("line_separation", -2)
	add_child(desc)

## Reflect current AP/MP and buffs. reason is BattleEngine.can_play's message.
func refresh(engine: BattleEngine, reason: String, player_turn: bool) -> void:
	playable = reason.is_empty()
	glow = playable and player_turn
	cost_label.label_settings.font_color = Color.WHITE if engine.ap >= int(card.ap) else Color("ff6a5a")
	mp_label.label_settings.font_color = Color("9ad0ff") if int(engine.player.mp) >= int(card.mp) else Color("ff6a5a")
	var lines: Array[String] = []
	for effect: Dictionary in card.effects:
		var evaluated := engine.effect_value(effect, engine.player)
		var value: String = str(evaluated.value) if evaluated.ok else "式エラー"
		var color := "ffd070"
		if evaluated.ok and int(evaluated.value) > int(effect.value):
			color = "7aff8a"
		elif evaluated.ok and int(evaluated.value) < int(effect.value):
			color = "ff7a6a"
		var label := UiText.name_for(effect.type)
		if effect.type == "modify_stat":
			label = UiText.name_for(str(effect.get("stat", ""))) + "+"
		lines.append("%s [color=#%s]%s[/color]" % [label, color, value])
	desc.text = "[center]%s\n%s[/center]" % [card.description, "  ".join(lines)]
	modulate = Color.WHITE if playable else Color(0.62, 0.6, 0.66)
	queue_redraw()

func _draw() -> void:
	if glow:
		draw_rect(Rect2(Vector2(-3, -3), SIZE + Vector2(6, 6)), Color(0.45, 0.95, 1.0, 0.75), false, 3.0)

func move_to(target_position: Vector2, target_rotation: float, target_scale: float, duration: float = 0.14) -> void:
	if motion != null and motion.is_valid():
		motion.kill()
	motion = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "position", target_position, duration)
	motion.tween_property(self, "rotation", target_rotation, duration)
	motion.tween_property(self, "scale", Vector2.ONE * target_scale, duration)
