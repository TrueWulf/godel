#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export PATH="$HOME/tools/hare/bin:$PATH"
hare=${HARE:-hare}
kernel=${KERNEL:-/boot/vmlinuz-linux-lts}
work="$root/.qemu/root"
mode=${1:-reboot}

command -v "$hare" >/dev/null || { printf '%s\n' "hare not found in PATH" >&2; exit 1; }
test -r "$kernel" || { printf '%s\n' "kernel not found: $kernel" >&2; exit 1; }

(cd "$root" && "$hare" test ./godel)
mkdir -p "$root/bin"
(cd "$root" && "$hare" build -o bin/godel ./cmd/godel)
(cd "$root" && "$hare" build -o bin/sh ./cmd/smoke/shell)
(cd "$root" && "$hare" build -o bin/worker ./cmd/smoke/worker)
(cd "$root" && "$hare" build -o bin/exiter ./cmd/smoke/exiter)
(cd "$root" && "$hare" build -o bin/reloadtest ./cmd/smoke/reloadtest)
(cd "$root" && "$hare" build -o bin/probe ./cmd/smoke/probe)

rm -rf "$work"
mkdir -p "$work/bin" "$work/etc/godel" "$work/proc" "$work/sys/fs/cgroup" \
	"$work/dev" "$work/run" "$work/root"
cp "$root/bin/godel" "$work/init"
cp "$root/bin/sh" "$work/bin/sh"
cp "$root/bin/worker" "$work/bin/worker"
cp "$root/bin/exiter" "$work/bin/exiter"
cp "$root/bin/reloadtest" "$work/bin/reloadtest"
cp "$root/bin/probe" "$work/bin/probe"
{
	printf '%s\n' '[service "exiter"]'
	printf '%s\n' 'command = /bin/exiter'
	printf '%s\n' 'restart = on-failure'
	printf '%s\n' 'restart_limit = 3'
	printf '%s\n' 'restart_delay = 100ms'
	printf '%s\n' '[service "worker"]'
	printf '%s\n' 'command = /bin/worker -v --booted'
	printf '%s\n' '[service "smoke"]'
	printf '%s\n' 'command = /bin/sh --smoke'
	printf '%s\n' '[service "reloadtest"]'
	printf '%s\n' 'command = /bin/reloadtest'
	printf '%s\n' 'restart = never'
	printf '%s\n' '[service "probe"]'
	printf '%s\n' 'command = /bin/probe'
	printf '%s\n' 'type = oneshot'
	printf '%s\n' 'env = GODEL_SMOKE_ENV=present'
} > "$work/etc/godel/services.conf"

if [ "$mode" = badconfig ]; then
	printf '%s\n' 'command = /bin/broken' > "$work/etc/godel/services.conf"
fi

(cd "$work" && printf '%s\0' . ./bin ./bin/sh ./bin/worker ./bin/exiter \
	./bin/reloadtest ./etc ./etc/godel ./etc/godel/services.conf \
	./bin/probe \
	./proc ./sys ./sys/fs ./sys/fs/cgroup ./dev ./run ./root ./init \
	| cpio --quiet --null -o -H newc > "$root/.qemu/initramfs.cpio")

if [ "$mode" = poweroff ]; then
	append='console=ttyS0 root=/dev/ram rdinit=/init godel-test=poweroff'
else
	append='console=ttyS0 root=/dev/ram rdinit=/init godel-test=reboot'
fi
exec qemu-system-x86_64 -m 256M -kernel "$kernel" \
	-initrd "$root/.qemu/initramfs.cpio" -append "$append" \
	-nographic -no-reboot
