#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
kernel=${KERNEL:-/boot/vmlinuz-linux-lts}
logs="$root/.image/logs"
mkdir -p "$logs"

test -x bin/godel || { echo "no bin/godel; run make" >&2; exit 1; }
if ! bin/godel -t tools/rootfs/services.conf; then
	echo "host-side config validation failed" >&2
	exit 1
fi

work=$(mktemp -d /tmp/godel-system.XXXXXX)
trap 'rm -rf "$work"' EXIT

status=0
for session in tools/sessions/*.session; do
	name=$(basename "$session" .session)
	# alpine-* sessions run against .image/alpine.ext4 (musl userland),
	# driven by the qemu-alpine target, not the busybox test image
	case $name in alpine-*) continue ;; esac
	echo "=== $name"
	cp "$root/.image/disk.ext4" "$work/$name.ext4"
	if [ "$name" = fsck ]; then
		debugfs -w -R "ssv s_state 0" "$work/$name.ext4" > /dev/null 2>&1 || true
	fi
	extras=""
	if [ "$name" = extras ]; then
		cp "$root/.image/home.ext4" "$work/$name-home.ext4"
		cp "$root/.image/var.ext4" "$work/$name-var.ext4"
		debugfs -w -R "ssv s_state 0" "$work/$name-home.ext4" > /dev/null 2>&1 || true
		debugfs -w -R "ssv s_state 0" "$work/$name-var.ext4" > /dev/null 2>&1 || true
		extras="--extra $work/$name-home.ext4 --extra $work/$name-var.ext4"
	fi
	if ! bin/qemu-session \
			--kernel "$kernel" \
			--disk "$work/$name.ext4" \
			--script "$session" \
			--log "$logs/$name.log" \
			$extras; then
		echo "=== $name FAILED (transcript: $logs/$name.log)"
		status=1
		break
	fi
done

if [ "$status" = 0 ]; then
	echo "all system sessions passed"
	# The basic transcript must yield a parseable boot report: this
	# verifies the [T+Nms] supervisor stamping end-to-end in QEMU.
	if bin/godelctl boot-report "$logs/basic.log" | tee "$logs/basic.report" |
			grep -q '^boot 1: .*ready='; then
		echo "boot report parsed (see $logs/basic.report)"
	else
		echo "boot report FAILED on basic.log" >&2
		status=1
	fi
fi
exit $status
