use bytes;
use strings;

export def MAX_SERVICES: size = 16;
export def MAX_ARGS: size = 8;
export def MAX_ENV: size = 4;
export def MAX_AFTER: size = 4;
export def MAX_NAME_LEN: size = 31;
export def BUF_CAPACITY: size = 16 * 1024;
export def MAX_WARNINGS: size = 4;
export def NO_INDEX: u8 = 0xff;

export type restart = enum u8 { always, on_failure, none };
export type service_kind = enum u8 { long_running, oneshot };

export type service = struct {
	name: [MAX_NAME_LEN + 1]u8,
	name_len: u8,
	argv_off: [MAX_ARGS]u16,
	argv_len: [MAX_ARGS]u16,
	argc: u8,
	env_off: [MAX_ENV]u16,
	env_len: [MAX_ENV]u16,
	envc: u8,
	after_names: [MAX_AFTER][MAX_NAME_LEN + 1]u8,
	after_lens: [MAX_AFTER]u8,
	after: [MAX_AFTER]u8,
	after_len: u8,
	line: size,
	restart: restart,
	kind: service_kind,
	restart_limit: u32,
	restart_delay_ms: i64,
	shutdown_timeout_ms: i64,
};

export type diag = struct { line: size, msg: str };
export type warning = struct { line: size, msg: str };

export type set = struct {
	buf: [BUF_CAPACITY]u8,
	used: size,
	services: [MAX_SERVICES]service,
	count: size,
	warnings: [MAX_WARNINGS]warning,
	warning_count: size,
};

export fn new_service() service = service {
	after = [NO_INDEX, NO_INDEX, NO_INDEX, NO_INDEX],
	restart_limit = 10,
	restart_delay_ms = 250,
	shutdown_timeout_ms = 5000,
	...
};

export fn svc_name(svc: *const service) []u8 = svc.name[..svc.name_len];

export fn svc_after_name(svc: *const service, i: size) []u8 =
	svc.after_names[i][..svc.after_lens[i]];

export fn svc_arg(s: *const set, svc: *const service, i: size) []u8 =
	s.buf[svc.argv_off[i]..svc.argv_off[i] + svc.argv_len[i]];

export fn svc_env(s: *const set, svc: *const service, i: size) []u8 =
	s.buf[svc.env_off[i]..svc.env_off[i] + svc.env_len[i]];

fn eqs(a: []u8, b: str) bool = bytes::equal(a, strings::toutf8(b));

fn has_prefix(a: []u8, b: str) bool = {
	const nb = strings::toutf8(b);
	if (len(a) < len(nb)) return false;
	return bytes::equal(a[..len(nb)], nb);
};

fn has_suffix(a: []u8, b: str) bool = {
	const nb = strings::toutf8(b);
	if (len(a) < len(nb)) return false;
	return bytes::equal(a[len(a) - len(nb)..], nb);
};

fn sp3(c: u8) bool = c == ' ' || c == '\t' || c == '\r';
fn sp2(c: u8) bool = c == ' ' || c == '\t';

fn trim3(line: []u8) []u8 = {
	let start: size = 0;
	for (start < len(line) && sp3(line[start])) start += 1;
	let end = len(line);
	for (end > start && sp3(line[end - 1])) end -= 1;
	return line[start..end];
};

fn trim2(x: []u8) (size, size) = {
	let start: size = 0;
	for (start < len(x) && sp2(x[start])) start += 1;
	let end = len(x);
	for (end > start && sp2(x[end - 1])) end -= 1;
	return (start, end);
};

fn add_warning(s: *set, line: size, msg: str) void = {
	if (s.warning_count >= MAX_WARNINGS) return;
	s.warnings[s.warning_count] = warning { line = line, msg = msg };
	s.warning_count += 1;
};

fn find_name(s: *const set, name: []u8) (void | size) = {
	for (let i = 0z; i < s.count; i += 1) {
		if (bytes::equal(svc_name(&s.services[i]), name)) return i;
	};
};

fn push_service(s: *set, svc: *service) (void | diag) = {
	if (svc.argc == 0) {
		return diag { line = svc.line, msg = "service has no command" };
	};
	if (s.count == MAX_SERVICES) {
		return diag { line = svc.line, msg = "too many services" };
	};
	s.services[s.count] = *svc;
	s.count += 1;
};

