use fmt;
use os;
use godel;
use rt;
use strings;

def VERSION: str = "0.6.0";
def SERVICES_CONF: str = "/etc/godel/services.conf";
def CONSOLE_DEVICE: str = "/dev/console";
def KILL_PHASE_MS: i64 = 1_000;
def SHUTDOWN_CAP_MS: i64 = 30_000;
def SHUTDOWN_POWEROFF: u64 = 0x4321fedc;
def SHUTDOWN_RESTART: u64 = 0x1234567;
def RB_MAGIC: u64 = 0xfee1dead;
def RB_CMD: u64 = 672274793;
def RB_ENABLE_CAD: u64 = 0x89abcdef;

type shutdown_action = enum u8 { poweroff, reboot };

let sets: [2]godel::set = [godel::set { ... }, godel::set { ... }];
let active_set: size = 0;
let svcs: [godel::MAX_SERVICES]godel::runtime =
	[godel::runtime { pidfd = -1, ... }...];

type dying_entry = struct {
	used: bool,
	pid: int,
	pidfd: int,
	had_cgroup: bool,
	name: [godel::MAX_NAME_LEN + 1]u8,
	name_len: u8,
};

let dying: [godel::MAX_SERVICES]dying_entry =
	[dying_entry { pidfd = -1, ... }...];

type shutdown_state = struct {
	active: bool,
	mode: shutdown_action,
	phase_kill: bool,
	deadline: i64,
};

let shutdown: shutdown_state = shutdown_state {
	active = false,
	mode = shutdown_action::poweroff,
	phase_kill = false,
	deadline = 0,
};

let rescue_pid: int = 0;
let rescue_pidfd: int = -1;
let recovery_active = false;
let recovery_used = false;

let ep: godel::epoll = godel::epoll { fd = -1 };
let tmr: godel::timer = godel::timer { fd = -1 };
let cg: godel::controller = godel::controller { ... };
let logger: godel::log = godel::log {
	fd = -1,
	written = 0,
	limit = godel::DEFAULT_LIMIT,
	path = [0...],
	path_len = 0,
};

const FS_PROC: [5]u8 = ['p', 'r', 'o', 'c', 0];
const FS_SYSFS: [6]u8 = ['s', 'y', 's', 'f', 's', 0];
const FS_DEVTMPFS: [9]u8 = ['d', 'e', 'v', 't', 'm', 'p', 'f', 's', 0];
const FS_TMPFS: [6]u8 = ['t', 'm', 'p', 'f', 's', 0];
const FS_CGROUP2: [8]u8 = ['c', 'g', 'r', 'o', 'u', 'p', '2', 0];
const MODE_0755: [10]u8 = ['m', 'o', 'd', 'e', '=', '0', '7', '5', '5', 0];
const RESCUE_CS: [8]u8 = ['/', 'b', 'i', 'n', '/', 's', 'h', 0];

fn logf(f: str, args: fmt::field...) void = {
	let buf: [512]u8 = [0...];
	const line = fmt::bsprintf(buf, f, args...)!;
	godel::write_bytes(&logger, strings::toutf8(line));
};

fn state_name(state: godel::state) str = switch (state) {
case godel::state::stopped => yield "stopped";
case godel::state::up => yield "up";
case godel::state::backoff => yield "backoff";
case godel::state::gave_up => yield "gave-up";
};

// This file is intentionally a snapshot, not an RPC protocol: it remains
// useful in a broken system and needs no daemon, socket, or allocation.
fn write_status() void = {
	let buffer: [4096]u8 = [0...];
	let used: size = 0;
	for (let i = 0z; i < sets[active_set].count; i += 1) {
		const svc = &sets[active_set].services[i];
		const line = fmt::bsprintf(buffer[used..], "{}\t{}\tpid={}\trestarts={}\n",
			nm(godel::svc_name(svc)), state_name(svcs[i].state),
			svcs[i].pid: i64, svcs[i].restarts)!;
		used += len(strings::toutf8(line));
	};
	match (rt::open("/run/godel/status",
			rt::O_WRONLY | rt::O_CREATE | rt::O_TRUNC | rt::O_CLOEXEC, 0o644)) {
	case let fd: int =>
		if (used > 0) {
			let _ = rt::write(fd, &buffer[0]: *const opaque, used);
		};
		let _ = rt::close(fd);
	case => void;
	};
};

fn nm(a: []u8) str = strings::fromutf8_unsafe(a);

