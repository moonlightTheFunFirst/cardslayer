"""Regenerate original prototype definitions; never run over edited data implicitly."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'data'

def effect(kind, value, target='self', formula='', scaling=0, stat='strength'):
    return dict(type=kind, value=value, target=target, formula_id=formula, scaling=scaling, stat=stat)

def damage(value, scaling, magic=False, target='selected_enemy'):
    return effect('damage', value, target, 'magic_damage' if magic else 'physical_damage', scaling)

cards = []
def card(id, name, ap, mp, target, effects, description, category='attack'):
    cards.append(dict(id=id, name=name, ap=ap, mp=mp, target=target, effects=effects, description=description, category=category, image_path=''))
card('strike','斬撃',1,0,'selected_enemy',[damage(6,.5)],'力を乗せた一撃。')
card('guard','防御',1,0,'self',[effect('block',8)],'ブロックを8得る。','support')
card('heavy_strike','強打',2,0,'selected_enemy',[damage(14,1)],'重い一撃を叩き込む。')
card('fireball','火球',1,3,'selected_enemy',[damage(10,.8,True)],'知恵に応じた魔法攻撃。')
card('sweep','薙ぎ払い',2,0,'all_enemies',[damage(5,.4,target='all_enemies')],'生存する敵全体を攻撃。')
card('insight','洞察',1,0,'self',[effect('draw',2)],'山札から2枚引く。','support')
card('heal','癒し',1,4,'self',[effect('heal',10)],'HPを10回復。','support')
card('focus','精神集中',1,0,'self',[effect('restore_mp',4)],'MPを4回復。','support')
card('poison_stab','毒の刃',1,0,'selected_enemy',[damage(3,.3),effect('apply_poison',3,'selected_enemy')],'ダメージを与え、生存していれば毒3。')
card('battle_cry','戦意',1,0,'self',[effect('modify_stat',2)],'戦闘中、力を2増やす。','buff')
enemies = []
for id,name,hp,power,xp,gold,actions in [
    ('mossling','苔の小鬼',20,2,12,8,[('ひっかく',[damage(3,.5,target='player')]),('身を守る',[effect('block',4)])]),
    ('thorn','棘の獣',24,3,15,10,[('突進',[damage(4,.5,target='player')]),('毒の棘',[effect('apply_poison',2,'player')])]),
    ('wisp','灯火の霊',18,2,14,9,[('火花',[damage(3,.5,True,'player')]),('蓄火',[effect('modify_stat',1,stat='wisdom')])]),
    ('warden','朽ち森の守護者',65,5,40,30,[('枝の鉄槌',[damage(6,.5,target='player')]),('樹皮',[effect('block',7)]),('腐蝕',[damage(4,.5,target='player'),effect('apply_poison',2,'player')])]),
]:
    enemies.append(dict(id=id,name=name,hp=hp,strength=power,wisdom=power,xp=xp,gold=gold,actions=[dict(name=n,effects=e) for n,e in actions]))
affixes = [dict(id=id,name=name,stat=stat,min=lo,max=hi,weight=10) for id,name,stat,lo,hi in [('vital','生命','max_hp',3,10),('arcane','魔力','max_mp',1,4),('mighty','剛力','strength',1,3),('sage','賢者','wisdom',1,3)]]
items=[]
for id,name,slot,bonuses,requirements in [('sword','旅人の剣','weapon',{'strength':2},{}),('staff','灰木の杖','weapon',{'wisdom':2},{}),('vest','革の胴衣','armor',{'max_hp':8},{}),('robe','修練の衣','armor',{'max_mp':3},{}),('ring','力の指輪','accessory',{'strength':1},{'strength':5}),('charm','灯火のお守り','accessory',{'wisdom':1,'max_hp':3},{'wisdom':5})]:
    items.append(dict(id=id,name=name,slot=slot,bonuses=bonuses,requirements=requirements,level=1,affixes=[a['id'] for a in affixes]))
areas=[dict(id='forest',name='朽ち森',start='start',boss='boss',nodes=[dict(id=id,enemies=es,next=ns) for id,es,ns in [('start',[],['a','b']),('a',['mossling'],['c']),('b',['wisp'],['c']),('c',['thorn','mossling'],['boss']),('boss',['warden'],[])]])]
formulas=[dict(id='physical_damage',expression='base + strength * scaling'),dict(id='magic_damage',expression='base + wisdom * scaling')]
rules=[dict(id='combat',ap=3,initial_hand=5,draw=1,hand_limit=10,mp_regen=2,starter_deck=['strike']*6+['guard']*6+[c['id'] for c in cards[2:]],loot_bases=[i['id'] for i in items],rarity_weights=dict(common=70,magic=25,rare=5))]
from loot_samples import add_loot_rules
add_loot_rules(items, affixes, rules)
for group in ['cards','enemies','items','affixes','areas','formulas','rules']:
    (ROOT/f'{group}.json').write_text(json.dumps(dict(schema_version=1,entries=globals()[group]),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
