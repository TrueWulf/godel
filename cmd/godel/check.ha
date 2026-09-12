use fs;
use godel;
use os;
use strings;

let pathbuf_a: [256]u8 = [0...];
let pathbuf_b: [256]u8 = [0...];

fn mkpath(buf: *[256]u8, a: str, b: str) (void | str) = {
	const ab = strings::toutf8(a);
	const bb = strings::toutf8(b);
	if (len(ab) + len(bb) >= len(buf)) return;
	buf[..len(ab)] = ab;
	buf[len(ab)..len(ab) + len(bb)] = bb;
	const n = len(ab) + len(bb);
	return strings::fromutf8_unsafe(buf[..n]);
};

fn validate_path(path: str) never = {
	const st = match (os::stat(path)) {
	case let st: fs::filestat => yield st;
	case let e: fs::error =>
		logf("godel: -t {}: {}\n", path, fs::strerror(e));
		os::exit(2);
	};
	const isdir = fs::isdir(st.mode);
	let filepath: (void | str) = void;
	let scandir: (void | str) = void;
	if (isdir) {
		filepath = mkpath(&pathbuf_a, path, "/services.conf");
		const d = mkpath(&pathbuf_b, path, "/services.d");
		let has_d = false;
		match (d) {
		case void => void;
		case let dp: str =>
			match (os::stat(dp)) {
			case let sd: fs::filestat => has_d = fs::isdir(sd.mode);
			case => void;
			};
		};
		scandir = if (has_d) d else path;
	} else {
		filepath = path;
	};
	const next = active_set ^ 1;
	match (load_from(next, filepath, scandir)) {
	case void =>
		logf("godel: {}: OK, {} service(s)\n", path, sets[next].count: i64);
		os::exit(0);
	case let d: godel::diag =>
		logf("godel: {}:{}: {}\n", src_path(d.file), d.line, d.msg);
		os::exit(1);
	};
};
