#!/usr/bin/env python3
"""Scripted serial-console sessions for the Godel test image.

Boots the image under QEMU with the serial console on pipes, replays an
expect/send script, and records the full console transcript to a log
file. The transcript is the evidence for every test: exit status 0 means
every expect matched in the captured output.

Script format, one action per line; blank lines and #comments ignored:
  expect PATTERN [timeout=SECONDS]   wait for PATTERN in unread output
  send TEXT                          write TEXT plus a newline
  write TEXT                         write TEXT verbatim (no newline)
  sleep SECONDS                      pause the replay, output still logged
  comment TEXT                       only recorded in the transcript log

Patterns are plain substrings matched against the raw console bytes
(decoded with errors="replace").
"""

import argparse
import os
import select
import subprocess
import sys
import time

CHUNK = 4096


def fail(message: str) -> "NoReturn":  # type: ignore[name-defined]
    sys.stderr.write("qemu-session: FAIL: %s\n" % message)
    sys.exit(1)


def stop(qemu: subprocess.Popen) -> None:
    if qemu.poll() is None:
        qemu.terminate()
        try:
            qemu.wait(timeout=5)
        except subprocess.TimeoutExpired:
            qemu.kill()
            qemu.wait()


def parse_script(path: str):
    actions = []
    with open(path, "r", encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            parts = stripped.split(None, 1)
            verb = parts[0]
            argument = parts[1] if len(parts) > 1 else ""
            if verb == "expect":
                timeout = 60.0
                words = argument.split()
                if len(words) >= 2 and words[-1].startswith("timeout="):
                    timeout = float(words[-1][len("timeout="):])
                    argument = " ".join(words[:-1])
                if not argument:
                    fail("script line %d: expect needs a pattern" % number)
                actions.append(("expect", argument, timeout))
            elif verb == "send":
                actions.append(("send", argument + "\n", 0.0))
            elif verb == "write":
                actions.append(("write", argument, 0.0))
            elif verb == "verify":
                # Deferred check: PATTERN must exist anywhere in the
                # transcript read so far, regardless of consume position.
                if not argument:
                    fail("script line %d: verify needs a pattern" % number)
                actions.append(("verify", argument, 0.0))
            elif verb == "sleep":
                actions.append(("sleep", "", float(argument)))
            elif verb == "comment":
                actions.append(("comment", argument, 0.0))
            else:
                fail("script line %d: unknown action %r" % (number, verb))
    if not actions:
        fail("script is empty")
    return actions


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--kernel", required=True)
    parser.add_argument("--disk", required=True)
    parser.add_argument("--script", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--append", default=(
        "console=ttyS0,115200 root=/dev/vda rw init=/sbin/godel panic=-1"))
    parser.add_argument("--memory", default="256M")
    parser.add_argument("--extras", action="store_true",
                        help="attach the optional /home and /var disks")
    parser.add_argument("--no-reboot", action="store_true",
                        help="pass -no-reboot to QEMU")
    args = parser.parse_args()

    for required in (args.kernel, args.disk, args.script):
        if not os.path.exists(required):
            fail("not found: %s" % required)

    command = [
        "qemu-system-x86_64",
        "-m", args.memory,
        "-kernel", args.kernel,
        "-drive", "file=%s,format=raw,if=virtio" % args.disk,
        "-append", args.append,
        "-nographic",
    ]
    if args.extras:
        repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        command += [
            "-drive", "file=%s/.image/home.ext4,format=raw,if=virtio" % repo,
            "-drive", "file=%s/.image/var.ext4,format=raw,if=virtio" % repo,
        ]
    if args.no_reboot:
        command.append("-no-reboot")

    actions = parse_script(args.script)
    transcript = open(args.log, "wb")

    qemu = subprocess.Popen(
        command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT)

    buffer = ""
    consumed = 0

    def pump(timeout: float) -> bool:
        """Read console output for up to `timeout` seconds.

        Returns False on EOF. Data always lands in `buffer`, so the
        caller re-checks its pattern after every pump call.
        """
        nonlocal buffer
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return True
            readable, _, _ = select.select([qemu.stdout], [], [],
                                           min(remaining, 0.2))
            if not readable:
                continue
            chunk = os.read(qemu.stdout.fileno(), CHUNK)
            if not chunk:
                return False
            transcript.write(chunk)
            transcript.flush()
            buffer += chunk.decode("utf-8", errors="replace")

    for action in actions:
        try:
            kind = action[0]
            if kind == "comment":
                transcript.write(("---- %s\n" % action[1]).encode())
                continue
            if kind == "sleep":
                time.sleep(action[2])
                continue
            if kind in ("send", "write"):
                try:
                    qemu.stdin.write(action[1].encode())
                    qemu.stdin.flush()
                except BrokenPipeError:
                    fail("console closed before %s: %r" % (kind, action[1]))
                continue
            if kind == "verify":
                if action[1] not in buffer:
                    fail("verify failed: %r not in transcript so far:\n%s"
                         % (action[1], buffer[-2000:]))
                transcript.write(("---- verified: %s\n"
                                  % action[1]).encode())
                continue
            pattern, timeout = action[1], action[2]
            deadline = time.monotonic() + timeout
            while True:
                index = buffer.find(pattern, consumed)
                if os.environ.get("QEMU_SESSION_DEBUG"):
                    sys.stderr.write("dbg: find(%r, %d)=%d len=%d\n"
                                     % (pattern, consumed, index, len(buffer)))
                if index >= 0:
                    consumed = index + len(pattern)
                    if os.environ.get("QEMU_SESSION_DEBUG"):
                        sys.stderr.write("dbg: matched %r -> consumed=%d\n"
                                         % (pattern, consumed))
                    break
                if not pump(0.2):
                    if buffer.find(pattern, consumed) >= 0:
                        break
                    tail = buffer[-2000:]
                    fail("console closed while waiting for %r; tail:\n%s"
                         % (pattern, tail))
                if time.monotonic() > deadline:
                    tail = buffer[-2000:]
                    absolute = buffer.find(pattern)
                    fail("timeout after %.0fs waiting for %r "
                         "(consumed=%d, len=%d, first-occurrence=%d); tail:\n%s"
                         % (timeout, pattern, consumed, len(buffer),
                            absolute, tail))
        except SystemExit:
            stop(qemu)
            raise

    # Give trailing output a moment, then terminate QEMU unless it already
    # exited (a poweroff in the script exits QEMU by itself).
    try:
        if pump(1.0):
            qemu.terminate()
            qemu.wait(timeout=10)
        else:
            qemu.wait(timeout=10)
    except subprocess.TimeoutExpired:
        qemu.kill()

    transcript.close()
    status = qemu.returncode
    if status is not None and status not in (0, -15):
        sys.stderr.write("qemu-session: QEMU exited with status %s\n" % status)
        sys.exit(1)
    sys.stderr.write("qemu-session: OK (%d bytes transcript)\n"
                     % os.path.getsize(args.log))
    sys.exit(0)


if __name__ == "__main__":
    main()
