#!/bin/sh
# GRUB backend for tools/install.sh.
#
# Contract (shared with future limine/extlinux/systemd-boot backends):
#   bl_detect                 -> exit 0 when the bootloader is usable
#   bl_backup STAMP           -> back up every file this backend may change
#   bl_add_entry K I R        -> add the "Godel (test)" entry (idempotent);
#                                K=kernel path, I=initrd path, R=root= spec
#   bl_finish                 -> regenerate the boot menu
#   bl_verify                 -> assert the entry landed in the live menu
#
# Globals provided by install.sh: ROOT, DRYRUN, run(), die(), info().
# The generated entry is additive only: the default entry and
# GRUB_DEFAULT are never touched.

GRUB_MKCONFIG=${GRUB_MKCONFIG:-grub-mkconfig}
GODEL_BEGIN="# >>> godel begin"
GODEL_END="# <<< godel end"

bl_detect() {
	command -v "$GRUB_MKCONFIG" >/dev/null 2>&1 ||
		return 1
	[ -d "$ROOT/boot/grub" ] || return 1
	[ -f "$ROOT/etc/grub.d/40_custom" ] || return 1
	return 0
}

bl_backup() {
	run cp -a "$ROOT/etc/grub.d/40_custom" \
		"$ROOT/etc/godel/backups/40_custom.bak-$1"
	run cp -a "$ROOT/boot/grub/grub.cfg" \
		"$ROOT/etc/godel/backups/grub.cfg.bak-$1"
}

bl_add_entry() {
	_kernel=$1
	_initrd=$2
	_rootarg=$3

	# grub's own root: search by filesystem UUID so the entry works no
	# matter what GRUB_DEFAULT points at
	_uuid=
	case $_rootarg in
	UUID=*) _uuid=${_rootarg#UUID=} ;;
	/dev/*)
		if command -v blkid >/dev/null 2>&1; then
			_uuid=$(blkid -s UUID -o value "$_rootarg" 2>/dev/null || true)
		fi
		;;
	esac

	# /boot on its own partition -> kernel paths are relative to it
	_krel=$_kernel
	_irel=$_initrd
	if mountpoint -q "$ROOT/boot" 2>/dev/null; then
		_krel=${_kernel#/boot}
		_irel=${_initrd#/boot}
	fi

	if [ "$DRYRUN" = 1 ]; then
		echo "  [dry-run] add 'Godel (test)' to $ROOT/etc/grub.d/40_custom"
		return 0
	fi

	_custom=$ROOT/etc/grub.d/40_custom
	_tmp=${_custom}.godel-new
	sed "/^$GODEL_BEGIN\$/,/^$GODEL_END\$/d" "$_custom" > "$_tmp"
	{
		echo "$GODEL_BEGIN"
		echo "menuentry 'Godel (test)' --class godel --id gnulinux-godel-test {"
		echo "	load_video"
		echo "	insmod gzio"
		echo "	insmod part_msdos"
		echo "	insmod part_gpt"
		case ${ROOTFSTYPE:-} in
		btrfs) echo "	insmod btrfs" ;;
		xfs) echo "	insmod xfs" ;;
		f2fs) echo "	insmod f2fs" ;;
		*) echo "	insmod ext2" ;;
		esac
		if [ -n "$_uuid" ]; then
			echo "	search --no-floppy --fs-uuid --set=root $_uuid"
		fi
		echo "	echo	'Loading ${_kernel##*/} with Godel as init ...'"
		echo "	linux	$_krel root=$_rootarg ro init=/usr/local/sbin/godel"
		echo "	echo	'Loading initial ramdisk ...'"
		echo "	initrd	$_irel"
		echo "}"
		echo "$GODEL_END"
	} >> "$_tmp"
	mv "$_tmp" "$_custom"
	chmod 755 "$_custom"
	info "entry appended to $_custom"
}

bl_finish() {
	run "$GRUB_MKCONFIG" -o "$ROOT/boot/grub/grub.cfg"
}

bl_verify() {
	if [ "$DRYRUN" = 1 ]; then
		info "dry-run: boot menu not regenerated"
		return 0
	fi
	n=$(grep -c "menuentry 'Godel (test)'" "$ROOT/boot/grub/grub.cfg" || true)
	[ "$n" = 1 ] ||
		die "expected exactly 1 'Godel (test)' entry in grub.cfg, found ${n:-0}"
	info "verified: 1 'Godel (test)' entry in grub.cfg"
}
