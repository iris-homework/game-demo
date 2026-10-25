"""Deterministic special-card extension of neon-comic-title-v3.

ImageGen supplies only the unchanged illustrations; this renderer supplies every
frame pixel and all typography. Run from any directory with Python + Pillow.
"""
from pathlib import Path
import hashlib, json, random
from PIL import Image, ImageDraw, ImageFont, ImageOps, __version__ as PIL_VERSION

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art_sources/dancer_special_v1'
OUTPUT = ROOT / 'assets/cards/dancer_special_v1'
DATA = ROOT / 'data/cards/dancer_encounter_cards.json'
FONT = ROOT / 'assets/fonts/NotoSerifCJKsc-Bold.otf'
TITLE_FONT = SOURCE / 'fonts/NotoSansCJKsc-Bold.otf'
TEMPLATE = 'neon-comic-special-v1'
W, H = 1086, 1448
INK, PAPER = '#101016', '#d9d7cf'
PALETTES = {
    'black': {'accent':'#8290a4', 'title':'#252933', 'ink':'#d6dae3', 'dark':'#454d60', 'light':'#c8cfda'},
    'white': {'accent':'#e8e5dc', 'title':'#e8e5dc', 'ink':INK, 'dark':'#888b91', 'light':'#fffdf5'},
}

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def font(size): return ImageFont.truetype(str(FONT), size)
def polygon(draw, points, fill, edge=INK, width=5):
    draw.polygon(points, fill=fill)
    if edge: draw.line(points + [points[0]], fill=edge, width=width, joint='curve')

def write(draw, point, text, size, color, stroke=0):
    draw.text(point, text, font=font(size), fill=color, anchor='mm', stroke_width=stroke, stroke_fill=INK)

def centered(draw, center, text, face, color):
    bounds = draw.textbbox(center, text, font=face, anchor='mm')
    point = (center[0], center[1] - (bounds[1]+bounds[3])/2 + center[1])
    draw.text(point, text, font=face, fill=color, anchor='mm')
    return list(draw.textbbox(point, text, font=face, anchor='mm'))

