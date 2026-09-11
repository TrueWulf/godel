# Next Session: Godel 0.7.x hardening

## Current Baseline

- Current development version: `0.7.0-beta.3` (tagged `v0.7.0-beta.3`;
  `v0.7.0-beta.1` and `.2` were tagged mid-session as fixes landed).
- Host system: Artix Linux with dinit as PID 1. Leave that installation
  intact.
- Godel now boots as PID 1 from a persistent ext4 QEMU disk image
  (`make qemu-system`): busybox rootfs, serial login (`root`/`godel`),
  oneshots for hostname, root remount, `/tmp`, optional `/home`/`/var`,
  agetty on `ttyS0` and `tty1`, `godelctl` for status/reload/reboot/
  poweroff.
- Quoting (double/single, escapes, concatenation) works in `command` and
  `env`; 46 unit tests.
- Sessions under `tools/sessions/` prove SIGKILL recovery, SIGKILL
  escalation against SIGTERM-trapping services, rescue-shell recovery,
  reload of added/changed/removed oneshots, poweroff during backoff, and
  orphan/zombie-free teardown of services with children.
- 50 consecutive boot/reboot soak cycles completed on both
  `vmlinuz-linux-lts` (6.18.48) and `vmlinuz-linux-zen` (7.2.2) with
  transcripts kept under `.image/soak`.

## Candidate Work for 0.7.1 / 0.8

1. Readiness protocol: `after` is start ordering only. Add a minimal
   readiness mechanism, ideally wire-compatible with the
   `notification-fd` convention already used by s6, dinit, and nitro,
   so service packs stay portable.
2. Per-service output: route service stdout/stderr to supervised
   per-service log files (or a dedicated logger service) instead of the
   shared console; write to a mounted /var/log when the optional /var
   disk is present.
3. fsck hook for the root filesystem before the remount-rw oneshot.
4. Native mount unit only if the sh -c oneshots demonstrably lose real
   failure modes; keep explicit commands otherwise.
5. Real-hardware test on a non-critical machine with a separate,
   manually recoverable GRUB entry; never touch the host's
   `/boot/grub/grub.cfg`.
6. QEMU CI once runner capacity allows (`make test-system` under KVM).
7. Comparison note (docs/comparison.md) against nitro (leahneukirchen,
   0.8.1, used by dérive in core/), runit, s6, and dinit with honest
   feature and size tables, before showing Godel anywhere publicly.
8. License review: GPL-3.0-or-later is a hard mismatch for
   public-domain/ISC-leaning distributions like dérive; decide whether
   to keep it or relicense/mitigate before pitching Godel as an
   alternative to their init stack.

## What Must Not Happen

- Do not make Godel the PID 1 of the daily Artix installation yet.
- Do not overwrite `/boot/grub/grub.cfg`; use a separate, manually
  recoverable GRUB entry when real-hardware testing begins.
- Do not claim stable, production-ready, or safer-than-mature-inits
  status.

## Criteria For 1.0.0

- Godel runs daily on at least one non-critical real installation for
  months.
- The boot image supports normal login, mounts, shutdown, recovery, and
  service supervision without manual rescue work.
- Documented upgrade and rollback path exists.
- Known kernel compatibility range is tested.
- No unresolved data-loss, orphan-process, or boot-lockout bug remains.
