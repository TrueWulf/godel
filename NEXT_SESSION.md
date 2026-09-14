# Next Session: Godel 0.9.x — soak toward 1.0.0

## Language rule

All replies to the user must be in Russian. Code, commit messages, and
documentation stay in English.

## Current state (2026-09-13)

- **0.9.0 is released**: pushed to Codeberg (`origin`) and GitHub,
  tagged `v0.9.0` (tag hash `acbc448` after the history rewrite). All
  commits and future commits are authored `TrueWulf
  <truewulf@noreply.codeberg.org>` (repo-level git config set; the old
  `Godel Release <godel@localhost>` identity is gone from history via
  filter-branch).
- The machine-specific migration kit no longer lives in the repo: it
  is `/home/truewulf/godel-host/apply.sh` (idempotent; installs
  binaries to /usr/local, rewrites `/etc/godel/services.d/*.conf`
  (17 services), manages the two GRUB Godel entries with backups in
  `/etc/godel/backups/`). Run it after every `make` that should reach
  the real machine.
- Supervisor on the real machine: 17 services, memory accounting live
  (`memory.current` per service), ctl FIFO live (`godelctl
  start/stop/catlog/list`), happd supervised (`restart = always`,
  `after = networkmanager tun`), tun oneshot provides /dev/net/tun.
- Repo: `examples/` added (desktop 12 services, server 9, minimal VM
  conf; both validate with `godel -t`). README final: relative
  markdown links only, centered via one `<div align="center">` with
  markdown paragraphs, no badge images.
- 69 unit tests, 17/17 scripted QEMU sessions, soaks green earlier.

## Lessons from the Codeberg README work

- Forgejo rewrites relative paths ONLY in markdown links; raw HTML
  `<a href="relative">` 404s. Keep all cross-file links as markdown.
- Codeberg blocks external images (shields.io never loads); the
  license is a plain `License` link instead of a badge.
- Raw HTML was replaced by `<div align="center">` + blank line +
  markdown paragraphs (both centered and properly spaced).
- `godel -t <single file>` merges the host's real `/etc/godel/
  services.d`; validate example DIRECTORIES instead.

## Bugs fixed during the real-machine migration (1-5)

1. Readiness-pipe EOF re-logged forever → fd closed on EOF
   (`eofonce.session`).
2. `/dev/pts` and `/dev/shm` never mounted → boot mounts both
   (`basic.session`).
3. Memory accounting silently dead: `+memory +pids` must be enabled at
   the hierarchy root before the `godel` group → fixed with live
   assertions (`root-memory-ok` etc.).
4. pidfd spin: missed `take_status` left a level-triggered pidfd in
   epoll → infinite busy loop and log flood; all three death paths now
   detach the pidfd and converge via the reaped ring (`flood.session`,
   `control.session`).
5. **Dirty shutdown (data-integrity blocker)**: `finish_shutdown()`
   called `rt::sync()` but never remounted filesystems read-only, so
   ext4 never set its clean flag; the next boot stopped with
   "Superblock needs_recovery flag is clear, but journal has data" and
   the user recovered with `fsck -y`. Fix: `finish_shutdown()` scans
   `/proc/mounts` (8 KiB fixed buffer) and remounts every disk fs
   (ext2/3/4, xfs, btrfs, vfat, exfat, f2fs, ntfs3) read-only before
   the final sync and reboot syscall; escaped mount paths are skipped.
   `basic.session` asserts `remounting filesystems read-only`.

Note: `supervisor.log.1` under /var/log/godel can be a stale fossil —
logsync only overwrites it when the current boot's `godel.log` actually
rotates; clean short boots never rotate, so old spam may persist. Do
not cite log.1 as evidence about the previous boot without checking.

## Open items (in priority order)

1. **Bug 5 closure test**: run
   `sudo sh /home/truewulf/godel-host/apply.sh`, then in the evening
   `doas godelctl poweroff`; the next morning the machine MUST boot
   clean with no fsck. That closes the incident formally.
2. **zen login delay**: on zen the user lands in the session late
   (lts is instant). bash_profile now runs
   `exec dbus-run-session -- niri --session` (backup at
   `~/.bash_profile.bak-godel`); autologin works on lts. Retest on a
   zen boot and read the fresh `/var/log/godel/supervisor.log` (getty
   restarts, niri start timing, dmesg nvidia timing).
3. **swap**: one boot had `SwapTotal: 0`; `/swapfile` exists (4 GiB,
   correct perms). The user should run `doas swapon /swapfile` and
   report; on error read `/var/log/godel/swap.log` via doas (the
   service swallows stderr into its log).
4. **suspend/resume and power button**: never tested anywhere.
   `/sys/power/state` includes `mem`. Protocol: `doas loginctl
   suspend`, wake, then check `godelctl status` (all up, restarts 0),
   network, clock, niri alive. Power button last: short press should
   reach elogind's HandlePowerKey=poweroff; if nothing happens,
   consider an acpid oneshot in the kit. Lid is N/A (desktop, no
   /proc/acpi/button).
5. **Flatpak portals gap** (found 2026-09-13): Steam Flatpak errored
   "requires a working D-Bus session bus and flatpak-portal service".
   Not a PID 1 bug: there is no `systemd --user` layer under Godel by
   design; on non-systemd systems the session starts its own user
   services. pipewire/pipewire-pulse/wireplumber already spawn via
   niri config lines 90-92; `xdg-desktop-portal-gnome` and
   `xdg-desktop-portal` were added to
   `~/.config/niri/config.kdl` spawn-at-startup (backup at
   `config.kdl.bak-godel`; the user's earlier web-style attempt to fix
   the badge via raw img src is unrelated). After the next relogin:
   `pgrep -af xdg-desktop-portal` must show the portal, then retry
   Steam; on failure capture
   `flatpak run --command=bash com.valvesoftware.Steam -c
   'flatpak-spawn -vv true'`.
6. **vpn-cli**: the user's own console client for happd; it talks to
   happd directly and can use `godelctl stop happd` / `start happd`
   around server switches.

## Roadmap to 1.0.0

Stage 4 soak (weeks of daily driving on the real machine), every
deviation recorded. Blockers are data-loss or boot-lock bugs (bug 5
class); the default GRUB entry stays on dinit until none remain.
Near the end of the soak: AUR package (`godel-bin`), more distro
example sets (Alpine: mdev paths, Void). 1.0.0 = quiet weeks + no
open blockers + docs current.

## Session protocol on the user's machine

- Persistent evidence in `/var/log/godel/` (mode 0600; see the fossil
  note above); `/run/godel/*` is tmpfs and dies with the boot.
- `godelctl` refuses to signal PID 1 without `/run/godel/status`
  (dual-init safety). Never run `godelctl reload` under dinit.
- Host safety rules unchanged: never touch the dinit entries, the
  default boot entry, or the working bootloader config; all machine
  changes go through `~/godel-host/apply.sh` with backups; QEMU
  testing uses disposable images under `.image/` or /tmp.
- Commits go to both remotes (origin = Codeberg, github mirror);
  force-with-lease only after checking what diverged.
