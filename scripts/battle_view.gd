class_name BattleView
extends Control

## Slay the Spire style battle screen. BattleEngine resolves each action
## instantly; this view replays engine.events as animations and sound, then
## emits action_finished so main.gd can continue (reward / defeat / redraw).

signal action_finished
signal editor_requested
signal retreat_requested
signal retry_requested(new_seed: bool)

const SCREEN := Vector2(1280, 720)
const GROUND_Y: float = 496.0
const HERO_X: float = 300.0
const HAND_REST_Y: float = 666.0
const PLAY_LINE: float = 470.0
const AIM_CENTER := Vector2(640, 500)
const DECK_POS := Vector2(60, 682)
const HOVER_SCALE: float = 1.5

var engine: BattleEngine
var sound: Sound
var info: Dictionary = {}
var stage: Control
var hero: BattleActor
var foes: Array[BattleActor] = []
var fx: Control
var hand_layer: Control
var arrow: Control
var cards: Array[BattleCard] = []
var queue: Array[Dictionary] = []
var playing: bool = false
var finishing: bool = false
var notify_after: bool = false
var hovered: int = -1
var held: int = -1
var dragging: bool = false
var press_pos := Vector2.ZERO
var mouse := Vector2(640, 360)
var aim_target: int = -1
var lunged: bool = false
var last_group: int = -1
var ap_label: Label
var mp_label: Label
var deck_label: Label
var info_label: Label
var end_button: Button
var mute_button: Button
var log_panel: PanelContainer
var log_label: RichTextLabel
var banner: ColorRect
var banner_label: Label
var toast: Label
var tip_panel: PanelContainer
var tip_label: Label

func setup(battle: BattleEngine, audio: Sound, context: Dictionary) -> void:
	engine = battle
	sound = audio
	info = context
	position = Vector2.ZERO
	size = SCREEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	build_stage()
	build_hud()
	# Cards are dealt by the queued draw event, so hold off hand reconciliation.
	playing = true
	sync()
	engine.events.clear()
	queue.append({"kind": "intro"})
	queue.append({"kind": "draw", "ids": engine.hand.duplicate()})
	step()

# ------------------------------------------------------------------ building

func build_stage() -> void:
	stage = Control.new()
	stage.size = SCREEN
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	var background_path := "res://assets/backgrounds/%s.png" % ("forest_boss" if info.get("boss", false) else "forest")
	if ResourceLoader.exists(background_path):
		stage.add_child(BattleCard.pixel_rect(load(background_path), Vector2.ZERO, 4))
	hero = BattleActor.new()
	stage.add_child(hero)
	hero.setup(texture_or_null("res://assets/sprites/hero.png"), -1, "英雄", 3)
	hero.position = Vector2(HERO_X - hero.size.x / 2, GROUND_Y - hero.size.y)
	var total: float = 0.0
	for i: int in engine.enemies.size():
		var enemy: Dictionary = engine.enemies[i]
		var texture := texture_or_null("res://assets/sprites/enemies/%s.png" % enemy.id)
		if texture == null:
			texture = texture_or_null("res://assets/sprites/enemies/default.png")
		var foe := BattleActor.new()
		stage.add_child(foe)
		foe.setup(texture, i, enemy.name, 3)
		foes.append(foe)
		total += foe.size.x
	var gap: float = 40.0 if foes.size() < 2 else clampf((560.0 - total) / (foes.size() - 1), -40.0, 60.0)
	var x: float = 950.0 - (total + gap * (foes.size() - 1)) / 2
	for foe: BattleActor in foes:
		foe.position = Vector2(x, GROUND_Y - foe.size.y)
		x += foe.size.x + gap
	fx = Control.new()
	fx.size = SCREEN
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(fx)

