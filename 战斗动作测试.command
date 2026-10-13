#!/bin/zsh
cd "$(dirname "$0")"
exec /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/combat_stage_demo.tscn
