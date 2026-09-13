class_name CardView
extends Button

func configure(card: Dictionary, reason: String = "", highlighted: bool = false, engine: BattleEngine = null) -> void:
	custom_minimum_size = Vector2(172, 194)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	text = "%s\nAP %d / MP %d\n\n%s" % [card.name, card.ap, card.mp, card.description]
	for effect: Dictionary in card.effects:
		var value: String = str(int(effect.value))
		if engine != null:
			var evaluated := engine.effect_value(effect, engine.player)
			value = str(evaluated.value) if evaluated.ok else "式エラー"
		text += "\n%s %s" % [UiText.name_for(effect.type), value]
	if not reason.is_empty():
		text += "\n" + reason
	tooltip_text = text
	disabled = not reason.is_empty()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("244851") if card.category == "support" else Color("493543")
	if highlighted:
		style.bg_color = Color("806331")
	style.border_color = Color("deb96c")
	style.set_border_width_all(2 if highlighted else 1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	add_theme_stylebox_override("normal", style)
	add_theme_font_size_override("font_size", 15)
	var image_path: String = card.get("image_path", "")
	if not image_path.is_empty() and ResourceLoader.exists(image_path):
		var resource: Resource = load(image_path)
		if resource is Texture2D:
			icon = resource
			expand_icon = true
			add_theme_constant_override("icon_max_width", 48)
