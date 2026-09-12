<h1 align="center"><img src="assets/godel-wordmark.png" alt="godel" width="330"></h1>

<p align="center">
  A simple, static Linux init and service supervisor written in Hare.
</p>

<p align="center">
  <a href="https://codeberg.org/TrueWulf/godel">Source</a> ·
  <a href="docs/architecture.md">Architecture</a> ·
  <a href="docs/first-boot.md">First boot</a> ·
  <a href="docs/migration.md">Migration</a> ·
  <a href="docs/comparison.md">Comparison</a> ·
  <a href="docs/benchmarks.md">Benchmarks</a>
</p>

Godel is for VMs, embedded images, and personal systems where a transparent
PID 1 is more useful than a distribution-sized service manager.

It is **not** a systemd replacement and does not try to compete with OpenRC,
runit, dinit, s6, or GNU Shepherd. Godel is an experiment in a simple,
allocation-free Hare init: explicit enough to audit, strict enough to fail
visibly, and based on current Linux process primitives.

## Why Hare

Hare produces a static binary without libc by default and keeps the language
and runtime deliberately small. Godel measures its static PID 1 footprint and
build time in [`docs/benchmarks.md`](docs/benchmarks.md).

Godel uses Hare tagged unions for service-exit decisions, fixed storage rather
than a heap, and explicit Linux syscalls only where the standard library does
not cover the kernel interface.

## Features

- PID 1 boot setup: procfs, sysfs, devtmpfs, cgroup v2, `/run` tmpfs, console
- `epoll` event loop with `signalfd`, `timerfd`, and `pidfd`
- SIGCHLD fallback supervision if a pidfd is unavailable
- cgroup v2 process-tree cleanup with process-group fallback
- dependency ordering, restart policies, exponential backoff, and give-up
- readiness opt-in per service (`notification-fd`), wire-compatible with
  the s6/dinit/nitro convention; `after` gates on readiness where declared,
  with an optional `readiness_timeout` that releases dependents
- single-file config plus a scanned `/etc/godel/services.d/` directory
  (one service per file, name = file name) merging into one snapshot
- `godel -t PATH`: parse-only validation with line-numbered diagnostics
- per-service stdout/stderr logging under `/var/log/godel` (fallback
  `/run/godel/logs`), mode 0600, supervisor wall-clock header at every
  (re)open, size rotation at restart, `log = no` console opt-out
- per-service `run-as = user[:group]` identity switching before exec
- atomic SIGHUP config reload: invalid files never replace the active config
- quote-aware `command` and `env` parsing (double/single quotes, escapes)
- graceful shutdown: SIGTERM, service deadline, SIGKILL escalation, reboot
- Ctrl-Alt-Del support for VM consoles
- recovery shell for bad configurations or persistent service failure
- allocation-free `/run/godel/status` and two-generation `/run/godel/godel.log`
- per-service `env = NAME=VALUE` entries and `type = oneshot` boot jobs
- `godelctl status|reload|reboot|poweroff` over a documented control interface

## Build

Requires Hare 0.26.0.1 or newer, a Linux host, and `make`.

```sh
make          # build bin/godel and bin/godelctl
make test     # 69 unit tests
```

The Makefile defaults to `~/tools/hare/bin/hare`; override it with
`make HARE=hare` when Hare is already on `PATH`.

## QEMU test image

```sh
make qemu-system      # build image and boot it with serial console
make test-system      # scripted login, supervision, and failure sessions
tools/soak.sh 50      # 50 boot/reboot cycles with retained transcripts
```

`make qemu-system` builds a disposable ext4 disk image under `.image/`
(no initramfs, no root privileges) and boots it: Godel runs as PID 1 with
busybox on the disk, agetty on `ttyS0` and `tty1`, serial login as
`root`/`godel`, oneshots for hostname, root remount, `/tmp`, and optional
`/home`/`/var` mounts. Log in, run `godelctl status`, kill a service and
watch it restart, reload the config, reboot and power off —
[`docs/first-boot.md`](docs/first-boot.md) walks through the whole flow.

The scripted sessions in `tools/sessions/` prove the failure paths and
the subsystems: SIGKILL recovery, SIGTERM-trapping services,
corrupted configurations rescued from the recovery shell, reload of
added, changed, and removed oneshots, readiness gating with a late
newline, a readiness timeout that releases stuck dependents, per-service
logs with rotation, a service running under `run-as` with its own log,
booting from `services.d` alone, an fsck hook on a forced-dirty ext4
root and on non-root disks, and poweroff during restart backoff. An
honest comparison with nitro, runit, s6, and dinit is in
[`docs/comparison.md`](docs/comparison.md).

