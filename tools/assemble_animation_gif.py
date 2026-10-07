#!/usr/bin/env python3
"""Assemble a sprite sheet or PNG frame directory into a looping GIF.

The script only crops and quantizes supplied pixels. It does not redraw,
repair, warp, add effects, or interpolate final frames.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image


FRAME_SAMPLE_LIMIT = 8
PALETTE_SAMPLE_CELL = 128


class AssemblyError(Exception):
    """Raised for user-facing assembly errors."""


def positive_int(value: str) -> int:
    try:
        number = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"expected an integer, got {value!r}") from exc
    if number <= 0:
        raise argparse.ArgumentTypeError("value must be greater than zero")
    return number


def emit_error(message: str) -> None:
    print(
        json.dumps(
            {"status": "error", "error": message},
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        file=sys.stderr,
    )


def palette_image_from_source(source: Image.Image) -> tuple[Image.Image, bytes]:
    """Quantize a source image to one 256-color palette."""
    palette_source = source.convert("RGB").quantize(
        colors=256,
        method=Image.Quantize.MEDIANCUT,
    )
    palette = bytearray(palette_source.getpalette() or [])
    palette = palette[:768]
    if len(palette) < 768:
        palette.extend([0] * (768 - len(palette)))

    palette_image = Image.new("P", (1, 1))
    palette_image.putpalette(bytes(palette))
    return palette_image, bytes(palette)


def uniform_sample_indices(total: int, limit: int) -> list[int]:
    if total <= 0:
        return []
    if total <= limit:
        return list(range(total))
    if limit <= 1:
        return [0]
    return sorted({round(index * (total - 1) / (limit - 1)) for index in range(limit)})


def build_palette_from_frame_paths(frame_paths: list[Path]) -> tuple[Image.Image, bytes]:
    """Sample at most eight frames, shrink them, and build one shared palette."""
    sample_indices = uniform_sample_indices(len(frame_paths), FRAME_SAMPLE_LIMIT)
    if not sample_indices:
        raise AssemblyError("no frames are available for palette extraction")

    mosaic = Image.new(
        "RGB",
        (PALETTE_SAMPLE_CELL * len(sample_indices), PALETTE_SAMPLE_CELL),
        (0, 0, 0),
    )
    for slot, frame_index in enumerate(sample_indices):
        with Image.open(frame_paths[frame_index]) as source:
            source.seek(0)
            source.load()
            sample = source.convert("RGB")
            sample.thumbnail(
                (PALETTE_SAMPLE_CELL, PALETTE_SAMPLE_CELL),
                Image.Resampling.LANCZOS,
            )
            left = slot * PALETTE_SAMPLE_CELL + (
                PALETTE_SAMPLE_CELL - sample.width
            ) // 2
            top = (PALETTE_SAMPLE_CELL - sample.height) // 2
            mosaic.paste(sample, (left, top))

    return palette_image_from_source(mosaic)


def collect_frame_paths(frames_dir: Path) -> list[Path]:
    if not frames_dir.is_dir():
        raise AssemblyError(f"frames directory does not exist: {frames_dir}")
    frame_paths = sorted(
        (
            path
            for path in frames_dir.iterdir()
            if path.is_file() and path.suffix.lower() == ".png"
        ),
        key=lambda path: path.name,
    )
    if not frame_paths:
        raise AssemblyError(f"no PNG frames found in: {frames_dir}")
    return frame_paths


def read_gif(path: Path) -> dict[str, Any]:
    """Reopen the output and read count, duration, size, and loop metadata."""
    with Image.open(path) as image:
        frame_count = getattr(image, "n_frames", 1)
        loop = image.info.get("loop")
        sizes: list[tuple[int, int]] = []
        durations: list[int | None] = []

        for index in range(frame_count):
            image.seek(index)
            sizes.append(tuple(image.size))
            durations.append(image.info.get("duration"))

    return {
        "frame_count": frame_count,
        "loop": loop,
        "sizes": sizes,
        "durations": durations,
    }


def encode_gif(
    frames: list[Image.Image],
    output_path: Path,
    duration_ms: int,
    palette_bytes: bytes,
) -> None:
    if not frames:
        raise AssemblyError("no frames were prepared for encoding")

    created = False
    try:
        with output_path.open("xb") as output_file:
            created = True
            frames[0].save(
                output_file,
                format="GIF",
                save_all=True,
                append_images=frames[1:],
                duration=duration_ms,
                loop=0,
                optimize=False,
                disposal=2,
                palette=palette_bytes,
            )
    except FileExistsError as exc:
        raise AssemblyError(
            f"refusing to overwrite existing output: {output_path}"
        ) from exc
    except Exception:
        if created:
            output_path.unlink(missing_ok=True)
        raise


def build_report(
    *,
    output_path: Path,
    source_mode: str,
    sheet_path: Path | None,
    frames_dir: Path | None,
    columns: int | None,
    rows: int | None,
    source_frame_count: int,
    source_size: tuple[int, int] | None,
    expected_frame_size: tuple[int, int],
    duration_ms: int,
    frame_order: str,
    palette_source: str,
) -> dict[str, Any]:
    probe = read_gif(output_path)
    expected_total_duration = source_frame_count * duration_ms
    actual_total_duration = sum(duration or 0 for duration in probe["durations"])

    frame_count_ok = probe["frame_count"] == source_frame_count
    frame_size_ok = all(
        size == expected_frame_size for size in probe["sizes"]
    )
    per_frame_duration_ok = all(
        duration == duration_ms for duration in probe["durations"]
    )
    total_duration_ok = actual_total_duration == expected_total_duration
    loop_ok = probe["loop"] == 0
    file_size_bytes = output_path.stat().st_size
    file_size_ok = file_size_bytes > 0

    frame_merge_detected = probe["frame_count"] < source_frame_count
    verification_ok = (
        frame_size_ok
        and total_duration_ok
        and loop_ok
        and file_size_ok
        and not (probe["frame_count"] > source_frame_count)
    )

    if not verification_ok:
        status = "error"
    elif frame_merge_detected:
        status = "frame_merge_detected"
    elif frame_count_ok and per_frame_duration_ok:
        status = "ok"
    else:
        status = "error"

    report: dict[str, Any] = {
        "status": status,
        "source_mode": source_mode,
        "sheet": str(sheet_path) if sheet_path is not None else None,
        "frames_dir": str(frames_dir) if frames_dir is not None else None,
        "output": str(output_path),
        "columns": columns,
        "rows": rows,
        "source_size": list(source_size) if source_size is not None else None,
        "frame_size": list(expected_frame_size),
        "source_frame_count": source_frame_count,
        "encoded_frame_count": probe["frame_count"],
        "duration_ms_requested": duration_ms,
        "encoded_durations_ms": probe["durations"],
        "expected_total_duration_ms": expected_total_duration,
        "encoded_total_duration_ms": actual_total_duration,
        "total_duration_ms": actual_total_duration,
        "loop": probe["loop"],
        "file_size_bytes": file_size_bytes,
        "file_size_mib": round(file_size_bytes / (1024 * 1024), 3),
        "palette": {
            "source": palette_source,
            "capacity": 256,
            "shared_by_all_frames": True,
            "dither": "none",
        },
        "frame_order": frame_order,
        "checks": {
            "frame_count": frame_count_ok,
            "frame_size": frame_size_ok,
            "per_frame_duration": per_frame_duration_ok,
            "total_duration": total_duration_ok,
            "loop": loop_ok,
            "file_size": file_size_ok,
        },
    }
    if frame_merge_detected:
        report["warning"] = (
            "Consecutive identical frames were merged by the GIF encoder; "
            "encoded_frame_count is lower than source_frame_count."
        )

    return report


def assemble_sheet(
    *,
    sheet_path: Path,
    output_path: Path,
    columns: int,
    rows: int,
    duration_ms: int,
) -> dict[str, Any]:
    if not sheet_path.is_file():
        raise AssemblyError(f"input sheet does not exist or is not a file: {sheet_path}")
    if output_path.exists():
        raise AssemblyError(f"refusing to overwrite existing output: {output_path}")

    with Image.open(sheet_path) as sheet:
        sheet.seek(0)
        sheet.load()
        source_width, source_height = sheet.size

        if source_width % columns != 0:
            raise AssemblyError(
                f"sheet width {source_width} is not divisible by columns {columns}"
            )
        if source_height % rows != 0:
            raise AssemblyError(
                f"sheet height {source_height} is not divisible by rows {rows}"
            )

        frame_width = source_width // columns
        frame_height = source_height // rows
        if frame_width <= 0 or frame_height <= 0:
            raise AssemblyError("calculated frame size must be positive")

        palette_image, palette_bytes = palette_image_from_source(sheet)
        frames: list[Image.Image] = []
        # Read left-to-right within each row, then top-to-bottom.
        for row in range(rows):
            for column in range(columns):
                left = column * frame_width
                top = row * frame_height
                crop = sheet.crop(
                    (left, top, left + frame_width, top + frame_height)
                )
                frames.append(
                    crop.convert("RGB").quantize(
                        palette=palette_image,
                        dither=Image.Dither.NONE,
                    )
                )

    expected_frame_size = (frame_width, frame_height)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    encode_gif(frames, output_path, duration_ms, palette_bytes)
    return build_report(
        output_path=output_path,
        source_mode="sheet",
        sheet_path=sheet_path,
        frames_dir=None,
        columns=columns,
        rows=rows,
        source_frame_count=columns * rows,
        source_size=(source_width, source_height),
        expected_frame_size=expected_frame_size,
        duration_ms=duration_ms,
        frame_order="left-to-right,top-to-bottom",
        palette_source="entire_sheet",
    )


def assemble_frames_dir(
    *,
    frames_dir: Path,
    output_path: Path,
    duration_ms: int,
) -> dict[str, Any]:
    if output_path.exists():
        raise AssemblyError(f"refusing to overwrite existing output: {output_path}")

    frame_paths = collect_frame_paths(frames_dir)
    palette_image, palette_bytes = build_palette_from_frame_paths(frame_paths)
    frames: list[Image.Image] = []
    expected_frame_size: tuple[int, int] | None = None

    for frame_path in frame_paths:
        with Image.open(frame_path) as source:
            source.seek(0)
            source.load()
            frame_size = tuple(source.size)
            if expected_frame_size is None:
                expected_frame_size = frame_size
            elif frame_size != expected_frame_size:
                raise AssemblyError(
                    f"frame size mismatch: {frame_path} is {frame_size}, "
                    f"expected {expected_frame_size}"
                )

            frames.append(
                source.convert("RGB").quantize(
                    palette=palette_image,
                    dither=Image.Dither.NONE,
                )
            )

    if expected_frame_size is None:
        raise AssemblyError("no frames were loaded")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    encode_gif(frames, output_path, duration_ms, palette_bytes)
    return build_report(
        output_path=output_path,
        source_mode="frames_dir",
        sheet_path=None,
        frames_dir=frames_dir,
        columns=None,
        rows=None,
        source_frame_count=len(frame_paths),
        source_size=None,
        expected_frame_size=expected_frame_size,
        duration_ms=duration_ms,
        frame_order="filename-ascending",
        palette_source="uniform_sample_up_to_8_frames_downscaled_mosaic",
    )


def assemble(
    *,
    sheet_path: Path | None,
    frames_dir: Path | None,
    output_path: Path,
    columns: int,
    rows: int,
    duration_ms: int,
) -> dict[str, Any]:
    if sheet_path is not None:
        return assemble_sheet(
            sheet_path=sheet_path,
            output_path=output_path,
            columns=columns,
            rows=rows,
            duration_ms=duration_ms,
        )
    if frames_dir is not None:
        return assemble_frames_dir(
            frames_dir=frames_dir,
            output_path=output_path,
            duration_ms=duration_ms,
        )
    raise AssemblyError("one of --sheet or --frames-dir is required")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Crop a sprite sheet or read PNG frames and encode a looping GIF."
    )
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--sheet", help="source sprite-sheet path (grid mode)")
    inputs.add_argument(
        "--frames-dir",
        help="directory containing frame PNGs sorted by filename (directory mode)",
    )
    parser.add_argument(
        "--columns",
        type=positive_int,
        default=2,
        help="number of frame columns in --sheet mode (default: 2)",
    )
    parser.add_argument(
        "--rows",
        type=positive_int,
        default=4,
        help="number of frame rows in --sheet mode (default: 4)",
    )
    parser.add_argument(
        "--duration-ms",
        type=positive_int,
        default=240,
        help="duration of each frame in milliseconds (default: 240)",
    )
    parser.add_argument("--output", required=True, help="destination GIF path")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    sheet_path = Path(args.sheet).expanduser() if args.sheet else None
    frames_dir = Path(args.frames_dir).expanduser() if args.frames_dir else None
    output_path = Path(args.output).expanduser()

    try:
        report = assemble(
            sheet_path=sheet_path,
            frames_dir=frames_dir,
            output_path=output_path,
            columns=args.columns,
            rows=args.rows,
            duration_ms=args.duration_ms,
        )
    except (AssemblyError, OSError, ValueError) as exc:
        emit_error(str(exc))
        return 1

    print(json.dumps(report, ensure_ascii=False, separators=(",", ":")))
    return 0 if report["status"] != "error" else 1


if __name__ == "__main__":
    raise SystemExit(main())