func texture_or_null(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null

func style(path: String) -> StyleBox:
	return PixelUi.style(path)

func make_button(text: String, action: Callable, parent: Node, end_style: bool = false) -> Button:
	return PixelUi.button(text, action, parent, sound, end_style)

func build_hud() -> void:
	var bar := PanelContainer.new()
	bar.position = Vector2.ZERO
	bar.size = Vector2(SCREEN.x, 44)
	bar.add_theme_stylebox_override("panel", style("res://assets/ui/panel.png"))
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	info_label = BattleCard.text_label("", 16, Color("f4ead8"), 4)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_label)
	if info.get("test", false):
		make_button("同じ条件で再試行", func() -> void: retry_requested.emit(false), row)
		make_button("新しいシードで再試行", func() -> void: retry_requested.emit(true), row)
		make_button("◀ 編集へ戻る (F1)", func() -> void: editor_requested.emit(), row)
	elif info.get("dev", false):
		make_button("◀ エディタ (F1)", func() -> void: editor_requested.emit(), row)
	make_button("ログ", func() -> void: log_panel.visible = not log_panel.visible, row)
	mute_button = make_button("BGM/SE: OFF" if sound.muted else "BGM/SE: ON", func() -> void:
		mute_button.text = "BGM/SE: OFF" if sound.toggle_mute() else "BGM/SE: ON", row)
	make_button("撤退", func() -> void: retreat_requested.emit(), row)

	var orb := BattleCard.pixel_rect(texture_or_null("res://assets/ui/energy_orb.png"), Vector2(22, 540), 2)
	orb.tooltip_text = "AP（行動力）: カードの使用に必要。毎ターン全回復"
	orb.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(orb)
	ap_label = BattleCard.text_label("", 26, Color.WHITE, 7)
	ap_label.position = Vector2(22, 540)
	ap_label.size = Vector2(80, 80)
	add_child(ap_label)
	var mp_row := HBoxContainer.new()
	mp_row.position = Vector2(18, 624)
	mp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mp_row)
	var gem := BattleCard.pixel_rect(BattleActor.icon("mp"), Vector2.ZERO, 2)
	gem.custom_minimum_size = Vector2(32, 32)
	mp_row.add_child(gem)
	mp_label = BattleCard.text_label("", 17, Color("9ad0ff"), 4)
	mp_row.add_child(mp_label)
	var deck := BattleCard.pixel_rect(texture_or_null("res://assets/ui/deck.png"), DECK_POS - Vector2(26, 30), 2)
	deck.tooltip_text = "山札。使ったカードは山札の底へ戻ります"
	deck.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(deck)
	deck_label = BattleCard.text_label("", 18, Color.WHITE, 5)
	deck_label.position = DECK_POS + Vector2(22, -4)
	deck_label.size = Vector2(40, 30)
	add_child(deck_label)

	end_button = make_button("ターン終了", end_turn, self, true)
	end_button.position = Vector2(1100, 586)
	end_button.size = Vector2(160, 58)
	var hint := BattleCard.text_label("E: ターン終了  1-0: カード選択\n右クリック/Esc: 取消", 12, Color("c8c0d0"), 3)
	hint.position = Vector2(1060, 650)
	hint.size = Vector2(210, 44)
	add_child(hint)

	hand_layer = Control.new()
	hand_layer.size = SCREEN
	hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hand_layer)
	arrow = Control.new()
	arrow.size = SCREEN
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.draw.connect(draw_arrow)
	add_child(arrow)

	log_panel = PanelContainer.new()
	log_panel.position = Vector2(880, 50)
	log_panel.size = Vector2(390, 280)
	log_panel.add_theme_stylebox_override("panel", style("res://assets/ui/panel.png"))
	log_panel.visible = false
	add_child(log_panel)
	log_label = RichTextLabel.new()
	log_label.scroll_following = true
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	log_panel.add_child(log_label)

	tip_panel = PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel", style("res://assets/ui/panel.png"))
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.visible = false
	add_child(tip_panel)
	tip_label = BattleCard.text_label("", 14, Color("f4ead8"))
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tip_panel.add_child(tip_label)

	banner = ColorRect.new()
	banner.color = Color(0.05, 0.03, 0.08, 0.72)
	banner.position = Vector2(0, 230)
	banner.size = Vector2(SCREEN.x, 96)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	add_child(banner)
	banner_label = BattleCard.text_label("", 42, Color.WHITE, 10)
	banner_label.size = banner.size
	banner.add_child(banner_label)
	toast = BattleCard.text_label("", 22, Color("ffb0a0"), 6)
	toast.position = Vector2(340, 410)
	toast.size = Vector2(600, 40)
	toast.modulate.a = 0.0
	add_child(toast)

# ------------------------------------------------------------------ state

