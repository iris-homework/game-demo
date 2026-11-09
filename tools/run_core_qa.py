#!/usr/bin/env python3
"""Run core regressions sequentially in a copied Godot project and unique QA user dir."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

from check_config import ROOT, validate_project

SUITES = {
    "audio": ("audio/sfx_hooks_cleanup_tests", "audio/formal_audio_tests"),
    "story": ("story/mercenary_tests", "story/run", "story/event_refresh_tests"),
    "combat": ("combat/rules/combat_tests", "combat/cards/resource_cards_tests"),
}
FAILURE = re.compile(r"SCRIPT ERROR|Parse Error|^\s*ERROR:|Assertion failed|\bchecks, [1-9]\d* failures\b|failures=[1-9]\d*", re.M)
SUMMARY = re.compile(r"(?:(\d+) checks, 0 failures|checks=(\d+) failures=0)")


def execute(command, folder, env, timeout, import_only=False, python_tests=False):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "command.json").write_text(json.dumps(command, ensure_ascii=False, indent=2))
    timed_out = False
    with (folder / "stdout.log").open("w") as stdout, (folder / "stderr.log").open("w") as stderr:
        try:
            result = subprocess.run(command, env=env, stdout=stdout, stderr=stderr, timeout=timeout)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code, timed_out = None, True
    output = (folder / "stdout.log").read_text(errors="replace") + "\n" + (folder / "stderr.log").read_text(errors="replace")
    summaries = [left or right for left, right in SUMMARY.findall(output)]
    complete = import_only or (bool(re.search(r"^OK$", output, re.M)) if python_tests else bool(summaries))
    passed = code == 0 and not timed_out and not FAILURE.search(output) and complete
    record = {"status": "passed" if passed else "failed", "exit_code": code,
              "timed_out": timed_out, "checks": int(summaries[-1]) if summaries else None,
              "completion_marker": complete}
    (folder / "result.json").write_text(json.dumps(record, indent=2))
    print(folder.name + ": " + record["status"], flush=True)
    return record


def stage_project(destination, user_name):
    def ignore(_directory, names):
        return set(names) & {".git", ".DS_Store", "__pycache__", "node_modules", "artifacts", "backups", "incoming", "vendor"}
    for name in ("assets", "data", "scripts", "scenes", "shaders", "tests", "enemy_asset_pipeline"):
        shutil.copytree(ROOT / name, destination / name, ignore=ignore)
    # Reuse imported binary resources by copying; Godot writes only to this copy.
    if (ROOT / ".godot").exists():
        shutil.copytree(ROOT / ".godot", destination / ".godot", ignore=ignore)
    settings = (ROOT / "project.godot").read_text()
    settings, count = re.subn(r'^config/custom_user_dir_name="[^"]*"$',
                             'config/custom_user_dir_name="' + user_name + '"', settings, flags=re.M)
    if count != 1 or 'config/use_custom_user_dir=true' not in settings:
        raise RuntimeError("Cannot establish an independent Godot QA user directory")
    (destination / "project.godot").write_text(settings)
    manifest = {}
    for name in ("data", "scripts", "scenes", "shaders", "tests", "enemy_asset_pipeline/runtime"):
        for path in sorted((destination / name).rglob("*")):
            if path.is_file():
                manifest[path.relative_to(destination).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_PATH") or shutil.which("godot") or shutil.which("godot4") or "/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--output", type=Path, help="new evidence directory; never overwrites an earlier run")
    parser.add_argument("--suite", choices=("audio", "story", "combat"), action="append", help="repeat to select groups; default all")
    parser.add_argument("--timeout", type=int, default=180, help="seconds per process")
    parser.add_argument("--keep-project", action="store_true")
    args = parser.parse_args(argv)
    godot = Path(args.godot).expanduser().resolve()
    if not godot.is_file():
        parser.error("Godot executable missing; use --godot or GODOT_PATH")
    if args.timeout < 1:
        parser.error("--timeout must be positive")
    stamp = datetime.now().astimezone().strftime("%Y%m%dT%H%M%S%z") + "-" + uuid.uuid4().hex[:6]
    output = (args.output or ROOT / "artifacts/qa" / ("core-" + stamp)).expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"source": str(ROOT), "output": str(output), "suites": {}, "boundaries": "headless + Dummy audio; no pixel, physical-input or listening validation"}
    config = validate_project(ROOT)
    (output / "config.json").write_text(json.dumps(config, ensure_ascii=False, indent=2))
    report["suites"]["config"] = {"status": "failed" if config["errors"] else "passed", "errors": len(config["errors"])}
    if config["errors"]:
        report["status"] = "failed"
        (output / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print("Configuration checks failed: " + str(output / "config.json"))
        return 1
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    report["suites"]["config_regression"] = execute(
        [sys.executable, "-B", "-m", "unittest", "discover", "-s", str(ROOT / "tools/tests"), "-v"],
        output / "config-regression", env, args.timeout, python_tests=True)
    stage = Path(tempfile.mkdtemp(prefix="midnight-core-qa-"))
    user_name = "MidnightCoreQA-" + uuid.uuid4().hex
    report.update(project=str(stage), user_directory_name=user_name)
    manifest = stage_project(stage, user_name)
    for path in sorted((ROOT / "tools").rglob("*.py")):
        manifest[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    (output / "source-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    env["QA_OUT_DIR"] = str(output)
    command = [str(godot), "--headless", "--audio-driver", "Dummy", "--path", str(stage)]
    report["suites"]["import"] = execute(command + ["--editor", "--import", "--quit"], output / "import", env, args.timeout, import_only=True)
    if report["suites"]["import"]["status"] == "passed":
        for group in dict.fromkeys(args.suite or SUITES):
            for scene in SUITES[group]:
                folder = output / scene.replace("/", "-")
                env["QA_OUT_DIR"] = str(folder)
                report["suites"][scene] = execute(command + ["res://tests/" + scene + ".tscn"], folder, env, args.timeout)
    report["status"] = "passed" if all(item["status"] == "passed" for item in report["suites"].values()) else "failed"
    if report["status"] == "passed" and not args.keep_project:
        shutil.rmtree(stage)
    report["project_retained"] = stage.exists()
    (output / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print("CORE QA: " + report["status"] + "; evidence: " + str(output))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
