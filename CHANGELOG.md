# Changelog

## 0.9.6 - 2026-10-11

- Audit-hardening pass across the supervisor, godelctl, and the
  installer. Supervisor: event-setup failures are logged before exit,
  the dying slot's cgroup flag is computed once, the status buffer has
  headroom against the worst-case line, and `godelctl start` resets the
  restart counter so a gave-up service gets a genuine fresh start.
- godelctl: the status snapshot buffer is 32 KiB (status of very large
  service sets no longer truncates the tail), and `godelctl catlog`
  falls back to `/run/godel/logs/` when `/var/log/godel/` has no file.
- Installer: `dief` takes the message only, the unused `fmsg` helper is
  gone, staged writes go through a short-write-safe `write_all`, and
  probe/report string leaks (runlevel listings, mdev probes, installed
  binary paths) are freed.
- Both fixture matrices and the 77 unit tests pass unchanged.

## 0.9.5.3 - 2026-10-05

- The installer is one binary now. The bootloader phase (detect,
  backup, entry, finish, verify for GRUB, Limine, extlinux,
  systemd-boot, and rEFInd) moved from five POSIX-shell plugins and a
  shell driver into `bin/godel-install` itself; `tools/install.sh` and
  `tools/bootloaders/` are gone, about 450 lines of shell with them.
  `make install-godel BOOTLOADER=...` calls the binary directly; the
  fixture matrices (`test-install.sh`, `test-compat-install.sh`) pass
  unchanged in what they assert.
- Backup stamps gained a nanosecond suffix so back-to-back runs can no
  longer overwrite each other's backups.
- README and docs sobered: no hardware-performance speculation, plain
  statements of what runs where (Artix as the running system init under
  GRUB and Limine) and what is only fixture-covered.

## 0.9.5.2 - 2026-10-05

- The desktop profile starts elogind in the foreground under direct
  supervision (`restart = always`, `restart_delay = 1s`,
  `shutdown_timeout = 2s`, `log = no`) instead of `--daemon` with
  `type = oneshot`. The daemonizing parent exited cleanly within
  milliseconds, so the supervisor logged a clean exit while the real
  daemon ran unsupervised and would never be restarted after a crash.
  The same shape is applied to the metal service pack.
- README accuracy pass: the full `godelctl` verb list (`status --json`,
  `list`, `uptime` were missing), the current QEMU session count, and
  the installer split into the Hare core plus the thin shell driver.

## 0.9.5.1 - 2026-10-02

- Removed the fixed 64-service ceiling. Snapshot storage is reserved
  once per generation, sized to the actual service count before parsing
  begins; the runtime tables (per-service state, dying slots, readiness
  pipes, orphan ring, status buffer, start-order scratch) are allocated
  alongside it and are plain fixed pointers afterwards, so the PID 1
  event loop still never allocates. The `epoll` tag layout moved the
  special and per-class tags to high bit positions (1<<40 and above) so
  the index space is never capped by the tag packing. Per-service
  limits are unchanged (8 argv, 4 env, 4 after, 31-byte names).
- Unit tests cover 64, 128, and 256 services (permutation check on the
  start order at 128/256); a QEMU session boots 259 configured services
  and verifies all of them reach `up` before a clean poweroff.
- `godelctl boot-report` (Hare) replaces the awk implementation; output
  is byte-identical on the full QEMU log corpus, the shell/awk version
  is retired, and the fixture harness now drives the subcommand.
- Installer core moved to Hare (`cmd/godel-install`, `bin/godel-install`):
  distro detection, OpenRC capability discovery, kernel/initramfs/root
  detection, fstab parsing, service generation, staging, validation, and
  commit. The five bootloader backends stay POSIX plugins behind the
  bl_* contract, driven by `tools/install.sh` through a state file. Both
  fixture matrices (single-backend and 7-scenario compatibility) pass
  unchanged.
- Fixed a latent reload bug found during the tag-layout rebase: a moved
  service's readiness pipe is re-tagged in epoll, so a late readiness
  newline can no longer flip the wrong service's ready flag.
