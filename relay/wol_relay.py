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
