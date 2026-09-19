#!/bin/sh
# Fixture test for tools/install.sh (no root, no real bootloader):
#   - dry-run changes nothing and still validates the profile
#   - a real run installs services that pass `godel -t`
#   - the 'Godel (test)' entry appears exactly once (idempotent re-run)
#   - /etc/default/grub (the default boot selection) is never touched
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
test -x bin/godel || { echo "test-install: run make first" >&2; exit 1; }

fx=$(mktemp -d /tmp/godel-install-test.XXXXXX)
trap 'rm -rf "$fx"' EXIT

mkdir -p "$fx/etc/grub.d" "$fx/etc/default" "$fx/boot/grub" \
	"$fx/usr/bin" "$fx/usr/sbin" "$fx/usr/lib/elogind" \
	"$fx/sys/fs/cgroup" "$fx/etc/godel"

printf 'ID=artix\n' > "$fx/etc/os-release"
cat > "$fx/etc/fstab" <<'EOF'
# /dev/sda1 is /, plus one extra mount and swap: the desktop-base shape
/dev/sda1 / ext4 defaults 0 1
UUID=11112222-3333-4444-5555-666677778888 /home ext4 defaults 0 2
/swapfile none swap defaults 0 0
EOF
: > "$fx/boot/vmlinuz-test"
: > "$fx/boot/initramfs-test.img"
cat > "$fx/etc/grub.d/40_custom" <<'EOF'
#!/bin/sh
exec tail -n +3 $0
menuentry 'Artix Linux' --id gnulinux-arch {
	linux /boot/vmlinuz-linux root=UUID=aaaa ro
	initrd /boot/initramfs-linux.img
}
EOF
printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\n' > "$fx/etc/default/grub"
printf 'placeholder cfg\n' > "$fx/boot/grub/grub.cfg"
: > "$fx/sys/fs/cgroup/cgroup.controllers"

for b in agetty dbus-daemon udevd udevadm NetworkManager sysctl ip dmesg; do
	: > "$fx/usr/bin/$b"
	chmod 755 "$fx/usr/bin/$b"
done
: > "$fx/usr/sbin/fsck.ext4"
chmod 755 "$fx/usr/sbin/fsck.ext4"
: > "$fx/usr/lib/elogind/elogind"
chmod 755 "$fx/usr/lib/elogind/elogind"

printf 'BOOT_IMAGE=/boot/vmlinuz-test root=UUID=aaaa-bbbb ro quiet\n' \
	> "$fx/cmdline"

# fake grub-mkconfig: writes a menu that includes the godel entry,
# mirroring what a real grub-mkconfig does with 40_custom
cat > "$fx/fake-mkconfig.sh" <<'EOF'
#!/bin/sh
# $1 = -o, $2 = output file
[ "$1" = "-o" ] || exit 1
{
	echo "### BEGIN fake grub-mkconfig ###"
	echo "menuentry 'Artix Linux' --id gnulinux-arch { }"
	echo "menuentry 'Godel (test)' --class godel --id gnulinux-godel-test { }"
	echo "### END fake grub-mkconfig ###"
} > "$2"
EOF
chmod 755 "$fx/fake-mkconfig.sh"

env ROOT="$fx" CMDLINE_FILE="$fx/cmdline" \
	ROOTDEV=/dev/sda1 ROOTFSTYPE=ext4 GRUB_MKCONFIG="$fx/fake-mkconfig.sh" \
	sh tools/install.sh --bootloader grub --dry-run > "$fx/dry.log" 2>&1 || {
	cat "$fx/dry.log"
	echo "test-install: dry-run failed" >&2
	exit 1
}
grep -q "profile validated" "$fx/dry.log" ||
	{ echo "test-install: dry-run did not validate profile" >&2; exit 1; }
[ "$(grep -c godel "$fx/etc/grub.d/40_custom")" = 0 ] ||
	{ echo "test-install: dry-run modified 40_custom" >&2; exit 1; }
