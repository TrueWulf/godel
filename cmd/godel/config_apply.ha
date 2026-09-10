use fs;
use godel;
use io;
use os;

fn read_config_file(buffer: []u8) (void | []u8) = {
	const f = match (os::open(SERVICES_CONF)) {
	case let f: io::file => yield f;
	case let e: fs::error =>
		logf("godel: open {}: {}\n", SERVICES_CONF, fs::strerror(e));
		return;
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
			logf("godel: read {}: {}\n", SERVICES_CONF, io::strerror(e));
			return;
		};
	};
	return buffer[..used];
};

fn load_and_apply() void = {
	let content_buf: [godel::BUF_CAPACITY]u8 = [0...];
	const content = match (read_config_file(content_buf[..])) {
	case void =>
		logf("godel: {} not found\n", SERVICES_CONF);
		enter_rescue();
		return;
	case let c: []u8 => yield c;
	};
	const next = active_set ^ 1;
	match (godel::parse(&sets[next], content)) {
	case void => void;
	case let d: godel::diag =>
		logf("godel: {}:{}: {}; entering recovery\n",
			SERVICES_CONF, d.line, d.msg);
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
			SERVICES_CONF, warning.line, warning.msg);
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
		if (j == godel::NO_INDEX) continue;
		svcs[i] = svcs[j];
		svcs[i].restarts = 0;
		svcs[i].restart_at = 0;
		svcs[j] = godel::runtime { pidfd = -1, ... };
		let _ = godel::epoll_modify(&ep, svcs[i].pidfd, i: u64);
	};
	active_set = next;

	let order: [godel::MAX_SERVICES]size = [0...];
	const total = godel::start_order(&sets[active_set], &order);
	for (let k = 0z; k < total; k += 1) {
		const index = order[k];
		if (svcs[index].state == godel::state::up) continue;
		start(index);
	};
	check_recovery();
	write_status();
};

fn reload() void = {
	logf("godel: reloading configuration\n");
	let content_buf: [godel::BUF_CAPACITY]u8 = [0...];
	const content = match (read_config_file(content_buf[..])) {
	case void =>
		logf("godel: reload skipped: {} unreadable\n", SERVICES_CONF);
		return;
	case let c: []u8 => yield c;
	};
	const next = active_set ^ 1;
	match (godel::parse(&sets[next], content)) {
	case void => void;
	case let d: godel::diag =>
		logf("godel: reload refused: {}:{}: {}\n",
			SERVICES_CONF, d.line, d.msg);
		return;
	};
	report_warnings(next);
	apply_config(next);
	recovery_used = false;
	logf("godel: configuration reloaded\n");
};
