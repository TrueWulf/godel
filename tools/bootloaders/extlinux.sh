#!/bin/sh
# extlinux/syslinux backend. Adds a LABEL only; the existing DEFAULT remains
# untouched, so the old init stays the automatic fallback.

EXTLINUX_CONFIG=
for p in /boot/extlinux/extlinux.conf /boot/syslinux/syslinux.cfg /boot/syslinux/syslinux.conf; do
	[ -f "$ROOT$p" ] && EXTLINUX_CONFIG=$ROOT$p && break
done
EXTLINUX_BEGIN="# >>> godel begin"
EXTLINUX_END="# <<< godel end"

bl_detect() { [ -n "$EXTLINUX_CONFIG" ]; }
bl_backup() { run cp -a "$EXTLINUX_CONFIG" "$ROOT/etc/godel/backups/extlinux.conf.bak-$1"; }

bl_add_entry() {
	kernel=$1 initrd=$2 rootarg=$3
	if [ "$DRYRUN" = 1 ]; then
		echo "  [dry-run] add 'Godel (test)' to $EXTLINUX_CONFIG"
		return 0
	fi
	tmp=$EXTLINUX_CONFIG.godel-new
	sed "/^$EXTLINUX_BEGIN\$/,/^$EXTLINUX_END\$/d" "$EXTLINUX_CONFIG" > "$tmp"
	{
		echo "$EXTLINUX_BEGIN"
		echo 'LABEL godel-test'
		echo '  MENU LABEL Godel (test)'
		echo "  LINUX $kernel"
		echo "  INITRD $initrd"
		echo "  APPEND root=$rootarg ro init=/usr/local/sbin/godel"
		echo "$EXTLINUX_END"
	} >> "$tmp"
	mv "$tmp" "$EXTLINUX_CONFIG"
	info "entry appended to $EXTLINUX_CONFIG"
}

bl_finish() { :; }
bl_verify() {
	if [ "$DRYRUN" = 1 ]; then info "dry-run: extlinux config not modified"; return 0; fi
	grep -q '^LABEL godel-test$' "$EXTLINUX_CONFIG" || die "Godel entry missing from $EXTLINUX_CONFIG"
	info "verified: LABEL godel-test in $EXTLINUX_CONFIG"
}
