use bytes;
use fmt;
use io;
use os;
use strings;

type svc_rec = struct {
	name: str,
	start_t: i64,
	ready: i64,
};

type oneshot_rec = struct {
	name: str,
	ms: i64,
};

type report = struct {
	pid1_t: i64,
	ready_t: i64,
	svcs: []svc_rec,
	oneshots: []oneshot_rec,
	sd_begin: i64,
	sd_end: i64,
	sd_deadline: i64,
	ro_ms: i64,
	sync_ms: i64,
	hung: i64,
	sd_mode: str,
};

fn has_prefix(line: []u8, p: str) bool =
	bytes::hasprefix(line, strings::toutf8(p));

fn stamp_split(line: []u8) (void | (i64, []u8)) = {
	if (!has_prefix(line, "[T+")) return;
	let i = 3z;
	let v: i64 = 0;
	for (i < len(line) && line[i] >= '0' && line[i] <= '9'; i += 1) {
		v = v * 10 + (line[i] - '0'): i64;
	};
	if (i == 3 || i + 4 > len(line)) return;
	if (!bytes::equal(line[i..i + 4], strings::toutf8("ms] "))) return;
	return (v, line[i + 4..]);
};

fn num_after(line: []u8, marker: str) (void | i64) = {
	const m = strings::toutf8(marker);
	if (len(m) >= len(line)) return;
	for (let i = 0z; i + len(m) <= len(line); i += 1) {
		if (!bytes::equal(line[i..i + len(m)], m)) continue;
		let v: i64 = 0;
		let j = i + len(m);
		const d0 = j;
		for (j < len(line) && line[j] >= '0' && line[j] <= '9'; j += 1) {
			v = v * 10 + (line[j] - '0'): i64;
		};
		if (j == d0) return;
		return v;
	};
};

fn tail_num(line: []u8, marker: str, tail: str) (void | i64) = {
	if (!has_prefix(line, marker)) return;
	if (!bytes::hassuffix(line, strings::toutf8(tail))) return;
	return num_after(line, marker);
};

fn is_starting(line: []u8) bool = {
	const tail = strings::toutf8(" starting");
	if (!has_prefix(line, "godel ")) return false;
	if (len(line) < 8 || line[6] < '0' || line[6] > '9') return false;
	if (!bytes::hassuffix(line, tail)) return false;
	for (let i = 6z; i < len(line) - len(tail); i += 1) {
		if (line[i] == ' ') return false;
	};
	return true;
};

fn is_ready_line(line: []u8) bool = {
	const head = strings::toutf8("godel: ready in ");
	if (!has_prefix(line, "godel: ready in ")) return false;
	let i = len(head);
	const d0 = i;
	for (i < len(line) && line[i] >= '0' && line[i] <= '9'; i += 1) {
		void;
	};
	if (i == d0) return false;
	return i + 5 <= len(line)
		&& bytes::equal(line[i..i + 5], strings::toutf8(" ms; "));
};

fn started_name(line: []u8) (void | str) = {
	const head = strings::toutf8("godel: started ");
	const mark = strings::toutf8(" (pid ");
	if (!has_prefix(line, "godel: started ")) return;
	for (let i = len(head); i + len(mark) <= len(line); i += 1) {
		if (!bytes::equal(line[i..i + len(mark)], mark)) continue;
		let j = i + len(mark);
		const d0 = j;
		for (j < len(line) && line[j] >= '0' && line[j] <= '9'; j += 1) {
			void;
		};
		if (j == d0) return;
		if (j + 1 != len(line) || line[j] != ')') return;
		return strings::fromutf8_unsafe(line[len(head)..i]);
	};
};

fn ready_after(line: []u8) (void | (str, i64)) = {
	const head = strings::toutf8("godel: ");
	const mark = strings::toutf8(" is ready after ");
	const tail = strings::toutf8(" ms");
	if (!has_prefix(line, "godel: ")) return;
	if (!bytes::hassuffix(line, tail)) return;
	for (let i = len(head); i + len(mark) + len(tail) <= len(line); i += 1) {
		if (!bytes::equal(line[i..i + len(mark)], mark)) continue;
		let j = i + len(mark);
		let v: i64 = 0;
		const d0 = j;
		for (j < len(line) && line[j] >= '0' && line[j] <= '9'; j += 1) {
			v = v * 10 + (line[j] - '0'): i64;
		};
		if (j == d0) return;
		if (j + len(tail) != len(line)) return;
		return (strings::fromutf8_unsafe(line[len(head)..i]), v);
	};
};