[ ! -e "$fx/etc/godel/services.d" ] ||
	{ echo "test-install: dry-run wrote services.d" >&2; exit 1; }
[ ! -e "$fx/usr/local/sbin/godel" ] ||
	{ echo "test-install: dry-run installed binaries" >&2; exit 1; }

default_before=$(md5sum "$fx/etc/default/grub" | cut -d' ' -f1)
custom_before=$(md5sum "$fx/etc/grub.d/40_custom" | cut -d' ' -f1)

env ROOT="$fx" CMDLINE_FILE="$fx/cmdline" \
	ROOTDEV=/dev/sda1 ROOTFSTYPE=ext4 GRUB_MKCONFIG="$fx/fake-mkconfig.sh" \
	sh tools/install.sh --bootloader grub > "$fx/run.log" 2>&1 || {
	cat "$fx/run.log"
	echo "test-install: install failed" >&2
	exit 1
}
grep -q "services      : fsck-root rootfs-rw mount-fstab swap-fstab" "$fx/run.log" ||
	{ echo "test-install: unexpected service set:" >&2; grep 'services      :' "$fx/run.log" >&2; exit 1; }

bin/godel -t "$fx/etc/godel/services.d" ||
	{ echo "test-install: installed services failed validation" >&2; exit 1; }
[ -x "$fx/usr/local/sbin/godel" ] ||
	{ echo "test-install: godel not installed" >&2; exit 1; }
[ -f "$fx/etc/godel/lib/mount-fstab.sh" ] ||
	{ echo "test-install: mount helper missing" >&2; exit 1; }
grep -q "swap-fstab" "$fx/etc/godel/services.d/swap-fstab.conf" ||
	{ echo "test-install: swap service missing" >&2; exit 1; }

[ "$(grep -c "menuentry 'Godel (test)'" "$fx/etc/grub.d/40_custom")" = 1 ] ||
	{ echo "test-install: expected 1 entry in 40_custom" >&2; exit 1; }
grep -q "search --no-floppy --fs-uuid --set=root aaaa-bbbb" \
	"$fx/etc/grub.d/40_custom" ||
	{ echo "test-install: grub search line missing" >&2; exit 1; }
[ "$(grep -c "menuentry 'Godel (test)'" "$fx/boot/grub/grub.cfg")" = 1 ] ||
	{ echo "test-install: entry missing from regenerated menu" >&2; exit 1; }
[ "$(md5sum "$fx/etc/default/grub" | cut -d' ' -f1)" = "$default_before" ] ||
	{ echo "test-install: /etc/default/grub was modified" >&2; exit 1; }

env ROOT="$fx" CMDLINE_FILE="$fx/cmdline" \
	ROOTDEV=/dev/sda1 ROOTFSTYPE=ext4 GRUB_MKCONFIG="$fx/fake-mkconfig.sh" \
	sh tools/install.sh --bootloader grub --force > "$fx/rerun.log" 2>&1 || {
	cat "$fx/rerun.log"
	echo "test-install: re-run failed" >&2
	exit 1
}
[ "$(grep -c "menuentry 'Godel (test)'" "$fx/etc/grub.d/40_custom")" = 1 ] ||
	{ echo "test-install: re-run duplicated the entry" >&2; exit 1; }
[ "$(md5sum "$fx/etc/default/grub" | cut -d' ' -f1)" = "$default_before" ] ||
	{ echo "test-install: re-run modified /etc/default/grub" >&2; exit 1; }
[ "$(ls "$fx/etc/godel/backups" | grep -c 40_custom)" -ge 2 ] ||
	{ echo "test-install: re-run did not back up 40_custom" >&2; exit 1; }

# refuse an unknown bootloader instead of guessing
if env ROOT="$fx" CMDLINE_FILE="$fx/cmdline" \
	sh tools/install.sh --bootloader limine >/dev/null 2>&1; then
	echo "test-install: limine should be refused today" >&2
	exit 1
fi

echo "test-install: all checks passed"
