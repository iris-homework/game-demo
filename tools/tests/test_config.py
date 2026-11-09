"""Mutation regressions for authored-data diagnostics, using disposable data copies."""
import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_config
import build_release


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="midnight-config-qa-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(check_config.ROOT / "data", self.root / "data")
        # Existence-only resource fixtures avoid copying artwork or requiring Windows symlink privileges.
        def resources(value):
            if isinstance(value, str) and value.startswith("res://"):
                relative = Path(value[6:])
                if (check_config.ROOT / relative).is_file():
                    target = self.root / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.touch()
            elif isinstance(value, dict):
                for child in value.values(): resources(child)
            elif isinstance(value, list):
                for child in value: resources(child)
        for path in (self.root / "data").rglob("*.json"):
            resources(json.loads(path.read_text()))

    def mutate(self, name, edit):
        path = self.root / "data" / name
        value = json.loads(path.read_text())
        edit(value)
        path.write_text(json.dumps(value, ensure_ascii=False))

    def errors(self):
        return check_config.validate_project(self.root)["errors"]

    def rejected(self, file, field):
        errors = self.errors()
        self.assertTrue(any(item["file"] == "data/" + file and field in item["field"] for item in errors), errors)

    def test_current_data_and_intentional_placeholders(self):
        self.assertEqual(check_config.validate_project(check_config.ROOT)["errors"], [])
        report = check_config.validate_project(self.root)
        self.assertEqual(report["errors"], [])
        self.assertEqual((report["cards"], report["events"], report["battles"]), (45, 16, 14))

    def test_duplicate_array_id(self):
        self.mutate("cards/cards.json", lambda cards: cards.append(cards[0]))
        self.rejected("cards/cards.json", ".id")

    def test_duplicate_json_key_is_not_silently_overwritten(self):
        (self.root / "data/config.json").write_text('{"initialDay":1,"initialDay":2}')
        self.assertTrue(any("duplicate JSON key: initialDay" in e["message"] for e in self.errors()))

    def test_syntax_diagnostic_includes_line(self):
        (self.root / "data/config.json").write_text('{\n "initialDay": }')
        self.assertTrue(any(e["file"] == "data/config.json" and "line 2" in e["message"] for e in self.errors()))

    def test_required_field_and_boolean_cost(self):
        def edit(cards):
            del cards[0]["name"]
            cards[1]["cost"] = True
        self.mutate("cards/cards.json", edit)
        self.rejected("cards/cards.json", "[0].name")
        self.rejected("cards/cards.json", "[1].cost")

    def test_unknown_effect_and_invalid_energy(self):
        def edit(cards):
            cards[0]["effects"][0]["type"] = "not_implemented"
            cards[-2]["effects"][0]["amount"] = 0
        self.mutate("cards/cards.json", edit)
        self.rejected("cards/cards.json", "[0].effects[0].type")
        self.rejected("cards/cards.json", "[43].effects[0].amount")

    def test_unknown_buff(self):
        self.mutate("cards/cards.json", lambda cards: cards[0].update(effects=[{"type":"buff", "id":"missing", "amount":1}]))
        self.rejected("cards/cards.json", "[0].effects[0].id")

    def test_missing_resource_and_asset_reference(self):
        self.mutate("assets.json", lambda assets: assets["city"].update(path="res://assets/not-there.png"))
        self.mutate("places.json", lambda places: places[0].update(backgroundAssetId="missing"))
        self.rejected("assets.json", ".city.path")
        self.rejected("places.json", "[0].backgroundAssetId")

    def test_broken_node_and_choice_targets(self):
        def edit(events):
            events["E01"]["nodes"]["intro_01"]["next"] = "missing"
            events["E01"]["nodes"]["contract"]["choices"][0]["next"] = "missing"
        self.mutate("weeks/week1/events.json", edit)
        self.rejected("weeks/week1/events.json", ".intro_01.next")
        self.rejected("weeks/week1/events.json", ".choices[0].next")

    def test_broken_enemy_and_result_routes(self):
        def edit(battles):
            battles["B02"]["enemyIds"] = ["missing"]
            battles["B02"]["returnNodeByResult"]["win"] = "missing"
        self.mutate("battles.json", edit)
        self.rejected("battles.json", ".B02.enemyIds[0]")
        self.rejected("battles.json", ".B02.returnNodeByResult.win")

    def test_duplicate_event_across_weeks(self):
        first = json.loads((self.root / "data/weeks/week1/events.json").read_text())["E01"]
        self.mutate("weeks/week2/events.json", lambda events: events.update(E01=first))
        self.assertTrue(any("across weeks" in e["message"] for e in self.errors()))

    def test_week_index_must_cover_exactly_one_week(self):
        self.mutate("weeks/week1/week.json", lambda week: week["eventIds"].append("E17"))
        self.rejected("weeks/week1/week.json", ".eventIds")

    def test_unknown_technology_and_condition(self):
        def edit(events):
            events["E01"]["nodes"]["contract"]["choices"][0]["effects"][0]["id"] = "missing"
            events["E02"]["unlockCondition"] = {"completed":"missing"}
        self.mutate("weeks/week1/events.json", edit)
        self.rejected("weeks/week1/events.json", ".effects[0].id")
        self.rejected("weeks/week1/events.json", ".unlockCondition.completed")

    def test_wrong_containers_report_without_crashing(self):
        self.mutate("prototype/cyberware.json", lambda value: value.update(cards=123))
        self.mutate("battles.json", lambda value: value["B02"].update(eventId=[], enemyIds={}))
        self.mutate("weeks/week1/events.json", lambda value: value["E01"].update(nodes=[]))
        self.rejected("prototype/cyberware.json", ".cards")
        self.rejected("battles.json", ".B02.eventId")
        self.rejected("weeks/week1/events.json", ".E01.nodes")

    def test_nonfinite_numbers(self):
        (self.root / "data/config.json").write_text('{"initialDay":NaN}')
        self.assertTrue(any("non-finite JSON" in e["message"] for e in self.errors()))

    def test_new_adventure_required_fields_and_player_hp(self):
        self.mutate("config.json", lambda value: value.pop("initialDay"))
        self.mutate("player_characters.json", lambda value: value["noren"]["attributes"].update(maxHp=0))
        self.rejected("config.json", ".initialDay")
        self.rejected("player_characters.json", ".noren.attributes.maxHp")

    def test_enemy_loop_cannot_divide_by_zero(self):
        self.mutate("enemies/enemies.json", lambda value: value["robot"].update(intentLoopStart=3))
        self.rejected("enemies/enemies.json", ".robot.intentLoopStart")

    def test_release_preflight_rejects_before_output_or_godot(self):
        self.mutate("cards/cards.json", lambda cards: cards[0].update(cost=-1))
        destination = self.root / "should-not-be-created"
        with patch.object(build_release, "ROOT", self.root), patch.object(sys, "argv", ["build_release.py", "--output", str(destination)]), patch.object(build_release.subprocess, "check_output") as invoke:
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
                build_release.main()
            invoke.assert_not_called()
        self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
