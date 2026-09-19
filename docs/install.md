# Installing Godel

One command, a supported distro, and a separate boot entry. You never
write service sets by hand: the installer detects what is available and
generates them.

## Supported today

- Distro family: Artix / Arch (`os-release` ID `artix`, `arch`, or
  `ID_LIKE=arch`).
- Bootloader: **GRUB**. Limine, extlinux/syslinux, and systemd-boot are
  planned backends and are refused with a clear message until then.
- Profile: **desktop base** — fsck/rootfs remount, fstab mounts, fstab
  swap, loopback, udev + trigger, sysctl, D-Bus, elogind,
  NetworkManager, two gettys, log sync. Missing pieces are reported,
  not silently dropped.

## The one command

```sh
git clone https://codeberg.org/TrueWulf/godel.git
cd godel
make            # builds bin/godel, bin/godelctl (needs the Hare toolchain)
doas make install-artix-grub
```

What it does, in order:

1. Detects the running kernel, its initramfs, and the `root=` argument
   from `/proc/cmdline` (nothing is guessed from other installs).
2. Checks prerequisites: cgroup v2 unified hierarchy, `/etc/fstab`,
   GRUB with `40_custom`.
3. Generates `/etc/godel/services.d/*.conf` into a staging directory
   and validates it with `godel -t` before touching anything.
4. Installs `godel`, `godelctl`, and the man pages under
   `/usr/local`.
5. Backs up every file it changes into `/etc/godel/backups/`.
6. Appends a **`Godel (test)`** menu entry to `/etc/grub.d/40_custom`
   and regenerates `grub.cfg`. The default entry, `GRUB_DEFAULT`, and
   any other bootloader configuration are never modified.

Then reboot and pick `Godel (test)` in the menu. Log in on tty1 and run
`godelctl list`; every service should show `up` or a completed oneshot
with `restarts=0`.

## Safety model

- The entry is additive and separate. Your current init keeps booting
  until you explicitly choose `Godel (test)` in the GRUB menu.
- Rollback: remove the `# >>> godel begin` … `# <<< godel end` block
  from `/etc/grub.d/40_custom`, run `grub-mkconfig -o
  /boot/grub/grub.cfg`, and reboot. Backups of everything are in
  `/etc/godel/backups/`.
- Re-running the installer is idempotent: the entry is replaced, not
  duplicated; the previous service set is backed up first. It refuses
  to run when `/etc/godel/services.d` is not empty unless you pass
  `--force`.

## Preview without changes

```sh
doas sh tools/install.sh --bootloader grub --dry-run
```

The dry run detects, generates, validates the profile, and prints every
step it *would* take, changing nothing.

## What is intentionally not automatic (yet)

- Other bootloaders (Limine, extlinux, systemd-boot): the backend
  contract lives in `tools/bootloaders/grub.sh`; new backends are small
  scripts implementing `bl_detect`, `bl_backup`, `bl_add_entry`,
  `bl_finish`, `bl_verify`.
- Other distros (Alpine first: mdev, OpenRC discovery, mkinitfs,
  extlinux) — the installer structure is ready for them.
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

CI runs `tools/test-install.sh`, which builds a fake root tree
(fstab, kernels, GRUB config, binaries), runs the installer against it
in dry-run and real modes, and asserts:

- the generated service set passes `godel -t`;
- the entry appears exactly once, even after a re-run;
- `/etc/default/grub` is byte-identical before and after;
- an unsupported bootloader is refused.
