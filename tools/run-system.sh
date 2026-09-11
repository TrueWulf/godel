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

append=${APPEND:-console=ttyS0,115200 root=/dev/vda ro init=/sbin/godel panic=-1}

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
