class_name HubView
extends Control

## Real (pixel-art) home-base screens: home, status, card list, deck, equipment
## and shop. All game changes go through HubActions / Shop, the same code the
## debug menu in main.gd uses, then profile_changed asks main.gd to save.

signal navigate(page: String)
signal depart_requested
signal editor_requested
signal debug_requested
signal title_requested
signal profile_changed

const SCREEN := Vector2(1280, 720)
const PAGES: Array[String] = ["hub", "status", "cards", "deck", "equipment", "items", "shop"]
const TITLES: Dictionary = {"hub": "本拠地", "status": "主人公の状態", "cards": "カード一覧", "deck": "デッキ編集", "equipment": "装備", "items": "持ち物", "shop": "ショップ"}
const STAT_ORDER: Array[String] = ["max_hp", "max_mp", "strength", "wisdom", "agility", "luck"]

var profile: Dictionary
var snapshot: Dictionary
var sound: Sound
var info: Dictionary = {}
var page: String = "hub"
var background: TextureRect
var content: Control
var toast: Label
var scroll: ScrollContainer
var saved_scroll: int = 0
var mute_button: Button

func setup(player_profile: Dictionary, definitions: Dictionary, audio: Sound, context: Dictionary) -> void:
	profile = player_profile
	snapshot = definitions
	sound = audio
	info = context
	position = Vector2.ZERO
	size = SCREEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background = BattleCard.pixel_rect(null, Vector2.ZERO, 4)
	add_child(background)
	content = Control.new()
	content.size = SCREEN
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	toast = BattleCard.text_label("", 20, Color("ffe8b0"), 6)
	toast.position = Vector2(240, 650)
	toast.size = Vector2(800, 40)
	toast.modulate.a = 0.0
	add_child(toast)

func show_page(next: String) -> void:
	if next != page:
		saved_scroll = 0
	page = next
	refresh()

## Rebuild the current page, keeping the list scroll position.
func refresh() -> void:
	if scroll != null and is_instance_valid(scroll):
		saved_scroll = scroll.scroll_vertical
	scroll = null
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var background_id := "shop" if page == "shop" else "hub_" + str(profile.get("hub_background", "camp"))
	background.texture = PixelUi.texture("res://assets/backgrounds/%s.png" % background_id)
	background.size = SCREEN
	build_top_bar()
	match page:
		"hub": build_home()
		"status": build_status()
		"cards": build_cards(false)
		"deck": build_cards(true)
		"equipment": build_equipment()
		"items": build_items()
		"shop": build_shop()
	if scroll != null:
		scroll.set_deferred("scroll_vertical", saved_scroll)

func changed(message: String = "") -> void:
	profile_changed.emit()
	refresh()
	if not message.is_empty():
		notify(message)

func notify(message: String) -> void:
	toast.text = message
	toast.modulate.a = 1.0
	var tween := toast.create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(toast, "modulate:a", 0.0, 0.4)

# ------------------------------------------------------------------ common

