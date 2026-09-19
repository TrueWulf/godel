# Next Session: Godel 0.9.2 — installer, soak toward 1.0.0

## Language rule

All replies to the user must be in Russian. Code, commit messages, and
documentation stay in English.

## Current state (2026-09-20)

- **0.9.2 is released**: on Codeberg and GitHub, tag `v0.9.2` (commit
  `ae14e30`). Highlights: the one-command installer
  (`doas make install-artix-grub`) with a pluggable bootloader-backend
  contract (GRUB implemented; limine/extlinux/systemd-boot planned),
  desktop-base profile generation from what is actually installed,
  dry-run mode, fixture-mode CI test (`tools/test-install.sh` in both
  CIs), `docs/install.md`.
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

1. **Autologin verification after reboot** (0.9.1 fix, still not
   verified on metal): pick `Artix Godel v3 (zen)`, expect silent
   `niri --session` start. `~/.cache/godel-login.log` diagnostics are
   still armed in fish config — keep until confirmed on zen AND lts,
   then strip.
2. **Bug 5 closure**: evening `doas godelctl poweroff`, morning must
   boot clean with no fsck. Formal close of the data-integrity
   incident.
3. **Portals** after relogin: single `pgrep -af xdg-desktop-portal`
   set, Steam Flatpak, screencast + file dialogs.
4. **swap**: swap-fstab-style stderr logging is in 0.9.1+ kit; check
   `swap.log` and `/proc/meminfo` on next Godel boot.
5. **suspend/resume and power button**: never tested; protocol in the
   previous session notes (loginctl suspend, godelctl status, network,
   clock, niri alive; power key last).
6. **Limine backend**: next installer backend, per user request; then
   other bootloaders.
7. **alpine-godel**: mdev profile, OpenRC runlevel discovery, mkinitfs,
   extlinux backend; QEMU first, then the user's distro-hop metal.
8. **After 0.9.5 (user decision)**: feature freeze; only code quality,
   smaller/faster core, nitro-style polish. No new subsystems — keep
   the Unix-init shape (no mini-systemd drift).
9. **vpn-cli**: the user's own console client for happd.

## Roadmap to 1.0.0

Stage 4 soak (weeks of daily driving), every deviation recorded.
Blockers are data-loss or boot-lock bugs only; the default GRUB entry
stays on dinit until none remain. Then: AUR `godel-bin` (man pages
already ship), more distro example sets, installer backends. 1.0.0 =
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