export fn parse(s: *set, source: []u8) (void | diag) = {
	s.used = if (len(source) < BUF_CAPACITY - 1) len(source) else BUF_CAPACITY - 1;
	s.buf[..s.used] = source[..s.used];
	s.count = 0;
	s.warning_count = 0;
	if (len(source) > s.used) {
		add_warning(s, 1, "config truncated");
	};

	let current = new_service();
	let in_section = false;
	let line_no: size = 0;
	let pos: size = 0;

	for (pos <= s.used) {
		let end = s.used;
		for (let i = pos; i < s.used; i += 1) {
			if (s.buf[i] == '\n') {
				end = i;
				break;
			};
		};
		line_no += 1;
		const line = trim3(s.buf[pos..end]);

		if (len(line) != 0 && line[0] != '#' && line[0] != '[' && !in_section) {
			return diag { line = line_no, msg = "setting outside [service] section" };
		};
		if (len(line) == 0 || line[0] == '#') {
			if (end == s.used) break;
			pos = end + 1;
			continue;
		};
		if (line[0] == '[') {
			if (in_section) {
				match (push_service(s, &current)) {
				case void => void;
				case let d: diag => return d;
				};
			};
			in_section = false;
			current = new_service();
			current.line = line_no;
			const header = match (parse_header(line)) {
			case void =>
				return diag { line = line_no, msg = "invalid section header" };
			case let h: []u8 => yield h;
			};
			if (!valid_name(header)) {
				return diag { line = line_no, msg = "invalid service name" };
			};
			if (len(header) > MAX_NAME_LEN) {
				return diag { line = line_no, msg = "service name too long" };
			};
			if (find_name(s, header) is size) {
				return diag { line = line_no, msg = "duplicate service name" };
			};
			current.name[..len(header)] = header;
			current.name_len = len(header): u8;
			in_section = true;
		} else {
			let eq = len(line);
			for (let i = 0z; i < len(line); i += 1) {
				if (line[i] == '=') {
					eq = i;
					break;
				};
			};
			if (eq == len(line)) {
				return diag { line = line_no, msg = "expected key = value" };
			};
			const (kt, ke) = trim2(line[..eq]);
			const key = line[kt..ke];
			const (vt, ve) = trim2(line[eq + 1..]);
			const value = line[eq + 1 + vt..eq + 1 + ve];
			if (len(key) == 0 || len(value) == 0) {
				return diag { line = line_no, msg = "empty key or value" };
			};
			const base = pos + eq + 1 + vt;
			match (apply_key(s, &current, key, value, base, line_no)) {
			case void => void;
			case let d: diag => return d;
			};
		};
		if (end == s.used) break;
		pos = end + 1;
	};

	if (in_section) {
		match (push_service(s, &current)) {
		case void => void;
		case let d: diag => return d;
		};
	};
	if (s.count == 0) {
		return diag { line = line_no, msg = "no services defined" };
	};
	match (resolve_after(s)) {
	case void => void;
	case let d: diag => return d;
	};
};

