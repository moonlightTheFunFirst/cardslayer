class_name PixelUi
extends RefCounted

## Shared pixel-art UI pieces for the real game screens (battle, home base, shop).

static func texture(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null

static func style(path: String, margin: float = 8.0) -> StyleBox:
	if not ResourceLoader.exists(path):
		return StyleBoxFlat.new()
	var box := StyleBoxTexture.new()
	box.texture = load(path)
	box.texture_margin_left = margin
	box.texture_margin_right = margin
	box.texture_margin_top = margin
	box.texture_margin_bottom = margin
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box

## accent=true uses the orange "end turn" style for the main action.
static func button(text: String, action: Callable, parent: Node, sound: Sound, accent: bool = false, font_size: int = -1) -> Button:
	var result := Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.add_theme_font_size_override("font_size", font_size if font_size > 0 else (18 if accent else 14))
	result.add_theme_stylebox_override("normal", style("res://assets/ui/button_end.png" if accent else "res://assets/ui/button.png"))
	result.add_theme_stylebox_override("hover", style("res://assets/ui/button_end_hover.png" if accent else "res://assets/ui/button_hover.png"))
	result.add_theme_stylebox_override("pressed", style("res://assets/ui/button_end_hover.png" if accent else "res://assets/ui/button_hover.png"))
	result.add_theme_stylebox_override("disabled", style("res://assets/ui/button_end_disabled.png"))
	result.add_theme_color_override("font_color", Color("f4ead8"))
	result.add_theme_color_override("font_disabled_color", Color("8a8090"))
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.pressed.connect(func() -> void:
		if sound != null:
			sound.play("click", 0.0)
		action.call())
	parent.add_child(result)
	return result

static func panel(parent: Node, rect: Rect2 = Rect2()) -> PanelContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", style("res://assets/ui/panel.png"))
	if rect.size != Vector2.ZERO:
		box.position = rect.position
		box.size = rect.size
	parent.add_child(box)
	return box

## wrap only for labels whose container gives them a width (VBox rows);
## wrapped labels inside HBox/Grid cells collapse to one character per line.
static func label(text: String, font_size: int = 16, color: Color = Color("f4ead8"), outline: int = 0, align_left: bool = true, wrap: bool = false) -> Label:
	var result := BattleCard.text_label(text, font_size, color, outline)
	if align_left:
		result.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if wrap:
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result
