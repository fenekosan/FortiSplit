# FortiSplit — how it is put together

**English** · [Русский](architecture.ru.md)

The details for anyone digging in: architecture, on-disk layout, the security
model, build scripts. For a short description and installation see the
[README](../README.md).

A macOS menu-bar app that brings up a FortiGate SSL-VPN through
[`openfortivpn`](https://github.com/adrienverge/openfortivpn) in **split-tunnel**
mode: only the subnets from the list go through the tunnel, all other traffic
takes the normal internet route. Plus a route-list editor and a state indicator
right in the status bar.

This is a working Ubuntu setup (openfortivpn + `set-routes=0` + custom routes)
ported to macOS. On Linux the routes were added by a NetworkManager dispatcher;
here they are put onto the live `pppN` by our own root script, which the app
calls after connecting.

> The build targets **personal use**: ad-hoc signature, no Apple Developer
> account, no notarization. Privileges come from `sudoers` rather than
> `SMAppService` (the latter requires a real signature).

---

## Architecture

```
┌──────────────────────────┐   edits directly   ┌────────────────────────────┐
│  FortiSplit.app          │───────────────────▶│  ~/.config/fortisplit/     │
│  (menu bar, LSUIElement) │  no root, plain    │   <name>.config  (0600)    │
│   runs as your user      │  FileManager       │   <name>.routes            │
└───────────┬──────────────┘                    │   active                   │
            │                                   └────────────────────────────┘
            │  sudo -n fortisplit-vpnctl start <config>
            │  sudo -n fortisplit-vpnctl apply-routes <routes>
            │  (allowed in /etc/sudoers.d/fortisplit, NOPASSWD)
            ▼
┌──────────────────────────┐
│  fortisplit-vpnctl       │  ← the single root boundary (bash)
│  start / stop / status   │     checks paths, starts the VPN,
│  apply-routes / logs     │     puts subnets on pppN via route(8)
└───────────┬──────────────┘
            │ launches                         ┌──────────────────────────┐
            ▼                                  │  pppd  →  pppN interface │
┌──────────────────────────┐──────uses────────▶│  (does not touch routes) │
│  openfortivpn -c config  │                   └──────────────────────────┘
│  (set-routes = 0)        │
└──────────────────────────┘
```

Why this shape: a GUI process must not be handed root, but there is also no
reason to scatter files across the system. Configs are ordinary user files the
app edits by itself; root is needed for exactly two things that are impossible
otherwise — starting openfortivpn and laying routes onto the ppp interface.

Routes are laid down by `vpnctl` itself through `apply-routes`, not by an
`/etc/ppp/ip-up` hook as it was done earlier. That way no file of ours ends up
being triggered by somebody else's PPP connection, and the app just calls the
command once the status turns `CONNECTED` (and again after the list is edited).
Repeating the call is harmless: an already-installed route is simply not added
twice.

## On-disk layout after installation

| What | Where | Mode |
|---|---|---|
| The app | `/Applications/FortiSplit.app` | ad-hoc signed |
| VPN config (holds the password) | `~/.config/fortisplit/<name>.config` | yours, 0600 |
| Routes of that config | `~/.config/fortisplit/<name>.routes` | yours |
| Name of the active config | `~/.config/fortisplit/active` | yours |
| Root script | `/usr/local/bin/fortisplit-vpnctl` | root:wheel 0755 |
| Sudo permission | `/etc/sudoers.d/fortisplit` | root:wheel 0440 |
| Session log | `/var/log/fortisplit.log` | root |

Exactly two permanent files live outside the bundle: the root script and the
sudoers rule. Fewer is not possible, and here is why. A NOPASSWD rule must point
at a file you cannot rewrite without a password: `/Applications/FortiSplit.app`
is writable by an admin silently, so a script inside the bundle would mean any
process running as you could swap it and get root. Everything else (ppp hooks,
route snapshots, pid files, a directory in `/etc`) has been removed from the
project.

The system part is installed by `install.sh`, which also creates
`~/.config/fortisplit` with a template config. `/var/log/fortisplit.log` appears
on its own at the first launch.

There can be several configs: each has its own routes file next to it, and
`active` holds the name of the one used when connecting. Switching configs
switches the set of subnets too — nothing is left over from the previous VPN.

---

## What the Mac needs to build

- macOS 13+ (for `MenuBarExtra`)
- Xcode Command Line Tools: `xcode-select --install` (gives `swift`, `codesign`)
- openfortivpn: `brew install openfortivpn`

## Building the installer

To share the app without handing over the sources:

```bash
./scripts/make-pkg.sh
```

You get `dist/FortiSplit-<version>.pkg` — that is the release artifact. Its
payload is the app plus the root script; the sudoers rule is written by a
`postinstall` script, because it depends on who is sitting at the machine
(`stat -f%Su /dev/console`) and cannot be baked into the payload. The rule is
validated with `visudo` before being installed, exactly as `install.sh` does it.

`pkgbuild --ownership recommended` matters here: without it the root script would
arrive owned by whoever built the package, and the sudoers rule would be trusting
a file the user can rewrite.

The package is **not signed** — that needs a Developer ID Installer certificate,
i.e. a paid account. So the recipient has to allow it once through System
Settings; the README walks through that. Unlike `install.sh`, the installer does
not seed a template config: the app creates `~/.config/fortisplit` on first launch
and the "New" button writes the template.

`install.sh` stays in the repo for installing straight from a source checkout.

## Build and install

```bash
# 1. Build the .app (ad-hoc signing is part of the script)
./build-app.sh

# 2. Install the privileged parts (asks for the sudo password once)
./install.sh

# 3. Fill in the VPN password (or later, in the app's settings window)
nano ~/.config/fortisplit/example.config     # or import your own in the settings window

# 4. Check that sudoers works without a password
sudo -n /usr/local/bin/fortisplit-vpnctl status    # -> DISCONNECTED

# 5. Install the app and launch it
cp -R FortiSplit.app /Applications/
open /Applications/FortiSplit.app
```

If the app does not start because of Gatekeeper (moved from a VM through a
browser or AirDrop — it caught quarantine):

```bash
xattr -dr com.apple.quarantine /Applications/FortiSplit.app
```

or once through **System Settings → Privacy & Security → "Open Anyway"**.

## Using it

The status-bar icon is described under [Icons](#icons) below.

Menu: **Connect / Disconnect**, **Settings…**, **Show Log**, **Quit**.

The settings window: config selection on top, two tabs below. Both work on the
config picked in the header — including a non-active one. The buttons on the
right depend on the tab, because "import" means different things on them.

- **Config** — the raw text of `<name>.config`, exactly as openfortivpn reads it.
  Buttons: "Make Active", "New", "Import…" (adds a new config from a file on
  disk), "Delete". The active config cannot be deleted, make another one active
  first.
- **Routes** — the CIDR subnet list of that config. "Save" writes the file;
  **"Apply Now"** puts the subnets onto the running tunnel with no reconnect —
  the button is enabled only while this config's tunnel is up. "Import…" here
  **replaces** the subnet list of the selected config with the contents of a
  file. Creating, deleting and switching the active config is not possible from
  this tab — that is the Config tab's business.

Editing configs needs no sudo: they are ordinary files in your home directory,
you can keep them in git, copy them between machines and edit them in any editor.

"Apply Now" only **adds** subnets: a route you removed from the list stays
installed until you reconnect. There is no need to remove it separately — it
disappears together with the `pppN` interface.

---

## Icons

The bundle icon sits ready in `Resources/FortiSplit.icns`, the build script puts
it into the `.app`. If the artwork changed — drop a new 1024×1024 square into
`Resources/AppIcon.png` and rebuild the size set:

```bash
./scripts/make-icns.sh
```

Finder and the Dock cache icons: if an old one is still shown after reinstalling,
`touch /Applications/FortiSplit.app` and restarting the Dock (`killall Dock`)
helps.

The status-bar icons are derived from the same artwork by a script:

```bash
swift scripts/make-menubar-icon.swift
```

It takes the whole emblem and subtracts the tube with the globe from it — the
result is a filled shield with a cut. Plus an outlined version. Both files are
template images (black + alpha), so macOS picks the color for the light and dark
menu bar itself.

States in the bar:

| State | Icon |
|---|---|
| Connected | filled shield |
| Connecting | the same, dimmed |
| Disconnected | outlined shield |
| Error | `exclamationmark.shield` (an SF Symbol) |

The error state deliberately stayed an SF Symbol: it has to stand out from the
row, while still keeping the shield motif.

## Interface language

The app and the scripts speak English and Russian. The app does not ask: macOS
picks `ru.lproj` or `en.lproj` from the bundle by the system language (System
Settings → General → Language & Region), English is the fallback.

The scripts look at `LANG`/`LC_ALL`, and `FORTISPLIT_LANG=en|ru` overrides that:

```bash
FORTISPLIT_LANG=en ./install.sh
```

`fortisplit-vpnctl` takes a `--lang=en|ru` flag before the command — the app
always passes it explicitly, because `sudo` scrubs the environment and `LANG`
cannot be relied on:

```bash
sudo -n /usr/local/bin/fortisplit-vpnctl --lang=ru status
```

## The first FortiGate certificate

On the very first connection openfortivpn may refuse with a message about an
unverified gateway certificate and print its SHA256. Copy the hash into the
"Config" tab (or straight into `~/.config/fortisplit/<name>.config`):

```
trusted-cert = <hash>
```

The easiest way is to run it manually once and see the hint:

```bash
sudo openfortivpn -c ~/.config/fortisplit/<name>.config
```

## 2FA / OTP

If the VPN requires a one-time code, a background start cannot work — it needs
interactive input. Connect manually with `-o <otp>` then; in that mode use the
app only for editing routes and watching the status.

## Security notes

`fortisplit-vpnctl` is allowed in sudoers without a password, so any process
running as your user can start it. That is acceptable on a personal machine, but
it is worth understanding what it means: the script feeds the root openfortivpn
process a config that you wrote yourself, and openfortivpn has the `pppd-*`
family of options which load arbitrary code into root. So this scheme is in
principle equivalent to "root on demand" — regardless of where the configs live.

That is exactly why moving the configs out of `/etc` into the home directory made
nothing worse: the password was already available to any process of the user
(through the very same `sudo -n fortisplit-vpnctl read-config` command), while
six root commands for editing files and the name parsing inside the root script
went away.

What the script does check, so as not to shoot itself in the foot: the path must
be absolute, contain no `..`, be a regular file (not a symlink) and belong to
whoever called sudo. The subnet list is parsed line by line, and only a line that
matched a strict IPv4 CIDR in full is passed to `route` — everything else is
skipped with a message.

If a stricter model is needed, that is the `SMAppService` + XPC + Developer ID
road (see AGENT.md, the "Ways forward" section).

## Uninstall

```bash
sudo rm -f /usr/local/bin/fortisplit-vpnctl \
           /etc/sudoers.d/fortisplit \
           /var/log/fortisplit.log
sudo pkgutil --forget local.fortisplit.installer   # if installed from the .pkg
rm -rf /Applications/FortiSplit.app
rm -rf ~/.config/fortisplit          # these configs hold passwords — delete deliberately
```

## Repository layout

```
FortiSplit/
├── Package.swift              SwiftPM, executable target
├── Sources/FortiSplit/
│   ├── FortiSplitApp.swift     @main, MenuBarExtra + settings window
│   ├── VPNController.swift     runs sudo vpnctl, polls status
│   ├── ConfigStore.swift       reads/writes ~/.config/fortisplit
│   ├── MenuContentView.swift   menu contents
│   ├── SettingsWindowView.swift config selection + tabs
│   └── TextFileEditor.swift    one text file editing pane
├── Resources/
│   ├── Info.plist              LSUIElement=true (status bar only)
│   ├── AppIcon.png             icon source, 1024×1024
│   ├── FortiSplit.icns         assembled bundle icon
│   ├── MenuIcon*.png           status-bar glyphs (+@2x)
│   └── en.lproj, ru.lproj      interface strings
├── scripts/
│   ├── fortisplit-vpnctl       root entry point: starting the VPN and routes
│   ├── make-icns.sh            AppIcon.png -> FortiSplit.icns
│   ├── make-menubar-icon.swift AppIcon.png -> status-bar glyphs
│   └── make-pkg.sh             the .pkg installer
├── config/
│   ├── example.config          config template
│   └── example.routes          empty subnet list
├── build-app.sh                builds the .app + ad-hoc signature
├── install.sh                  installs the privileged parts
├── docs/
│   ├── architecture.md         this document
│   ├── architecture.ru.md      this document in Russian
│   ├── screenshot.png          settings window for the README
│   └── gatekeeper.png          allowing the app to run
├── README.md, README.ru.md     short description and installation
└── AGENT.md                    instructions for a coding agent
```
