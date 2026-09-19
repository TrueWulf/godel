#!/bin/sh
# Godel one-command installer: build products -> system -> boot menu.
#
# Safety model (non-negotiable):
#   - the running/default boot entry is never modified;
#   - a separate "Godel (test)" entry is added instead;
#   - everything the installer touches is backed up under /etc/godel/backups;
#   - the generated service set is validated with `godel -t` BEFORE any
#     boot configuration changes;
#   - unsupported bootloaders are refused, not guessed.
#
# Scope for this release: Artix/Arch family + desktop-base profile.
# Bootloader support: grub (implemented); limine/extlinux/systemd-boot
# are future backends and are refused with a clear message.
#
# Usage:
#   doas sh tools/install.sh --bootloader grub [--dry-run] [--force]
#
# Environment (test/fixture mode):
#   ROOT=DIR        operate on a fixture tree instead of / (implies non-root ok)
#   CMDLINE_FILE=F  read kernel args here instead of /proc/cmdline
#   KERNEL=PATH     override detected kernel path
#   ROOTARG=SPEC    override detected root= kernel argument
#   ROOTDEV=DEV     override detected root device (for fsck-root)
#   ROOTFSTYPE=FS   override detected root filesystem type
#   GRUB_MKCONFIG=C override grub-mkconfig binary (backend hook for tests)
#
# Environment variables are read, command-line flags are not affected by
# the environment.

set -eu

: "${ROOT:=}"
: "${CMDLINE_FILE:=/proc/cmdline}"
: "${KERNEL:=}"
: "${ROOTARG:=}"
: "${ROOTDEV:=}"
: "${ROOTFSTYPE:=}"
BOOTLOADER=
DRYRUN=
FORCE=

usage() {
	echo "usage: sh tools/install.sh --bootloader grub [--dry-run] [--force]" >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case $1 in
	--bootloader)
		[ $# -ge 2 ] || usage
		BOOTLOADER=$2
		shift 2
		;;
	--dry-run) DRYRUN=1; shift ;;
	--force) FORCE=1; shift ;;
	*) usage ;;
	esac
done

[ -n "$BOOTLOADER" ] || usage

die() { echo "install: $*" >&2; exit 1; }
info() { echo "install: $*"; }
have() { test -x "$ROOT$1"; }
run() {
	if [ "$DRYRUN" = 1 ]; then
		echo "  [dry-run] $*"
	else
		"$@"
	fi
}

[ -n "$ROOT" ] || [ "$(id -u)" = 0 ] ||
	die "must run as root (or set ROOT=<fixture> for a test run)"

test -x bin/godel || die "bin/godel missing; run make first"
test -x bin/godelctl || die "bin/godelctl missing; run make first"

# --- distro ----------------------------------------------------------------
. "$ROOT/etc/os-release" 2>/dev/null || die "$ROOT/etc/os-release not readable"
case "${ID:-}:${ID_LIKE:-}" in
artix:* | arch:* | *:arch*) ;;
*) die "unsupported distro '${ID:-unknown}': this installer supports the Artix/Arch family" ;;
esac

