#!/bin/sh
set -eu

root=/home/truewulf/godel-hare
stamp=$(date +%Y%m%d-%H%M%S)
backup_dir=/etc/godel/backups

test -x "$root/bin/godel" || { echo "missing $root/bin/godel" >&2; exit 1; }
test -x "$root/bin/godelctl" || { echo "missing $root/bin/godelctl" >&2; exit 1; }

mkdir -p "$backup_dir"
for stale in /etc/grub.d/40_custom.bak-* /etc/grub.d/40_custom.orig; do
	[ -e "$stale" ] || continue
	mv "$stale" "$backup_dir/"
done
if [ -e /boot/grub/custom.cfg ]; then
	mv /boot/grub/custom.cfg "$backup_dir/custom.cfg.$stamp"
fi

install -m755 "$root/bin/godel" /usr/local/sbin/godel
install -m755 "$root/bin/godelctl" /usr/local/bin/godelctl

mkdir -p /etc/godel/services.d /var/log/godel
chmod 755 /etc/godel /etc/godel/services.d /var/log/godel

cat > /etc/godel/services.d/fsck-root.conf <<'EOF'
[service "fsck-root"]
command = /bin/sh -c "fsck.ext4 -p /dev/nvme0n1p2 2>/dev/null || echo 'fsck-root: root is mounted or unfixable; kernel journal recovery owns dirty state'"
type = oneshot
restart = never
EOF

cat > /etc/godel/services.d/hostname.conf <<'EOF'
[service "hostname"]
command = /usr/lib/dinit/hostname
type = oneshot
restart = never
after = fsck-root
EOF

cat > /etc/godel/services.d/rootfs-rw.conf <<'EOF'
[service "rootfs-rw"]
command = /bin/mount -o remount,rw /
type = oneshot
restart = never
after = fsck-root
EOF

cat > /etc/godel/services.d/mount-home.conf <<'EOF'
[service "mount-home"]
command = /bin/sh -c "mountpoint -q /home || { fsck.ext4 -p /dev/nvme0n1p3 2>/dev/null; [ $? -le 1 ] && touch /run/godel/fsck-home-ran; }; mountpoint -q /home || mount /dev/nvme0n1p3 /home"
type = oneshot
restart = never
after = rootfs-rw
EOF

cat > /etc/godel/services.d/swap.conf <<'EOF'
[service "swap"]
command = /bin/sh -c "swapon /swapfile 2>/dev/null || echo 'swap: already active or unavailable'"
type = oneshot
restart = never
after = rootfs-rw
EOF

cat > /etc/godel/services.d/net-lo.conf <<'EOF'
[service "net-lo"]
command = /bin/ip link set up dev lo
type = oneshot
restart = never
after = rootfs-rw
EOF

cat > /etc/godel/services.d/udev.conf <<'EOF'
[service "udev"]
command = /usr/bin/udevd
restart = on-failure
restart_delay = 1s
after = rootfs-rw
EOF

cat > /etc/godel/services.d/udev-trigger.conf <<'EOF'
[service "udev-trigger"]
command = /bin/sh -c "udevadm trigger -c add && udevadm settle"
type = oneshot
restart = never
after = udev
EOF

cat > /etc/godel/services.d/sysctl.conf <<'EOF'
[service "sysctl"]
command = /usr/bin/sysctl --system
type = oneshot
restart = never
after = udev-trigger
EOF

cat > /etc/godel/services.d/dbus.conf <<'EOF'
[service "dbus"]
command = /bin/sh -c "mkdir -p /run/dbus && exec /usr/bin/dbus-daemon --system --nofork --nopidfile --print-address=3"
notification-fd = 3
readiness_timeout = 15s
restart = on-failure
restart_delay = 1s
after = rootfs-rw net-lo
EOF

cat > /etc/godel/services.d/elogind.conf <<'EOF'
[service "elogind"]
command = /usr/lib/elogind/elogind --daemon
type = oneshot
restart = never
after = dbus rootfs-rw
EOF

cat > /etc/godel/services.d/networkmanager.conf <<'EOF'
[service "networkmanager"]
command = /usr/bin/NetworkManager -n
restart = on-failure
restart_delay = 2s
after = dbus rootfs-rw
EOF

cat > /etc/godel/services.d/tun.conf <<'EOF'
[service "tun"]
command = /usr/bin/modprobe tun
type = oneshot
restart = never
after = rootfs-rw udev-trigger
EOF

