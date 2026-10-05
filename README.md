<h1 align="center"><img src="assets/godel-wordmark.png" alt="godel" width="330"></h1>

<div align="center">

A small, static Linux init and service supervisor in Hare.

[Architecture](docs/architecture.md) · [Install](docs/install.md) · [First boot](docs/first-boot.md) · [Comparison](docs/comparison.md) · [Benchmarks](docs/benchmarks.md) · [License](LICENSE)

</div>

---

Godel is one static, libc-free binary that runs as PID 1 and supervises
every service on the machine: dependency ordering, restart policies,
readiness gating, per-service logs, `run-as`, atomic reload, recovery.
No allocation after boot; ~360 KB stripped; userspace ready in ~10 ms
on real hardware.

It targets VMs, embedded images, and personal machines on non-systemd
distributions (Artix, Void, Alpine, Gentoo). It is not a systemd
replacement and does not compete with OpenRC, runit, dinit, s6, or GNU
Shepherd; it is small enough to read in one sitting, which is the point.

## Features

- one `epoll` loop: `signalfd`, `timerfd`, one `pidfd` per service
  (SIGCHLD fallback on old kernels)
- cgroup v2 cleanup per service, process-group fallback
- dependency ordering, restart policies with exponential backoff and
  give-up, recovery shell
- readiness on the s6/dinit/nitro wire convention (`notification-fd`),
  `readiness_timeout` release, oneshot completion gates
- config: `/etc/godel/services.conf` + `services.d/` (one service per
  file), merged atomically; SIGHUP reload refuses invalid files
- no fixed service count — storage scales with the configuration at boot
- per-service logs (0600, rotation), `run-as`, `log = no`, oneshots
- per-service shutdown deadlines; SIGKILL only for services that
  outlive their own timeout
- `godelctl status [--json]|list|uptime|boot-report [LOG]|start|stop|
  catlog|reload|reboot|poweroff`
- `godel -t PATH` validation with line-numbered diagnostics

## Build

Hare 0.26.0.1+, Linux, make.

```sh
make          # bin/godel, bin/godelctl, bin/godel-install
make test     # 77 unit tests
```

## Test

```sh
make test-system     # 20 scripted QEMU sessions on a disposable image
tools/soak.sh 50     # 50 boot/reboot cycles, transcripts kept
sh tools/test-compat-install.sh   # installer fixture matrix
```

No root needed; the image lives under `.image/` and never touches the
host bootloader.

## Install

```sh
doas make install-godel BOOTLOADER=grub   # also: limine, extlinux,
                                          # systemd-boot, refind
```

The Hare core (`bin/godel-install`) detects the distro and its
capabilities, generates the desktop service set, validates it, and
stages everything; `tools/install.sh` drives it and adds a separate
**Godel (test)** boot entry — the current default entry is never
touched. Backups land in `/etc/godel/backups`.

## Configuration

```ini
[service "network"]
command = /usr/bin/dhcpcd -q eth0
restart = on-failure

[service "ssh"]
command = /usr/sbin/sshd -D
after = network
```

Keys: `command`, `after`, `restart` (`always|on-failure|never`),
`restart_limit`, `restart_delay`, `shutdown_timeout`, `env`, `type`
(`service|oneshot`), `notification-fd`, `readiness_timeout`, `run-as`,
`log`. Shell-like quoting in `command` and `env`. Full syntax and
semantics: [docs/architecture.md](docs/architecture.md); ready-made
sets in [examples/](examples/).

## Status

Experimental; 1.0.0 waits for sustained real-system testing. Linux
only; prefers pidfds (5.3+) and `cgroup.kill` (5.14+), degrades
gracefully without them.

## License

BSD-2-Clause — see [LICENSE](LICENSE). The linked Hare standard
library is MPL-2.0 on its own terms.
