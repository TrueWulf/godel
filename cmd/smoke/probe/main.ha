use fmt;
use io;
use os;
use strings;
use time;

export fn main() void = {
	match (os::getenv("GODEL_SMOKE_ENV")) {
	case let value: str => fmt::printfln("GODEL_SMOKE_ENV={}", value)!;
	case void => void;
	};
	time::sleep(300 * time::MILLISECOND);
	const f = match (os::open("/proc/1/status")) {
	case let f: io::file => yield f;
	case => return;
	};
	defer io::close(f)!;
	let buf: [4096]u8 = [0...];
	let used: size = 0;
	for (used < len(buf)) {
		match (io::read(f, buf[used..])) {
		case let n: size =>
			if (n == 0) break;
			used += n;
		case io::EOF => break;
		case => break;
		};
	};
	const text = strings::fromutf8_unsafe(buf[..used]);
	const it = strings::tokenize(text, "\n");
	for (true) {
		const line = match (strings::next_token(&it)) {
		case done => break;
		case let s: str => yield s;
		};
		if (strings::contains(line, "VmRSS")) {
			fmt::println(line)!;
			break;
		};
	};
};
