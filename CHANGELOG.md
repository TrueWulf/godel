# Changelog

## 0.7.0-beta.2 - 2026-09-11

- Fixed inherited-orphan zombies: PID 1 now reaps every exited child via
  `wait4(-1)` and hands tracked services their statuses from a small
  ring buffer instead of only waiting on known pids.
- Fixed a cgroup attach race: the service child now joins its cgroup
  before `execve`, so grandchildren can no longer be born outside the
  group and survive `cgroup.kill`.
- Made cgroup directory removal retry briefly while an asynchronous
  kill drains the group, so released services leave no residue.
- Added the orphans session proving no stray processes, no zombies, and
  a released cgroup after SIGKILL of a service with children, and
  hardened every session against matching its own command echo.
- Improved godelctl error output (`cannot signal PID 1 (poweroff):
  Operation not permitted` instead of a bare errno) and gave the
  Makefile real build dependencies.

## 0.7.0-beta.1 - 2026-09-11

- Added a bootable QEMU test image: `tools/build-rootfs.sh`,
  `tools/build-image.sh`, `tools/run-system.sh`, and `make qemu-system`.
  Godel runs as PID 1 from an ext4 virtio disk with busybox, serial
  login through getty, and a persistent root filesystem.
- Added real boot oneshots: hostname, root remount rw, `/tmp` tmpfs,
  and optional `/home` and `/var` mounts that tolerate missing disks.
- Added `godelctl` with `status`, `reload`, `reboot`, and `poweroff`
  over the documented PID 1 signal contract and status snapshot.
- Added quote-aware parsing for `command` and `env`: double and single
  quotes, backslash escapes, empty quoted arguments, and concatenation,
  all allocation-free in place. Unterminated quotes are rejected with a
  line-numbered diagnostic.
- Fixed reload restarting every unchanged running service: matched
  services in the same slot kept their runtime instead of being reset.
- Fixed graceful shutdown: stop now sends SIGTERM before the SIGKILL
  escalation; cgroup tree sweep happens at the escalation, not upfront.
- Added sessions and harnesses: `tools/qemu-session.py`, six
  `tools/sessions/*.session` scenarios including SIGKILL recovery,
  SIGTERM-trapping services, corrupted-config recovery, reload of
  added/changed/removed oneshots, and poweroff during restart backoff.
- Ran 50 consecutive boot/reboot soak cycles on both
  `vmlinuz-linux-lts` and `vmlinuz-linux-zen` with retained transcripts.
- Documented `docs/first-boot.md` and `docs/architecture.md` with a
  kernel compatibility table; refreshed README and benchmarks with
  measured numbers.

## 0.6.0 - 2026-09-10

- Made the restart policy a Hare tagged union, so restart delays only exist on
  restart outcomes.
- Added SIGCHLD fallback reaping when a pidfd cannot be opened or registered.
- Enabled Ctrl-Alt-Del handling for virtual-machine consoles.
- Added the allocation-free `/run/godel/status` service-state snapshot.
- Replaced destructive log truncation with two-generation rotation:
  `godel.log` and `godel.log.1`.
- Moved reload matching into tested library code and added a 27th unit test.
- Tightened event helpers to return `rt::errno` instead of uninformative
  booleans.
- Added `env = NAME=VALUE` and `type = oneshot` for self-hosted boot jobs.
- Added `make install`, a VM-oriented example configuration, and GPL-3.0-or-later licensing.
