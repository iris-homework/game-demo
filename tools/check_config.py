#!/usr/bin/env python3
"""Read-only authored-data checks; no Godot import, game startup or save access."""
import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OBJECT_FILES = (
    "assets.json", "characters.json", "player_characters.json", "config.json",
    "battles.json", "rewards.json", "place_dialogues.json", "map.json",
    "enemies/enemies.json", "enemies/combat_visuals.json", "cards/schema.json",
    "cards/dancer_encounter_cards.json", "cards/card_faces_no_character.json",
    "cards/card_faces_special.json", "prototype/combat.json", "prototype/rewards.json",
    "prototype/cyberware.json", "combat/noren.json", "card_reward_rates.json",
    "black_market.json", "technology_shop.json", "items/items.json", "cyberware/cyberware.json",
)
ARRAY_FILES = ("cards/cards.json", "places.json", "training_enemies.json", "buffs/buffs.json")


def integer(value, minimum=0):
    # JSON roundtrips may produce whole floats; booleans are never numbers here.
    return type(value) in (int, float) and math.isfinite(value) and value >= minimum and value == int(value)


class Validator:
    def __init__(self, root):
        self.root = Path(root)
        self.errors = []
        self.documents = {}

    def error(self, file, field, message):
        self.errors.append({"file": file, "field": field, "message": message})

    def load(self, name, expected=dict):
        file = "data/" + name
        try:
            def unique_object(pairs):
                result = {}
                for key, value in pairs:
                    if key in result:
                        raise ValueError("duplicate JSON key: " + key)
                    result[key] = value
                return result
            def reject_constant(value):
                raise ValueError("non-finite JSON number: " + value)
            value = json.loads((self.root / file).read_text(encoding="utf-8-sig"),
                               object_pairs_hook=unique_object, parse_constant=reject_constant)
        except (OSError, ValueError) as exc:
            self.error(file, "$", str(exc))
            value = expected()
        if not isinstance(value, expected):
            self.error(file, "$", "expected " + expected.__name__)
            value = expected()
        self.documents[name] = value
        return value

    def objects(self, value, file, field="$", keyed=False, check_id=True):
        result = {}
        if not isinstance(value, dict if keyed else list):
            self.error(file, field, "expected object dictionary" if keyed else "expected object array")
            return result
        entries = value.items() if keyed else enumerate(value)
        for key, item in entries:
            at = f"{field}.{key}" if keyed else f"{field}[{key}]"
            if not isinstance(item, dict):
                self.error(file, at, "expected object")
                continue
            identifier = item.get("id", key if keyed else None)
            if not isinstance(identifier, str) or not identifier:
                self.error(file, at + ".id", "expected nonempty ID")
                continue
            if keyed and check_id and identifier != key:
                self.error(file, at + ".id", "ID must match dictionary key")
            catalog_key = key if keyed else identifier
            if catalog_key in result:
                self.error(file, at + ".id", "duplicate ID: " + identifier)
            result[catalog_key] = item
        return result

    def ref(self, value, catalog, file, field, optional=False):
        if optional and value == "":
            return
        if not isinstance(value, str) or value not in catalog:
            self.error(file, field, "unknown reference: " + repr(value))

    def refs(self, values, catalog, file, field):
        if not isinstance(values, list):
            self.error(file, field, "expected ID array")
            return
        for index, value in enumerate(values):
            self.ref(value, catalog, file, f"{field}[{index}]")

    def schema(self, value, spec, file, field):
        """The subset used by cards/schema.json, not a general JSON Schema engine."""
        types = {"object": lambda v: isinstance(v, dict), "array": lambda v: isinstance(v, list),
                 "string": lambda v: isinstance(v, str), "integer": integer,
                 "boolean": lambda v: isinstance(v, bool)}
        kind = spec.get("type")
        if kind and (kind not in types or not types[kind](value)):
            self.error(file, field, "expected " + kind)
            return
        if "enum" in spec and value not in spec["enum"]:
            self.error(file, field, "unsupported value: " + repr(value))
        if isinstance(value, dict):
            for key in spec.get("required", []):
                if key not in value:
                    self.error(file, field + "." + key, "required field missing")
            for key, child in spec.get("properties", {}).items():
                if key in value:
                    self.schema(value[key], child, file, field + "." + key)
            for rule in spec.get("allOf", []):
                condition = rule.get("if", {})
                if all(key in value for key in condition.get("required", [])) and all(
                        value.get(key) == child.get("const") for key, child in condition.get("properties", {}).items()):
                    self.schema(value, rule.get("then", {}), file, field)
        if isinstance(value, list):
            if len(value) < spec.get("minItems", 0):
                self.error(file, field, "too few items")
            for index, item in enumerate(value):
                self.schema(item, spec.get("items", {}), file, f"{field}[{index}]")
        if isinstance(value, str) and "pattern" in spec and not re.search(spec["pattern"], value):
            self.error(file, field, "does not match " + spec["pattern"])
        if type(value) in (int, float) and (not math.isfinite(value) or value < spec.get("minimum", -math.inf) or value > spec.get("maximum", math.inf)):
            self.error(file, field, "number outside allowed range or non-finite")

    def resources(self, value, file, assets, field="$"):
        if isinstance(value, str) and value.startswith("res://"):
            relative = Path(value[6:])
            if ".." in relative.parts or relative.is_absolute() or not (self.root / relative).is_file():
                self.error(file, field, "resource file missing or outside project: " + value)
        elif isinstance(value, dict):
            for key, child in value.items():
                at = field + "." + key
                if key.endswith("AssetId") and child is not None:
                    self.ref(child, assets, file, at, optional=True)
                self.resources(child, file, assets, at)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                self.resources(child, file, assets, f"{field}[{index}]")

    def condition(self, value, file, field, events):
        if not isinstance(value, dict):
            self.error(file, field, "expected condition object")
            return
        for key, child in value.items():
            at = field + "." + key
            if key in ("all", "any"):
                if not isinstance(child, list):
                    self.error(file, at, "expected condition array")
                else:
                    for index, item in enumerate(child):
                        self.condition(item, file, f"{at}[{index}]", events)
            elif key == "completed":
                self.ref(child, events, file, at)
            elif key == "completedCount":
                if not isinstance(child, dict):
                    self.error(file, at, "expected completedCount object")
                else:
                    self.refs(child.get("ids"), events, file, at + ".ids")
                    if not integer(child.get("atLeast")):
                        self.error(file, at + ".atLeast", "expected nonnegative integer")
            elif key not in ("flag", "target", "creditsAtLeast"):
                self.error(file, at, "unknown condition")

    def story(self, story, file, at, events, battles, characters, places, rewards, technology):
        self.schema(story, {"required": ["title", "placeId", "startNodeId", "nodes"],
                            "properties": {"title": {"type": "string"}}}, file, at)
        self.ref(story.get("placeId"), places, file, at + ".placeId")
        nodes = story.get("nodes")
        if not isinstance(nodes, dict):
            self.error(file, at + ".nodes", "expected node dictionary")
            return
        self.ref(story.get("startNodeId"), nodes, file, at + ".startNodeId")
        self.condition(story.get("unlockCondition", {}), file, at + ".unlockCondition", events)
        self.refs(story.get("rewardIds", []), rewards, file, at + ".rewardIds")
        for key, node in nodes.items():
            field = at + ".nodes." + key
            if not isinstance(node, dict):
                self.error(file, field, "expected node object")
                continue
            if node.get("type", "dialogue") not in ("dialogue", "stage", "battle", "finish", "place"):
                self.error(file, field + ".type", "unknown node type")
            if "id" in node and node["id"] != key:
                self.error(file, field + ".id", "ID must match node key")
            if "next" in node:
                self.ref(node["next"], set(nodes) | {"@map"}, file, field + ".next")
            self.ref(node.get("speakerId", ""), set(characters) | {"@player"}, file, field + ".speakerId", True)
            portraits = node.get("portraits", {})
            if not isinstance(portraits, dict):
                self.error(file, field + ".portraits", "expected portrait object")
            else:
                for side, identifier in portraits.items():
                    self.ref(identifier, set(characters) | {"@player"}, file, field + ".portraits." + side, True)
            if node.get("type") == "battle":
                self.ref(node.get("battleId"), battles, file, field + ".battleId")
            choices = node.get("choices", [])
            if not isinstance(choices, list):
                self.error(file, field + ".choices", "expected choices array")
                choices = []
            containers = [(field, node)]
            for index, choice in enumerate(choices):
                here = f"{field}.choices[{index}]"
                if not isinstance(choice, dict):
                    self.error(file, here, "expected choice object")
                    continue
                self.ref(choice.get("next"), set(nodes) | {"@map"}, file, here + ".next")
                self.condition(choice.get("condition", {}), file, here + ".condition", events)
                containers.append((here, choice))
            for here, container in containers:
                actions = container.get("effects", [])
                if not isinstance(actions, list):
                    self.error(file, here + ".effects", "expected action array")
                    continue
                for index, action in enumerate(actions):
                    action_at = f"{here}.effects[{index}]"
                    if not isinstance(action, dict):
                        self.error(file, action_at, "expected action object")
                        continue
                    op = action.get("op")
                    if op not in ("setFlag", "spendCredits", "addCredits", "setTarget", "grantTechnology",
                                  "completeEvent", "healHpPercent", "advanceDay", "finishWeek", "grantReward"):
                        self.error(file, action_at + ".op", "unknown action")
                    for operation, catalog in (("grantTechnology", technology), ("completeEvent", events), ("grantReward", rewards)):
                        if op == operation:
                            self.ref(action.get("id"), catalog, file, action_at + ".id")

    def run(self):
        for name in OBJECT_FILES:
            self.load(name)
        for name in ARRAY_FILES:
            self.load(name, list)
        # Only playable weeks are runtime content; pending week3 remains a valid placeholder.
        week_files = sorted((self.root / "data/weeks").glob("*/week.json"))
        if not week_files:
            self.error("data/weeks", "$", "no week indexes")
        events, origins = {}, {}
        for path in week_files:
            week_name = path.relative_to(self.root / "data").as_posix()
            week = self.load(week_name)
            if week.get("status") == "pending":
                continue
            name = week_name.replace("week.json", "events.json")
            local = self.objects(self.load(name), "data/" + name, keyed=True)
            ids = week.get("eventIds")
            if not isinstance(ids, list) or any(not isinstance(item, str) for item in ids) or len(set(ids)) != len(ids) or set(ids) != set(local):
                self.error("data/" + week_name, "$.eventIds", "must list this week's events exactly once")
            for identifier in local:
                if identifier in events:
                    self.error("data/" + name, "$." + identifier, "duplicate event ID across weeks")
                origins[identifier] = "data/" + name
            events.update(local)
            if "bossEventId" in week:
                self.ref(week["bossEventId"], local, "data/" + week_name, "$.bossEventId")
        data = self.documents
        cards = self.objects(data["cards/cards.json"], "data/cards/cards.json")
        places = self.objects(data["places.json"], "data/places.json")
        battles = self.objects(data["battles.json"], "data/battles.json", keyed=True)
        # Phase-one definitions may intentionally share an actor ID with phase two.
        enemies = self.objects(data["enemies/enemies.json"], "data/enemies/enemies.json", keyed=True, check_id=False)
        buffs = self.objects(data["buffs/buffs.json"], "data/buffs/buffs.json")
        technology = self.objects(data["prototype/cyberware.json"].get("cards", []), "data/prototype/cyberware.json", "$.cards")
        characters, assets, rewards = data["characters.json"], data["assets.json"], data["rewards.json"]
        self.schema(data["config.json"], {
            "required": ["defaultPlayerCharacterId", "initialDay", "initialCredits", "developmentMode"],
            "properties": {"defaultPlayerCharacterId": {"type": "string"},
                           "initialDay": {"type": "integer", "minimum": 1, "maximum": 7},
                           "initialCredits": {"type": "integer", "minimum": 0},
                           "developmentMode": {"type": "boolean"}}}, "data/config.json", "$")
        for identifier, asset in assets.items():
            if isinstance(asset, dict) and asset.get("kind") == "pending" and asset.get("path") == "":
                continue
            if not isinstance(asset, dict) or not isinstance(asset.get("path"), str) or not asset["path"].startswith("res://"):
                self.error("data/assets.json", "$." + identifier + ".path", "project resource path required")
        for index, card in enumerate(data["cards/cards.json"]):
            self.schema(card, data["cards/schema.json"], "data/cards/cards.json", f"$[{index}]")
            if not isinstance(card, dict) or not isinstance(card.get("effects"), list):
                continue
            for n, effect in enumerate(card["effects"]):
                if not isinstance(effect, dict):
                    continue
                at = f"$[{index}].effects[{n}]"
                if effect.get("type") == "buff":
                    self.ref(effect.get("id"), buffs, "data/cards/cards.json", f"$[{index}].effects[{n}].id")
                if effect.get("type") in ("damage", "draw", "ammo") and "amount" not in effect:
                    self.error("data/cards/cards.json", at + ".amount", "required field missing")
                for key in ("amount", "hits", "rangedBonus", "bleedTriggers", "requiresBleed"):
                    if key in effect and not integer(effect[key], -999 if key == "amount" and effect.get("id", effect.get("type")) == "strength" else 0):
                        self.error("data/cards/cards.json", at + "." + key, "expected finite integer in allowed range")
        self.ref(data["config.json"].get("defaultPlayerCharacterId"), data["player_characters.json"], "data/config.json", "$.defaultPlayerCharacterId")
        for identifier, player in self.objects(data["player_characters.json"], "data/player_characters.json", keyed=True).items():
            self.schema(player, {"required": ["attributes", "startingDeck", "skills"], "properties": {
                "attributes": {"type": "object", "required": ["maxHp"], "properties": {"maxHp": {"type": "integer", "minimum": 1}}},
                "startingDeck": {"type": "array", "minItems": 1}, "skills": {"type": "array"}}}, "data/player_characters.json", "$." + identifier)
            self.ref(identifier, characters, "data/player_characters.json", "$." + identifier)
            self.refs(player.get("startingDeck"), cards, "data/player_characters.json", "$." + identifier + ".startingDeck")
            self.refs(player.get("cyberwareIds", []), technology, "data/player_characters.json", "$." + identifier + ".cyberwareIds")
        for identifier, story in events.items():
            self.story(story, origins[identifier], "$." + identifier, events, battles, characters, places, rewards, technology)
        for identifier, story in data["place_dialogues.json"].items():
            if not isinstance(story, dict):
                self.error("data/place_dialogues.json", "$." + identifier, "expected story object")
                continue
            self.story(story, "data/place_dialogues.json", "$." + identifier, events, battles, characters, places, rewards, technology)
        for identifier, battle in battles.items():
            file, at = "data/battles.json", "$." + identifier
            self.ref(battle.get("eventId"), events, file, at + ".eventId")
            self.ref(battle.get("placeId"), places, file, at + ".placeId")
            if battle.get("battleType", "normal") not in ("normal", "elite", "boss"):
                self.error(file, at + ".battleType", "unknown battle type")
            self.refs(battle.get("enemyIds"), enemies, file, at + ".enemyIds")
            self.refs(battle.get("phaseTwoEnemyIds", []), enemies, file, at + ".phaseTwoEnemyIds")
            self.refs(battle.get("participants", []), set(characters) | set(enemies) | {"@player"}, file, at + ".participants")
            routes = battle.get("returnNodeByResult")
            if not isinstance(routes, dict) or not {"win", "lose"}.issubset(routes):
                self.error(file, at + ".returnNodeByResult", "win/lose routes required")
            else:
                event = events.get(battle.get("eventId"), {}) if isinstance(battle.get("eventId"), str) else {}
                nodes = event.get("nodes", {})
                for result, target in routes.items():
                    self.ref(target, nodes if isinstance(nodes, dict) else {}, file, at + ".returnNodeByResult." + result)
        for identifier, enemy in enemies.items():
            # Combat-only actors such as the white dancer need no dialogue portrait.
            self.ref(enemy.get("characterId"), set(characters) | set(enemies), "data/enemies/enemies.json", "$." + identifier + ".characterId")
            at = "$." + identifier
            if enemy.get("maxHp") is not None and not integer(enemy["maxHp"], 1):
                self.error("data/enemies/enemies.json", at + ".maxHp", "expected positive integer or prototype null")
            sequence = enemy.get("intentSequence", [])
            if not isinstance(sequence, list):
                self.error("data/enemies/enemies.json", at + ".intentSequence", "expected intent array")
            elif sequence and (not integer(enemy.get("intentLoopStart", 0)) or enemy.get("intentLoopStart", 0) >= len(sequence)):
                self.error("data/enemies/enemies.json", at + ".intentLoopStart", "loop start must be inside the intent sequence")
        self.objects(data["training_enemies.json"], "data/training_enemies.json")
        for index, entry in enumerate(data["training_enemies.json"]):
            if isinstance(entry, dict):
                self.ref(entry.get("battleId"), battles, "data/training_enemies.json", f"$[{index}].battleId")
        offers = data["technology_shop.json"].get("offers", [])
        for identifier, offer in self.objects(offers, "data/technology_shop.json", "$.offers").items():
            self.ref(identifier, technology, "data/technology_shop.json", "$.offers." + identifier + ".id")
            if not integer(offer.get("price")):
                self.error("data/technology_shop.json", "$.offers." + identifier + ".price", "expected nonnegative integer")
        for name, value in data.items():
            if name != "cards/schema.json":
                self.resources(value, "data/" + name, assets)
        return {"files": len(data), "cards": len(cards), "events": len(events), "battles": len(battles), "errors": self.errors}


def validate_project(root=ROOT):
    return Validator(root).run()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--json", action="store_true", help="emit a machine-readable report")
    args = parser.parse_args(argv)
    report = validate_project(args.root)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        for error in report["errors"]:
            print(f'{error["file"]}:{error["field"]}: {error["message"]}')
        print(f'CONFIG: {report["files"]} files, {report["cards"]} cards, {report["events"]} events, '
              f'{report["battles"]} battles, {len(report["errors"])} errors')
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
