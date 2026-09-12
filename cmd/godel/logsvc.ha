use fmt;
use fs;
use godel;
use os;
use rt;
use strings;
use time;

def SERVICE_LOG_LIMIT: size = 64 * 1024;
def VAR_LOG_DIR: str = "/var/log/godel";
def RUN_LOG_DIR: str = "/run/godel/logs";

fn log_path(dir: str, name: []u8, out: *[160]u8) (void | []u8) = {
	const d = strings::toutf8(dir);
	if (len(d) + 1 + len(name) + 4 >= len(out)) return;
	out[..len(d)] = d;
	out[len(d)] = '/';
	out[len(d) + 1..len(d) + 1 + len(name)] = name;
	const n = len(d) + 1 + len(name);
	out[n..n + 4] = strings::toutf8(".log");
	return out[..n + 4];
};

fn rotate_if_large(path: []u8) void = {
	const st = match (os::stat(strings::fromutf8_unsafe(path))) {
	case let st: fs::filestat => yield st;
	case => return;
	};
	if (st.sz <= SERVICE_LOG_LIMIT) return;
	let previous: [160]u8 = [0...];
	if (len(path) + 2 >= len(previous)) return;
	previous[..len(path)] = path;
	previous[len(path)] = '.';
	previous[len(path) + 1] = '1';
	let _ = rt::renameat(rt::AT_FDCWD, path, rt::AT_FDCWD,
		previous[..len(path) + 2], 0);
};

fn wall_stamp(out: *[24]u8) str = {
	let ts = rt::timespec { tv_sec = 0, tv_nsec = 0 };
	let _ = rt::clock_gettime(time::clock::REALTIME: int, &ts);
	const secs = ts.tv_sec;
	const days = secs / 86400;
	const rem = secs % 86400;
	const hh = rem / 3600;
	const mi = (rem % 3600) / 60;
	const ss = rem % 60;
	const z = days + 719468;
	const era = z / 146097;
	const doe = z - era * 146097;
	const yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
	const y = yoe + era * 400;
	const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
	const mp = (5 * doy + 2) / 153;
	const d = doy - (153 * mp + 2) / 5 + 1;
	const m = if (mp < 10) mp + 3 else mp - 9;
	const yy = if (m <= 2) y + 1 else y;
	return fmt::bsprintf(out, "{:_04}-{:_02}-{:_02}T{:_02}:{:_02}:{:_02}Z",
		yy: i64, m: i64, d: i64, hh: i64, mi: i64, ss: i64)!;
};

fn write_log_header(fd: int, name: []u8) void = {
	let stamp: [24]u8 = [0...];
	const st = wall_stamp(&stamp);
	let line: [192]u8 = [0...];
	const text = fmt::bsprintf(line, "== godel: {} log opened {}\n",
		nm(name), st)!;
	const raw = strings::toutf8(text);
	let _ = rt::write(fd, &raw[0]: *const opaque, len(raw));
};

fn open_in(dir: str, name: []u8) int = {
	let _ = rt::mkdir(strings::toutf8(dir), 0o755);
	let path: [160]u8 = [0...];
	const pathb = match (log_path(dir, name, &path)) {
	case void => return -1;
	case let p: []u8 => yield p;
	};
	rotate_if_large(pathb);
	match (rt::open(pathb,
			rt::O_WRONLY | rt::O_APPEND | rt::O_CREATE | rt::O_CLOEXEC,
			0o600)) {
	case let fd: int =>
		write_log_header(fd, name);
		return fd;
	case => return -1;
	};
};

fn open_service_log(cfg: *const godel::service) void = {
	if (cfg.log_disabled) {
		child_log_fd = -1;
		return;
	};
	const name = godel::svc_name(cfg);
	child_log_fd = open_in(VAR_LOG_DIR, name);
	if (child_log_fd < 0) {
		child_log_fd = open_in(RUN_LOG_DIR, name);
	};
	if (child_log_fd < 0) {
		logf("godel: {}: no writable log location, using console\n",
			nm(name));
	};
};
