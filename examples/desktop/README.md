Example desktop service set for a non-systemd distribution
(Artix, Void, or similar) booting with Godel as PID 1.

Adapt before installing:

- fsck-root.conf and swap.conf: replace /dev/sda1 and /swapfile
  with your root device and swap location (see lsblk -f). Drop
  fsck-root.conf entirely if your root is not ext4.
- udev.conf: distributions install udevd at /usr/bin/udevd
  (eudev) or /usr/lib/udev/udevd (systemd udev reused standalone).
- getty-tty1.conf: replace the autologin user or drop the
  --autologin flag for a normal login prompt.

Install:

    cp *.conf /etc/godel/services.d/
    godel -t /etc/godel/services.d

Notes:

- dbus signals readiness on fd 3, so anything with
  `after = dbus` starts only after the system bus is live.
- elogind daemonizes itself, so it runs as an unsupervised
  oneshot: the seat is ready once it exits cleanly. This is a
  known trade-off, not a bug.
- Server variants of this set live in ../server.