- Fixed the root cause of slow shutdown: PID 1 runs with supervisor
  signals blocked (signalfd delivery) and children inherited that mask
  across fork+exec, so SIGTERM never reached any service and every
  shutdown rode to the deadline and finished under SIGKILL. Children
  now reset their signal mask before exec. Shutdown is per-service:
  each service's own `shutdown_timeout` is its deadline, SIGKILL lands
  only on services that outlive it, and the power switch follows the
  last exit instead of a global timeout. Measured in QEMU: 5.2 s to
  2.2 s with an interactive getty shell (the only deliberate holdout),
  ~0.4 s with none; 259-service boot shuts down in 2.4 s.
- Console output is now a timeline: `godel: boot complete in N ms` is
  logged when the last dependency chain settles (the existing
  `godel: ready in` line keeps measuring configuration load), shutdown
  logs `stopping N running service(s)`, per-service SIGKILL decisions,
  and a final `godel: down in N ms (remount-ro X ms, sync Y ms)`.
- SIGKILL fallback after the grace interval shrank from 1 s to 250 ms.

## 0.9.5 - 2026-10-02

- Fixed the last dirty-shutdown path: session managers (elogind scopes)
  move user processes out of the supervisor's cgroup tree, so a graceful
  shutdown left live browser/daemon processes holding writable mmaps.
  Their remount-ro failed with EBUSY, ext4 `needs_recovery` survived,
  and every boot paid ~2.5 s of journal replay. PID 1 now runs a final
  stray-process sweep (SIGKILL to every userland process except PID 1;
  kernel threads and zombies are skipped by their empty cmdline) before
  disks go read-only. Covered by the new `stray-sweep` QEMU session.
- Shutdown forensics: the supervisor-log tail is persisted to
  `/var/log/godel/shutdown.log` before root goes read-only, every
  remount-ro outcome is logged per mount (errno on failure),
  `/proc/mounts` truncation is reported, and root is remounted last so
  the evidence append lands on a writable filesystem.
- Boot profiling on real hardware (`tools/boot-report.sh` over the
  0.9.4 `[T+Nms]` stamps) identified mount-home (~2.5 s journal replay
  on /home) and udev-trigger settle (~1.7 s) as the remaining getty
  gates; the stray sweep above removes the root cause instead of
  shortening the gate.

## 0.9.4 - 2026-09-27

- Alpine moves from capability preview to a tested profile for the
  musl/busybox userland. When `udevd` is absent but busybox `mdev` is
  present, the installer generates an `mdev` oneshot (initial `mdev -s`
  scan plus hotplug-helper registration when
  `/proc/sys/kernel/hotplug` exists) and gates getty on it. The
  kernel-dependent hotplug capability is reported explicitly instead of
  failing silently. Getty now waits for the device-manager oneshot on
  every profile (udev-trigger or mdev).
- OpenRC runlevel discovery: on systems with `/etc/runlevels`, the
  installer reads boot/sysinit/default entries purely as a capability
  source (never executed), lists them, and names every service it will
  not transfer so capability loss is explicit.
- Alpine initramfs naming (`/boot/initramfs-lts`, no `.img` suffix) is
  recognised; mkinitfs and dracut presence are reported as initramfs
  generators.
- Alpine fixture tests (extlinux and GRUB backends over an
  `ID=alpine` tree with mdev and runlevels) joined the compatibility
  matrix, and `tools/build-alpine.sh` assembles a disposable musl +
  busybox Alpine rootfs for the new `alpine-mdev` QEMU session: real
  musl binaries boot godel as init, mdev scans, gettys answer, and the
  shutdown path completes cleanly (`make qemu-alpine`).
- Measured boot and shutdown profiling: every supervisor log line now
  carries a `[T+Nms]` monotonic stamp (PID 1 only), shutdown logs the
  deadline, the SIGKILL phase with a hung-service count, and
  remount-ro/sync durations. `tools/boot-report.sh` turns a supervisor
  log into a boot/shutdown timeline report (multiple boots supported);
  QEMU transcripts are checked against it in `tools/test-system.sh`.
