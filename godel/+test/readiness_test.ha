use bytes;
use fmt;
use memio;
use strings;

fn rparse_ok(s: *set, src: str) void = {
	match (parse(s, strings::toutf8(src))) {
	case void => void;
	case let d: diag =>
		let buf: [128]u8 = [0...];
		let f = memio::fixed(buf);
		fmt::fprintf(&f, "unexpected diag at line {}: {}",
			d.line: i64, d.msg)!;
		abort(memio::string(&f)!);
	};
};

fn rfind(s: *set, name: str) size = {
	for (let i = 0z; i < s.count; i += 1) {
		if (bytes::equal(svc_name(&s.services[i]), strings::toutf8(name))) {
			return i;
		};
	};
	abort("service not found");
};

@test fn plain_ordering_satisfied_by_running_dependency() void = {
	let s = set { ... };
	rparse_ok(&s, "[service \"a\"]\ncommand = /bin/true\n[service \"b\"]\ncommand = /bin/true\nafter = a\n");
	let rts: [MAX_SERVICES]runtime = [new_runtime()...];
	rts[rfind(&s, "a")].pid = 42;
	const dep = &s.services[rfind(&s, "a")];
	assert(dep_satisfied(dep, &rts[rfind(&s, "a")]));
};

@test fn notified_dependency_requires_readiness() void = {
	let s = set { ... };
	rparse_ok(&s, "[service \"a\"]\ncommand = /bin/true\nnotification-fd = 3\n[service \"b\"]\ncommand = /bin/true\nafter = a\n");
	const ai = rfind(&s, "a");
	let rts: [MAX_SERVICES]runtime = [new_runtime()...];
	rts[ai].pid = 42;
	assert(!dep_satisfied(&s.services[ai], &rts[ai]));
	rts[ai].ready = true;
	assert(dep_satisfied(&s.services[ai], &rts[ai]));
};

@test fn completed_oneshot_dependency_satisfies_notified_gate() void = {
	let s = set { ... };
	rparse_ok(&s, "[service \"a\"]\ncommand = /bin/true\ntype = oneshot\nrestart = never\nnotification-fd = 3\n[service \"b\"]\ncommand = /bin/true\nafter = a\n");
	const ai = rfind(&s, "a");
	let rts: [MAX_SERVICES]runtime = [new_runtime()...];
	rts[ai].pid = 42;
	assert(!dep_satisfied(&s.services[ai], &rts[ai]));
	rts[ai].pid = 0;
	assert(!dep_satisfied(&s.services[ai], &rts[ai]));
	rts[ai].exited = true;
	rts[ai].last_status = 0;
	assert(dep_satisfied(&s.services[ai], &rts[ai]));
	rts[ai].last_status = 1;
	assert(!dep_satisfied(&s.services[ai], &rts[ai]));
};

@test fn ready_starts_holds_dependents_until_readiness() void = {
	let s = set { ... };
	rparse_ok(&s, "[service \"late\"]\ncommand = /bin/true\nnotification-fd = 3\n[service \"dep\"]\ncommand = /bin/true\nafter = late\n[service \"free\"]\ncommand = /bin/true\n");
	const li = rfind(&s, "late");
	let rts: [MAX_SERVICES]runtime = [new_runtime()...];
	rts[li].pid = 42;
	let order: [MAX_SERVICES]size = [0...];
	let n = ready_starts(&s, rts, &order);
	assert(n == 2);
	assert(order[0] == li);
	assert(order[1] == rfind(&s, "free"));
	rts[li].ready = true;
	n = ready_starts(&s, rts, &order);
	assert(n == 3);
	assert(order[1] == rfind(&s, "dep"));
	assert(order[2] == rfind(&s, "free"));
};

@test fn ready_starts_without_notification_matches_start_order() void = {
	let s = set { ... };
	rparse_ok(&s, "[service \"c\"]\ncommand = /bin/true\nafter = a b\n[service \"a\"]\ncommand = /bin/true\n[service \"b\"]\ncommand = /bin/true\nafter = a\n");
	let rts: [MAX_SERVICES]runtime = [new_runtime()...];
	let order: [MAX_SERVICES]size = [0...];
	let plain: [MAX_SERVICES]size = [0...];
	const n = ready_starts(&s, rts, &order);
	const m = start_order(&s, &plain);
	assert(n == m);
	assert(n == 3);
	for (let i = 0z; i < n; i += 1) {
		assert(order[i] == plain[i]);
	};
};

@test fn released_dependency_satisfies_gate() void = {
	let s = set { ... };
	rparse_ok(&s, "[service \"a\"]\ncommand = /bin/true\nnotification-fd = 3\n[service \"b\"]\ncommand = /bin/true\nafter = a\n");
	const ai = rfind(&s, "a");
	let rts: [MAX_SERVICES]runtime = [new_runtime()...];
	rts[ai].pid = 42;
	assert(!dep_satisfied(&s.services[ai], &rts[ai]));
	rts[ai].released = true;
	assert(dep_satisfied(&s.services[ai], &rts[ai]));
};

@test fn readiness_due_respects_deadline_and_state() void = {
	let s = set { ... };
	rparse_ok(&s, "[service \"a\"]\ncommand = /bin/true\nnotification-fd = 3\nreadiness_timeout = 2s\n");
	const ai = rfind(&s, "a");
	const cfg = &s.services[ai];
	let r = new_runtime();
	r.pid = 42;
	r.started_at = 1000;
	assert(!readiness_due(cfg, &r, 2999));
	assert(readiness_due(cfg, &r, 3000));
	r.ready = true;
	assert(!readiness_due(cfg, &r, 5000));
	r.ready = false;
	r.released = true;
	assert(!readiness_due(cfg, &r, 5000));
	r.released = false;
	r.pid = 0;
	assert(!readiness_due(cfg, &r, 5000));
};

@test fn readiness_due_requires_timeout_and_notification() void = {
	let s = set { ... };
	rparse_ok(&s, "[service \"plain\"]\ncommand = /bin/true\n[service \"notimeout\"]\ncommand = /bin/true\nnotification-fd = 3\n");
	const r = new_runtime();
	assert(!readiness_due(&s.services[rfind(&s, "plain")], &r, 1_000_000));
	assert(!readiness_due(&s.services[rfind(&s, "notimeout")], &r, 1_000_000));
};
