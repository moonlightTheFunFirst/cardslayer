class_name UiText
extends RefCounted

const NAMES: Dictionary = {
	"head": "頭（兜）", "body": "胴（鎧）", "arms": "腕（籠手）", "right_hand": "武器（右）", "left_hand": "武器・盾（左）", "two_handed": "両手武器（左右）", "feet": "足（ブーツ）",
	"legendary": "レジェンダリー", "unique": "ユニーク", "level_growth": "1レベルごとの成長", "count_weights": "個数の抽選重み", "affix_weights": "候補ごとの抽選重み", "value_ranges": "等級ごとの数値範囲", "rarities": "等級設定", "exception_chance": "特別ロール確率（%）", "exception_min": "特別ロール最小値", "exception_max": "特別ロール最大値",
	"damage": "ダメージ", "block": "ブロック", "heal": "HP回復", "draw": "ドロー", "restore_mp": "MP回復", "apply_poison": "毒付与", "modify_stat": "能力強化",
	"self": "自分", "player": "英雄", "selected_enemy": "選択した敵", "all_enemies": "敵全体",
	"weapon": "武器", "armor": "防具", "accessory": "装飾品", "common": "コモン", "magic": "マジック", "rare": "レア",
	"max_hp": "最大HP", "max_mp": "最大MP", "strength": "力", "wisdom": "知恵", "agility": "敏捷", "luck": "運",
	"id": "ID", "name": "名前", "description": "説明", "image_path": "画像パス", "category": "カテゴリ", "attack": "攻撃", "support": "補助", "buff": "強化",
	"ap": "AP", "mp": "MP", "hp": "HP", "target": "対象", "type": "効果種別", "value": "基礎値", "scaling": "係数", "formula_id": "計算式ID", "stat": "対象能力",
	"effects": "効果", "actions": "行動", "xp": "経験値", "gold": "ゴールド", "slot": "部位", "bonuses": "基礎補正", "requirements": "装備条件", "level": "レベル",
	"affixes": "アフィックス候補", "min": "最小値", "max": "最大値", "weight": "抽選重み", "nodes": "ノード", "enemies": "敵構成", "next": "接続先", "start": "開始ノード", "boss": "ボスノード",
	"expression": "数式", "initial_hand": "初期手札", "hand_limit": "手札上限", "mp_regen": "ターンMP回復", "starter_deck": "初期デッキ", "loot_bases": "装備抽選候補", "rarity_weights": "等級抽選重み",
	"seed": "乱数シード", "base": "基礎能力", "deck": "デッキ", "equipment": "装備", "area": "エリア"
}

static func name_for(id: String) -> String:
	return str(NAMES.get(id, id))

static func bonuses(values: Dictionary) -> String:
	var parts: Array[String] = []
	for stat: String in values:
		if values[stat] != 0:
			parts.append("%s +%d" % [name_for(stat), values[stat]])
	return "、".join(parts) if not parts.is_empty() else "なし"