- Fixed the systemd-boot backend killing the installer under `set -e`
  on a first install (no previous entry file to back up), and the
  compatibility matrix now actually runs all backend tests (limine
  current/legacy, extlinux, systemd-boot, rEFInd, alpine extlinux/grub).

## 0.9.3 - 2026-09-20

- Expanded the compatibility installer from GRUB-only Artix/Arch to a
  capability-detected desktop-base profile for Artix/Arch, Void, Alpine,
  Debian/Ubuntu, Fedora, openSUSE, and Gentoo. The profile searches
  distro-native paths for udev, elogind, D-Bus, sysctl, getty, and
  networking; NetworkManager falls back to dhcpcd. It recognises common
  initramfs names from Arch/Fedora/Void and Debian.
- Added bootloader backends for Limine (current `limine.conf` and legacy
  `limine.cfg` syntax, auto-detected), extlinux/syslinux, systemd-boot,
  and rEFInd. Every backend adds only a separate `godel (test)` entry,
  preserves the existing default selection, creates a backup, and
  verifies its result. `make install-godel BOOTLOADER=<name>` is the
  generic entry point.
- Added a five-backend Void fixture matrix to CI. It validates generated
  services, legacy/current Limine syntax, idempotent entries, and that
  Limine timeout/default, extlinux DEFAULT, systemd-boot loader.conf,
  and rEFInd default_selection stay unchanged.

## 0.9.2 - 2026-09-20

- Added a one-command installer for Artix/Arch-family machines:
  `doas make install-artix-grub` (or `sh tools/install.sh --bootloader
  grub`). It detects the running kernel/initramfs/root argument, checks
  cgroup v2 and GRUB prerequisites, generates a desktop-base service
  set (fsck, rootfs remount, fstab mounts and swap, loopback, udev,
  sysctl, D-Bus, elogind, NetworkManager, gettys, log sync) from what
  is actually installed, validates it with `godel -t` before touching
  the system, backs everything up under `/etc/godel/backups`, and adds
  a separate `godel (test)` GRUB entry. The default entry and
  `GRUB_DEFAULT` are never modified; unsupported bootloaders are
  refused, not guessed.
- Bootloader backends are pluggable (`tools/bootloaders/grub.sh`
  defines the contract); Limine, extlinux, and systemd-boot are planned
  backends. A `--dry-run` prints and validates the whole plan without
  changing anything; `ROOT=` fixture mode makes the installer fully
  CI-testable (`tools/test-install.sh`, now part of both CIs).
- Documented the install path in `docs/install.md`.

## 0.9.1 - 2026-09-15

- Fixed a boot race: a plain oneshot dependency (no `notification-fd`)
  now holds its dependents until it has run to completion, cleanly or
  not, instead of merely until it has started. On a fast real-machine boot the
  autologin getty could run while `mount-home` was still mounting
  `/home`: login fell back to `home = /`, fish could not read its config
  directory, and the session autostart block never ran, so the user had
  to start the compositor by hand. A failed oneshot still releases the
  gate so a broken mount or fsck cannot wedge boot forever. New
  `oneshot-gate` scripted session covers the race end to end.
- Added `godel --version` and `godelctl --version`.
- Added `godelctl status --json`: the status snapshot as one line of
  JSON (`name`, `state`, `pid`, `restarts`, `ready`) for scripts.
- Added `godelctl uptime`: supervisor uptime, service totals, summed
  restarts, and readiness timeouts in one line.
- Added man pages `godel(8)` and `godelctl(8)`; `make install` now
  installs them under `$(PREFIX)/share/man/man8`.
- Added a GitHub Actions workflow mirroring the Codeberg Woodpecker CI
  (unit tests, build, example-set validation in both).
- `examples/desktop/swap.conf` keeps swapon's stderr so the per-service
  log tells a missing swapfile from wrong permissions or holes when
  SwapTotal reads 0.

