#!/bin/sh
# systemd-boot backend. A Boot Loader Specification entry is a standalone
# file, so loader.conf/default is deliberately never read or changed.

BOOT_ENTRIES=
for p in /boot/loader/entries /boot/efi/loader/entries /efi/loader/entries; do
	[ -d "$ROOT$p" ] && BOOT_ENTRIES=$ROOT$p && break
done
SYSTEMD_BOOT_ENTRY=

bl_detect() {
	[ -n "$BOOT_ENTRIES" ] || return 1
	case $BOOT_ENTRIES in
	"$ROOT/boot/loader/entries") SYSTEMD_BOOT_ENTRY=$BOOT_ENTRIES/godel-test.conf ;;
	"$ROOT/boot/efi/loader/entries") SYSTEMD_BOOT_ENTRY=$BOOT_ENTRIES/godel-test.conf ;;
	"$ROOT/efi/loader/entries") SYSTEMD_BOOT_ENTRY=$BOOT_ENTRIES/godel-test.conf ;;
	esac
	return 0
}

bl_backup() {
	[ -e "$SYSTEMD_BOOT_ENTRY" ] &&
		run cp -a "$SYSTEMD_BOOT_ENTRY" "$ROOT/etc/godel/backups/godel-test.conf.bak-$1"
}

bl_add_entry() {
	kernel=$1 initrd=$2 rootarg=$3
	# Entry paths are relative to the boot partition. The common /boot layout
	# is supported; a separate ESP must also contain the chosen kernel/initrd.
	case $BOOT_ENTRIES in
	"$ROOT/boot/loader/entries") kpath=${kernel#/boot}; ipath=${initrd#/boot} ;;
	"$ROOT/boot/efi/loader/entries")
		case $kernel:$initrd in /boot/efi/*:/boot/efi/*) kpath=${kernel#/boot/efi}; ipath=${initrd#/boot/efi} ;; *)
			die "systemd-boot ESP is /boot/efi but kernel/initrd are not on that partition" ;;
		esac
		;;
	"$ROOT/efi/loader/entries")
		case $kernel:$initrd in /efi/*:/efi/*) kpath=${kernel#/efi}; ipath=${initrd#/efi} ;; *)
			die "systemd-boot ESP is /efi but kernel/initrd are not on that partition" ;;
		esac
		;;
	esac
	if [ "$DRYRUN" = 1 ]; then
		echo "  [dry-run] write $SYSTEMD_BOOT_ENTRY without changing loader.conf"
		return 0
	fi
	cat > "$SYSTEMD_BOOT_ENTRY" <<EOF
title   Godel (test)
linux   $kpath
initrd  $ipath
options root=$rootarg ro init=/usr/local/sbin/godel
EOF
	info "entry written to $SYSTEMD_BOOT_ENTRY"
}

bl_finish() { :; }
bl_verify() {
	if [ "$DRYRUN" = 1 ]; then info "dry-run: systemd-boot entry not written"; return 0; fi
	grep -q '^title   Godel (test)$' "$SYSTEMD_BOOT_ENTRY" || die "Godel entry missing from $SYSTEMD_BOOT_ENTRY"
	info "verified: $SYSTEMD_BOOT_ENTRY"
}
