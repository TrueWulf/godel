HARE ?= $(HOME)/tools/hare/bin/hare
PREFIX ?= /usr/local
DESTDIR ?=
export PATH := $(HOME)/tools/hare/bin:$(PATH)

GODEL_SRC := $(wildcard cmd/godel/*.ha godel/*.ha)
GODELCTL_SRC := $(wildcard cmd/godelctl/*.ha)
GODEL_INSTALL_SRC := $(wildcard cmd/godel-install/*.ha)

.PHONY: all test install install-godel install-artix-grub clean

all: bin/godel bin/godelctl bin/godel-install

bin/godel: $(GODEL_SRC)
	@mkdir -p bin
	$(HARE) build -o bin/godel ./cmd/godel

bin/godelctl: $(GODELCTL_SRC)
	@mkdir -p bin
	$(HARE) build -o bin/godelctl ./cmd/godelctl

bin/godel-install: $(GODEL_INSTALL_SRC)
	@mkdir -p bin
	$(HARE) build -o bin/godel-install ./cmd/godel-install

test:
	$(HARE) test ./godel

install: bin/godel bin/godelctl
	install -Dm755 bin/godel $(DESTDIR)$(PREFIX)/sbin/godel
	install -Dm755 bin/godelctl $(DESTDIR)$(PREFIX)/bin/godelctl

# One-command install: builds, detects distro and bootloader, generates the
# desktop-base service set, and adds a separate 'godel (test)' boot entry;
# the default entry is not touched.
# Run as root:  doas make install-godel BOOTLOADER=grub   (add DRYRUN:
# bin/godel-install --dry-run directly).
install-godel: all
	test -n "$(BOOTLOADER)" || { echo "set BOOTLOADER=grub|limine|extlinux|systemd-boot|refind" >&2; exit 2; }
	bin/godel-install --bootloader "$(BOOTLOADER)"

install-artix-grub: all
	bin/godel-install --bootloader grub

clean:
	rm -rf bin