fn clean_exit(line: []u8) (void | (str, i64)) = {
	const head = strings::toutf8("godel: ");
	const mark = strings::toutf8(" exited cleanly after ");
	const tail = strings::toutf8(" ms");
	if (!has_prefix(line, "godel: ")) return;
	if (!bytes::hassuffix(line, tail)) return;
	for (let i = len(head); i + len(mark) + len(tail) <= len(line); i += 1) {
		if (!bytes::equal(line[i..i + len(mark)], mark)) continue;
		let j = i + len(mark);
		let v: i64 = 0;
		const d0 = j;
		for (j < len(line) && line[j] >= '0' && line[j] <= '9'; j += 1) {
			v = v * 10 + (line[j] - '0'): i64;
		};
		if (j == d0) return;
		if (j + len(tail) != len(line)) return;
		return (strings::fromutf8_unsafe(line[len(head)..i]), v);
	};
};

fn shutdown_mode(line: []u8) (void | str) = {
	const head = strings::toutf8("godel: shutting down (");
	if (!has_prefix(line, "godel: shutting down (")) return;
	if (len(line) == 0 || line[len(line) - 1] != ')') return;
	const inner = line[len(head)..len(line) - 1];
	if (len(inner) == 0) return;
	for (let i = 0z; i < len(inner); i += 1) {
		if (inner[i] < 'a' || inner[i] > 'z') return;
	};
	return strings::fromutf8_unsafe(inner);
};

fn remount_sync(line: []u8) (void | (i64, i64)) = {
	const head = strings::toutf8("godel: remount-ro took ");
	const mid = strings::toutf8(" ms; sync took ");
	const tail = strings::toutf8(" ms");
	if (!has_prefix(line, "godel: remount-ro took ")) return;
	let i = len(head);
	let ro: i64 = 0;
	const d0 = i;
	for (i < len(line) && line[i] >= '0' && line[i] <= '9'; i += 1) {
		ro = ro * 10 + (line[i] - '0'): i64;
	};
	if (i == d0 || i + len(mid) > len(line)) return;
	if (!bytes::equal(line[i..i + len(mid)], mid)) return;
	i += len(mid);
	let sy: i64 = 0;
	const s0 = i;
	for (i < len(line) && line[i] >= '0' && line[i] <= '9'; i += 1) {
		sy = sy * 10 + (line[i] - '0'): i64;
	};
	if (i == s0 || i + len(tail) != len(line)) return;
	if (!bytes::equal(line[i..], tail)) return;
	return (ro, sy);
};

fn flush_report(rep: *report, boot_n: *size) void = {
	if (rep.pid1_t < 0) return;
	*boot_n += 1;
	fmt::printf("boot {}: pid1=T+{}ms", *boot_n, rep.pid1_t)!;
	if (rep.ready_t >= 0) {
		fmt::printf(" ready=T+{}ms load={}ms",
			rep.ready_t, rep.ready_t - rep.pid1_t)!;
	};
	fmt::println()!;
	if (len(rep.oneshots) > 0) {
		fmt::print("  oneshots:")!;
		for (let k = 0z; k < len(rep.oneshots); k += 1) {
			fmt::printf(" {} {}ms", rep.oneshots[k].name, rep.oneshots[k].ms)!;
		};
		fmt::println()!;
	};
	if (len(rep.svcs) > 0) {
		fmt::print("  services:")!;
		for (let k = 0z; k < len(rep.svcs); k += 1) {
			fmt::printf(" {} T+{}ms", rep.svcs[k].name, rep.svcs[k].start_t)!;
			if (rep.svcs[k].ready >= 0) {
				fmt::printf("(ready {}ms)", rep.svcs[k].ready)!;
			};
		};
		fmt::println()!;
	};
	if (rep.sd_begin >= 0) {
		fmt::printf("  shutdown: mode={} begin=T+{}ms",
			rep.sd_mode, rep.sd_begin)!;
		if (rep.sd_deadline >= 0) {
			fmt::printf(" deadline={}ms", rep.sd_deadline)!;
		};
		if (rep.hung >= 0) {
			fmt::printf(" hung={}", rep.hung)!;
		};
		if (rep.ro_ms >= 0) {
			fmt::printf(" remount-ro={}ms", rep.ro_ms)!;
		};
		if (rep.sync_ms >= 0) {
			fmt::printf(" sync={}ms", rep.sync_ms)!;
		};
		if (rep.sd_end >= 0) {
			fmt::printf(" total={}ms", rep.sd_end - rep.sd_begin)!;
		};
		fmt::println()!;
	};
};

