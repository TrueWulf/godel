// godelctl drives a running Godel PID 1 over its documented control
// interface: signals to process 1 plus the /run/godel/status snapshot.
// The interface is stable; the transport may change after 1.0.
use fmt;
use fs;
use io;
use os;
use rt;

const USAGE: str = "usage: godelctl status|reload|reboot|poweroff";

fn signal_for(command: str) (void | int) = switch (command) {
case "reload" => yield rt::SIGHUP;
case "reboot" => yield rt::SIGUSR1;
case "poweroff" => yield rt::SIGTERM;
case => yield;
};

fn print_status() int = {
	const f = match (os::open("/run/godel/status")) {
	case let f: io::file => yield f;
	case let e: fs::error =>
		fmt::errorfln("godelctl: cannot read /run/godel/status: {}",
			fs::strerror(e))!;
		return 1;
	};
	defer io::close(f)!;
	match (io::copy(os::stdout, f)) {
	case size => void;
	case let e: io::error =>
		fmt::errorfln("godelctl: read failed: {}", io::strerror(e))!;
		return 1;
	};
	return 0;
};

export fn main() void = {
	const args = os::args;
	if (len(args) != 2) {
		fmt::errorln(USAGE)!;
		os::exit(1);
	};
	if (args[1] == "status") {
		os::exit(print_status());
	};
	const sig = match (signal_for(args[1])) {
	case void =>
		fmt::errorln(USAGE)!;
		os::exit(1);
	case let s: int => yield s;
	};
	match (rt::kill(1, sig)) {
	case void => os::exit(0);
	case let e: rt::errno =>
		fmt::errorfln("godelctl: cannot signal PID 1 ({}): {}",
			args[1], rt::strerror(e))!;
		os::exit(1);
	};
};
