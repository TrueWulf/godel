<h1 align="center"><img src="assets/godel-wordmark.png" alt="godel" width="330"></h1>

<p align="center">
  A simple, static Linux init and service supervisor written in Hare.
</p>

<p align="center">
  <a href="https://codeberg.org/TrueWulf/godel">Source</a> ·
  <a href="docs/architecture.md">Architecture</a> ·
  <a href="docs/first-boot.md">First boot</a> ·
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
make test     # 46 unit tests
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

The scripted sessions in `tools/sessions/` prove the failure paths: SIGKILL
recovery, SIGTERM-trapping services, corrupted configurations rescued from
the recovery shell, reload of added, changed, and removed oneshots, and
poweroff during restart backoff.

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
`never`), `restart_limit`, `restart_delay`, `shutdown_timeout`, `env`, and
`type` (`service` or `oneshot`). `after` is start ordering only, never
readiness. Limits are intentional and fixed: 16 services, 8 command
arguments, 4 environment entries, 4 dependencies, and 31-byte names. See
[`examples/services.conf`](examples/services.conf) for a bootable
VM-oriented configuration.

`command` and `env` values are tokenized like a shell subset: double and
single quotes group whitespace, backslash escapes the next byte outside
quotes, and quoted segments concatenate with bare text. Unterminated quotes
are rejected with a line-numbered diagnostic.

## Control interface

`godelctl` is the stable operator interface:

```sh
godelctl status     # dump /run/godel/status (name, state, pid, restarts)
godelctl reload     # re-read the config; refuses invalid files atomically
godelctl reboot
godelctl poweroff
```

`reload`, `reboot`, and `poweroff` send `SIGHUP`, `SIGUSR1`, and `SIGTERM`
to PID 1; those signals are the documented transport and also work from any
process.

## Status

Godel 0.7.0-beta.3 is experimental software. A stable release is reserved
for 1.0.0 after sustained real-system testing. It is Linux-only and relies
on pidfds for its preferred supervision path (Linux 5.3+) and `cgroup.kill`
for full cgroup tree cleanup (Linux 5.14+). The SIGCHLD and process-group
paths keep the supervisor functional on older kernels with reduced
isolation; the compatibility table in
[`docs/architecture.md`](docs/architecture.md) has the details and the
tested kernel list.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
