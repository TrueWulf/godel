# Godel 0.9.0 Benchmarks

Godel is intentionally small rather than benchmark-driven. These
measurements were taken on the development machine (Artix Linux,
x86_64) during the 0.9.0 session, from the QEMU test image described in
`docs/first-boot.md`: Godel boots from an ext4 virtio disk as PID 1
with nine services, including agetty on two consoles, readiness-gated
mount oneshots, fsck hooks, and per-service logging with wall-clock
headers.

| Metric | Result |
|---|---:|
| Ready time, `vmlinuz-linux-lts` (6.18.48) | median 70 ms, min 51, max 114 (50 boots) |
| Ready time, `vmlinuz-linux-zen` (7.2.2) | median 84 ms, min 71, max 130 (50 boots) |
| `godel` binary, stripped | 360656 bytes (352.2 KiB), static, no libc |
| `godelctl` binary, stripped | 246448 bytes (240.7 KiB), static |
| Unit tests | 69 |
| PID 1 source, `cmd/godel` + `godel/` | ~2800 lines of Hare |
| `godelctl` source | 56 lines of Hare |
| Test harness + tooling, host side | ~1000 lines of Hare and shell |

"Ready" is Godel's own `Godel: ready in N ms` log line: all config
sources parsed, eligible services forked, event loop entered. The 100
boot samples come from the 50-cycle soak transcripts on each kernel,
rerun this session against the 0.9.0 loader (single-file config plus
`services.d` scan); the transcripts are kept under `.image/soak` on the
build machine. PID 1 memory is not re-measured this session; the 0.7.0
measurement (368 KiB RSS, 580 KiB VmPeak) predates the readiness,
logging, and directory-config additions.

The soaks exercised, per kernel, 50 consecutive serial logins and
`godelctl reboot` cycles on a persistent ext4 root disk (50 unclean
shutdowns with sync, journal replayed by the kernel on each mount),
ending in a clean `godelctl poweroff`. Zero readiness stalls and zero
lost exits were recorded.

Failure-path sessions run on every `tools/test-system.sh` pass on both
kernels — fourteen in total: SIGKILL recovery with a visible restart
counter, poweroff during restart backoff, SIGKILL escalation against a
service that traps SIGTERM, recovery from a corrupted configuration
through the rescue shell, reload of added, changed, and removed
oneshots, readiness gating with a late newline, a readiness timeout
that releases stuck dependents, per-service log placement, rotation,
and headers, `run-as` with an unprivileged service writing its log and
a bad user failing loudly before exec, booting from `services.d` alone
(including the duplicate-name refusal), the fsck hook on a
forced-dirty ext4 root and on non-root disks, and orphan/zombie-free
teardown. The 0.9.0 sessions caught two real bugs before release: the
directory loader skipped `after` resolution when `services.d` was
absent (breaking readiness gating at boot), and a released readiness
gate did not clear the `started` precondition, so dependents of a
timed-out service stayed blocked. Both are covered by sessions and
unit tests now. Numbers are recorded from the release machine rather
than claimed as portable performance guarantees.