fn mkcs(buf: []u8, s: str) *const u8 = {
	const b = strings::toutf8(s);
	buf[..len(b)] = b;
	buf[len(b)] = 0;
	return &buf[0]: *const u8;
};

fn setup_envp(envp: []nullable *const u8, envbufs: *[3][48]u8) size = {
	envp[0] = mkcs(&envbufs[0], "HOME=/root");
	envp[1] = mkcs(&envbufs[1], "PATH=/usr/sbin:/usr/bin:/sbin:/bin");
	envp[2] = mkcs(&envbufs[2], "TERM=linux");
	return 3;
};

export fn main() void = {
	if (rt::getpid() != 1) {
		os::exit(1);
	};
	mount_pseudo_filesystems();
	mount_runtime();
	connect_console();
	godel::open_file(&logger, strings::toutf8("/run/godel/godel.log"));
	logf("Godel {}: starting\n", VERSION);
	let _ = rt::syscall(rt::SYS_reboot, RB_MAGIC, RB_CMD, RB_ENABLE_CAD, 0);

	cg = godel::setup(strings::toutf8("/sys/fs/cgroup"));
	if (cg.enabled) {
		logf("godel: cgroup v2 enabled\n");
	} else {
		logf("godel: cgroup v2 unavailable, using process groups\n");
	};

	const mask = godel::signal_mask();
	godel::block_signals(&mask);
	const sfd = godel::new_signalfd(&mask);
	if (!(godel::epoll_create(&ep) is void)) ep.fd = -1;
	if (!(godel::timer_create(&tmr) is void)) tmr.fd = -1;
	if (sfd < 0 || ep.fd < 0 || tmr.fd < 0) os::exit(1);
	if (!(godel::epoll_add(&ep, sfd, godel::TAG_SIGNAL) is void)
			|| !(godel::epoll_add(&ep, tmr.fd, godel::TAG_TIMER) is void)) {
		os::exit(1);
	};

	const boot_ms = godel::now_ms();
	load_and_apply();
	logf("Godel: ready in {} ms; {} service(s) configured\n",
		godel::now_ms() - boot_ms, sets[active_set].count);

	let events: [20]rt::epoll_event =
		[rt::epoll_event { events = 0, data = rt::epoll_data { u64_ = 0 } }...];
	for (true) {
		arm_timer();
		const n = godel::epoll_wait_events(&ep, events[..]);
		for (let i = 0z; i < n; i += 1) {
			const data = events[i].data.u64_;
			if (data == godel::TAG_SIGNAL) {
				for (true) {
					match (godel::read_signal(sfd)) {
					case void => break;
					case let sig: u8 => handle_signal(sig);
					};
				};
			} else if (data == godel::TAG_TIMER) {
				let _ = godel::timer_read_tick(&tmr);
				on_timer();
			} else if (data == godel::TAG_RESCUE) {
				on_rescue_death();
			} else if (data < godel::MAX_SERVICES: u64) {
				on_service_death(data: size);
			} else if (data >= godel::TAG_DYING_BASE
					&& data < godel::TAG_DYING_BASE
						+ godel::MAX_SERVICES: u64) {
				on_dying_death((data - godel::TAG_DYING_BASE): size);
			};
		};
	};
};


fn start(index: size) void = {
	const cfg = &sets[active_set].services[index];
	const rtst = &svcs[index];
	const pid = match (rt::fork()) {
	case let p: rt::pid_t => yield p;
	case let e: rt::errno =>
		logf("godel: cannot start {}: fork failed\n", nm(godel::svc_name(cfg)));
		rtst.state = godel::state::gave_up;
		write_status();
		check_recovery();
		return;
	case void => run_child(&sets[active_set], cfg);
	};
	rtst.pid = pid;
	rtst.state = godel::state::up;
	rtst.started_at = godel::now_ms();
	match (godel::pidfd_open(pid)) {
		case let pfd: int =>
			rtst.pidfd = pfd;
			if (!(godel::epoll_add(&ep, pfd, index: u64) is void)) {
				godel::close_fd(pfd);
				rtst.pidfd = -1;
				logf("godel: {}: pidfd registration failed\n", nm(godel::svc_name(cfg)));
			};
	case =>
		logf("godel: {}: pidfd unavailable, supervision degraded\n",
			nm(godel::svc_name(cfg)));
	};
	if (!godel::attach(&cg, godel::svc_name(cfg), pid)) {
		logf("godel: {}: cgroup attach failed\n", nm(godel::svc_name(cfg)));
	};
	logf("godel: started {} (pid {})\n", nm(godel::svc_name(cfg)), pid: i64);
	write_status();
};


