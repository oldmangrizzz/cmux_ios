#!/usr/bin/env python3
"""cmuxd-remote WebSocket relay server — test harness.

Mimics the cmuxd-remote daemon's WebSocket relay protocol so the iOS app
can connect during development.  Spawns a local PTY with a shell and
bridges I/O over JSON-RPC over WebSocket.

Usage:
    python3 Tests/cmuxd_relay_server.py [--port 9123] [--token abc...]

Protocol (reverse-engineered from cmuxd-remote v0.63.2):

    → {"id":1, "method":"session.basic", "params":{"cols":80,"rows":24}}
    ← {"id":1, "result":{"session_id":"<uuid>"}}

    → {"method":"write", "params":{"data_base64":"<base64>"}}   (fire-and-forget)
    ← {"method":"data", "params":{"data_base64":"<base64>"}}    (unsolicited)

    → {"id":2, "method":"session.resize", "params":{"session_id":"...","cols":100,"rows":40}}
    ← {"id":2, "result":true}

    → {"id":3, "method":"session.close", "params":{"session_id":"..."}}
    ← {"id":3, "result":true}

    → {"id":0, "method":"relay.auth", "params":{"token":"..."}}
    ← {"id":0, "result":true}
"""

import argparse
import asyncio
import json
import os
import pty
import signal
import struct
import sys
import termios
import fcntl
import uuid

import websockets


# ── PTY bridge ──────────────────────────────────────────────────────────────

class PtyBridge:
    """Manages a PTY with a shell process, bridging to a WebSocket."""

    def __init__(self, cols: int = 80, rows: int = 24):
        self.cols = cols
        self.rows = rows
        self.fd: int | None = None
        self.child_pid: int | None = None
        self.session_id = str(uuid.uuid4())

    def spawn(self):
        """Fork a shell inside a PTY."""
        pid, fd = pty.fork()
        if pid == 0:
            # Child — start a shell
            shell = os.environ.get("SHELL", "/bin/bash")
            os.execvp(shell, [shell])
            sys.exit(1)
        self.fd = fd
        self.child_pid = pid
        self._set_winsize(self.cols, self.rows)

    def _set_winsize(self, cols: int, rows: int):
        """Update the PTY window size."""
        if self.fd is not None:
            packed = struct.pack("HHHH", rows, cols, 0, 0)
            fcntl.ioctl(self.fd, termios.TIOCSWINSZ, packed)

    def write(self, data: bytes):
        """Write data from the WebSocket into the PTY (user input)."""
        if self.fd is not None:
            os.write(self.fd, data)

    def resize(self, cols: int, rows: int):
        self.cols = cols
        self.rows = rows
        self._set_winsize(cols, rows)

    def close(self):
        """Close the PTY and kill the child."""
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None
        if self.child_pid is not None:
            try:
                os.kill(self.child_pid, signal.SIGHUP)
            except ProcessLookupError:
                pass
            self.child_pid = None

    def fileno(self) -> int:
        assert self.fd is not None
        return self.fd


# ── WebSocket relay handler ─────────────────────────────────────────────────

async def handle_client(websocket, token: str | None):
    """Handle a single WebSocket client connection."""

    pty_bridge = PtyBridge()
    pty_bridge.spawn()

    authenticated = token is None  # skip auth if no token configured
    pending_responses: dict[int, asyncio.Future] = {}

    async def pty_reader():
        """Read from PTY and send as JSON-RPC data messages."""
        loop = asyncio.get_event_loop()
        while True:
            try:
                data = await loop.run_in_executor(None, os.read, pty_bridge.fileno(), 4096)
                if not data:
                    break
                b64 = __import__("base64").b64encode(data).decode()
                msg = json.dumps({"method": "data", "params": {"data_base64": b64}})
                await websocket.send(msg)
            except (OSError, ConnectionError):
                break

    async def ws_reader():
        """Read JSON-RPC messages from WebSocket and dispatch."""
        nonlocal authenticated

        async for raw in websocket:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue

            method = msg.get("method")
            msg_id = msg.get("id")
            params = msg.get("params", {})

            # ── Authentication ──
            if method == "relay.auth":
                if token is not None and params.get("token") == token:
                    authenticated = True
                    await send_result(msg_id, True)
                elif token is None:
                    authenticated = True  # no token configured, accept anything
                    await send_result(msg_id, True)
                else:
                    authenticated = False
                    await send_error(msg_id, "authentication failed")
                continue

            if not authenticated:
                await send_error(msg_id, "not authenticated")
                continue

            # ── session.basic ──
            if method == "session.basic":
                cols = params.get("cols", 80)
                rows = params.get("rows", 24)
                pty_bridge.resize(cols, rows)
                await send_result(msg_id, {"session_id": pty_bridge.session_id})
                continue

            # ── session.resize ──
            if method == "session.resize":
                cols = params.get("cols", pty_bridge.cols)
                rows = params.get("rows", pty_bridge.rows)
                pty_bridge.resize(cols, rows)
                await send_result(msg_id, True)
                continue

            # ── session.close ──
            if method == "session.close":
                await send_result(msg_id, True)
                pty_bridge.close()
                continue

            # ── write (terminal input) ──
            if method == "write":
                b64 = params.get("data_base64", "")
                data = __import__("base64").b64decode(b64)
                pty_bridge.write(data)
                # Fire-and-forget — no response
                continue

            # ── Unknown method ──
            await send_error(msg_id, f"unknown method: {method}")

    async def send_result(msg_id: int | None, result):
        if msg_id is None:
            return
        await websocket.send(json.dumps({"id": msg_id, "result": result}))

    async def send_error(msg_id: int | None, message: str):
        if msg_id is None:
            return
        await websocket.send(json.dumps({"id": msg_id, "error": message}))

    try:
        # Run both readers concurrently
        await asyncio.gather(pty_reader(), ws_reader())
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        pty_bridge.close()


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="cmuxd-remote relay test server")
    parser.add_argument("--port", type=int, default=9123, help="Listen port (default: 9123)")
    parser.add_argument("--token", type=str, default=None,
                        help="Optional auth token (64 hex chars)")
    parser.add_argument("--host", type=str, default="0.0.0.0", help="Bind address")
    args = parser.parse_args()

    async def start():
        print(f"cmuxd relay test server listening on ws://{args.host}:{args.port}/")
        if args.token:
            print(f"  auth token: {args.token}")
        else:
            print("  auth: disabled")
        print(f"  shell: {os.environ.get('SHELL', '/bin/bash')}")
        print()
        print("Connect from the iOS app using transport type 'cmuxd Relay'")
        print("Send SIGINT (Ctrl+C) to stop.")

        async def handler(websocket):
            await handle_client(websocket, args.token)

        async with websockets.serve(handler, args.host, args.port):
            await asyncio.get_running_loop().create_future()  # run forever

    try:
        asyncio.run(start())
    except KeyboardInterrupt:
        print("\nShutting down.")


if __name__ == "__main__":
    main()
