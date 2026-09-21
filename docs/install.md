# Installing Godel

One command, a detected bootloader, and a separate boot entry. You never
write service sets by hand: the installer detects what is available and
generates them.

## Supported today

- Distro families: Artix/Arch and Void are covered by CI fixtures. Alpine,
  Debian/Ubuntu, Fedora, openSUSE, and Gentoo are capability-detected preview
  targets: run `--dry-run`, inspect every reported capability, and test the
  generated entry before relying on it. The installer never pretends a
  desktop profile is complete when a binary is absent.
- Bootloaders: **GRUB**, **Limine** (current `limine.conf` and legacy
  `limine.cfg`), **extlinux/syslinux**, **systemd-boot**, and **rEFInd**.
  All backends add a test entry only: the current default remains untouched.
- Profile: **desktop base** — fsck/rootfs remount, fstab mounts, fstab
  swap, loopback, udev + trigger, sysctl, D-Bus, elogind,
  NetworkManager, two gettys, log sync. Missing pieces are reported,
  not silently dropped.

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
6. Adds a separate **`Godel (test)`** entry using the selected bootloader
   backend. The default selection (`GRUB_DEFAULT`, Limine `default_entry`,
   extlinux `DEFAULT`, systemd-boot `loader.conf`, rEFInd
   `default_selection`) is never modified.

Then reboot and pick `Godel (test)` in the menu. Log in on tty1 and run
`godelctl list`; every service should show `up` or a completed oneshot
with `restarts=0`.

## Safety model

- The entry is additive and separate. Your current init keeps booting
  until you explicitly choose `Godel (test)` in the boot menu.
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
doas sh tools/install.sh --bootloader limine --dry-run
```

The dry run detects, generates, validates the profile, and prints every
step it *would* take, changing nothing.

## Compatibility details

- Backends are small POSIX-shell files implementing `bl_detect`,
  `bl_backup`, `bl_add_entry`, `bl_finish`, `bl_verify`. This is the same
  split used by `kernel-install`: entry data is generic; menu syntax belongs
  to the bootloader.
- Limine searches multiple valid config locations and auto-detects current
  colon syntax vs legacy `KERNEL_PATH=` syntax. It leaves `timeout` and
  `default_entry` untouched.
- The generic desktop profile is capability based, not init-system based:
  udev/eudev, D-Bus, elogind, NetworkManager or dhcpcd, and agetty are used
  only when found. Alpine's mdev and OpenRC service discovery still need a
  dedicated profile before a real Alpine desktop is claimed supported.
- NixOS is deliberately refused: its boot and service graph are declarative,
  not `/etc/fstab` plus mutable service configuration.
- Cloning your *entire* current service set: daemonizers and
  init-specific hooks cannot be converted safely by a script; the
  desktop base is the honest automated subset.

## Troubleshooting

### `reboot` / `shutdown` say "connect: No such file or directory"

The util-linux `reboot` and `shutdown` binaries try to talk to systemd
(logind's private socket), which Godel does not provide by design. Use
the supervisor's own control path instead:

```sh
doas godelctl reboot
doas godelctl poweroff
```

Do **not** use `reboot -f`: it triggers the reboot syscall directly,
bypassing Godel's clean-shutdown path (services stopped, filesystems
remounted read-only, sync). That is how dirty ext4 journals and fsck
prompts come back.

## The fixture test

CI runs `tools/test-install.sh` for the Artix/GRUB baseline and
`tools/test-compat-install.sh` for Void fixtures covering current and legacy
Limine, extlinux, systemd-boot, and rEFInd. They assert:

- the generated service set passes `godel -t`;
- the entry appears exactly once, even after a re-run;
- every existing bootloader default is byte-identical before and after;
- a re-run leaves exactly one Godel entry.
