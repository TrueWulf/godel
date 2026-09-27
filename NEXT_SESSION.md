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

1. **Bug 5: CLOSED (2026-09-27)**. Clean `godelctl poweroff` at 22:29,
   boot at 22:31 on 0.9.4 binaries: fresh `dmesg.log` has no ext4
   recovery and no fsck (the readonly-orphan-cleanup line is the
   normal per-mount check). Data-integrity incident formally closed.
2. **Measured boot optimization (next target)**. First metal metrics
   from `boot-report.sh` (zen, 2026-09-27 22:31): PID 1 exec at
   T+7.7 s (kernel side), Godel config load 26 ms, dbus ready 152 ms,
   mount-home 2570 ms, udev-trigger 1674 ms, getty at T+10462 ms —
   exactly gated by mount-home (7881+2570). Both slow oneshots already
   run in parallel; getty waits on mount-home. Next steps: add step
   timing inside the mount-home command (fsck vs mount split) to
   /var/log/godel/mount-home.log, consider whether the per-boot fsck
   probe can be cheaper, and evaluate a bounded udevadm-settle
   readiness strategy — without weakening the getty gate, the
   autologin ordering, or shutdown safety. Every change needs a test.
3. **Autologin**: confirmed on zen for 0.9.2 and 0.9.4 boots.
   Instrumentation in `~/.cache/godel-login.log` stays until
   confirmed on lts too, then strip.
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

## Plan for 0.9.5 (scope decided 2026-09-27, work next session)

Theme: reduce the shell share and trim code — the last release before
the feature freeze. Ground truth: Hare 3758 lines; shell splits into
~1006 lines of shipped logic (install.sh + bootloader backends +
boot-report.sh) and ~943 lines of host tooling (test/build scripts,
never shipped). Policy statement to add to README: host tooling stays
POSIX shell on purpose; shipped logic migrates to Hare.

1. **`godelctl boot-report`** (Hare port of tools/boot-report.sh,
   ~170 lines): parsing only, unit-tested, `doas godelctl boot-report`
   (the log is root-owned). The shell version is deleted once the
   test harness checks the Hare one; test-system.sh keeps verifying
   QEMU transcripts through the new subcommand.
2. **Installer logic → Hare** (`cmd/godel-install`): distro detect,
   capability detection, service-set generation, staging, validation —
   ~480 lines of install.sh move. The five bootloader backends stay
   POSIX shell plugins behind the existing bl_* contract (per-bootloader
   text munging; adding a bootloader must remain a ~60-line file).
   The 8-fixture compatibility matrix is the migration safety net;
   `sh tools/install.sh` remains the entry point, now exec'ing the
   Hare core.
3. **Measured boot optimization** (from the 2026-09-27 metal metrics):
   split timing inside mount-home (fsck vs mount) written to its
   service log; evaluate a bounded udevadm-settle readiness strategy
   against the measured 1674 ms. Constraints unchanged: getty gate,
   autologin ordering, shutdown fsync/remount-ro stay untouched; every
   change ships with a session or unit test; boot-report before/after
   numbers go into the release notes.
4. **Code trim on the PID 1 core**: dead code audit across cmd/godel +
   godel/, fixed buffers and no-alloc-after-boot invariants re-checked,
   test count must not drop below 71. Small doc pass (man pages,
   architecture.md) to match reality.
5. **Soak items riding along**: autologin on lts (one controlled boot,
   then strip ~/.cache/godel-login.log), suspend/resume + power button,
   Void+Limine friend dry-run (`--bootloader limine --dry-run` first).

Non-goals for 0.9.5: new subsystems, new bootloader backends, Alpine on
real hardware (QEMU matrix remains the claim boundary), mini-systemd
drift. After 0.9.5: feature freeze.

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
