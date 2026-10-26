"""Update only the deterministic v3 rules panel from the owning card data.

Keeps the existing frame, title and illustration pixels. Complete definitions
are rebound only after PNG/layout validation; frozen mismatches still fall back.
Run with --output-dir to retain per-card hashes, bounds and before PNGs.
"""
from pathlib import Path
import argparse, hashlib, json, random, re
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT = Path(__file__).resolve().parents[2]
AREA = (118, 956, 971, 1325)
SIZES = (70, 66, 62, 58, 54, 50, 46, 42, 38, 36)
PREFERRED_LINES = {
    "noren_05": [
        "获得2颗弹药。",
        "消耗。"
    ],
    "noren_06": [
        "获得2颗弹药",
        "和8点格挡。"
    ],
    "noren_11": [
        "获得11点格挡。",
        "近身技：获得1颗弹药。",
        "远程技：对一名敌人",
        "施加1层虚弱。"
    ],
    "noren_12": [
        "消耗另一张手牌，",
        "获得3颗弹药。"
    ],
    "noren_13": [
        "造成10点伤害。"
    ],
    "noren_14": [
        "造成6点伤害。",
        "近身技：施加1层虚弱。"
    ],
    "noren_15": [
        "下一张攻击牌的",
        "每段基础伤害增加5。",
        "可叠加，跨回合保留。消耗。"
    ],
    "noren_16": [
        "造成9点伤害。",
        "近身技：抽2张牌。"
    ],
    "noren_17": [
        "造成16点伤害。",
        "近身技：额外获得",
        "2颗弹药。"
    ],
    "noren_18": [
        "获得2颗弹药。",
        "下一张攻击牌的",
        "每段基础伤害增加4。",
        "可叠加，跨回合保留。"
    ],
    "noren_19": [
        "造成8点伤害，",
        "施加2层虚弱。"
    ],
    "noren_21": [
        "造成8点伤害。",
        "远程技：若打出本牌前",
        "恰好拥有1颗弹药，",
        "本牌基础伤害增加4。"
    ],
    "noren_25": [
        "造成14点伤害。",
        "远程技：若目标用牌前",
        "生命≤50%，基础伤害+8。"
    ],
    "noren_27": [
        "造成6点伤害，",
        "攻击结束后施加2层裂伤。"
    ],
    "noren_29": [
        "造成14点伤害，",
        "攻击结束后施加4层裂伤。"
    ],
    "noren_31": [
        "获得8点格挡。",
        "若自身没有弹反，",
        "获得1层弹反。"
    ],
    "noren_32": [
        "获得14点格挡。",
        "若自身弹反少于2层，",
        "获得1层弹反。"
    ],
    "noren_33": [
        "获得16点格挡和1层弹反。"
    ],
    "noren_37": [
        "造成6点伤害，",
        "然后触发2次裂伤。",
        "近战与远程均生效；",
        "远程合计触发2次。"
    ],
    "noren_38": [
        "对所有敌人造成6点伤害，",
        "全部攻击结束后，",
        "对所有敌人施加3层裂伤。"
    ],
    "noren_40": [
        "本场战斗中，",
        "近战每段攻击命中后",
        "施加1层裂伤。"
    ]
}
FONT = ROOT / "assets/fonts/NotoSerifCJKsc-Bold.otf"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def panel():
    # Same seed, ranges and drawing order as the original v3 renderer.
    image = Image.new("RGBA", (1086, 1448), "#1c1c25")
    draw = ImageDraw.Draw(image)
    rng = random.Random(231023)
    for _ in range(25000):
        x, y = rng.randrange(84, 994), rng.randrange(115, 1355)
        value = rng.choice([23, 26, 31, 34, 37])
        draw.point((x, y), fill=(value, value, value + 5, 255))
    for _ in range(360):
        x, y = rng.randrange(90, 990), rng.randrange(960, 1340)
        draw.line((x, y, x + rng.randrange(3, 16), y - rng.randrange(4, 18)), fill="#22232d", width=1)
    return image.crop(AREA)

