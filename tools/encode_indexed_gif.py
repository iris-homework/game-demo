#!/usr/bin/env python3
"""Encode an indexed GIF from explicit palette indices, then verify the result.

This is a format-only encoder. It rebuilds every frame from caller-supplied
palette indices with Image.frombytes("P", ...) plus a caller-supplied
768-integer palette, writes the GIF without re-quantizing or remapping any
index, and then decodes the source and the written GIF again to compare them
frame by frame.

Only pixels where the mask is non-zero may differ from the source. Any RGB
difference outside the mask fails verification. The script never edits art,
interpolates frames, or changes colors.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


PALETTE_BYTES = 768
DISPOSAL = 2


class EncodeError(Exception):
    """Raised for user-facing validation and encoding errors."""


def emit_error(message: str) -> None:
    print(
        json.dumps(
            {"status": "error", "error": message},
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        file=sys.stderr,
    )


def write_report(report_path: Path, report: dict[str, Any]) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def require_int(source: dict[str, Any], key: str, *, minimum: int) -> int:
    if key not in source:
        raise EncodeError(f"metadata is missing required field {key!r}")
    value = source[key]
    if isinstance(value, bool) or not isinstance(value, int):
        raise EncodeError(f"metadata {key!r} must be an integer, got {value!r}")
    if value < minimum:
        raise EncodeError(f"metadata {key!r} must be >= {minimum}, got {value!r}")
    return value


def load_metadata(metadata_path: Path) -> dict[str, Any]:
    if not metadata_path.is_file():
        raise EncodeError(f"metadata does not exist or is not a file: {metadata_path}")
    try:
        raw = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EncodeError(f"cannot read metadata JSON: {exc}") from exc
    if not isinstance(raw, dict):
        raise EncodeError("metadata root must be a JSON object")
    return raw


def validate_metadata(raw: dict[str, Any]) -> dict[str, Any]:
    width = require_int(raw, "width", minimum=1)
    height = require_int(raw, "height", minimum=1)
    frame_count = require_int(raw, "frame_count", minimum=1)
    loop = require_int(raw, "loop", minimum=0)

    durations = raw.get("durations")
    if not isinstance(durations, list) or len(durations) != frame_count:
        length = len(durations) if isinstance(durations, list) else None
        raise EncodeError(
            "metadata 'durations' must be a list with one integer millisecond "
            f"value per frame (expected {frame_count}, got {length})"
        )
    for index, duration in enumerate(durations):
        if isinstance(duration, bool) or not isinstance(duration, int):
            raise EncodeError(
                f"metadata durations[{index}] must be an integer, got {duration!r}"
            )
        if duration <= 0:
            raise EncodeError(
                f"metadata durations[{index}] must be greater than zero, got {duration!r}"
            )

    palette = raw.get("palette")
    if not isinstance(palette, list) or len(palette) != PALETTE_BYTES:
        length = len(palette) if isinstance(palette, list) else type(palette).__name__
        raise EncodeError(
            "metadata 'palette' must be "
            f"{PALETTE_BYTES} flattened RGB integers (256 triples), got {length}"
        )
    for index, value in enumerate(palette):
        if isinstance(value, bool) or not isinstance(value, int):
            raise EncodeError(
                f"metadata palette[{index}] must be an integer, got {value!r}"
            )
        if not 0 <= value <= 255:
            raise EncodeError(
                f"metadata palette[{index}] must be in 0..255, got {value!r}"
            )

    return {
        "width": width,
        "height": height,
        "frame_count": frame_count,
        "durations": [int(value) for value in durations],
        "loop": loop,
        "palette": [int(value) for value in palette],
    }


def read_binary(path: Path, *, expected_length: int, label: str) -> bytes:
    if not path.is_file():
        raise EncodeError(f"{label} does not exist or is not a file: {path}")
    data = path.read_bytes()
    if len(data) != expected_length:
        raise EncodeError(f"{label} has {len(data)} bytes, expected {expected_length}")
    return data


def build_frames(
    indices: np.ndarray, width: int, height: int, palette_bytes: bytes
) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for frame in indices:
        image = Image.frombytes("P", (width, height), frame.tobytes())
        image.putpalette(palette_bytes)
        frames.append(image)
    return frames


def encode_gif(
    frames: list[Image.Image],
    output_path: Path,
    durations: list[int],
    loop: int,
) -> None:
    created = False
    try:
        with output_path.open("xb") as handle:
            created = True
            frames[0].save(
                handle,
                format="GIF",
                save_all=True,
                append_images=frames[1:],
                duration=list(durations),
                loop=loop,
                optimize=False,
                disposal=DISPOSAL,
            )
    except FileExistsError as exc:
        raise EncodeError(
            f"refusing to overwrite existing output: {output_path}"
        ) from exc
    except Exception:
        if created:
            output_path.unlink(missing_ok=True)
        raise


def normalized_palette(image: Image.Image) -> list[int]:
    """Return the image palette as exactly 768 RGB integers, zero padded."""
    raw = image.getpalette() or []
    values = [int(value) for value in raw[:PALETTE_BYTES]]
    if len(values) < PALETTE_BYTES:
        values.extend([0] * (PALETTE_BYTES - len(values)))
    return values


def verify(
    *,
    source_path: Path,
    output_path: Path,
    meta: dict[str, Any],
    mask_bool: np.ndarray,
) -> dict[str, Any]:
    width = meta["width"]
    height = meta["height"]
    expected_count = meta["frame_count"]
    expected_durations = list(meta["durations"])
    expected_loop = meta["loop"]
    expected_palette = list(meta["palette"])

    problems: list[str] = []
    outside_per_frame: list[int] = []
    inside_per_frame: list[int] = []
    source_durations: list[Any] = []
    output_durations: list[Any] = []
    outside_total = 0
    inside_total = 0
    frame_rgb_shapes_ok = True

    with Image.open(source_path) as source, Image.open(output_path) as output:
        source_count = getattr(source, "n_frames", 1)
        output_count = getattr(output, "n_frames", 1)
        source_loop = source.info.get("loop")
        output_loop = output.info.get("loop")
        source_size = tuple(source.size)
        output_size = tuple(output.size)
        compared = min(source_count, output_count)
        source.seek(0)
        source_palette = normalized_palette(source)
        output.seek(0)
        output_palette = normalized_palette(output)

        for frame_index in range(source_count):
            source.seek(frame_index)
            source_durations.append(source.info.get("duration"))
        for frame_index in range(output_count):
            output.seek(frame_index)
            output_durations.append(output.info.get("duration"))

        for frame_index in range(compared):
            source.seek(frame_index)
            source_rgb = np.asarray(source.convert("RGB"), dtype=np.uint8)
            output.seek(frame_index)
            output_rgb = np.asarray(output.convert("RGB"), dtype=np.uint8)

            if source_rgb.shape != (height, width, 3) or output_rgb.shape != (
                height,
                width,
                3,
            ):
                frame_rgb_shapes_ok = False
                outside_per_frame.append(0)
                inside_per_frame.append(0)
                continue

            difference = np.any(source_rgb != output_rgb, axis=2)
            outside = difference & ~mask_bool
            inside = difference & mask_bool
            outside_count = int(outside.sum())
            inside_count = int(inside.sum())
            outside_total += outside_count
            inside_total += inside_count
            outside_per_frame.append(outside_count)
            inside_per_frame.append(inside_count)

    checks = {
        "metadata_frame_count_matches_source": source_count == expected_count,
        "metadata_size_matches_source": source_size == (width, height),
        "metadata_durations_match_source": source_durations == expected_durations,
        "metadata_loop_matches_source": source_loop == expected_loop,
        "output_frame_count": output_count == expected_count,
        "output_size": output_size == (width, height),
        "output_durations": output_durations == source_durations,
        "output_loop": output_loop == source_loop,
        "source_palette_matches_metadata": source_palette == expected_palette,
        "output_palette_matches_metadata": output_palette == expected_palette,
        "frame_rgb_shapes": frame_rgb_shapes_ok,
        "outside_mask_unchanged": outside_total == 0,
    }

    if source_count != expected_count:
        problems.append(
            f"source has {source_count} frames but metadata declares {expected_count}"
        )
    if source_size != (width, height):
        problems.append(f"source frame size {source_size} != metadata {width}x{height}")
    if source_durations != expected_durations:
        problems.append("re-decoded source durations differ from metadata 'durations'")
    if source_loop != expected_loop:
        problems.append(
            f"source loop {source_loop!r} != metadata loop {expected_loop!r}"
        )
    if output_count != expected_count:
        problems.append(
            f"output has {output_count} frames but expected {expected_count} "
            "(adjacent identical frames may have been merged)"
        )
    if output_size != (width, height):
        problems.append(f"output frame size {output_size} != {width}x{height}")
    if output_durations != source_durations:
        problems.append(
            "re-decoded output durations differ from the re-decoded source durations"
        )
    if output_loop != source_loop:
        problems.append(f"output loop {output_loop!r} != source loop {source_loop!r}")
    if source_palette != expected_palette:
        problems.append("source palette differs from metadata 'palette'")
    if output_palette != expected_palette:
        problems.append(
            "output palette differs from metadata 'palette' (color table changed)"
        )
    if not frame_rgb_shapes_ok:
        problems.append("one or more decoded frames had an unexpected RGB shape")
    if outside_total != 0:
        problems.append(
            f"{outside_total} pixel(s) differ outside the mask; expected 0"
        )

    status = "ok" if all(checks.values()) else "error"

    return {
        "status": status,
        "source": str(source_path),
        "output": str(output_path),
        "width": width,
        "height": height,
        "frame_count": expected_count,
        "source_frame_count": source_count,
        "output_frame_count": output_count,
        "compared_frame_count": compared,
        "frame_size": [width, height],
        "source_size": list(source_size),
        "output_size": list(output_size),
        "loop": output_loop,
        "source_loop": source_loop,
        "metadata_loop": expected_loop,
        "durations_ms": expected_durations,
        "source_durations_ms": source_durations,
        "output_durations_ms": output_durations,
        "mask_pixels": int(mask_bool.sum()),
        "outside_mask_changed_per_frame": outside_per_frame,
        "outside_mask_changed_total": outside_total,
        "inside_mask_changed_per_frame": inside_per_frame,
        "inside_mask_changed_total": inside_total,
        "palette_matches_metadata": {
            "source": source_palette == expected_palette,
            "output": output_palette == expected_palette,
        },
        "output_bytes": output_path.stat().st_size,
        "encoding": {
            "mode": "P",
            "pixels_from": "caller-supplied palette indices",
            "palette": "caller-supplied 768 flattened RGB integers",
            "requantized": False,
            "index_remapped": False,
            "optimize": False,
            "disposal": DISPOSAL,
            "save_all": True,
        },
        "checks": checks,
        "problems": problems,
    }


def run(args: argparse.Namespace) -> dict[str, Any]:
    metadata_path = Path(args.metadata).expanduser()
    indices_path = Path(args.indices).expanduser()
    mask_path = Path(args.mask).expanduser()
    source_path = Path(args.source).expanduser()
    output_path = Path(args.output).expanduser()

    meta = validate_metadata(load_metadata(metadata_path))
    width = meta["width"]
    height = meta["height"]
    frame_count = meta["frame_count"]

    mask_bytes = read_binary(mask_path, expected_length=width * height, label="mask")
    indices_bytes = read_binary(
        indices_path,
        expected_length=frame_count * width * height,
        label="indices",
    )

    if not source_path.is_file():
        raise EncodeError(
            f"source GIF does not exist or is not a file: {source_path}"
        )
    if output_path.exists():
        raise EncodeError(f"refusing to overwrite existing output: {output_path}")

    mask_bool = np.frombuffer(mask_bytes, dtype=np.uint8).reshape((height, width)) != 0
    provided_indices = np.frombuffer(indices_bytes, dtype=np.uint8).reshape(
        (frame_count, height, width)
    )

    palette_bytes = bytes(meta["palette"])
    frames = build_frames(provided_indices, width, height, palette_bytes)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    encode_gif(frames, output_path, meta["durations"], meta["loop"])

    return verify(
        source_path=source_path,
        output_path=output_path,
        meta=meta,
        mask_bool=mask_bool,
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Encode an indexed GIF from caller-supplied palette indices and "
            "verify that nothing outside the mask changed."
        )
    )
    parser.add_argument("--metadata", required=True, help="metadata JSON path")
    parser.add_argument(
        "--indices",
        required=True,
        help="raw uint8 palette indices, frame_count*width*height bytes",
    )
    parser.add_argument(
        "--mask",
        required=True,
        help="raw uint8 mask, width*height bytes (non-zero = may change)",
    )
    parser.add_argument("--source", required=True, help="original GIF path")
    parser.add_argument("--output", required=True, help="new GIF path")
    parser.add_argument("--report", required=True, help="verification report JSON path")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    report_path = Path(args.report).expanduser()

    try:
        report = run(args)
    except (EncodeError, OSError, ValueError) as exc:
        emit_error(str(exc))
        write_report(
            report_path,
            {
                "status": "error",
                "error": str(exc),
                "metadata": str(Path(args.metadata).expanduser()),
                "indices": str(Path(args.indices).expanduser()),
                "mask": str(Path(args.mask).expanduser()),
                "source": str(Path(args.source).expanduser()),
                "output": str(Path(args.output).expanduser()),
            },
        )
        return 1

    write_report(report_path, report)
    print(json.dumps(report, ensure_ascii=False, separators=(",", ":")))
    return 0 if report["status"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
