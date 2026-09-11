HARE ?= $(HOME)/tools/hare/bin/hare
PREFIX ?= /usr/local
DESTDIR ?=
export PATH := $(HOME)/tools/hare/bin:$(PATH)

.PHONY: all test install image qemu-system qemu-reboot qemu-poweroff qemu-badconfig clean

all: bin/godel bin/godelctl

bin/godel:
	@mkdir -p bin
	$(HARE) build -o bin/godel ./cmd/godel

bin/godelctl:
	@mkdir -p bin
	$(HARE) build -o bin/godelctl ./cmd/godelctl

test:
	$(HARE) test ./godel

install: bin/godel bin/godelctl
	install -Dm755 bin/godel $(DESTDIR)$(PREFIX)/sbin/godel
	install -Dm755 bin/godelctl $(DESTDIR)$(PREFIX)/bin/godelctl

image:
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