func actor(index: int) -> BattleActor:
	return hero if index < 0 else foes[index]

func player_turn() -> bool:
	return not playing and not finishing and engine.outcome.is_empty() and engine.fault.is_empty()

func sync() -> void:
	hero.apply_state(engine.state_of(engine.player))
	for i: int in foes.size():
		foes[i].apply_state(engine.state_of(engine.enemies[i]))
	update_intents()
	update_hud(engine.ap, int(engine.player.mp))
	if not playing:
		reconcile_hand()
	refresh_cards()
	layout_hand()
	log_label.text = "\n".join(engine.log.slice(maxi(0, engine.log.size() - 60)))
	if not engine.fault.is_empty():
		toast.text = "数式エラーで停止: %s — エディタで修正してください" % engine.fault
		toast.modulate.a = 1.0

func update_hud(ap: int, mp: int) -> void:
	ap_label.text = "%d/%d" % [ap, int(engine.rules.ap)]
	mp_label.text = "MP %d/%d" % [mp, int(engine.effective(engine.player).max_mp)]
	deck_label.text = str(engine.deck.size())
	var where: String = info.get("area", "")
	if not str(info.get("node", "")).is_empty():
		where += " ・ " + ("ボス" if info.get("boss", false) else str(info.node))
	var text := "%s   ターン %d" % [where if not where.is_empty() else "戦闘テスト", engine.turn]
	if info.get("test", false):
		text = "● テストプレイ seed %s   %s" % [info.get("seed", ""), text]
	if not str(info.get("notice", "")).is_empty():
		text += "   " + str(info.notice)
	info_label.text = text
	end_button.disabled = not player_turn()
	end_button.text = "ターン終了" if player_turn() or not engine.outcome.is_empty() else "敵のターン…"

func update_intents() -> void:
	for i: int in foes.size():
		var enemy: Dictionary = engine.enemies[i]
		if enemy.hp <= 0:
			foes[i].set_intent([], "")
			continue
		var actions: Array = enemy.definition.actions
		var action: Dictionary = actions[int(enemy.action) % actions.size()]
		var parts: Array = []
		for effect: Dictionary in action.effects:
			var evaluated := engine.effect_value(effect, enemy)
			var shown: bool = effect.type in ["damage", "block", "heal", "apply_poison", "restore_mp"]
			parts.append({"type": effect.type, "value": str(evaluated.value) if shown and evaluated.ok else ""})
		foes[i].set_intent(parts, "次の行動: " + engine.intent(enemy))

func reconcile_hand() -> void:
	var matches: bool = cards.size() == engine.hand.size()
	for i: int in mini(cards.size(), engine.hand.size()):
		matches = matches and cards[i].card.id == engine.hand[i]
	if matches:
		return
	for card: BattleCard in cards:
		card.queue_free()
	cards.clear()
	for id: String in engine.hand:
		var card := new_card(id)
		card.position = Vector2(640, HAND_REST_Y) - BattleCard.SIZE / 2

func new_card(id: String) -> BattleCard:
	var card := BattleCard.new()
	hand_layer.add_child(card)
	card.setup(engine.cards[id])
	cards.append(card)
	return card

func refresh_cards() -> void:
	for i: int in cards.size():
		var reason: String = engine.can_play(i, -1, false) if i < engine.hand.size() else "—"
		cards[i].refresh(engine, reason, player_turn())

# ------------------------------------------------------------------ hand layout

func rest_center(i: int, n: int) -> Vector2:
	var spacing: float = minf(150.0, 680.0 / maxf(1.0, n))
	var offset: float = i - (n - 1) / 2.0
	return Vector2(640.0 + offset * spacing, HAND_REST_Y + offset * offset * 2.5)

func rest_rotation(i: int, n: int) -> float:
	return deg_to_rad((i - (n - 1) / 2.0) * minf(4.0, 28.0 / maxf(1.0, n)))

