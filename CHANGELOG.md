# Changelog

## 0.6.1-beta.1 - Unreleased

- Continue the beta line after the `v0.6.0` feature release.
- Reserve `1.0.0` for a stable release after real-system validation.

## 0.6.0 - 2026-09-10

- Made the restart policy a Hare tagged union, so restart delays only exist on
  restart outcomes.
- Added SIGCHLD fallback reaping when a pidfd cannot be opened or registered.
- Enabled Ctrl-Alt-Del handling for virtual-machine consoles.
- Added the allocation-free `/run/godel/status` service-state snapshot.
- Replaced destructive log truncation with two-generation rotation:
  `godel.log` and `godel.log.1`.
- Moved reload matching into tested library code and added a 27th unit test.
- Tightened event helpers to return `rt::errno` instead of uninformative
  booleans.
- Added `env = NAME=VALUE` and `type = oneshot` for self-hosted boot jobs.
- Added `make install`, a VM-oriented example configuration, and GPL-3.0-or-later licensing.
