use fmt;
use io;
use os;
use rt;
use strings;
use time;

const NEWCONF: str = "[service \"worker\"]
command = /bin/worker -v --booted

[service \"smoke\"]
command = /bin/sh --smoke

[service \"extra\"]
command = /bin/worker -v --extra
";

export fn main() void = {
	fmt::println("Godel QEMU smoke test: reloadtest running")!;
	time::sleep(1 * time::SECOND);
	match (os::create("/etc/godel/services.conf", 0o644)) {
	case let f: io::file =>
		defer io::close(f)!;
		io::writeall(f, strings::toutf8(NEWCONF))!;
	case => return;
	};
	fmt::println("Godel QEMU smoke test: sending SIGHUP to init")!;
	let _ = rt::kill(rt::getppid(), rt::SIGHUP);
	time::sleep(5 * time::SECOND);
};
