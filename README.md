# FortiSplit

**English** · [Русский](README.ru.md)

A macOS menu-bar client for FortiGate SSL-VPN with real split tunneling: only the
subnets you list travel through the tunnel, everything else keeps using your
normal internet connection.

![FortiSplit settings window](docs/screenshot.png)

## How it works

FortiSplit drives [openfortivpn](https://github.com/adrienverge/openfortivpn) with
`set-routes = 0`, so the gateway never touches your routing table. Once the tunnel
is up, the app puts your subnets on the `pppN` interface itself — and can push an
edited list onto a running tunnel without reconnecting.

Configs are plain files in `~/.config/fortisplit`, editable from the app or any
text editor, no root involved. Keep as many as you like and switch the active one
in the settings window; each has its own subnet list.

Exactly two permanent files land outside the app bundle:

| Path | Purpose |
|---|---|
| `/usr/local/bin/fortisplit-vpnctl` | the root script — the only place anything runs as root |
| `/etc/sudoers.d/fortisplit` | a rule letting your user run **only** that script without a password |

That is the entire privileged surface. The GUI itself never runs as root: it asks
the script to start openfortivpn, report status, and lay down routes.

## Install

Requires macOS 13 or newer and openfortivpn:

```bash
brew install openfortivpn
```

Grab the archive from [Releases](../../releases), unpack it and run:

```bash
xattr -dr com.apple.quarantine FortiSplit.app   # ad-hoc signed, so Gatekeeper blocks it after a download
cp -R FortiSplit.app /Applications/
./install.sh                                    # asks for your sudo password once
open /Applications/FortiSplit.app
```

Or build it yourself: `./build-app.sh && ./install.sh`.

A shield icon appears in the menu bar — filled while the tunnel is up, outlined
when it is down. Open **Settings…**, fill in the config template or **Import…** an
existing openfortivpn config, then list your subnets on the **Routes** tab.

On the first connection openfortivpn usually rejects the gateway certificate and
prints its hash (**Show Log**); add `trusted-cert = <hash>` to the config.

## Worth knowing

The NOPASSWD rule means any process running as you can invoke the script and,
through the openfortivpn config it feeds to root, obtain root. That is a fair
trade on a personal machine; on a managed one, judge for yourself. The stricter
alternative — `SMAppService` + XPC — needs a paid Developer ID, which this project
deliberately avoids.

If your VPN requires a one-time code, background startup cannot work; connect
manually with `openfortivpn -o <otp>` and use the app for status and routes only.

## More

- [INSTALL.md](INSTALL.md) — what `install.sh` and the root script do, and how to uninstall
- [docs/architecture.ru.md](docs/architecture.ru.md) — architecture, security notes, build and icon scripts (in Russian)
- [AGENT.md](AGENT.md) — notes for whoever picks this up next
