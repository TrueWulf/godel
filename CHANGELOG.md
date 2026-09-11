# Changelog

## 0.8.0 - 2026-09-11

- Relicensed from GPL-3.0-or-later to BSD-2-Clause; the Hare standard
  library remains MPL-2.0 and permits the larger work.
- Added a readiness mechanism opt-in per service via
  `notification-fd = N` (3..1024): the service is started with the write
  end of a pipe at fd N and becomes ready by writing a newline, the same
  wire convention s6, dinit, and nitro use. `after` gates on readiness
  only where the dependency opted in; plain ordering stays the default.
  A readiness failure degrades to plain ordering with a logged notice.
- Added per-service logging: service stdout/stderr are routed to
  `/var/log/godel/<name>.log` when writable, falling back to
  `/run/godel/logs/<name>.log` on a read-only root, rotated to
  `<name>.log.1` at restart past 64 KiB. The console now carries only
  PID 1's own messages. The status snapshot gained a `ready=` field.
- Changed the test image to boot with `root=... ro` and remount rw via a
  notified `rootfs-rw` oneshot, so dependents start deterministically
  after the remount. Added an opt-in `fsck-root` oneshot before the
  remount that runs `fsck.ext4 -p`, reports honestly that a mounted
  root cannot be checked, and leaves dirty-journal recovery to the
  kernel; proven on a forced-dirty ext4 with a captured kernel recovery
  line.
- Added system sessions proving readiness gating (a late newline delays
  the dependent, a silent notified service holds it indefinitely),
  per-service log placement and rotation, and the fsck hook. All eleven
  sessions pass on both test kernels.
- Reload semantics refined: oneshots that ran to a clean completion are
  no longer re-run by a reload that keeps their identity, and changing
  `notification-fd` now replaces the service like an argv change.
- Fixed a supervisor bug that readiness made visible: the orphan
  reaper's status ring restarted at slot zero on every SIGCHLD, so each
  burst of child exits overwrote the oldest recorded statuses. A service
  whose pidfd signalled after its status was clobbered could never be
  reaped and stalled the event loop; the ring cursor now persists across
  calls. A 50-cycle soak reproduced the stall at boot 8 before the fix
  and the transcript under `.image/soak` keeps the evidence.
- qemu-session now kills its QEMU on every failure path instead of
  leaking it.
- Unit tests grew from 46 to 56, covering the notification-fd parser and
  the readiness gating (dep_satisfied, ready_starts).

## 0.7.0-beta.3 - 2026-09-11

- Replaced the Python serial-console harness with a static Hare binary
  (`cmd/qemu-session`, -k/-d/-s/-l/-a/-m/-x/-n, same session-script
  format). The repository is now Hare and POSIX shell only; verified by
  rerunning all eight system sessions and 15-cycle soaks on both test
  kernels.
- Fixed the harness not draining console output before a verify check,
  which had made that check depend on output timing.

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
