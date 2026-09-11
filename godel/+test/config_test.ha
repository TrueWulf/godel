use bytes;
use fmt;
use memio;
use strings;

fn expect_diag(r: (void | diag), want_line: size, want_msg: str) void = {
	const d = r as diag;
	assert(d.line == want_line);
	assert(d.msg == want_msg);
};

fn parse_ok(s: *set, src: str) void = {
	match (parse(s, strings::toutf8(src))) {
	case void => void;
	case let d: diag =>
		abort(fmtstr("unexpected diag at line {}: {}", d.line: i64, d.msg));
	};
};

let abortbuf: [128]u8 = [0...];

fn fmtstr(a: str, b: i64, c: str) str = {
	let s = memio::fixed(abortbuf);
	fmt::fprintf(&s, "{}{}{}", a, b, c)!;
	return memio::string(&s)!;
};

@test fn parses_full_service_definitions() void = {
	let s = set { ... };
	const src = "# example
[service \"network\"]
command = /usr/bin/dhcpcd -q eth0
restart = on-failure
restart_limit = 5
restart_delay = 1s
shutdown_timeout = 2s

[service \"ssh\"]
command = /usr/sbin/sshd -D
after = network
";
	parse_ok(&s, src);
	assert(s.count == 2);
	const net = &s.services[0];
	assert(bytes::equal(svc_name(net), strings::toutf8("network")));
	assert(bytes::equal(svc_arg(&s, net, 0), strings::toutf8("/usr/bin/dhcpcd")));
	assert(bytes::equal(svc_arg(&s, net, 1), strings::toutf8("-q")));
	assert(bytes::equal(svc_arg(&s, net, 2), strings::toutf8("eth0")));
	assert(net.restart == restart::on_failure);
	assert(net.restart_limit == 5);
	assert(net.restart_delay_ms == 1000);
	assert(net.shutdown_timeout_ms == 2000);
	const ssh = &s.services[1];
	assert(ssh.after_len == 1);
	assert(ssh.after[0] == 0);
};

@test fn parses_service_environment_and_oneshot_type() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"setup\"]\ncommand = /bin/setup\ntype = oneshot\nenv = HOME=/srv MODE=boot\n");
	const svc = &s.services[0];
	assert(svc.kind == service_kind::oneshot);
	assert(svc.envc == 2);
	assert(bytes::equal(svc_env(&s, svc, 0), strings::toutf8("HOME=/srv")));
	assert(bytes::equal(svc_env(&s, svc, 1), strings::toutf8("MODE=boot")));
};

@test fn defaults_are_applied() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/true\n");
	const svc = &s.services[0];
	assert(svc.restart == restart::always);
	assert(svc.restart_limit == 10);
	assert(svc.restart_delay_ms == 250);
	assert(svc.shutdown_timeout_ms == 5000);
	assert(svc.after_len == 0);
};

@test fn rejects_missing_command() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8("[service \"a\"]\nrestart = never\n")),
		1, "service has no command");
};

@test fn rejects_duplicate_name() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\n[service \"a\"]\ncommand = /bin/true\n")),
		3, "duplicate service name");
};

@test fn rejects_unknown_after_target() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\nafter = ghost\n")),
		1, "after names unknown service");
};

@test fn rejects_dependency_cycle() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\nafter = b\n[service \"b\"]\ncommand = /bin/true\nafter = a\n")),
		4, "after dependencies form a cycle");
};

@test fn rejects_bad_duration() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\nrestart_delay = soon\n")),
		3, "duration must be like 250ms or 5s");
};

@test fn rejects_setting_outside_section() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8("command = /bin/true\n")),
		1, "setting outside [service] section");
};

@test fn rejects_invalid_section_header() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8("[service a]\ncommand = /bin/true\n")),
		1, "invalid section header");
};

@test fn rejects_too_many_arguments() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/echo 1 2 3 4 5 6 7 8 9\n")),
		2, "too many arguments");
};

@test fn rejects_bad_environment_entries() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\nenv = NOT-VALID=yes\n")),
		3, "env must be NAME=VALUE");
};

@test fn rejects_unknown_service_type() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\ntype = daemon\n")),
		3, "type must be service or oneshot");
};

@test fn rejects_no_services() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8("# nothing here\n")),
		2, "no services defined");
};

@test fn records_unknown_key_as_warning() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/true\nfrobnicate = yes\n");
	assert(s.warning_count == 1);
	assert(s.warnings[0].line == 3);
};