func layout_hand() -> void:
	var n := cards.size()
	for i: int in n:
		var card := cards[i]
		var center := rest_center(i, n)
		var rotation_value := rest_rotation(i, n)
		var card_scale: float = 1.0
		card.z_index = i
		if i == held:
			card.z_index = 200
			if needs_target(i):
				card.move_to(AIM_CENTER - BattleCard.SIZE / 2, 0.0, 1.0, 0.12)
			continue
		if i == hovered and held < 0:
			center = Vector2(clampf(center.x, 130, SCREEN.x - 130), SCREEN.y - BattleCard.SIZE.y * HOVER_SCALE / 2)
			rotation_value = 0.0
			card_scale = HOVER_SCALE
			card.z_index = 100
		elif hovered >= 0 and held < 0:
			center.x += signf(float(i - hovered)) * 40.0
		card.move_to(center - BattleCard.SIZE / 2, rotation_value, card_scale)

func needs_target(i: int) -> bool:
	return i >= 0 and i < engine.hand.size() and engine.needs_target(engine.cards[engine.hand[i]])

func card_at(point: Vector2) -> int:
	var n := cards.size()
	if hovered >= 0 and hovered < n and held < 0:
		var size_now := BattleCard.SIZE * HOVER_SCALE
		var hover_rect := Rect2(Vector2(clampf(rest_center(hovered, n).x, 130, SCREEN.x - 130) - size_now.x / 2, SCREEN.y - size_now.y), size_now)
		if hover_rect.has_point(point):
			return hovered
	for i: int in range(n - 1, -1, -1):
		var rect := Rect2(rest_center(i, n) - BattleCard.SIZE / 2, BattleCard.SIZE)
		if rect.has_point(point):
			return i
	return -1

func enemy_at(point: Vector2) -> int:
	for i: int in foes.size():
		if not foes[i].dead and foes[i].hit_rect().has_point(point):
			return i
	return -1

# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = event.position
		on_motion()
		return
	if not player_turn():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_pos = event.position
			mouse = event.position
			if held >= 0:
				resolve_held()
			else:
				var i := card_at(event.position)
				if i >= 0:
					pick(i)
					dragging = true
			get_viewport().set_input_as_handled()
		elif held >= 0 and dragging:
			dragging = false
			if event.position.distance_to(press_pos) > 14.0:
				resolve_held()
			get_viewport().set_input_as_handled()
	elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or event.is_action_pressed("ui_cancel"):
		if held >= 0:
			cancel_held()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		if key == KEY_E:
			end_turn()
			get_viewport().set_input_as_handled()
		elif key >= KEY_0 and key <= KEY_9:
			var i: int = 9 if key == KEY_0 else key - KEY_1
			if i < cards.size():
				if held == i:
					cancel_held()
				else:
					cancel_held()
					pick(i)
				get_viewport().set_input_as_handled()

func pick(i: int) -> void:
	held = i
	hovered = -1
	sound.play("card_select", 0.0)
	layout_hand()
	on_motion()

func cancel_held() -> void:
	if held < 0:
		return
	held = -1
	dragging = false
	aim_target = -1
	for foe: BattleActor in foes:
		foe.set_targeted(false)
	hovered = card_at(mouse)
	layout_hand()
	arrow.queue_redraw()

func resolve_held() -> void:
	var i := held
	if needs_target(i):
		var target := enemy_at(mouse)
		if target >= 0:
			cancel_held()
			play_card(i, target)
			return
	elif mouse.y < PLAY_LINE:
		cancel_held()
		play_card(i, -1)
		return
	var other := card_at(mouse)
	cancel_held()
	if other >= 0 and other != i:
		pick(other)

func on_motion() -> void:
	if held >= 0 and held < cards.size():
		if needs_target(held):
			aim_target = enemy_at(mouse)
			for foe_index: int in foes.size():
				foes[foe_index].set_targeted(foe_index == aim_target)
		else:
			var card := cards[held]
			card.position = mouse - BattleCard.SIZE / 2
			card.rotation = 0.0
			card.modulate = Color(1.25, 1.25, 1.1) if mouse.y < PLAY_LINE else Color.WHITE
		arrow.queue_redraw()
		tip_panel.visible = false
		return
	var over := card_at(mouse) if player_turn() else -1
	if over != hovered:
		hovered = over
		if over >= 0:
			sound.play("card_hover", 0.05, -10.0)
		layout_hand()
	show_actor_tip()

