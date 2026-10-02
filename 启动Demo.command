#!/bin/zsh
set -e
cd "$(dirname "$0")"
if [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  engine=/Applications/Godot.app/Contents/MacOS/Godot
elif command -v godot >/dev/null 2>&1; then
  engine=$(command -v godot)
elif command -v godot4 >/dev/null 2>&1; then
  engine=$(command -v godot4)
else
  echo '请先安装 Godot 4 标准版，然后导入 project.godot 并按 F5。'
  read -r '?按回车退出'
  exit 1
fi
"$engine" --headless --path "$PWD" --editor --import --quit
exec "$engine" --path "$PWD"
