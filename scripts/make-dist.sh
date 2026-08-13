#!/bin/bash
# Собирает каталог для раздачи: приложение + install.sh + то, что ему нужно.
# Исходники внутрь не попадают.
#
#   ./scripts/make-dist.sh
#
# На выходе: dist/FortiSplit-<версия>/ и такой же .zip рядом.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
OUT="dist/FortiSplit-$VERSION"

echo "==> Пересобираю приложение"
./build-app.sh >/dev/null

echo "==> Раскладываю $OUT"
rm -rf "$OUT" "dist/FortiSplit-$VERSION.zip"
mkdir -p "$OUT/scripts" "$OUT/config"

# ditto, а не cp: у бандла есть подпись, её надо перенести как есть
ditto FortiSplit.app "$OUT/FortiSplit.app"
# install.sh ищет их по этим путям, поэтому раскладку сохраняем
install -m 755 install.sh "$OUT/install.sh"
install -m 755 scripts/fortisplit-vpnctl "$OUT/scripts/fortisplit-vpnctl"
install -m 644 config/example.config "$OUT/config/example.config"
install -m 644 config/example.routes "$OUT/config/example.routes"
install -m 644 INSTALL.md "$OUT/README.md"

echo "==> Проверяю подпись в копии"
codesign --verify --strict "$OUT/FortiSplit.app"

echo "==> Упаковываю"
ditto -c -k --keepParent "$OUT" "dist/FortiSplit-$VERSION.zip"

echo ""
echo "Готово:"
echo "  $(pwd)/$OUT"
echo "  $(pwd)/dist/FortiSplit-$VERSION.zip  ($(du -h "dist/FortiSplit-$VERSION.zip" | cut -f1))"
