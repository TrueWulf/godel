use fmt;
use fs;
use io;
use os;
use rt;
use strings;

const USAGE: str =
	"usage: godelctl status|list|start <service>|stop <service>|catlog <service>|reload|reboot|poweroff";

fn bytes_eq(a: []u8, b: []u8) bool = {
	if (len(a) != len(b)) return false;
	for (let i = 0z; i < len(a); i += 1) {
		if (a[i] != b[i]) return false;
	};
	return true;
};

fn running_under_godel() bool = match (os::stat("/run/godel/status")) {
case let st: fs::filestat => yield fs::isfile(st.mode);
case => yield false;
};

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

fn known_service(name: str) bool = {
	if (len(name) == 0 || len(name) > 31) return false;
	const f = match (os::open("/run/godel/status")) {
	case let f: io::file => yield f;
	case => return false;
	};
	defer io::close(f)!;
	let buf: [8192]u8 = [0...];
	let used: size = 0;
	for (used < len(buf)) {
		match (io::read(f, buf[used..])) {
		case let n: size =>
			if (n == 0) break;
			used += n;
		case => break;
		};
	};
	let pos: size = 0;
	for (pos < used) {
		let end = pos;
		for (end < used && buf[end] != '\n') end += 1;
		let tab = pos;
		for (tab < end && buf[tab] != '\t') tab += 1;
		if (tab > pos && bytes_eq(buf[pos..tab], strings::toutf8(name))) {
			return true;
		};
		pos = end + 1;
	};
	return false;
};

fn ctl_write(verb: str, name: str) int = {
	const f = match (os::open("/run/godel/ctl", fs::flag::WRONLY)) {
	case let f: io::file => yield f;
	case =>
		fmt::errorln("godelctl: cannot open /run/godel/ctl")!;
		return 1;
	};
	defer io::close(f)!;
	let buf: [48]u8 = [0...];
	const line = fmt::bsprintf(buf, "{} {}\n", verb, name)!;
	match (io::write(f, strings::toutf8(line))) {
	case size => void;
	case =>
		fmt::errorln("godelctl: write failed")!;
		return 1;
	};
	fmt::errorfln("{}: {} requested", name, verb)!;
	return 0;
};

fn print_log(name: str) int = {
	let path: [64]u8 = [0...];
	const p = fmt::bsprintf(path, "/var/log/godel/{}.log", name)!;
	const f = match (os::open(p)) {
	case let f: io::file => yield f;
	case =>
		fmt::errorfln("godelctl: no log for {}", name)!;
		return 1;
	};
	defer io::close(f)!;
	match (io::copy(os::stdout, f)) {
	case size => void;
	case => return 1;
	};
	return 0;
};

export fn main() void = {
	const args = os::args;
	if (len(args) == 2 && (args[1] == "status" || args[1] == "list")) {
		os::exit(print_status());
	};
	if (len(args) == 3 && args[1] == "catlog") {
		if (!running_under_godel()) {
			fmt::errorln("godelctl: Godel is not running")!;
			os::exit(1);
		};
		if (!known_service(args[2])) {
			fmt::errorfln("godelctl: unknown service {}", args[2])!;
			os::exit(1);
		};
		os::exit(print_log(args[2]));
	};
	if (len(args) == 3 && (args[1] == "start" || args[1] == "stop")) {
		if (!running_under_godel()) {
			fmt::errorln("godelctl: Godel is not running (no /run/godel/status); refusing to signal PID 1")!;
			os::exit(1);
		};
		if (!known_service(args[2])) {
			fmt::errorfln("godelctl: unknown service {}", args[2])!;
			os::exit(1);
		};
		os::exit(ctl_write(args[1], args[2]));
	};
	if (len(args) != 2) {
		fmt::errorln(USAGE)!;
		os::exit(1);
	};
	if (!running_under_godel()) {
		fmt::errorln("godelctl: Godel is not running (no /run/godel/status); refusing to signal PID 1")!;
		os::exit(1);
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
