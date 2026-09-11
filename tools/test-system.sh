#!/bin/sh
# Runs every serial-console session against a fresh copy of the image and
# keeps transcripts under .image/logs. Exits nonzero on the first failure.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
kernel=${KERNEL:-/boot/vmlinuz-linux-lts}
logs="$root/.image/logs"
mkdir -p "$logs"

work=$(mktemp -d /tmp/godel-system.XXXXXX)
trap 'rm -rf "$work"' EXIT

status=0
for session in tools/sessions/*.session; do
	name=$(basename "$session" .session)
	echo "=== $name"
	cp "$root/.image/disk.ext4" "$work/$name.ext4"
	extras=""
	if [ "$name" = extras ]; then
		extras="--extras"
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
fi
exit $status
