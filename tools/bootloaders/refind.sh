#!/bin/sh
# rEFInd backend. rEFInd's global default_selection is deliberately left
# intact; this only appends one explicit Linux stanza carrying init=.

REFIND_CONFIG=
for p in /boot/EFI/refind/refind.conf /boot/efi/EFI/refind/refind.conf /efi/EFI/refind/refind.conf; do
	[ -f "$ROOT$p" ] && REFIND_CONFIG=$ROOT$p && break
done
REFIND_BEGIN="# >>> godel begin"
REFIND_END="# <<< godel end"

bl_detect() { [ -n "$REFIND_CONFIG" ]; }
bl_backup() { run cp -a "$REFIND_CONFIG" "$ROOT/etc/godel/backups/refind.conf.bak-$1"; }

bl_add_entry() {
	kernel=$1 initrd=$2 rootarg=$3
	case $REFIND_CONFIG in
	"$ROOT/boot/efi/"*)
		case $kernel:$initrd in /boot/efi/*:/boot/efi/*) kpath=${kernel#/boot/efi}; ipath=${initrd#/boot/efi} ;; *)
			die "rEFInd config is on /boot/efi but kernel/initrd are not on that partition" ;;
		esac
		;;
	"$ROOT/efi/"*)
		case $kernel:$initrd in /efi/*:/efi/*) kpath=${kernel#/efi}; ipath=${initrd#/efi} ;; *)
			die "rEFInd config is on /efi but kernel/initrd are not on that partition" ;;
		esac
		;;
	*)
		kpath=$kernel; ipath=$initrd
		if case $REFIND_CONFIG in "$ROOT/boot/"*) true ;; *) false ;; esac \
			&& mountpoint -q "$ROOT/boot" 2>/dev/null; then
			kpath=${kernel#/boot}; ipath=${initrd#/boot}
		fi
		;;
	esac
	if [ "$DRYRUN" = 1 ]; then
		echo "  [dry-run] add 'Godel (test)' to $REFIND_CONFIG"
		return 0
	fi
	tmp=$REFIND_CONFIG.godel-new
	sed "/^$REFIND_BEGIN\$/,/^$REFIND_END\$/d" "$REFIND_CONFIG" > "$tmp"
	{
		echo "$REFIND_BEGIN"
		echo 'menuentry "Godel (test)" {'
		echo "    loader $kpath"
		echo "    initrd $ipath"
		echo "    options \"root=$rootarg ro init=/usr/local/sbin/godel\""
		echo '}'
		echo "$REFIND_END"
	} >> "$tmp"
	mv "$tmp" "$REFIND_CONFIG"
	info "entry appended to $REFIND_CONFIG"
}

bl_finish() { :; }
bl_verify() {
	if [ "$DRYRUN" = 1 ]; then info "dry-run: rEFInd config not modified"; return 0; fi
	grep -q '^menuentry "Godel (test)" {$' "$REFIND_CONFIG" || die "Godel entry missing from $REFIND_CONFIG"
	info "verified: 'Godel (test)' in $REFIND_CONFIG"
}