fn apply_key(
	s: *set,
	svc: *service,
	key: []u8,
	value: []u8,
	base: size,
	line_no: size,
) (void | diag) = {
	if (eqs(key, "command")) {
		let argc: size = 0;
		let start: (void | size) = void;
		let i: size = 0;
		for (i <= len(value); i += 1) {
			const at_end = i == len(value);
			const sep = !at_end && (value[i] == ' ' || value[i] == '\t');
			if (start is void) {
				if (!at_end && !sep) start = i;
			} else if (at_end || sep) {
				if (argc == MAX_ARGS) {
					return diag { line = line_no, msg = "too many arguments" };
				};
				s.buf[base + i] = 0;
				svc.argv_off[argc] = (base + start: size): u16;
				svc.argv_len[argc] = (i - start: size): u16;
				argc += 1;
				start = void;
			};
		};
		svc.argc = argc: u8;
		return;
	};
	if (eqs(key, "after")) {
		let count: size = 0;
		let start: (void | size) = void;
		let i: size = 0;
		for (i <= len(value); i += 1) {
			const at_end = i == len(value);
			const sep = !at_end && (value[i] == ' ' || value[i] == '\t');
			if (start is void) {
				if (!at_end && !sep) start = i;
			} else if (at_end || sep) {
				if (count == MAX_AFTER) {
					return diag { line = line_no, msg = "too many after entries" };
				};
				const dep = value[start: size..i];
				if (len(dep) > MAX_NAME_LEN) {
					return diag { line = line_no, msg = "after name too long" };
				};
				if (bytes::equal(svc_name(svc), dep)) {
					return diag { line = line_no, msg = "service depends on itself" };
				};
				svc.after_names[count][..len(dep)] = dep;
				svc.after_lens[count] = len(dep): u8;
				count += 1;
				start = void;
			};
		};
		svc.after_len = count: u8;
		return;
	};
	if (eqs(key, "env")) {
		let count: size = svc.envc: size;
		let start: (void | size) = void;
		let i: size = 0;
		for (i <= len(value); i += 1) {
			const at_end = i == len(value);
			const sep = !at_end && (value[i] == ' ' || value[i] == '\t');
			if (start is void) {
				if (!at_end && !sep) start = i;
			} else if (at_end || sep) {
				if (count == MAX_ENV) {
					return diag { line = line_no, msg = "too many environment entries" };
				};
				const entry = value[start: size..i];
				if (!valid_env(entry)) {
					return diag { line = line_no, msg = "env must be NAME=VALUE" };
				};
				for (let j = 0z; j < count; j += 1) {
					if (env_key_equal(entry, svc_env(s, svc, j))) {
						return diag { line = line_no, msg = "duplicate environment name" };
					};
				};
				s.buf[base + i] = 0;
				svc.env_off[count] = (base + start: size): u16;
				svc.env_len[count] = (i - start: size): u16;
				count += 1;
				start = void;
			};
		};
		svc.envc = count: u8;
		return;
	};
	if (eqs(key, "type")) {
		if (eqs(value, "service")) {
			svc.kind = service_kind::long_running;
		} else if (eqs(value, "oneshot")) {
			svc.kind = service_kind::oneshot;
		} else {
			return diag { line = line_no, msg = "type must be service or oneshot" };
		};
		return;
	};
	if (eqs(key, "restart")) {
		if (eqs(value, "always")) {
			svc.restart = restart::always;
		} else if (eqs(value, "on-failure")) {
			svc.restart = restart::on_failure;
		} else if (eqs(value, "never")) {
			svc.restart = restart::none;
		} else {
			return diag {
				line = line_no,
				msg = "restart must be always, on-failure or never",
			};
		};
		return;
	};
	if (eqs(key, "restart_limit")) {
		svc.restart_limit = match (parse_u32(value)) {
		case void =>
			return diag { line = line_no, msg = "restart_limit must be a number" };
		case let n: u32 => yield n;
		};
		if (svc.restart_limit > 1000) {
			return diag { line = line_no, msg = "restart_limit too large" };
		};
		return;
	};
	if (eqs(key, "restart_delay") || eqs(key, "shutdown_timeout")) {
		const ms = match (parse_duration(value)) {
		case void =>
			return diag { line = line_no, msg = "duration must be like 250ms or 5s" };
		case let n: i64 => yield n;
		};
		if (ms < 0 || ms > 120_000) {
			return diag { line = line_no, msg = "duration out of range" };
		};
		if (key[0] == 'r') {
			svc.restart_delay_ms = ms;
		} else {
			svc.shutdown_timeout_ms = ms;
		};
		return;
	};
	add_warning(s, line_no, "unknown key");
};

fn resolve_after(s: *set) (void | diag) = {
	for (let i = 0z; i < s.count; i += 1) {
		const svc = &s.services[i];
		for (let slot = 0z; slot < svc.after_len: size; slot += 1) {
			const found = match (find_name(s, svc_after_name(svc, slot))) {
			case void =>
				return diag { line = svc.line, msg = "after names unknown service" };
			case let f: size => yield f;
			};
			svc.after[slot] = found: u8;
		};
	};
	match (find_cycle(s.services[..s.count])) {
	case void => void;
	case let line: size =>
		return diag { line = line, msg = "after dependencies form a cycle" };
	};
};

export fn start_order(s: *const set, order: *[MAX_SERVICES]size) size = {
	let launched: [MAX_SERVICES]bool = [false...];
	let total: size = 0;
	for (total < s.count) {
		let progress = false;
		for (let i = 0z; i < s.count; i += 1) {
			if (launched[i]) continue;
			let ready = true;
			const svc = &s.services[i];
			for (let slot = 0z; slot < svc.after_len: size; slot += 1) {
				if (!launched[svc.after[slot]]) {
					ready = false;
					break;
				};
			};
			if (ready) {
				order[total] = i;
				launched[i] = true;
				total += 1;
				progress = true;
			};
		};
		if (!progress) break;
	};
	return total;
};

