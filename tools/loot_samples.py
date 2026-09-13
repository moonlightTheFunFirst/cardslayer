"""Initial values for spec 17–19, used only by explicit sample regeneration."""
def add_loot_rules(items, affixes, rules):
    changes = {
        'sword': ('旅人の剣', 'right_hand'), 'staff': ('灰木の両手杖', 'two_handed'),
        'vest': ('革の胴衣', 'body'), 'robe': ('修練の衣', 'body'),
        'ring': ('剛力の籠手', 'arms'), 'charm': ('灯火の兜', 'head'),
    }
    for item in items:
        item['name'], item['slot'] = changes[item['id']]
        item['level_growth'] = {stat: round(value * .2, 2) for stat, value in item['bonuses'].items()}
    for id, name, slot, bonuses in [('shield', '鉄縁の盾', 'left_hand', {'max_hp': 6}), ('dagger', '守りの短剣', 'left_hand', {'strength': 1}), ('boots', '旅人のブーツ', 'feet', {'agility': 2})]:
        items.append(dict(id=id, name=name, slot=slot, bonuses=bonuses, requirements={}, level=1,
                          level_growth={stat: round(value * .2, 2) for stat, value in bonuses.items()}, affixes=[]))
    for id, name, stat, minimum, maximum in [
        ('swift', '俊足', 'agility', 1, 3), ('lucky', '幸運', 'luck', 1, 3),
        ('stout', '頑健', 'max_hp', 2, 8), ('lucid', '明晰', 'max_mp', 1, 3),
        ('blue_star', '蒼星の祝福', 'wisdom', 6, 12),
    ]:
        affixes.append(dict(id=id, name=name, stat=stat, min=minimum, max=maximum, weight=10))
    for item in items:
        item['affixes'] = [a['id'] for a in affixes]
    counts = {'common': {'1': 100}, 'magic': {'1': 70, '2': 30},
              'rare': {'3': 7000, '4': 2400, '5': 590, '6': 9, '7': 1},
              'legendary': {'1': 40, '2': 60}, 'unique': {'1': 40, '2': 60}}
    rarities = []
    for rarity, count_weights in counts.items():
        weights, ranges = {}, {}
        for affix in affixes:
            id = affix['id']
            weights[id] = (1 if rarity == 'magic' else 0) if id == 'blue_star' else 100
            high = affix['max']
            ranges[id] = dict(min=affix['min'], max=high, exception_chance=1 if rarity == 'common' else 0,
                              exception_min=high+1, exception_max=high*2)
        rarities.append(dict(id=rarity, count_weights=count_weights, affix_weights=weights, value_ranges=ranges))
    rules[0]['loot_bases'] = [item['id'] for item in items]
    rules[0]['rarity_weights'] = dict(common=70, magic=25, rare=5, legendary=0, unique=0)
    rules.append(dict(id='loot', rarities=rarities))