func show_actor_tip() -> void:
	var over: BattleActor = null
	if hero.hit_rect().has_point(mouse):
		over = hero
	var enemy := enemy_at(mouse)
	if enemy >= 0:
		over = foes[enemy]
	tip_panel.visible = over != null and hovered < 0
	if over == null:
		return
	var lines: Array[String] = [over.display_name]
	if over.index >= 0:
		lines.append("次の行動: " + engine.intent(engine.enemies[over.index]))
	var state: Dictionary = over.state
	if int(state.get("block", 0)) > 0:
		lines.append("ブロック %d: 次の被ダメージを軽減（自分のターン開始時に消える）" % int(state.block))
	if int(state.get("poison", 0)) > 0:
		lines.append("毒 %d: ターン開始時にダメージを受け、1減る" % int(state.poison))
	var buffs: Dictionary = state.get("buffs", {})
	for stat: String in buffs:
		lines.append("%s %+d（戦闘中）" % [UiText.name_for(stat), int(buffs[stat])])
	tip_label.text = "\n".join(lines)
	tip_panel.reset_size()
	var at := over.position + Vector2(over.size.x + 8, 0)
	if at.x + tip_panel.size.x > SCREEN.x - 8:
		at.x = over.position.x - tip_panel.size.x - 8
	tip_panel.position = Vector2(at.x, clampf(at.y, 52, 400))

func draw_arrow() -> void:
	if held < 0 or not needs_target(held):
		return
	var start := AIM_CENTER - Vector2(0, BattleCard.SIZE.y / 2 + 6)
	var control := Vector2(start.x, mouse.y - 40)
	var color := Color("ffd84a") if aim_target >= 0 else Color("f4ead8")
	var previous := start
	var count: int = 14
	for step_index: int in count:
		var t: float = float(step_index) / count
		var point := start.lerp(control, t).lerp(control.lerp(mouse, t), t)
		var block: float = 6.0 + t * 6.0
		arrow.draw_rect(Rect2(point - Vector2(block, block) / 2 - Vector2(2, 2), Vector2(block + 4, block + 4)), Color("140c18"))
		arrow.draw_rect(Rect2(point - Vector2(block, block) / 2, Vector2(block, block)), color)
		previous = point
	var direction := (mouse - previous).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.UP
	var side := direction.orthogonal()
	var head := PackedVector2Array([mouse + direction * 10, mouse - direction * 14 + side * 14, mouse - direction * 14 - side * 14])
	var rim := PackedVector2Array([mouse + direction * 15, mouse - direction * 18 + side * 19, mouse - direction * 18 - side * 19])
	arrow.draw_colored_polygon(rim, Color("140c18"))
	arrow.draw_colored_polygon(head, color)

# ------------------------------------------------------------------ actions

func play_card(i: int, target: int) -> void:
	var reason := engine.can_play(i, target)
	if not reason.is_empty():
		deny(reason)
		return
	if engine.play(i, target):
		notify_after = true
		run(engine.events)

func end_turn() -> void:
	if not player_turn():
		return
	cancel_held()
	hovered = -1
	engine.end_turn()
	notify_after = true
	run(engine.events)

func deny(reason: String) -> void:
	sound.play("denied", 0.0)
	toast.text = reason
	toast.modulate.a = 1.0
	var tween := toast.create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	refresh_cards()
	layout_hand()

func run(events: Array[Dictionary]) -> void:
	queue.append_array(events.duplicate(true))
	events.clear()
	tip_panel.visible = false
	if not playing:
		playing = true
		update_hud(engine.ap, int(engine.player.mp))
		refresh_cards()
		step()

func step() -> void:
	if queue.is_empty():
		playing = false
		finish()
		return
	var wait: float = handle(queue.pop_front())
	var tween := create_tween()
	tween.tween_interval(maxf(wait, 0.0))
	tween.tween_callback(step)

func finish() -> void:
	sync()
	if not engine.outcome.is_empty():
		if finishing:
			return
		finishing = true
		update_hud(engine.ap, int(engine.player.mp))
		sound.play_bgm("")
		var victory: bool = engine.outcome == "victory"
		sound.play("victory" if victory else "defeat", 0.0, -2.0)
		show_banner("勝利！" if victory else "敗北…", Color("ffe08a") if victory else Color("ff8a8a"), 99.0)
		var tween := create_tween()
		tween.tween_interval(1.9)
		tween.tween_callback(func() -> void: action_finished.emit())
		return
	on_motion()
	if notify_after:
		notify_after = false
		action_finished.emit()

