# Next Session: Godel 0.9.0

## Current Baseline

- Current release: `0.8.0`, licensed BSD-2-Clause. Godel boots as PID 1
  in the QEMU test image (`ro` cmdline, opt-in `fsck-root` before the
  remount, notified mount oneshots, gettys after the remount,
  per-service logs, readiness via `notification-fd`).
- 56 unit tests; eleven system sessions under `tools/sessions/` are
  green on both test kernels; 50-cycle boot/reboot soaks passed on
  `vmlinuz-linux-lts` (6.18.48) and `vmlinuz-linux-zen` (7.2.2) with
  transcripts kept under `.image/soak`.
- An honest comparison with nitro, runit, s6, and dinit lives in
  `docs/comparison.md`; the real-machine runbook is
  `docs/migration.md`.
- The 0.8.x line stays open only for real regressions; feature work
  goes into 0.9.0.

## Scope For 0.9.0

The goal is a real-machine daily-driver experiment as described in
`docs/migration.md`.

1. Lift the fixed configuration limits. Keep the single-file format
   working and add a scanned directory (`/etc/godel/services.d/*.conf`,
   name = basename): snapshot grows to at least 64 services, both
   sources merge, a duplicate service name across sources is a
   diagnostic. Parsing stays allocation-free. Acceptance: the test
   image boots from directory config alone; all sessions and both 50-
   cycle soaks stay green.
2. `godel -t PATH`: parse-only validation of a file or directory with
   line-numbered diagnostics and a nonzero exit on error, so a
   migration rehearsal can check a config without booting.
3. Readiness timeout: optional `readiness_timeout` (duration like the
   others); an unready notified service is logged, marked failed, and
   released from gating when the deadline passes. Acceptance: a new
   session where a silent service times out and its dependents start.
4. `run-as = user[:group]` per service, applied after the cgroup
   attach and before `execve` via `setgid`/`setuid` (single group, no
   supplementary groups; documented). Acceptance: a session where a
   service runs as a non-root user and writes its per-service log.
5. Log improvements: wall-clock timestamps in every per-service log
   line prefix (written by the supervisor side is impossible — the
   child writes directly; so prefix at rotation time only, or accept
   raw service output — decide honestly and document whichever is
   chosen), log file mode 0600, `log = no` per-service opt-out for
   services that must keep the console (gettys on other vtys).
6. fsck hook for non-root disks: either a per-oneshot `check = DEVICE`
   key or a documented sh pattern in the image; tolerate the same
   mounted-refusal case as `fsck-root`.
7. Refresh `docs/benchmarks.md`, README, and the comparison table
   after the changes; rerun full suites and both 50-cycle soaks.

## What Must Not Happen

- Do not replace the daily system's default init until 0.9.0 has been
  stable on real hardware for a while.
- Do not overwrite the working bootloader entry; the migration runbook
  creates a separate one and the old init stays the default.
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