Older initramfs smoke tests are still available:

```sh
make qemu-reboot      # backoff, give-up, reload, reboot
make qemu-poweroff    # graceful SIGTERM shutdown
make qemu-badconfig   # recovery-shell path
```

They use `tools/run-qemu.sh`, require `qemu-system-x86_64`, `cpio`, and a
kernel at `/boot/vmlinuz-linux-lts` (override with `KERNEL=/path/to/kernel`),
and do not modify the host bootloader.

## Configuration

`/etc/godel/services.conf` is a small INI-like file:

```ini
[service "network"]
command = /usr/bin/dhcpcd -q eth0
restart = on-failure
restart_delay = 1s

[service "ssh"]
command = /usr/sbin/sshd -D
after = network
```

Supported keys are `command`, `after`, `restart` (`always`, `on-failure`, or
`never`), `restart_limit`, `restart_delay`, `shutdown_timeout`, `env`,
`type` (`service` or `oneshot`), `notification-fd`, `readiness_timeout`,
`run-as`, and `log` (`yes`/`no`). `after` is start ordering; a dependency
that declares `notification-fd = N` (3..1024) makes its dependents wait
until it writes a newline to fd N — the same convention s6, dinit, and
nitro use. `readiness_timeout = 5s` bounds that wait: at the deadline the
service is stopped and marked failed, and its dependents start. Plain
ordering applies everywhere else.

`run-as = user[:group]` drops the service to one uid/gid after the cgroup
attach, before `execve`; there are no supplementary groups. `log = no`
keeps a service on the console instead of a per-service log file (for
gettys on other vtys).

The same snapshot also merges `/etc/godel/services.d/*.conf`, scanned in
name order. A directory file holds exactly one service whose name equals
the file name (`sshd.conf` defines `[service "sshd"]`); a duplicate name
across sources is a diagnostic that refuses the whole configuration.
`godel -t PATH` validates a file, a config root, or the directory with
line-numbered diagnostics and a nonzero exit, without starting anything.
Limits are intentional and fixed: 64 services, 8 command arguments,
4 environment entries, 4 dependencies, and 31-byte names. See
[`examples/services.conf`](examples/services.conf) for a bootable
VM-oriented configuration.

Service stdout and stderr are routed to `/var/log/godel/<name>.log`
(fallback `/run/godel/logs/<name>.log` while the root is read-only), mode
0600, rotated to `<name>.log.1` at restart past 64 KiB. The supervisor
writes a wall-clock header line at every (re)open; the child's own output
between headers is raw and untimestamped, because the child writes the
file descriptor directly. The console stays reserved for PID 1's
messages.

`command` and `env` values are tokenized like a shell subset: double and
single quotes group whitespace, backslash escapes the next byte outside
quotes, and quoted segments concatenate with bare text. Unterminated quotes
are rejected with a line-numbered diagnostic.

## Control interface

`godelctl` is the stable operator interface:

```sh
godelctl status           # dump /run/godel/status (name, state, pid, restarts)
godelctl list             # same output, explicit alias
godelctl start <service>  # manual start (also clears a backoff timer)
godelctl stop <service>   # manual stop; restart policies do not fire
godelctl catlog <service> # dump /var/log/godel/<service>.log
godelctl reload           # re-read the config; refuses invalid files atomically
godelctl reboot
godelctl poweroff
```

`reload`, `reboot`, and `poweroff` send `SIGHUP`, `SIGUSR1`, and `SIGTERM`
to PID 1; those signals are the documented transport and also work from any
process. `start` and `stop` go through the root-only `/run/godel/ctl` FIFO,
one `verb name` line per write; a manual stop is never retried by the
restart policy until an explicit start.

## Status

Godel 0.9.0 is experimental software. A stable release is reserved
for 1.0.0 after sustained real-system testing. It is Linux-only and relies
on pidfds for its preferred supervision path (Linux 5.3+) and `cgroup.kill`
for full cgroup tree cleanup (Linux 5.14+). The SIGCHLD and process-group
paths keep the supervisor functional on older kernels with reduced
isolation; the compatibility table in
[`docs/architecture.md`](docs/architecture.md) has the details and the
tested kernel list.

## License

BSD-2-Clause. See [LICENSE](LICENSE).