# ------------------------------------------------------------------ event playback

func handle(ev: Dictionary) -> float:
	match ev.kind:
		"intro":
			var title: String = "ボス戦" if info.get("boss", false) else (str(info.get("area", "")) if not str(info.get("area", "")).is_empty() else "戦闘開始")
			show_banner(title, Color("ffd8a0") if info.get("boss", false) else Color.WHITE, 0.5)
			return 0.7
		"draw":
			var ids: Array = ev.ids
			var tween := create_tween()
			for id: String in ids:
				tween.tween_callback(func() -> void: deal_card(id))
				tween.tween_interval(0.08)
			return 0.08 * ids.size() + 0.12
		"card":
			fly_played(int(ev.index), int(ev.target))
			update_hud(int(ev.ap), int(ev.mp))
			lunged = false
			last_group = -1
			sound.play("card_play")
			return 0.16
		"effect":
			return on_effect(ev)
		"phase":
			var target := actor(int(ev.target))
			target.apply_state(ev.state)
			if int(ev.poison) > 0:
				sound.play("poison")
				popup(target, "-%d" % int(ev.poison), Color("8aff6a"), 30)
				target.hurt(0.5)
				burst(target, Color("7aff4a"), 8)
				check_death(target, false)
				return 0.4
			return 0.0
		"enemy_turn":
			sound.play("turn_end", 0.0)
			update_hud(engine.ap, int(engine.player.mp))
			refresh_cards()
			show_banner("敵のターン", Color("ffb0a0"), 0.35)
			return 0.7
		"act":
			var foe := actor(int(ev.source))
			foe.announce(str(ev.name))
			return 0.3
		"turn":
			update_intents()
			update_hud(int(ev.ap), int(ev.mp))
			sound.play("turn_start", 0.0)
			show_banner("ターン %d" % int(ev.turn), Color("a0e0ff"), 0.3)
			return 0.6
	return 0.0

func on_effect(ev: Dictionary) -> float:
	var target := actor(int(ev.target))
	var source := actor(int(ev.source))
	var amount: int = int(ev.amount)
	var first_of_group: bool = int(ev.group) != last_group
	var grouped: bool = not queue.is_empty() and queue[0].get("kind", "") == "effect" and int(queue[0].get("group", -1)) == int(ev.group)
	last_group = int(ev.group)
	var was_dead: bool = target.dead
	match str(ev.type):
		"damage":
			var dealt: int = amount - int(ev.absorbed)
			if int(ev.source) >= 0:
				if first_of_group:
					source.lunge(-1.0)
					sound.play("enemy_attack")
			elif not lunged:
				hero.lunge(1.0)
				lunged = true
			if first_of_group:
				if int(ev.source) < 0:
					sound.play("magic" if ev.magic else ("sweep" if grouped else ("heavy" if amount >= 14 else "slash")))
				else:
					sound.play("hurt" if dealt > 0 else "block_hit")
			if int(ev.absorbed) > 0:
				sound.play("block_hit")
				popup(target, "ブロック -%d" % int(ev.absorbed), Color("8ac8ff"), 18, Vector2(0, -34))
			if dealt > 0:
				target.hurt(clampf(dealt / 8.0, 0.6, 2.0))
				popup(target, str(dealt), Color("ffffff"), 36 if dealt >= 10 else 30)
				burst(target, Color("ffb050") if ev.magic else Color("fff0d0"), 10)
				if dealt >= 12:
					shake(clampf(dealt / 2.0, 6.0, 16.0))
		"block":
			sound.play("block")
			popup(target, "+%d" % amount, Color("8ac8ff"), 28)
			target.pulse(Color(0.7, 0.9, 1.8))
		"heal":
			sound.play("heal")
			popup(target, "+%d" % amount, Color("7aff8a"), 30)
			target.pulse(Color(0.8, 1.8, 0.8))
			burst(target, Color("a0ffa0"), 8)
		"restore_mp":
			sound.play("mp")
			popup(target, "MP +%d" % amount, Color("9ad0ff"), 26)
			target.pulse(Color(0.8, 0.9, 1.8))
		"apply_poison":
			sound.play("poison")
			popup(target, "毒 +%d" % amount, Color("8aff6a"), 24, Vector2(0, -30))
			target.pulse(Color(0.8, 1.6, 0.6))
		"modify_stat":
			sound.play("buff")
			popup(target, "%s +%d" % [UiText.name_for(str(ev.stat)), amount], Color("ffd070"), 26)
			target.pulse(Color(1.8, 1.5, 0.7))
		"draw":
			pass
	target.apply_state(ev.state)
	if int(ev.target) < 0:
		mp_label.text = "MP %d/%d" % [int(ev.state.mp), int(engine.effective(engine.player).max_mp)]
		refresh_cards()
	check_death(target, was_dead)
	if str(ev.type) == "draw":
		return 0.0
	return 0.06 if grouped else 0.34

