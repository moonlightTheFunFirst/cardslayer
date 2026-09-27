class_name ItemRunner
extends RefCounted

## Consumable definitions: validation, the GDScript effect scripts, and running
## an item against an ItemContext (battle or field).
##
## A consumable uses its selected conditions / basic_effects unless "script"
## is set. A script may define:
##   func can_use(ctx) -> String   # "" = usable, otherwise the reason shown
##   func use(ctx)                 # required
## and can call ctx.basic_reason() / ctx.apply_basic() to reuse the defaults.

const KINDS: Array[String] = ["heal", "restore_mp", "block", "modify_stat", "reduce_damage", "cure_bad_status", "damage", "damage_all", "draw"]
const BATTLE_ONLY_KINDS: Array[String] = ["block", "modify_stat", "reduce_damage", "cure_bad_status", "damage", "damage_all", "draw"]
const CONDITIONS: Array[String] = ["hp_not_full", "mp_not_full", "has_bad_status"]
const SCENES: Array[String] = ["battle", "anywhere"]
const TARGETS: Array[String] = ["self", "selected_enemy"]
const ICONS: Array[String] = ["herb", "elixir", "power", "defense", "vial", "dice", "potion_red", "potion_blue"]
const SOUNDS: Array[String] = ["heal", "cure", "buff", "block", "mp", "magic", "poison", "slash", "heavy", "item_use"]
const ANIMATIONS: Array[String] = ["sparkle", "burst", "pulse", "none"]
## Not a sandbox, but keeps item scripts to gameplay code: no file, OS or engine access.
const FORBIDDEN := "\\b(OS|FileAccess|DirAccess|ResourceLoader|ResourceSaver|ProjectSettings|Engine|ClassDB|JavaScriptBridge|Thread|Mutex|Semaphore|Expression|GDScript|HTTPClient|HTTPRequest|StreamPeer\\w*|PacketPeer\\w*|TCPServer|UDPServer|Marshalls|JSON|load|preload|get_tree|extends|class_name|static|await|Callable|call|callv|call_deferred|set|get|set_script|get_script)\\b"
const DEFAULTS: Dictionary = {"id": "items", "carry_limit": 3, "starter": ["herb", "herb"]}
const TEMPLATE := "func can_use(ctx):\n\treturn ctx.basic_reason()\n\nfunc use(ctx):\n\tctx.apply_basic()\n"

static var compiled: Dictionary = {}

