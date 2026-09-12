use rt;
use time;

export def TAG_SIGNAL: u64 = 0xffff_ffff;
export def TAG_TIMER: u64 = 0xffff_fffe;
export def TAG_RESCUE: u64 = 0xffff_fffd;
export def TAG_CTL: u64 = 0xffff_fffc;
export def TAG_DYING_BASE: u64 = 0x100;
export def TAG_NOTIFY_BASE: u64 = 0x200;

export fn now_ms() i64 = {
	let ts = rt::timespec { tv_sec = 0, tv_nsec = 0 };
	let _ = rt::clock_gettime(time::clock::MONOTONIC: int, &ts);
	return ts.tv_sec * 1000 + ts.tv_nsec / 1_000_000;
};

export fn close_fd(fd: int) void = {
	if (fd >= 0) {
		let _ = rt::close(fd);
	};
};

export type epoll = struct { fd: int };

export fn epoll_create(ep: *epoll) (void | rt::errno) = {
	match (rt::epoll_create1(0)) {
	case let fd: int =>
		ep.fd = fd;
		return;
	case let e: rt::errno => return e;
	};
};

fn epoll_ctl(ep: *epoll, op: int, fd: int, data: u64) (void | rt::errno) = {
	let ev = rt::epoll_event {
		events = rt::EPOLLIN,
		data = rt::epoll_data { u64_ = data },
	};
	match (rt::epoll_ctl(ep.fd, op, fd, &ev)) {
	case void => return;
	case let e: rt::errno => return e;
	};
};

export fn epoll_add(ep: *epoll, fd: int, data: u64) (void | rt::errno) =
	epoll_ctl(ep, rt::EPOLL_CTL_ADD, fd, data);

export fn epoll_modify(ep: *epoll, fd: int, data: u64) (void | rt::errno) =
	epoll_ctl(ep, rt::EPOLL_CTL_MOD, fd, data);

export fn epoll_remove(ep: *epoll, fd: int) void = {
	let _ = rt::epoll_ctl(ep.fd, rt::EPOLL_CTL_DEL, fd, null);
};

export fn epoll_wait_events(ep: *epoll, events: []rt::epoll_event) size = {
	for (true) {
		match (rt::epoll_wait(ep.fd, &events[0], len(events): int, -1)) {
		case let n: int =>
			if (n > 0) return n: size;
			return 0;
		case let e: rt::errno =>
			if (e == rt::EINTR) continue;
			return 0;
		};
	};
};

export fn signal_mask() rt::sigset = {
	let set = rt::sigset { __val = [0] };
	rt::sigemptyset(&set);
	let _ = rt::sigaddset(&set, rt::SIGTERM);
	let _ = rt::sigaddset(&set, rt::SIGINT);
	let _ = rt::sigaddset(&set, rt::SIGUSR1);
	let _ = rt::sigaddset(&set, rt::SIGHUP);
	let _ = rt::sigaddset(&set, rt::SIGCHLD);
	return set;
};

export fn block_signals(mask: *rt::sigset) void = {
	let old = rt::sigset { __val = [0] };
	rt::sigprocmask(rt::SIG_BLOCK, mask, &old)!;
};

export fn new_signalfd(mask: *rt::sigset) int = {
	match (rt::signalfd(-1, mask, rt::SFD_NONBLOCK | rt::SFD_CLOEXEC)) {
	case let fd: int => return fd;
	case => return -1;
	};
};

export fn read_signal(fd: int) (void | u8) = {
	let si = rt::signalfd_siginfo { ... };
	match (rt::read(fd, &si: *opaque, size(rt::signalfd_siginfo))) {
	case let n: size =>
		if (n == size(rt::signalfd_siginfo)) return si.ssi_signo: u8;
		return;
	case => return;
	};
};

export type timer = struct { fd: int };

export fn timer_create(t: *timer) (void | rt::errno) = {
	match (rt::timerfd_create(time::clock::MONOTONIC: int,
			rt::TFD_NONBLOCK | rt::TFD_CLOEXEC)) {
	case let fd: int =>
		t.fd = fd;
		return;
	case let e: rt::errno => return e;
	};
};

export fn timer_set_abs(t: *timer, abs_ms: i64) void = {
	let its = rt::itimerspec {
		it_interval = rt::timespec { tv_sec = 0, tv_nsec = 0 },
		it_value = rt::timespec {
			tv_sec = abs_ms / 1000,
			tv_nsec = (abs_ms % 1000) * 1_000_000,
		},
	};
	let _ = rt::timerfd_settime(t.fd, 1, &its, null);
};

export fn timer_disable(t: *timer) void = timer_set_abs(t, 0);

export fn timer_read_tick(t: *timer) bool = {
	let ticks: u64 = 0;
	match (rt::read(t.fd, &ticks: *opaque, 8)) {
	case let n: size => return n == 8 && ticks > 0;
	case => return false;
	};
};

export fn pidfd_open(pid: int) (void | int) = {
	match (rt::pidfd_open(pid, 0)) {
	case let fd: int => return fd;
	case => return;
	};
};

export fn wait_pid_nohang(pid: int) (void | u32) = {
	let st: int = 0;
	for (true) {
		match (rt::wait4(pid, &st, rt::WNOHANG, null)) {
		case let child: rt::pid_t =>
			if (child == 0) return;
			return st: u32;
		case let e: rt::errno =>
			if (e == rt::EINTR) continue;
			return;
		};
	};
};

export fn wait_any_nohang() (void | (int, u32)) = {
	let st: int = 0;
	for (true) {
		match (rt::wait4(-1, &st, rt::WNOHANG, null)) {
		case let child: rt::pid_t =>
			if (child == 0) return;
			return (child, st: u32);
		case let e: rt::errno =>
			if (e == rt::EINTR) continue;
			return;
		};
	};
};

export fn kill_process_group(pgid: int, sig: int) void = {
	if (pgid > 0) {
		let _ = rt::kill(-pgid, sig);
	};
};
