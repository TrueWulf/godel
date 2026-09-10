use bytes;
use fmt;
use io;
use os;
use rt;
use strings;
use time;

export fn main() void = {
	fmt::println("Godel QEMU smoke test: /bin/sh started")!;
	let buffer: [4096]u8 = [0...];
	let cmdline: []u8 = strings::toutf8("reboot");
	match (os::open("/proc/cmdline")) {
	case let f: io::file =>
		defer io::close(f)!;
		let used: size = 0;
		for (used < len(buffer)) {
			match (io::read(f, buffer[used..])) {
			case let n: size =>
				if (n == 0) break;
				used += n;
			case io::EOF => break;
			case => break;
			};
		};
		if (used > 0) cmdline = buffer[..used];
	case => void;
	};
	const text = strings::fromutf8_unsafe(cmdline);
	const sig: int = if (strings::contains(text, "godel-test=poweroff")) {
		yield rt::SIGTERM;
	} else {
		yield rt::SIGUSR1;
	};
	fmt::println(if (sig == rt::SIGTERM) {
		yield "Godel QEMU smoke test: sending SIGTERM to init";
	} else {
		yield "Godel QEMU smoke test: sending SIGUSR1 to init";
	})!;
	time::sleep(2 * time::SECOND);
	let _ = rt::kill(rt::getppid(), sig);
	for (true) rt::syscall(rt::SYS_pause);
};
