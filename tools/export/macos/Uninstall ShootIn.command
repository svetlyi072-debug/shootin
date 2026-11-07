#!/bin/bash
# Удаление ShootIn с macOS. Двойной клик (или: bash "Uninstall ShootIn.command").
# Сохранения и моды игрока остаются; чтобы удалить и их, запустите с ключом --purge.

PURGE=0
[ "$1" = "--purge" ] && PURGE=1
DATA="$HOME/Library/Application Support/Godot/app_userdata/ShootIn"

pkill -x ShootIn 2>/dev/null
for dir in /Applications "$HOME/Applications"; do
	if [ -d "$dir/ShootIn.app" ]; then
		rm -rf "$dir/ShootIn.app" && echo "Удалено: $dir/ShootIn.app"
	fi
done
if [ "$PURGE" -eq 1 ]; then
	rm -rf "$DATA" && echo "Удалены сохранения и моды: $DATA"
elif [ -d "$DATA" ]; then
	echo "Сохранения и моды остались в: $DATA"
	echo "(чтобы удалить и их: bash \"Uninstall ShootIn.command\" --purge)"
fi
echo "Готово. Это окно можно закрыть."
