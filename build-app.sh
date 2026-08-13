#!/bin/bash
# Собирает FortiSplit.app из SwiftPM-таргета и подписывает ad-hoc.
# Требует: Xcode Command Line Tools (swift, codesign). Запускать на macOS.
set -euo pipefail
cd "$(dirname "$0")"

APP="FortiSplit.app"
BIN="FortiSplit"

LANG_CODE=en
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in ru*|RU*) LANG_CODE=ru ;; esac
case "${FORTISPLIT_LANG:-}" in ru) LANG_CODE=ru ;; en) LANG_CODE=en ;; esac
t() {
    local k="$1" a="${2:-}"
    case "$LANG_CODE:$k" in
        ru:building)  echo "==> Собираю (swift build, release)" ;;
        en:building)  echo "==> Building (swift build, release)" ;;
        ru:no-bin)    echo "Не найден собранный бинарник: $a" ;;
        en:no-bin)    echo "Built binary not found: $a" ;;
        ru:bundle)    echo "==> Собираю бандл $a" ;;
        en:bundle)    echo "==> Assembling the $a bundle" ;;
        ru:sign)      echo "==> Ad-hoc подпись (обязательна на Apple Silicon)" ;;
        en:sign)      echo "==> Ad-hoc signing (required on Apple Silicon)" ;;
        ru:done)      echo "Готово: $a" ;;
        en:done)      echo "Done: $a" ;;
        ru:next)      echo "Дальше: ./install.sh   (ставит root-скрипт, sudoers и конфиги в ~/.config)" ;;
        en:next)      echo "Next: ./install.sh   (installs the root script, sudoers rule and configs in ~/.config)" ;;
        ru:next2)     echo "Затем перетащи FortiSplit.app в /Applications и запусти." ;;
        en:next2)     echo "Then drag FortiSplit.app to /Applications and launch it." ;;
    esac
}

t building
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$BIN"
[ -x "$BIN_PATH" ] || { t no-bin "$BIN_PATH" >&2; exit 1; }

t bundle "$APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/FortiSplit.icns "$APP/Contents/Resources/FortiSplit.icns"
cp Resources/MenuIcon*.png "$APP/Contents/Resources/"
# Локализации: macOS сама выберет .lproj по языку системы
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
done

t sign
codesign --force --deep --sign - "$APP"

echo ""
t done "$(pwd)/$APP"
t next
t next2
