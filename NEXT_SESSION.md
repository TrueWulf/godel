# Next Session: Godel 0.9.x — real-machine migration (Stage 3/4)

## Language rule

All replies to the user must be in Russian. Code, commit messages, and
documentation stay in English.

## Current state (read before doing anything)

- 0.9.0 is **implemented and QEMU-verified but NOT committed**. The
  whole 0.9.0 diff (library, PID 1, tools, sessions, docs, version
  bump) plus the migration kit sits uncommitted in the working tree.
  The user has not approved commits yet; do not commit, push, or tag
  without explicit approval of each batch.
- QEMU evidence: 69 unit tests; 15 system sessions green on
  `vmlinuz-linux-lts` (6.18.48) and `vmlinuz-linux-zen` (7.2.2); both
  50-cycle boot/reboot soaks rerun with transcripts under `.image/soak`.
- The real-machine migration (docs/migration.md, Stage 3) has started
  on the user's host: Artix Linux, **GRUB** (not Limine — the user
  misremembered; `/efi/EFI/Artix/grubx64.efi`), dinit as the default
  init. Root nvme0n1p2 (ext4, UUID 6463a70a-…), /home nvme0n1p3,
  swapfile, nvidia proprietary (610.57.04), niri + foot + fuzzel
  desktop, autologin truewulf on tty1 via `/usr/lib/dinit/agetty-default`
  reading `/etc/dinit.d/config/agetty-tty1.conf`; session chain is
  `exec dbus-run-session -- niri-session` from `~/.bash_profile`.
