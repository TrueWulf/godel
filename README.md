<h1 align="center"><img src="assets/godel-wordmark.png" alt="godel" width="330"></h1>

godel is a Linux init and service supervisor written in Hare. One static
binary, no libc, runs as PID 1. Dependency ordering, restart policies,
readiness gating, per-service logs, clean shutdown. No allocation after
boot, ~380 KB stripped. A separate `godelctl` binary controls a running
supervisor.

I wanted an init I could read in one sitting, so I wrote one. It runs on
my machine (Void) as PID 1, daily. Linux only, prefers pidfds and
cgroup.kill, degrades without them.

## Build

Hare 0.26.0.1, Linux, make.

    make
    make test

## Config

`/etc/godel/services.conf` plus `/etc/godel/services.d/`. A directory
file holds one service named after the file. `godel -t PATH` checks a
config without starting anything.

    [service "ssh"]
    command = /usr/sbin/sshd -D
    after = network

Keys: command, after, restart, restart_limit, restart_delay,
shutdown_timeout, env, type, notification-fd, readiness_timeout, run-as,
log. Ready-made sets in examples/.

## Install

    make install-godel BOOTLOADER=grub

The installer detects the distro, generates the service set and adds a
separate 'godel (test)' boot entry. The default entry is never touched.
Bootloaders: grub, limine, extlinux, systemd-boot, refind.

## Status

1.0.0. This is what I run daily. No packaging yet. BSD-2-Clause. The
Hare standard library is MPL-2.0 on its own terms.