@test fn orders_services_after_their_dependencies() void = {
	let s = set { ... };
	const src = "[service \"c\"]
command = /bin/true
after = a b
[service \"a\"]
command = /bin/true
[service \"b\"]
command = /bin/true
after = a
";
	parse_ok(&s, src);
	let order: [MAX_SERVICES]size = [0...];
	const n = start_order(&s, &order);
	assert(n == 3);
	assert(order[0] == 1);
	assert(order[1] == 2);
	assert(order[2] == 0);
};

@test fn parses_durations() void = {
	assert(parse_duration(strings::toutf8("250ms")) as i64 == 250);
	assert(parse_duration(strings::toutf8("5s")) as i64 == 5000);
	assert(parse_duration(strings::toutf8("750")) as i64 == 750);
	assert(parse_duration(strings::toutf8("abc")) is void);
	assert(parse_duration(strings::toutf8("")) is void);
};

@test fn command_accepts_double_quoted_argument() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/sh -c \"echo hello world\"\n");
	const svc = &s.services[0];
	assert(svc.argc == 3);
	assert(bytes::equal(svc_arg(&s, svc, 0), strings::toutf8("/bin/sh")));
	assert(bytes::equal(svc_arg(&s, svc, 1), strings::toutf8("-c")));
	assert(bytes::equal(svc_arg(&s, svc, 2), strings::toutf8("echo hello world")));
};

@test fn command_accepts_single_quoted_argument() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/echo 'a b  c'\n");
	const svc = &s.services[0];
	assert(svc.argc == 2);
	assert(bytes::equal(svc_arg(&s, svc, 1), strings::toutf8("a b  c")));
};

@test fn command_concatenates_quoted_and_bare_segments() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/echo pre\"mid dle\"'suf'\n");
	const svc = &s.services[0];
	assert(svc.argc == 2);
	assert(bytes::equal(svc_arg(&s, svc, 1), strings::toutf8("premid dlesuf")));
};

@test fn command_outside_backslash_escapes_one_byte() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/echo a\\ b\n");
	const svc = &s.services[0];
	assert(svc.argc == 2);
	assert(bytes::equal(svc_arg(&s, svc, 1), strings::toutf8("a b")));
};

@test fn command_double_quotes_keep_most_backslashes() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/echo \"a\\nb\\\"c\"\n");
	const svc = &s.services[0];
	assert(svc.argc == 2);
	assert(bytes::equal(svc_arg(&s, svc, 1), strings::toutf8("a\\nb\"c")));
};

@test fn command_accepts_empty_quoted_argument() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/echo \"\" x\n");
	const svc = &s.services[0];
	assert(svc.argc == 3);
	assert(len(svc_arg(&s, svc, 1)) == 0);
	assert(bytes::equal(svc_arg(&s, svc, 2), strings::toutf8("x")));
};

@test fn rejects_unterminated_double_quote() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/echo \"open\n")),
		2, "unterminated quote");
};

@test fn rejects_unterminated_single_quote() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/echo 'open\n")),
		2, "unterminated quote");
};

@test fn env_accepts_quoted_value_with_spaces() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/true\nenv = MSG=\"hello world\"\n");
	const svc = &s.services[0];
	assert(svc.envc == 1);
	assert(bytes::equal(svc_env(&s, svc, 0), strings::toutf8("MSG=hello world")));
};

@test fn env_rejects_unterminated_quote() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\nenv = MSG=\"hello\n")),
		3, "unterminated quote");
};

@test fn env_concatenation_still_validates_name() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/true\nenv = M\"S\"G=x\n");
	const svc = &s.services[0];
	assert(bytes::equal(svc_env(&s, svc, 0), strings::toutf8("MSG=x")));
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\nenv = N\"O\"T-VALID=yes\n")),
		3, "env must be NAME=VALUE");
};

@test fn notification_fd_defaults_to_zero() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/true\n");
	assert(s.services[0].notification_fd == 0);
};

@test fn parses_notification_fd() void = {
	let s = set { ... };
	parse_ok(&s, "[service \"a\"]\ncommand = /bin/true\nnotification-fd = 3\n");
	assert(s.services[0].notification_fd == 3);
};

@test fn rejects_low_notification_fd() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\nnotification-fd = 2\n")),
		3, "notification-fd must be 3 or higher");
};

@test fn rejects_non_numeric_notification_fd() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\nnotification-fd = stdio\n")),
		3, "notification-fd must be a number");
};

@test fn rejects_huge_notification_fd() void = {
	let s = set { ... };
	expect_diag(parse(&s, strings::toutf8(
		"[service \"a\"]\ncommand = /bin/true\nnotification-fd = 1025\n")),
		3, "notification-fd too large");
};
