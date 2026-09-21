# Next Session: Godel 0.9.3 — compatibility, soak toward 1.0.0

## Language rule

All replies to the user must be in Russian. Code, commit messages, and
documentation stay in English.

## Current state (2026-09-20)

- **0.9.3 is ready**: compatibility-only release, no PID 1 behavior
  changes. Installer backends cover GRUB, Limine current/legacy syntax,
  extlinux/syslinux, systemd-boot, and rEFInd. The profile detects
  Artix/Arch and Void fixtures plus preview-capability paths for Alpine,
  Debian/Ubuntu, Fedora, openSUSE, and Gentoo. Initramfs names include
  Arch/Fedora/Void and Debian forms. `make install-godel BOOTLOADER=...`
  is the generic command; `install-artix-grub` remains an alias.
- **0.9.3 verification**: 71 unit tests, 18 QEMU sessions, the original
  Artix/GRUB fixture, and a compatibility matrix for Void + Limine
  current/legacy, extlinux, systemd-boot, and rEFInd all pass. Every
  fixture preserves the existing boot default and is idempotent.
- The installer is for FRESH machines. This machine keeps its own
  protocol: `~/godel-host/apply.sh` (the installer refuses to run here
  because `/etc/godel/services.d` is non-empty — that guard is by
  design).
- Earlier releases: 0.9.1 (oneshot completion gate = boot-race fix,
  `godelctl status --json`/`uptime`/`--version`, man pages, 18 QEMU
  sessions incl. `oneshot-gate`), 0.9.0.
- Note: a `README.md` Status-line fix (`db6d652`) was pushed via the
  Codeberg web UI on 2026-09-15; the 0.9.2 release commit was rebased
  on top of it, tags force-with-lease'd on both forges (divergence
  checked: that web edit only).

## Open items (in priority order)

1. **GRUB default is now Godel** (owner decision 2026-09-20):
   `GRUB_DEFAULT=gnulinux-godel-zen-…`, `TIMEOUT=0`, `STYLE=hidden`.
   The dinit entries are still in the menu; recovery is hold-ESC
   during early GRUB, or live media. This RAISES the priority of the
   clean-shutdown verification below: the machine now boots Godel
   unattended every time.
2. **Bug 5 closure (now critical)**: evening `doas godelctl poweroff`,
   next boot must be clean with no fsck. Formal close of the
   data-integrity incident on 0.9.2 binaries.
3. **Autologin verification after reboot** (0.9.1 fix, not yet
   verified on metal): expect silent `niri --session` start.
   `~/.cache/godel-login.log` diagnostics still armed in fish config —
   keep until confirmed on zen AND lts, then strip.
4. **Portals** after relogin: single `pgrep -af xdg-desktop-portal`
   set, Steam Flatpak, screencast + file dialogs.
5. **swap**: check `swap.log` and `/proc/meminfo` on next Godel boot.
6. **suspend/resume and power button**: never tested; protocol in
   earlier session notes.
7. **Void + Limine real-machine verification**: the compatibility
   matrix is fixture-only; test the friend's actual config path and
   Limine version with backups before booting.
8. **alpine-godel**: mdev profile, OpenRC runlevel discovery, mkinitfs;
   current installer only does capability preview there, not a claimed
   complete Alpine desktop profile.
9. **After 0.9.5 (user decision)**: feature freeze; only code quality,
   smaller/faster core, nitro-style polish. No new subsystems — keep
   the Unix-init shape (no mini-systemd drift).
10. **vpn-cli**: the user's own console client for happd.

## Roadmap to 1.0.0

Stage 4 soak (weeks of daily driving), every deviation recorded.
Blockers are data-loss or boot-lock bugs only. The owner has selected
Godel as the hidden GRUB default; dinit entries remain as recovery.
Then: AUR `godel-bin` (man pages already ship), more distro example
sets, installer backends. 1.0.0 =
quiet weeks + no open blockers + docs current.

## Session protocol on the user's machine

- Persistent evidence in `/var/log/godel/` (mode 0600; do not cite
  `supervisor.log.1` without checking freshness). `/run/godel/*` dies
  with the boot.
- `godelctl` refuses to signal PID 1 without `/run/godel/status`. Never
  run `godelctl reload` under dinit.
- Host safety: dinit entries, default boot entry, and the working
  bootloader config are untouchable; machine changes go through
  `~/godel-host/apply.sh`; QEMU uses disposable images.
- Commits go to both remotes (origin = Codeberg, github mirror);
  force-with-lease only after checking what diverged (see the 0.9.2
  tag note above).
