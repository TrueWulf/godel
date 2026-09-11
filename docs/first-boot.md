# First boot with the QEMU test image

This guide builds a small bootable disk image and drives Godel as PID 1
under QEMU. Nothing outside the repository's `.image/` directory is
written; the host system, bootloader, and `/boot` are never touched.

## Prerequisites

- Hare 0.26.0.1 or newer (`HARE=/path/to/hare` overrides the default)
- `qemu-system-x86_64`
- `mke2fs` (e2fsprogs), `cpio`, `curl` (first run only, to fetch a static
  busybox), and Python 3 for the scripted console sessions
- A Linux kernel with virtio-blk and ext4 built in, for example
  `/boot/vmlinuz-linux-lts` or `/boot/vmlinuz-linux-zen`

## Build and boot interactively

```sh
make qemu-system          # builds bin/, rootfs, disk image, boots QEMU
```

Exit QEMU with `Ctrl-A x`. The kernel, disk, and kernel command line can
be overridden without a rebuild:

```sh
tools/run-system.sh                            # defaults
KERNEL=/boot/vmlinuz-linux-zen tools/run-system.sh
EXTRAS=1 tools/run-system.sh                   # attach /home and /var disks
APPEND="console=ttyS0,115200 root=/dev/vda rw init=/sbin/godel" tools/run-system.sh
```

## Log in

The serial console shows the Godel boot log and then a getty prompt:

```
Godel 0.7.0-beta.1: starting
godel: cgroup v2 enabled
...
Godel test image godel-vm on /dev/ttyS0

godel-vm login:
```

Log in as `root` with password `godel`. Both are test-image credentials
defined by `tools/build-rootfs.sh`; they are not defaults of Godel
itself.

## Drive the system

```sh
godelctl status          # one line per service: name, state, pid, restarts
godelctl reload          # re-read /etc/godel/services.conf, SIGHUP to PID 1
godelctl reboot
godelctl poweroff
```

The service configuration lives in `/etc/godel/services.conf`. Edit it
with `vi` (the image ships busybox applets only) and run `godelctl
reload`. An invalid file is refused atomically: the running services are
untouched and the refusal is logged with a line number.

Kill a supervised service and watch the restart policy:

```sh
kill -9 $(awk '$1=="beacon"{print $3}' /run/godel/status | cut -d= -f2)
```

The console logs the signal, the scheduled restart delay, and the fresh
start; `godelctl status` shows the incremented restart counter.

The image deliberately does not install busybox `reboot`, `poweroff`, or
`halt` applets: their signal conventions differ from Godel's. Use
`godelctl`. If every service is gone and the configuration is broken,
Godel starts a recovery shell on the console; repair
`/etc/godel/services.conf` there and type `exit` to resume booting.

## Scripted sessions and soak runs

`tools/qemu-session.py` replays expect/send scripts over the serial
console and records full transcripts:

```sh
tools/test-system.sh             # every tools/sessions/*.session scenario
tools/soak.sh 50                 # 50 boot/reboot cycles, default kernel
tools/soak.sh 50 /boot/vmlinuz-linux-zen
```

Transcripts are kept under `.image/logs` and `.image/soak`. A session
exits nonzero as soon as an expectation fails, and its transcript is the
evidence of what happened.
