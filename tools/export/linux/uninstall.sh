#!/bin/sh
# Удаление ShootIn (Linux). Запуск:   ./uninstall.sh   или   sh uninstall.sh
#   --purge   удалить и сохранения с модами игрока (иначе они остаются на диске)
#   -y        не спрашивать подтверждения
set -u

PURGE=0
ASSUME_YES=0
for arg in "$@"; do
	case "$arg" in
		--purge) PURGE=1 ;;
		-y|--yes) ASSUME_YES=1 ;;
		-h|--help) echo "Использование: uninstall.sh [--purge] [-y]"; exit 0 ;;
	esac
done

PREFIX=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
[ -f "$PREFIX/ShootIn.x86_64" ] || { echo "Это не папка установленной игры (нет ShootIn.x86_64): $PREFIX" >&2; exit 1; }

XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
case "$PREFIX" in
	/opt/*|/usr/*)
		if [ "$(id -u)" -ne 0 ]; then
			command -v sudo >/dev/null 2>&1 || { echo "Нужны права администратора (sudo)." >&2; exit 1; }
			exec sudo sh "$0" "$@"
		fi
		APPS_DIR="/usr/share/applications"; ICON="/usr/share/icons/hicolor/256x256/apps/shootin.png"; LINK="/usr/local/bin/shootin" ;;
	*)
		APPS_DIR="$XDG_DATA/applications"; ICON="$XDG_DATA/icons/hicolor/256x256/apps/shootin.png"; LINK="$HOME/.local/bin/shootin" ;;
esac

if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
	printf 'Удалить ShootIn из %s? [д/Н] ' "$PREFIX"
	read -r answer || answer=""
	case "$answer" in [YyДд]*) ;; *) echo "Отменено."; exit 0 ;; esac
fi

rm -f "$APPS_DIR/shootin.desktop" "$ICON"
DESKTOP_DIR=""
command -v xdg-user-dir >/dev/null 2>&1 && DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || true)
for d in "$DESKTOP_DIR" "$HOME/Desktop"; do
	[ -n "$d" ] && rm -f "$d/ShootIn.desktop"
done
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" >/dev/null 2>&1

rm -f "$PREFIX/ShootIn.x86_64" "$PREFIX/ShootIn.png" "$PREFIX/README.txt" "$PREFIX/mods/README.txt"
# Команду `shootin` удаляем, только если она наша: ссылка вела на удалённую только что игру.
if [ -L "$LINK" ] && [ ! -e "$LINK" ]; then rm -f "$LINK"; fi
rm -f "$PREFIX/uninstall.sh"  # скрипт уже прочитан оболочкой, удалять себя безопасно
KEPT=""
if [ "$PURGE" -eq 1 ]; then
	rm -rf "$PREFIX/mods" "$XDG_DATA/godot/app_userdata/ShootIn"
else
	if [ -d "$PREFIX/mods" ] && [ -n "$(ls -A "$PREFIX/mods" 2>/dev/null)" ]; then KEPT="$PREFIX/mods"; fi
	rmdir "$PREFIX/mods" 2>/dev/null
fi
rmdir "$PREFIX" 2>/dev/null

echo "ShootIn удалена."
[ -n "$KEPT" ] && echo "Ваши моды сохранены в $KEPT"
[ "$PURGE" -eq 0 ] && [ -d "$XDG_DATA/godot/app_userdata/ShootIn" ] && echo "Сохранения остались в $XDG_DATA/godot/app_userdata/ShootIn (удалить: uninstall.sh --purge)"
exit 0
