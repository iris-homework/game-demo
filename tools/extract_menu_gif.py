"""Decode the approved menu GIF into lossless, pixel-verified Godot frames."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
source, output = Path(args.source), Path(args.output)
if output.exists():
    raise SystemExit('Frame directory already exists; refusing to overwrite')
source_hash = hashlib.sha256(source.read_bytes()).hexdigest().upper()
with Image.open(source) as animation:
    if animation.size != (1008, 567) or animation.n_frames != 60:
        raise SystemExit('Expected the approved 1008x567 / 60-frame animation')
    if animation.info.get('loop') != 0:
        raise SystemExit('Expected an infinite-loop source GIF')
    output.mkdir(parents=True)
    frames = []
    for index in range(animation.n_frames):
        animation.seek(index)
        duration = animation.info.get('duration')
        if duration != 80:
            raise SystemExit(f'Unexpected frame duration at {index}: {duration}')
        pixels = animation.convert('RGB')
        frame_path = output / f'frame_{index:03d}.png'
        pixels.save(frame_path, format='PNG', optimize=True)
        with Image.open(frame_path) as decoded:
            if decoded.convert('RGB').tobytes() != pixels.tobytes():
                raise SystemExit(f'Lossless frame verification failed: {index}')
        frames.append({'index': index, 'file': frame_path.name, 'duration_ms': duration,
                       'sha256': hashlib.sha256(frame_path.read_bytes()).hexdigest().upper()})
manifest = {'date': '2026-10-07', 'source': 'res://assets/menu/' + source.name,
            'source_sha256': source_hash, 'width': 1008, 'height': 567,
            'frame_count': 60, 'frame_duration_ms': 80, 'loop_duration_ms': 4800,
            'loop': 0, 'source_playback_speed': 1.0, 'pixel_verification': '60/60 lossless RGB matches',
            'method': 'Decode reviewed GIF frames only; no re-rendering, redraw or color adjustment',
            'decoded_rgb_bytes': 1008 * 567 * 3 * 60, 'frames': frames}
(output / 'source-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: v for k, v in manifest.items() if k != 'frames'}, ensure_ascii=False))
