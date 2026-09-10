# Godel

Godel is a small, static Linux init and service supervisor written in
[Hare](https://harelang.org). It is for VMs, embedded images, and personal
systems where a transparent PID 1 is more useful than a distribution-sized
service manager.

It is **not** a systemd replacement and does not try to compete with runit,
dinit, or other mature general-purpose init systems. Godel is an experiment in
what a modern, allocation-free Hare init can look like: small enough to audit,
strict enough to fail visibly, and based on current Linux process primitives.

## Why Hare

Hare produces a static binary without libc by default and keeps the language
and runtime deliberately small. Godel 0.6.0 measures its static PID 1
footprint and build time in [`docs/benchmarks.md`](docs/benchmarks.md).

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
- graceful shutdown: SIGTERM, service deadline, SIGKILL escalation, reboot
- Ctrl-Alt-Del support for VM consoles
- recovery shell for bad configurations or persistent service failure
- allocation-free `/run/godel/status` and two-generation `/run/godel/godel.log`
- per-service `env = NAME=VALUE` entries and `type = oneshot` boot jobs

## Build

Requires Hare 0.26.0.1 or newer, a Linux host, and `make`.

```sh
make          # build bin/godel
make test     # 27 unit tests
```

The Makefile defaults to `~/tools/hare/bin/hare`; override it with
`make HARE=hare` when Hare is already on `PATH`.

## QEMU smoke tests

```sh
make qemu-reboot      # backoff, give-up, reload, reboot
make qemu-poweroff    # graceful SIGTERM shutdown
make qemu-badconfig   # recovery-shell path
```

These use `tools/run-qemu.sh`, require `qemu-system-x86_64`, `cpio`, and a
kernel at `/boot/vmlinuz-linux-lts` (override with `KERNEL=/path/to/kernel`).
They build an isolated initramfs and do not modify the host bootloader.

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
`type` (`service` or `oneshot`). Limits are
intentional and fixed: 16 services, 8 command arguments, 4 dependencies, and
31-byte names. See [`examples/services.conf`](examples/services.conf) for a
bootable VM-oriented configuration.

PID 1 signals: `SIGTERM`/`SIGINT` power off, `SIGUSR1` reboots, and `SIGHUP`
validates and reloads configuration. `/run/godel/status` exposes one
tab-separated line per service: name, state, PID, and restart count.

## Status

Godel 0.6.0-beta.1 is experimental software. It is Linux-only and relies on
pidfds for its preferred supervision path (Linux 5.3+) and `cgroup.kill` for
full cgroup tree cleanup (Linux 5.14+). The SIGCHLD and process-group paths
keep the supervisor functional on older kernels with reduced isolation.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
