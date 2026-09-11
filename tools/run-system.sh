# Boots the built Godel test image in QEMU with the serial console on
# stdio (exit with Ctrl-A x). The root filesystem is a persistent ext4
# disk; no initramfs is used because virtio-blk and ext4 are built into
# the target kernels. Environment overrides:
#   KERNEL=/boot/vmlinuz-linux-zen  pick the kernel to test
#   DISK=/path/to/disk.ext4         pick another root disk
#   APPEND="..."                    override the kernel command line
#   EXTRAS=1                        attach optional /home and /var disks
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kernel=${KERNEL:-/boot/vmlinuz-linux-lts}
disk=${DISK:-$root/.image/disk.ext4}

test -r "$disk" || {
	echo "no disk image at $disk; run tools/build-image.sh" >&2
	exit 1
}
test -r "$kernel" || {
	echo "kernel not readable: $kernel" >&2
	exit 1
}

append=${APPEND:-console=ttyS0,115200 root=/dev/vda rw init=/sbin/godel panic=-1}

set -- qemu-system-x86_64 \
	-m 256M \
	-kernel "$kernel" \
	-drive file="$disk",format=raw,if=virtio \
	-append "$append" \
	-nographic

if [ "${EXTRAS:-0}" = 1 ]; then
	set -- "$@" \
		-drive file="$root/.image/home.ext4",format=raw,if=virtio \
		-drive file="$root/.image/var.ext4",format=raw,if=virtio
fi

exec "$@"
