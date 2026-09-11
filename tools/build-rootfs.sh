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

e2fsck=/usr/bin/e2fsck
loader=/lib64/ld-linux-x86-64.so.2
if [ -x "$e2fsck" ] && [ -f "$loader" ]; then
	mkdir -p "$stage/usr/sbin" "$stage/usr/lib" "$stage/lib64"
	install -m 755 "$e2fsck" "$stage/usr/sbin/e2fsck"
	ln -s /usr/sbin/e2fsck "$stage/bin/fsck.ext4"
	install -m 755 "$loader" "$stage/lib64/ld-linux-x86-64.so.2"
	for lib in $(ldd "$e2fsck" | awk '$3 ~ /^\// {print $3}'); do
		install -m 755 "$lib" "$stage/usr/lib/$(basename "$lib")"
	done
	for lib in $(ldd "$loader" | awk '$3 ~ /^\// {print $3}'); do
		install -m 755 "$lib" "$stage/usr/lib/$(basename "$lib")"
	done
fi

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
