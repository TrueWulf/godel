<h1 align="center"><img src="assets/godel-wordmark.png" alt="godel" width="330"></h1>

<p align="center">A static Linux init and service supervisor written in Hare.</p>

<p align="center">

[Architecture](docs/architecture.md) · [First boot](docs/first-boot.md) · [Migration](docs/migration.md) · [Comparison](docs/comparison.md) · [Benchmarks](docs/benchmarks.md) · [License](LICENSE)

</p>

Godel is one static binary, built without libc, that runs as PID 1 and
supervises every service on the machine. It is written in Hare, about
3,150 lines of it (3,900 with tests), with the whole configuration in a
fixed 32 KiB snapshot and no allocation after boot. The stripped binary
is 361 KB, PID 1 sits at around 392 KB of resident memory on a running
desktop, and userspace is ready in about ten milliseconds.

It targets VMs, embedded images, and personal machines, including
non-systemd distributions such as Artix, Void, Alpine, and Gentoo.
It is not a systemd replacement, and it does not compete with OpenRC,
runit, dinit, s6, or GNU Shepherd; those have years of production use
behind them. Godel is small enough to read in one sitting, which is
the point.

## Why Hare

Hare builds static binaries without libc by default and keeps its
runtime small enough to hold in your head. Godel leans on that: service
exit decisions are tagged unions, the configuration lives in fixed
storage, and kernel interfaces the standard library does not wrap are
called as plain syscalls. Footprint and build time are measured in
[docs/benchmarks.md](docs/benchmarks.md).

## Features

- PID 1 boot setup: procfs, sysfs, devtmpfs, cgroup v2, `/run` tmpfs, console
- `epoll` event loop with `signalfd`, `timerfd`, and `pidfd`
- SIGCHLD fallback supervision when a pidfd is unavailable
- cgroup v2 process-tree cleanup with a process-group fallback
- dependency ordering, restart policies, exponential backoff, give-up
- readiness opt-in per service (`notification-fd`), on the same wire
  convention as s6, dinit, and nitro; `after` gates on readiness where
  declared, with an optional `readiness_timeout` that releases dependents
- single-file config plus a scanned `/etc/godel/services.d/` directory
  (one service per file, name = file name) merged into one snapshot
- `godel -t PATH`: parse-only validation with line-numbered diagnostics
- per-service stdout/stderr logs under `/var/log/godel` (fallback
  `/run/godel/logs`), mode 0600, a wall-clock header at every open,
  size rotation, `log = no` console opt-out
- `run-as = user[:group]` identity switching before exec
- atomic SIGHUP reload: an invalid file never replaces the active config
- quote-aware `command` and `env` parsing (double/single quotes, escapes)
- graceful shutdown: SIGTERM, service deadline, SIGKILL escalation
- Ctrl-Alt-Del support for VM consoles
- recovery shell for bad configurations or persistent failure
- allocation-free `/run/godel/status`, two-generation `/run/godel/godel.log`
- per-service `env` entries and `type = oneshot` boot jobs
- `godelctl status|list|start|stop|catlog|reload|reboot|poweroff`

## Build

Hare 0.26.0.1 or newer, a Linux host, and make.

```sh
make          # build bin/godel and bin/godelctl
make test     # 69 unit tests
```

The Makefile looks for `hare` in `~/tools/hare/bin`; override with
`make HARE=hare` when it is already on `PATH`.

## Testing

`make test-system` boots a disposable QEMU image through 17 scripted
sessions (kill and restart, readiness gating and timeouts, atomic
reload, recovery from corrupt configs, per-service logging, run-as,
orphan floods, graceful poweroff). `tools/soak.sh 50` runs 50
boot/reboot cycles and keeps the transcripts. The image lives under
`.image/`, needs no root, and never touches the host bootloader.
[docs/first-boot.md](docs/first-boot.md) walks the image by hand, and
[docs/comparison.md](docs/comparison.md) compares Godel with nitro,
runit, s6, and dinit feature by feature.

## Examples

Ready-to-adapt service sets live in [examples/](examples/):

- `examples/desktop/` is a workstation set: fsck, udev, dbus, elogind,
  NetworkManager, a getty
- `examples/server/` is a small server or VM set: DHCP, sshd, cron,
  syslog
- `examples/services.conf` is a minimal VM image with a readiness-gated
  application

Each directory says what to adapt (device nodes, daemon paths); a set
installs with a copy plus `godel -t`.

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

Keys: `command`, `after`, `restart` (`always`, `on-failure`, `never`),
`restart_limit`, `restart_delay`, `shutdown_timeout`, `env`, `type`
(`service` or `oneshot`), `notification-fd`, `readiness_timeout`,
`run-as`, `log` (`yes`/`no`).

`after` is start ordering. A dependency that declares
`notification-fd = N` (3..1024) holds its dependents until it writes a
newline to fd N; s6, dinit, and nitro use the same convention.
`readiness_timeout = 5s` bounds that wait: at the deadline the service
is stopped, marked failed, and its dependents start. Everywhere else,
plain ordering applies.

`run-as = user[:group]` drops the service to one uid/gid after the
cgroup attach and before `execve`; there are no supplementary groups.
`log = no` keeps a service on the console instead of a log file, which
is what you want for gettys.

`/etc/godel/services.d/*.conf` is scanned in name order and merged into
the same snapshot. A directory file holds exactly one service named
after the file (`sshd.conf` defines `[service "sshd"]`); a duplicate
name across sources refuses the whole configuration. `godel -t PATH`
validates a file, a config root, or the directory with line-numbered
diagnostics and a nonzero exit, without starting anything.

Limits are deliberate and fixed: 64 services, 8 command arguments, 4
environment entries, 4 dependencies, 31-byte names. See
[examples/](examples/) for complete sets.

Service stdout and stderr go to `/var/log/godel/<name>.log` (fallback
`/run/godel/logs/<name>.log` while the root is read-only), mode 0600,
rotated to `<name>.log.1` past 64 KiB. The supervisor writes a
wall-clock header at every open; lines between headers are the child's
own bytes and carry no timestamps, because the child writes the
descriptor directly.

`command` and `env` values are tokenized like a shell subset: double
and single quotes group whitespace, backslash escapes the next byte
outside quotes, quoted segments concatenate with bare text, and an
unterminated quote is a diagnostic.

## Control interface

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

`reload`, `reboot`, and `poweroff` are `SIGHUP`, `SIGUSR1`, and
`SIGTERM` to PID 1, so they work from any process. `start` and `stop`
go through the root-only `/run/godel/ctl` FIFO, one `verb name` line
per write. A manual stop is never retried by the restart policy until
an explicit start.

## Status

Godel 0.9.0 is experimental. 1.0.0 waits for sustained real-system
testing. The supervisor is Linux-only and prefers pidfds (Linux 5.3+)
and `cgroup.kill` (Linux 5.14+); on older kernels the SIGCHLD and
process-group paths keep it working with less isolation. The
compatibility table in
[docs/architecture.md](docs/architecture.md) has details and the
tested kernel list.

## License

BSD-2-Clause, see [LICENSE](LICENSE). The Hare standard library, which
the binaries link, is MPL-2.0 on its own terms.