fn stop_service(index: size) void = {
	const rtst = &svcs[index];
	if (rtst.pid <= 0) return;
	const name = godel::svc_name(&sets[active_set].services[index]);
	const had_cgroup = godel::kill_tree(&cg, name);
	godel::kill_process_group(rtst.pid, rt::SIGTERM);
	for (let s = 0z; s < godel::MAX_SERVICES; s += 1) {
		const slot = &dying[s];
		if (slot.used) continue;
		slot.used = true;
		slot.pid = rtst.pid;
		slot.pidfd = rtst.pidfd;
		slot.had_cgroup = had_cgroup || cg.enabled;
		slot.name_len = len(name): u8;
		slot.name[..len(name)] = name;
		if (rtst.pidfd >= 0) {
			let _ = godel::epoll_modify(&ep, rtst.pidfd,
				godel::TAG_DYING_BASE + s: u64);
		};
		rtst.pid = 0;
		rtst.pidfd = -1;
		rtst.state = godel::state::stopped;
		write_status();
		return;
	};
	logf("godel: dying table full, {} may be orphaned\n", nm(name));
	rtst.pid = 0;
	rtst.pidfd = -1;
	rtst.state = godel::state::stopped;
	write_status();
};

fn on_service_death(index: size) void = {
	const status = match (godel::wait_pid_nohang(svcs[index].pid)) {
	case void => return;
	case let s: u32 => yield s;
	};
	on_service_exit(index, status);
};

fn on_service_exit(index: size, status: u32) void = {
	const rtst = &svcs[index];
	if (rtst.pid <= 0) return;
	const cfg = &sets[active_set].services[index];
	const now = godel::now_ms();
	if (rtst.pidfd >= 0) {
		godel::epoll_remove(&ep, rtst.pidfd);
		godel::close_fd(rtst.pidfd);
		rtst.pidfd = -1;
	};
	rtst.pid = 0;
	const uptime = now - rtst.started_at;
	let _ = godel::kill_tree(&cg, godel::svc_name(cfg));
	godel::release(&cg, godel::svc_name(cfg));
	if (shutdown.active) {
		rtst.state = godel::state::stopped;
		logf("godel: {} stopped\n", nm(godel::svc_name(cfg)));
		write_status();
		return;
	};
	const decision = godel::on_exit(rtst, cfg, status, now);
	match (godel::classify(status)) {
	case void => match (decision) {
		case godel::stopped => logf("godel: {} exited cleanly after {} ms\n", nm(godel::svc_name(cfg)), uptime);
		case let delay: godel::restart_in => logf("godel: {} exited cleanly after {} ms; restarting in {} ms\n", nm(godel::svc_name(cfg)), uptime, delay);
		case godel::gave_up => logf("godel: {} exited cleanly; restart limit reached, giving up\n", nm(godel::svc_name(cfg)));
	};
	case let code: u32 => match (decision) {
		case godel::stopped => logf("godel: {} exited with code {} after {} ms\n", nm(godel::svc_name(cfg)), code, uptime);
		case let delay: godel::restart_in => logf("godel: {} exited with code {} after {} ms; restarting in {} ms\n", nm(godel::svc_name(cfg)), code, uptime, delay);
		case godel::gave_up => logf("godel: {} exited with code {}; restart limit reached, giving up\n", nm(godel::svc_name(cfg)), code);
	};
	case let sig: u8 => match (decision) {
		case godel::stopped => logf("godel: {} killed by signal {} after {} ms\n", nm(godel::svc_name(cfg)), sig, uptime);
		case let delay: godel::restart_in => logf("godel: {} killed by signal {} after {} ms; restarting in {} ms\n", nm(godel::svc_name(cfg)), sig, uptime, delay);
		case godel::gave_up => logf("godel: {} killed by signal {}; restart limit reached, giving up\n", nm(godel::svc_name(cfg)), sig);
	};
	};
	write_status();
	if (shutdown.active && all_stopped()) finish_shutdown();
	check_recovery();
};

fn all_stopped() bool = {
	for (let i = 0z; i < godel::MAX_SERVICES; i += 1) {
		if (svcs[i].pid > 0) return false;
	};
	for (let i = 0z; i < godel::MAX_SERVICES; i += 1) {
		if (dying[i].used) return false;
	};
	if (rescue_pid > 0) return false;
	return true;
};

