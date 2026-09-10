# Next Session: Godel 0.7.0-beta.1

## Goal

Make Godel usable as PID 1 in a deliberately small, real boot environment.
Do not replace the host's existing init during development. The first target is
a bootable QEMU disk image and an initramfs that provides a login shell,
persistent root filesystem, and recoverable failure paths.

## Current Baseline

- Current development version: `0.6.1-beta.1`.
- Released tag: `v0.6.0`.
- Host system: Artix Linux with dinit as PID 1. Leave that installation intact.
- Godel already has: cgroup v2/process-group supervision, reload, recovery
  shell, status snapshots, `env =`, `type = oneshot`, and QEMU smoke tests.

## 0.7.0-beta.1 Scope

### 1. Build a Real Test Image

1. Add `tools/build-rootfs.sh` that creates a disposable rootfs under
   `.image/root`.
2. Add `tools/build-image.sh` that builds Godel, creates an initramfs or
   ext4 disk image, and never writes to the host's real root filesystem.
3. Include only explicit runtime dependencies: Godel, a shell, `agetty`,
   mount tools, required shared libraries if static binaries are unavailable,
   `/etc/passwd`, `/etc/shadow` only when a real login is needed, and Godel's
   service configuration.
4. Add `make qemu-system` to boot this image with serial console support.

Acceptance: QEMU reaches a Godel-managed login prompt and an operator can log
in, inspect `/run/godel/status`, reload a service, and power off cleanly.

### 2. Real Boot Responsibilities

1. Add documented, tested oneshot services for hostname, root remount, `/tmp`,
   and optional `/home`/`/var` mounts.
2. Decide whether mount configuration stays as explicit oneshot commands or
   gains a native mount unit. Do not add a native unit unless it removes real
   failure modes and remains simpler than explicit commands.
3. Verify `agetty` on `ttyS0` and a physical virtual terminal. Confirm that
   `setsid` plus the service command correctly acquires a controlling terminal.
4. Add a normal command path for administration: `godelctl reload`,
   `godelctl reboot`, `godelctl poweroff`, and `godelctl status`. It may use
   existing PID 1 signals initially, but its interface must be stable.

Acceptance: the test image supports boot, login, status, reload, reboot, and
poweroff without manually typing process IDs.

### 3. Service Semantics Needed for Daily Use

1. Define dependency semantics precisely: `after` is start ordering only, not
   readiness. Document this prominently.
2. Add a minimal readiness model only if required by the test image. Prefer a
   simple `type = oneshot` dependency chain before inventing a large protocol.
3. Add quote-aware command and environment parsing, or explicitly reject quotes
   with a diagnostic. The current whitespace tokenizer is insufficient for
   normal shell-like command lines.
4. Add tests for reload of changed, removed, and added oneshot services.
5. Add tests for failed cgroup setup, pidfd fallback, and shutdown while a
   service is in restart backoff.

### 4. Reliability Gates

1. Test the image with both installed host kernels: `linux-lts` and
   `linux-zen`.
2. Run at least 50 consecutive QEMU boot/reboot cycles and retain logs.
3. Test forced service hangs, SIGKILL, invalid reloads, and full cgroup trees.
4. Add Codeberg CI that runs `make test`; add QEMU CI once runner capacity is
   available.
5. Write `docs/first-boot.md`, `docs/architecture.md`, and a compatibility
   table with minimum kernel requirements.

## What Must Not Happen

- Do not make Godel the PID 1 of the daily Artix installation yet.
- Do not overwrite `/boot/grub/grub.cfg`; use a separate, manually recoverable
  GRUB entry when real-hardware testing begins.
- Do not claim stable, production-ready, or safer-than-mature-inits status.

## Criteria For 1.0.0

- Godel runs daily on at least one non-critical real installation for months.
- The boot image supports normal login, mounts, shutdown, recovery, and
  service supervision without manual rescue work.
- Documented upgrade and rollback path exists.
- Known kernel compatibility range is tested.
- No unresolved data-loss, orphan-process, or boot-lockout bug remains.
