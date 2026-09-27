#!/bin/sh
# Build a minimal Alpine Linux rootfs with Godel as init, for the
# alpine QEMU sessions.
#
# What is really being assembled is the musl + busybox userland that
# Alpine ships. Godel itself is a static, libc-free binary and does
# not care; the generated service set only needs its binaries present
# (busybox mdev, busybox getty). The Alpine repositories are simply
# the canonical upstream source for that userland, so the test runs
# against real musl-linked binaries rather than a simulation.
#
# apk.static pulls alpine-baselayout, busybox, musl-utils, and
# mdev-conf into .image/alpine-root; the result is packed as
# .image/alpine.ext4.
#
# The result is disposable test material.
#
# Must run as root (apk needs it):   doas sh tools/build-alpine.sh
# Environment:
#   ALPINE_MIRROR  repository mirror (default dl-cdn.alpinelinux.org)
#   ALPINE_BRANCH  release branch   (default v3.22)
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image="$root/.image"
stage="$image/alpine-root"
cache="$image/cache"
mirror=${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}
branch=${ALPINE_BRANCH:-v3.22}
arch=x86_64

[ "$(id -u)" = 0 ] || {
	echo "build-alpine: must run as root (apk.static needs it): doas sh tools/build-alpine.sh" >&2
	exit 1
}
for binary in bin/godel bin/godelctl; do
	test -x "$root/$binary" || {
		echo "build-alpine: missing $root/$binary; run make first" >&2
		exit 1
	}
done

mkdir -p "$cache"
apk_static="$cache/apk-tools-static.apk.unpack"
if [ ! -x "$apk_static/sbin/apk.static" ]; then
	listing=$(curl -fsSL --retry 3 "$mirror/$branch/main/$arch/") ||
		{ echo "build-alpine: cannot list $mirror/$branch/main/$arch/" >&2; exit 1; }
	name=$(printf '%s\n' "$listing" |
		sed -n 's/.*href="\([^"]*apk-tools-static-[^"]*\.apk\)".*/\1/p' | head -n 1)
	[ -n "$name" ] || { echo "build-alpine: apk-tools-static not found in index" >&2; exit 1; }
	echo "build-alpine: fetching $name"
	rm -rf "$apk_static"
	mkdir -p "$apk_static"
	curl -fsSL --retry 3 -o "$cache/$name.part" "$mirror/$branch/main/$arch/$name"
	tar -xzf "$cache/$name.part" -C "$apk_static"
	rm -f "$cache/$name.part"
fi

# apk-tools-static does not bundle the distribution keys; alpine-keys
# provides them. Signature checking stays on.
alpine_keys="$cache/alpine-keys.apk.unpack"
if [ ! -d "$alpine_keys/etc/apk/keys" ]; then
	listing=$(curl -fsSL --retry 3 "$mirror/$branch/main/$arch/") ||
		{ echo "build-alpine: cannot list $mirror/$branch/main/$arch/" >&2; exit 1; }
	name=$(printf '%s\n' "$listing" |
		sed -n 's/.*href="\([^"]*alpine-keys-[^"]*\.apk\)".*/\1/p' | head -n 1)
	[ -n "$name" ] || { echo "build-alpine: alpine-keys not found in index" >&2; exit 1; }
	echo "build-alpine: fetching $name"
	rm -rf "$alpine_keys"
	mkdir -p "$alpine_keys"
	curl -fsSL --retry 3 -o "$cache/$name.part" "$mirror/$branch/main/$arch/$name"
	tar -xzf "$cache/$name.part" -C "$alpine_keys"
	rm -f "$cache/$name.part"
fi
keys_dir="$alpine_keys/etc/apk/keys"
[ -d "$keys_dir" ] || { echo "build-alpine: no keys in alpine-keys package" >&2; exit 1; }

rm -rf "$stage"
mkdir -p "$stage"
# dl-cdn (Fastly) occasionally answers with transient fetch errors;
# retry a few times before giving up.
apk_ok=0
for attempt in 1 2 3 4 5; do
	if "$apk_static/sbin/apk.static" \
		--root "$stage" --initdb \
		--keys-dir "$keys_dir" \
		--repository "$mirror/$branch/main" \
		--repository "$mirror/$branch/community" \
		--no-cache add \
		alpine-baselayout busybox musl-utils mdev-conf 2>&1 |
		grep -v '^WARNING: Ignoring'; then
		apk_ok=1
		break
	fi
	echo "build-alpine: apk attempt $attempt failed; retrying" >&2
	rm -rf "$stage"
	mkdir -p "$stage"
	sleep 5
done
[ "$apk_ok" = 1 ] || { echo "build-alpine: apk bootstrap failed" >&2; exit 1; }

# Godel itself
install -m 755 "$root/bin/godel" "$stage/sbin/godel"
install -m 755 "$root/bin/godelctl" "$stage/bin/godelctl"

# login plumbing: root password + the ttys the session uses
chroot "$stage" /bin/sh -c 'echo root:godel | chpasswd'
for tty in tty1 tty2 ttyS0; do
	grep -q "^$tty$" "$stage/etc/securetty" || echo "$tty" >> "$stage/etc/securetty"
done

# Service set mirrors what tools/install.sh generates for an mdev
# system: same commands, same ordering, no OpenRC.
mkdir -p "$stage/etc/godel"
cat > "$stage/etc/godel/services.conf" <<'EOF'
[service "rootfs-rw"]
command = /bin/mount -o remount,rw /
type = oneshot
restart = never

[service "mdev"]
command = /bin/sh -c "if [ -e /proc/sys/kernel/hotplug ]; then echo /sbin/mdev > /proc/sys/kernel/hotplug; fi; /sbin/mdev -s"
type = oneshot
restart = never
after = rootfs-rw

[service "hostname"]
command = /bin/hostname godel-alpine
type = oneshot
restart = never
after = rootfs-rw

[service "getty-tty1"]
command = /sbin/getty 38400 tty1
restart = always
restart_delay = 1s
shutdown_timeout = 2s
log = no
after = rootfs-rw mdev hostname

[service "getty-ttyS0"]
command = /sbin/getty -L 115200 ttyS0
restart = always
restart_delay = 1s
shutdown_timeout = 2s
log = no
after = rootfs-rw mdev hostname
EOF

./bin/godel -t "$stage/etc/godel/services.conf"

rm -f "$image/alpine.ext4"
mke2fs -q -F -t ext4 -b 4096 -I 256 -L alpine-root \
	-d "$stage" "$image/alpine.ext4" 128m

# Give the artifacts back to the invoking user (doas does not export
# SUDO_USER; logname still sees the original session owner).
owner=${SUDO_USER:-$(logname 2>/dev/null || true)}
if [ -n "$owner" ]; then
	chown "$owner" "$image/alpine.ext4" 2>/dev/null || true
	chown -R "$owner" "$stage" 2>/dev/null || true
fi
echo "alpine rootfs ready at $stage"
echo "alpine image ready at $image/alpine.ext4"
