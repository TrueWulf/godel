# Godel architecture

Godel is a static, freestanding (no libc) Hare binary that runs as PID 1.
This document describes how the pieces fit together and which kernel
features each path relies on.

## Process model

- One `epoll(7)` event loop multiplexes a signalfd, a timerfd, and one
  pidfd per service. Signal delivery is fully synchronous: SIGTERM,
  SIGINT, SIGUSR1, SIGHUP, and SIGCHLD arrive through the signalfd.
- Services are forked children. Every child calls `setsid()`, so each
  service is a process group and `kill(-pgid)` reaches the whole tree.
  `agetty`/`getty` then acquire the controlling terminal with
  `TIOCSCTTY`, which is what makes serial login work.
- Preferred supervision is `pidfd_open` (Linux 5.3+): exit notification
  through epoll, no SIGCHLD scanning. When a pidfd cannot be opened or
  registered, Godel falls back to reaping in the SIGCHLD handler with
  `wait4(WNOHANG)`; supervision continues with coarser timing.
- Cleanup uses cgroup v2 (one subgroup per service under
  `/sys/fs/cgroup/godel`): `cgroup.kill` (Linux 5.14+) sweeps orphaned
  grandchildren. Without cgroup v2 the process group alone is used.

## Shutdown sequence

1. SIGTERM to every running service's process group (the graceful
   phase). Each service's `shutdown_timeout` sets the deadline, capped
   at 30 seconds.
2. On deadline: SIGKILL to every remaining process group plus
   `cgroup.kill` per service to catch orphans that escaped their parent.
3. One second later: reap, sync, `reboot(RB_POWER_OFF|RB_RESTART)`.

Ctrl-Alt-Del is enabled via `reboot(RB_ENABLE_CAD)`; the kernel turns a
console CAD into SIGINT, which follows the poweroff path.

## Configuration and reload

`/etc/godel/services.conf` is parsed into a fixed-size snapshot: at most
16 services, 8 argv entries, 4 `env` entries, and 4 `after` references
per service, all pointing into a 16 KiB buffer. Parsing mutates the
buffer in place (NUL-terminating words) and never allocates.

The tokenizer understands double quotes, single quotes, backslash
escapes, empty quoted arguments, and concatenation of quoted and bare
segments — a `sh -c "mountpoint -q /home || mount /dev/vdb /home"` line
reaches the shell as one argv element. Unterminated quotes are rejected
with a line-numbered diagnostic.

Reload is atomic: the new file is parsed into the *inactive* set first.
On any parse error the active set is untouched and the refusal is
logged. On success, services are matched by name plus argv:

- matched and unchanged: keep the running process, reset restart
  bookkeeping (same slot) or move the runtime to the new slot and
  re-target its pidfd epoll tag;
- removed: SIGTERM per policy;
- added or changed: started in dependency order.

`after` is start ordering only, never readiness. A oneshot that has not
finished does not block later services; chain readiness explicitly by
making later jobs depend on earlier oneshots only when a plain ordering
is genuinely enough.

## Failure paths

- A service that exhausts `restart_limit` enters `gave-up`. When no
  service remains `up` or in `backoff`, Godel starts a recovery shell on
  the console exactly once per configuration generation. Exiting the
  shell re-reads the configuration; if it is valid, normal operation
  resumes, otherwise the machine powers off.
- If all services simply finish (no failures), Godel powers off — a
  useful property for one-shot boot jobs with no long-running service.
- `SIGHUP`-reload refusals never disturb running services; the recovery
  shell path and boot path share the same validation.

## Observability

- `/run/godel/status`: one tab-separated line per service —
  `name`, `state` (`stopped|up|backoff|gave-up`), `pid=`, `restarts=`.
  Written after every state change; read by `godelctl status`.
- `/run/godel/godel.log` (+ `.1`): the same lines as the console, in a
  two-generation 64 KiB ring file.
- The console (fds 0/1/2 of PID 1) carries every log line.

## Control interface

`godelctl` is the stable operator interface. `status` reads the status
snapshot; `reload`, `reboot`, and `poweroff` send `SIGHUP`, `SIGUSR1`,
and `SIGTERM` to PID 1 respectively. The signal contract is the
documented transport; the `godelctl` command names are what operators
and scripts should rely on.

## Kernel requirements

| Feature | Minimum kernel | Fallback without it |
|---|---|---|
| Boot as PID 1, devtmpfs, cgroup v2 mount | 4.6 | none (hard requirement) |
| pidfd supervision (`pidfd_open`) | 5.3 | SIGCHLD reaping |
| Full-tree cleanup (`cgroup.kill`) | 5.14 | process-group signals |
| Test image root disk (virtio-blk, ext4) | built into kernel | initramfs with modules |

Tested kernels: 6.18.48-1-lts and 7.2.2-zen1-1-zen, 50 consecutive
boot/reboot cycles each (see `docs/benchmarks.md`). Older kernels than
5.14 work with reduced cleanup guarantees; kernels without cgroup v2
mounted at `/sys/fs/cgroup` fall back to process groups automatically.
