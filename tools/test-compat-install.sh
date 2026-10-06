#!/bin/sh
# Installer compatibility matrix. Every backend runs in a disposable root
# fixture and must preserve the bootloader's existing default selection.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo"
test -x bin/godel || { echo "test-compat-install: run make first" >&2; exit 1; }

base_fixture() {
	fx=$(mktemp -d /tmp/godel-compat.XXXXXX)
	mkdir -p "$fx/etc/godel" "$fx/usr/bin" "$fx/usr/sbin" \
		"$fx/usr/libexec/elogind" "$fx/sys/fs/cgroup" "$fx/boot"
	printf 'ID=void\n' > "$fx/etc/os-release"
	cat > "$fx/etc/fstab" <<'EOF'
/dev/sda1 / ext4 defaults 0 1
UUID=11112222-3333-4444-5555-666677778888 /home ext4 defaults 0 2
/swapfile none swap defaults 0 0
EOF
	: > "$fx/boot/vmlinuz-test"
	: > "$fx/boot/initramfs-test.img"
	: > "$fx/sys/fs/cgroup/cgroup.controllers"
	for b in agetty dbus-daemon udevd udevadm NetworkManager sysctl ip dmesg; do
		: > "$fx/usr/bin/$b"; chmod 755 "$fx/usr/bin/$b"
	done
	: > "$fx/usr/sbin/fsck.ext4"; chmod 755 "$fx/usr/sbin/fsck.ext4"
	: > "$fx/usr/libexec/elogind/elogind"; chmod 755 "$fx/usr/libexec/elogind/elogind"
	printf 'BOOT_IMAGE=/boot/vmlinuz-test root=UUID=aaaa-bbbb ro quiet\n' > "$fx/cmdline"
}

run_install() {
	backend=$1
	shift
	env ROOT="$fx" CMDLINE_FILE="$fx/cmdline" ROOTDEV=/dev/sda1 ROOTFSTYPE=ext4 \
		"$@" bin/godel-install --bootloader "$backend" --force > "$fx/run.log" 2>&1 || {
		cat "$fx/run.log"; echo "test-compat-install: $backend install failed" >&2; exit 1;
	}
	bin/godel -t "$fx/etc/godel/services.d" >/dev/null || {
		echo "test-compat-install: $backend generated invalid services" >&2; exit 1;
	}
}

assert_twice() {
	file=$1 pattern=$2
	[ "$(grep -c "$pattern" "$file")" = 1 ] || {
		echo "test-compat-install: expected exactly one '$pattern' in $file" >&2; exit 1;
	}
}

test_limine_new() {
	base_fixture
	mkdir -p "$fx/boot/limine"
	cat > "$fx/boot/limine/limine.conf" <<'EOF'
timeout: 0
default_entry: Existing
/Existing
    protocol: linux
    path: boot():/boot/vmlinuz-test
EOF
	run_install limine
	assert_twice "$fx/boot/limine/limine.conf" '^/Godel (test)$'
	grep -q '^timeout: 0$' "$fx/boot/limine/limine.conf"
	grep -q '^default_entry: Existing$' "$fx/boot/limine/limine.conf"
	run_install limine
	assert_twice "$fx/boot/limine/limine.conf" '^/Godel (test)$'
	rm -rf "$fx"
}

test_limine_legacy() {
	base_fixture
	cat > "$fx/boot/limine.cfg" <<'EOF'
TIMEOUT=0
DEFAULT_ENTRY=1
/Existing
PROTOCOL=linux
KERNEL_PATH=boot():/boot/vmlinuz-test
EOF
	run_install limine
	assert_twice "$fx/boot/limine.cfg" '^/Godel (test)$'
	grep -q '^TIMEOUT=0$' "$fx/boot/limine.cfg"
	run_install limine
	assert_twice "$fx/boot/limine.cfg" '^/Godel (test)$'
	rm -rf "$fx"
}

test_extlinux() {
	base_fixture
	mkdir -p "$fx/boot/extlinux"
	cat > "$fx/boot/extlinux/extlinux.conf" <<'EOF'
DEFAULT void
LABEL void
  LINUX /boot/vmlinuz-test
EOF
	run_install extlinux
	assert_twice "$fx/boot/extlinux/extlinux.conf" '^LABEL godel-test$'
	grep -q '^DEFAULT void$' "$fx/boot/extlinux/extlinux.conf"
	run_install extlinux
	assert_twice "$fx/boot/extlinux/extlinux.conf" '^LABEL godel-test$'
	rm -rf "$fx"
}

