#!/bin/sh
# Limine backend. Supports current limine.conf colon syntax and legacy
# limine.cfg KEY=VALUE syntax. Limine reads its config directly, so no
# regeneration command is needed after an atomic config update.

LIMINE_CONFIG=
for p in \
	/boot/limine/limine.conf /boot/limine.conf /limine/limine.conf /limine.conf \
	/boot/efi/EFI/BOOT/limine.conf /boot/efi/limine/limine.conf \
	/efi/EFI/BOOT/limine.conf /efi/limine/limine.conf \
	/boot/limine/limine.cfg /boot/limine.cfg /limine/limine.cfg /limine.cfg; do
	[ -f "$ROOT$p" ] && LIMINE_CONFIG=$ROOT$p && break
done
LIMINE_BEGIN="# >>> godel begin"
LIMINE_END="# <<< godel end"

bl_detect() { [ -n "$LIMINE_CONFIG" ]; }

bl_backup() {
	run cp -a "$LIMINE_CONFIG" "$ROOT/etc/godel/backups/limine.conf.bak-$1"
}

bl_add_entry() {
	kernel=$1 initrd=$2 rootarg=$3
	case $LIMINE_CONFIG in
	"$ROOT/boot/efi/"*)
		case $kernel:$initrd in /boot/efi/*:/boot/efi/*) kpath=${kernel#/boot/efi}; ipath=${initrd#/boot/efi} ;; *)
			die "Limine config is on /boot/efi but kernel/initrd are not on that partition" ;;
		esac
		;;
	"$ROOT/efi/"*)
		case $kernel:$initrd in /efi/*:/efi/*) kpath=${kernel#/efi}; ipath=${initrd#/efi} ;; *)
			die "Limine config is on /efi but kernel/initrd are not on that partition" ;;
		esac
		;;
	*)
		kpath=$kernel; ipath=$initrd
		if case $LIMINE_CONFIG in "$ROOT/boot/"*) true ;; *) false ;; esac \
			&& mountpoint -q "$ROOT/boot" 2>/dev/null; then
			kpath=${kernel#/boot}; ipath=${initrd#/boot}
		fi
		;;
	esac
	if [ "$DRYRUN" = 1 ]; then
		echo "  [dry-run] add 'Godel (test)' to $LIMINE_CONFIG"
		return 0
	fi
	tmp=$LIMINE_CONFIG.godel-new
	sed "/^$LIMINE_BEGIN\$/,/^$LIMINE_END\$/d" "$LIMINE_CONFIG" > "$tmp"
	{
		echo "$LIMINE_BEGIN"
		if grep -qi '^KERNEL_PATH=' "$LIMINE_CONFIG"; then
			echo '/Godel (test)'
			echo 'PROTOCOL=linux'
			echo "KERNEL_PATH=boot():$kpath"
			echo "MODULE_PATH=boot():$ipath"
			echo "KERNEL_CMDLINE=root=$rootarg ro init=/usr/local/sbin/godel"
		else
			echo '/Godel (test)'
			echo '    protocol: linux'
			echo "    path: boot():$kpath"
			echo "    module_path: boot():$ipath"
			echo "    cmdline: root=$rootarg ro init=/usr/local/sbin/godel"
		fi
		echo "$LIMINE_END"
	} >> "$tmp"
	mv "$tmp" "$LIMINE_CONFIG"
	info "entry appended to $LIMINE_CONFIG"
}

bl_finish() { :; }

bl_verify() {
	if [ "$DRYRUN" = 1 ]; then info "dry-run: Limine config not modified"; return 0; fi
	grep -q '^/Godel (test)$' "$LIMINE_CONFIG" || die "Godel entry missing from $LIMINE_CONFIG"
	info "verified: 'Godel (test)' in $LIMINE_CONFIG"
}