- Real boots so far: 3 pre-v3 (all lts), then the **v3 boot (lts)** —
  the session this file was updated during. v3 reached the desktop:
  nvidia loads via udev coldplug, NetworkManager brings the link up
  (1 Gbps), two `foot` processes running (PTY fix proven on real
  hardware), elogind seat on seat0, boot clean ("ready in 11 ms",
  dbus ready after 91 ms). `supervisor.log.1` in `/var/log/godel/` is
  the rotated EOF-spam fossil from boot 1 (1170 duplicate "closed its
  readiness pipe" lines) — kept as evidence.

## Bugs found on real hardware (both fixed and regression-proven)

1. EOF on a readiness pipe was re-logged forever: `on_notify` logged
   the "closed its readiness pipe without a newline" case but never
   closed the fd, so epoll kept reporting it; the log flooded, rotated,
   and burned the boot history. Fix: the notify fd is closed on EOF.
   `tools/sessions/eofonce.session` proves exactly one log line.
2. Godel never mounted `/dev/pts` (or `/dev/shm`). Every PTY-based
   terminal failed instantly (`foot: failed to open PTY`) while
   real-VT gettys worked — which is why the QEMU suites never caught
   it (the test image has no PTY terminals). Fix: the boot mounts
   `devpts` (`gid=5,mode=620,ptmxmode=0666`) and `/dev/shm`
   (mode 1777); `basic.session` asserts `mount | grep devpts`,
   `ls /dev/pts` shows `ptmx`, and `/dev/shm` is mounted.
3. Memory accounting (the v3 feature) was **silently dead**: `setup()`
   wrote `+memory +pids` only to `/sys/fs/cgroup/godel/
   cgroup.subtree_control`, but a cgroup only has controllers
   available once they are enabled in its *parent's* subtree_control —
   which was never written. The write failed, `write_root_file`
   swallowed the failure (returns bool nobody checked), root's
   subtree_control stayed empty, and no per-service `memory.current`
   ever existed. Found by live inspection on the v3 boot (empty
   subtree_control at both levels), not by a crash or a log error;
   QEMU never caught it because no session asserted memory files.
   Fix: `godel/cgroup.ha` now enables `+memory` then `+pids` at the
   hierarchy root first, then at the `godel` level; `setup()` reports
   an `accounting` flag and PID 1 logs
   `godel: memory accounting enabled` (or `unavailable`). Regression:
   `basic.session` asserts `root-memory-ok`, `supervisor-memory-ok`,
   and a live `beacon-memory-file-ok` (markers built via `$m` so the
   terminal echo can never satisfy the expect); 69 unit tests and
   15/15 system sessions pass on the rebuilt image.
3. Found by reading persisted logs, not by a crash — the logsync
   service (PID 1 log copied to `/var/log/godel/supervisor.log` every
   5 s) is what made both diagnoses possible. Keep it.

## In flight: migration kit v3 (migration/apply.sh)

apply.sh is idempotent and self-healing. One `sudo sh
migration/apply.sh` run: installs `bin/godel` and `bin/godelctl` to
`/usr/local`, rewrites `/etc/godel/services.d/*.conf` (14 services:
fsck-root, hostname, rootfs-rw, mount-home, swap, net-lo, udev,
udev-trigger, sysctl, dbus, elogind, networkmanager, getty-tty1,
getty-tty2, logsync — one service per file, name = file name), moves
stray executable backups out of `/etc/grub.d/` into
`/etc/godel/backups/` (grub-mkconfig was executing them and
duplicating menu entries — the user saw doubled Godel entries),
rewrites the numbered `Artix Godel vN` entries in `40_custom`, keeps
`GRUB_TIMEOUT=5` / `GRUB_TIMEOUT_STYLE=menu` (default stays pinned to
the dinit entry), regenerates grub.cfg, and finishes with
`godel -t /etc/godel/services.d`.

v3 contents: devpts/shm binary, memory accounting (`+memory +pids` in
cgroup `subtree_control`), elogind oneshot, getty-tty2, logsync also
snapshots `dmesg` to `/var/log/godel/dmesg.log`.

The v3 boot exposed bug 3 above; `bin/godel` has been rebuilt with the
fix (image regenerated, full QEMU suite green). apply.sh itself is
unchanged — its next run simply installs the fixed binary.

## happd (VPN daemon) — added 2026-09-12, needs one apply.sh run

The user's VPN is Happ (`happ-desktop-bin` 4.1.3): GUI `/usr/bin/happ`
plus a root daemon `/opt/happ/bin/happd` (foreground, spawns
`/opt/happ/bin/core/xray` and `/opt/happ/bin/tun/sing-box` for TUN).
Under dinit it was started by `/etc/dinit.d/happd`; under Godel nothing
started it — that was the "happd не работает" report. apply.sh now
installs `happd.conf` (service 16): `restart = always` + `restart_delay
= 5s` deliberately matching upstream `Restart=always`/`RestartSec=5s`
(happd exits cleanly on a newer-client connection for self-upgrade, so
`on-failure` would leave it dead), `after = networkmanager` (NM has a
notification-fd, so startup waits for real network readiness). The
full 16-service set validates with `godel -t`. The daemon also keeps
its own `/var/log/happd.log`; stdout/stderr land in
`/var/log/godel/happd.log`. The user is writing a personal `vpn-cli`
console client for the same daemon — it talks to happd directly, Godel
is irrelevant to it beyond the daemon being up.

## Commit state (0.9.0 pre-release)

The user approved committing 0.9.0 as a pre-release. Committed locally
in five batches (library; PID 1 + godelctl; tools + sessions; docs;
migration kit). NOT pushed, NOT tagged — push to origin (Codeberg) +
github and the `v0.9.0` tag still need explicit approval.

## What the user must do next

1. `sudo sh /home/truewulf/godel-hare/migration/apply.sh`
   (idempotent; installs the memory-accounting fix into
   `/usr/local/sbin/godel` and the new `happd.conf`)
2. Reboot into `Artix Godel v3 (lts)`.
3. Verify accounting end-to-end:
   `grep memory /sys/fs/cgroup/cgroup.subtree_control` and
   `/sys/fs/cgroup/godel/cgroup.subtree_control`;
   `cat /sys/fs/cgroup/godel/dbus/memory.current` non-zero;
   supervisor.log (or `/run/godel/godel.log`) shows
   `godel: memory accounting enabled`.
4. Verify happd: `godelctl status | grep happd` shows
   `up ... restarts=0`, then connect from the Happ GUI; a server switch
   must show happd restart (clean exit + restart=always) and recover.
5. Then `godelctl poweroff` (first real graceful shutdown test) and a
   reboot cycle; `opencode --continue` inside that session for live
   verification.

## Session protocol on the user's machine

- Persistent evidence lives in `/var/log/godel/`: `supervisor.log(.1)`,
  per-service logs (mode 0600, temporarily 644 for debugging),
  `dmesg.log`. `/run/godel/*` is tmpfs and dies with the boot.
- `godelctl` refuses to signal PID 1 without `/run/godel/status`
  (dual-init safety). Never run `godelctl reload` under dinit.
- Host safety rules are unchanged: never touch the dinit entries, the
  default boot entry, or the working bootloader configuration; every
  bootloader change goes through apply.sh with backups in
  `/etc/godel/backups/`; all QEMU testing uses disposable images under
  `.image/` or `/tmp`.

## Next steps for 0.9.x

1. Verify the v3 boot end-to-end. Already proven on the v3 boot:
   foot/PTY, devpts+shm, dbus readiness, elogind seat, NetworkManager.
   Still open: memory accounting numbers after the fix (needs one
   apply.sh run + reboot), `godelctl poweroff` and `reboot`.
2. Desktop completeness iterations: check `wallpaper-select --startup`
   runs (user reported missing wallpaper on an early boot), happd VPN
   oneshot, time sync (Godel has no NTP yet — RTC only), nftables.
3. Stage 4: weeks of daily driving, every deviation recorded.
   Suspend/resume, lid, and the power button have never been tested
   under Godel anywhere.
4. Commit the 0.9.0 work after explicit approval: four proposed
   batches (library; PID 1; tools + sessions; docs + version) plus the
   migration kit; push to origin (Codeberg) and github; tag `v0.9.0`.
5. Keep docs/benchmarks.md and the comparison table current if
   anything material changes.
