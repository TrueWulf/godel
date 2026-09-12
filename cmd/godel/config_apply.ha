use bytes;
use errors;
use fs;
use godel;
use io;
use os;
use rt;
use strings;

def CONF_ROOT: str = "/etc/godel";
def CONF_FILE: str = "/etc/godel/services.conf";
def CONF_DIR: str = "/etc/godel/services.d";
def SRC_NAME_MAX: size = 256;
def STEM_MAX: size = 63;

let src_names: [godel::MAX_FILES][SRC_NAME_MAX]u8 = [[0...]...];
let src_lens: [godel::MAX_FILES]u8 = [0...];
let src_count: size = 0;

type dir_name = struct {
	buf: [STEM_MAX + 1]u8,
	nlen: u8,
};

let dir_names: [godel::MAX_SERVICES]dir_name = [dir_name { ... }...];
let dir_count: size = 0;
let fullbuf: [SRC_NAME_MAX]u8 = [0...];

fn src_path(i: size) str = nm(src_names[i][..src_lens[i]: size]);

fn record_source(path: []u8) (void | godel::diag) = {
	if (src_count == godel::MAX_FILES) {
		return godel::diag {
			file = 0,
			line = 1,
			msg = "too many config files",
		};
	};
	if (len(path) >= SRC_NAME_MAX) {
		return godel::diag {
			file = 0,
			line = 1,
			msg = "config path too long",
		};
	};
	src_names[src_count][..len(path)] = path;
	src_lens[src_count] = len(path): u8;
	src_count += 1;
};

fn join2(a: str, b: []u8) (void | []u8) = {
	const ab = strings::toutf8(a);
	if (len(ab) + 1 + len(b) >= SRC_NAME_MAX) return;
	fullbuf[..len(ab)] = ab;
	fullbuf[len(ab)] = '/';
	fullbuf[len(ab) + 1..len(ab) + 1 + len(b)] = b;
	const n = len(ab) + 1 + len(b);
	fullbuf[n] = 0;
	return fullbuf[..n];
};

fn read_file(path: str, buffer: []u8) (void | []u8) = {
	const f = match (os::open(path)) {
	case let f: io::file => yield f;
	case let e: fs::error =>
		match (e) {
		case errors::noentry => return;
		case =>
			logf("godel: open {}: {}\n", path, fs::strerror(e));
			return;
		};
	};
	defer io::close(f)!;
	let used: size = 0;
	for (used < len(buffer)) {
		match (io::read(f, buffer[used..])) {
		case let n: size =>
			if (n == 0) break;
			used += n;
		case io::EOF => break;
		case let e: io::error =>
			logf("godel: read {}: {}\n", path, io::strerror(e));
			return;
		};
	};
	return buffer[..used];
};

fn has_conf_suffix(name: []u8) bool = {
	if (len(name) < 6) return false;
	return bytes::equal(name[len(name) - 5..], strings::toutf8(".conf"));
};

fn name_lt(a: []u8, b: []u8) bool = {
	const n = if (len(a) < len(b)) len(a) else len(b);
	for (let i = 0z; i < n; i += 1) {
		if (a[i] != b[i]) return a[i] < b[i];
	};
	return len(a) < len(b);
};

fn scan_entries(dfd: int) (void | godel::diag) = {
	let dbuf: [4096]u8 = [0...];
	dir_count = 0;
	for (true) {
		const n = match (rt::getdents64(dfd, &dbuf[0], len(dbuf))) {
		case let n: size => yield n;
		case => return;
		};
		if (n == 0) break;
		let off: size = 0;
		for (off < n) {
			const de = &dbuf[off]: *rt::dirent64;
			const reclen = de.d_reclen: size;
			off += reclen;
			if (de.d_type != rt::DT_REG && de.d_type != rt::DT_UNKNOWN) {
				continue;
			};
			let nlen: size = 0;
			for (let i = 0z; i < reclen; i += 1) {
				if (de.d_name[i] == 0) break;
				nlen += 1;
			};
			const name = de.d_name[..nlen];
			if (!has_conf_suffix(name)) continue;
			if (nlen < 6 || nlen > STEM_MAX + 5) {
				return godel::diag {
					file = 0,
					line = 1,
					msg = "config file name length unsupported",
				};
			};
			if (dir_count == godel::MAX_SERVICES) {
				return godel::diag {
					file = 0,
					line = 1,
					msg = "too many config files in services.d",
				};
			};
			dir_names[dir_count].buf[..nlen] = name;
			dir_names[dir_count].nlen = nlen: u8;
			dir_count += 1;
		};
	};
	for (let i = 1z; i < dir_count; i += 1) {
		const key = dir_names[i];
		let j = i;
		for (j > 0 && name_lt(key.buf[..key.nlen: size],
				dir_names[j - 1].buf[..dir_names[j - 1].nlen: size])) {
			dir_names[j] = dir_names[j - 1];
			j -= 1;
		};
		dir_names[j] = key;
	};
};

fn load_dir_file(
	s: *godel::set,
	content: []u8,
	scan_path: str,
	idx: size,
) (void | godel::diag) = {
	const entry = &dir_names[idx];
	const stem = entry.buf[..(entry.nlen: size) - 5];
	const path = match (join2(scan_path, entry.buf[..entry.nlen: size])) {
	case void =>
		return godel::diag {
			file = 0,
			line = 1,
			msg = "config path too long",
		};
	case let p: []u8 => yield p;
	};
	const id = src_count: u8;
	match (record_source(path)) {
	case void => void;
	case let d: godel::diag => return d;
	};
	const c = match (read_file(strings::fromutf8_unsafe(path), content)) {
	case void =>
		return godel::diag {
			file = id,
			line = 1,
			msg = "config file unreadable",
		};
	case let c: []u8 => yield c;
	};
	const before = s.count;
	match (godel::parse_file(s, c, id)) {
	case void => void;
	case let d: godel::diag => return d;
	};
	if (s.count != before + 1) {
		const line: size = if (s.count > before) s.services[s.count - 1].line else 1;
		return godel::diag {
			file = id,
			line = line,
			msg = "file must define exactly one service",
		};
	};
	const svc = &s.services[s.count - 1];
	if (!bytes::equal(godel::svc_name(svc), stem)) {
		return godel::diag {
			file = id,
			line = svc.line,
			msg = "service name must match the file name",
		};
	};
};