## rules/items merged over DEFAULTS (older edit workspaces may lack the entry).
static func settings(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = DEFAULTS.duplicate(true)
	var rules := DefinitionRepository.new().indexed("rules", snapshot)
	if rules.has("items"):
		for key: String in rules.items:
			result[key] = rules.items[key]
	return result

static func carry_limit(snapshot: Dictionary) -> int:
	return int(settings(snapshot).carry_limit)

static func icon_path(definition: Dictionary) -> String:
	return "res://assets/items/%s.png" % str(definition.get("icon", "potion_red"))

## {"ok", "instance" | "error"}; cached by source text.
static func compile(source: String) -> Dictionary:
	if compiled.has(source):
		return compiled[source]
	var result: Dictionary
	var forbidden := RegEx.new()
	forbidden.compile(FORBIDDEN)
	var found := forbidden.search(source)
	if found != null:
		result = {"ok": false, "error": "使用できない語があります: " + found.get_string()}
	else:
		var script := GDScript.new()
		script.source_code = "extends RefCounted\n" + source
		if script.reload() != OK:
			result = {"ok": false, "error": "スクリプトの構文エラー（Godotの出力に詳細）"}
		else:
			var instance: Object = script.new()
			if not instance.has_method("use"):
				result = {"ok": false, "error": "func use(ctx) が必要です"}
			else:
				result = {"ok": true, "instance": instance}
	compiled[source] = result
	return result

static func validate_settings(entry: Dictionary, consumables: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var limit: Variant = entry.get("carry_limit", DEFAULTS.carry_limit)
	if not EquipmentGenerator.valid_number(limit, 0, 10) or floor(float(limit)) != float(limit):
		issues.append("rules/items/carry_limit: 整数 0～10 が必要")
	var starter: Variant = entry.get("starter", DEFAULTS.starter)
	if not starter is Array:
		issues.append("rules/items/starter: ID配列が必要")
	else:
		for id: Variant in starter:
			if not consumables.has(id):
				issues.append("rules/items/starter: 参照先がありません " + str(id))
	return issues

static func validate(entry: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var path := "consumables/" + str(entry.get("id", ""))
	for field: String in ["description", "script", "effect_color"]:
		if not entry.get(field) is String:
			issues.append(path + "/" + field + ": 文字列が必要")
	for field: Array in [["price", 1, 1000000], ["shop_weight", 0, 100000]]:
		var value: Variant = entry.get(field[0])
		if not EquipmentGenerator.valid_number(value, field[1], field[2]) or floor(float(value)) != float(value):
			issues.append("%s/%s: 整数 %d～%d が必要" % [path, field[0], field[1], field[2]])
	for pair: Array in [["icon", ICONS], ["sound", SOUNDS], ["animation", ANIMATIONS], ["scene", SCENES], ["target", TARGETS]]:
		if entry.get(pair[0]) not in pair[1]:
			issues.append("%s/%s: 不正な値 %s" % [path, pair[0], str(entry.get(pair[0]))])
	if entry.get("effect_color") is String and not Color.html_is_valid(entry.effect_color):
		issues.append(path + "/effect_color: 色は 7aff8a のような16進数で指定")
	if not entry.get("conditions") is Array:
		issues.append(path + "/conditions: 配列が必要")
	else:
		for condition: Variant in entry.conditions:
			if condition not in CONDITIONS:
				issues.append(path + "/conditions: 未知の条件 " + str(condition))
	if not entry.get("basic_effects") is Array:
		issues.append(path + "/basic_effects: 配列が必要")
		return issues
	for effect: Variant in entry.basic_effects:
		if not effect is Dictionary or effect.get("kind") not in KINDS:
			issues.append(path + "/basic_effects: 未知の効果 " + str(effect.get("kind") if effect is Dictionary else effect))
			continue
		for field: String in ["min", "max"]:
			if not EquipmentGenerator.valid_number(effect.get(field), 0, 100000) or floor(float(effect[field])) != float(effect[field]):
				issues.append(path + "/basic_effects/" + field + ": 整数 0～100000 が必要")
		if EquipmentGenerator.valid_number(effect.get("min"), 0, 100000) and EquipmentGenerator.valid_number(effect.get("max"), 0, 100000) and effect.min > effect.max:
			issues.append(path + "/basic_effects: min > max")
		if effect.kind == "modify_stat" and effect.get("stat") not in DefinitionRepository.STATS:
			issues.append(path + "/basic_effects: 能力強化の能力が不正")
		if effect.kind in BATTLE_ONLY_KINDS and entry.get("scene") != "battle":
			issues.append(path + ": 「%s」は戦闘中専用です。使用場面を戦闘にしてください" % UiText.name_for(effect.kind))
		if effect.kind == "damage" and entry.get("target") != "selected_enemy":
			issues.append(path + ": 単体ダメージには対象「選択した敵」が必要")
	if entry.get("target") == "selected_enemy" and entry.get("scene") != "battle":
		issues.append(path + ": 敵を対象にするアイテムは戦闘中専用です")
	if entry.get("script") is String and not str(entry.script).strip_edges().is_empty():
		var result := compile(entry.script)
		if not result.ok:
			issues.append(path + "/script: " + result.error)
	elif entry.get("basic_effects") is Array and entry.basic_effects.is_empty():
		issues.append(path + ": 基本効果かスクリプトのどちらかが必要")
	return issues

static func has_script(definition: Dictionary) -> bool:
	return not str(definition.get("script", "")).strip_edges().is_empty()

## "" when usable, otherwise the reason (shown on the greyed-out slot).
static func can_use(definition: Dictionary, ctx: ItemContext) -> String:
	if definition.get("scene") == "battle" and not ctx.in_battle():
		return "戦闘中のみ使用できます"
	if definition.get("target") == "selected_enemy" and not ctx.has_target():
		return "対象の敵を選択してください"
	if not has_script(definition):
		return ctx.basic_reason()
	var result := compile(definition.script)
	if not result.ok:
		return "スクリプトエラー: " + result.error
	if not result.instance.has_method("can_use"):
		return ctx.basic_reason()
	var reason: Variant = result.instance.can_use(ctx)
	if reason == null:
		return ""
	return str(reason)

static func use(definition: Dictionary, ctx: ItemContext) -> void:
	if not has_script(definition):
		ctx.apply_basic()
		return
	var result := compile(definition.script)
	if result.ok:
		result.instance.use(ctx)