def wrap(text, font):
    lines = []
    for paragraph in text.split("\n"):
        sentences = re.findall(r"[^。；]*[。；]|[^。；]+$", paragraph)
        if not sentences:
            lines.append("")
        for sentence in sentences:
            tokens = re.findall(r"\d+(?:\.\d+)?(?:[ ]*(?:点|层|张|颗|次|倍|回合|%))?|[^\d]", sentence)
            line = ""
            for token in tokens:
                if line and font.getlength(line + token) > 826 and token[0] not in "。，；：、！？%）〕】”’ ":
                    lines.append(line)
                    line = ""
                line += token
            lines.append(line)
    assert "".join(lines) == text.replace("\n", "")
    return lines

def render(image, text, preferred=None):
    if any(ord(c) < 32 and c != "\n" for c in text) or "\\n" in text:
        raise ValueError("Invalid rules text")
    result = image.copy()
    result.paste(panel(), AREA)
    draw = ImageDraw.Draw(result)
    for size in SIZES:
        font = ImageFont.truetype(str(FONT), size)
        lines = preferred or wrap(text, font)
        assert "".join(lines) == text.replace("\n", "")
        if any(font.getlength(line) > 826 for line in lines) or len(lines) * (size + 20) > 365:
            continue
        baseline = 1114 - (len(lines) - 1) * (size + 20) / 2
        bounds = [draw.textbbox((543, baseline + i * (size + 20)), line, font=font, anchor="mm", stroke_width=2)
                  for i, line in enumerate(lines)]
        if all(118 <= b[0] and b[2] <= 971 and 956 <= b[1] and b[3] <= 1325 for b in bounds):
            break
    else:
        raise ValueError("Rules do not fit the v3 panel")
    for i, line in enumerate(lines):
        draw.text((543, baseline + i * (size + 20)), line, font=font, fill="#eeede5", anchor="mm", stroke_width=2, stroke_fill="#101016")
    outside = ImageChops.difference(result, image)
    outside.paste((0, 0, 0, 0), AREA)
    assert not any(channel.getbbox() for channel in outside.split()), "Pixels outside rules changed"
    return result, {"fontSize": size, "lines": lines, "bounds": bounds, "verbatim": True, "outsideRulesUnchanged": True}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    binding_path = ROOT / "data/cards/card_faces_no_character.json"
    bindings = json.loads(binding_path.read_text())
    assert bindings["templateId"] == "neon-comic-title-v3"
    cards = json.loads((ROOT / "data/cards/cards.json").read_text())
    records = []
    for card in cards:
        entry = bindings["cards"][card["id"]]
        if entry["definition"] == card:
            continue
        if card["rarity"] == "C":
            raise ValueError("Basic cards must remain unchanged")
        path = ROOT / entry["path"].removeprefix("res://")
        before_bytes = path.read_bytes()
        before = Image.open(path).convert("RGBA")
        assert before.size == (1086, 1448)
        updated, layout = render(before, card["cardText"], PREFERRED_LINES.get(card["id"]))
        (args.output_dir / (card["id"] + "-before.png")).write_bytes(before_bytes)
        record = {"id": card["id"], "beforeSha256": sha(path), "oldDefinition": entry["definition"],
                  "definition": card, "fontSha256": sha(FONT), "layout": layout,
                  "visualReview": "pending", "userAcceptance": "pending"}
        updated.save(path)
        with Image.open(path) as check:
            assert check.mode == "RGBA" and check.size == (1086, 1448)
        record["sha256"] = sha(path)
        records.append(record)
        entry["definition"] = card
    binding_path.write_text(json.dumps(bindings, ensure_ascii=False, indent=2) + "\n")
    report = {"templateId": bindings["templateId"], "cardsUpdated": len(records), "rulesArea": AREA, "records": records}
    (args.output_dir / "card-rules-manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"cardsUpdated": len(records), "allRulesVerbatim": True, "outsideRulesUnchanged": True}))

if __name__ == "__main__":
    main()
