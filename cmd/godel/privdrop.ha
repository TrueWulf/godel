use bytes;
use fs;
use godel;
use io;
use os;
use rt;
use strings;

def PASSWD_FILE: str = "/etc/passwd";
def GROUP_FILE: str = "/etc/group";
def ID_BUF_MAX: size = 16 * 1024;

type ids = struct { uid: u32, gid: u32 };

fn digits_only(name: []u8) bool = {
	if (len(name) == 0) return false;
	for (let i = 0z; i < len(name); i += 1) {
		if (name[i] < '0' || name[i] > '9') return false;
	};
	return true;
};

fn parse_num(text: []u8) (void | u32) = {
	if (!digits_only(text)) return;
	let acc: u64 = 0;
	for (let i = 0z; i < len(text); i += 1) {
		if (acc > 429496729) return;
		acc = acc * 10 + (text[i] - '0'): u64;
	};
	if (acc > 4294967295) return;
	return acc: u32;
};

fn colon_fields(line: []u8, starts: *[8]size, lens: *[8]size) size = {
	let n: size = 0;
	let start: size = 0;
	for (let i = 0z; i <= len(line); i += 1) {
		if (i == len(line) || line[i] == ':') {
			if (n == 8) return 0;
			starts[n] = start;
			lens[n] = i - start;
			n += 1;
			start = i + 1;
			if (i == len(line)) break;
		};
	};
	return n;
};

fn scan_id_file(path: str, name: []u8, id_field: size) (void | u32) = {
	const f = match (os::open(path)) {
	case let f: io::file => yield f;
	case => return;
	};
	defer io::close(f)!;
	let buf: [ID_BUF_MAX]u8 = [0...];
	let used: size = 0;
	for (used < len(buf)) {
		match (io::read(f, buf[used..])) {
		case let n: size =>
			if (n == 0) break;
			used += n;
		case io::EOF => break;
		case => return;
		};
	};
	let pos: size = 0;
	for (pos < used) {
		let end = pos;
		for (end < used && buf[end] != '\n') end += 1;
		const line = buf[pos..end];
		pos = end + 1;
		let starts: [8]size = [0...];
		let lens: [8]size = [0...];
		const n = colon_fields(line, &starts, &lens);
		if (n < id_field + 1) continue;
		if (!bytes::equal(line[starts[0]..starts[0] + lens[0]], name)) continue;
		return parse_num(line[starts[id_field]..starts[id_field] + lens[id_field]]);
	};
};

fn apply_run_as(s: *const godel::set, cfg: *const godel::service) void = {
	if (cfg.runas_len == 0) return;
	const spec = godel::svc_runas(s, cfg);
	let colon: (void | size) = void;
	for (let i = 0z; i < len(spec); i += 1) {
		if (spec[i] == ':') {
			colon = i;
			break;
		};
	};
	const user = match (colon) {
	case void => yield spec;
	case let c: size => yield spec[..c];
	};
	let want: ids = ids { uid = 0, gid = 0 };
	if (digits_only(user)) {
		want.uid = parse_num(user) as u32;
		want.gid = want.uid;
	} else {
		match (scan_id_file(PASSWD_FILE, user, 2)) {
		case void =>
			logf("godel: {}: run-as: unknown user '{}'\n",
				nm(godel::svc_name(cfg)), nm(user));
			os::exit(126);
		case let id: u32 =>
			want.uid = id;
			want.gid = id;
		};
		match (scan_id_file(PASSWD_FILE, user, 3)) {
		case void => void;
		case let gid: u32 => want.gid = gid;
		};
	};
	match (colon) {
	case void => void;
	case let c: size =>
		const group = spec[c + 1..];
		if (digits_only(group)) {
			want.gid = parse_num(group) as u32;
		} else {
			match (scan_id_file(GROUP_FILE, group, 2)) {
			case void =>
				logf("godel: {}: run-as: unknown group '{}'\n",
					nm(godel::svc_name(cfg)), nm(group));
				os::exit(126);
			case let gid: u32 => want.gid = gid;
			};
		};
	};
	if (rt::setresgid(want.gid: uint, want.gid: uint, want.gid: uint) is rt::errno
			|| rt::setresuid(want.uid: uint, want.uid: uint, want.uid: uint) is rt::errno) {
		logf("godel: {}: run-as: cannot drop privileges\n",
			nm(godel::svc_name(cfg)));
		os::exit(126);
	};
};