fn on_dying_death(slot_index: size) void = {
	const slot = &dying[slot_index];
	if (!slot.used) return;
	if (godel::wait_pid_nohang(slot.pid) is void) return;
	if (slot.pidfd >= 0) {
		godel::epoll_remove(&ep, slot.pidfd);
		godel::close_fd(slot.pidfd);
		slot.pidfd = -1;
	};
	if (slot.had_cgroup) {
		const name = slot.name[..slot.name_len];
		let _ = godel::kill_tree(&cg, name);
		godel::release(&cg, name);
	};
	slot.used = false;
	write_status();
	if (shutdown.active && all_stopped()) finish_shutdown();
};

fn handle_signal(sig: u8) void = {
	switch (sig: int) {
	case rt::SIGTERM, rt::SIGINT => begin_shutdown(shutdown_action::poweroff);
	case rt::SIGUSR1 => begin_shutdown(shutdown_action::reboot);
	case rt::SIGHUP => reload();
	case rt::SIGCHLD => reap_unobserved_children();
	case => void;
	};
};

// pidfds are preferred, but SIGCHLD ensures a service remains supervised on
// kernels where pidfd_open is unavailable or an epoll registration fails.
fn reap_unobserved_children() void = {
	for (let i = 0z; i < sets[active_set].count; i += 1) {
		if (svcs[i].pid <= 0 || svcs[i].pidfd >= 0) continue;
		match (godel::wait_pid_nohang(svcs[i].pid)) {
		case void => void;
		case let status: u32 => on_service_exit(i, status);
		};
	};
	for (let i = 0z; i < godel::MAX_SERVICES; i += 1) {
		if (!dying[i].used || dying[i].pidfd >= 0) continue;
		if (godel::wait_pid_nohang(dying[i].pid) is u32) {
			const slot = &dying[i];
			if (slot.had_cgroup) {
				const name = slot.name[..slot.name_len];
				let _ = godel::kill_tree(&cg, name);
				godel::release(&cg, name);
			};
			slot.used = false;
		};
	};
	if (rescue_pid > 0 && rescue_pidfd < 0
			&& godel::wait_pid_nohang(rescue_pid) is u32) {
		on_rescue_exit();
	};
	write_status();
};


fn begin_shutdown(mode: shutdown_action) void = {
	if (shutdown.active) {
		if (shutdown.mode != mode) shutdown.mode = mode;
		return;
	};
	shutdown = shutdown_state {
		active = true,
		mode = mode,
		phase_kill = false,
		deadline = 0,
	};
	logf("Godel: shutting down ({})\n",
		if (mode == shutdown_action::reboot) "reboot" else "poweroff");
	let longest: i64 = 1_000;
	for (let i = 0z; i < sets[active_set].count; i += 1) {
		if (svcs[i].state != godel::state::up) continue;
		if (sets[active_set].services[i].shutdown_timeout_ms > longest) {
			longest = sets[active_set].services[i].shutdown_timeout_ms;
		};
		stop_service(i);
	};
	if (rescue_pid > 0) godel::kill_process_group(rescue_pid, rt::SIGTERM);
	if (longest > SHUTDOWN_CAP_MS) longest = SHUTDOWN_CAP_MS;
	shutdown.deadline = godel::now_ms() + longest;
};

fn on_timer() void = {
	const now = godel::now_ms();
	if (shutdown.active) {
		if (now < shutdown.deadline) return;
		if (!shutdown.phase_kill) {
			shutdown.phase_kill = true;
			shutdown.deadline = now + KILL_PHASE_MS;
			for (let i = 0z; i < sets[active_set].count; i += 1) {
				if (svcs[i].pid > 0) {
					godel::kill_process_group(svcs[i].pid, rt::SIGKILL);
				};
			};
			for (let i = 0z; i < godel::MAX_SERVICES; i += 1) {
				if (dying[i].used && dying[i].pid > 0) {
					godel::kill_process_group(dying[i].pid, rt::SIGKILL);
				};
			};
			if (rescue_pid > 0) {
				godel::kill_process_group(rescue_pid, rt::SIGKILL);
			};
			logf("godel: sending SIGKILL to remaining services\n");
		} else {
			finish_shutdown();
		};
		return;
	};
	for (let i = 0z; i < godel::MAX_SERVICES; i += 1) {
		if (svcs[i].state != godel::state::backoff
				|| svcs[i].restart_at > now) continue;
		svcs[i].state = godel::state::stopped;
		svcs[i].restart_at = 0;
		start(i);
	};
};

