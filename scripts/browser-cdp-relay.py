#!/usr/bin/env python3
"""Expose Chromium's loopback-only CDP inside the Compose network."""

import os
import pwd
import select
import socket
import socketserver


UPSTREAM = ("127.0.0.1", 9222)
LISTEN = ("0.0.0.0", 9223)
BUFFER_SIZE = 64 * 1024
PID_FILE = "/tmp/browser-cdp-relay.pid"


class RelayHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        try:
            upstream = socket.create_connection(UPSTREAM, timeout=5)
            upstream.settimeout(None)
        except OSError:
            return

        with upstream:
            peers = (self.request, upstream)
            try:
                while True:
                    readable, _, _ = select.select(peers, (), ())
                    for source in readable:
                        data = source.recv(BUFFER_SIZE)
                        if not data:
                            return
                        target = upstream if source is self.request else self.request
                        target.sendall(data)
            except OSError:
                return


class RelayServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def drop_privileges() -> None:
    user = pwd.getpwnam("abc")
    os.setgroups([])
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)


if __name__ == "__main__":
    drop_privileges()
    with open(PID_FILE, "w", encoding="ascii") as pid_file:
        pid_file.write(f"{os.getpid()}\n")
    os.chmod(PID_FILE, 0o600)
    try:
        with RelayServer(LISTEN, RelayHandler) as server:
            server.serve_forever()
    finally:
        try:
            os.unlink(PID_FILE)
        except FileNotFoundError:
            pass