test_systemd_boot() {
	base_fixture
	rm "$fx/boot/initramfs-test.img"
	: > "$fx/boot/initrd.img-test"
	mkdir -p "$fx/boot/loader/entries"
	printf 'default existing.conf\ntimeout 0\n' > "$fx/boot/loader/loader.conf"
	run_install systemd-boot
	grep -q '^title   Godel (test)$' "$fx/boot/loader/entries/godel-test.conf"
	grep -q '^default existing.conf$' "$fx/boot/loader/loader.conf"
	run_install systemd-boot
	assert_twice "$fx/boot/loader/entries/godel-test.conf" '^title   Godel (test)$'
	rm -rf "$fx"
}

test_refind() {
	base_fixture
	mkdir -p "$fx/boot/EFI/refind"
	printf 'default_selection Existing\n' > "$fx/boot/EFI/refind/refind.conf"
	run_install refind
	assert_twice "$fx/boot/EFI/refind/refind.conf" '^menuentry "Godel (test)" {$'
	grep -q '^default_selection Existing$' "$fx/boot/EFI/refind/refind.conf"
	run_install refind
	assert_twice "$fx/boot/EFI/refind/refind.conf" '^menuentry "Godel (test)" {$'
	rm -rf "$fx"
}

alpine_fixture() {
	fx=$(mktemp -d /tmp/godel-compat.XXXXXX)
	mkdir -p "$fx/etc/godel" "$fx/usr/bin" "$fx/usr/sbin" "$fx/sbin" \
		"$fx/usr/libexec/elogind" "$fx/sys/fs/cgroup" "$fx/boot" \
		"$fx/etc/runlevels/sysinit" "$fx/etc/runlevels/boot" \
		"$fx/etc/runlevels/default"
	printf 'ID=alpine\n' > "$fx/etc/os-release"
	cat > "$fx/etc/fstab" <<'EOF'
/dev/sda1 / ext4 defaults 0 1
UUID=11112222-3333-4444-5555-666677778888 /home ext4 defaults 0 2
/swapfile none swap defaults 0 0
EOF
	: > "$fx/boot/vmlinuz-lts"
	: > "$fx/boot/initramfs-lts"
	: > "$fx/sys/fs/cgroup/cgroup.controllers"
	for b in agetty dbus-daemon NetworkManager sysctl ip dmesg; do
		: > "$fx/usr/bin/$b"; chmod 755 "$fx/usr/bin/$b"
	done
	: > "$fx/sbin/mdev"; chmod 755 "$fx/sbin/mdev"
	: > "$fx/etc/mdev.conf"
	: > "$fx/usr/sbin/fsck.ext4"; chmod 755 "$fx/usr/sbin/fsck.ext4"
	: > "$fx/usr/sbin/mkinitfs"; chmod 755 "$fx/usr/sbin/mkinitfs"
	: > "$fx/usr/libexec/elogind/elogind"; chmod 755 "$fx/usr/libexec/elogind/elogind"
	ln -s /sbin/mdev "$fx/etc/runlevels/sysinit/mdev"
	ln -s /sbin/devfs "$fx/etc/runlevels/sysinit/devfs"
	ln -s /etc/init.d/sysctl "$fx/etc/runlevels/boot/sysctl"
	ln -s /etc/init.d/hostname "$fx/etc/runlevels/boot/hostname"
	ln -s /etc/init.d/swap "$fx/etc/runlevels/boot/swap"
	ln -s /etc/init.d/hwclock "$fx/etc/runlevels/boot/hwclock"
	ln -s /etc/init.d/local "$fx/etc/runlevels/default/local"
	# BOOT_IMAGE names the unversioned Alpine kernel; the installer must
	# find initramfs-lts (no .img suffix) for it.
	printf 'BOOT_IMAGE=/boot/vmlinuz-lts root=UUID=alpine-root ro quiet\n' > "$fx/cmdline"
}

