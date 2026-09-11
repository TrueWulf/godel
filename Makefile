HARE ?= $(HOME)/tools/hare/bin/hare
PREFIX ?= /usr/local
DESTDIR ?=
export PATH := $(HOME)/tools/hare/bin:$(PATH)

GODEL_SRC := $(wildcard cmd/godel/*.ha godel/*.ha)
GODELCTL_SRC := $(wildcard cmd/godelctl/*.ha)
QEMU_SESSION_SRC := $(wildcard cmd/qemu-session/*.ha)

.PHONY: all test install image qemu-system qemu-reboot qemu-poweroff qemu-badconfig clean

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
