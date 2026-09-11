# Godel 0.7.0-beta.1 Benchmarks

Godel is intentionally small rather than benchmark-driven. These
measurements were taken on the development machine (Artix Linux,
x86_64) during the 0.7.0-beta.1 session, from the QEMU test image
described in `docs/first-boot.md`: Godel boots from an ext4 virtio disk
as PID 1 with eight services, including agetty on two consoles.

| Metric | Result |
|---|---:|
| Ready time, `vmlinuz-linux-lts` (6.18.48) | median 93 ms, min 79, max 118 (55 boots) |
| Ready time, `vmlinuz-linux-zen` (7.2.2) | median 122 ms, min 104, max 312 (50 boots) |
| PID 1 RSS | 368 KiB (VmPeak 580 KiB) |
| `godel` binary, stripped | 315848 bytes (308.4 KiB), static |
| `godelctl` binary, stripped | 246448 bytes (240.7 KiB), static |
| Incremental build (warm Hare cache) | 30 ms |
| Build from empty Hare cache | 675 ms |
| Unit tests | 46 |

"Ready" is Godel's own `Godel: ready in N ms` log line: config parsed,
all services forked, event loop entered. The 105 boot samples come from
the 50-cycle soak transcripts on each kernel plus single-boot sessions;
the transcripts are kept under `.image/soak` on the build machine.

The soak runs exercised, per kernel, 50 consecutive serial logins and
`godelctl reboot` cycles on a persistent ext4 root disk (50 journal
replays per kernel), ending in a clean `godelctl poweroff`.

Failure-path sessions run on every `tools/test-system.sh` pass: SIGKILL
recovery with a visible restart counter, poweroff during restart
backoff, SIGKILL escalation against a service that traps SIGTERM,
recovery from a corrupted configuration through the rescue shell, and
reload of added, changed, and removed oneshots. Numbers are recorded
from the release machine rather than claimed as portable performance
guarantees.
