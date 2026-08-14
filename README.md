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

Requires macOS 13 or newer. First install openfortivpn — FortiSplit drives it,
it is not bundled:

```bash
brew install openfortivpn
```

Then download **FortiSplit-x.y.z.pkg** from [Releases](../../releases) and open
it. The installer places the app in `/Applications` and the root script in
`/usr/local/bin`, and adds the sudoers rule for your user. Nothing else.

### Letting macOS open it

The package is signed ad-hoc, not with a paid Developer ID, so on the first
attempt macOS refuses to open it. This is expected and you only do it once:

![Allowing the app in System Settings](docs/gatekeeper.png)

1. Double-click the `.pkg` — a warning appears, dismiss it.
2. Open **System Settings → Privacy & Security** and scroll down to **Security**.
3. Next to the message about the blocked file press **Open Anyway** (the
   screenshot shows a placeholder name) and confirm with Touch ID or your
   password.
4. Double-click the `.pkg` again — this time it installs.

If you prefer the terminal, this route skips the dialog entirely:

```bash
sudo installer -pkg FortiSplit-0.1.0.pkg -target /
```

Add `-allowUntrusted` if it complains about the missing signature.

Building from source instead: `./build-app.sh && ./install.sh`.

### First run

Launch FortiSplit from `/Applications` — a shield icon appears in the menu bar,
filled while the tunnel is up, outlined when it is down. Open **Settings…**,
press **New** for a config template or **Import…** to pick an existing
openfortivpn config, then list your subnets on the **Routes** tab.

On the first connection openfortivpn usually rejects the gateway certificate and
prints its hash (**Show Log**); add `trusted-cert = <hash>` to the config.

### Uninstall

```bash
sudo rm -f /usr/local/bin/fortisplit-vpnctl /etc/sudoers.d/fortisplit /var/log/fortisplit.log
sudo pkgutil --forget local.fortisplit.installer
rm -rf /Applications/FortiSplit.app
rm -rf ~/.config/fortisplit      # these configs hold passwords — delete deliberately
```

## Worth knowing

The NOPASSWD rule means any process running as you can invoke the script and,
through the openfortivpn config it feeds to root, obtain root. That is a fair
trade on a personal machine; on a managed one, judge for yourself. The stricter
alternative — `SMAppService` + XPC — needs a paid Developer ID, which this project
deliberately avoids.

If your VPN requires a one-time code, background startup cannot work; connect
manually with `openfortivpn -o <otp>` and use the app for status and routes only.

## More

- [docs/architecture.md](docs/architecture.md) — architecture, what the root script does, security notes, build and icon scripts
- [AGENT.md](AGENT.md) — notes for whoever picks this up next
