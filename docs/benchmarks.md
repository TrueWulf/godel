# Godel 0.6.0 Benchmarks

Godel is intentionally small rather than benchmark-driven. These measurements
describe a static Hare PID 1 on an x86_64 QEMU VM with 256 MiB RAM. The boot
test uses the same initramfs as `tools/run-qemu.sh`.

| Metric | Result |
|---|---:|
| Ready time | 68–86 ms (two QEMU release scenarios) |
| PID 1 RSS | 374 KiB (median of two `/bin/probe` QEMU scenarios) |
| Stripped binary size | 315792 bytes (308.4 KiB) |
| Clean output build | 39 ms (warm Hare cache) |
| Unit tests | 31 |

The release script verifies three operational paths: restart/reload/reboot,
graceful poweroff, and recovery from an invalid configuration. The `probe`
oneshot also proves that `env = GODEL_SMOKE_ENV=present` reaches a service.

Numbers are intentionally recorded from the release machine rather than
claimed as portable performance guarantees. Kernel, QEMU version, linker, and
CPU cache state all affect startup measurements.
