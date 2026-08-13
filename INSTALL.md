# FortiSplit

Меню-бар приложение для macOS: поднимает FortiGate SSL-VPN через `openfortivpn`
в режиме split-tunnel — в туннель уходят только подсети из твоего списка,
остальной трафик идёт обычным путём. Конфигов может быть несколько,
переключаются из окна настроек.

*(English version below.)*

## Что нужно

- macOS 13 или новее
- [Homebrew](https://brew.sh) и `openfortivpn`:

  ```bash
  brew install openfortivpn
  ```

## Установка

```bash
# 1. Снять карантин: приложение подписано ad-hoc, и после скачивания
#    Gatekeeper его не пустит
xattr -dr com.apple.quarantine FortiSplit.app

# 2. Поставить приложение
cp -R FortiSplit.app /Applications/

# 3. Поставить привилегированную часть (спросит пароль sudo один раз)
./install.sh

# 4. Запустить
open /Applications/FortiSplit.app
```

Иконка-щит появится в строке меню. Дальше **Настройки…** → вкладка «Конфиг»:
заполни шаблон или нажми «Импорт…» и выбери готовый `.config` от openfortivpn.
На вкладке «Маршруты» — список подсетей в формате CIDR, по одной на строку.

При первом подключении openfortivpn обычно ругается на сертификат шлюза и
печатает его хэш (видно через **Показать логи**). Добавь строку
`trusted-cert = <хэш>` в конфиг.

## Что делает install.sh

Кладёт в систему всего два постоянных файла — оба нужны, чтобы приложение могло
поднимать VPN, ни разу не спросив пароль:

| Куда | Что |
|---|---|
| `/usr/local/bin/fortisplit-vpnctl` | root-скрипт: единственное место, где что-то делается от root |
| `/etc/sudoers.d/fortisplit` | правило, разрешающее твоему пользователю запускать **только** этот скрипт без пароля |

И заводит каталог конфигов `~/.config/fortisplit` с шаблоном (если конфигов там
ещё нет). Права root для этого не нужны: конфиги — обычные твои файлы.

Правило sudoers проверяется до установки: битый файл в `/etc/sudoers.d` сломал
бы `sudo` целиком.

## Что делает fortisplit-vpnctl

Приложение работает от твоего пользователя и root не имеет. Всё, что без root
невозможно, вынесено в один маленький bash-скрипт с пятью командами:

- `start <конфиг>` — запускает `openfortivpn` с этим конфигом
- `stop` — гасит его
- `status` — отвечает `DISCONNECTED` / `CONNECTING` / `CONNECTED <ip>`
- `apply-routes <файл>` — кладёт подсети из файла на поднятый интерфейс `pppN`
  (это и есть кнопка «Применить сейчас»: маршруты меняются без переподключения)
- `logs` — последние строки `/var/log/fortisplit.log`

Пути, которые приходят от приложения, скрипт проверяет: только абсолютный путь,
без `..`, обычный файл, не симлинк, принадлежащий вызвавшему. Из списка
маршрутов в системную команду `route` уходят лишь строки, целиком совпавшие с
форматом IPv4-CIDR.

**Важно понимать:** правило NOPASSWD означает, что любой процесс от твоего имени
может дёрнуть этот скрипт и, через конфиг openfortivpn, получить root. Для
личной машины это нормальный размен, для рабочей — решай сам.

## Удаление

```bash
sudo rm -f /usr/local/bin/fortisplit-vpnctl /etc/sudoers.d/fortisplit /var/log/fortisplit.log
rm -rf /Applications/FortiSplit.app
rm -rf ~/.config/fortisplit      # конфиги с паролями — удаляй осознанно
```

---

# FortiSplit (English)

A macOS menu-bar app that brings up a FortiGate SSL-VPN through `openfortivpn`
in split-tunnel mode: only the subnets you list go through the tunnel, all other
traffic takes the normal route. You can keep several configs and switch between
them in the settings window.

## Requirements

- macOS 13 or newer
- [Homebrew](https://brew.sh) and `openfortivpn`: `brew install openfortivpn`

## Install

```bash
# 1. Clear quarantine — the app is ad-hoc signed, so Gatekeeper blocks it
#    after a download
xattr -dr com.apple.quarantine FortiSplit.app

# 2. Install the app
cp -R FortiSplit.app /Applications/

# 3. Install the privileged part (asks for your sudo password once)
./install.sh

# 4. Launch
open /Applications/FortiSplit.app
```

A shield icon appears in the menu bar. Open **Settings…** → **Config** tab, fill
in the template or press **Import…** and pick an existing openfortivpn `.config`.
The **Routes** tab holds the subnets, one CIDR per line.

On the first connection openfortivpn usually rejects the gateway certificate and
prints its hash (see **Show Log**). Add `trusted-cert = <hash>` to the config.

## What install.sh does

It puts exactly two permanent files on the system, both required so the app can
bring the VPN up without ever asking for a password:

| Path | Purpose |
|---|---|
| `/usr/local/bin/fortisplit-vpnctl` | the root script — the only place where anything runs as root |
| `/etc/sudoers.d/fortisplit` | a rule letting your user run **only** that script without a password |

It also creates `~/.config/fortisplit` with a template config (only if no config
is there yet). That needs no root: the configs are ordinary files of yours.

The sudoers rule is validated before installation — a malformed file in
`/etc/sudoers.d` would break `sudo` entirely.

## What fortisplit-vpnctl does

The app runs as your user and has no root. Everything that genuinely requires
root lives in one small bash script with five commands:

- `start <config>` — launches `openfortivpn` with that config
- `stop` — kills it
- `status` — reports `DISCONNECTED` / `CONNECTING` / `CONNECTED <ip>`
- `apply-routes <file>` — puts the subnets onto the live `pppN` interface
  (this is the **Apply Now** button: routes change with no reconnect)
- `logs` — the tail of `/var/log/fortisplit.log`

Paths coming from the app are checked: absolute only, no `..`, a regular file,
not a symlink, owned by the calling user. Out of the routes file, only lines
matching the IPv4 CIDR format in full are passed to the system `route` command.

**Worth knowing:** the NOPASSWD rule means any process running as you can invoke
this script and, through the openfortivpn config, obtain root. That is a fair
trade on a personal machine; on a managed one, judge for yourself.

## Uninstall

```bash
sudo rm -f /usr/local/bin/fortisplit-vpnctl /etc/sudoers.d/fortisplit /var/log/fortisplit.log
rm -rf /Applications/FortiSplit.app
rm -rf ~/.config/fortisplit      # these configs hold passwords — delete deliberately
```