fn check_recovery() void = {
	if (shutdown.active || recovery_active) return;
	let any_gave_up = false;
	for (let i = 0z; i < sets[active_set].count; i += 1) {
		switch (svcs[i].state) {
		case godel::state::up, godel::state::backoff => return;
		case godel::state::gave_up => any_gave_up = true;
		case godel::state::stopped => void;
		};
	};
	if (!any_gave_up) {
		logf("godel: all services finished; powering off\n");
		begin_shutdown(shutdown_action::poweroff);
		return;
	};
	if (!recovery_used) {
		enter_rescue();
		return;
	};
	logf("godel: services keep failing and recovery was used\n");
	begin_shutdown(shutdown_action::poweroff);
};

fn enter_rescue() void = {
	recovery_used = true;
	logf("godel: starting recovery shell on console\n");
	const pid = match (rt::fork()) {
	case void => run_rescue();
	case let e: rt::errno =>
		logf("godel: rescue fork failed\n");
		begin_shutdown(shutdown_action::poweroff);
		return;
	case let p: rt::pid_t => yield p;
	};
	rescue_pid = pid;
	match (godel::pidfd_open(pid)) {
	case let pfd: int =>
		rescue_pidfd = pfd;
		if (!(godel::epoll_add(&ep, pfd, godel::TAG_RESCUE) is void)) {
			godel::close_fd(pfd);
			rescue_pidfd = -1;
		};
	case => void;
	};
	recovery_active = true;
};

fn run_rescue() never = {
	let _ = rt::setsid();
	let argv: [2]nullable *const u8 = [null, null];
	argv[0] = &RESCUE_CS[0]: *const u8;
	let envbufs: [3][48]u8 = [[0...]...];
	let envp: [4]nullable *const u8 = [null...];
	let _ = setup_envp(envp[..], &envbufs);
	let _ = rt::execve(&RESCUE_CS[0]: *const u8,
		&argv: *[*]nullable *const u8, &envp: *[*]nullable *const u8);
	logf("godel: cannot execute rescue shell\n");
	os::exit(127);
};

fn on_rescue_death() void = {
	if (godel::wait_pid_nohang(rescue_pid) is void) return;
	on_rescue_exit();
};

fn on_rescue_exit() void = {
	if (rescue_pidfd >= 0) {
		godel::epoll_remove(&ep, rescue_pidfd);
		godel::close_fd(rescue_pidfd);
		rescue_pidfd = -1;
	};
	rescue_pid = 0;
	recovery_active = false;
	write_status();
	if (shutdown.active) return;
	logf("godel: recovery shell exited\n");
	let content_buf: [godel::BUF_CAPACITY]u8 = [0...];
	let valid = false;
	match (read_config_file(content_buf[..])) {
	case void => void;
	case let c: []u8 =>
		valid = godel::parse(&sets[active_set ^ 1], c) is void;
	};
	if (valid) {
		report_warnings(active_set ^ 1);
		apply_config(active_set ^ 1);
		recovery_used = false;
		return;
	};
	logf("godel: no valid configuration to start\n");
	begin_shutdown(shutdown_action::poweroff);
};

fn arm_timer() void = {
	let nearest: (void | i64) = void;
	if (shutdown.active) nearest = shutdown.deadline;
	for (let i = 0z; i < godel::MAX_SERVICES; i += 1) {
		if (svcs[i].state == godel::state::backoff) {
			nearest = match (nearest) {
			case void => yield svcs[i].restart_at;
			case let n: i64 =>
				yield if (n < svcs[i].restart_at) n
					else svcs[i].restart_at;
			};
		};
	};
	match (nearest) {
	case void => godel::timer_disable(&tmr);
	case let deadline: i64 => godel::timer_set_abs(&tmr, deadline);
	};
};

fn finish_shutdown() never = {
	for (let i = 0z; i < godel::MAX_SERVICES; i += 1) {
		if (svcs[i].pid > 0) {
			let _ = godel::wait_pid_nohang(svcs[i].pid);
		};
	};
	logf("Godel: {} now\n",
		if (shutdown.mode == shutdown_action::reboot) "rebooting"
		else "powering off");
	rt::sync();
	const cmd: u64 = if (shutdown.mode == shutdown_action::reboot)
		SHUTDOWN_RESTART
	else
		SHUTDOWN_POWEROFF;
	const rc = rt::syscall(rt::SYS_reboot, RB_MAGIC, RB_CMD, cmd, 0);
	if (rc > 0x7fff_ffff_ffff_ffff) {
		logf("godel: reboot syscall failed\n");
	};
	for (true) rt::syscall(rt::SYS_pause);
};
