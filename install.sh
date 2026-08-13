#!/bin/bash
# Installs the privileged part (needs sudo once) and creates the user's config
# directory. Idempotent: existing configs are never overwritten.
#
# Only two permanent files land outside the bundle: the root script itself and
# the sudoers rule. The rule has to point at a file the user cannot rewrite —
# otherwise NOPASSWD would mean free root for any process running as the user.
#
# Language follows LANG/LC_ALL; override with FORTISPLIT_LANG=en|ru.
set -euo pipefail
cd "$(dirname "$0")"

USER_NAME="$(whoami)"
CONF_DIR="$HOME/.config/fortisplit"

LANG_CODE=en
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in ru*|RU*) LANG_CODE=ru ;; esac
case "${FORTISPLIT_LANG:-}" in ru) LANG_CODE=ru ;; en) LANG_CODE=en ;; esac

t() {
    local k="$1" a="${2:-}"
    case "$LANG_CODE:$k" in
        ru:checking)     echo "==> Проверяю openfortivpn" ;;
        en:checking)     echo "==> Checking for openfortivpn" ;;
        ru:no-ofv)       echo "openfortivpn не найден. Установи: brew install openfortivpn" ;;
        en:no-ofv)       echo "openfortivpn not found. Install it: brew install openfortivpn" ;;
        ru:inst-script)  echo "==> Ставлю root-скрипт vpnctl -> /usr/local/bin" ;;
        en:inst-script)  echo "==> Installing the vpnctl root script -> /usr/local/bin" ;;
        ru:conf-dir)     echo "==> Каталог конфигов -> $a (без root)" ;;
        en:conf-dir)     echo "==> Config directory -> $a (no root needed)" ;;
        ru:seeded)       echo "    положил шаблон $a — заполни его или импортируй свой конфиг" ;;
        en:seeded)       echo "    wrote the $a template — fill it in or import your own config" ;;
        ru:kept)         echo "    $a уже есть — не трогаю" ;;
        en:kept)         echo "    $a already exists — leaving it alone" ;;
        ru:sudoers)      echo "==> Настраиваю sudoers (NOPASSWD только на vpnctl)" ;;
        en:sudoers)      echo "==> Configuring sudoers (NOPASSWD for vpnctl only)" ;;
        ru:sudoers-bad)  echo "sudoers-правило не прошло проверку, ничего не ставлю" ;;
        en:sudoers-bad)  echo "the sudoers rule failed validation, installing nothing" ;;
        ru:leftovers)    echo "Замечание: от прошлой версии остались файлы, они больше не нужны:" ;;
        en:leftovers)    echo "Note: leftovers from an older version are still around and no longer needed:" ;;
        ru:remove-with)  echo "Удалить: sudo rm -rf $a" ;;
        en:remove-with)  echo "Remove them with: sudo rm -rf $a" ;;
        ru:done)         echo "Готово. Проверь: sudo -n /usr/local/bin/fortisplit-vpnctl status" ;;
        en:done)         echo "Done. Check it: sudo -n /usr/local/bin/fortisplit-vpnctl status" ;;
        ru:done-hint)    echo "Должно вывести DISCONNECTED без запроса пароля." ;;
        en:done-hint)    echo "It should print DISCONNECTED without asking for a password." ;;
    esac
}

t checking
if ! command -v openfortivpn >/dev/null 2>&1 \
   && [ ! -x /opt/homebrew/bin/openfortivpn ] \
   && [ ! -x /usr/local/bin/openfortivpn ]; then
    t no-ofv >&2
    exit 1
fi

t inst-script
# на чистой Apple Silicon машине /usr/local/bin может отсутствовать вовсе
# (Homebrew ставится в /opt/homebrew), а install каталоги не создаёт
sudo mkdir -p /usr/local/bin
sudo install -m 755 -o root -g wheel scripts/fortisplit-vpnctl /usr/local/bin/fortisplit-vpnctl

t conf-dir "$CONF_DIR"
mkdir -p "$CONF_DIR"
chmod 700 "$CONF_DIR"
# Шаблон кладём, только если конфигов нет вообще: у того, кто уже завёл свои,
# лишний example.config в списке ни к чему.
if ! compgen -G "$CONF_DIR/*.config" >/dev/null; then
    install -m 600 config/example.config "$CONF_DIR/example.config"
    install -m 644 config/example.routes "$CONF_DIR/example.routes"
    t seeded "example.config"
    echo "example" > "$CONF_DIR/active"
else
    t kept "$CONF_DIR"
fi

t sudoers
tmp="$(mktemp)"
echo "$USER_NAME ALL=(root) NOPASSWD: /usr/local/bin/fortisplit-vpnctl" > "$tmp"
# Проверяем ДО установки: битый файл в /etc/sudoers.d ломает sudo целиком.
if ! sudo visudo -cf "$tmp"; then
    t sudoers-bad >&2
    rm -f "$tmp"; exit 1
fi
sudo install -m 440 -o root -g wheel "$tmp" /etc/sudoers.d/fortisplit
rm -f "$tmp"

# Хвосты прошлых версий, которые ставили ppp-хуки и конфиги в /etc
leftovers=()
for f in /etc/ppp/ip-up /etc/ppp/ip-down; do
    [ -f "$f" ] && grep -q 'vpn-routes' "$f" 2>/dev/null && leftovers+=("$f")
done
[ -d /etc/openfortivpn ] && leftovers+=("/etc/openfortivpn")
if [ ${#leftovers[@]} -gt 0 ]; then
    echo ""
    t leftovers
    printf '    %s\n' "${leftovers[@]}"
    t remove-with "${leftovers[*]}"
fi

echo ""
t done
t done-hint
