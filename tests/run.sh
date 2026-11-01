#!/usr/bin/env bash
# Проверки игры: каждая — отдельный запуск Godot со сценарием tests/NN_*.gd (extends SceneTree),
# в конце строка «ALL OK» или «FAIL: …». Окно Godot мелькает: снимкам экрана нужен рендер, без --headless.
# Сохранения, снимки и вывод — в tests/out/ (не в git); настоящие сохранения в user://saves/ не трогаются.
#
#   bash tests/run.sh            — все проверки
#   bash tests/run.sh 14 25      — только 14_*.gd и 25_*.gd
#
# Путь к Godot — из переменной GODOT, по умолчанию — консольная сборка 4.7.2 на рабочем столе.
GODOT="${GODOT:-/c/Users/diord/Desktop/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 1
mkdir -p tests/out/test_saves

if [ $# -gt 0 ]; then
	files=()
	for n in "$@"; do files+=(tests/"$(printf '%02d' "$((10#$n))")"_*.gd); done
else
	files=(tests/[0-9][0-9]_*.gd)
fi

failed=0
for f in "${files[@]}"; do
	name=$(basename "$f" .gd)
	timeout 280 "$GODOT" --path . --script "res://$f" > "tests/out/$name.txt" 2>&1
	result=$(grep -E 'ALL OK|FAIL' "tests/out/$name.txt" | tail -1)
	errors=$(grep -c 'SCRIPT ERROR' "tests/out/$name.txt")
	if [ "$result" != "ALL OK" ] || [ "$errors" -gt 0 ]; then
		failed=$((failed + 1))
		echo "✗ $name: ${result:-нет итога (упал или завис)} · ошибок скрипта: $errors"
	else
		echo "✓ $name"
	fi
done
echo "Не прошло: $failed из ${#files[@]}. Подробности — tests/out/<имя>.txt"
[ "$failed" -eq 0 ]