fn parse_header(line: []u8) (void | []u8) = {
	if (!has_prefix(line, "[service")) return;
	const rest_raw = line[8..];
	const (t, e) = trim2(rest_raw);
	const rest = rest_raw[t..e];
	if (len(rest) < 3 || rest[0] != '"') return;
	let close: (void | size) = void;
	for (let i = 1z; i < len(rest); i += 1) {
		if (rest[i] == '"') {
			close = i;
			break;
		};
	};
	const c = match (close) {
	case void => return;
	case let n: size => yield n;
	};
	const tail_raw = rest[c + 1..];
	const (tt, te) = trim2(tail_raw);
	if (!eqs(tail_raw[tt..te], "]")) return;
	return rest[1..c];
};

fn valid_name(name: []u8) bool = {
	if (len(name) == 0) return false;
	for (let k = 0z; k < len(name); k += 1) {
		const ch = name[k];
		const ok = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
			(ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.';
		if (!ok) return false;
	};
	return true;
};

fn env_key_len(entry: []u8) (void | size) = {
	for (let i = 0z; i < len(entry); i += 1) {
		if (entry[i] == '=') return i;
	};
};

fn valid_env(entry: []u8) bool = {
	const key_len = match (env_key_len(entry)) {
	case void => return false;
	case let n: size => yield n;
	};
	if (key_len == 0) return false;
	for (let i = 0z; i < key_len; i += 1) {
		const ch = entry[i];
		const alpha = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
		if (!(alpha || ch == '_' || (i > 0 && ch >= '0' && ch <= '9'))) return false;
	};
	return true;
};

fn env_key_equal(a: []u8, b: []u8) bool = {
	const an = match (env_key_len(a)) {
	case void => return false;
	case let n: size => yield n;
	};
	const bn = match (env_key_len(b)) {
	case void => return false;
	case let n: size => yield n;
	};
	return an == bn && bytes::equal(a[..an], b[..bn]);
};

export fn parse_duration(text: []u8) (i64 | void) = {
	if (len(text) == 0) return;
	let digits = text;
	let mult: i64 = 1;
	if (has_suffix(text, "ms")) {
		digits = text[..len(text) - 2];
	} else if (has_suffix(text, "s")) {
		digits = text[..len(text) - 1];
		mult = 1000;
	};
	if (len(digits) == 0) return;
	let acc: u64 = 0;
	for (let k = 0z; k < len(digits); k += 1) {
		const ch = digits[k];
		if (ch < '0' || ch > '9') return;
		if (acc > 922337203685477580) return;
		acc = acc * 10 + (ch - '0'): u64;
		if (acc > 9223372036854775807) return;
	};
	const n = acc: i64;
	if (mult == 1000 && n > 9223372036854775) return;
	return n * mult;
};

fn parse_u32(text: []u8) (u32 | void) = {
	if (len(text) == 0) return;
	let acc: u64 = 0;
	for (let k = 0z; k < len(text); k += 1) {
		const ch = text[k];
		if (ch < '0' || ch > '9') return;
		if (acc > 429496729) return;
		acc = acc * 10 + (ch - '0'): u64;
		if (acc > 4294967295) return;
	};
	return acc: u32;
};

fn find_cycle(services: []service) (void | size) = {
	let color: [MAX_SERVICES]u8 = [0...];
	for (let i = 0z; i < len(services); i += 1) {
		if (color[i] == 0) {
			match (visit(services, &color, i: u8)) {
			case void => void;
			case let line: size => return line;
			};
		};
	};
};

fn visit(services: []service, color: *[MAX_SERVICES]u8, index: u8) (void | size) = {
	color[index] = 1;
	const svc = &services[index];
	for (let slot = 0z; slot < svc.after_len: size; slot += 1) {
		const dep = svc.after[slot];
		if (dep == NO_INDEX) continue;
		if (color[dep] == 1) return svc.line;
		if (color[dep] == 0) {
			match (visit(services, color, dep)) {
			case void => void;
			case let line: size => return line;
			};
		};
	};
	color[index] = 2;
};
