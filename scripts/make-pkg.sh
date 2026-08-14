#!/bin/bash
# Собирает установщик dist/FortiSplit-<версия>.pkg.
#
#   ./scripts/make-pkg.sh
#
# В пакете ровно то же, что раньше ставил install.sh: приложение и root-скрипт.
# Правило sudoers пишет postinstall — оно зависит от того, кто сидит за машиной,
# и заранее в payload его не положить.
#
# Пакет НЕподписанный: подпись установщика требует сертификата Developer ID
# Installer, то есть платного аккаунта. Поэтому получателю всё равно придётся
# один раз разрешить запуск через «Настройки → Конфиденциальность и
# безопасность» — это описано в README.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
IDENTIFIER="local.fortisplit.installer"
OUT="dist/FortiSplit-$VERSION.pkg"

LANG_CODE=en
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in ru*|RU*) LANG_CODE=ru ;; esac
case "${FORTISPLIT_LANG:-}" in ru) LANG_CODE=ru ;; en) LANG_CODE=en ;; esac
say() { [ "$LANG_CODE" = ru ] && echo "$1" || echo "$2"; }

say "==> Пересобираю приложение" "==> Rebuilding the app"
./build-app.sh >/dev/null

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root/Applications" "$work/root/usr/local/bin" "$work/scripts" \
         "$work/res/en.lproj" "$work/res/ru.lproj"

say "==> Раскладываю payload" "==> Laying out the payload"
ditto FortiSplit.app "$work/root/Applications/FortiSplit.app"
install -m 755 scripts/fortisplit-vpnctl "$work/root/usr/local/bin/fortisplit-vpnctl"
# Снимаем что снимается (карантин и прочее). com.apple.provenance система
# удалить не даёт, но он уезжает в payload как AppleDouble-метаданные, которые
# установщик склеивает обратно в атрибут — лишних файлов ._имя на диске не будет.
xattr -cr "$work/root" 2>/dev/null || true

cat > "$work/scripts/postinstall" <<'POSTINSTALL'
#!/bin/bash
# Выполняется от root после распаковки payload.
# Единственная задача — правило sudoers на того пользователя, который реально
# сидит за машиной: под root-скриптом $USER здесь бесполезен.
set -uo pipefail

CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
    logger -t fortisplit "postinstall: не удалось определить пользователя, sudoers не настроен"
    exit 0
fi

tmp="$(mktemp)"
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/fortisplit-vpnctl\n' "$CONSOLE_USER" > "$tmp"
# Проверяем ДО установки: битый файл в /etc/sudoers.d ломает sudo целиком.
if visudo -cf "$tmp" >/dev/null 2>&1; then
    install -m 440 -o root -g wheel "$tmp" /etc/sudoers.d/fortisplit
    logger -t fortisplit "postinstall: sudoers настроен для $CONSOLE_USER"
else
    logger -t fortisplit "postinstall: правило sudoers не прошло проверку, не ставлю"
fi
rm -f "$tmp"

if ! /usr/bin/env PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin \
     command -v openfortivpn >/dev/null 2>&1; then
    logger -t fortisplit "postinstall: openfortivpn не найден, нужен brew install openfortivpn"
fi

exit 0
POSTINSTALL
chmod 755 "$work/scripts/postinstall"

cat > "$work/res/en.lproj/readme.html" <<'HTML'
<html><body style="font: 13px -apple-system; margin: 0">
<p>FortiSplit needs <b>openfortivpn</b>. If you do not have it yet, install
<a href="https://brew.sh">Homebrew</a> and run:</p>
<p><code>brew install openfortivpn</code></p>
<p>The installer puts two things on the system:</p>
<ul>
<li><code>/Applications/FortiSplit.app</code></li>
<li><code>/usr/local/bin/fortisplit-vpnctl</code> — the root script, plus a
<code>/etc/sudoers.d/fortisplit</code> rule that lets your user run only that
script without a password.</li>
</ul>
<p>Your VPN configs stay in <code>~/.config/fortisplit</code> and are never
touched by the installer.</p>
</body></html>
HTML

cat > "$work/res/ru.lproj/readme.html" <<'HTML'
<html><body style="font: 13px -apple-system; margin: 0">
<p>FortiSplit требует <b>openfortivpn</b>. Если его ещё нет — поставьте
<a href="https://brew.sh">Homebrew</a> и выполните:</p>
<p><code>brew install openfortivpn</code></p>
<p>Установщик кладёт в систему две вещи:</p>
<ul>
<li><code>/Applications/FortiSplit.app</code></li>
<li><code>/usr/local/bin/fortisplit-vpnctl</code> — root-скрипт, плюс правило
<code>/etc/sudoers.d/fortisplit</code>, разрешающее запускать без пароля только
его.</li>
</ul>
<p>Конфиги VPN лежат в <code>~/.config/fortisplit</code>, установщик их не
трогает.</p>
</body></html>
HTML

say "==> pkgbuild" "==> pkgbuild"
# --ownership recommended: в payload владельцем становится root:wheel, иначе
# root-скрипт приехал бы с правами сборщика и sudoers доверял бы файлу,
# который пользователь может переписать
pkgbuild --root "$work/root" \
         --scripts "$work/scripts" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --ownership recommended \
         --install-location / \
         "$work/component.pkg" >/dev/null

cat > "$work/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>FortiSplit</title>
    <organization>local.fortisplit</organization>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <volume-check>
        <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
    </volume-check>
    <readme file="readme.html"/>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default"><pkg-ref id="$IDENTIFIER"/></choice>
    <pkg-ref id="$IDENTIFIER" version="$VERSION">component.pkg</pkg-ref>
</installer-gui-script>
XML

say "==> productbuild" "==> productbuild"
mkdir -p dist
rm -f "$OUT"
productbuild --distribution "$work/distribution.xml" \
             --package-path "$work" \
             --resources "$work/res" \
             "$OUT" >/dev/null

echo ""
say "Готово: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))" \
    "Done: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
