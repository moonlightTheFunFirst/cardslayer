class_name DefinitionModels
extends RefCounted

# Construct only after DefinitionRepository validation. JSON dictionaries remain
# the editable/serializable representation; these records are runtime definitions.
class Effect extends RefCounted:
	var kind: String
	var target: String
	var value: int
	var scaling: float
	var formula_id: String
	var stat: String
	func _init(raw: Dictionary) -> void:
		kind = raw.type
		target = raw.target
		value = int(raw.value)
		scaling = float(raw.get("scaling", 0))
		formula_id = raw.get("formula_id", "")
		stat = raw.get("stat", "strength")

class Card extends RefCounted:
	var id: String
	var name: String
	var ap: int
	var mp: int
	var target: String
	var effects: Array[Effect] = []
	func _init(raw: Dictionary) -> void:
		id = raw.id
		name = raw.name
		ap = int(raw.ap)
		mp = int(raw.mp)
		target = raw.target
		for effect: Dictionary in raw.effects:
			effects.append(Effect.new(effect))

class Enemy extends RefCounted:
	var id: String
	var name: String
	var hp: int
	var strength: int
	var wisdom: int
	var xp: int
	var gold: int
	var actions: Array[Dictionary] = []
	func _init(raw: Dictionary) -> void:
		id = raw.id
		name = raw.name
		hp = int(raw.hp)
		strength = int(raw.strength)
		wisdom = int(raw.wisdom)
		xp = int(raw.xp)
		gold = int(raw.gold)
		actions.assign(raw.actions.duplicate(true))

class Item extends RefCounted:
	var id: String
	var slot: String
	var level: int
	var bonuses: Dictionary[String, int] = {}
	var requirements: Dictionary[String, int] = {}
	var affixes: Array[String] = []
	func _init(raw: Dictionary) -> void:
		id = raw.id
		slot = raw.slot
		level = int(raw.level)
		for key: String in raw.bonuses:
			bonuses[key] = int(raw.bonuses[key])
		for key: String in raw.requirements:
			requirements[key] = int(raw.requirements[key])
		affixes.assign(raw.affixes)

class Affix extends RefCounted:
	var id: String
	var stat: String
	var minimum: int
	var maximum: int
	var weight: int
	func _init(raw: Dictionary) -> void:
		id = raw.id
		stat = raw.stat
		minimum = int(raw.min)
		maximum = int(raw.max)
		weight = int(raw.weight)

class Area extends RefCounted:
	var id: String
	var start: String
	var boss: String
	var nodes: Array[Dictionary] = []
	func _init(raw: Dictionary) -> void:
		id = raw.id
		start = raw.start
		boss = raw.boss
		nodes.assign(raw.nodes.duplicate(true))

class Formula extends RefCounted:
	var id: String
	var expression: String
	func _init(raw: Dictionary) -> void:
		id = raw.id
		expression = raw.expression

class Rules extends RefCounted:
	var ap: int
	var initial_hand: int
	var draw: int
	var hand_limit: int
	var mp_regen: int
	func _init(raw: Dictionary) -> void:
		ap = int(raw.ap)
		initial_hand = int(raw.initial_hand)
		draw = int(raw.draw)
		hand_limit = int(raw.hand_limit)
		mp_regen = int(raw.mp_regen)

var cards: Dictionary[String, Card] = {}
var enemies: Dictionary[String, Enemy] = {}
var items: Dictionary[String, Item] = {}
var affixes: Dictionary[String, Affix] = {}
var areas: Dictionary[String, Area] = {}
var formulas: Dictionary[String, Formula] = {}
var rules: Rules

func _init(source: Dictionary) -> void:
	for raw: Dictionary in source.cards.entries:
		cards[raw.id] = Card.new(raw)
	for raw: Dictionary in source.enemies.entries:
		enemies[raw.id] = Enemy.new(raw)
	for raw: Dictionary in source.items.entries:
		items[raw.id] = Item.new(raw)
	for raw: Dictionary in source.affixes.entries:
		affixes[raw.id] = Affix.new(raw)
	for raw: Dictionary in source.areas.entries:
		areas[raw.id] = Area.new(raw)
	for raw: Dictionary in source.formulas.entries:
		formulas[raw.id] = Formula.new(raw)
	for raw: Dictionary in source.rules.entries:
		if raw.id == "combat":
			rules = Rules.new(raw)
