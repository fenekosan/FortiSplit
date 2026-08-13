#!/bin/bash
# Собирает Resources/FortiSplit.icns из Resources/AppIcon.png (1024x1024).
# Запускать только когда сменилась картинка — .icns лежит в репозитории готовым.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Resources/AppIcon.png"
OUT="Resources/FortiSplit.icns"
[ -f "$SRC" ] || { echo "нет исходника $SRC" >&2; exit 1; }

work="$(mktemp -d)/FortiSplit.iconset"
mkdir -p "$work"
# macOS ждёт именно эти имена и размеры
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x \
            256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    px="${spec%%:*}"; name="${spec#*:}"
    sips -z "$px" "$px" "$SRC" --out "$work/icon_$name.png" >/dev/null
done

iconutil -c icns "$work" -o "$OUT"
rm -rf "$(dirname "$work")"
echo "готово: $OUT ($(du -h "$OUT" | cut -f1))"
