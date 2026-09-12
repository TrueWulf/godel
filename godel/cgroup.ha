use fmt;
use rt;
use time;
use strings;

export def MAX_PATH: size = 128;

export type controller = struct {
	enabled: bool,
	accounting: bool,
	root: [MAX_PATH]u8,
	root_len: size,
};

fn write_at(dir: []u8, file: str, content: []u8) bool = {
	const dlen = len(dir);
	const flen = len(strings::toutf8(file));
	if (dlen + 1 + flen >= MAX_PATH) return false;
	let path: [MAX_PATH]u8 = [0...];
	path[..dlen] = dir;
	path[dlen] = '/';
	path[dlen + 1..dlen + 1 + flen] = strings::toutf8(file);
	match (rt::open(path[..dlen + 1 + flen],
			rt::O_WRONLY | rt::O_NOFOLLOW | rt::O_CLOEXEC, 0)) {
	case let fd: int =>
		const ok = match (rt::write(fd, &content[0]: *const opaque, len(content))) {
		case let n: size => yield n == len(content);
		case => yield false;
		};
		let _ = rt::close(fd);
		return ok;
	case => return false;
	};
};

fn write_root_file(c: *const controller, file: str, content: []u8) bool = {
	if (!c.enabled) return false;
	return write_at(c.root[..c.root_len], file, content);
};

export fn setup(base: []u8) controller = {
	let self = controller { enabled = false, ... };
	if (len(base) == 0 || len(base) + 6 >= MAX_PATH) return self;
	self.root[..len(base)] = base;
	self.root[len(base)] = '/';
	self.root[len(base) + 1..len(base) + 6] = strings::toutf8("godel");
	self.root_len = len(base) + 6;
	match (rt::mkdir(self.root[..self.root_len], 0o755)) {
	case void => self.enabled = true;
	case let e: rt::errno =>
		if (e == rt::EEXIST) {
			self.enabled = true;
		};
	};
	if (self.enabled) {
		// Controllers only become available to a cgroup once they are
		// enabled in its parent's subtree_control, so the hierarchy root
		// must be enabled first; the supervisor level then passes them on
		// to the per-service groups.
		self.accounting = write_at(base, "cgroup.subtree_control",
			strings::toutf8("+memory"));
		write_root_file(&self, "cgroup.subtree_control",
			strings::toutf8("+memory"));
		write_at(base, "cgroup.subtree_control", strings::toutf8("+pids"));
		write_root_file(&self, "cgroup.subtree_control",
			strings::toutf8("+pids"));
	};
	return self;
};

fn service_dir(c: *const controller, name: []u8, out: *[MAX_PATH]u8) (void | []u8) = {
	if (!c.enabled) return;
	if (c.root_len + 1 + len(name) >= MAX_PATH) return;
	out[..c.root_len] = c.root[..c.root_len];
	out[c.root_len] = '/';
	out[c.root_len + 1..c.root_len + 1 + len(name)] = name;
	const total = c.root_len + 1 + len(name);
	return out[..total];
};

fn write_file_in(c: *const controller, name: []u8, file: str, content: []u8) bool = {
	let path: [MAX_PATH]u8 = [0...];
	const dir = match (service_dir(c, name, &path)) {
	case void => return false;
	case let d: []u8 => yield d;
	};
	return write_at(dir, file, content);
};

export fn attach(c: *const controller, name: []u8, pid: int) bool = {
	let path: [MAX_PATH]u8 = [0...];
	const dir = match (service_dir(c, name, &path)) {
	case void => return false;
	case let d: []u8 => yield d;
	};
	match (rt::mkdir(dir, 0o755)) {
	case void => void;
	case let e: rt::errno =>
		if (e != rt::EEXIST) return false;
	};
	let pidbuf: [16]u8 = [0...];
	const pidstr = fmt::bsprintf(pidbuf, "{}\n", pid)!;
	return write_file_in(c, name, "cgroup.procs", strings::toutf8(pidstr));
};

export fn kill_tree(c: *const controller, name: []u8) bool =
	write_file_in(c, name, "cgroup.kill", strings::toutf8("1"));

export fn release(c: *const controller, name: []u8) void = {
	let path: [MAX_PATH]u8 = [0...];
	const dir = match (service_dir(c, name, &path)) {
	case void => return;
	case let d: []u8 => yield d;
	};
	for (let attempt = 0; attempt < 10; attempt += 1) {
		match (rt::unlinkat(rt::AT_FDCWD, dir, rt::AT_REMOVEDIR)) {
		case void => return;
		case let e: rt::errno =>
			if (e == rt::ENOENT) return;
			time::sleep(1 * time::MILLISECOND);
		};
	};
};
