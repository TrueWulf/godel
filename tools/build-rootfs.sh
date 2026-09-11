# Assembles the disposable Godel test root filesystem under .image/root.
# Nothing outside .image is written. The static busybox is fetched once
# into .image/cache. Binaries must already exist in bin/ (build-image.sh
# builds them first). No root privileges are required.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image="$root/.image"
stage="$image/root"
cache="$image/cache"
bbver=1.35.0
busybox="$cache/busybox-$bbver-x86_64-linux-musl"

if [ ! -x "$busybox" ]; then
	mkdir -p "$cache"
	url="https://busybox.net/downloads/binaries/$bbver-x86_64-linux-musl/busybox"
	echo "fetching $url"
	curl -fsSL --retry 3 -o "$busybox.part" "$url"
	chmod 755 "$busybox.part"
	case "$(file -b "$busybox.part")" in
	*static*) ;;
	*) echo "downloaded busybox is not static" >&2; exit 1 ;;
	esac
	mv "$busybox.part" "$busybox"
fi

for binary in bin/godel bin/godelctl; do
	test -x "$root/$binary" || {
		echo "missing $root/$binary; run tools/build-image.sh" >&2
		exit 1
	}
done

rm -rf "$stage"
mkdir -p "$stage/bin" "$stage/sbin" "$stage/etc/godel" "$stage/proc" \
	"$stage/sys" "$stage/sys/fs/cgroup" "$stage/dev" "$stage/run" \
	"$stage/tmp" "$stage/var/log" "$stage/home" "$stage/root" "$stage/mnt"
chmod 1777 "$stage/tmp"
chmod 700 "$stage/root"

install -m 755 "$busybox" "$stage/bin/busybox"
# init, halt, reboot, and poweroff are deliberately not installed: their
# busybox signal conventions differ from Godel's. Use godelctl instead.
for applet in sh ash cat ls ps kill echo printf sleep sync dmesg uname \
	hostname mount umount setsid stty clear reset sed vi grep cp mv rm \
	ln chmod chown mkdir mknod touch id env date true false test seq \
	head tail wc md5sum free top passwd su dd find xargs awk cut sort \
	uniq tr stat readlink dirname basename tty whoami mountpoint login \
	getty; do
	ln -s busybox "$stage/bin/$applet"
done

install -m 755 "$root/bin/godel" "$stage/sbin/godel"
install -m 755 "$root/bin/godelctl" "$stage/bin/godelctl"

cat > "$stage/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF
cat > "$stage/etc/group" <<'EOF'
root:x:0:
EOF
hash=$("$busybox" cryptpw -m sha512 godel)
printf 'root:%s:19900:0:99999:7:::\n' "$hash" > "$stage/etc/shadow"
chmod 600 "$stage/etc/shadow"
cat > "$stage/etc/securetty" <<'EOF'
console
tty0
tty1
ttyS0
EOF

cp "$root/tools/rootfs/services.conf" "$stage/etc/godel/services.conf"
cp "$root/tools/rootfs/issue" "$stage/etc/issue"
cp "$root/tools/rootfs/motd" "$stage/etc/motd"
cp "$root/tools/rootfs/profile" "$stage/etc/profile"
cat > "$stage/etc/os-release" <<EOF
NAME="Godel test image"
ID=godel-test
VERSION="$bbver"
PRETTY_NAME="Godel test image (busybox $bbver)"
EOF

echo "rootfs ready at $stage"
