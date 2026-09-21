HARE ?= $(HOME)/tools/hare/bin/hare
PREFIX ?= /usr/local
DESTDIR ?=
export PATH := $(HOME)/tools/hare/bin:$(PATH)

GODEL_SRC := $(wildcard cmd/godel/*.ha godel/*.ha)
GODELCTL_SRC := $(wildcard cmd/godelctl/*.ha)
QEMU_SESSION_SRC := $(wildcard cmd/qemu-session/*.ha)

.PHONY: all test install install-godel install-artix-grub image qemu-system qemu-reboot qemu-poweroff qemu-badconfig clean

all: bin/godel bin/godelctl bin/qemu-session

bin/godel: $(GODEL_SRC)
	@mkdir -p bin
	$(HARE) build -o bin/godel ./cmd/godel

bin/godelctl: $(GODELCTL_SRC)
	@mkdir -p bin
	$(HARE) build -o bin/godelctl ./cmd/godelctl

bin/qemu-session: $(QEMU_SESSION_SRC)
	@mkdir -p bin
	$(HARE) build -o bin/qemu-session ./cmd/qemu-session

test:
	$(HARE) test ./godel

install: bin/godel bin/godelctl
	install -Dm755 bin/godel $(DESTDIR)$(PREFIX)/sbin/godel
	install -Dm755 bin/godelctl $(DESTDIR)$(PREFIX)/bin/godelctl
	install -Dm644 man/godel.8 $(DESTDIR)$(PREFIX)/share/man/man8/godel.8
	install -Dm644 man/godelctl.8 $(DESTDIR)$(PREFIX)/share/man/man8/godelctl.8

# One-command install for Artix/Arch-family machines with GRUB:
# builds, installs, generates the desktop-base service set, and adds a
# separate 'Godel (test)' boot entry; the default entry is not touched.
# Run as root:  doas make install-artix-grub   (add DRYRUN: --dry-run via
# sh tools/install.sh directly).
install-godel: all
	test -n "$(BOOTLOADER)" || { echo "set BOOTLOADER=grub|limine|extlinux|systemd-boot|refind" >&2; exit 2; }
	sh tools/install.sh --bootloader "$(BOOTLOADER)"

install-artix-grub: all
	sh tools/install.sh --bootloader grub

image: bin/godel bin/godelctl
	tools/build-image.sh

qemu-system: image
	tools/run-system.sh

qemu-reboot: all
	tools/run-qemu.sh reboot

qemu-poweroff: all
	tools/run-qemu.sh poweroff

qemu-badconfig: all
	tools/run-qemu.sh badconfig

clean:
	rm -rf bin .qemu
