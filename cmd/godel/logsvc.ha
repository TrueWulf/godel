use fs;
use godel;
use os;
use rt;
use strings;

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
			0o644)) {
	case let fd: int => return fd;
	case => return -1;
	};
};

fn open_service_log(cfg: *const godel::service) void = {
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
