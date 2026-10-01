# Next Session: Godel 0.9.5.1 — sweep verification on metal, Hare ports

## Language rule

All replies to the user must be in Russian. Code, commit messages, and
documentation stay in English.

## Current state (2026-10-02, end of session)

- **0.9.5 committed on main** (not tagged yet — owner asked to commit
  now, tag tomorrow): the dirty-shutdown root cause is fixed (final
  stray sweep before remount-ro), shutdown forensics added
  (`shutdown.log`, per-mount remount-ro outcomes with errno). Full
  matrix green: 71 unit tests, fixture matrices (8 backends incl.
  Alpine extlinux/GRUB), 18+1 QEMU sessions incl. the new
  `stray-sweep`, sh -n, git diff --check.
- **Machine still runs 0.9.4 binaries.** Upgrade tomorrow via
  `~/godel-host/apply.sh`, then verify the sweep on metal: after an
  evening poweroff, `/var/log/godel/mount-home.log` must show a clean
  /home (no "recovering journal"), `shutdown.log` must exist with
  remount-ro results, and `boot-report.sh` should show mount-home
  dropping from ~2500 ms toward ~100 ms. That closes the boot-speed
  item measured on 2026-09-27.
- **stray-sweep session limitation (known, documented)**: it proves
  the sweep runs and the shutdown completes, but the simulated stray
  sometimes dies on its own before the sweep (busybox `ps`/`cat
  /proc/*` output proved flaky in the harness; cgroupfs seq_files
  hang when read while a member lives). The metal check is the real
  proof. Improving the simulation is optional later work.
- Root-cause chain established this session, worth keeping in mind:
  elogind scopes -> live userland with writable mmaps on /home ->
  remount-ro EBUSY -> needs_recovery -> ~2.5 s journal replay every
  boot. Root was always clean because nothing mmaps files there.

## Open items (in priority order)

1. **Tag + push 0.9.5** after owner review: `git tag v0.9.5`, push
   main + tag to Codeberg (origin) and GitHub; divergence check first.
2. **apply.sh upgrade to 0.9.5 + metal verification of the sweep**
   (details above) — the headline of this release.
3. **Boot optimization, remaining gates**: with the dirty-journal cost
   gone, re-measure with boot-report.sh; then evaluate udevadm settle
   (~1.7 s) against a bounded readiness strategy. Getty gate,
   autologin ordering, and shutdown safety stay untouched; every
   change ships with a test.
4. **boot-report as Hare** (`godelctl boot-report` subcommand); the
   shell version retires after the harness switches. The awk version
   is verified byte-identical under busybox awk.
5. **Installer logic -> Hare** (`cmd/godel-install`): detect,
   capability discovery, service generation, staging move to Hare;
   the five bootloader backends stay POSIX plugins behind the bl_*
   contract; the fixture matrix is the safety net.
6. **Code trim on the PID 1 core**: dead code audit, no-alloc
   invariants re-checked, test count must not drop below 71.
7. **Soak**: autologin on lts (one controlled boot, then strip
   `~/.cache/godel-login.log`), suspend/resume + power button,
   Void + Limine friend dry-run (`--bootloader limine --dry-run`).
8. **vpn-cli**: the user's own console client for happd.
9. **After 0.9.5.x**: feature freeze.

## Roadmap to 1.0.0

Stage 4 soak (weeks of daily driving), every deviation recorded.
Blockers are data-loss or boot-lock bugs only. The owner has selected
Godel as the hidden GRUB default; dinit entries remain as recovery.
Then: AUR `godel-bin` (man pages already ship), more distro example
sets, installer backends. 1.0.0 = quiet weeks + no open blockers +
docs current.

## Session protocol on the user's machine

- Persistent evidence in `/var/log/godel/` (mode 0600). From 0.9.4
  every supervisor line carries `[T+Nms]`; from 0.9.5 shutdown also
  writes `/var/log/godel/shutdown.log` with per-mount remount results.
- `godelctl` refuses to signal PID 1 without `/run/godel/status`. Never
  run `godelctl reload` under dinit.
- Host safety: dinit entries, default boot entry, and the working
  bootloader config are untouchable; machine changes go through
  `~/godel-host/apply.sh`; QEMU uses disposable images.
- Power management under Godel: only `doas godelctl reboot/poweroff`.
  Never `reboot -f`.
- Commits go to both remotes (origin = Codeberg, github mirror);
  force-with-lease only after checking what diverged.
