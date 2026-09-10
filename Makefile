HARE ?= $(HOME)/tools/hare/bin/hare
PREFIX ?= /usr/local
DESTDIR ?=
export PATH := $(HOME)/tools/hare/bin:$(PATH)

.PHONY: all test install qemu-reboot qemu-poweroff qemu-badconfig clean

all: bin/godel

bin/godel:
	@mkdir -p bin
	$(HARE) build -o bin/godel ./cmd/godel

test:
	$(HARE) test ./godel

install: bin/godel
	install -Dm755 bin/godel $(DESTDIR)$(PREFIX)/sbin/godel

qemu-reboot: all
	tools/run-qemu.sh reboot

qemu-poweroff: all
	tools/run-qemu.sh poweroff

qemu-badconfig: all
	tools/run-qemu.sh badconfig

clean:
	rm -rf bin .qemu
