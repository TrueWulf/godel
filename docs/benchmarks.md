# Godel 0.8.0 Benchmarks

Godel is intentionally small rather than benchmark-driven. These
measurements were taken on the development machine (Artix Linux,
x86_64) during the 0.8.0 session, from the QEMU test image described in
`docs/first-boot.md`: Godel boots from an ext4 virtio disk as PID 1
with nine services, including agetty on two consoles, readiness-gated
mount oneshots, and per-service logging.

| Metric | Result |
|---|---:|
| Ready time, `vmlinuz-linux-lts` (6.18.48) | median 68 ms, min 50, max 125 (50 boots) |
| Ready time, `vmlinuz-linux-zen` (7.2.2) | median 95 ms, min 78, max 118 (50 boots) |
| `godel` binary, stripped | 329512 bytes (321.8 KiB), static, no libc |
| `godelctl` binary, stripped | 246448 bytes (240.7 KiB), static |
| Unit tests | 56 |
| PID 1 source, `cmd/godel` + `godel/` | ~2400 lines of Hare |
| `godelctl` source | 56 lines of Hare |
| Test harness + tooling, host side | ~900 lines of Hare and shell |

"Ready" is Godel's own `Godel: ready in N ms` log line: config parsed,
eligible services forked, event loop entered. The 100 boot samples come
from the 50-cycle soak transcripts on each kernel; the transcripts are
kept under `.image/soak` on the build machine. PID 1 memory is not
re-measured this session; the 0.7.0 measurement (368 KiB RSS, 580 KiB
VmPeak) predates the readiness and logging additions.

The soak runs exercised, per kernel, 50 consecutive serial logins and
`godelctl reboot` cycles on a persistent ext4 root disk (50 unclean
shutdowns with sync, journal replayed by the kernel on each mount),
ending in a clean `godelctl poweroff`. Zero readiness stalls and zero
lost exits were recorded after the orphan-ring fix described in the
changelog; the pre-fix stall is preserved in the earlier transcript of
the same directory.

Failure-path sessions run on every `tools/test-system.sh` pass on both
kernels: SIGKILL recovery with a visible restart counter, poweroff
during restart backoff, SIGKILL escalation against a service that traps
SIGTERM, recovery from a corrupted configuration through the rescue
shell, reload of added, changed, and removed oneshots, readiness gating
with a late newline, per-service log placement and rotation, the fsck
hook on a forced-dirty root, and orphan/zombie-free teardown. Numbers
are recorded from the release machine rather than claimed as portable
performance guarantees.
