#!/bin/sh
# Установщик ShootIn для Linux (x86_64).
#
# Запуск:   ./install.sh          — для текущего пользователя (root не нужен), игра в ~/.local/share/ShootIn
#           ./install.sh --system — для всех пользователей, игра в /opt/ShootIn (попросит пароль через sudo)
# Если файл не запускается из-за прав — достаточно:   sh install.sh
#
# Что делает: создаёт нужные папки (игра, mods рядом с игрой, сохранения), копирует игру и САМ ставит
# право на запуск (chmod +x), добавляет ярлык в меню приложений и на рабочий стол, команду `shootin`
# и скрипт удаления. Ничего не скачивает и не трогает систему за пределами этих папок.
set -u

APP_NAME="ShootIn"
BIN_NAME="ShootIn.x86_64"
ICON_NAME="ShootIn.png"
VERSION="@VERSION@"

MODE="user"
PREFIX=""
WANT_DESKTOP=1
WANT_MENU=1
ASSUME_YES=0

say() { printf '%s\n' "$*"; }
fail() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }

usage() {
	cat <<EOF
Установка $APP_NAME $VERSION

  ./install.sh [параметры]

  --system          установить для всех пользователей (/opt/$APP_NAME, нужен sudo)
  --prefix ПАПКА    поставить игру в указанную папку
  --no-desktop      не создавать ярлык на рабочем столе
  --no-menu         не добавлять игру в меню приложений
  -y, --yes         ничего не спрашивать
  -h, --help        эта справка

Удаление: uninstall.sh из этой папки (или из папки установленной игры).
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--system) MODE="system" ;;
		--prefix) shift; [ $# -gt 0 ] || fail "после --prefix нужна папка"; PREFIX="$1" ;;
		--no-desktop) WANT_DESKTOP=0 ;;
		--no-menu) WANT_MENU=0 ;;
		-y|--yes) ASSUME_YES=1 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; fail "неизвестный параметр: $1" ;;
	esac
	shift
done

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || fail "не удалось определить папку установщика"

[ -f "$HERE/$BIN_NAME" ] || fail "рядом с install.sh нет файла $BIN_NAME. Распакуйте архив целиком и запустите установщик из распакованной папки."

case "$(uname -m)" in
	x86_64|amd64) ;;
	*) say "Внимание: эта сборка рассчитана на процессор x86_64, а у вас $(uname -m). Игра может не запуститься." ;;
esac

