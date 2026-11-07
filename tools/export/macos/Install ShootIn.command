#!/bin/bash
# Установщик ShootIn для macOS. Двойной клик (или: bash "Install ShootIn.command").
# Копирует ShootIn.app в «Программы», сам ставит право на запуск, снимает блокировку Gatekeeper
# («программа загружена из интернета»), подписывает приложение локально и создаёт папки для модов.
# Ничего не скачивает.

APP="ShootIn.app"
BIN="ShootIn"
HERE="$(cd "$(dirname "$0")" && pwd)"

say() { printf '%s\n' "$*"; }
fail() { printf '\nОшибка: %s\n' "$*"; printf 'Нажмите Enter, чтобы закрыть окно…'; read -r _; exit 1; }

say "Установка ShootIn"
say "-----------------"
[ -d "$HERE/$APP" ] || fail "рядом с установщиком нет $APP. Распакуйте архив целиком и запустите установщик из распакованной папки."

if [ -w /Applications ]; then
	DEST_DIR="/Applications"
else
	DEST_DIR="$HOME/Applications"
	mkdir -p "$DEST_DIR" || fail "не удалось создать $DEST_DIR"
fi
DEST="$DEST_DIR/$APP"

# Если игра сейчас запущена, её нужно закрыть, иначе файлы не заменить.
if pgrep -x "$BIN" >/dev/null 2>&1; then
	say "ShootIn сейчас запущена — закрываю её…"
	pkill -x "$BIN"
	sleep 2
fi

say "Копирую в $DEST …"
rm -rf "$DEST"
ditto "$HERE/$APP" "$DEST" || fail "не удалось скопировать приложение в $DEST_DIR"

# Снять «карантин» (иначе macOS не даёт открыть программу без подписи разработчика) и поставить права запуска.
xattr -cr "$DEST" 2>/dev/null
chmod -R u+rwX "$DEST"
chmod +x "$DEST/Contents/MacOS/"* 2>/dev/null
[ -x "$DEST/Contents/MacOS/$BIN" ] || fail "файл $DEST/Contents/MacOS/$BIN не стал исполняемым"

# Локальная (ad-hoc) подпись: на Mac с процессорами Apple программа без подписи не запускается.
if command -v codesign >/dev/null 2>&1; then
	if ! codesign --verify --deep "$DEST" >/dev/null 2>&1; then
		say "Подписываю приложение локально…"
		codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || say "Внимание: подписать не удалось, но попробуем запустить."
	fi
fi

# Папки игры: сюда игра кладёт сохранения и моды, установленные из неё.
DATA="$HOME/Library/Application Support/Godot/app_userdata/ShootIn"
mkdir -p "$DATA/mods"
cat > "$DATA/mods/README.txt" <<EOF
Сюда можно класть моды для ShootIn: .zip-архивы или папки с файлом mod.json.
Игра находит их при открытии экрана «Моды» (главное меню -> Моды) и включает галочкой.
EOF

say ""
say "Готово! ShootIn установлена: $DEST"
say "Папка модов: $DATA/mods"
say "Запускаю игру…"
open "$DEST"
say "Это окно можно закрыть."
exit 0
