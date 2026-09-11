# Runs N consecutive boot/reboot cycles against a fresh copy of the test
# image and keeps the full transcript under .image/soak. Every cycle goes
# through a real serial login and godelctl reboot, so the persistent ext4
# root disk is remounted and journaled 50 times in a row.
#
# usage: tools/soak.sh [CYCLES] [KERNEL]
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
cycles=${1:-50}
kernel=${2:-/boot/vmlinuz-linux-lts}
logdir="$root/.image/soak"
mkdir -p "$logdir"
stamp=$(date +%Y%m%d-%H%M%S)
log="$logdir/soak-$(basename "$kernel")-$stamp.log"

test -r "$kernel" || { echo "kernel not readable: $kernel" >&2; exit 1; }
test -r "$root/.image/disk.ext4" || {
	echo "no disk image; run tools/build-image.sh" >&2
	exit 1
}

work=$(mktemp /tmp/godel-soak.XXXXXX.ext4)
script=$(mktemp /tmp/godel-soak.XXXXXX.session)
trap 'rm -f "$work" "$script"' EXIT
cp "$root/.image/disk.ext4" "$work"

{
	echo "# generated: $cycles boot/reboot cycles on $(basename "$kernel")"
	i=1
	while [ "$i" -le "$cycles" ]; do
		echo "expect login: timeout=120"
		echo "send root"
		echo "expect Password:"
		echo "send godel"
		echo "expect godel#"
		if [ "$i" -lt "$cycles" ]; then
			echo "send godelctl reboot"
			echo "expect rebooting timeout=60"
		else
			echo "send godelctl poweroff"
			echo "expect powering off timeout=60"
		fi
		i=$((i + 1))
	done
} > "$script"

echo "soak: $cycles cycles on $(basename "$kernel"); transcript $log"
bin/qemu-session \
	--kernel "$kernel" \
	--disk "$work" \
	--script "$script" \
	--log "$log"

boots=$(grep -ac ': starting' "$log" || true)
logins=$(grep -ac 'login\[[0-9]*\]: root login' "$log" || true)
echo "soak: $boots boot banners, $logins logins, transcript kept at $log"
test "$boots" -eq "$cycles"