# No kmod-static-nodes exists under Godel, so nothing creates /dev/net/tun
# on boot: TUN-based VPN daemons (happd/sing-box, wireguard-style setups)
# would all fail with ENOENT. The tun module is CONFIG_TUN=m, so a oneshot
# modprobe creates the device node via devtmpfs.

# restart = always on purpose: on a newer-client connection happd exits
# cleanly by design (self-upgrade re-exec), so on-failure would leave it
# dead. Delay matches upstream RestartSec=5s.
cat > /etc/godel/services.d/happd.conf <<'EOF'
[service "happd"]
command = /opt/happ/bin/happd
restart = always
restart_delay = 5s
after = networkmanager tun
EOF

cat > /etc/godel/services.d/getty-tty1.conf <<'EOF'
[service "getty-tty1"]
command = /usr/lib/dinit/agetty-default tty1
restart = always
restart_delay = 1s
shutdown_timeout = 2s
log = no
after = rootfs-rw udev-trigger
EOF

cat > /etc/godel/services.d/getty-tty2.conf <<'EOF'
[service "getty-tty2"]
command = /usr/lib/dinit/agetty-default tty2
restart = always
restart_delay = 1s
shutdown_timeout = 2s
log = no
after = rootfs-rw
EOF

cat > /etc/godel/services.d/logsync.conf <<'EOF'
[service "logsync"]
command = /bin/sh -c "while :; do cp -f /run/godel/godel.log /var/log/godel/supervisor.log 2>/dev/null; cp -f /run/godel/godel.log.1 /var/log/godel/supervisor.log.1 2>/dev/null; dmesg > /var/log/godel/dmesg.log 2>/dev/null; sleep 5; done"
restart = always
restart_delay = 2s
after = rootfs-rw
EOF

cp -a /etc/grub.d/40_custom "$backup_dir/40_custom.bak-$stamp"
awk '
/menuentry .Artix Godel/ {skip=1}
skip == 0 {print}
skip == 1 && /^}/ {skip=0}
' /etc/grub.d/40_custom > "/etc/grub.d/40_custom.tmp"
mv "/etc/grub.d/40_custom.tmp" /etc/grub.d/40_custom
chmod 755 /etc/grub.d/40_custom
cat >> /etc/grub.d/40_custom <<'EOF'
menuentry 'Artix Godel v3 (zen)' --class artix --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-godel-zen-6463a70a-278e-43ad-bdcd-d19053c52af3' {
	load_video
	set gfxpayload=keep
	insmod gzio
	insmod part_msdos
	insmod ext2
	search --no-floppy --fs-uuid --set=root 6463a70a-278e-43ad-bdcd-d19053c52af3
	echo	'Loading Linux linux-zen with Godel as init ...'
	linux	/boot/vmlinuz-linux-zen root=UUID=6463a70a-278e-43ad-bdcd-d19053c52af3 ro init=/usr/local/sbin/godel nvidia_drm.modeset=1
	echo	'Loading initial ramdisk ...'
	initrd	/boot/amd-ucode.img /boot/initramfs-linux-zen.img
}
menuentry 'Artix Godel v3 (lts)' --class artix --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-godel-lts-6463a70a-278e-43ad-bdcd-d19053c52af3' {
	load_video
	set gfxpayload=keep
	insmod gzio
	insmod part_msdos
	insmod ext2
	search --no-floppy --fs-uuid --set=root 6463a70a-278e-43ad-bdcd-d19053c52af3
	echo	'Loading Linux linux-lts with Godel as init ...'
	linux	/boot/vmlinuz-linux-lts root=UUID=6463a70a-278e-43ad-bdcd-d19053c52af3 ro init=/usr/local/sbin/godel nvidia_drm.modeset=1
	echo	'Loading initial ramdisk ...'
	initrd	/boot/amd-ucode.img /boot/initramfs-linux-lts.img
}
EOF

cp -a /etc/default/grub "$backup_dir/grub-default.bak-$stamp"
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/; s/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub

cp -a /boot/grub/grub.cfg "$backup_dir/grub.cfg.bak-$stamp"
grub-mkconfig -o /boot/grub/grub.cfg

grep -E "^GRUB_(DEFAULT|TIMEOUT|TIMEOUT_STYLE)=" /etc/default/grub

/usr/local/sbin/godel -t /etc/godel/services.d

echo "---- installed"
ls -l /usr/local/sbin/godel /usr/local/bin/godelctl
ls /etc/godel/services.d/
grep -c "menuentry 'Artix Godel" /boot/grub/grub.cfg
grep "GRUB_DEFAULT=" /etc/default/grub
