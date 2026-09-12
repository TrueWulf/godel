# Migrating an existing system to Godel

This runbook describes how to move a real Artix Linux installation from
its current init (dinit, OpenRC, runit, or s6) to Godel without risking
the machine. It assumes Godel 0.9.0 or newer. The rule throughout: the
existing init stays the default until Godel has proven itself, and no
existing bootloader entry is ever modified.

## Why the QEMU record is not enough

The QEMU suites prove the supervisor's logic: ordering, readiness,
restart, cleanup, recovery, poweroff. A real machine adds:

- the firmware/GRUB path (no `-kernel`, no serial console unless
  configured),
- real hardware enumeration and udev/eudev behaviour,
- slow disks, real network interfaces, firmware-dependent devices,
- power events: reboot, suspend, lid, power button,
- real users, permissions, and long-lived sessions,
- and a different failure price: a broken VM boot costs a restart, a
  broken machine boot costs the machine.

Plan for all seven before calling anything production-ready.

## Stage 0: safety net

1. Back up or snapshot the system partition. Have a live USB that can
   boot the machine and chroot in.
2. Read the current bootloader configuration. Create a *new* GRUB entry
   by hand (custom entry in `/etc/grub.d/40_custom` plus
   `grub-mkconfig`, or an explicit menuentry edit) that duplicates the
   working entry with `init=/usr/local/sbin/godel` appended. Never edit
   the working entry, never change the default until Stage 4.
3. Verify the root filesystem is ext4 (the bundled `fsck-root` hook
   checks ext4) and that the kernel has virtio not required (real
   hardware needs no modules built into the kernel that the boot
   depends on; the initramfs question is avoided by `init=` on the
   real root, but the root and `/usr` drivers must be built in or the
   entry needs an initramfs — check `lsinitcpio`/`mkinitcpio` config).

## Stage 1: write the service set

Godel mounts procfs, sysfs, devtmpfs, cgroup v2, and `/run` itself.
Everything else is services in `/etc/godel/services.d/`. The honest
way to build this list is to copy the *checklist*, not the code: read
the service directories of the init already on the machine (for Artix:
`/etc/dinit.d`, `/etc/runit/sv`, `/etc/openrc/runlevels`, or the s6
bundle) and write one Godel stanza per daemon, pointing at the same
binaries. Typical Artix set:

- oneshots: `sysctl`, `hostname`, `swapon`, `seedrng`/`urandom-seed`
  equivalent, `dmesg` console level,
- `udevd` (eudev): `/usr/bin/udevd --daemon` is wrong for a
  supervisor — run `/usr/lib/udev/udevd` in the foreground? eudev's
  udevd daemonizes; use `udevd --daemon` inside a oneshot that then
  runs `udevadm trigger` and `udevadm settle`, supervised only
  indirectly, or patch to foreground mode. This is the first real
  friction point; expect iteration.
- network: `dhcpcd` runs fine foreground (`dhcpcd -B`), or
  `iwd`/`connman` in the foreground per their flags,
- desktop: `dbus-daemon` (`--nofork --nopidfile`), `elogind`,
  `socklog`/`sysklogd` or nothing,
- `sshd`, `cronie` (`-n`), `acpid` (`-f`), `agetty` tty1..tty6,
- optional `fsck-root` oneshot from the test image.

Daemons that insist on backgrounding are handled with their foreground
flags; a daemon that cannot run foreground is started by a oneshot and
is *not* supervised — that is a documented gap, not a hidden one.

Every long-running service gets `restart = on-failure`, a sane
`restart_delay`, and `notification-fd` only where the daemon truly
supports readiness. Do not invent readiness flags; a service that
cannot signal must not declare `notification-fd`.

## Stage 2: rehearse without touching the machine

1. Validate the configuration: `godel -t /etc/godel/services.d` parses
   every file and reports diagnostics without starting anything
   (required 0.9.0 feature).
2. Clone the real root filesystem into a raw image (or boot a throwaway
   copy of the disk in QEMU with `-drive file=real-disk-copy`) and boot
   it with the *same* service set. Fix every failure there. This is the
   rehearsal that catches wrong paths, daemonizing daemons, and missing
   users.
3. Only when the cloned-disk boot reaches login and every service is
   `up` (or deliberately `stopped`) is the machine allowed to boot
   Godel once.

## Stage 3: first real boot

1. Boot the new entry once, interactively, from the GRUB menu. Watch
   the console; with no serial console configured, PID 1 messages go to
   the VGA console.
2. Expected first-boot failures: a daemon that backgrounded anyway, a
   missing foreground flag, a service ordering mistake. Each one is a
   configuration fix, then reboot into the old init and iterate.
3. Leave the old init as the default. Boot Godel deliberately, daily,
   by hand.

## Stage 4: soak and flip

- Weeks of daily use, `godelctl status` reviewed, logs under
  `/var/log/godel/` skimmed after every suspend/resume and power event.
- Record every deviation. A bug that loses data or locks the boot is a
  0.9.x blocker; the default entry does not change until none remain.
- Only after the runbook's quiet weeks: make the Godel entry the
  default, keep the old init entry forever as the recovery path.

## What to honestly expect

- The service set will take several boot iterations; that is normal.
- `udevd` and `elogind` are the likely hard cases.
- Anything that depends on systemd units, D-Bus activation, or socket
  activation does not exist under Godel and needs its daemon started
  directly or is out of scope.
- Until the 16-service limit is lifted in 0.9.0, a desktop set does not
  fit at all; do not attempt the migration before that lands.