## 0.9.0 - 2026-09-12

- Lifted the fixed configuration limits: the snapshot now holds 64
  services in a 32 KiB buffer. Configuration merges two sources: the
  single-file `/etc/godel/services.conf` (still fully supported) and a
  scanned `/etc/godel/services.d/` directory read in name order, where
  `sshd.conf` defines `[service "sshd"]` and a file must contain
  exactly that one service. A duplicate service name across sources is
  a diagnostic that refuses the whole configuration; diagnostics carry
  the file name and line. Parsing stays allocation-free.
- Added `godel -t PATH`: parse-only validation of a config file, a
  config root, or a `services.d` directory, with `path:line: message`
  diagnostics and a nonzero exit, so a configuration can be checked
  without booting (the migration runbook's Stage 2 tool).
- Added `readiness_timeout` (duration): a notified service that has not
  signalled when the deadline passes is logged, stopped, marked
  `ready=timeout` in the status snapshot, and its dependents are
  released. Without the key an unready notified service still holds its
  dependents indefinitely.
- Added `run-as = user[:group]`: the child drops to one uid/gid after
  the cgroup attach and before `execve` (`setresgid` then `setresuid`,
  names resolved from `/etc/passwd` and `/etc/group`, numeric ids
  accepted, no supplementary groups). An unresolvable user or group
  exits 126 before exec with the reason in the service log. Changing
  `run-as` now replaces the service on reload, like an argv change.
- Logging: per-service log files are created with mode 0600; `log = no`
  opts a service out of per-service logging and keeps the console; the
  supervisor writes a wall-clock header line at every log (re)open.
  The timestamp question was decided honestly: per-line prefixes are
  impossible because the child writes the descriptor directly, so lines
  between headers stay raw and untimestamped, and the header carries
  the wall-clock time.
- Non-root disk checks: the test image's `mount-home`/`mount-var`
  oneshots now run `fsck.ext4 -p` on the extra disks before mounting
  them, guarded by `mountpoint` so a mounted disk is never checked, and
  leave a marker when the check ran; proven by a captured session with
  forced-dirty extra disks.
- The loader skips no validation steps when a source is missing: the
  0.9.0 sessions caught an early return that skipped `after` resolution
  whenever `services.d` did not exist, silently breaking readiness
  gating at boot; fixed and covered by a session.
- Reload matching now compares `run-as` alongside name, argv, and
  `notification-fd`.
- Twelve more unit tests (69 total) and three new system sessions
  (`readytimeout`, `runas`, `direconfig`) on both test kernels; both
  50-cycle boot/reboot soaks rerun with transcripts kept under
  `.image/soak`.
- Memory accounting: PID 1 enables `+memory` and `+pids` at the cgroup
  v2 hierarchy root and then at the supervisor group, logging
  `memory accounting enabled`; every service runs in its own group.
- Control channel: PID 1 owns a root-only `/run/godel/ctl` FIFO and
  `godelctl` gained `start <service>`, `stop <service>` (a manual stop
  is never retried by the restart policy until an explicit start),
  `catlog <service>`, and `list`. A missed death status now detaches
  the pidfd instead of leaving a level-triggered event in epoll — the
  old paths could spin PID 1 and flood the log forever when a death
  raced the SIGCHLD reaper (seen on real hardware); `flood.session`
  and `control.session` cover both.
- Real-hardware migration (Stage 3, Artix/GRUB) found three bugs, all
  fixed and regression-covered: a closed readiness pipe was re-logged
  forever and flooded the log (the fd is now closed on EOF,
  `eofonce.session` proves exactly one line); `/dev/pts` and `/dev/shm`
  were never mounted, breaking every PTY terminal (the boot mounts both,
  `basic.session` asserts them); and the subtree_control write went only
  to the supervisor group, so controllers were never available anywhere
  (the hierarchy root is enabled first, with session assertions for the
  root, the supervisor group, and a live per-service `memory.current`).

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
  godel runs as PID 1 from an ext4 virtio disk with busybox, serial
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