fn reset_report(rep: *report) void = {
	rep.pid1_t = -1;
	rep.ready_t = -1;
	rep.svcs = rep.svcs[..0];
	rep.oneshots = rep.oneshots[..0];
	rep.sd_begin = -1;
	rep.sd_end = -1;
	rep.sd_deadline = -1;
	rep.ro_ms = -1;
	rep.sync_ms = -1;
	rep.hung = -1;
	rep.sd_mode = "";
};

fn run_boot_report(path: str) int = {
	const f = match (os::open(path)) {
	case let f: io::file => yield f;
	case =>
		fmt::errorfln("boot-report: cannot read {}", path)!;
		return 1;
	};
	const data = match (io::drain(f)) {
	case let d: []u8 => yield d;
	case =>
		io::close(f)!;
		fmt::errorfln("boot-report: cannot read {}", path)!;
		return 1;
	};
	io::close(f)!;
	defer free(data);

	let rep = report {
		pid1_t = -1, ready_t = -1,
		svcs = [], oneshots = [],
		sd_begin = -1, sd_end = -1, sd_deadline = -1,
		ro_ms = -1, sync_ms = -1, hung = -1,
		sd_mode = "",
	};
	let boot_n: size = 0;
	let stamped = false;

	let pos: size = 0;
	for (pos <= len(data)) {
		let end = pos;
		for (end < len(data) && data[end] != '\n'; end += 1) {
			void;
		};
		const line = data[pos..end];
		pos = end + 1;

		const stamped_line = match (stamp_split(line)) {
		case void => continue;
		case let s: (i64, []u8) => yield s;
		};
		stamped = true;
		const t = stamped_line.0;
		const rest = stamped_line.1;

		if (is_starting(rest)) {
			flush_report(&rep, &boot_n);
			reset_report(&rep);
			rep.pid1_t = t;
			continue;
		};
		if (rep.pid1_t < 0) rep.pid1_t = t;
		if (is_ready_line(rest)) rep.ready_t = t;

		let consumed = false;
		match (started_name(rest)) {
		case void => void;
		case let name: str => {
			let found = false;
			for (let k = 0z; k < len(rep.svcs); k += 1) {
				if (rep.svcs[k].name == name) {
					rep.svcs[k].start_t = t;
					found = true;
					break;
				};
			};
			if (!found) {
				append(rep.svcs,
					svc_rec { name = name, start_t = t, ready = -1 })!;
			};
			consumed = true;
		};
		};
		if (consumed) continue;
		match (ready_after(rest)) {
		case void => void;
		case let r: (str, i64) => {
			for (let k = 0z; k < len(rep.svcs); k += 1) {
				if (rep.svcs[k].name == r.0) {
					rep.svcs[k].ready = r.1;
					break;
				};
			};
			consumed = true;
		};
		};
		if (consumed) continue;
		match (clean_exit(rest)) {
		case void => void;
		case let c: (str, i64) => {
			let found = false;
			for (let k = 0z; k < len(rep.oneshots); k += 1) {
				if (rep.oneshots[k].name == c.0) {
					rep.oneshots[k].ms = c.1;
					found = true;
					break;
				};
			};
			if (!found) {
				append(rep.oneshots, oneshot_rec { name = c.0, ms = c.1 })!;
			};
			consumed = true;
		};
		};
		if (consumed) continue;
		match (shutdown_mode(rest)) {
		case void => void;
		case let m: str => {
			rep.sd_begin = t;
			rep.sd_mode = m;
			consumed = true;
		};
		};
		if (consumed) continue;
		match (tail_num(rest, "godel: shutdown deadline in ", " ms")) {
		case void => void;
		case let n: i64 => {
			rep.sd_deadline = n;
			consumed = true;
		};
		};
		if (consumed) continue;
		match (tail_num(rest,
				"godel: sending SIGKILL to remaining services (", " hung)")) {
		case void => void;
		case let n: i64 => {
			rep.hung = n;
			consumed = true;
		};
		};
		if (consumed) continue;
		match (remount_sync(rest)) {
		case void => void;
		case let rs: (i64, i64) => {
			rep.ro_ms = rs.0;
			rep.sync_ms = rs.1;
			consumed = true;
		};
		};
		if (consumed) continue;
		if (bytes::equal(rest, strings::toutf8("godel: rebooting now"))
				|| bytes::equal(rest,
					strings::toutf8("godel: powering off now"))) {
			rep.sd_end = t;
		};
	};

	if (!stamped) {
		fmt::errorln(
			"boot-report: no [T+Nms] stamps found; logs are pre-0.9.4")!;
		return 1;
	};
	flush_report(&rep, &boot_n);
	return 0;
};
