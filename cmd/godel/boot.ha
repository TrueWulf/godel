use godel;
use os;
use rt;
use strings;

fn mount_one(source: str, target: str, fstype: *const u8, flags: u64,
		data: nullable *opaque) void = {
	match (rt::mount(source, target, fstype, flags, data)) {
	case void => void;
	case let e: rt::errno =>
		if (e != rt::EBUSY && e != rt::EEXIST && e != rt::ENOENT) {
			logf("godel: mount {} failed: {}\n", target, e: i64);
		};
	};
};

fn mount_pseudo_filesystems() void = {
	mount_one("proc", "/proc", &FS_PROC[0]: *const u8, 0, null);
	mount_one("sysfs", "/sys", &FS_SYSFS[0]: *const u8, 0, null);
	mount_one("devtmpfs", "/dev", &FS_DEVTMPFS[0]: *const u8, 0,
		&MODE_0755[0]: *opaque);
	let _ = rt::mkdir("/dev/pts", 0o755);
	mount_one("devpts", "/dev/pts", &FS_DEVPTS[0]: *const u8, 0,
		&DEVPTS_OPTS[0]: *opaque);
	let _ = rt::mkdir("/dev/shm", 0o1777);
	mount_one("shm", "/dev/shm", &FS_TMPFS[0]: *const u8, 0,
		&MODE_1777[0]: *opaque);
	mount_one("cgroup2", "/sys/fs/cgroup", &FS_CGROUP2[0]: *const u8, 0, null);
};

fn mount_runtime() void = {
	let _ = rt::mkdir("/run", 0o755);
	mount_one("run", "/run", &FS_TMPFS[0]: *const u8, 0,
		&MODE_0755[0]: *opaque);
	let _ = rt::mkdir("/run/godel", 0o755);
};

fn connect_console() void = {
	match (rt::open(CONSOLE_DEVICE, rt::O_RDWR, 0)) {
	case let fd: int =>
		let _ = rt::dup2(fd, 0);
		let _ = rt::dup2(fd, 1);
		let _ = rt::dup2(fd, 2);
		if (fd > 2) godel::close_fd(fd);
	case => void;
	};
};

fn run_child(s: *const godel::set, cfg: *const godel::service) never = {
	let _ = rt::setsid();
	godel::attach(&cg, godel::svc_name(cfg), rt::getpid());
	if (child_notify_w >= 0) {
		if (rt::dup2(child_notify_w, child_notify_no) < 0) {
			os::exit(126);
		};
	};
	if (child_log_fd >= 0) {
		if (rt::dup2(child_log_fd, 1) < 0 || rt::dup2(child_log_fd, 2) < 0) {
			os::exit(126);
		};
	};
	apply_run_as(s, cfg);
	let argv: [godel::MAX_ARGS + 1]nullable *const u8 = [null...];
	for (let i = 0z; i < cfg.argc: size; i += 1) {
		argv[i] = &s.buf[cfg.argv_off[i]: size]: *const u8;
	};
	let envbufs: [3][48]u8 = [[0...]...];
	let envp: [godel::MAX_ENV + 4]nullable *const u8 = [null...];
	let envc = setup_envp(envp[..], &envbufs);
	for (let i = 0z; i < cfg.envc: size; i += 1) {
		envp[envc] = &s.buf[cfg.env_off[i]: size]: *const u8;
		envc += 1;
	};
	const path = &s.buf[cfg.argv_off[0]: size]: *const u8;
	let _ = rt::execve(path, &argv: *[*]nullable *const u8,
		&envp: *[*]nullable *const u8);
	logf("godel: cannot execute {}\n", nm(godel::svc_arg(s, cfg, 0)));
	os::exit(127);
};