# Для всех пользователей нужны права администратора: перезапускаемся через sudo.
if [ "$MODE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
	command -v sudo >/dev/null 2>&1 || fail "для --system нужен sudo (или запустите установщик от имени root)"
	say "Для установки в /opt нужны права администратора, запрашиваю sudo…"
	exec sudo sh "$0" "$@" --system
fi

XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
if [ "$MODE" = "system" ]; then
	[ -n "$PREFIX" ] || PREFIX="/opt/$APP_NAME"
	APPS_DIR="/usr/share/applications"
	ICON_DIR="/usr/share/icons/hicolor/256x256/apps"
	BIN_DIR="/usr/local/bin"
	DESKTOP_DIR=""
else
	[ -n "$PREFIX" ] || PREFIX="$XDG_DATA/$APP_NAME"
	APPS_DIR="$XDG_DATA/applications"
	ICON_DIR="$XDG_DATA/icons/hicolor/256x256/apps"
	BIN_DIR="$HOME/.local/bin"
	DESKTOP_DIR=""
	if command -v xdg-user-dir >/dev/null 2>&1; then
		DESKTOP_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || true)
	fi
	[ -n "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME/Desktop"
	[ -d "$DESKTOP_DIR" ] || DESKTOP_DIR=""
fi
# Сохранения и моды, поставленные из самой игры, Godot кладёт сюда:
USER_DATA="$XDG_DATA/godot/app_userdata/$APP_NAME"

say "Устанавливаю $APP_NAME $VERSION в $PREFIX"

# 1. Папки.
mkdir -p "$PREFIX/mods" || fail "не удалось создать $PREFIX (нет прав? попробуйте --system или другой --prefix)"
if [ "$MODE" = "user" ]; then
	mkdir -p "$USER_DATA/mods" || say "Внимание: не удалось создать $USER_DATA/mods"
fi

# 2. Игра и право на запуск: именно то, что иначе приходится делать вручную командой chmod +x.
cp -f "$HERE/$BIN_NAME" "$PREFIX/$BIN_NAME" || fail "не удалось скопировать игру в $PREFIX"
chmod 755 "$PREFIX/$BIN_NAME" || fail "не удалось поставить право на запуск (chmod +x) для $PREFIX/$BIN_NAME"
[ -x "$PREFIX/$BIN_NAME" ] || fail "файл $PREFIX/$BIN_NAME не стал исполняемым (папка смонтирована с noexec?). Выберите другую папку через --prefix."

[ -f "$HERE/$ICON_NAME" ] && cp -f "$HERE/$ICON_NAME" "$PREFIX/$ICON_NAME"
[ -f "$HERE/uninstall.sh" ] && { cp -f "$HERE/uninstall.sh" "$PREFIX/uninstall.sh"; chmod 755 "$PREFIX/uninstall.sh"; }
[ -f "$HERE/README.txt" ] && cp -f "$HERE/README.txt" "$PREFIX/README.txt"
cat > "$PREFIX/mods/README.txt" <<EOF
Сюда можно класть моды для ShootIn: .zip-архивы или папки с файлом mod.json.
Игра находит их при открытии экрана «Моды» (главное меню -> Моды) и включает галочкой.
Моды, установленные кнопкой «Установить из файла…» прямо в игре, лежат в другой папке:
$USER_DATA/mods
EOF

# 3. Ярлыки.
write_desktop_entry() {
	cat > "$1" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$APP_NAME
Comment=2D экшен-платформер: 34 уровня, 8 боссов и моды
Comment[ru]=2D экшен-платформер: 34 уровня, 8 боссов и моды
Exec="$PREFIX/$BIN_NAME"
Path=$PREFIX
Icon=$PREFIX/$ICON_NAME
Terminal=false
Categories=Game;ActionGame;
StartupWMClass=$APP_NAME
EOF
	chmod 755 "$1"
}

if [ "$WANT_MENU" -eq 1 ]; then
	mkdir -p "$APPS_DIR" && write_desktop_entry "$APPS_DIR/shootin.desktop" && say "Добавлен в меню приложений: $APPS_DIR/shootin.desktop"
	if [ -f "$PREFIX/$ICON_NAME" ]; then
		mkdir -p "$ICON_DIR" && cp -f "$PREFIX/$ICON_NAME" "$ICON_DIR/shootin.png"
	fi
	command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" >/dev/null 2>&1
	command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f "$(dirname "$(dirname "$(dirname "$ICON_DIR")")")" >/dev/null 2>&1
fi

if [ "$WANT_DESKTOP" -eq 1 ] && [ -n "$DESKTOP_DIR" ]; then
	if write_desktop_entry "$DESKTOP_DIR/ShootIn.desktop"; then
		# GNOME и другие оболочки запускают ярлык с рабочего стола только после пометки «доверенный».
		command -v gio >/dev/null 2>&1 && gio set "$DESKTOP_DIR/ShootIn.desktop" metadata::trusted true >/dev/null 2>&1
		say "Ярлык на рабочем столе: $DESKTOP_DIR/ShootIn.desktop"
	fi
fi

# 4. Команда `shootin` в терминале.
if mkdir -p "$BIN_DIR" 2>/dev/null && ln -sf "$PREFIX/$BIN_NAME" "$BIN_DIR/shootin" 2>/dev/null; then
	say "Команда для терминала: shootin  ($BIN_DIR/shootin)"
fi

say ""
say "Готово! $APP_NAME установлена."
say "  Игра:   $PREFIX/$BIN_NAME"
say "  Моды:   $PREFIX/mods  (положите сюда .zip или папку мода)"
[ "$MODE" = "user" ] && say "  Сохранения и моды из игры: $USER_DATA"
say "  Удалить: $PREFIX/uninstall.sh"
say "Запуск: найдите «$APP_NAME» в меню приложений (раздел «Игры») или выполните: $PREFIX/$BIN_NAME"

# Двойной клик из файлового менеджера: терминала нет, поэтому сообщаем о результате окном.
if [ ! -t 1 ]; then
	if command -v zenity >/dev/null 2>&1; then
		zenity --info --title="$APP_NAME" --text="$APP_NAME установлена.\n\nЗапуск — из меню приложений (раздел «Игры»).\nПапка модов: $PREFIX/mods" >/dev/null 2>&1
	elif command -v kdialog >/dev/null 2>&1; then
		kdialog --title "$APP_NAME" --msgbox "$APP_NAME установлена.\nЗапуск — из меню приложений (раздел «Игры»).\nПапка модов: $PREFIX/mods" >/dev/null 2>&1
	elif command -v notify-send >/dev/null 2>&1; then
		notify-send "$APP_NAME установлена" "Запуск — из меню приложений (раздел «Игры»)" >/dev/null 2>&1
	fi
elif [ "$ASSUME_YES" -eq 0 ] && [ "$MODE" = "user" ]; then
	printf 'Запустить игру сейчас? [Д/н] '
	read -r answer || answer=""
	case "$answer" in
		""|[YyДд]*) ( "$PREFIX/$BIN_NAME" >/dev/null 2>&1 & ) ;;
	esac
fi
exit 0
