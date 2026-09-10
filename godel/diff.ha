use bytes;

// Service identity deliberately includes argv: changing a command replaces it.
export fn argv_equal(
	a: *const set,
	aa: *const service,
	b: *const set,
	bb: *const service,
) bool = {
	if (aa.argc != bb.argc) return false;
	for (let i = 0z; i < aa.argc: size; i += 1) {
		if (!bytes::equal(svc_arg(a, aa, i), svc_arg(b, bb, i))) return false;
	};
	return true;
};

// Marks running services that may retain their process across a reload.
export fn match_running(
	next: *const set,
	old: *const set,
	runtimes: []runtime,
	indices: *[MAX_SERVICES]u8,
	matched: *[MAX_SERVICES]bool,
) void = {
	for (let i = 0z; i < next.count; i += 1) {
		for (let j = 0z; j < old.count; j += 1) {
			if (matched[j] || runtimes[j].state != state::up) continue;
			if (bytes::equal(svc_name(&next.services[i]),
					svc_name(&old.services[j]))
					&& argv_equal(next, &next.services[i], old, &old.services[j])) {
				indices[i] = j: u8;
				matched[j] = true;
				break;
			};
		};
	};
};