def render(card, color):
    assert card['name'] == '灵魂链接 ' + ('黑' if color == 'black' else '白')
    assert card['type'] == 'special' and card['cost'] == 1 and 'rarity' not in card
    palette = PALETTES[color]
    accent, dark, light = (palette[k] for k in ['accent','dark','light'])
    image = Image.new('RGBA', (W,H))
    d = ImageDraw.Draw(image)
    polygon(d,[(46,35),(1028,26),(1065,57),(1062,1404),(1037,1425),(27,1430),(20,100),(46,100)],'#191b25','#08090d',12)
    for points, paint, width in [([(48,63),(1032,55),(1034,1394),(42,1404),(48,63)],accent,8),
            ([(64,79),(1014,72),(1015,1375),(59,1388),(64,79)],dark,6),
            ([(75,88),(1005,83),(1003,1366),(74,1374),(75,88)],INK,7)]:
        d.line(points,fill=paint,width=width,joint='curve')
    polygon(d,[(84,114),(992,111),(995,1354),(82,1357)],'#1c1c25',None)
    rng=random.Random(231023)
    for _ in range(25000):
        x,y=rng.randrange(84,994),rng.randrange(115,1355)
        value=rng.choice([23,26,31,34,37]); d.point((x,y),fill=(value,value,value+5,255))
    for _ in range(360):
        x,y=rng.randrange(90,990),rng.randrange(960,1340)
        d.line((x,y,x+rng.randrange(3,16),y-rng.randrange(4,18)),fill='#22232d',width=1)
    for x in (52,1022):
        for _ in range(44):
            y,length=rng.randrange(105,1380),rng.randrange(6,52)
            paint=rng.choice([accent,light,'#101219',dark])
            d.line((x+rng.randrange(-7,5),y,x+1,y+length),fill=paint,width=rng.randrange(2,7))
    d.line([(70,1382),(496,1381),(521,1390),(892,1383),(1007,1388)],fill=accent,width=9)
    d.line([(62,1395),(392,1393)],fill=accent,width=4)
    polygon(d,[(1008,1293),(1005,1367),(950,1374),(980,1330)],accent,None)
    polygon(d,[(63,1119),(79,1092),(78,1273),(68,1303)],accent,None)
    # Exact v3 sloping window. Contain the complete generated object group so the
    # diagonal chain tips stay intact; never paint over or retouch the source.
    window=[(91,275),(992,274),(991,821),(824,887),(262,887),(90,822)]
    mask=Image.new('L',(W,H)); ImageDraw.Draw(mask).polygon(window,fill=255)
    art_path=SOURCE/f'{color}_illustration.png'
    illustration=Image.open(art_path).convert('RGBA')
    art=ImageOps.contain(illustration,(884,589),method=Image.Resampling.LANCZOS)
    layer=Image.new('RGBA',(W,H),'#0c0c12')
    layer.paste(art,((W-art.width)//2,284+(589-art.height)//2))
    image.alpha_composite(Image.composite(layer,Image.new('RGBA',(W,H)),mask))
    d=ImageDraw.Draw(image)
    d.line(window+[window[0]],fill=INK,width=19,joint='curve')
    d.line(window+[window[0]],fill=PAPER,width=7,joint='curve')
    d.line([(102,290),(102,811),(272,875)],fill='#71727a',width=3)
    d.line([(979,290),(978,810),(823,875)],fill='#a7aaa9',width=3)
    polygon(d,[(114,188),(66,269),(119,257),(106,306),(220,277),(941,267),(1004,288),(997,242),(1047,222),(1029,157)],dark)
    polygon(d,[(134,133),(977,130),(1007,154),(980,264),(160,274),(126,244)],palette['title'])
    d.line([(163,145),(965,142),(989,159)],fill=light,width=4)
    d.line([(177,259),(958,250)],fill=dark,width=3)
    for _ in range(750):
        x,y=rng.randrange(165,972),rng.randrange(150,248)
        d.point((x,y),fill=rng.choice([palette['title'],dark,light]))
    title_box=centered(d,(550,200),card['name'],ImageFont.truetype(str(TITLE_FONT),96),palette['ink'])
    assert title_box[0]>224 and title_box[2]+20<873 and title_box[1]>=142 and title_box[3]<=253,title_box
    polygon(d,[(32,106),(70,72),(146,68),(201,101),(224,157),(209,227),(162,260),(89,265),(31,232),(15,164)],INK,accent,9)
    d.line([(36,112),(75,83),(137,79),(190,105)],fill=light,width=5)
    d.line([(33,219),(88,251),(157,249),(198,222)],fill=dark,width=7)
    cost_ink='#d6dae3' if color=='black' else '#e8e5dc'
    write(d,(119,160),str(card['cost']),152,cost_ink,7)
    cost_box=list(d.textbbox((119,160),'1',font=font(152),anchor='mm',stroke_width=7))
    # A variant marker, deliberately not a C/B/A/S rarity badge.
    d.ellipse((873,70,1057,254),fill=INK,outline=accent,width=9)
    badge_box=centered(d,(965,162),'黑' if color=='black' else '白',font(104),cost_ink)
    assert all((x-965)**2+(y-162)**2<82**2 for x in (badge_box[0],badge_box[2]) for y in (badge_box[1],badge_box[3])),badge_box
    polygon(d,[(400,853),(677,853),(711,895),(682,936),(403,936),(372,895)],palette['title'],INK,6)
    d.line([(413,864),(668,864)],fill=light,width=3)
    write(d,(542,891),'特殊',65,palette['ink'])
    # Keep source rules verbatim, with the same font/area as all forty cards.
    rules=card['cardText']; lines=[rules[:8],rules[8:]]
    assert ''.join(lines)==rules and '\\n' not in rules and all(lines)
    boxes=[]
    for index,line in enumerate(lines):
        y=1136+(index-.5)*90
        write(d,(544,y),line,70,'#f5f0e7',2)
        box=list(d.textbbox((544,y),line,font=font(70),anchor='mm',stroke_width=2))
        assert 118<=box[0]<box[2]<=971 and 956<=box[1]<box[3]<=1325,box
        boxes.append(box)
    assert image.getpixel((0,0))[3]==0 and image.getpixel((544,1300))[3]==255
    path=OUTPUT/f"{card['id']}.png";image.save(path)
    return {'definition':card,'path':str(path.relative_to(ROOT)),'sha256':sha(path),
        'illustration':str(art_path.relative_to(ROOT)),'illustrationSha256':sha(art_path),
        'titleBounds':title_box,'variantBounds':badge_box,'costBounds':cost_box,
        'rulesLines':lines,'rulesBounds':boxes,'canvas':[W,H],'mode':image.mode,
        'userAcceptance':'pending','visualReview':'pending'}

def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    cards=json.loads(DATA.read_text())
    records=[render(cards[f'dancer_{color}_card'],color) for color in ['black','white']]
    config={'schemaVersion':1,'templateId':TEMPLATE,'canvas':[W,H],
        'font':'res://assets/fonts/NotoSerifCJKsc-Bold.otf',
        'cards':{r['definition']['id']:{'path':'res://'+r['path'],'definition':r['definition']} for r in records}}
    (ROOT/'data/cards/card_faces_special.json').write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n')
    manifest={'templateId':TEMPLATE,'parentTemplate':'neon-comic-title-v3','date':'2026-10-25',
        'rendererSha256':sha(__file__),'sourceDefinitionSha256':sha(DATA),'fonts':{str(p.relative_to(ROOT)):sha(p) for p in [FONT,TITLE_FONT]},
        'software':{'pillow':PIL_VERSION},'cards':records}
    (OUTPUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    # Delivery previews are deterministic layout artifacts, not engine captures.
    for width,label in [(362,'large'),(173,'hand')]:
        gap=22; sheet=Image.new('RGB',(width*2+gap*3,round(width*H/W)+gap*2),'#11141d')
        for i,r in enumerate(records):
            im=Image.open(ROOT/r['path']).convert('RGBA');im.thumbnail((width,round(width*H/W)),Image.Resampling.LANCZOS)
            sheet.paste(im,(gap+(width+gap)*i,gap),im)
        preview_dir=SOURCE/'previews'; preview_dir.mkdir(exist_ok=True)
        sheet.save(preview_dir/f'preview_{label}.png')
    print(json.dumps({'cards':len(records),'canvas':[W,H],'template':TEMPLATE,'verbatimRules':True},ensure_ascii=False))

if __name__=='__main__':main()