func build_top_bar() -> void:
	var bar := PixelUi.panel(content, Rect2(Vector2.ZERO, Vector2(SCREEN.x, 44)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	var where: String = TITLES[page]
	if page == "hub":
		where += " — " + HubActions.background_name(str(profile.get("hub_background", "")))
	var text := "%s    Lv %d   EXP %d/%d   %d G" % [where, profile.level, profile.xp, HubActions.xp_needed(profile), profile.gold]
	if info.get("test", false):
		text = "● テストプレイ   " + text
	var title := PixelUi.label(text, 16, Color("f4ead8"), 4)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	if info.get("test", false):
		PixelUi.button("◀ 編集へ戻る (F1)", func() -> void: editor_requested.emit(), row, sound)
	elif info.get("dev", false):
		PixelUi.button("デバッグメニュー", func() -> void: debug_requested.emit(), row, sound)
		PixelUi.button("◀ エディタ (F1)", func() -> void: editor_requested.emit(), row, sound)
	mute_button = PixelUi.button("BGM/SE: OFF" if sound.muted else "BGM/SE: ON", func() -> void:
		mute_button.text = "BGM/SE: OFF" if sound.toggle_mute() else "BGM/SE: ON", row, sound)
	if page == "hub" and not info.get("test", false):
		PixelUi.button("タイトルへ", func() -> void: title_requested.emit(), row, sound)

## Dark framed page with a title row and a back button; returns the body container.
func sheet(rect: Rect2, back_text: String = "◀ 本拠地へ戻る") -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.06, 0.45)
	shade.position = Vector2(0, 44)
	shade.size = SCREEN - Vector2(0, 44)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if page != "shop":
		content.add_child(shade)
	var frame := PixelUi.panel(content, rect)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	frame.add_child(body)
	var head := HBoxContainer.new()
	body.add_child(head)
	var title := PixelUi.label(TITLES[page], 24, Color("ffe8b0"), 5)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	PixelUi.button(back_text, func() -> void: navigate.emit("hub"), head, sound)
	return body

func scroll_body(parent: Node) -> ScrollContainer:
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll

func hero_sprite(at: Vector2, pixel_scale: int) -> TextureRect:
	var hero := BattleCard.pixel_rect(PixelUi.texture("res://assets/sprites/hero.png"), at, pixel_scale)
	hero.pivot_offset = Vector2(hero.size.x / 2, hero.size.y)
	return hero

func breathe(node: Control) -> void:
	var idle := node.create_tween().set_loops()
	idle.tween_property(node, "scale", Vector2(1.0, 1.03), 0.9).set_trans(Tween.TRANS_SINE)
	idle.tween_property(node, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)

# ------------------------------------------------------------------ pages

func build_home() -> void:
	var hero := hero_sprite(Vector2(190, 322), 4)
	content.add_child(hero)
	breathe(hero)
	var values := Progression.stats(profile, snapshot)
	var summary := PixelUi.panel(content, Rect2(24, 612, 520, 92))
	summary.add_child(PixelUi.label("英雄  Lv %d   HP %d / %d   MP %d / %d\n力 %d  知恵 %d  敏捷 %d  運 %d   デッキ %d枚  装備 %d/%d" % [
		profile.level, profile.hp, values.max_hp, profile.mp, values.max_mp, values.strength, values.wisdom, values.agility, values.luck,
		profile.deck.size(), profile.equipped.size(), EquipmentGenerator.SLOTS.size()], 16, Color("f4ead8"), 3))
	var menu := PixelUi.panel(content, Rect2(900, 70, 340, 560))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	menu.add_child(list)
	list.add_child(PixelUi.label("メニュー", 20, Color("ffe8b0"), 4))
	var entries: Array = [
		["出撃", func() -> void: depart_requested.emit(), true],
		["デッキ編集", func() -> void: navigate.emit("deck"), false],
		["装備", func() -> void: navigate.emit("equipment"), false],
		["カード一覧", func() -> void: navigate.emit("cards"), false],
		["主人公の状態", func() -> void: navigate.emit("status"), false],
		["持ち物", func() -> void: navigate.emit("items"), false],
		["ショップ", func() -> void: navigate.emit("shop"), false],
		["背景: %s ▶" % HubActions.background_name(str(profile.hub_background)), func() -> void:
			HubActions.next_background(profile)
			changed("背景を「%s」に切り替えました" % HubActions.background_name(str(profile.hub_background))), false],
	]
	for entry: Array in entries:
		var item := PixelUi.button(entry[0], entry[1], list, sound, entry[2], 20)
		item.custom_minimum_size = Vector2(300, 58 if entry[2] else 52)

func build_status() -> void:
	var body := sheet(Rect2(60, 64, 1160, 630))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	columns.add_child(left)
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(300, 290)
	left.add_child(portrait)
	var hero := hero_sprite(Vector2(38, 0), 4)
	portrait.add_child(hero)
	left.add_child(PixelUi.label("英雄  レベル %d" % profile.level, 22, Color("ffe8b0"), 4))
	var bar := ProgressBar.new()
	bar.max_value = HubActions.xp_needed(profile)
	bar.value = profile.xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(280, 16)
	left.add_child(bar)
	left.add_child(PixelUi.label("EXP %d / %d   所持金 %d G" % [profile.xp, HubActions.xp_needed(profile), profile.gold]))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	right.add_child(grid)
	var effective := Progression.stats(profile, snapshot)
	for text: String in ["能力", "基礎", "装備込み"]:
		grid.add_child(PixelUi.label(text, 16, Color("c8b8e8")))
	for stat: String in STAT_ORDER:
		grid.add_child(PixelUi.label(UiText.name_for(stat), 18))
		grid.add_child(PixelUi.label(str(profile.base[stat]), 18))
		var bonus: int = int(effective[stat]) - int(profile.base[stat])
		grid.add_child(PixelUi.label("%d%s" % [effective[stat], "  (+%d)" % bonus if bonus > 0 else ""], 18, Color("9affb0") if bonus > 0 else Color("f4ead8")))
	right.add_child(PixelUi.label("装備中", 18, Color("c8b8e8")))
	for slot: String in EquipmentGenerator.SLOTS:
		var item := HubActions.equipped_item(profile, slot)
		var line := PixelUi.label("%s: %s" % [UiText.name_for(slot), HubActions.item_title(item, snapshot) if not item.is_empty() else "なし"], 15)
		if not item.is_empty():
			line.label_settings.font_color = EquipmentGenerator.COLORS[item.rarity]
		right.add_child(line)
	var lines := HubActions.status_lines(profile, snapshot)
	right.add_child(PixelUi.label(lines[lines.size() - 1], 15, Color("f4ead8"), 0, true, true))

func build_cards(editing: bool) -> void:
	var body := sheet(Rect2(40, 56, 1200, 650))
	var message := "デッキ %d / %d枚（%d枚以上・同じカードは%d枚まで）" % [profile.deck.size(), HubActions.DECK_MAX, HubActions.DECK_MIN, HubActions.COPIES_MAX]
	if not editing:
		message = "全%d種類。表示の数値は現在の能力で計算しています。" % DefinitionRepository.new().records("cards", snapshot).size()
	body.add_child(PixelUi.label(message, 16, Color("f4ead8")))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	scroll_body(body).add_child(grid)
	var stats := Progression.stats(profile, snapshot)
	var formulas := DefinitionRepository.new().indexed("formulas", snapshot)
	for card_data: Dictionary in DefinitionRepository.new().records("cards", snapshot):
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		grid.add_child(cell)
		var card := BattleCard.new()
		cell.add_child(card)
		card.setup(card_data)
		card.preview(stats, formulas)
		var id: String = card_data.id
		var count: int = profile.deck.count(id)
		if not editing:
			cell.add_child(PixelUi.label("デッキ %d枚" % count, 15, Color("f4ead8"), 3, false))
			continue
		var controls := HBoxContainer.new()
		controls.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(controls)
		var remove := PixelUi.button("−", func() -> void:
			if HubActions.remove_card(profile, id):
				changed(), controls, sound, false, 20)
		remove.custom_minimum_size = Vector2(44, 36)
		remove.disabled = not HubActions.remove_card_reason(profile, id).is_empty()
		remove.tooltip_text = HubActions.remove_card_reason(profile, id)
		var amount := PixelUi.label("%d枚" % count, 18, Color("ffe8b0") if count > 0 else Color("8a8090"), 3, false)
		amount.custom_minimum_size.x = 52
		controls.add_child(amount)
		var add := PixelUi.button("＋", func() -> void:
			if HubActions.add_card(profile, id):
				changed(), controls, sound, false, 20)
		add.custom_minimum_size = Vector2(44, 36)
		add.disabled = not HubActions.add_card_reason(profile, id).is_empty()
		add.tooltip_text = HubActions.add_card_reason(profile, id)

func item_block(parent: Node, item: Dictionary) -> VBoxContainer:
	var frame := PixelUi.panel(parent)
	var box := VBoxContainer.new()
	frame.add_child(box)
	var title := PixelUi.label(HubActions.item_title(item, snapshot), 17, EquipmentGenerator.COLORS[item.rarity], 3, true, true)
	box.add_child(title)
	box.add_child(PixelUi.label(HubActions.item_details(item, snapshot), 14, Color("f4ead8"), 0, true, true))
	var after := HubActions.preview_equip(profile, item, snapshot)
	box.add_child(PixelUi.label("装備後: %s\n%s" % [HubActions.stats_text(after), HubActions.requirement_text(item, snapshot)], 13, Color("c8c0d8"), 0, true, true))
	return box

func build_equipment() -> void:
	var body := sheet(Rect2(40, 56, 1200, 650))
	body.add_child(PixelUi.label("現在: " + HubActions.stats_text(Progression.stats(profile, snapshot)), 16))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	body.add_child(columns)
	var slots := VBoxContainer.new()
	slots.custom_minimum_size.x = 440
	slots.add_theme_constant_override("separation", 6)
	columns.add_child(slots)
	slots.add_child(PixelUi.label("装備枠", 18, Color("c8b8e8")))
	for slot: String in EquipmentGenerator.SLOTS:
		var row := HBoxContainer.new()
		slots.add_child(row)
		var name_label := PixelUi.label(UiText.name_for(slot), 14, Color("c8c0d8"))
		name_label.custom_minimum_size.x = 120
		row.add_child(name_label)
		var item := HubActions.equipped_item(profile, slot)
		var worn := PixelUi.label(HubActions.item_title(item, snapshot) if not item.is_empty() else "なし", 14, EquipmentGenerator.COLORS[item.rarity] if not item.is_empty() else Color("8a8090"))
		worn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(worn)
		var take_off := PixelUi.button("外す", func() -> void:
			if HubActions.unequip(profile, slot, snapshot):
				changed(), row, sound)
		take_off.disabled = item.is_empty()
	var list_side := VBoxContainer.new()
	list_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(list_side)
	list_side.add_child(PixelUi.label("所持品 %d個" % profile.inventory.size(), 18, Color("c8b8e8")))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll_body(list_side).add_child(list)
	if profile.inventory.is_empty():
		list.add_child(PixelUi.label("戦闘に勝つかショップで購入すると装備が手に入ります。", 15, Color("f4ead8"), 0, true, true))
	for item: Dictionary in profile.inventory:
		var box := item_block(list, item)
		var reason := HubActions.equip_reason(profile, item, snapshot)
		var wear := PixelUi.button("装備中" if HubActions.is_equipped(profile, item) else "装備する", func() -> void:
			if HubActions.equip(profile, item, snapshot):
				changed(), box, sound)
		wear.size_flags_horizontal = Control.SIZE_SHRINK_END
		wear.disabled = not reason.is_empty()
		wear.tooltip_text = reason

func build_shop() -> void:
	var body := sheet(Rect2(716, 56, 540, 650), "◀ 本拠地へ帰還")
	body.add_child(PixelUi.label("所持金 %d G   品揃えは出撃から帰還するたびに入れ替わります" % profile.gold, 15, Color("ffe070"), 0, true, true))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll_body(body).add_child(list)
	var offers := Shop.stock(profile)
	if offers.is_empty():
		list.add_child(PixelUi.label("商品がありません。", 16))
	for i: int in offers.size():
		var offer: Dictionary = offers[i]
		var box := consumable_block(list, HubActions.consumable(snapshot, offer.id), "所持 %d" % HubActions.owned(profile, offer.id)) if offer.kind == "consumable" else item_block(list, offer.item)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		box.add_child(row)
		row.add_child(PixelUi.label("%d G" % int(offer.price), 18, Color("ffe070"), 3))
		var reason := Shop.buy_reason(profile, i)
		var buy := PixelUi.button("売り切れ" if offer.sold else "購入", func() -> void:
			if Shop.buy(profile, i):
				sound.play("buff", 0.0)
				changed("%s を購入しました" % (HubActions.consumable(snapshot, offer.id).name if offer.kind == "consumable" else HubActions.item_title(offer.item, snapshot))), row, sound, not offer.sold)
		buy.disabled = not reason.is_empty()
		buy.tooltip_text = reason
		if offer.sold:
			box.modulate = Color(1, 1, 1, 0.5)

func consumable_block(parent: Node, item: Dictionary, note: String) -> VBoxContainer:
	var frame := PixelUi.panel(parent)
	var box := VBoxContainer.new()
	frame.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var icon := BattleCard.pixel_rect(PixelUi.texture(ItemRunner.icon_path(item)), Vector2.ZERO, 2)
	icon.custom_minimum_size = Vector2(32, 32)
	head.add_child(icon)
	var title := PixelUi.label("%s   %s" % [item.name, note], 17, Color("ffe8b0"), 3)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	box.add_child(PixelUi.label("%s\n使用場面: %s / 対象: %s" % [item.description, UiText.name_for(item.scene), UiText.name_for(item.target)], 14, Color("f4ead8"), 0, true, true))
	return box

func build_items() -> void:
	var body := sheet(Rect2(40, 56, 1200, 650))
	var limit := ItemRunner.carry_limit(snapshot)
	body.add_child(PixelUi.label("持ち込み %d / %d個（出撃時に持っていく消費アイテム。戦闘中は上部バー、マップではボタンから使用）" % [profile.loadout.size(), limit], 16, Color("f4ead8"), 0, true, true))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	body.add_child(slots)
	for i: int in maxi(limit, profile.loadout.size()):
		var slot := PixelUi.panel(slots)
		slot.custom_minimum_size = Vector2(170, 64)
		var inner := HBoxContainer.new()
		slot.add_child(inner)
		if i >= profile.loadout.size():
			inner.add_child(PixelUi.label("空き", 15, Color("8a8090")))
			continue
		var item := HubActions.consumable(snapshot, profile.loadout[i])
		var icon := BattleCard.pixel_rect(PixelUi.texture(ItemRunner.icon_path(item)), Vector2.ZERO, 2)
		icon.custom_minimum_size = Vector2(32, 32)
		inner.add_child(icon)
		inner.add_child(PixelUi.label(str(item.name), 15, Color("ffe8b0") if i < limit else Color("ff8a8a")))
		var index := i
		PixelUi.button("外す", func() -> void:
			if HubActions.unload_item(profile, index):
				changed(), inner, sound)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll_body(body).add_child(list)
	if profile.consumables.is_empty():
		list.add_child(PixelUi.label("消費アイテムを持っていません。ショップで購入できます。", 15, Color("f4ead8"), 0, true, true))
	for id: String in profile.consumables:
		var item := HubActions.consumable(snapshot, id)
		var box := consumable_block(list, item, "×%d（持ち込み %d）" % [HubActions.owned(profile, id), profile.loadout.count(id)])
		var reason := HubActions.load_reason(profile, snapshot, id)
		var carry := PixelUi.button("持ち込む", func() -> void:
			if HubActions.load_item(profile, snapshot, id):
				changed(), box, sound)
		carry.size_flags_horizontal = Control.SIZE_SHRINK_END
		carry.disabled = not reason.is_empty()
		carry.tooltip_text = reason
