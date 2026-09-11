set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image="$root/.image"
PATH="$HOME/tools/hare/bin:$PATH"
hare=${HARE:-hare}

cd "$root"
"$hare" build -o bin/godel ./cmd/godel
"$hare" build -o bin/godelctl ./cmd/godelctl
tools/build-rootfs.sh

rm -f "$image/disk.ext4" "$image/home.ext4" "$image/var.ext4"
mke2fs -q -F -t ext4 -b 4096 -I 256 -L godel-root \
	-d "$image/root" "$image/disk.ext4" 64m

mkdir -p "$image/extra-home" "$image/extra-var"
echo "godel home extra disk" > "$image/extra-home/marker.txt"
echo "godel var extra disk" > "$image/extra-var/marker.txt"
mke2fs -q -F -t ext4 -b 1024 -I 256 -L godel-home \
	-d "$image/extra-home" "$image/home.ext4" 2m
mke2fs -q -F -t ext4 -b 1024 -I 256 -L godel-var \
	-d "$image/extra-var" "$image/var.ext4" 2m
rm -rf "$image/extra-home" "$image/extra-var"

echo "image ready at $image/disk.ext4"
