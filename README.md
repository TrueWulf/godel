<h1 align="center"><img src="assets/godel-wordmark.png" alt="godel" width="330"></h1>

<div align="center">

A small, static Linux init and service supervisor in Hare.

[Architecture](docs/architecture.md) · [Install](docs/install.md) · [First boot](docs/first-boot.md) · [Comparison](docs/comparison.md) · [Benchmarks](docs/benchmarks.md) · [License](LICENSE)

</div>

---

Godel is one static, libc-free binary that runs as PID 1 and supervises
every service: dependency ordering, restart policies, readiness gating,
per-service logs, `run-as`, atomic reload, recovery. No allocation after
boot; ~360 KB stripped. It is the running system init on the
development machine (Artix, GRUB and Limine).

Built for VMs, embedded images, and personal machines on non-systemd
distros (Artix, Void, Alpine, Gentoo). Small enough to read in one
sitting.

## Features

- one `epoll` loop: `signalfd`, `timerfd`, one `pidfd` per service
- cgroup v2 cleanup per service, process-group fallback
- dependency ordering, restart backoff with give-up, recovery shell
- readiness via `notification-fd`, oneshot completion gates
- `/etc/godel/services.conf` + `services.d/`, atomic merge; SIGHUP
  reload refuses invalid files
- no fixed service count; per-service logs, `run-as`, shutdown
  deadlines with SIGKILL only for services that outlive their own
  timeout
- `godelctl status [--json]|list|uptime|boot-report|start|stop|catlog|
  reload|reboot|poweroff`
- `godel -t PATH` validation with line-numbered diagnostics

## Build

Hare 0.26.0.1+, Linux, make.

```sh
make
make test
```

## Test

```sh
make test-system
make qemu-alpine
sh tools/test-compat-install.sh
```

No root needed; images live under `.image/` and never touch the host
bootloader.

## Install

```sh
doas make install-godel BOOTLOADER=grub
```

`bin/godel-install` detects the distro, generates the desktop service
set, validates it, and adds a separate **Godel (test)** boot entry —
the current default is never touched. Bootloaders: grub, limine,
extlinux, systemd-boot, refind. Backups land in `/etc/godel/backups`.

## Configuration

```ini
[service "network"]
command = /usr/bin/dhcpcd -q eth0
restart = on-failure

[service "ssh"]
command = /usr/sbin/sshd -D
after = network
```

Keys: `command`, `after`, `restart`, `restart_limit`, `restart_delay`,
`shutdown_timeout`, `env`, `type`, `notification-fd`,
`readiness_timeout`, `run-as`, `log`. Full syntax:
[docs/architecture.md](docs/architecture.md); ready-made sets in
[examples/](examples/).

## Status

Experimental. Runs on one machine, in daily use; no distribution
packaging yet. Linux only; prefers pidfds (5.3+) and `cgroup.kill`
(5.14+), degrades gracefully without them.

## License

BSD-2-Clause — see [LICENSE](LICENSE). The linked Hare standard library
is MPL-2.0 on its own terms.
