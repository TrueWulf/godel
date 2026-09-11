# Godel compared with other supervisors

This note exists to keep claims about Godel checkable. Versions compared:
Godel 0.8.0, nitro 0.8.1, runit 2.2.0, s6 2.13.x (with s6-rc 0.5.x),
dinit 0.23.0. Everything below describes the core upstream tools, not
distribution add-ons. Binary sizes are measured here only for Godel;
other projects are not measured, so their row is qualitative.

## Feature table

| | Godel | nitro | runit | s6 (+s6-rc) | dinit |
|---|---|---|---|---|---|
| Language | Hare | C | C | C | C++ |
| License | BSD-2-Clause | 0BSD | BSD-3-Clause | ISC | Apache-2.0 |
| Static no-libc binary | yes | musl builds | musl builds | optional (libc) | no (libc) |
| Config model | one INI-like file, fixed limits | directory of scripts | directory of scripts | directory + compiled s6-rc DB | per-service description files |
| Service limit | 16, fixed storage | unbounded | unbounded | unbounded | unbounded |
| Dependency ordering | `after`, start order | none built in (use `SYS/setup`) | none built in | s6-rc graph, compiled | full graph, parallel, rollback |
| Readiness protocol | `notification-fd` (s6/dinit/nitro compatible) | `notification-fd` | none | `notification-fd` | `ready-notification` (pipe or sd_notify) |
| Readiness gating of `after` | opt-in per dependency | no (readiness affects state only) | n/a | readiness affects state, gates are manual | `waits-for` gates on readiness |
| Per-service logging | file with size rotation | pipe to log service, chainable | pipe to svlogd | pipe to s6-log | `logfile` or consumer service |
| Log processing/filtering | none | via chained log services | svlogd | s6-log | external |
| Restart policies | always/on-failure/never, exponential backoff, give-up | restart with 2s throttle | always | s6-rc policies | restart flag, interval |
| Atomic config reload | yes (inactive-set parse, keep-or-restart matching) | `rescan` | no | `s6-rc update` | `dinitctl reload` |
| cgroup cleanup | cgroup v2 `cgroup.kill` per service | no | no | no | no |
| Per-service user switching | no | via run scripts (chpst) | via run scripts (chpst) | s6-setuidgid | `run-as` |
| User (non-PID 1) mode | no | yes | yes (runsvdir) | yes | yes |
| Control interface | signals + godelctl (status/reload/reboot/poweroff) | Unix socket + nitroctl | sv, signals | full s6-rc/s6-svscan toolkit | dinitctl |
| Timers/cron | no | no (snooze suggested) | no | no | no |
| PID 1 platforms | Linux only | Linux, NetBSD | Linux | Linux, BSDs | Linux, OpenBSD, more |

## Where Godel genuinely differs

- The whole supervisor is one freestanding Hare binary with no heap
  allocation at runtime and a fixed-memory configuration snapshot; the
  PID 1 binary stripped is 329,520 bytes (self-measured, x86-64,
  `hare build` output, `strip`).
- `cgroup.kill` per service gives orphan-grandchild cleanup that none of
  the four others do in their core.
- Readiness uses the `notification-fd` wire convention, so service packs
  written for s6, dinit, or nitro keep working; `after` can gate on
  readiness where the dependency opted in, and stays plain ordering
  otherwise.
- Reload re-parses into an inactive set and either keeps or replaces each
  service by name plus argv, refusing the whole file on any error.

## Where Godel falls short (read this before choosing it)

- Hard limits: 16 services, 8 argv entries, 4 env entries, 4 `after`
  references, 31-byte names. Many real systems exceed this quickly.
- No per-service user, group, chroot, or namespace support. Everything
  runs as root. nitro, runit, s6, and dinit all delegate or implement
  privilege dropping.
- No user-session mode: the binary refuses to run when it is not PID 1.
- Readiness has no timeout. A notified service that never writes its
  newline blocks its dependents forever, with no failure signal.
- Logging is a plain append-rotated file per service. There is no log
  chaining, filtering, or shipping; svlogd, s6-log, and nitro log
  services are all more capable. Logs are root-readable only.
- No timers, no socket or buffer activation, no oneshot up/down split,
  no templated or parameterized services (nitro's `@` templates, dinit's
  triggered services).
- The tool ecosystem is two binaries. s6's toolkit (three dozen
  utilities), runit's svlogd, and dinit's dinitcheck/dinit-monitor have
  no equivalents here.
- Track record: Godel has booted only in QEMU on two kernels. It has
  months-scale real-hardware testing nowhere, no distribution packaging,
  and no upgrade/rollback story. nitro, runit, s6, and dinit have years
  of production use.

## Source size (measured, 2026-09-11)

| | lines |
|---|---:|
| Godel PID 1 (`cmd/godel` + `godel/`, incl. tests) | 2716 |
| Godel `godelctl` | 56 |
| nitro `nitro.c` (master, ~0.8.x) | 2163 |
| nitro `nitroctl.c` | 842 |

The line counts say less than they appear to: nitro ships more features
(user sessions, log chains, parametrized services, Unix-socket control)
in fewer lines, while Godel's count includes its test suite.

## Statement of intent

Godel is an experiment in a small, auditable PID 1 for VMs, embedded
images, and personal machines. It does not replace systemd, and at this
point it does not replace nitro, runit, s6, or dinit either; each of
those is more capable, more portable, and far better tested. The
comparison above exists so that anyone evaluating Godel can see both
sides without marketing.
