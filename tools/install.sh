#!/bin/sh
# Godel one-command installer driver: flags -> Hare core -> bootloader plugin.
#
# Safety model (non-negotiable):
#   - the running/default boot entry is never modified;
#   - a separate "Godel (test)" entry is added instead;
#   - everything the installer touches is backed up under /etc/godel/backups;
#   - the generated service set is validated with `godel -t` BEFORE any
#     boot configuration changes;
#   - unsupported bootloaders are refused, not guessed.
#
# The detection, capability discovery, service generation, and staging
# phases live in bin/godel-install (cmd/godel-install). This driver only
# parses flags and drives the bl_* bootloader plugin contract:
#   bl_detect, bl_backup STAMP, bl_add_entry K I R, bl_finish, bl_verify
# Globals provided to the backend: ROOT, DRYRUN, run(), die(), info().
#
# Usage:
#   doas sh tools/install.sh --bootloader grub [--dry-run] [--force]
#
# Environment (test/fixture mode):
#   ROOT=DIR        operate on a fixture tree instead of / (implies non-root ok)
#   CMDLINE_FILE=F  read kernel args here instead of /proc/cmdline
#   KERNEL=PATH     override detected kernel path
#   ROOTARG=SPEC    override detected root= kernel argument
#   ROOTDEV=DEV     override detected root device (for fsck-root)
#   ROOTFSTYPE=FS   override detected root filesystem type
#   GRUB_MKCONFIG=C override grub-mkconfig binary (backend hook for tests)

set -eu

: "${ROOT:=}"
: "${CMDLINE_FILE:=/proc/cmdline}"
: "${KERNEL:=}"
: "${ROOTARG:=}"
: "${ROOTDEV:=}"
: "${ROOTFSTYPE:=}"
BOOTLOADER=
DRYRUN=
FORCE=

usage() {
	echo "usage: sh tools/install.sh --bootloader grub [--dry-run] [--force]" >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case $1 in
	--bootloader)
		[ $# -ge 2 ] || usage
		BOOTLOADER=$2
		shift 2
		;;
	--dry-run) DRYRUN=1; shift ;;
	--force) FORCE=1; shift ;;
	*) usage ;;
	esac
done

[ -n "$BOOTLOADER" ] || usage

die() { echo "install: $*" >&2; exit 1; }
info() { echo "install: $*"; }
run() {
	if [ "$DRYRUN" = 1 ]; then
		echo "  [dry-run] $*"
	else
		"$@"
	fi
}

[ -n "$ROOT" ] || [ "$(id -u)" = 0 ] ||
	die "must run as root (or set ROOT=<fixture> for a test run)"

test -x bin/godel || die "bin/godel missing; run make first"
test -x bin/godelctl || die "bin/godelctl missing; run make first"
test -x bin/godel-install || die "bin/godel-install missing; run make first"

stamp=$(date +%Y%m%d-%H%M%S).$$
state=$(mktemp)
trap 'rm -f "$state"' EXIT

# --- core: detect, discover, generate, stage, validate, commit ---------------
GODEL_DRYRUN=$DRYRUN GODEL_FORCE=$FORCE GODEL_STAMP=$stamp GODEL_STATE="$state" \
	bin/godel-install

# --- bootloader: POSIX plugin behind the bl_* contract -----------------------
# shellcheck disable=SC1090
. "$state"

backend=tools/bootloaders/$BOOTLOADER.sh
test -f "$backend" ||
	die "unknown bootloader '$BOOTLOADER' (available: grub, limine, extlinux, systemd-boot, refind)"
# shellcheck disable=SC1090
. "$backend"

bl_detect || die "bootloader '$BOOTLOADER' not detected; refusing to guess"
bl_backup "$STAMP"
bl_add_entry "$KERNEL" "$INITRD" "$ROOTARG"
bl_finish
bl_verify