fn load_from(
	next: size,
	file_path: (void | str),
	scan_path: (void | str),
) (void | godel::diag) = {
	let content: [godel::BUF_CAPACITY]u8 = [0...];
	const s = &sets[next];
	godel::reset_set(s);
	src_count = 0;
	match (file_path) {
	case void => void;
	case let p: str =>
		match (record_source(strings::toutf8(p))) {
		case void => void;
		case let d: godel::diag => return d;
		};
	};
	match (scan_path) {
	case void => void;
	case let p: str =>
		if (file_path is void) {
			match (record_source(strings::toutf8(p))) {
			case void => void;
			case let d: godel::diag => return d;
			};
		};
	};
	match (file_path) {
	case void => void;
	case let p: str =>
		const c = match (read_file(p, content)) {
		case void => void;
		case let c: []u8 =>
			match (godel::parse_file(s, c, 0)) {
			case void => void;
			case let d: godel::diag => return d;
			};
		};
	};
	match (scan_path) {
	case void => void;
	case let p: str => {
		const scanned = match (rt::open(p,
				rt::O_RDONLY | rt::O_DIRECTORY | rt::O_CLOEXEC, 0)) {
		case let fd: int => yield fd;
		case => yield -1;
		};
		if (scanned >= 0) {
			defer godel::close_fd(scanned);
			match (scan_entries(scanned)) {
			case void => void;
			case let d: godel::diag => return d;
			};
			for (let i = 0z; i < dir_count; i += 1) {
				match (load_dir_file(s, content, p, i)) {
				case void => void;
				case let d: godel::diag => return d;
				};
			};
		};
	};
	};
	return godel::finish_set(s);
};

fn load_and_apply() void = {
	const next = active_set ^ 1;
	match (load_from(next, CONF_FILE,
			CONF_DIR)) {
	case void => void;
	case let d: godel::diag =>
		logf("godel: {}:{}: {}; entering recovery\n",
			src_path(d.file), d.line, d.msg);
		enter_rescue();
		return;
	};
	report_warnings(next);
	apply_config(next);
};

fn report_warnings(set_index: size) void = {
	for (let i = 0z; i < sets[set_index].warning_count; i += 1) {
		const warning = &sets[set_index].warnings[i];
		logf("godel: {}:{}: warning: {}\n",
			src_path(warning.file), warning.line, warning.msg);
	};
};

fn apply_config(next: size) void = {
	const old = active_set;
	let match_idx: [godel::MAX_SERVICES]u8 = [godel::NO_INDEX...];
	let matched: [godel::MAX_SERVICES]bool = [false...];

	godel::match_running(&sets[next], &sets[old], svcs[..], &match_idx, &matched);
	for (let j = 0z; j < sets[old].count; j += 1) {
		if (!matched[j] && svcs[j].state == godel::state::up) stop_service(j);
	};
	for (let i = 0z; i < sets[next].count; i += 1) {
		const j = match_idx[i];
		if (j == godel::NO_INDEX) {
			svcs[i] = godel::new_runtime();
			notify_r[i] = -1;
			continue;
		};
		if (i == j) {
			svcs[i].restarts = 0;
			svcs[i].restart_at = 0;
			continue;
		};
		svcs[i] = svcs[j];
		svcs[i].restarts = 0;
		svcs[i].restart_at = 0;
		svcs[j] = godel::runtime { pidfd = -1, ... };
		notify_r[i] = notify_r[j];
		notify_r[j] = -1;
		if (svcs[i].pidfd >= 0) {
			let _ = godel::epoll_modify(&ep, svcs[i].pidfd, i: u64);
		};
	};
	for (let i = sets[next].count: size; i < godel::MAX_SERVICES; i += 1) {
		svcs[i] = godel::runtime { pidfd = -1, ... };
		notify_r[i] = -1;
	};
	for (let i = 0z; i < sets[next].count; i += 1) {
		const r = &svcs[i];
		r.pending = switch (r.state) {
		case godel::state::up, godel::state::backoff => yield false;
		case godel::state::stopped => yield !r.finished;
		case godel::state::gave_up => yield true;
		};
	};
	active_set = next;

	pump_starts();
	check_recovery();
	write_status();
};

fn pump_starts() void = {
	if (shutdown.active) return;
	let order: [godel::MAX_SERVICES]size = [0...];
	const total = godel::ready_starts(&sets[active_set], svcs[..], &order);
	for (let k = 0z; k < total; k += 1) {
		const index = order[k];
		if (!svcs[index].pending) continue;
		svcs[index].pending = false;
		start(index);
	};
};

fn reload() void = {
	logf("godel: reloading configuration\n");
	const next = active_set ^ 1;
	match (load_from(next, CONF_FILE,
			CONF_DIR)) {
	case void => void;
	case let d: godel::diag =>
		logf("godel: reload refused: {}:{}: {}\n",
			src_path(d.file), d.line, d.msg);
		return;
	};
	report_warnings(next);
	apply_config(next);
	recovery_used = false;
	logf("godel: configuration reloaded\n");
};