# --- kernel / initramfs / root ---------------------------------------------
if [ -z "$KERNEL" ]; then
	cmdline=$(cat "$CMDLINE_FILE" 2>/dev/null) || die "cannot read $CMDLINE_FILE"
	KERNEL=$(printf '%s\n' "$cmdline" | tr ' ' '\n' |
		sed -n 's/^BOOT_IMAGE=//p' | head -n 1)
	[ -n "$KERNEL" ] || die "cannot detect BOOT_IMAGE in $CMDLINE_FILE"
	case $KERNEL in
	/boot/*) ;;
	/*) die "unexpected BOOT_IMAGE path: $KERNEL" ;;
	*) KERNEL=/boot/${KERNEL#boot/} ;;
	esac
	ROOTARG=$(printf '%s\n' "$cmdline" | tr ' ' '\n' |
		sed -n 's/^root=//p' | head -n 1)
	[ -n "$ROOTARG" ] || die "cannot detect root= in $CMDLINE_FILE"
fi
[ -f "$ROOT$KERNEL" ] || die "kernel $ROOT$KERNEL not found"

kname=${KERNEL#/boot/}
kname=${kname#vmlinuz-}
INITRD=/boot/initramfs-$kname.img
[ -f "$ROOT$INITRD" ] || die "initramfs $ROOT$INITRD not found (mkinitcpio naming expected)"

[ -f "$ROOT/sys/fs/cgroup/cgroup.controllers" ] ||
	die "cgroup v2 unavailable (no cgroup.controllers); Godel requires a unified hierarchy"
[ -f "$ROOT/etc/fstab" ] || die "$ROOT/etc/fstab missing"

# --- fstab: mount points and swap ------------------------------------------
MPS=$(awk '!/^#/ && NF >= 3 && $2 != "/" && $3 != "swap" &&
	$3 !~ /^(tmpfs|devtmpfs|proc|procfs|sysfs|efivarfs|devpts|mqueue|cgroup2)$/ &&
	"," $4 "," !~ /,noauto,/ && "," $4 "," !~ /,bind,/ { print $2 }' \
	"$ROOT/etc/fstab")
SWAPS=$(awk '!/^#/ && NF >= 3 && $3 == "swap" && "," $4 "," !~ /,noauto,/ { print $1 }' \
	"$ROOT/etc/fstab")
HAS_SWAP=0
[ -n "$SWAPS" ] && HAS_SWAP=1

# --- optional capabilities --------------------------------------------------
ENABLED=
SKIPPED=
enable() { ENABLED="$ENABLED $1"; }
skip() { SKIPPED="$SKIPPED [$1: $2]"; }

AGETTY=
for p in /usr/bin/agetty /sbin/agetty /bin/agetty; do
	have "$p" && AGETTY=$p && break
done
DMESG=
for p in /usr/bin/dmesg /bin/dmesg; do
	have "$p" && DMESG=$p && break
done
IP=
for p in /usr/bin/ip /sbin/ip /bin/ip; do
	have "$p" && IP=$p && break
done

FSCK_OK=
if [ -z "$ROOTDEV" ]; then
	ROOTDEV=$(findmnt -n -o SOURCE / 2>/dev/null || true)
	ROOTFSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
fi
case $ROOTFSTYPE in
ext2 | ext3 | ext4)
	if have /usr/sbin/fsck.ext4 || have /sbin/fsck.ext4; then FSCK_OK=1; fi
	;;
esac

# --- refuse to clobber an existing non-generated set -----------------------
if [ -z "$FORCE" ] && [ -d "$ROOT/etc/godel/services.d" ] &&
	[ "$(ls -A "$ROOT/etc/godel/services.d" 2>/dev/null | wc -l)" -gt 0 ]; then
	die "/etc/godel/services.d is not empty; pass --force to replace it (a backup is kept)"
fi

# --- staging area ------------------------------------------------------------
stamp=$(date +%Y%m%d-%H%M%S).$$
if [ "$DRYRUN" = 1 ]; then
	stage=$(mktemp -d /tmp/godel-install.XXXXXX)/services.d
	mkdir -p "$stage"
	HELPER=$(mktemp -d /tmp/godel-install.XXXXXX)/mount-fstab.sh
	trap 'rm -rf "$(dirname "$stage")" "$(dirname "$HELPER")"' EXIT
else
	stage=$ROOT/etc/godel/services.d.new
	HELPER=$ROOT/etc/godel/lib/mount-fstab.sh
	rm -rf "$stage"
	run mkdir -p "$stage" "$ROOT/etc/godel/lib" "$ROOT/etc/godel/backups" \
		"$ROOT/var/log/godel"
fi

conf() { # conf <name> <contents> — add a service to the staging set
	printf '%s\n' "$2" > "$stage/$1.conf"
	enable "$1"
}

# --- profile: desktop base ---------------------------------------------------
{
	echo '#!/bin/sh'
	echo '# generated by tools/install.sh; mounts every fstab entry Godel needs'
	echo 'for mp in'"$(printf " '%s'" $MPS)"'; do'
	echo '	mountpoint -q "$mp" || { mount "$mp" || echo "mount-fstab: failed $mp"; }'
	echo 'done'
	echo 'exit 0'
} > "$HELPER"
chmod 755 "$HELPER"

after_fsck=
if [ -n "$FSCK_OK" ]; then
	conf fsck-root "[service \"fsck-root\"]
command = /bin/sh -c \"fsck.ext4 -p $ROOTDEV 2>/dev/null || echo 'fsck-root: root mounted or unfixable; kernel journal recovery owns dirty state'\"
type = oneshot
restart = never"
	after_fsck="after = fsck-root"
fi
conf rootfs-rw "[service \"rootfs-rw\"]
command = /bin/mount -o remount,rw /
type = oneshot
restart = never
$after_fsck"

if [ -n "$MPS" ]; then
	conf mount-fstab "[service \"mount-fstab\"]
command = /bin/sh /etc/godel/lib/mount-fstab.sh
type = oneshot
restart = never
after = rootfs-rw"
else
	skip mount-fstab "no extra fstab mounts"
fi

if [ "$HAS_SWAP" = 1 ]; then
	conf swap-fstab "[service \"swap-fstab\"]
command = /bin/sh -c \"swapon -a 2>&1 || echo 'swap: swapon -a failed'\"
type = oneshot
restart = never
after = rootfs-rw"
else
	skip swap-fstab "no swap in fstab"
fi

if [ -n "$IP" ]; then
	conf net-lo "[service \"net-lo\"]
command = $IP link set up dev lo
type = oneshot
restart = never
after = rootfs-rw"
else
	skip net-lo "ip(8) not found"
fi

if have /usr/bin/udevd; then
	conf udev "[service \"udev\"]
command = /usr/bin/udevd
restart = on-failure
restart_delay = 1s
after = rootfs-rw"
	conf udev-trigger "[service \"udev-trigger\"]
command = /bin/sh -c \"udevadm trigger -c add && udevadm settle\"
type = oneshot
restart = never
after = udev"
else
	skip udev "udevd not found (mdev support ships with the Alpine profile)"
fi

if [ -f "$stage/udev-trigger.conf" ]; then
	conf sysctl "[service \"sysctl\"]
command = /usr/bin/sysctl --system
type = oneshot
restart = never
after = udev-trigger"
elif have /usr/bin/sysctl; then
	conf sysctl "[service \"sysctl\"]
command = /usr/bin/sysctl --system
type = oneshot
restart = never
after = rootfs-rw"
else
	skip sysctl "sysctl not found"
fi

after_dbus="rootfs-rw"
if have /usr/bin/dbus-daemon; then
	[ -f "$stage/net-lo.conf" ] && after_dbus="rootfs-rw net-lo"
	conf dbus "[service \"dbus\"]
command = /bin/sh -c \"mkdir -p /run/dbus && exec /usr/bin/dbus-daemon --system --nofork --nopidfile --print-address=3\"
notification-fd = 3
readiness_timeout = 15s
restart = on-failure
restart_delay = 1s
after = $after_dbus"
else
	skip dbus "dbus-daemon not found"
fi

if have /usr/lib/elogind/elogind; then
	conf elogind "[service \"elogind\"]
command = /usr/lib/elogind/elogind --daemon
type = oneshot
restart = never
after = $after_dbus"
else
	skip elogind "elogind not found"
fi

if have /usr/bin/NetworkManager; then
	conf networkmanager "[service \"networkmanager\"]
command = /usr/bin/NetworkManager -n
restart = on-failure
restart_delay = 2s
after = $after_dbus"
else
	skip networkmanager "NetworkManager not found"
fi

if [ -n "$AGETTY" ]; then
	after_getty="rootfs-rw udev-trigger"
	[ -f "$stage/mount-fstab.conf" ] && after_getty="$after_getty mount-fstab"
	for tty in 1 2; do
		conf "getty-tty$tty" "[service \"getty-tty$tty\"]
command = $AGETTY -L 38400 tty$tty linux
restart = always
restart_delay = 1s
shutdown_timeout = 2s
log = no
after = $after_getty"
	done
else
	skip getty "agetty not found"
fi

if [ -n "$DMESG" ]; then
	conf logsync "[service \"logsync\"]
command = /bin/sh -c \"while :; do cp -f /run/godel/godel.log /var/log/godel/supervisor.log 2>/dev/null; cp -f /run/godel/godel.log.1 /var/log/godel/supervisor.log.1 2>/dev/null; $DMESG > /var/log/godel/dmesg.log 2>/dev/null; sleep 5; done\"
restart = always
restart_delay = 2s
after = rootfs-rw"
else
	skip logsync "dmesg not found"
fi

count=$(ls -A "$stage" | wc -l)
[ "$count" -gt 0 ] || die "profile generated no services; aborting"
./bin/godel -t "$stage" || die "generated configuration failed validation"
info "profile validated: $count service(s)"

# --- commit services, install binaries -------------------------------------
if [ "$DRYRUN" != 1 ]; then
	if [ -d "$ROOT/etc/godel/services.d" ] &&
		[ "$(ls -A "$ROOT/etc/godel/services.d" 2>/dev/null | wc -l)" -gt 0 ]; then
		run cp -a "$ROOT/etc/godel/services.d" \
			"$ROOT/etc/godel/backups/services.d.$stamp"
	fi
	run rm -rf "$ROOT/etc/godel/services.d"
	run mv "$stage" "$ROOT/etc/godel/services.d"
	run install -Dm755 bin/godel "$ROOT/usr/local/sbin/godel"
	run install -Dm755 bin/godelctl "$ROOT/usr/local/bin/godelctl"
	run install -Dm644 man/godel.8 "$ROOT/usr/local/share/man/man8/godel.8"
	run install -Dm644 man/godelctl.8 "$ROOT/usr/local/share/man/man8/godelctl.8"
fi

# --- bootloader -------------------------------------------------------------
backend=tools/bootloaders/$BOOTLOADER.sh
test -f "$backend" ||
	die "unknown bootloader '$BOOTLOADER' (available: grub; limine/extlinux/systemd-boot are future backends)"
# shellcheck disable=SC1090
. "$backend"

bl_detect || die "bootloader '$BOOTLOADER' not detected; refusing to guess"
bl_backup "$stamp"
bl_add_entry "$KERNEL" "$INITRD" "$ROOTARG"
bl_finish
bl_verify

# --- report ------------------------------------------------------------------
echo "----------------------------------------------------------"
info "Godel installed:"
info "  kernel/initrd : $KERNEL / $INITRD"
info "  root arg      : $ROOTARG"
info "  services      :$ENABLED"
[ -n "$SKIPPED" ] && info "  skipped       : $SKIPPED"
info "next steps:"
info "  1. reboot and pick 'Godel (test)' in the boot menu"
info "  2. log in on tty1; check: godelctl list"
info "  3. to undo: remove the godel block from the bootloader config,"
info "     regenerate it; backups are in /etc/godel/backups"
