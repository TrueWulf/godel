use rt;

export def DEFAULT_LIMIT: size = 64 * 1024;

export type log = struct {
	fd: int,
	written: size,
	limit: size,
	path: [128]u8,
	path_len: size,
};

export fn open_file(l: *log, path: []u8) void = {
	if (len(path) >= len(l.path)) return;
	l.path[..len(path)] = path;
	l.path_len = len(path);
	match (rt::open(path,
			rt::O_WRONLY | rt::O_APPEND | rt::O_CREATE | rt::O_CLOEXEC,
			0o644)) {
	case let fd: int => l.fd = fd;
	case => void;
	};
};

fn rotate(l: *log) void = {
	close_fd(l.fd);
	l.fd = -1;
	if (l.path_len == 0 || l.path_len + 2 >= len(l.path)) return;
	let previous: [128]u8 = [0...];
	previous[..l.path_len] = l.path[..l.path_len];
	previous[l.path_len] = '.';
	previous[l.path_len + 1] = '1';
	let _ = rt::renameat(rt::AT_FDCWD, l.path[..l.path_len], rt::AT_FDCWD,
		previous[..l.path_len + 2], 0);
	open_file(l, l.path[..l.path_len]);
	l.written = 0;
};

export fn write_bytes(l: *log, data: []u8) void = {
	let _ = rt::write(2, &data[0]: *const opaque, len(data));
	if (l.fd < 0) return;
	if (l.written + len(data) > l.limit) {
		rotate(l);
		if (l.fd < 0) return;
	};
	match (rt::write(l.fd, &data[0]: *const opaque, len(data))) {
	case let n: size => l.written += n;
	case => void;
	};
};
