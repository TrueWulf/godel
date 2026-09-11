# Next Session: Godel 0.9.0

## Current Baseline

- Current release: `0.8.0`, relicensed to BSD-2-Clause. Godel boots as PID 1 in
  the QEMU test image (`ro` cmdline, opt-in `fsck-root` before the
  remount, notified mount oneshots, gettys after the remount,
  per-service logs, readiness via `notification-fd`).
- 56 unit tests; eleven system sessions under `tools/sessions/` are
  green on both test kernels; 50-cycle boot/reboot soaks passed on
  `vmlinuz-linux-lts` (6.18.48) and `vmlinuz-linux-zen` (7.2.2) with
  transcripts kept under `.image/soak`.
- An honest comparison with nitro, runit, s6, and dinit lives in
  `docs/comparison.md`.
- The 0.8.x line stays open only for real regressions; feature work
  goes straight to 0.9.0.

## Scope For 0.9.0

The goal is to make a real-machine daily-driver experiment possible.

1. Lift the fixed configuration limits: replace the single 16 KiB
   snapshot with directory-per-service configuration (or a much larger
   snapshot) so a desktop boot with udev, network, dbus, syslog, cron,
   and several gettys fits. Keep parsing allocation-free.
2. Readiness timeout: optional `readiness_timeout` so a notified
   service that never signals fails visibly instead of holding its
   dependents forever.
3. `run-as = user[:group]` per service; everything currently runs as
   root.
4. Log improvements: timestamps, documented permissions, and a
   considered rotation story beyond the single `.1` generation.
5. fsck hook for non-root disks.
6. Real-hardware runbook: a separate bootloader entry that never
   touches the host's `/boot/grub/grub.cfg`, with the previous init
   kept as the default until Godel has proven itself.

## What Must Not Happen

- Do not replace the daily system's default init until 0.9.0 has been
  stable on real hardware for a while.
- Do not overwrite `/boot/grub/grub.cfg`; use a separate, manually
  recoverable bootloader entry when real-hardware testing begins.
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
