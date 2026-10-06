# godel benchmarks

Measured on the development machine (Artix Linux, x86_64), 0.9.5.3.

| Metric | Result |
|---|---:|
| Ready time, real metal boot | 12 ms, 18 services |
| `godel` binary, stripped | 385664 bytes (376.6 KiB), static, no libc |
| Unit tests | 77 |
| QEMU sessions | 20 |
| PID 1 source, `cmd/godel` + `godel/` | ~3400 lines of Hare |
| `godelctl` source | ~700 lines of Hare |
| installer source, `cmd/godel-install` | ~1600 lines of Hare |

"Ready" is godel's own `ready in N ms` log line: all config sources
parsed, eligible services forked, event loop entered. The metal number
is from the daily-driver boot under Limine.

Historical QEMU medians from the 0.9.0 soak (50 boots per kernel):
70 ms on `linux-lts`, 84 ms on `linux-zen`, zero readiness stalls and
zero lost exits across 100 unclean-shutdown cycles. Soak tooling stays
in `tools/soak.sh`; rerun it after any scheduler change rather than
trusting old numbers.
