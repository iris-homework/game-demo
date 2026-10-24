# assets-sfx-combat

Game combat sound effects (impacts, explosions, weapons, hits)

## Stats

- **Total assets**: 255
- **License**: CC0-1.0 (all Kenney assets are public domain)
- **Source**: [kenney.nl](https://kenney.nl)

## Source Packs

| Pack | Assets | License | Link |
|------|--------|---------|------|
| Kenney Impact Sounds | 130 | CC0-1.0 | [Link](https://kenney.nl/assets/impact-sounds) |
| Kenney Rpg Audio | 52 | CC0-1.0 | [Link](https://kenney.nl/assets/rpg-audio) |
| Kenney Sci Fi Sounds | 73 | CC0-1.0 | [Link](https://kenney.nl/assets/sci-fi-sounds) |

## Structure

```
assets-sfx-combat/
├── assets/kenney/    # Organized by source pack
├── previews/         # Pack preview images
├── LICENSES/         # License files per pack
├── manifest.json     # Machine-readable asset index (255 entries)
├── tags.json         # Genre, theme, style tags
└── README.md
```

## Usage

Browse `manifest.json` for the full asset index. Each entry includes:

```json
{
  "id": "kenney-<pack>/<asset-name>",
  "name": "Human Readable Name",
  "path": "assets/kenney/<pack>/...",
  "source": "Kenney <Pack Name>",
  "sourceUrl": "https://kenney.nl/assets/<pack>",
  "license": "CC0-1.0",
  "tags": [...],
  "fileType": "png|ogg|obj|..."
}
```

## License

All assets are **CC0-1.0** (Creative Commons Zero) — public domain, free for any use including commercial, no attribution required. See `LICENSES/` for original license files from each pack.
