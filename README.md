# ImmichLauncher

**ImmichLauncher** is a small open-source Android app (Flutter) that lets you keep your
self-hosted [Immich](https://immich.app) server **powered off when you don't need it**
and wake it with one tap — at home or anywhere in the world.

<p align="center">
  <img src="docs/screenshots/home.png" alt="Home screen" width="250">
  <img src="docs/screenshots/wizard.png" alt="Setup wizard" width="250">
  <img src="docs/screenshots/settings.png" alt="Settings" width="250">
</p>

> _Screenshots are placeholders: add your own to `docs/screenshots/`._

## What it does

| Button | What happens |
| --- | --- |
| **Open Locally** | Checks if the server answers on your home network. If not, it sends a **Wake-on-LAN magic packet** (UDP broadcast, port 9), shows a progress indicator while it waits for the server and Immich to come up, then opens Immich at `http://<local-ip>:<immich-port>`. |
| **Open Remotely** | Makes sure **Tailscale** is connected on the phone, turning it on in the background if it isn't (it only opens the Tailscale app if that fails, e.g. when you are logged out). Checks if the server answers on its Tailscale IP. If not, it calls `GET http://<relay-ip>:<relay-port>/wake` on your **relay device**, which wakes the server for you. Once the server is up, it opens Immich at `http://<server-tailscale-ip>:<immich-port>`. |
| **Status indicator** | Checks the server every 30 seconds (and whenever you return to the app): **green** = online (and through which route), **red** = offline. |
| **Shut down server** | Visible only while the server is online. After a confirmation dialog, it logs in over **SSH** (to the local or Tailscale IP, depending on what you used last) and runs `sudo shutdown now`. |

Other details:

- A **first-run setup wizard** collects the configuration; everything can be changed later from **Settings** (gear icon).
- No values are hardcoded: every IP, MAC address, port and username comes from your configuration.
- Configuration is stored with `shared_preferences`. The SSH password is **never stored unless you tick "Remember password"**, and then it is kept in encrypted storage backed by the Android Keystore (`flutter_secure_storage`).
- SSH host keys are pinned on first use (TOFU). If the server's key changes, shutdown is refused until you reset trusted keys in Settings.
- Errors are reported with plain-language messages (e.g. "The relay device did not answer. Check that it is online…").

## How it works

```
             at home (Wi-Fi)                         away (mobile data / other Wi-Fi)

  ┌───────┐  WoL magic packet   ┌────────┐     ┌───────┐   Tailscale    ┌─────────────┐  WoL   ┌────────┐
  │ Phone │ ──────────────────▶ │ Server │     │ Phone │ ─────────────▶ │ Relay (Pi)  │ ─────▶ │ Server │
  │       │ ◀── Immich :2283 ── │        │     │       │  GET /wake     │ always on   │  LAN   │        │
  └───────┘                     └────────┘     │       │ ◀──────── Immich over Tailscale ────── │        │
                                               └───────┘                                        └────────┘
```

Wake-on-LAN packets are broadcasts, so they cannot cross the internet or a VPN. When you are
away, a tiny always-on device on your home LAN (Raspberry Pi, old laptop, NAS, …) receives the
request through Tailscale and sends the magic packet locally.

## Requirements

- **An Immich server** (typically Ubuntu + Docker) with:
  - **Wake-on-LAN enabled** in the BIOS/UEFI and on the network card (see below). A wired Ethernet connection is strongly recommended: most Wi-Fi cards can't be woken.
  - **Tailscale** installed and set to start at boot (`sudo systemctl enable --now tailscaled`).
  - **OpenSSH server** (`sudo apt install openssh-server`) and a user that can run `sudo` (used by the shutdown button).
  - Immich containers set to start automatically (`restart: always` in `docker-compose.yml`, which is the default).
- **A relay device**: any always-on Linux device on the **same LAN** as the server, with **Tailscale** and **Python 3 + Flask**, running the relay script below.
- **An Android phone** with:
  - the [Tailscale app](https://play.google.com/store/apps/details?id=com.tailscale.ipn), logged into the same tailnet;
  - the [Immich app](https://play.google.com/store/apps/details?id=app.alextran.immich) (if it's missing, ImmichLauncher opens the web UI in the browser instead).

## Setup

### 1. Enable Wake-on-LAN on the server

1. In the BIOS/UEFI, enable **Wake on LAN** / **Power On By PCI-E** / **Resume by LAN** (the name varies) and, if present, disable **ErP / Deep Sleep**.
2. On Ubuntu, find your Ethernet interface and its MAC address:
   ```bash
   ip link show
   # 2: enp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
   #     link/ether 68:1d:ef:4a:6b:da brd ff:ff:ff:ff:ff:ff   <- MAC address
   ```
3. Enable WoL on the card and make it persistent (replace `enp3s0`):
   ```bash
   sudo apt install ethtool
   sudo ethtool enp3s0 | grep Wake-on        # "Wake-on: g" means enabled
   sudo ethtool -s enp3s0 wol g
   ```
   To persist it with NetworkManager: `sudo nmcli connection modify "<connection name>" 802-3-ethernet.wake-on-lan magic`.
   With netplan, add `wakeonlan: true` under your interface and run `sudo netplan apply`.
4. Give the server a **fixed local IP** (a DHCP reservation in your router) and note it.
5. Note the server's Tailscale IP: `tailscale ip -4`.

### 2. Set up the relay device

1. Install Tailscale, log in, and note its Tailscale IP: `tailscale ip -4`.
2. Install Flask and copy the [relay script](#relay-script) (also in [`relay/wol_relay.py`](relay/wol_relay.py)):
   ```bash
   sudo apt install python3-flask        # or: pip install flask
   sudo mkdir -p /opt/immich-launcher-relay
   sudo cp relay/wol_relay.py /opt/immich-launcher-relay/
   ```
3. Try it:
   ```bash
   python3 /opt/immich-launcher-relay/wol_relay.py --mac 68:1D:EF:4A:6B:DA
   curl http://<relay-tailscale-ip>:8765/wake   # from another tailnet device: should wake the server
   ```
4. Run it as a service so it survives reboots: edit `User=`, `WOL_MAC` (and optionally `RELAY_HOST`) in [`relay/wol-relay.service`](relay/wol-relay.service), then
   ```bash
   sudo cp relay/wol-relay.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now wol-relay
   journalctl -u wol-relay -f
   ```

> **Security:** the relay has no authentication: anyone who can reach it can wake your server (and nothing else).
> Don't expose its port to the internet. Set `RELAY_HOST` to the relay's Tailscale IP so it only
> listens on your tailnet, and/or restrict it with Tailscale ACLs.

### 3. Install the app

Download the APK from the [Releases](../../releases) page, or build it yourself (see [Building](#building-from-source)).

### 4. First-run wizard

On first launch ImmichLauncher asks for:

| Field | Example | Where to find it |
| --- | --- | --- |
| Server local IP | `192.168.1.10` | `ip -4 addr` on the server, or your router's device list |
| Server MAC address | `68:1D:EF:4A:6B:DA` | `ip link show` on the server (`link/ether` value) |
| Server Tailscale IP | `100.101.102.103` | `tailscale ip -4` on the server |
| Relay device Tailscale IP | `100.64.0.2` | `tailscale ip -4` on the relay device |
| Relay port | `8765` (default) | the `--port` / `RELAY_PORT` you started the relay with |
| SSH username | `ubuntu` | your Ubuntu username (`whoami` on the server) |
| SSH port | `22` (default) | `Port` in `/etc/ssh/sshd_config` |
| Immich port | `2283` (default) | host port of `immich-server` in `docker-compose.yml` |

<p align="center">
  <img src="docs/screenshots/wizard-step1.png" alt="Wizard – home network" width="220">
  <img src="docs/screenshots/wizard-step2.png" alt="Wizard – Tailscale" width="220">
  <img src="docs/screenshots/wizard-step3.png" alt="Wizard – server access" width="220">
</p>

### 5. Configure the Immich app (once) — required for remote access

The Immich app stores its own server address, and Android gives other apps no way to change it. If you
logged in with the local IP, Immich keeps using it even when ImmichLauncher opened it remotely, so it
can't load anything away from home. Fix it once, inside the Immich app:

1. Log in (either address works).
2. Open **Settings → Networking** and enable **Automatic URL switching**.
3. **Local network**: set your home Wi-Fi name and `http://<server-local-ip>:2283`
   (Immich asks for location permission so it can read the Wi-Fi name).
4. **External network**: add `http://<server-tailscale-ip>:2283`.

Immich then picks the right address by itself every time it starts.

> Alternative: make the relay a Tailscale **subnet router** (`sudo tailscale set --advertise-routes=192.168.1.0/24`
> and approve the route in the Tailscale admin console). The local IP is then reachable over Tailscale too,
> so a single address works everywhere.

### Optional: shutdown without typing the sudo password

ImmichLauncher sends your password to `sudo` over the SSH session, so no extra configuration is needed.
If you prefer not to give the SSH user full sudo rights, you can allow only shutdown:

```bash
echo "$USER ALL=(root) NOPASSWD: /usr/sbin/shutdown" | sudo tee /etc/sudoers.d/immich-launcher
sudo chmod 440 /etc/sudoers.d/immich-launcher
```

## Relay script

Save as `wol_relay.py` on the relay device (identical to [`relay/wol_relay.py`](relay/wol_relay.py)).
It exposes `GET /wake` (sends the magic packet) and `GET /health`.

```python
#!/usr/bin/env python3
"""ImmichLauncher Wake-on-LAN relay.

Run this on an always-on device (Raspberry Pi, NAS, router, ...) that is on
the same LAN as your Immich server and connected to Tailscale. When the
ImmichLauncher app calls GET /wake, the relay broadcasts a Wake-on-LAN magic
packet on the LAN to wake the server.

Configuration (environment variables or command-line flags):

  WOL_MAC        / --mac        MAC address of the server (required)
  WOL_BROADCAST  / --broadcast  Broadcast address   (default 255.255.255.255)
  WOL_PORT       / --wol-port   WoL UDP port        (default 9)
  RELAY_HOST     / --host       Address to listen on (default 0.0.0.0;
                                use your Tailscale IP to listen only there)
  RELAY_PORT     / --port       HTTP port           (default 8765)

Example:
  pip install flask
  python3 wol_relay.py --mac 68:1D:EF:4A:6B:DA --host 100.64.0.2
"""

import argparse
import logging
import os
import re
import socket
import sys

from flask import Flask, jsonify

log = logging.getLogger("wol_relay")


def parse_mac(mac: str) -> bytes:
    hex_digits = re.sub(r"[:\-.]", "", mac.strip())
    if not re.fullmatch(r"[0-9A-Fa-f]{12}", hex_digits):
        raise ValueError(f"invalid MAC address: {mac!r}")
    return bytes.fromhex(hex_digits)


def magic_packet(mac: str) -> bytes:
    """6 bytes of 0xFF followed by the MAC address repeated 16 times."""
    return b"\xff" * 6 + parse_mac(mac) * 16


def send_wol(mac: str, broadcast: str, port: int) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(magic_packet(mac), (broadcast, port))


def create_app(mac: str, broadcast: str, wol_port: int) -> Flask:
    app = Flask(__name__)

    @app.get("/wake")
    def wake():
        try:
            send_wol(mac, broadcast, wol_port)
        except OSError as e:
            log.exception("failed to send magic packet")
            return jsonify(ok=False, error=f"Failed to send magic packet: {e}"), 500
        log.info("magic packet sent to %s via %s:%d", mac, broadcast, wol_port)
        return jsonify(ok=True, message=f"Magic packet sent to {mac}")

    @app.get("/health")
    def health():
        return jsonify(ok=True)

    return app


def main() -> int:
    parser = argparse.ArgumentParser(description="ImmichLauncher Wake-on-LAN relay")
    parser.add_argument("--mac", default=os.environ.get("WOL_MAC"),
                        help="MAC address of the server to wake")
    parser.add_argument("--broadcast", default=os.environ.get("WOL_BROADCAST", "255.255.255.255"),
                        help="broadcast address (default: 255.255.255.255)")
    parser.add_argument("--wol-port", type=int, default=int(os.environ.get("WOL_PORT", "9")),
                        help="Wake-on-LAN UDP port (default: 9)")
    parser.add_argument("--host", default=os.environ.get("RELAY_HOST", "0.0.0.0"),
                        help="address to listen on (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=int(os.environ.get("RELAY_PORT", "8765")),
                        help="HTTP port to listen on (default: 8765)")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    if not args.mac:
        parser.error("the server MAC address is required (--mac or WOL_MAC)")
    try:
        parse_mac(args.mac)
    except ValueError as e:
        parser.error(str(e))

    app = create_app(args.mac, args.broadcast, args.wol_port)
    log.info("listening on http://%s:%d — waking %s", args.host, args.port, args.mac)
    app.run(host=args.host, port=args.port)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

## Building from source

Requirements: Flutter (stable; tested with 3.47), the Android SDK and a JDK 17 or newer.
`flutter doctor` should show both **Flutter** and **Android toolchain** as green.

```bash
git clone https://github.com/tommasocarraro/immich-launcher.git
cd immich-launcher
flutter pub get
flutter analyze
flutter test
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

> The release build is signed with the debug key (Flutter's default), which is fine for sideloading.
> To publish your own builds, configure a release keystore as described in
> [Flutter's Android deployment guide](https://docs.flutter.dev/deployment/android#sign-the-app).

### Project layout

```
lib/
├── main.dart                         # app entry: wizard on first run, else home
├── constants.dart                    # defaults, timeouts, package names
├── controllers/launcher_controller.dart  # open/wake/poll/shutdown flows
├── models/                           # config model, field specs, validators
├── screens/                          # setup wizard, home, settings
├── services/                         # WoL, relay HTTP, SSH, probes, Tailscale, platform bridge
└── widgets/                          # form fields, status indicator
android/app/src/main/kotlin/.../MainActivity.kt  # VPN detection, launching apps/URLs
relay/                                # relay script + systemd unit
```

## Troubleshooting

| Problem | Things to check |
| --- | --- |
| "The server did not come online" (local) | The phone is on your home Wi-Fi (not a guest network); WoL is enabled in BIOS **and** with `ethtool`; the server is wired. Some routers block broadcasts from Wi-Fi to Ethernet: wake from the relay instead. |
| "The relay device did not answer" | `systemctl status wol-relay` on the relay; `curl http://<relay-ip>:8765/health` from another tailnet device. |
| Server is on, but Immich doesn't answer | `docker compose ps` on the server; check the Immich port in Settings. |
| Remote status stays red after boot | Tailscale must start at boot on the server: `sudo systemctl enable tailscaled`. |
| Immich opens but can't load (remote) | The Immich app is still using the local IP: set up Automatic URL switching (setup step 5). |
| Tailscale app opens instead of connecting in the background | Open Tailscale once, log in and accept the VPN permission prompt; after that it connects silently. |
| "SSH host key changed" | Expected after reinstalling the server: Settings → Reset trusted SSH host keys. |

## Contributing

Issues and pull requests are welcome. Please run `flutter analyze` and `flutter test` before submitting.

## License

[MIT](LICENSE)
