# Next Session: Godel 0.9.4 — measured profiles, Alpine mdev, soak

## Language rule

All replies to the user must be in Russian. Code, commit messages, and
documentation stay in English.

## Current state (2026-09-27)

- **0.9.4 is released**: tag `v0.9.4` on `da7a2d9`, main and tag pushed
  to Codeberg (origin) and GitHub after divergence check. Machine
  upgraded to 0.9.4 binaries and powered off cleanly the same evening.
- **0.9.4 contents**: measured boot/shutdown profiling plus the Alpine
  mdev profile. No PID 1 behavioral ordering changed; the supervisor
  log format gained a `[T+Nms]` monotonic prefix (PID 1 only),
  shutdown now logs deadline, SIGKILL phase with hung count, and
  remount-ro/sync durations. `tools/boot-report.sh` turns
  supervisor logs into timeline reports (busybox-awk verified via the
  Alpine chroot).
- **Alpine grade moved up**: mdev profile (initial scan +
  kernel-dependent hotplug helper, reported explicitly), OpenRC
  runlevel discovery as a capability source (never executed),
  `initramfs-lts` naming, mkinitfs/dracut reporting. Fixture-tested
  (alpine extlinux + GRUB) and QEMU-tested on a real musl + busybox
  rootfs built by `tools/build-alpine.sh` (`make qemu-alpine`, session
  `alpine-mdev`). Support grades are documented in `docs/install.md`:
  fixture-tested / QEMU-tested / real-machine-tested / preview.
- **Verification this session**: 71 unit tests, test-install,
  test-compat-install (7 backends — now all actually invoked; this
  caught a real `set -e` bug in the systemd-boot backend's bl_backup),
  test-boot-report, sh -n across all scripts, 18 busybox QEMU sessions
  + the new alpine-mdev session, `git diff --check`.
- The machine now runs **0.9.4 binaries** (upgraded via
  `~/godel-host/apply.sh` on 2026-09-27).
- dl-cdn (Fastly) occasionally throws transient fetch errors at
  apk.static; build-alpine.sh retries five times.

## Open items (in priority order)

1. **Bug 5 closure (in flight)**: the machine was upgraded to 0.9.4
   binaries via `~/godel-host/apply.sh` (2026-09-27 late evening,
   backups in `/etc/godel/backups`), then powered off with
   `doas godelctl poweroff`. The 0.9.2→0.9.4 shutdown path is
   logging-only (T+ stamps, deadline/SIGKILL/remount-ro/sync lines),
   so the clean-shutdown closure is valid on 0.9.4. Next session:
   verify the boot was clean — no ext4 recovery/fsck in the fresh
   `dmesg.log`, no fsck prompts — then formally close the incident.
2. **First 0.9.4 boot metrics**: run `sh tools/boot-report.sh
   /var/log/godel/supervisor.log` — T+ stamps give kernel-relative
   absolutes for the first time on metal (this morning's 0.9.2 boot:
   ready 7 ms, fsck 45 ms, dbus ready 64 ms, mount-home 1313 ms,
   udev-trigger 1346 ms, getty ~1.35 s; the two slow oneshots gate
   getty and are the first optimization targets, within the safety
   rules: no weakening of the getty gate, no autologin race, no
   dropping fsync/remount-ro).
3. **Autologin**: confirmed working on zen (2026-09-27 boot, niri
   started 1 s after boot without input). The 0.9.4 boot is another
   zen check; instrumentation in `~/.cache/godel-login.log` stays
   until confirmed on lts too, then strip.
4. **suspend/resume and power button**: never tested; protocol in
   earlier session notes.
5. **Boot metrics on 0.9.4**: after the first 0.9.4 boot, run
   `sh tools/boot-report.sh /var/log/godel/supervisor.log` — the T+
   stamps give kernel-relative absolutes (this morning's 0.9.2 boot:
   ready 7 ms, fsck 45 ms, dbus ready 64 ms, mount-home 1313 ms,
   udev-trigger 1346 ms, getty ~1.35 s; the two slow oneshots gate
   getty and are the first optimization targets, within the safety
   rules: no weakening of the getty gate, no autologin race, no
   dropping fsync/remount-ro).
6. **Void + Limine real-machine verification** (friend's machine):
   start only with `doas sh tools/install.sh --bootloader limine
   --dry-run`; verify config path, syntax, kernel/initrd paths,
   preserved `default_entry`/`timeout`. Real layout quirks become
   fixtures + backend fixes, never manual workarounds.
7. **Alpine on real hardware**: only after someone asks; the QEMU
   matrix is the current claim boundary.
8. **boot-report as Hare**: candidate `godelctl boot-report` subcommand
   for 0.9.5 (owner preference: more Hare, less shell where logic
   lives). The awk version ships until then.
9. **After 0.9.5**: feature freeze; only code quality, smaller/faster
   core, nitro-style polish. No new subsystems — keep the Unix-init
   shape (no mini-systemd drift).
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
  with the boot. From 0.9.4 every supervisor line carries `[T+Nms]`.
- `godelctl` refuses to signal PID 1 without `/run/godel/status`. Never
  run `godelctl reload` under dinit.
- Host safety: dinit entries, default boot entry, and the working
  bootloader config are untouchable; machine changes go through
  `~/godel-host/apply.sh`; QEMU uses disposable images
  (`.image/*.ext4`, rebuilt at will).
- Power management under Godel: only `doas godelctl reboot/poweroff`
  (util-linux reboot wants systemd; `reboot -f` skips clean shutdown —
  never suggest it).
- Commits go to both remotes (origin = Codeberg, github mirror);
  force-with-lease only after checking what diverged (see the 0.9.2
  tag note above).