func check_death(target: BattleActor, was_dead: bool) -> void:
	if target.dead and not was_dead and target != hero:
		sound.play("enemy_die")
		burst(target, Color("c0a0ff"), 16)

func deal_card(id: String) -> void:
	var card := new_card(id)
	card.position = DECK_POS - BattleCard.SIZE / 2
	card.scale = Vector2.ONE * 0.25
	card.rotation = -0.6
	sound.play("card_draw", 0.1)
	deck_label.text = str(engine.deck.size())
	refresh_cards()
	layout_hand()

func fly_played(index: int, target: int) -> void:
	if index < 0 or index >= cards.size():
		return
	var card: BattleCard = cards.pop_at(index)
	card.z_index = 300
	card.glow = false
	card.queue_redraw()
	if card.motion != null and card.motion.is_valid():
		card.motion.kill()
	var focus := Vector2(640, 330) if target < 0 else foes[target].position + foes[target].size / 2 - Vector2(0, 40)
	var tween := card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	tween.tween_property(card, "position", focus.lerp(Vector2(640, 330), 0.6) - BattleCard.SIZE / 2, 0.16)
	tween.tween_property(card, "rotation", 0.0, 0.16)
	tween.tween_property(card, "scale", Vector2.ONE, 0.16)
	tween.chain().tween_interval(0.12)
	tween.chain().set_parallel()
	tween.tween_property(card, "position", DECK_POS - BattleCard.SIZE / 2, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "scale", Vector2.ONE * 0.2, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(card.queue_free)
	layout_hand()

# ------------------------------------------------------------------ effects

func popup(target: BattleActor, text: String, color: Color, font_size: int, offset: Vector2 = Vector2.ZERO) -> void:
	var label := BattleCard.text_label(text, font_size, color, 8)
	label.size = Vector2(240, 48)
	label.pivot_offset = label.size / 2
	label.position = target.position + Vector2(target.size.x / 2 - 120 + randf_range(-18, 18), target.size.y * 0.3) + offset
	label.scale = Vector2.ONE * 1.6
	fx.add_child(label)
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - 70, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(label.queue_free)

func burst(target: BattleActor, color: Color, count: int) -> void:
	var center := target.position + target.size * Vector2(0.5, 0.45)
	for i: int in count:
		var bit := ColorRect.new()
		var pixel: float = [6.0, 9.0, 12.0][i % 3]
		bit.size = Vector2(pixel, pixel)
		bit.color = color if i % 3 else Color.WHITE
		bit.position = center
		bit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx.add_child(bit)
		var angle: float = TAU * i / count + randf_range(-0.3, 0.3)
		var distance: float = randf_range(50, 110)
		var tween := bit.create_tween().set_parallel()
		tween.tween_property(bit, "position", center + Vector2(cos(angle), sin(angle)) * distance, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(bit, "modulate:a", 0.0, 0.4).set_delay(0.12)
		tween.chain().tween_callback(bit.queue_free)

func shake(strength: float) -> void:
	var tween := create_tween()
	for i: int in 6:
		tween.tween_property(stage, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * (1.0 - i / 6.0), 0.035)
	tween.tween_property(stage, "position", Vector2.ZERO, 0.035)

func show_banner(text: String, color: Color, hold: float) -> void:
	banner_label.text = text
	banner_label.label_settings.font_color = color
	banner.modulate.a = 0.0
	var tween := banner.create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.15)
	tween.tween_interval(hold)
	tween.tween_property(banner, "modulate:a", 0.0, 0.25)