assert_alpine_common() {
	run_log=$1
	grep -q "device manager: mdev" "$run_log" ||
		{ echo "test-compat-install: alpine mdev not selected" >&2; exit 1; }
	grep -q "runlevel boot: " "$run_log" ||
		{ echo "test-compat-install: openrc runlevels not reported" >&2; exit 1; }
	grep -q "not transferred" "$run_log" ||
		{ echo "test-compat-install: openrc gaps not reported" >&2; exit 1; }
	grep -q "kernel/initrd : /boot/vmlinuz-lts / /boot/initramfs-lts" "$run_log" ||
		{ echo "test-compat-install: alpine initramfs-lts not used" >&2; exit 1; }
	grep -q "initramfs gen : /usr/sbin/mkinitfs" "$run_log" ||
		{ echo "test-compat-install: mkinitfs not reported" >&2; exit 1; }
	[ -f "$fx/etc/godel/services.d/mdev.conf" ] ||
		{ echo "test-compat-install: mdev service missing" >&2; exit 1; }
	[ ! -e "$fx/etc/godel/services.d/udev.conf" ] ||
		{ echo "test-compat-install: udev must not be generated for mdev systems" >&2; exit 1; }
	grep -q "mdev" "$fx/etc/godel/services.d/getty-tty1.conf" ||
		{ echo "test-compat-install: getty does not gate on mdev" >&2; exit 1; }
	bin/godel -t "$fx/etc/godel/services.d" >/dev/null ||
		{ echo "test-compat-install: alpine services invalid" >&2; exit 1; }
}

test_alpine_extlinux() {
	alpine_fixture
	mkdir -p "$fx/boot/extlinux"
	cat > "$fx/boot/extlinux/extlinux.conf" <<'EOF'
DEFAULT lts
LABEL lts
  LINUX /boot/vmlinuz-lts
  INITRD /boot/initramfs-lts
EOF
	run_install extlinux
	assert_alpine_common "$fx/run.log"
	assert_twice "$fx/boot/extlinux/extlinux.conf" '^LABEL godel-test$'
	grep -q '^DEFAULT lts$' "$fx/boot/extlinux/extlinux.conf"
	grep -q 'INITRD.*initramfs-lts' "$fx/boot/extlinux/extlinux.conf"
	run_install extlinux
	assert_twice "$fx/boot/extlinux/extlinux.conf" '^LABEL godel-test$'
	rm -rf "$fx"
}

test_alpine_grub() {
	alpine_fixture
	mkdir -p "$fx/etc/grub.d" "$fx/etc/default" "$fx/boot/grub"
	cat > "$fx/etc/grub.d/40_custom" <<'EOF'
#!/bin/sh
exec tail -n +3 $0
menuentry 'Alpine Linux' --id alpine {
	linux /boot/vmlinuz-lts root=UUID=alpine-root ro
	initrd /boot/initramfs-lts
}
EOF
	printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=3\n' > "$fx/etc/default/grub"
	printf 'placeholder cfg\n' > "$fx/boot/grub/grub.cfg"
	cat > "$fx/fake-mkconfig.sh" <<'EOF'
#!/bin/sh
[ "$1" = "-o" ] || exit 1
{
	echo "menuentry 'Alpine Linux' --id alpine { }"
	echo "menuentry 'Godel (test)' --id gnulinux-godel-test { }"
} > "$2"
EOF
	chmod 755 "$fx/fake-mkconfig.sh"
	env ROOT="$fx" CMDLINE_FILE="$fx/cmdline" ROOTDEV=/dev/sda1 ROOTFSTYPE=ext4 \
		GRUB_MKCONFIG="$fx/fake-mkconfig.sh" \
		bin/godel-install --bootloader grub --force > "$fx/run.log" 2>&1 || {
		cat "$fx/run.log"; echo "test-compat-install: alpine grub install failed" >&2; exit 1;
	}
	assert_alpine_common "$fx/run.log"
	[ "$(grep -c "menuentry 'Godel (test)'" "$fx/etc/grub.d/40_custom")" = 1 ]
	[ "$(md5sum "$fx/etc/default/grub" | cut -d' ' -f1)" != "" ]
	grep -q '^GRUB_DEFAULT=0$' "$fx/etc/default/grub"
	rm -rf "$fx"
}

test_limine_new
test_limine_legacy
test_extlinux
test_systemd_boot
test_refind
test_alpine_extlinux
test_alpine_grub
echo "test-compat-install: all checks passed (limine current/legacy, extlinux, systemd-boot, refind, alpine extlinux/grub)"
