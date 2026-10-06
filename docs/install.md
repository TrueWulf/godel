# Installing godel

One command, a detected bootloader, and a separate boot entry. You never
write service sets by hand: the installer detects what is available and
generates them.

## Supported today

godel runs as the system init on the development machine (Artix, GRUB
and Limine). Verified every change:

- The installer compatibility matrix covers Void and Alpine fixtures
  over GRUB, Limine (current and legacy syntax), extlinux, systemd-boot,
  and rEFInd.
- The Alpine `mdev` profile boots a real musl/busybox rootfs (from the
  Alpine repositories) with godel as init: mdev scan, gettys, clean
  shutdown (`make qemu-alpine`).
- Other distros (Debian/Ubuntu, Fedora, openSUSE, Gentoo) are
  capability-detected: run `--dry-run` and inspect every reported
  capability before trusting it.
- Bootloaders: **GRUB**, **Limine** (current `limine.conf` and legacy
  `limine.cfg`), **extlinux/syslinux**, **systemd-boot**, and **rEFInd**.
  All backends add a test entry only: the current default remains untouched.
  Limine note: release 12.x ships no third-party filesystem drivers —
  on UEFI it reads the ESP only (FAT32, NTFS), so the backend requires
  the kernel and initramfs to live on the ESP and references them via
  `boot()`. Paths into an ext4 root (`uuid(...)`, `hdd(...)`) cannot
  resolve and panic with "Failed to open kernel".
- Profile: **desktop base** — fsck/rootfs remount, fstab mounts, fstab
  swap, loopback, device manager (udev + trigger, or busybox `mdev` on
  musl userlands), sysctl, D-Bus, elogind, NetworkManager, two gettys,
  log sync. Missing pieces are reported, not silently dropped. Getty
  is gated on the device-manager oneshot on every profile.

## The one command

```sh
git clone https://codeberg.org/TrueWulf/godel.git
cd godel
make            # builds bin/godel, bin/godelctl (needs the Hare toolchain)
doas make install-godel BOOTLOADER=limine
```

Replace `limine` with `grub`, `extlinux`, `systemd-boot`, or `refind`.
For an Artix/GRUB shortcut, `doas make install-artix-grub` remains available.

What it does, in order:

1. Detects the running kernel, its initramfs, and the `root=` argument
   from `/proc/cmdline` (nothing is guessed from other installs).
2. Checks prerequisites: cgroup v2 unified hierarchy, `/etc/fstab`, the
   selected bootloader configuration, kernel, and a recognised initramfs.
3. Generates `/etc/godel/services.d/*.conf` into a staging directory
   and validates it with `godel -t` before touching anything.
4. Installs `godel`, `godelctl`, and the man pages under
   `/usr/local`.
5. Backs up every file it changes into `/etc/godel/backups/`.
6. Adds a separate **`godel (test)`** entry using the selected bootloader
   backend. The default selection (`GRUB_DEFAULT`, Limine `default_entry`,
   extlinux `DEFAULT`, systemd-boot `loader.conf`, rEFInd
   `default_selection`) is never modified.

Then reboot and pick `godel (test)` in the menu. Log in on tty1 and run
`godelctl list`; every service should show `up` or a completed oneshot
with `restarts=0`.

## Safety model

- The entry is additive and separate. Your current init keeps booting
  until you explicitly choose `godel (test)` in the boot menu.
- Rollback: remove the `# >>> godel begin` … `# <<< godel end` block from
  the selected bootloader config. GRUB additionally needs
  `grub-mkconfig -o /boot/grub/grub.cfg`; Limine, extlinux, and rEFInd read
  their config directly; systemd-boot rollback is removal of
  `loader/entries/godel-test.conf`. Backups are in `/etc/godel/backups/`.
- Re-running the installer is idempotent: the entry is replaced, not
  duplicated; the previous service set is backed up first. It refuses
  to run when `/etc/godel/services.d` is not empty unless you pass
  `--force`.

## Preview without changes

```sh
doas bin/godel-install --bootloader limine --dry-run
```

The dry run detects, generates, validates the profile, and prints every
step it *would* take, changing nothing.

## Compatibility details

- The bootloader phase lives in the same Hare binary: detect, backup,
  entry, finish, and verify run per bootloader, with the same guarantees
  the shell plugins used to provide.
- Limine searches multiple valid config locations and auto-detects current
  colon syntax vs legacy `KERNEL_PATH=` syntax. It leaves `timeout` and
  `default_entry` untouched.
- The generic desktop profile is capability based, not init-system based:
  udev/eudev, D-Bus, elogind, NetworkManager or dhcpcd, and agetty are used
  only when found. On musl userlands (Alpine) busybox `mdev` takes the
  device-manager role: an initial `mdev -s` scan plus hotplug-helper
  registration when the kernel offers `/proc/sys/kernel/hotplug`
  (CONFIG_UEVENT_HELPER). Without it, devtmpfs plus the initial scan
  cover device nodes; the installer reports which variant the running
  kernel provides.
- OpenRC systems (Alpine and similar) get a runlevel discovery report:
  `/etc/runlevels/{sysinit,boot,default}` entries are read purely as a
  capability source, never executed. The installer lists them and names
  every service it will not transfer, so nothing disappears silently.
- NixOS is deliberately refused: its boot and service graph are declarative,
  not `/etc/fstab` plus mutable service configuration.
- Cloning your *entire* current service set: daemonizers and
  init-specific hooks cannot be converted safely by a script; the
  desktop base is the honest automated subset.

## Troubleshooting

### `reboot` / `shutdown` say "connect: No such file or directory"

The util-linux `reboot` and `shutdown` binaries try to talk to systemd
(logind's private socket), which godel does not provide by design. Use
the supervisor's own control path instead:

```sh
doas godelctl reboot
doas godelctl poweroff
```

Do **not** use `reboot -f`: it triggers the reboot syscall directly,
bypassing godel's clean-shutdown path (services stopped, filesystems
remounted read-only, sync). That is how dirty ext4 journals and fsck
prompts come back.

## The fixture tests

CI runs `tools/test-install.sh` for the Artix/GRUB baseline and
`tools/test-compat-install.sh` for the compatibility matrix: Void
fixtures covering current and legacy Limine, extlinux, systemd-boot,
and rEFInd, plus Alpine fixtures (mdev instead of udev,
`initramfs-lts` naming, OpenRC runlevel report) over extlinux and GRUB.
They assert:

- the generated service set passes `godel -t`;
- the entry appears exactly once, even after a re-run;
- every existing bootloader default is byte-identical before and after;
- a re-run leaves exactly one godel entry.

## The Alpine QEMU session

`doas make qemu-alpine` assembles a disposable musl + busybox rootfs
with `tools/build-alpine.sh` (apk.static against the Alpine
repositories; network required) and boots it in QEMU with godel as
init. The session verifies the mdev scan, the kernel-dependent hotplug
helper report, gettys, the `[T+Nms]` supervisor stamps, and a clean
timed poweroff — the Alpine profile exercised against real musl
binaries, not a simulation.
