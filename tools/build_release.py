#!/usr/bin/env python3
"""Build standalone desktop releases in an isolated runtime-only project (macOS host)."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DIRS = ("assets", "data", "scenes", "scripts", "shaders",
                "enemy_asset_pipeline/runtime", "enemy_asset_pipeline/published")
EXCLUDED = ("assets/audio/incoming/", "enemy_asset_pipeline/published/backups/", "scripts/tools/")
PREVIEWS = {"scenes/combat_stage_demo.tscn", "scenes/battle_scenery_preview.tscn",
            "scripts/combat/stage_demo.gd", "enemy_asset_pipeline/runtime/audio_preview_bank.gd",
            "enemy_asset_pipeline/runtime/audio_scene_hooks.gd"}


def sha256(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def run(command, log):
    with log.open("w") as stream:
        subprocess.run([str(x) for x in command], stdout=stream, stderr=subprocess.STDOUT, check=True)
    # Godot can exit successfully even when individual scripts fail to parse.
    output = log.read_text(errors="replace")
    if "SCRIPT ERROR:" in output or "ERROR:" in output:
        raise RuntimeError("Godot reported an error; inspect " + str(log))


def stage_project(stage):
    manifest = {}
    for folder in RUNTIME_DIRS:
        for source in sorted((ROOT / folder).rglob("*")):
            if not source.is_file():
                continue
            relative = source.relative_to(ROOT).as_posix()
            if (relative.startswith(EXCLUDED) or relative.removesuffix(".uid") in PREVIEWS
                    or source.name == ".DS_Store" or source.suffix in {".md", ".tmp"}
                    or (relative.startswith("assets/") and source.suffix == ".json"
                        and relative != "assets/icons/map/locations.json")):
                continue
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            manifest[relative] = sha256(source)
    for name in ("project.godot", "export_presets.cfg"):
        shutil.copy2(ROOT / name, stage / name)
        manifest[name] = sha256(ROOT / name)
    return manifest


def player_files(folder, platform):
    licenses = folder / "Licenses"
    licenses.mkdir()
    for source in sorted((ROOT / "tools/release_licenses").glob("*.txt")):
        shutil.copy2(source, licenses / source.name)
    for name, source in {
        "NotoSans-LICENSE.txt": "assets/fonts/LICENSE.txt",
        "NotoSerif-LICENSE.txt": "assets/fonts/NotoSerifCJKsc-LICENSE.txt",
        "XSXB-LICENSE.txt": "enemy_asset_pipeline/runtime/LICENSE-XSXB.txt",
        "Ruina-RIGHTS.txt": "assets/audio/combat/ruina_reference/RIGHTS.txt",
        "Ruina-sources.json": "assets/audio/combat/ruina_reference/sources.json",
    }.items():
        shutil.copy2(ROOT / source, licenses / name)
    for source in sorted((ROOT / "assets/audio/game/licenses").glob("*.txt")):
        shutil.copy2(source, licenses / source.name)
    launch = ("完整解压后，双击 MidnightCommission.exe。请保持同目录的 MidnightCommission.pck 与 exe 放在一起。"
              if platform == "Windows" else
              "解压后，双击 MidnightCommission.app；也可以先拖入“应用程序”。兼容 Intel 与 Apple 芯片。\n"
              "此试玩包为临时签名，未做 Apple 公证。若下载后被系统拦截，请在“系统设置 → 隐私与安全性”中允许此次打开。")
    text = """午夜委托 · 第一周 Demo
游戏版本：0.4.0-noren-cards；内容构建日期：%s

启动：%s
无需安装 Godot，无需联网。Windows 使用 64 位系统；Mac 的 Intel 版本要求 macOS 11+，Apple 芯片要求 macOS 13+。
首次进入可选“新的委托”开始冒险，也可选“战斗演练”。

操作：点击卡牌再点目标，或拖动卡牌至目标；右键/Esc 取消；数字 1～9/0 选牌；点击结束回合；点击牌堆查看。
退出时请使用游戏内菜单，让程序完成存档。发行包不附带个人存档。
存档位置：Windows 为 %%APPDATA%%/MidnightCommissionDemo；macOS 为 ~/Library/Application Support/MidnightCommissionDemo。
与工程试玩共用该存档目录，已有进度会继续保留。删除或移动程序不会删除进度。

许可与来源见 Licenses。现用 Balatro 和 Library of Ruina 音频尚未确立公开再分发许可；本包不代表已完成对外发布的版权审核。
Godot 引擎及其第三方组件、Noto 字体、XSXB 的许可随包附带。
""" % (datetime.now().astimezone().strftime("%Y-%m-%d %z"), launch)
    (folder / "开始游玩.txt").write_text(text, encoding="utf-8-sig")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--output", type=Path, required=True, help="New directory; existing output is never overwritten")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    evidence = output / "构建记录"
    evidence.mkdir()
    stage = Path(tempfile.mkdtemp(prefix="midnight-release-"))
    manifest = stage_project(stage)
    (evidence / "source-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    metadata = {"source": str(ROOT), "stage": str(stage), "godot": subprocess.check_output([args.godot, "--version"], text=True).strip(),
                "commit": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()}
    (evidence / "build.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
    print("Isolated build project:", stage, flush=True)
    run([args.godot, "--headless", "--path", stage, "--editor", "--import", "--quit"], evidence / "import.log")
    for platform, preset, executable in [("Windows", "Windows Desktop", "MidnightCommission.exe"),
                                         ("macOS", "macOS", "MidnightCommission.app")]:
        folder = output / ("MidnightCommission-" + platform)
        folder.mkdir()
        run([args.godot, "--headless", "--path", stage, "--export-release", preset, folder / executable], evidence / (platform + "-export.log"))
        player_files(folder, platform)
        archive = output / (folder.name + ".zip")
        if platform == "macOS":
            subprocess.run(["ditto", "-c", "-k", "--keepParent", "--norsrc", str(folder), str(archive)], check=True)
        else:
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
                for file in sorted(folder.rglob("*")):
                    if file.is_file():
                        bundle.write(file, file.relative_to(output))
        print("Exported:", archive, flush=True)
    archives = {p.name: {"bytes": p.stat().st_size, "sha256": sha256(p)} for p in output.glob("*.zip")}
    (output / "SHA256SUMS.txt").write_text("".join(v["sha256"] + "  " + k + "\n" for k, v in archives.items()))
    (evidence / "archives.json").write_text(json.dumps(archives, ensure_ascii=False, indent=2))
    print("Done:", output, flush=True)


if __name__ == "__main__":
    main()
